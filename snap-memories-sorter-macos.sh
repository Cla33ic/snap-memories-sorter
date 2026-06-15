#!/bin/bash
#
# snap-memories-sorter-macos.sh — Rebuild Snapchat memories into two sorted archives (macOS).
#
# What it does:
#   1. Asks you (via a native macOS dialog) to pick:
#        - the folder that holds your Snapchat export ZIP files
#        - a destination folder for the sorted output
#   2. Extracts every *.zip from the chosen folder into a temporary working
#      directory (automatically deleted when the script finishes).
#   3. For every "<prefix>-main.<ext>" memory it finds:
#        - copies the raw file into   <dest>/Originals/<Year>/<Month>/   (untouched)
#        - writes the "as seen in Snapchat" version into <dest>/Merged/<Year>/<Month>/
#          (overlay burned on top for photos AND videos; plain copy if no overlay)
#
# Output:  <dest>/{Originals,Merged}/YYYY/MM/
#
# Requirements:
#   - macOS (uses AppleScript folder pickers)
#   - ffmpeg in PATH  (install with:  brew install ffmpeg)
#
# Usage:  chmod +x snap-memories-sorter-macos.sh && ./snap-memories-sorter-macos.sh

set -u

# ---- settings (rename the two output folders here if you like) -----------
SUB_ORIG="Originals"     # raw -main files only
SUB_MERGED="Merged"      # overlays composited in
MAX_PARALLEL=3           # video re-encodes are heavy; raise for photo-heavy sets

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- native macOS folder picker -----------------------------------------
choose_folder() {  # $1 = prompt shown in the dialog
  osascript -e "POSIX path of (choose folder with prompt \"$1\")" 2>/dev/null
}

echo "A dialog will ask for the folder that contains your Snapchat ZIP files..."
ZIPDIR="$(choose_folder "Select the folder that contains your Snapchat export ZIP files")"
[ -z "$ZIPDIR" ] && { echo "No source folder selected. Aborting." >&2; exit 1; }
ZIPDIR="${ZIPDIR%/}"

echo "Now pick where the sorted memories should be saved..."
BASE="$(choose_folder "Select the destination folder (Originals & Merged are created inside)")"
[ -z "$BASE" ] && { echo "No destination folder selected. Aborting." >&2; exit 1; }
BASE="${BASE%/}"

ORIG="$BASE/$SUB_ORIG"
MERGED="$BASE/$SUB_MERGED"
mkdir -p "$ORIG" "$MERGED"

# ---- temporary work dir (auto-removed on exit) --------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/snap-merged.XXXXXX")" || {
  echo "Could not create a temporary working directory." >&2; exit 1; }
MEM="$WORK/memories"
LIST=""
cleanup() { rm -rf "$WORK"; [ -n "$LIST" ] && rm -f "$LIST"; }
trap cleanup EXIT

# ---- locate ffmpeg -------------------------------------------------------
FFMPEG=""
if command -v ffmpeg >/dev/null 2>&1; then FFMPEG="$(command -v ffmpeg)"
elif [ -x "$SCRIPT_DIR/ffmpeg" ]; then FFMPEG="$SCRIPT_DIR/ffmpeg"; fi
if [ -z "$FFMPEG" ]; then
  echo "ffmpeg not found. Install it:  brew install ffmpeg" >&2
  exit 1
fi

echo
echo "Zips in:  $ZIPDIR"
echo "Work dir: $WORK   (temporary — deleted when done)"
echo "Output:   $BASE/{$SUB_ORIG,$SUB_MERGED}/YYYY/MM"
echo "ffmpeg:   $FFMPEG"
echo

# ---- 1. extract all zips from the chosen folder -------------------------
n=0
for z in "$ZIPDIR"/*.zip; do
  [ -f "$z" ] || continue   # guard against no-match glob
  echo "extracting $(basename "$z") ..."
  unzip -oq "$z" -d "$WORK" \
    || { echo "Failed to extract $(basename "$z") (corrupt or incomplete download?)." >&2; exit 1; }
  n=$((n+1))
done
[ "$n" -eq 0 ] && { echo "No .zip files found in $ZIPDIR." >&2; exit 1; }
echo "Extracted $n zip file(s)."
[ -d "$MEM" ] || { echo "No 'memories' folder found inside the extracted data." >&2; exit 1; }
MEM="$(cd "$MEM" && pwd)"   # canonical absolute path
echo

# ---- helpers -------------------------------------------------------------
find_overlay() {  # $1=dir  $2=prefix
  local cand
  for cand in "$1/$2-overlay."*; do
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}

SCALE='[1:v][0:v]scale2ref[ovl][bse];[bse][ovl]overlay=0:0'

stamp() {  # $1=file $2=year $3=month $4=day
  [ "$2" != "unknown" ] && touch -t "${2}${3}${4}1200" "$1" 2>/dev/null
}

process_one() {
  local main="$1" dir base stem prefix ext lext
  case "$main" in /*) : ;; *) main="$PWD/$main" ;; esac   # force absolute path
  dir="${main%/*}"; base="${main##*/}"                    # no fork: dirname/basename
  stem="${base%.*}"; prefix="${stem%-main}"
  ext="${base##*.}"; lext="$(printf '%s' "$ext" | tr 'A-Z' 'a-z')"

  # date lives in the filename as YYYY-MM-DD...; require that exact shape
  local year month day
  case "$base" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*)
      year="${base:0:4}"; month="${base:5:2}"; day="${base:8:2}" ;;
    *) year="unknown"; month="00"; day="01" ;;
  esac

  local kind="image"
  case "$lext" in mp4|mov|m4v|avi) kind="video" ;; esac
  local overlay; overlay="$(find_overlay "$dir" "$prefix")"

  # --- Originals: raw main, untouched ---
  local odir="$ORIG/$year/$month"; mkdir -p "$odir"
  local oout="$odir/$prefix.$lext"
  if [ ! -f "$oout" ]; then
    if cp "$main" "$oout.tmp" && mv "$oout.tmp" "$oout"; then
      stamp "$oout" "$year" "$month" "$day"
    else
      rm -f "$oout.tmp"; echo "[FAIL orig] $prefix"
    fi
  fi

  # --- Merged: as seen in Snapchat ---
  local mdir="$MERGED/$year/$month"; mkdir -p "$mdir"
  local moutext="$lext"
  [ -n "$overlay" ] && [ "$kind" = "image" ] && moutext="jpg"
  local mout="$mdir/$prefix.$moutext"
  if [ -f "$mout" ]; then echo "[skip] $prefix"; return 0; fi
  local tmp="$mout.tmp.$moutext"

  if [ -z "$overlay" ]; then
    cp "$main" "$tmp" && mv "$tmp" "$mout" || { rm -f "$tmp"; echo "[FAIL copy] $prefix"; return 1; }
  elif [ "$kind" = "image" ]; then
    "$FFMPEG" -nostdin -y -loglevel error -i "$main" -i "$overlay" \
      -filter_complex "$SCALE[v]" -map "[v]" -frames:v 1 -q:v 2 "$tmp" \
      && mv "$tmp" "$mout" || { rm -f "$tmp"; echo "[FAIL img] $prefix"; return 1; }
  else
    "$FFMPEG" -nostdin -y -loglevel error -i "$main" -i "$overlay" \
      -filter_complex "$SCALE[v]" -map "[v]" -map "0:a?" -c:a copy \
      -movflags +faststart "$tmp" \
      && mv "$tmp" "$mout" || { rm -f "$tmp"; echo "[FAIL vid] $prefix"; return 1; }
  fi
  stamp "$mout" "$year" "$month" "$day"
  echo "[ok]   $year/$month/$prefix${overlay:+  (overlay merged)}"
  return 0
}

# ---- 2. dispatch with a concurrency cap (bash 3.2 friendly) -------------
LIST=$(mktemp /tmp/snap_list.XXXXXX)
find "$MEM" -type f -name '*-main.*' > "$LIST"
TOTAL=$(grep -c . "$LIST")
VIDS=$(grep -ciE '\-main\.(mp4|mov|m4v|avi)$' "$LIST")
IMGS=$((TOTAL - VIDS))
echo "Found $TOTAL memories: $IMGS photo(s), $VIDS video(s)."
echo "Processing with $MAX_PARALLEL workers (videos take longer)..."
echo

while IFS= read -r m <&3; do
  [ -z "$m" ] && continue
  process_one "$m" &
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$MAX_PARALLEL" ]; do sleep 0.3; done
done 3< "$LIST"
wait

OC=$(find "$ORIG" -type f | wc -l | tr -d ' ')
MC=$(find "$MERGED" -type f | wc -l | tr -d ' ')
echo
echo "Done."
echo "  $SUB_ORIG : $OC files   ($ORIG)"
echo "  $SUB_MERGED : $MC files   ($MERGED)"
