@echo off
set /p COMPUTE="Specify GPU Compute Level (7.5, 8.6, 8.9, 9.0): "
@echo on
docker build --build-arg COMPUTE_LEVEL=%COMPUTE% --progress=plain -t nerfstudio-colmap4:latest .
pause