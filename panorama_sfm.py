#!/usr/bin/python3
"""
An example for running incremental SfM on 360 spherical panorama images.
Patched to fix memory corruption
"""

import argparse
import os
from collections.abc import Sequence
# SWITCHED: Using ProcessPoolExecutor to achieve full process/memory isolation
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, TypeVar, cast

import cv2
import numpy as np
import numpy.typing as npt
import PIL.ExifTags
import PIL.Image
from scipy.spatial.transform import Rotation
from tqdm import tqdm

import pycolmap
from pycolmap import logging

N = TypeVar("N", bound=int)
NDArrayNx2 = np.ndarray[tuple[N, Literal[2]], np.dtype[np.float64]]
NDArray3x1 = np.ndarray[tuple[Literal[3], Literal[1]], np.dtype[np.float64]]

@dataclass
class PanoRenderOptions:
    num_steps_yaw: int
    pitches_deg: Sequence[float]
    hfov_deg: float
    vfov_deg: float


PANO_RENDER_OPTIONS: dict[str, PanoRenderOptions] = {
    "overlapping": PanoRenderOptions(
        num_steps_yaw=4,
        pitches_deg=(-35.0, 0.0, 35.0),
        hfov_deg=90.0,
        vfov_deg=90.0,
    ),
    "non-overlapping": PanoRenderOptions(
        num_steps_yaw=4,
        pitches_deg=(0.0,),
        hfov_deg=90.0,
        vfov_deg=90.0,
    ),
}


def create_virtual_camera(
    pano_width: int,
    pano_height: int,
    hfov_deg: float,
    vfov_deg: float,
) -> pycolmap.Camera:
    """Create a virtual perspective camera."""
    image_width = int(pano_width * hfov_deg / 360)
    image_height = int(pano_height * vfov_deg / 180)
    focal = image_width / (2 * np.tan(np.deg2rad(hfov_deg) / 2))
    return pycolmap.Camera.create_from_model_id(
        camera_id=0,
        model=pycolmap.CameraModelId.SIMPLE_PINHOLE,
        focal_length=focal,
        width=image_width,
        height=image_height,
    )


def get_virtual_camera_rays(
    camera: pycolmap.Camera,
) -> npt.NDArray[np.floating]:
    size = (camera.height, camera.width)
    y, x = np.indices(size).astype(np.float32)
    
    xy: NDArrayNx2 = np.column_stack([x.ravel(), y.ravel()])
    xy += 0.5
    xy_norm: NDArrayNx2 = camera.cam_from_img(image_points=xy)
    rays = np.concatenate([xy_norm, np.ones_like(xy_norm[:, :1])], -1)
    rays /= np.linalg.norm(rays, axis=-1, keepdims=True)
    return rays


def spherical_img_from_cam(
    image_size: tuple[int, int], rays_in_cam: npt.NDArray[np.floating]
) -> npt.NDArray[np.floating]:
    """Project rays into a 360 panorama (spherical) image."""
    pano_width, pano_height = image_size
    if pano_width != pano_height * 2:
        raise ValueError("Only 360° panoramas are supported.")
    if rays_in_cam.ndim != 2 or rays_in_cam.shape[1] != 3:
        raise ValueError(f"{rays_in_cam.shape=} but expected (N,3).")
        
    r = rays_in_cam.T
    yaw = np.arctan2(r[0], r[2])
    pitch = -np.arctan2(r[1], np.linalg.norm(r[[0, 2]], axis=0))
    
    u = (1.0 + yaw / np.pi) / 2.0
    v = (1.0 - pitch * 2.0 / np.pi) / 2.0
    
    x_pixels = u * (pano_width - 1)
    y_pixels = v * (pano_height - 1)
    
    return np.stack([x_pixels, y_pixels], -1)


def get_virtual_rotations(
    num_steps_yaw: int, pitches_deg: Sequence[float]
) -> Sequence[npt.NDArray[np.floating]]:
    """Get the relative rotations of the virtual cameras w.r.t. the panorama."""
    cams_from_pano_r = []
    yaws = np.linspace(0, 360, num_steps_yaw, endpoint=False)
    for pitch_deg in pitches_deg:
        yaw_offset = (360 / num_steps_yaw / 2) if pitch_deg > 0 else 0
        for yaw_deg in yaws + yaw_offset:
            cam_from_pano_r = Rotation.from_euler(
                "XY", [-pitch_deg, -yaw_deg], degrees=True
            ).as_matrix()
            cams_from_pano_r.append(cam_from_pano_r)
    return cams_from_pano_r


def create_pano_rig_config(
    cams_from_pano_rotation: Sequence[npt.NDArray[np.floating]],
    ref_idx: int = 0,
) -> pycolmap.RigConfig:
    """Create a RigConfig for the given virtual rotations."""
    rig_cameras = []
    zero_translation = cast(NDArray3x1, np.zeros((3, 1), dtype=np.float64))
    for idx, cam_from_pano_rotation in enumerate(cams_from_pano_rotation):
        if idx == ref_idx:
            cam_from_rig = None
        else:
            cam_from_ref_rotation = (
                cam_from_pano_rotation @ cams_from_pano_rotation[ref_idx].T
            )
            cam_from_rig = pycolmap.Rigid3d(
                pycolmap.Rotation3d(cam_from_ref_rotation),
                zero_translation,
            )
        rig_cameras.append(
            pycolmap.RigConfigCamera(
                ref_sensor=idx == ref_idx,
                image_prefix=f"pano_camera{idx}/",
                cam_from_rig=cam_from_rig,
            )
        )
    return pycolmap.RigConfig(cameras=rig_cameras)


# Helper function moved globally to be picklable by ProcessPoolExecutor
def process_single_pano(
    pano_name: str,
    pano_image_dir: Path,
    output_image_dir: Path,
    mask_dir: Path,
    cams_from_pano_rotation: Sequence[npt.NDArray[np.floating]],
    cam_centers_in_pano: npt.NDArray[np.floating],
    image_prefixes: Sequence[str],
    pano_size: tuple[int, int],
    rays_in_cam: npt.NDArray[np.floating],
    camera_height: int,
    camera_width: int,
) -> None:
    pano_path = pano_image_dir / pano_name
    try:
        pano_pil_image = PIL.Image.open(pano_path)
    except PIL.Image.UnidentifiedImageError:
        return

    pano_exif = pano_pil_image.getexif()
    pano_image = np.asarray(pano_pil_image)
    gpsonly_exif = PIL.Image.Exif()
    gpsonly_exif[PIL.ExifTags.IFD.GPSInfo] = pano_exif.get_ifd(
        PIL.ExifTags.IFD.GPSInfo
    )

    pano_height, pano_width, *_ = pano_image.shape
    if pano_width != pano_height * 2:
        raise ValueError("Only 360° panoramas are supported.")

    if (pano_width, pano_height) != pano_size:
        raise ValueError("Panoramas of different sizes are not supported.")

    for cam_idx, cam_from_pano_r in enumerate(cams_from_pano_rotation):
        rays_in_pano = rays_in_cam @ cam_from_pano_r
        
        xy_in_pano = spherical_img_from_cam(pano_size, rays_in_pano)
        xy_in_pano = xy_in_pano.reshape(camera_height, camera_width, 2).astype(np.float32)
        
        x_coords = np.ascontiguousarray(xy_in_pano[..., 0] - 0.5)
        y_coords = np.ascontiguousarray(xy_in_pano[..., 1] - 0.5)
        
        image = cv2.remap(
            pano_image,
            x_coords,
            y_coords,
            cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_WRAP,
        )
        
        closest_camera_flat = np.argmax(rays_in_pano @ cam_centers_in_pano.T, -1)
        closest_camera = closest_camera_flat.reshape(camera_height, camera_width)
        
        mask = np.zeros((camera_height, camera_width), dtype=np.uint8)
        mask[closest_camera == cam_idx] = 255
        mask = np.ascontiguousarray(mask)

        image_name = image_prefixes[cam_idx] + pano_name
        mask_name = f"{image_name}.png"

        image_path = output_image_dir / image_name
        image_path.parent.mkdir(exist_ok=True, parents=True)
        PIL.Image.fromarray(image).save(image_path, exif=gpsonly_exif)

        mask_path = mask_dir / mask_name
        mask_path.parent.mkdir(exist_ok=True, parents=True)
        
        if not pycolmap.Bitmap.from_array(mask).write(mask_path):
            raise RuntimeError(f"Cannot write {mask_path}")


def render_perspective_images(
    pano_image_names: Sequence[str],
    pano_image_dir: Path,
    output_image_dir: Path,
    mask_dir: Path,
    render_options: PanoRenderOptions,
) -> pycolmap.RigConfig:
    cams_from_pano_rotation = get_virtual_rotations(
        num_steps_yaw=render_options.num_steps_yaw,
        pitches_deg=render_options.pitches_deg,
    )
    rig_config = create_pano_rig_config(cams_from_pano_rotation)
    image_prefixes = [cam.image_prefix for cam in rig_config.cameras]

    cam_centers_in_pano = np.einsum(
        "nij,i->nj", cams_from_pano_rotation, [0, 0, 1]
    )
    
    if not pano_image_names:
        return rig_config

    first_pano_path = pano_image_dir / pano_image_names[0]
    with PIL.Image.open(first_pano_path) as img:
        w, h = img.size
        
    main_thread_camera = create_virtual_camera(
        pano_width=w,
        pano_height=h,
        hfov_deg=render_options.hfov_deg,
        vfov_deg=render_options.vfov_deg,
    )
    
    camera_height = main_thread_camera.height
    camera_width = main_thread_camera.width
    pano_size = (w, h)
    rays_in_cam = get_virtual_camera_rays(main_thread_camera)

    num_panos = len(pano_image_names)
    # Using physical CPU cores safely for separate isolated processes
    max_workers = min(32, (os.cpu_count() or 2) - 1)

    with tqdm(total=num_panos) as pbar:
        with ProcessPoolExecutor(max_workers=max_workers) as process_pool:
            futures = [
                process_pool.submit(
                    process_single_pano,
                    pano_name,
                    pano_image_dir,
                    output_image_dir,
                    mask_dir,
                    cams_from_pano_rotation,
                    cam_centers_in_pano,
                    image_prefixes,
                    pano_size,
                    rays_in_cam,
                    camera_height,
                    camera_width,
                )
                for pano_name in pano_image_names
            ]
            for future in as_completed(futures):
                future.result()
                pbar.update(1)

    # Clean binding back on parent main thread execution
    # for rig_camera in rig_config.cameras:
    #     rig_camera.camera = main_thread_camera
    
    for idx, rig_camera in enumerate(rig_config.cameras):
        cam_copy = pycolmap.Camera.create_from_model_id(
            camera_id=idx,
            model=main_thread_camera.model,
            focal_length=main_thread_camera.focal_length_x, #copy focal length
            width=main_thread_camera.width,
            height=main_thread_camera.height,
        )
        rig_camera.camera = cam_copy

    return rig_config


def run(args: argparse.Namespace) -> None:
    pycolmap.set_random_seed(0)

    image_dir = args.output_path / "images"
    mask_dir = args.output_path / "masks"
    image_dir.mkdir(exist_ok=True, parents=True)
    mask_dir.mkdir(exist_ok=True, parents=True)

    database_path = args.output_path / "database.db"
    if database_path.exists():
        database_path.unlink()

    rec_path = args.output_path / "sparse"
    rec_path.mkdir(exist_ok=True, parents=True)

    pano_image_dir = args.input_image_path
    pano_image_names = sorted(
        p.relative_to(pano_image_dir).as_posix()
        for p in pano_image_dir.rglob("*")
        if not p.is_dir()
    )
    logging.info(f"Found {len(pano_image_names)} images in {pano_image_dir}.")

    rig_config = render_perspective_images(
        pano_image_names,
        pano_image_dir,
        image_dir,
        mask_dir,
        PANO_RENDER_OPTIONS[args.pano_render_type],
    )
    
    extraction_opts = pycolmap.FeatureExtractionOptions()
    extraction_opts.use_gpu = True
    extraction_opts.gpu_index = "0"
    
    reader_opts = pycolmap.ImageReaderOptions(mask_path=mask_dir)
    reader_opts.camera_model = "SIMPLE_PINHOLE"
    
    first_pano_path = pano_image_dir / pano_image_names[0]
    with PIL.Image.open(first_pano_path) as img:
        w, h = img.size
    render_opts = PANO_RENDER_OPTIONS[args.pano_render_type]
    img_w = int(w * render_opts.hfov_deg / 360)
    focal_prior = img_w / (2 * np.tan(np.deg2rad(render_opts.hfov_deg) / 2))
    
    reader_opts.camera_params = f"{focal_prior}, {img_w / 2.0}, {img_w / 2.0}"

    pycolmap.extract_features(
        database_path,
        image_dir,
        reader_options=reader_opts,
        camera_mode=pycolmap.CameraMode.PER_FOLDER,
        extraction_options=extraction_opts
    )
    
    print(f"Match mode: {args.matcher}")

    with pycolmap.Database.open(database_path) as db:
        pycolmap.apply_rig_config([rig_config], db)

    matching_options = pycolmap.FeatureMatchingOptions()
    matching_options.rig_verification = True
    matching_options.use_gpu = True
    matching_options.gpu_index = "0"
    matching_options.skip_image_pairs_in_same_frame = True
    
    if args.matcher == "sequential":
        pycolmap.match_sequential(
            database_path,
            pairing_options=pycolmap.SequentialPairingOptions(loop_detection=True),
            matching_options=matching_options,
        )
    elif args.matcher == "exhaustive":
        pycolmap.match_exhaustive(database_path, matching_options=matching_options)
    elif args.matcher == "vocabtree":
        pycolmap.match_vocabtree(database_path, matching_options=matching_options)
    elif args.matcher == "spatial":
        pycolmap.match_spatial(database_path, matching_options=matching_options)
    else:
        logging.fatal(f"Unknown matcher: {args.matcher}")

    glomap_opts = pycolmap.GlobalPipelineOptions()
    recs = pycolmap.global_mapping(
        database_path=database_path,
        image_path=image_dir,
        output_path=rec_path,
        options=glomap_opts
    )
    print("Done!")
    # for idx, rec in recs.items():
    #     logging.info(f"#{idx} {rec.summary()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input_image_path", type=Path, required=True)
    parser.add_argument("--output_path", type=Path, required=True)
    parser.add_argument(
        "--matcher",
        default="sequential",
        choices=["sequential", "exhaustive", "vocabtree", "spatial"],
    )
    parser.add_argument(
        "--pano_render_type",
        default="overlapping",
        choices=list(PANO_RENDER_OPTIONS.keys()),
    )
    run(parser.parse_args())