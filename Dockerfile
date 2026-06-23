#COLMAP
FROM nvidia/cuda:12.6.2-devel-ubuntu24.04 AS builder

ARG COMPUTE_LEVEL=7.5
ENV COMPUTE_VAR=${COMPUTE_LEVEL}
ENV TORCH_CUDA_ARCH_LIST=${COMPUTE_LEVEL}
RUN echo $(echo "${COMPUTE_LEVEL}" | sed 's/\.//g')

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# just directly install .deb of 0.5.0, more reliable than messing with apt repos
RUN wget https://developer.download.nvidia.com/compute/cudss/0.5.0/local_installers/cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb \
    && dpkg -i cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb \
    && cp /var/cudss-local-repo-ubuntu2204-0.5.0/cudss-*-keyring.gpg /usr/share/keyrings/

RUN find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "libcudss0-cuda-12_*.deb" -exec dpkg -i {} + \
    && find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "libcudss0-dev-cuda-12_*.deb" -exec dpkg -i {} + \
    && find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "libcudss0-static-cuda-12_*.deb" -exec dpkg -i {} + \
    && find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "cudss-cuda-12_*.deb" -exec dpkg -i {} + \
    && rm cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb

# RUN wget https://developer.download.nvidia.com/compute/cudss/0.5.0/local_installers/cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb \
#     && dpkg -i cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb \
#     && cp /var/cudss-local-repo-ubuntu2204-0.5.0/cudss-*-keyring.gpg /usr/share/keyrings/ \
#     && rm cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb

# RUN wget https://developer.download.nvidia.com/compute/cudss/0.3.0/local_installers/cudss-local-repo-ubuntu2204-0.3.0_0.3.0-1_amd64.deb \
#     && dpkg -i cudss-local-repo-ubuntu2204-0.3.0_0.3.0-1_amd64.deb \
#     && cp /var/cudss-local-repo-ubuntu2204-0.3.0/cudss-*-keyring.gpg /usr/share/keyrings/ \
#     && rm cudss-local-repo-ubuntu2204-0.3.0_0.3.0-1_amd64.deb

RUN apt-get update && apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y universe && \
    apt-get update && apt-get install -y --no-install-recommends \
    wget \
    git \
    curl \
    cmake \
    build-essential \
    libegl1-mesa-dev \
    libgoogle-glog-dev \
    libatlas-base-dev \
    libsuitesparse-dev \
    libsqlite3-dev \
    libboost-graph-dev \
    libboost-program-options-dev \
    libboost-system-dev \
    libeigen3-dev \
    libopenimageio-dev \
    libopenexr-dev \
    openimageio-tools \
    libgflags-dev \
    libcgal-dev \
    libmetis-dev \
    libgtest-dev \
    libgmock-dev \
    libopencv-dev \
    libglew-dev \
    libblas-dev \
    liblapack-dev \
    qt6-base-dev \
    qt6-svg-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    && rm -rf /var/lib/apt/lists/*

RUN cd /usr/lib/x86_64-linux-gnu && \
    ln -sf libcudss/12/libcudss.so.0.* libcudss.so.0 && \
    ln -sf libcudss.so.0 libcudss.so

RUN git clone --depth=1 https://github.com/facebookresearch/faiss.git /tmp/faiss-src && \
    cd /tmp/faiss-src && \
    mkdir build && cd build && \
    cmake .. -DFAISS_ENABLE_GPU=OFF -DBUILD_TESTING=OFF -DFAISS_ENABLE_PYTHON=OFF -DFAISS_ENABLE_TESTING=OFF -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) faiss && \
    make install && \
    rm -rf /tmp/faiss-src

RUN git clone --recurse-submodules https://github.com/ceres-solver/ceres-solver.git /tmp/ceres-src && \
    cd /tmp/ceres-src && \
    git checkout master && \
    mkdir build && cd build && \
    cmake .. -DBUILD_TESTING=OFF -DUSE_CUDA=ON -DCUDA=ON -DBUILD_CUDA=ON -DBUILD_EXAMPLES=OFF \
     -DCUDSS=ON \
     -DCUDSS_INCLUDE_DIR=/usr/include \
     -DCUDSS_LIBRARY=/usr/lib/x86_64-linux-gnu/libcudss/12/libcudss.so \
     -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/ceres-src

RUN git clone --depth=1 https://github.com/colmap/colmap.git /tmp/colmap-src && \
    cd /tmp/colmap-src && \
    # checkout latest tagged release. change to 'main' to checkout the latest arch
    git checkout $(git describe --tags $(git rev-list --tags --max-count=1)) && \
    mkdir build && cd build && \
    export QT_QPA_PLATFORM=offscreen && \
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      # 75;80;86;89;90
      -DCMAKE_CUDA_ARCHITECTURES="$(echo "${COMPUTE_LEVEL}" | sed 's/\.//g')" \
      -DGUI_ENABLED=ON \
      -DCUDA_ENABLED=ON \
      -DOPENGL_ENABLED=ON \
      -DTESTS_ENABLED=OFF \
      -DLIFT_WITH_CUDA=ON \
      -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++ \
      -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
      -DEigen3_DIR=/usr/lib/cmake/eigen3 \
      -DOpenImageIO_DIR=/usr/lib/cmake/OpenImageIO \
      -DCeres_DIR=/usr/local/lib/cmake/Ceres && \
    make -j$(nproc) && \
    make install && \
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip python3-dev ninja-build && \
    rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED && \
    cd /tmp/colmap-src && \
    pip3 install --no-cache-dir --break-system-packages ninja ruff pybind11 scikit-build-core && \
    pip3 wheel . --wheel-dir=/tmp/colmap-wheels && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/colmap-src

# RT
FROM nvidia/cuda:12.6.2-devel-ubuntu24.04

USER root

ARG COMPUTE_LEVEL=7.5
ENV COMPUTE_VAR=${COMPUTE_LEVEL}
ENV TORCH_CUDA_ARCH_LIST=${COMPUTE_LEVEL}

ENV DEBIAN_FRONTEND=noninteractive
ENV CUDA_HOME=/usr/local/cuda

RUN echo "deb http://archive.ubuntu.com/ubuntu/ jammy main universe restricted multiverse" > /etc/apt/sources.list.d/jammy-fallback.list
RUN echo "Package: *\nPin: release n=jammy\nPin-Priority: 100" > /etc/apt/preferences.d/jammy-pin

RUN apt-get update && apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y universe && \
    apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-dev \
    git \
    build-essential \
    libgoogle-glog0v5 \
    libatlas3-base \
    libsuitesparse-dev \
    libsqlite3-0 \
    libboost-graph1.74.0 \
    libboost-program-options1.74.0 \
    libopenimageio2.2 \
    libopenexr25 \
    libgflags2.2 \
    libmetis5 \
    libgl1 \
    libegl1 \
    libgl1-mesa-glx \
    libglvnd-dev \
    libgomp1 \
    libgflags-dev \
    libcgal-dev \
    libsuitesparse-dev \
    libgoogle-glog-dev \
    libgtest-dev \
    wget \
    curl \
    mesa-utils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/colmap /usr/local/bin/colmap
COPY --from=builder /usr/local/lib/ /usr/local/lib/
COPY --from=builder /usr/local/include/ /usr/local/include/
COPY --from=builder /usr/local/cuda/ /usr/local/cuda/
COPY --from=builder /usr/local/share/colmap /usr/local/share/colmap

COPY --from=builder /usr/lib/x86_64-linux-gnu/libcudss/12/libcudss.so.0.* /usr/local/lib/

COPY --from=builder /tmp/colmap-wheels /tmp/colmap-wheels
RUN rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED
RUN pip3 install /tmp/colmap-wheels/*.whl && rm -rf /tmp/colmap-wheels

RUN cd /usr/local/lib && \
    ln -sf libcudss.so.0.* libcudss.so.0 && \
    ln -sf libcudss.so.0 libcudss.so && \
    ldconfig

ENV PATH=/usr/local/cuda/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/lib:$LD_LIBRARY_PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://developer.download.nvidia.com/compute/cudss/0.5.0/local_installers/cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb \
    && dpkg -i cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb \
    && cp /var/cudss-local-repo-ubuntu2204-0.5.0/cudss-*-keyring.gpg /usr/share/keyrings/

RUN find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "libcudss0-cuda-12_*.deb" -exec dpkg -i {} + \
    && find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "libcudss0-dev-cuda-12_*.deb" -exec dpkg -i {} + \
    && find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "libcudss0-static-cuda-12_*.deb" -exec dpkg -i {} + \
    && find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "cudss-cuda-12_*.deb" -exec dpkg -i {} + \
    && rm cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb

RUN pip3 install --no-cache-dir --break-system-packages \
    torch \
    torchvision \
    --extra-index-url https://download.pytorch.org/whl/cu126 \
    --index-url https://download.pytorch.org/whl/cu126

ENV PATH=/usr/local/cuda/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/lib:$LD_LIBRARY_PATH
ENV CUDA_HOME=/usr/local/cuda

RUN git clone --recurse-submodules https://github.com/nerfstudio-project/gsplat.git /tmp/gsplat && \
    cd /tmp/gsplat && \
    export CUDA_HOME=/usr/local/cuda && export PATH=$CUDA_HOME/bin:$PATH && export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH && \
    FORCE_CMAKE=1 TORCH_CUDA_ARCH_LIST="$COMPUTE_VAR" MAX_JOBS=4 FORCE_CUDA=1 pip3 install --no-cache-dir --break-system-packages --no-build-isolation . && \
    rm -rf /tmp/gsplat

RUN git clone --depth=1 https://github.com/nerfstudio-project/nerfstudio.git /tmp/nerfstudio && \
    cd /tmp/nerfstudio && \
    pip3 install --no-cache-dir --break-system-packages --ignore-installed --no-deps . && \
    rm -rf /tmp/nerfstudio

RUN git clone --depth=1 https://github.com/KevinXu02/splatfacto-w.git /tmp/splatfacto-w && \
    cd /tmp/splatfacto-w && \
    pip3 install --no-cache-dir --break-system-packages --no-deps . && \
    rm -rf /tmp/splatfacto-w

RUN apt-get update && apt-get install -y --no-install-recommends \
    libmetis-dev \
    libeigen3-dev \
    libboost-all-dev \
    libatlas-base-dev \
    libatlas3-base \
    libgtest-dev \
    libgmock-dev \
    libopencv-dev \
    libglew-dev \
    libblas-dev \
    liblapack-dev \
    libgl1 \
    libegl1 \
    libglvnd-dev \
    libgomp1 \
    libopenimageio-dev \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

ENV colmap_DIR=/usr/local/share/colmap
ENV Ceres_DIR=/usr/local/lib/cmake/Ceres
COPY --from=builder /usr/local/lib/cmake/Ceres /usr/local/lib/cmake/Ceres

RUN python3 -m venv /opt/gluemap-env --system-site-packages

RUN pip3 uninstall -y numpy numpy
RUN pip3 install --no-cache-dir --break-system-packages "numpy<2.0.0" "huggingface_hub[cli]"

RUN mkdir -p /install/gluemap && git clone --recurse-submodules https://github.com/colmap/gluemap.git /install/gluemap && \
    cd /install/gluemap && \
    export Boost_INCLUDE_DIR=/usr/include && \
    /opt/gluemap-env/bin/pip install --no-cache-dir --upgrade pip setuptools wheel scikit-build-core && \
    /opt/gluemap-env/bin/pip install --no-cache-dir -e . \
    --config-settings=cmake.args="-DBoost_INCLUDE_DIR=/usr/include" \
    --config-settings=cmake.args="-DCeres_DIR=/usr/local/lib/cmake/Ceres" \
    --extra-index-url https://download.pytorch.org/whl/cu126 && \
    cd /install/gluemap/thirdparty/doppelgangers-plusplus/dust3r/croco/models/curope && \
    /opt/gluemap-env/bin/python setup.py build_ext --inplace
    

# RUN mkdir -p /gluemap && git clone --depth=1 --recurse-submodules --shallow-submodules https://github.com/colmap/gluemap.git /gluemap && \
#     cd /gluemap && \
#     export Boost_INCLUDE_DIR=/usr/include && \
#     pip3 install --no-cache-dir --break-system-packages -e . --config-settings=cmake.args="-DBoost_INCLUDE_DIR=/usr/include"

RUN pip3 uninstall -y numpy numpy
RUN pip3 install --no-cache-dir --break-system-packages --ignore-installed "cmake>=3.15" "appdirs>=1.4" "numpy<2.0.0" \
    "av>=9.2.0" \
    "comet_ml>=3.33.8" \
    "cryptography>=38" \
    "tyro>=0.9.8" \
    "gdown>=4.6.0" \
    "ninja>=1.10" \
    "h5py>=2.9.0" \
    "imageio>=2.21.1" \
    'importlib-metadata>=6.0.0; python_version < "3.10"' \
    "ipywidgets>=7.6" \
    "jaxtyping>=0.2.15" \
    "jupyterlab>=3.3.4" \
    "matplotlib>=3.6.0" \
    "mediapy>=1.1.0" \
    "msgpack>=1.0.4" \
    "msgpack_numpy>=0.4.8" \
    "nerfacc==0.5.2" \
    "open3d>=0.16.0" \
    "opencv-python-headless==4.10.0.84" \
    "pillow<11.0.0" \
    "plotly>=5.7.0" \
    "protobuf<=5!=3.20.0" \
    "pymeshlab>=2022.2.post2; platform_machine != 'arm64' and platform_machine != 'aarch64'" \
    "pymeshlab<2023.12.post2; sys_platform == 'win32' and platform_machine != 'arm64' and platform_machine != 'aarch64'" \
    "pyngrok>=5.1.0" \
    "python-socketio>=5.7.1" \
    "pyquaternion>=0.9.9" \
    "rawpy>=0.18.1; platform_machine != 'arm64'" \
    "newrawpy>=1.0.0b0; platform_machine == 'arm64'" \
    "requests" \
    "rich>=12.5.1" \
    "scikit-image>=0.19.3" \
    "splines==0.3.0" \
    "tensorboard>=2.13.0" \
    "typing_extensions>=4.4.0" \
    "viser==1.0.0" \
    "nuscenes-devkit>=1.1.1" \
    "wandb>=0.13.3" \
    "xatlas" \
    "trimesh>=3.20.2" \
    "timm==0.6.7" \
    "pytorch-msssim" \
    "pathos" \
    "packaging" \
    "fpsample" \
    "tensorly" \
    "torchmetrics[image]>=1.0.1"

# RUN pip install --no-cache-dir --break-system-packages setuptools wheel scikit-build-core transformers accelerate safetensors huggingface_hub

RUN ns-install-cli && pip3 cache purge

RUN echo "alias e='exit'" >> /root/.bashrc && \
    echo "alias cls='clear'" >> /root/.bashrc && \
    echo "alias gluemap='gluemap-demo'" >> /root/.bashrc && \
    echo "export MAX_JOBS=$(($(nproc) / 2))" >> /root/.bashrc && \
    echo "mkdir -p /NERFSTUDIO/gluemap_checkpoints && ln -s /NERFSTUDIO/gluemap_checkpoints /install/gluemap/checkpoints" >> /root/.bashrc && \
    echo "$DOCKER_AUTOEXEC" >> /root/.bashrc && \
    echo "export TORCH_CUDNN_V8_API_ENABLED=1" >> /root/.bashrc && \
    echo "export TORCH_ALLOW_TF32_CUBLAS_OVERRIDE=1" >> /root/.bashrc && \
    echo "mkdir -p /root/.cache/torchinductor" >> /root/.bashrc && \
    echo "mkdir -p /root/.cache/triton" >> /root/.bashrc && \
    echo "export TORCHINDUCTOR_CACHE_DIR=/root/.cache/torchinductor" >> /root/.bashrc && \
    echo "export TRITON_CACHE_DIR=/root/.cache/triton" >> /root/.bashrc && \
    echo "export TORCHINDUCTOR_FX_GRAPH_CACHE=1" >> /root/.bashrc && \
    echo "export TORCHINDUCTOR_AUTOGRAD_CACHE=1" >> /root/.bashrc && \
    echo "export TORCHINDUCTOR_MAX_AUTOTUNE=1" >> /root/.bashrc && \
    echo "export TORCH_CUDNN_SDPA_ENABLED=1" >> /root/.bashrc && \
    echo "export TORCH_FLASH_SDPA_ENABLED=1" >> /root/.bashrc && \
    echo "export TORCH_MEM_EFFICIENT_SDPA_ENABLED=1" >> /root/.bashrc && \
    echo "export TORCH_MATH_SDPA_ENABLED=1" >> /root/.bashrc && \
    echo "cls; nvcc --version | grep 'Cuda compilation tools'; colmap --version; python3 -c \"import sys, torch; print(f\\\"Python: {sys.version.split()[0]} | PyTorch: {torch.__version__} | Backend: {'cuda' if torch.cuda.is_available() else 'mps' if torch.backends.mps.is_available() else 'cpu'}\\\")\"; echo ''; echo 'Welcome to SfM-docker!'; echo ''; cd /NERFSTUDIO/" >> /root/.bashrc
    

#add-apt-repository -y ppa:kisak/kisak-mesa; apt update; apt-get install -y libgl1-mesa-dri libglx-mesa0 mesa-vulkan-drivers
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libglew2.2 \
    libqt6openglwidgets6t64 \
    libqt6svg6 \
    qt6-wayland \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV TORCH_CUDA_ARCH_LIST=${COMPUTE_LEVEL}

ENV QT_QPA_PLATFORM=offscreen
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV TORCH_FORCE_WEIGHTS_ONLY_LOAD=0
ENV TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1

RUN wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/utils/panorama_sfm.py && \
    chmod +x /usr/local/bin/panorama_sfm.py && \
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/utils/zx_process_video && \
    chmod +x /usr/local/bin/zx_process_video && \
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/utils/zx_process_video_360 && \
    chmod +x /usr/local/bin/zx_process_video_360 && \
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/utils/zx_download_assets && \
    chmod +x /usr/local/bin/zx_download_assets && \
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/utils/zx_splat && \
    chmod +x /usr/local/bin/zx_splat && \
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/utils/zx_glue_video && \
    chmod +x /usr/local/bin/zx_glue_video && \
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/utils/gluemap-demo && \
    chmod +x /usr/local/bin/gluemap-demo && \
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/utils/zx_gluemap_setup && \
    chmod +x /usr/local/bin/zx_gluemap_setup && \
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/utils/zx_find_blurry.py && \
    chmod +x /usr/local/bin/zx_find_blurry.py

USER root