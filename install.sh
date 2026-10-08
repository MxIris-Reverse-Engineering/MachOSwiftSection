#!/bin/bash

set -e  # Exit on any error

# Builds `swift-section` with build-executable-product.sh and installs the
# resulting binary on this machine.
#
#     ./install.sh [install-directory]
#
# The install directory defaults to /usr/local/bin, which macOS puts on PATH
# through /etc/paths. sudo is used only when that directory is not writable.
PRODUCT_NAME="swift-section"
PACKAGE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIRECTORY="${1:-/usr/local/bin}"

# A relative install directory means relative to where the script was invoked,
# so it is made absolute before the build changes the working directory.
case "${INSTALL_DIRECTORY}" in
    /*) ;;
    *) INSTALL_DIRECTORY="${PWD}/${INSTALL_DIRECTORY}" ;;
esac
INSTALL_DIRECTORY="${INSTALL_DIRECTORY%/}"
INSTALL_PATH="${INSTALL_DIRECTORY}/${PRODUCT_NAME}"

# build-executable-product.sh works relative to the current directory.
cd "${PACKAGE_DIRECTORY}"
./build-executable-product.sh

PRODUCT_PATH="${PACKAGE_DIRECTORY}/Products/${PRODUCT_NAME}"
if [ ! -f "${PRODUCT_PATH}" ]; then
    echo "Error: ${PRODUCT_PATH} not found after the build"
    exit 1
fi

PRIVILEGE_COMMAND=()
if ! mkdir -p "${INSTALL_DIRECTORY}" 2>/dev/null || [ ! -w "${INSTALL_DIRECTORY}" ]; then
    echo "${INSTALL_DIRECTORY} is not writable; installing with sudo..."
    PRIVILEGE_COMMAND=(sudo)
fi

# `install` writes a temporary file and renames it over the target, so an
# existing binary is replaced by a new file rather than overwritten in place:
# overwriting a signed binary in place gets the new one killed on launch.
"${PRIVILEGE_COMMAND[@]}" mkdir -p "${INSTALL_DIRECTORY}"
"${PRIVILEGE_COMMAND[@]}" install -m 0755 "${PRODUCT_PATH}" "${INSTALL_PATH}"

echo "Installed ${INSTALL_PATH}, version $("${INSTALL_PATH}" --version)"

# Another `swift-section` earlier on PATH — typically Homebrew's in
# /opt/homebrew/bin — would keep running instead of the one just installed.
RESOLVED_PATH="$(command -v "${PRODUCT_NAME}" || true)"
if [ -z "${RESOLVED_PATH}" ]; then
    echo "Warning: ${INSTALL_DIRECTORY} is not on PATH; run ${INSTALL_PATH} directly or add the directory to PATH."
elif [ "${RESOLVED_PATH}" != "${INSTALL_PATH}" ]; then
    echo "Warning: '${PRODUCT_NAME}' on PATH resolves to ${RESOLVED_PATH}, which shadows ${INSTALL_PATH}."
    echo "         Remove that copy (for Homebrew: brew uninstall ${PRODUCT_NAME}) or put ${INSTALL_DIRECTORY} earlier on PATH."
fi
