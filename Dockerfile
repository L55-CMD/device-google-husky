FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    android-sdk-libsparse-utils \
    bash \
    ca-certificates \
    cpio \
    curl \
    e2fsprogs \
    fakeroot \
    git \
    lz4 \
    openssh-client \
    python3 \
    sudo \
    unzip \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
