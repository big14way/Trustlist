#!/usr/bin/env bash
# Cut the screen recordings on the Desktop into the exact segments the
# composition uses, cropped to the page and scaled to the output size.
#
# Every recording is the whole 3024 by 1964 screen at 120 frames a second,
# with the macOS menu bar and the browser's tab and address bars in it. The
# crops below were measured from the frames, not guessed: the page content
# begins at y=228 in every clip, and the window's left and right edges are
# at the pixel columns listed per source. Each crop is then a 16 by 9 box
# from that top edge, scaled to 2560 by 1440.
#
# Cutting here rather than inside Remotion keeps the render light: the
# composition reads 30 frame per second mp4s of the right size instead of
# seeking inside 120 frame per second screen captures.
#
# Usage: bash prepare.sh            (from video/)
set -euo pipefail
cd "$(dirname "$0")"

SRC="${TRUSTLIST_RECORDINGS:-$HOME/Desktop}"
OUT=public/clips
mkdir -p "$OUT"

# crop=W:H:X:Y for each source, per the pixel measurements.
CROP_HOME="2956:1663:44:228"      # homepage.mov, stats.mov: window x 44..2999
CROP_WIDE="3000:1687:10:228"      # agent 137.mov, Yield Scout.mov: x 10..3009
CROP_STD="2988:1681:10:228"       # scene 6, docs, methodology, hosted site: x 10..2997
CROP_SPLIT="3009:1693:10:228"     # split.mov: browser and editor side by side, x 10..3018
CROP_FULL="2984:1678:4:228"       # hosted hompage.mov: window edge to the scrollbar, x 4..2987

# The recordings are variable frame rate: macOS writes a frame only when
# something on screen changes, so a segment over a still page holds very few
# frames and would come out shorter than its window. Every segment is
# therefore padded by cloning its last frame and then capped at the exact
# length, which makes the duration in timeline.ts true whatever the source
# did. The play window is selected on the input side (-ss and -t before -i)
# and the output length on the output side.

# cut <source> <start seconds> <duration seconds> <crop> <output name> [extra filter]
cut() {
  local src=$1 start=$2 dur=$3 crop=$4 name=$5 extra=${6:-}
  local vf="crop=$crop,scale=2560:1440:flags=lanczos"
  [ -n "$extra" ] && vf="$vf,$extra"
  vf="$vf,tpad=stop_mode=clone:stop_duration=60"
  echo "  $name  <- $(basename "$src") @ ${start}s for ${dur}s"
  ffmpeg -v error -y -ss "$start" -t "$dur" -i "$src" -an \
    -vf "$vf" -r 30 -fps_mode cfr -t "$dur" \
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
    -movflags +faststart "$OUT/$name.mp4"
}

# freeze <source> <start> <play seconds> <total seconds> <crop> <name>
# Plays the segment and then holds its last frame until <total>.
freeze() {
  local src=$1 start=$2 play=$3 total=$4 crop=$5 name=$6
  echo "  $name  <- $(basename "$src") @ ${start}s for ${play}s, held to ${total}s"
  ffmpeg -v error -y -ss "$start" -t "$play" -i "$src" -an \
    -vf "crop=$crop,scale=2560:1440:flags=lanczos,tpad=stop_mode=clone:stop_duration=60" \
    -r 30 -fps_mode cfr -t "$total" \
    -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
    -movflags +faststart "$OUT/$name.mp4"
}

echo "scene 1, the homepage"
cut "$SRC/homepage.mov" 0.0 14.2 "$CROP_HOME" s1

echo "scene 2, registry health (the clip is shorter than the line, so the end holds)"
freeze "$SRC/stats.mov" 3.0 22.17 34.8 "$CROP_HOME" s2

echo "scene 3, agent 137"
cut "$SRC/agent 137.mov" 12.0 38.2 "$CROP_WIDE" s3

echo "scene 4, hiring Yield Scout: search and open the sheet, approve and hire, the explorer"
cut "$SRC/Yield Scout.mov" 4.0 16.0 "$CROP_WIDE" s4a
cut "$SRC/Yield Scout.mov" 44.0 22.0 "$CROP_WIDE" s4b
cut "$SRC/Yield Scout.mov" 68.0 10.0 "$CROP_WIDE" s4c

echo "scene 5, delivery and acceptance: terminal, submitted, accept, settled, explorer"
cut "$SRC/split.mov" 24.0 6.0 "$CROP_SPLIT" s5a
cut "$SRC/split.mov" 40.0 4.0 "$CROP_SPLIT" s5b
cut "$SRC/split.mov" 54.0 6.0 "$CROP_SPLIT" s5c
cut "$SRC/split.mov" 66.0 4.0 "$CROP_SPLIT" s5d
cut "$SRC/split.mov" 78.0 8.0 "$CROP_SPLIT" s5e

echo "scene 6, verify on chain"
cut "$SRC/second agent 137 scene 6.mov" 8.0 22.4 "$CROP_STD" s6

echo "scene 7, the advantage report on GitHub"
freeze "$SRC/docs.mov" 6.0 30.78 32.6 "$CROP_STD" s7

echo "scene 8, methodology, scrolled at twice the recorded pace"
ffmpeg -v error -y -ss 4.0 -t 35.2 -i "$SRC/methodology.mov" -an \
  -vf "crop=$CROP_STD,scale=2560:1440:flags=lanczos,setpts=0.5*PTS,tpad=stop_mode=clone:stop_duration=60" \
  -r 30 -fps_mode cfr -t 17.6 -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
  -movflags +faststart "$OUT/s8.mp4"
echo "  s8  <- methodology.mov @ 4.0s, 35.2s at double speed"

echo "scene 9, the hosted site, the repository, the hosted site again"
# The first hosted site recording was made while the database sync was mid
# copy and showed an empty marketplace, so the homepage shots come from a
# retake made once the listing was fixed. The repository shot is unchanged.
# The retake starts before the page has finished loading, so its first
# second carries the counter collapsing on the live site.
HOSTED="$SRC/hosted hompage.mov"
cut "$HOSTED" 0.0 6.0 "$CROP_FULL" s9a
cut "$SRC/hosted site.mov" 36.0 5.0 "$CROP_STD" s9b
cut "$HOSTED" 30.0 6.0 "$CROP_FULL" s9c

echo
echo "durations as cut:"
for f in "$OUT"/*.mp4; do
  printf '  %-8s %ss\n' "$(basename "$f" .mp4)" "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")"
done
