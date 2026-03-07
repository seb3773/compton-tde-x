#!/bin/bash
# Install dependencies for compton-tde on Debian/Ubuntu-based systems

echo "Installing build dependencies for compton-tde..."

# Detect package manager
if command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        cmake \
        pkg-config \
        libx11-dev \
        libxcomposite-dev \
        libxdamage-dev \
        libxrender-dev \
        libxfixes-dev \
        libxrandr-dev \
        libxinerama-dev \
        libxext-dev \
        libgl-dev \
        libconfig-dev \
        libdbus-1-dev \
        libpcre2-dev

    echo ""
    echo "Dependencies installed successfully!"
    echo "You can now build compton-tde with:"
    echo "  cmake . && make compton-tde"
else
    echo "Error: apt-get not found. This script only supports Debian/Ubuntu-based systems."
    echo "Please install the following packages manually:"
    echo "  - X11 development libraries (libX11, libXcomposite, libXdamage, libXrender, libXfixes, libXrandr, libXinerama, libXext)"
    echo "  - OpenGL development libraries"
    echo "  - libconfig-dev"
    echo "  - libdbus-1-dev"
    echo "  - libpcre2-dev"
    echo "  - cmake, pkg-config, build-essential"
    exit 1
fi
