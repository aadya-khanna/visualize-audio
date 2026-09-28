#!/bin/bash
# Compiles scripts/palette_selftest.swift against the real Visualizer sources
# and runs it. See that file's header for what the output means.
#   ./scripts/palette_selftest.sh              # synthetic covers
#   ./scripts/palette_selftest.sh cover.jpg    # a real cover, by path
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)/palette_selftest"
swiftc -O \
  Sources/VisualizeAudio/Visualizer/ColorMapping.swift \
  Sources/VisualizeAudio/Visualizer/AlbumPalette.swift \
  Sources/VisualizeAudio/Media/NowPlaying.swift \
  Sources/VisualizeAudio/Media/MediaRemoteBridge.swift \
  scripts/palette_selftest.swift \
  -o "$out"
"$out" "$@"
