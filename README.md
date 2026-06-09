# All-in-one SfM Docker Image
(not tested on linux yet)

Clone the repo, use the `BUILD_IMAGE.bat` or `build_image.sh` to build the image. It is large and will take a long time, especially on building `gsplat` and `pytorch`.

You will have to manually specify your GPUs compute level, as otherwise the Docker build will take years to complete.

Once build, I'd recommend using `LAUNCH_CLI.bat` / `launch_cli.sh` to start Docker to automatically handle shared directories and GPU Passthrough.
- Maps `~/NERFSTUDIO` to `/NERFSTUDIO`
- Maps `~/NERFSTUDIO/.cache` to `/NERFSTUDIO/.cache`

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