#!/bin/sh
# Draws the static Top Shelf images with the extension's own drawing code (see
# scripts/top-shelf/main.swift). Needs only the Swift toolchain.
#   sh tvos/scripts/make-top-shelf.sh                       the static images, into the catalog
#   sh tvos/scripts/make-top-shelf.sh --slides <dir>        the carousel slides, for review
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -O -swift-version 5 KhajistanTV/Core/*.swift TopShelf/ShelfCanvas.swift TopShelf/ShelfArt.swift \
  scripts/top-shelf/main.swift -o .build/make-top-shelf
PIGEON=KhajistanTV/Resources/Assets.xcassets/Pigeon.imageset/pigeon.png
if [ "${1:-}" = "--slides" ]; then
  .build/make-top-shelf "$PIGEON" --slides .. "${2:?usage: make-top-shelf.sh --slides <dir>}"
else
  .build/make-top-shelf "$PIGEON" KhajistanTV/Resources/Assets.xcassets
fi
