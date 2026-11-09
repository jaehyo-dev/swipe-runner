#!/usr/bin/env bash
# v0.5.1 기록: 전후 비교, 진하기 시트 + 평균 채도, 처음부터 160BPM까지 mp4 + 4마디 캡처 띠, 잘하는 모델 mp4. 저장소 뿌리에서 실행.
# 사용: bash review/v0.5.1/capture.sh <임시 폴더> <잘하는 모델 시드>
set -euo pipefail
tmp=$1; seed=$2; out=review/v0.5.1; old=$tmp/old_v0.5.0; root=$PWD
mkdir -p "$tmp/art" "$tmp/cmp_new" "$tmp/cmp_old" "$old"
size() { printf '[display]\nwindow/size/window_width_override=720\nwindow/size/window_height_override=1280\n' > "$1/override.cfg"; }
trap 'rm -f "$root/override.cfg" "$root/compare_shots.gd" "$root/compare_shots.tscn" "$root/compare_shots.gd.uid"' EXIT
git archive v0.5.0 | tar -x -C "$old"
godot --headless --path "$old" --import >/dev/null 2>&1
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://compare_shots.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' > "$tmp/compare_shots.tscn"
for d in "$old" "$root"; do cp "$out/compare_shots.gd" "$tmp/compare_shots.tscn" "$d/"; size "$d"; done
godot --headless --path "$root" --import >/dev/null 2>&1
godot --path "$old" --resolution 720x1280 res://compare_shots.tscn -- "$tmp/cmp_old" 2>&1 | grep -E "SCRIPT ERROR" | cut -c1-160 || true
godot --path "$root" --resolution 720x1280 res://compare_shots.tscn -- "$tmp/cmp_new" 2>&1 | grep -E "SCRIPT ERROR" | cut -c1-160 || true
for n in bar pillars double; do ffmpeg -y -v error -i "$tmp/cmp_old/$n.png" -i "$tmp/cmp_new/$n.png" -filter_complex "[0]crop=720:800:0:360[a];[1]crop=720:800:0:360[b];[a][b]hstack" "$out/compare_$n.png"; done
# 진하기 시트
godot --path . --resolution 720x1280 res://tools/art_sheet.tscn -- "$tmp/art" 2>&1 | grep -E "SCRIPT ERROR" | cut -c1-160 || true
python3 "$out/tint_sheet.py" "$tmp/art" "$out/tint_sheet.png" | tee "$tmp/saturation.txt"
movie() { # 결과 모드 초 시드
  SEED=$4 EVENTS_JSON="$tmp/$1.json" godot --path . --write-movie "$tmp/$1.avi" --fixed-fps 60 --resolution 720x1280 res://tools/playthrough.tscn -- "$2" "$3" all 100 2>&1 | grep -E "SCRIPT ERROR" | cut -c1-160 || true
}
mp4() { ffmpeg -y -v error -i "$tmp/$1.avi" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 27 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k "$out/$2"; }
# 처음부터 160BPM까지 (대기 1.5초, 160 도착 92초 + 조금)
movie ladder clean 104 143
mp4 ladder ladder_to_160.mp4
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
# 잘하는 모델이 중앙값 근처에서 죽는 판
MODEL=good movie human human 300 "$seed"
mp4 human "good_model_seed_$seed.mp4"
python3 -c "import json; e=[x for x in json.load(open('$tmp/human.json')) if x['type']=='crash']; print('잘하는 모델 충돌', e[0]['at'] if e else None)"
