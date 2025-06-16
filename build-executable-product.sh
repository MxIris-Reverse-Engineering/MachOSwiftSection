#!/bin/bash

set -e  # Exit on any error

echo "Building x86_64 architecture..."
swift build -c release --arch x86_64 --product swift-section --enable-experimental-prebuilts

echo "Building arm64 architecture..."
swift build -c release --arch arm64 --product swift-section --enable-experimental-prebuilts

# Create Products directory
if [ ! -d "./Products" ]; then
    mkdir -p Products
fi

# Check if both binaries exist before creating universal binary
X86_BINARY=".build/x86_64-apple-macosx/release/swift-section"
ARM64_BINARY=".build/arm64-apple-macosx/release/swift-section"

if [ ! -f "$X86_BINARY" ]; then
    echo "Error: x86_64 binary not found at $X86_BINARY"
    exit 1
fi

if [ ! -f "$ARM64_BINARY" ]; then
    echo "Error: arm64 binary not found at $ARM64_BINARY"
    exit 1
fi

echo "Creating universal binary..."
lipo -create \
    "$X86_BINARY" \
    "$ARM64_BINARY" \
    -output ./Products/swift-section

echo "Universal binary created successfully:"
lipo -info ./Products/swift-section
file ./Products/swift-section
