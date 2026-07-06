@echo off
docker run --gpus all -it --user root --rm ^
    -v "%USERPROFILE%\sfm-docker:/NERFSTUDIO/" ^
    -v "%USERPROFILE%\sfm-docker\.cache:/root/.cache/" ^
    -p 7007:7007 ^
    -v /fast ^
    --shm-size=12gb ^
    -e QT_QPA_PLATFORM=offscreen ^
    nerfstudio-colmap4 bash