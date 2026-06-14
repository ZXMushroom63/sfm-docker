# All-in-one SfM Docker Image
(not tested on linux yet)

Clone the repo, use the `BUILD_IMAGE.bat` or `build_image.sh` to build the image. It is large and will take a long time, especially on building `gsplat` and `pytorch`.

You will have to manually specify your GPUs compute level, as otherwise the Docker build will take years to complete.

Once build, I'd recommend using `LAUNCH_CLI.bat` / `launch_cli.sh` to start Docker to automatically handle shared directories and GPU Passthrough.
- Maps `~/sfm-docker` to `/NERFSTUDIO`
- Maps `~/sfm-docker/.cache` to `/NERFSTUDIO/.cache`

Contains:
- Latest stable release of Ceres Solver (including GPU acceleration with cuDSS)
- Latest stable release of COLMAP with GPU acceleration and GLOMAP
- Latest gsplat
- Latest nerfstudio
- The splatfacto-w gaussian splat model
- The GLUEMAP proof of concept (`gluemap_demo`)
- A patched SfM script for 360 panorama with COLMAP, without the memory corruption issues!
- A couple other utility scripts

System Requirements:
- 20GB Storage (you can get away with less)
- nvidia GPU, 8GB VRAM (you can get away with less)
- 16GB RAM (pricey, you can get away with less)
- An internet connection for the build (necessary)
- CUDA 12.6 installed on the host, along with nvidia drivers

## Installation
- Install [CUDA 12.6](https://developer.nvidia.com/cuda-12-6-0-download-archive)
- Go to your user folder (`%USERPROFILE%` or `/home/username/`)
- Clone this repo: `git clone --depth=1 https://github.com/ZXMushroom63/sfm-docker.git`
- Have docker/podman running
- Use either `build_image.sh` or `BUILD_IMAGE.bat` to start building the image
  - This will take ages. Ideally, close background programs to prevent OOM crashes
- Use the `LAUNCH_CLI.bat` or `launch_cli.sh` scripts to start the docker image with the correct config
- `cd NERFSTUDIO` to enter the shared folder!

## Basic tutorials on my util scripts
### Standard video processing (eg: phone camera)
- Put the video inside the shared folder.
- Use `zx_process_video my_video.mp4 tracking/`
  - This will use GLOMAP + sequential matching to track the frames
- Then use `zx_splat tracking/ tracking/splat/` or an `ns-train splatfacto` to turn the tracked data into a splat. (or a nerf or whatever)
### 360 video
- Put the video inside the shared folder. It must be a 360 equirectangular video, with an aspect ratio of 2:1
- Use `zx_process_video_360 360_video.mp4 tracking/ [optional: frame stepping] [optional: extra flags]`
  - Default for frame stepping is `2`
- Then use `zx_splat tracking/ tracking/splat/` or an `ns-train splatfacto` to turn the tracked data into a splat. (or a nerf or whatever)
### GLUEMAP
- Notice: You need at least 12GB of VRAM for this to be useful. This crashed my 2080 Ti.
- Put the video inside the shared folder.
- Use `zx_glue_video the_video.mp4 tracking/ [optional: frame stepping]`
  - Default for frame stepping is `2`
- Then use `zx_splat tracking/ tracking/splat/` or an `ns-train splatfacto` to turn the tracked data into a splat. (or a nerf or whatever)