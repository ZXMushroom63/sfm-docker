#!/bin/sh

echo -n "Specify GPU Compute Level (7.5, 8.6, 8.9, 9.0): "
read COMPUTE

docker build --build-arg COMPUTE_LEVEL="$COMPUTE" --progress=plain -t nerfstudio-colmap4:latest .