@echo off
wsl docker run --gpus all -it --user root --rm ^
    -v "/mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' | tr -d '\r')/sfm-docker:/NERFSTUDIO" ^
    -v "/mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' | tr -d '\r')/sfm-docker/.cache:/root/.cache" ^
    -v /tmp/.X11-unix:/tmp/.X11-unix ^
    -v /mnt/wslg:/mnt/wslg ^
    -v /fast ^
    -v /usr/lib/wsl:/usr/lib/wsl ^
    -e LD_LIBRARY_PATH=/usr/lib/wsl/lib ^
    -e DISPLAY=$DISPLAY ^
    -e WAYLAND_DISPLAY=$WAYLAND_DISPLAY ^
    -e XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR ^
    -e QT_QPA_PLATFORM=wayland ^
    -e GALLIUM_DRIVER=d3d12 ^
    -e MESA_LOADER_DRIVER_OVERRIDE=d3d12 ^
    -e MESA_D3D12_DEFAULT_ADAPTER_NAME=dxgkrnl ^
    -e Q_XCB_GLX_INTEGRATION=none ^
    -e QT_STYLE_OVERRIDE=Fusion ^
    -e QT_XCB_FORCE_SOFTWARE_OPENGL=1 ^
    -e WA_WCG_DISABLE_BLIT_OPTIMIZATION=1 ^
    --device /dev/dxg ^
    --shm-size=12gb ^
    -p 7007:7007 ^
    nerfstudio-colmap4 bash