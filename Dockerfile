#COLMAP
FROM nvidia/cuda:12.6.2-devel-ubuntu24.04 AS builder

ARG COMPUTE_LEVEL=7.5
ENV COMPUTE_VAR=${COMPUTE_LEVEL}
ENV TORCH_CUDA_ARCH_LIST=${COMPUTE_LEVEL}
RUN export COMPUTE_VAR_CLEAN=$(echo "${COMPUTE_LEVEL}" | sed 's/\.//g')

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
    cmake \
    build-essential \
    libgl1-mesa-dev \
    libegl1-mesa-dev \
    libgoogle-glog-dev \
    libatlas-base-dev \
    libsuitesparse-dev \
    libsqlite3-dev \
    libboost-graph-dev \
    libboost-program-options-dev \
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

RUN git clone --depth=1 --recurse-submodules --shallow-submodules https://github.com/ceres-solver/ceres-solver.git /tmp/ceres-src && \
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
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      # 75;80;86;89;90
      -DCMAKE_CUDA_ARCHITECTURES="$COMPUTE_VAR_CLEAN" \
      -DGUI_ENABLED=OFF \
      -DCUDA_ENABLED=ON \
      -DOPENGL_ENABLED=OFF \
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
FROM nvidia/cuda:12.6.2-runtime-ubuntu24.04

USER root

ARG COMPUTE_LEVEL=7.5
ENV COMPUTE_VAR=${COMPUTE_LEVEL}
ENV TORCH_CUDA_ARCH_LIST=${COMPUTE_LEVEL}
RUN export COMPUTE_VAR_CLEAN=$(echo "${COMPUTE_LEVEL}" | sed 's/\.//g')

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
    libglvnd-dev \
    libgomp1 \
    libgflags-dev \
    libcgal-dev \
    libsuitesparse-dev \
    libgoogle-glog-dev \
    libgtest-dev \
    wget \
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

RUN pip3 install --no-cache-dir --break-system-packages \
    torch \
    torchvision \
    --extra-index-url https://download.pytorch.org/whl/cu126 \
    --index-url https://download.pytorch.org/whl/cu126

RUN git clone --depth=1 --recurse-submodules --shallow-submodules https://github.com/nerfstudio-project/gsplat.git /tmp/gsplat && \
    cd /tmp/gsplat && \
    FORCE_CMAKE=1 TORCH_CUDA_ARCH_LIST="$COMPUTE_VAR" MAX_JOBS=4 FORCE_CUDA=1 pip3 install --no-cache-dir --break-system-packages --no-build-isolation . && \
    rm -rf /tmp/gsplat

RUN git clone --depth=1 https://github.com/nerfstudio-project/nerfstudio.git /tmp/nerfstudio && \
    cd /tmp/nerfstudio && \
    pip3 install --no-cache-dir --break-system-packages --ignore-installed . && \
    rm -rf /tmp/nerfstudio

RUN git clone --depth=1 https://github.com/KevinXu02/splatfacto-w.git /tmp/splatfacto-w && \
    cd /tmp/splatfacto-w && \
    pip3 install --no-cache-dir --break-system-packages . && \
    rm -rf /tmp/splatfacto-w

RUN wget https://developer.download.nvidia.com/compute/cudss/0.5.0/local_installers/cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb \
    && dpkg -i cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb \
    && cp /var/cudss-local-repo-ubuntu2204-0.5.0/cudss-*-keyring.gpg /usr/share/keyrings/

RUN find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "libcudss0-cuda-12_*.deb" -exec dpkg -i {} + \
    && find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "libcudss0-dev-cuda-12_*.deb" -exec dpkg -i {} + \
    && find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "libcudss0-static-cuda-12_*.deb" -exec dpkg -i {} + \
    && find /var/cudss-local-repo-ubuntu2204-0.5.0/ -name "cudss-cuda-12_*.deb" -exec dpkg -i {} + \
    && rm cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb

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
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /gluemap && git clone --depth=1 --recurse-submodules --shallow-submodules https://github.com/colmap/gluemap.git /gluemap && \
    cd /gluemap && \
    export Boost_INCLUDE_DIR=/usr/include && \
    pip3 install --no-cache-dir --break-system-packages -e . --config-settings=cmake.args="-DBoost_INCLUDE_DIR=/usr/include"

RUN pip install "pillow<11.0.0" --force-reinstall
RUN pip install --no-cache-dir --break-system-packages "cmake>=3.15"
RUN pip install --no-cache-dir --break-system-packages setuptools wheel scikit-build-core transformers accelerate safetensors huggingface_hub

ENV colmap_DIR=/usr/local/share/colmap

RUN ns-install-cli && pip3 cache purge

RUN echo "alias e='exit'" >> /root/.bashrc && \
    echo "alias cls='clear'" >> /root/.bashrc && \
    echo "export QT_QPA_PLATFORM=offscreen" >> /root/.bashrc && \
    echo "export MAX_JOBS=$(($(nproc) / 2))" >> /root/.bashrc

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libglew2.2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV TORCH_CUDA_ARCH_LIST=${COMPUTE_LEVEL}

ENV QT_QPA_PLATFORM=offscreen
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

RUN wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/panorama_sfm.py && \
    chmod +x /usr/local/bin/panorama_sfm.py &&
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/zx_process_video && \
    chmod +x /usr/local/bin/zx_process_video &&
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/zx_process_video_360 && \
    chmod +x /usr/local/bin/zx_process_video_360 &&
    wget -P /usr/local/bin/ https://raw.githubusercontent.com/ZXMushroom63/sfm-docker/refs/heads/main/zx_download_assets && \
    chmod +x /usr/local/bin/zx_download_assets

USER root