FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        abootimg \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        cmake \
        cpio \
        curl \
        debootstrap \
        device-tree-compiler \
        dosfstools \
        file \
        genimage \
        git \
        libtool \
        lz4 \
        make \
        mtools \
        patch \
        pigz \
        pkg-config \
        qemu-user-static \
        squashfs-tools \
        u-boot-tools \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
