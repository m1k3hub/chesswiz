#!/bin/sh
# Regenerate the Staunton piece meshes (src/tk/gl_piece_data.h), the sprite
# PNGs (img/pieces_3d) and, with PREVIEW=dir, lineup/knight preview renders.
#   sh tools/blender-pieces/regen.sh         # header + sprites
#   PREVIEW=tests/tmp-app/blender-pieces sh tools/blender-pieces/regen.sh
# Then: find src -name 'tk_glboard*.o' -delete && make -C src
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
blender=${BLENDER:-blender}
set -- --header "$root/src/tk/gl_piece_data.h" --sprites "$root/img/pieces_3d" --samples "${SAMPLES:-128}"
[ -n "$PREVIEW" ] && set -- "$@" --preview "$PREVIEW"
"$blender" -b --factory-startup --python "$here/pieces.py" -- "$@"
