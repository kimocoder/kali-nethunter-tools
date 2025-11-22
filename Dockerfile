FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set up build environment variables
ENV ANDROID_NDK_VERSION=r23
ENV ANDROID_NDK_HOME=/opt/android-ndk
ENV PATH="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin:${PATH}"

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    cmake \
    ninja-build \
    python3 \
    python3-pip \
    wget \
    curl \
    git \
    unzip \
    bison \
    flex \
    gperf \
    texinfo \
    help2man \
    gawk \
    libtool-bin \
    libncurses5-dev \
    libssl-dev \
    libelf-dev \
    bc \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Install Python build tools
RUN pip3 install --no-cache-dir meson ninja

# Download and install Android NDK
RUN mkdir -p /opt && \
    cd /opt && \
    wget -q https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip && \
    unzip -q android-ndk-${ANDROID_NDK_VERSION}-linux.zip && \
    mv android-ndk-${ANDROID_NDK_VERSION} android-ndk && \
    rm android-ndk-${ANDROID_NDK_VERSION}-linux.zip

# Create workspace directory
WORKDIR /workspace

# Copy build system files
COPY . /workspace/

# Set up build environment
RUN chmod +x build.sh scripts/*.sh

# Default command
CMD ["/bin/bash"]
