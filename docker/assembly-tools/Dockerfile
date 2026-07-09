FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        abootimg \
        ca-certificates \
        cpio \
        debootstrap \
        device-tree-compiler \
        dosfstools \
        file \
        genimage \
        git \
        lz4 \
        mtools \
        pigz \
        qemu-user-static \
        squashfs-tools \
        u-boot-tools \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
