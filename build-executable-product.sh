#!/bin/bash

set -e  # Exit on any error

# Builds a universal `swift-section` (x86_64 + arm64) and signs it ad hoc.
#
# SwiftPM 6.4 made the Swift Build engine the default. Its products land in
# `<scratch>/out/Products/<Configuration>` — one directory shared by every
# architecture — instead of the native engine's `.build/<triple>/<configuration>`.
# Each architecture therefore gets its own scratch path, and the binary
# location is asked from SwiftPM (`--show-bin-path`) rather than assumed, so
# the script works under both engines and with either toolchain.
PRODUCT_NAME="swift-section"
ARCHITECTURES=("x86_64" "arm64")
SLICE_PATHS=()

for ARCHITECTURE in "${ARCHITECTURES[@]}"; do
    SCRATCH_PATH=".build/universal-${ARCHITECTURE}"
    echo "Building ${ARCHITECTURE} architecture..."
    swift build -c release --arch "${ARCHITECTURE}" --product "${PRODUCT_NAME}" --scratch-path "${SCRATCH_PATH}"

    BINARY_DIRECTORY="$(swift build -c release --arch "${ARCHITECTURE}" --product "${PRODUCT_NAME}" --scratch-path "${SCRATCH_PATH}" --show-bin-path)"
    SLICE_PATH="${BINARY_DIRECTORY}/${PRODUCT_NAME}"
    if [ ! -f "${SLICE_PATH}" ]; then
        echo "Error: ${ARCHITECTURE} binary not found at ${SLICE_PATH}"
        exit 1
    fi
    SLICE_PATHS+=("${SLICE_PATH}")
done

# Create Products directory
mkdir -p Products

echo "Creating universal binary..."
lipo -create "${SLICE_PATHS[@]}" -output "./Products/${PRODUCT_NAME}"

echo "Signing universal binary..."
codesign --force --sign - "./Products/${PRODUCT_NAME}"

echo "Universal binary created successfully:"
lipo -info "./Products/${PRODUCT_NAME}"
file "./Products/${PRODUCT_NAME}"
