#!/bin/bash

# Configuration
PACKAGE_NAME="compton-tde"
PACKAGE_VERSION="X"          # Version in package filename
DEB_VERSION="4.0"            # Version in control file (must start with digit)
ARCH=$(dpkg --print-architecture)
MAINTAINER="seb3773 <seb3773@github.com>"
DESCRIPTION="Optimized compton compositor for Trinity Desktop"
BUILD_DIR="package_build"

# Detect Trinity version from parent directory (e.g., tdebase-trinity-14.1.1)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TDE_VERSION=$(echo "$SCRIPT_DIR" | grep -oP 'trinity-\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")

# Package name format: compton-tde_<version>_tde<trinity_version>_<arch>.deb
DEB_NAME="${PACKAGE_NAME}_${PACKAGE_VERSION}_tde${TDE_VERSION}_${ARCH}.deb"

# Source directory (where compton-tde binary is built)
SOURCE_BUILD_DIR="$SCRIPT_DIR"

echo "Creating .deb package for $PACKAGE_NAME..."
echo "  Trinity version: $TDE_VERSION"
echo "  Architecture: $ARCH"

# Cleanup previous build
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR/opt/trinity/bin
mkdir -p $BUILD_DIR/DEBIAN

# Copy executable
echo "Copying binary..."
if [ -f "$SOURCE_BUILD_DIR/compton-tde" ]; then
    cp "$SOURCE_BUILD_DIR/compton-tde" "$BUILD_DIR/opt/trinity/bin/"
    chmod 755 "$BUILD_DIR/opt/trinity/bin/compton-tde"
    
    # Strip is already done by build process optionally, but valid to do here again if needed.
    # checking if sstrip exists
    if command -v sstrip >/dev/null 2>&1; then
        echo "Applying sstrip..."
        sstrip "$BUILD_DIR/opt/trinity/bin/compton-tde"
    else
        echo "sstrip not found, using strip..."
        strip --strip-all "$BUILD_DIR/opt/trinity/bin/compton-tde"
    fi
else
    echo "Error: compton-tde binary not found in $SOURCE_BUILD_DIR. Please run 'make compton-tde' first."
    exit 1
fi

# Create control file
echo "Creating control file..."
cat <<EOF > $BUILD_DIR/DEBIAN/control
Package: $PACKAGE_NAME
Version: $DEB_VERSION
Section: x11
Priority: optional
Architecture: $ARCH
Depends: libx11-6, libxcomposite1, libxdamage1, libxfixes3, libxrender1, libconfig9 | libconfig11, libpcre2-8-0, libdbus-1-3
Maintainer: $MAINTAINER
Description: $DESCRIPTION
 High performance GL/XRender compositor for TDE.
 Standalone optimized build.
EOF

# Build package
echo "Building package..."
dpkg-deb --build $BUILD_DIR $DEB_NAME

echo "Success! Package created: $DEB_NAME"
ls -lh $DEB_NAME
