#COLMAP
FROM nvidia/cuda:12.6.2-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://developer.download.nvidia.com/compute/cudss/0.5.0/local_installers/cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb \
    && dpkg -i cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb \
    && cp /var/cudss-local-repo-ubuntu2204-0.5.0/cudss-*-keyring.gpg /usr/share/keyrings/ \
    && rm cudss-local-repo-ubuntu2204-0.5.0_0.5.0-1_amd64.deb

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    git \
    cmake \
    build-essential \
    libgl1-mesa-dev \
    libegl1-mesa-dev \
    libgoogle-glog-dev \
    libatlas-base-dev \
    libsuitesparse-dev \
    libfaiss-dev \
    libsqlite3-dev \
    libboost-graph-dev \
    libboost-program-options-dev \
    libeigen3-dev \
    libopenimageio-dev \
    libopenexr-dev \
    libcudss0-dev-cuda-12 \
    cudss-cuda-12 \
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

RUN git clone https://github.com/colmap/colmap.git /tmp/colmap-src && \
    cd /tmp/colmap-src && \
    # checkout latest tagged release. change to 'main' to checkout the latest arch
    git checkout $(git describe --tags $(git rev-list --tags --max-count=1)) && \
    mkdir build && cd build && \
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      # 75;80;86;89;90
      -DCMAKE_CUDA_ARCHITECTURES="75" \
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
    cd /tmp/colmap-src && \
    pip3 install ninja ruff pybind11 scikit-build-core && \
    pip3 wheel . --wheel-dir=/tmp/colmap-wheels && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/colmap-src

# RT
FROM nvidia/cuda:12.6.2-runtime-ubuntu22.04

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV CUDA_HOME=/usr/local/cuda

RUN apt-get update && apt-get install -y --no-install-recommends \
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
    libopencv-core4.5d \
    libgl1 \
    libegl1 \
    libglvnd-dev \
    libgomp1 \
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
RUN pip3 install /tmp/colmap-wheels/*.whl && rm -rf /tmp/colmap-wheels

RUN cd /usr/local/lib && \
    ln -sf libcudss.so.0.* libcudss.so.0 && \
    ln -sf libcudss.so.0 libcudss.so && \
    ldconfig

ENV PATH=/usr/local/cuda/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/lib:$LD_LIBRARY_PATH

RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel
RUN pip3 install --no-cache-dir \
    torch \
    torchvision \
    --extra-index-url https://download.pytorch.org/whl/cu126 \
    --index-url https://download.pytorch.org/whl/cu126

RUN git clone --recurse-submodules https://github.com/nerfstudio-project/gsplat.git /tmp/gsplat && \
    cd /tmp/gsplat && \
    FORCE_CMAKE=1 TORCH_CUDA_ARCH_LIST="7.5" MAX_JOBS=4 FORCE_CUDA=1 pip3 install --no-cache-dir --no-build-isolation . && \
    rm -rf /tmp/gsplat

RUN git clone https://github.com/nerfstudio-project/nerfstudio.git /tmp/nerfstudio && \
    cd /tmp/nerfstudio && \
    pip3 install --no-cache-dir . && \
    rm -rf /tmp/nerfstudio

RUN git clone https://github.com/KevinXu02/splatfacto-w.git /tmp/splatfacto-w && \
    cd /tmp/splatfacto-w && \
    pip3 install --no-cache-dir . && \
    rm -rf /tmp/splatfacto-w

RUN git clone https://github.com/colmap/gluemap.git /tmp/gluemap && \
    cd /tmp/gluemap && \
    pip3 install --no-cache-dir . && \
    rm -rf /tmp/gluemap

RUN pip install "pillow<11.0.0" --force-reinstall
RUN pip install --no-cache-dir "cmake>=3.15"
RUN pip install --no-cache-dir setuptools wheel scikit-build-core transformers accelerate safetensors huggingface_hub

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

ENV TORCH_CUDA_ARCH_LIST="7.5"

ENV QT_QPA_PLATFORM=offscreen
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

RUN wget -P /usr/local/bin/ https://raw.githubusercontent.com/colmap/colmap/refs/heads/main/python/examples/panorama_sfm.py && \
    sed -i '1s|^|#!/usr/bin/python3\n|' /usr/local/bin/panorama_sfm.py && \
    chmod +x /usr/local/bin/panorama_sfm.py

USER root