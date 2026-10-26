#!/usr/bin/env bash
# make_ref.sh -- regenera ref/: el upscan y la salida TMDS del hito 1 (commit
# 20936e6 de main, sin cambios de RTL respecto de tnCartWonder) con los modulos
# renombrados a *_ORIG, para que el banco compare la version nueva con la
# original en la misma simulacion. Se ejecuta desde cualquier sitio del repo
# con un git que entienda el worktree (Git Bash en Windows).
set -euo pipefail
HITO1=20936e6
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
mkdir -p ref
git show "$HITO1:fpga/src/peripheral/video/video_upscan.sv" \
  | sed -E 's/\b(VIDEO_UPSCAN(_STRETCH_BUFFER|_BUFFER)?)\b/\1_ORIG/g' > ref/video_upscan_orig.sv
git show "$HITO1:fpga/src/board/rev1/board_rev1_tmds.sv" \
  | sed -E 's/\b(BOARD_REV1_TMDS_OUT(_DELAY)?)\b/\1_ORIG/g' > ref/board_rev1_tmds_orig.sv
# huella de lo que se compara: el fichero original entero (antes del renombrado)
{
  echo "# origen: commit $HITO1, sha256 del fichero original (git show) y de la copia renombrada"
  for f in fpga/src/peripheral/video/video_upscan.sv fpga/src/board/rev1/board_rev1_tmds.sv; do
    echo "$(git show "$HITO1:$f" | sha256sum | cut -d' ' -f1)  $HITO1:$f"
  done
  sha256sum ref/video_upscan_orig.sv ref/board_rev1_tmds_orig.sv
} > ref/SHA256SUMS
cat ref/SHA256SUMS
