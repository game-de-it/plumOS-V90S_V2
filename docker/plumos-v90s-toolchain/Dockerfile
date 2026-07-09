FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PLUMOS_TARGET=aarch64-linux-gnu
ENV CC=gcc
ENV CXX=g++
ENV AR=ar
ENV RANLIB=ranlib
ENV STRIP=strip
ENV PKG_CONFIG_ALLOW_CROSS=1

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    abootimg \
    autoconf \
    automake \
    bash \
    bc \
    binutils \
    bison \
    build-essential \
    ca-certificates \
    cmake \
    cpio \
    curl \
    debootstrap \
    device-tree-compiler \
    dosfstools \
    e2fsprogs \
    fdisk \
    file \
    flex \
    gawk \
    genimage \
    gettext \
    git \
    jq \
    libasound2-dev \
    libegl-dev \
    libfreetype6-dev \
    libgles-dev \
    libpipewire-0.3-dev \
    libpulse-dev \
    libsdl2-dev \
    libtool \
    libudev-dev \
    lz4 \
    make \
    meson \
    mtools \
    ninja-build \
    patch \
    parted \
    pigz \
    pkg-config \
    python3 \
    python3-pip \
    qemu-user-static \
    rsync \
    squashfs-tools \
    tar \
    u-boot-tools \
    unzip \
    wget \
    xz-utils \
    zip \
    zlib1g-dev \
    zstd \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /workspace /opt/plumos-v90s/cache \
  && chmod 0777 /workspace /opt/plumos-v90s/cache

WORKDIR /workspace

CMD ["/bin/bash"]
