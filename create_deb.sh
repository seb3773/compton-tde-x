#!/bin/bash

# Configuration
PACKAGE_NAME="compton-tde"
VERSION="1.0"
ARCH=$(dpkg --print-architecture)
MAINTAINER="seb3773 <seb3773@github.com>"
DESCRIPTION="Optimized compton compositor for Trinity Desktop"
BUILD_DIR="package_build"
DEB_NAME="${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"

# Paths
SOURCE_BUILD_DIR="../../build/twin/compton-tde"

echo "Creating .deb package for $PACKAGE_NAME..."

# Cleanup previous build
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR/opt/trinity/bin
mkdir -p $BUILD_DIR/DEBIAN

# Copy executable
echo "Copying binary..."
if [ -f "$SOURCE_BUILD_DIR/compton-tde" ]; then
    cp "$SOURCE_BUILD_DIR/compton-tde" "$BUILD_DIR/opt/trinity/bin/"
    chmod 755 "$BUILD_DIR/opt/trinity/bin/compton-tde"
    
    # Apply sstrip
    echo "Applying sstrip..."
    sstrip "$BUILD_DIR/opt/trinity/bin/compton-tde"
else
    echo "Error: compton-tde binary not found in $SOURCE_BUILD_DIR"
    exit 1
fi

# Create control file
echo "Creating control file..."
cat <<EOF > $BUILD_DIR/DEBIAN/control
Package: $PACKAGE_NAME
Version: $VERSION
Section: x11
Priority: optional
Architecture: $ARCH
Depends: tdebase-trinity, libx11-6, libxcomposite1, libxdamage1, libxfixes3, libxrender1, libconfig11
Maintainer: $MAINTAINER
Description: $DESCRIPTION
 High performance GL/XRender compositor for TDE.
 Compiled with -O3 -ffast-math -flto.
EOF

# Build package
echo "Building package..."
dpkg-deb --build $BUILD_DIR $DEB_NAME

echo "Success! Package created: $DEB_NAME"
ls -lh $DEB_NAME
