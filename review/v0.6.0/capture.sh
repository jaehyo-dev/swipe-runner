#!/usr/bin/env bash
# v0.6.0 기록: 전후 비교, 읽기 시트, 진하기 시트, 부서짐 GIF, 처음부터 160BPM까지 mp4 + 4마디 캡처 띠, 밝기 순서 표. 저장소 뿌리에서 실행.
# 사용: bash review/v0.6.0/capture.sh <임시 폴더>
set -euo pipefail
tmp=$1; out=review/v0.6.0; old=$tmp/old_v0.5.1; root=$PWD
mkdir -p "$tmp/art" "$tmp/cmp_new" "$tmp/cmp_old" "$tmp/shards" "$old"
scene() { printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://%s.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' "$1" > "$2/$1.tscn"; }
size() { printf '[display]\nwindow/size/window_width_override=720\nwindow/size/window_height_override=1280\n' > "$1/override.cfg"; }
trap 'rm -f "$root/override.cfg" "$root"/moment_shots.* "$root"/shatter_shots.*' EXIT
# 창이 있어야 그려지므로 앱을 숨긴 채로 띄운다: 화면을 가리지 않고 포커스도 뺏지 않는다. 숨기면 느려지지만 결과는 같다.
gd() { local log; log=$(mktemp); open -W -g -j -n -a /Applications/Godot.app --stdout "$log" --stderr "$log" --env "SEED=${SEED:-}" --env "EVENTS_JSON=${EVENTS_JSON:-}" --args "$@"; grep -E "SCRIPT ERROR" "$log" | cut -c1-160 || true; rm -f "$log"; }
# 전후 비교: 같은 시드, 같은 순간 (100BPM, 160BPM)
git archive v0.5.1 | tar -x -C "$old"
for d in "$old" "$root"; do cp "$out/moment_shots.gd" "$d/"; scene moment_shots "$d"; size "$d"; done
cp "$out/shatter_shots.gd" "$root/"; scene shatter_shots "$root"
godot --headless --path "$old" --import >/dev/null 2>&1
godot --headless --path "$root" --import >/dev/null 2>&1
gd --path "$old" --resolution 720x1280 res://moment_shots.tscn -- "$tmp/cmp_old"
gd --path "$root" --resolution 720x1280 res://moment_shots.tscn -- "$tmp/cmp_new"
for b in 100 160; do ffmpeg -y -v error -i "$tmp/cmp_old/moment_$b.png" -i "$tmp/cmp_new/moment_$b.png" -filter_complex "hstack" "$out/compare_$b.png"; done
# 읽기 시트, 진하기 시트
gd --path "$root" --resolution 720x1280 res://tools/art_sheet.tscn -- "$tmp/art"
python3 "$out/read_sheet.py" "$tmp/art" "$out/read_sheet.png"
python3 "$out/tint_sheet.py" "$tmp/art" "$out/tint_sheet.png" | tee "$tmp/saturation.txt"
# 부서짐 GIF: 가까이서, 한 개·겹줄·점프로 넘기
gd --path "$root" --resolution 720x1280 res://shatter_shots.tscn -- "$tmp/shards"
for n in single double over; do
  ffmpeg -y -v error -framerate 60 -i "$tmp/shards/${n}_%03d.png" -filter_complex "crop=720:620:0:520,scale=420:-1:flags=lanczos,fps=30,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$out/shatter_$n.gif"
done
# 처음부터 160BPM까지 (대기 1.5초, 160 도착 92초 + 조금), 소리 포함
SEED=143 EVENTS_JSON="$tmp/ladder.json" gd --path "$root" --write-movie "$tmp/ladder.avi" --fixed-fps 60 --resolution 720x1280 res://tools/playthrough.tscn -- clean 104 all 100
ffmpeg -y -v error -i "$tmp/ladder.avi" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 27 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k "$out/ladder_to_160.mp4"
python3 - "$tmp/ladder.avi" "$out/ladder_strip.png" <<'PY'
import os, subprocess, sys
from PIL import Image
src, dst = sys.argv[1:3]
t, shots, names = 1.5, [], []
for b in range(100, 165, 5):
    at = t + 3.5 * 4 * 60 / b  # 색이 다 따라간 뒤 (2마디 + 조금)
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
python3 -c "import json; e=[x for x in json.load(open('$tmp/ladder.json')) if x['type']=='crash']; print('영상 충돌', len(e))"
