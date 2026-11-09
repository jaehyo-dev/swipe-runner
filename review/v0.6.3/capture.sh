#!/usr/bin/env bash
# v0.6.3 기록: 2칸 벽 시트, 벽 뒤 장애물, 멀리서 나타나기, 시야각, 처음부터 160BPM까지 mp4 + 4마디 캡처 띠. 저장소 뿌리에서 실행.
# 사용: bash review/v0.6.3/capture.sh <임시 폴더>
set -euo pipefail
tmp=$1; out=review/v0.6.3; root=$PWD
mkdir -p "$tmp/wall"
trap 'rm -f "$root/override.cfg" "$root"/wall_shots.*' EXIT
printf '[display]\nwindow/size/window_width_override=720\nwindow/size/window_height_override=1280\n' > override.cfg
cp "$out/wall_shots.gd" .
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://wall_shots.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' > wall_shots.tscn
godot --headless --path . --import >/dev/null 2>&1
# 앱을 숨긴 채로 띄운다: 화면을 가리지 않고 포커스도 뺏지 않는다
gd() { local log; log=$(mktemp); open -W -g -j -n -a /Applications/Godot.app --stdout "$log" --stderr "$log" --env "SEED=${SEED:-}" --env "EVENTS_JSON=${EVENTS_JSON:-}" --args "$@"; grep -E "SCRIPT ERROR" "$log" | cut -c1-160 || true; rm -f "$log"; }
gd --path "$root" --resolution 720x1280 res://wall_shots.tscn -- "$tmp/wall"
w=$tmp/wall
for p in left right ends; do ffmpeg -y -v error -i "$w/wall_${p}_z10.png" -i "$w/wall_${p}_z25.png" -i "$w/wall_${p}_z45.png" -filter_complex "hstack=inputs=3,scale=1080:-1" "$tmp/row_$p.png"; done
ffmpeg -y -v error -i "$tmp/row_left.png" -i "$tmp/row_right.png" -i "$tmp/row_ends.png" -filter_complex "vstack=inputs=3" "$out/wall_sheet.png"
ffmpeg -y -v error -i "$w/behind_low.png" -i "$w/behind_high.png" -i "$w/behind_block.png" -filter_complex "hstack=inputs=3,scale=1080:-1" "$out/wall_behind.png"
ffmpeg -y -v error -i "$w/far_fade.png" -vf "crop=140:50:290:530,scale=980:-1:flags=neighbor" "$out/far_fade.png"
ffmpeg -y -v error -i "$w/fov_62.png" -i "$w/fov_68.png" -filter_complex "hstack,scale=720:-1" "$out/fov_62_68.png"
rm -f override.cfg
# 처음부터 160BPM까지 (대기 1.5초, 160 도착 92초 + 조금), 소리 포함
SEED=143 EVENTS_JSON="$tmp/ladder.json" gd --path "$root" --write-movie "$tmp/ladder.avi" --fixed-fps 60 --resolution 720x1280 res://tools/playthrough.tscn -- clean 104 all 100
ffmpeg -y -v error -i "$tmp/ladder.avi" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 27 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k "$out/ladder_to_160.mp4"
python3 - "$tmp/ladder.avi" "$out/ladder_strip.png" <<'PY'
import os, subprocess, sys
from PIL import Image
src, dst = sys.argv[1:3]
t, shots, names = 1.5, [], []
for b in range(100, 165, 5):
    at = t + 3.5 * 4 * 60 / b  # 색과 시야각이 다 따라간 뒤 (2마디 + 조금)
    frame = f"{dst}.{b}.png"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-ss", str(at), "-i", src, "-frames:v", "1", "-vf", "scale=150:-1", frame], check=True)
    shots.append(Image.open(frame).convert("RGB")); names.append(frame)
    t += 4 * 4 * 60 / b
strip = Image.new("RGB", (sum(s.width for s in shots), shots[0].height))
x = 0
for s in shots:
    strip.paste(s, (x, 0)); x += s.width
strip.save(dst)
for n in names:
    os.remove(n)
PY
