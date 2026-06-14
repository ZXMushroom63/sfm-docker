#!/bin/sh
docker run --gpus all -it --user root --rm \
  -v "$HOME/sfm-docker:/NERFSTUDIO/" \
  -v "$HOME/sfm-docker/.cache:/root/.cache/" \
  -p 7007:7007 \
  --shm-size=12gb \
  nerfstudio-colmap4 bash