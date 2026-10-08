#!/bin/bash

set -e  # Exit on any error

# Builds a universal `swift-section` (x86_64 + arm64) and signs it ad hoc.
#
# How the two slices get built depends on SwiftPM's default build engine, and
# the two engines fail in opposite ways once macro plugins (MemberwiseInit,
# FrameworkToolbox) are in the graph:
#
# - Swift Build, the default from SwiftPM 6.4: a separate `--arch x86_64` build
#   on an arm64 Mac never builds the macro plugins for the host ("Build input
#   file cannot be found: …/MemberwiseInitMacros"). One build with both
#   `--arch` flags does, and links the universal binary itself.
# - The native engine, SwiftPM 6.3 and earlier: a build with both `--arch`
#   flags goes through XCBuild, which drops the macro plugin targets ("missing
#   target with GUID 'PACKAGE-TARGET:MemberwiseInitMacros'"). Separate builds
#   work, and lipo joins them.
#
# Each build gets its own scratch path, and the binary location is asked from
# SwiftPM (`--show-bin-path`) rather than assumed: the engines put it in
# different places.
PRODUCT_NAME="swift-section"
SWIFT_VERSION_NUMBERS="$(swift --version 2>&1 | sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1 \2/p' | head -n 1)"
read -r SWIFT_MAJOR_VERSION SWIFT_MINOR_VERSION <<< "${SWIFT_VERSION_NUMBERS}"
if [ -z "${SWIFT_MAJOR_VERSION}" ] || [ -z "${SWIFT_MINOR_VERSION}" ]; then
    echo "Error: could not read the Swift version from 'swift --version'"
    exit 1
fi

swift package update

# Builds with the given arguments and prints the path of the resulting binary.
# The build's own output goes to stderr so that only the path is captured.
build_product() {
    local binary_directory
    swift build -c release --product "${PRODUCT_NAME}" "$@" >&2 || return 1
    binary_directory="$(swift build -c release --product "${PRODUCT_NAME}" "$@" --show-bin-path)" || return 1
    echo "${binary_directory}/${PRODUCT_NAME}"
}

mkdir -p Products

if [ "${SWIFT_MAJOR_VERSION}" -gt 6 ] || { [ "${SWIFT_MAJOR_VERSION}" -eq 6 ] && [ "${SWIFT_MINOR_VERSION}" -ge 4 ]; }; then
    echo "Building arm64 + x86_64 in one Swift Build invocation..."
    UNIVERSAL_BINARY_PATH="$(build_product --arch arm64 --arch x86_64 --scratch-path .build/universal)"
    if [ ! -f "${UNIVERSAL_BINARY_PATH}" ]; then
        echo "Error: universal binary not found at ${UNIVERSAL_BINARY_PATH}"
        exit 1
    fi
    cp "${UNIVERSAL_BINARY_PATH}" "./Products/${PRODUCT_NAME}"
else
    SLICE_PATHS=()
    for ARCHITECTURE in x86_64 arm64; do
        echo "Building ${ARCHITECTURE} architecture..."
        SLICE_PATH="$(build_product --arch "${ARCHITECTURE}" --scratch-path ".build/universal-${ARCHITECTURE}")"
        if [ ! -f "${SLICE_PATH}" ]; then
            echo "Error: ${ARCHITECTURE} binary not found at ${SLICE_PATH}"
            exit 1
        fi
        SLICE_PATHS+=("${SLICE_PATH}")
    done
    echo "Creating universal binary..."
    lipo -create "${SLICE_PATHS[@]}" -output "./Products/${PRODUCT_NAME}"
fi

# One architecture per `-verify_arch`: Xcode 27's lipo takes a second
# architecture name for a second input file and refuses the command.
for ARCHITECTURE in arm64 x86_64; do
    if ! lipo "./Products/${PRODUCT_NAME}" -verify_arch "${ARCHITECTURE}"; then
        echo "Error: ./Products/${PRODUCT_NAME} lacks ${ARCHITECTURE}:"
        lipo -info "./Products/${PRODUCT_NAME}"
        exit 1
    fi
done

echo "Signing universal binary..."
codesign --force --sign - "./Products/${PRODUCT_NAME}"

echo "Universal binary created successfully:"
lipo -info "./Products/${PRODUCT_NAME}"
file "./Products/${PRODUCT_NAME}"
