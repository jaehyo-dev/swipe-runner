#!/usr/bin/env bash
# v0.5.0 기록 만들기: 진하기 시트, 전후 비교, 사다리 mp4 + 캡처 띠, 사람 모델 mp4. 저장소 뿌리에서 실행.
# 사용: bash review/v0.5.0/capture.sh <임시 폴더> <사람 모델 시드>
set -euo pipefail
tmp=$1; human_seed=$2; out=review/v0.5.0; old=$tmp/old_v0.4.1; art=$tmp/art; art_old=$tmp/art_old
mkdir -p "$tmp" "$old" "$art" "$art_old"
root=$PWD
size() { printf '[display]\nwindow/size/window_width_override=720\nwindow/size/window_height_override=1280\n' > "$1/override.cfg"; }
trap 'rm -f "$root/override.cfg" "$old/override.cfg"' EXIT
git archive v0.4.1 | tar -x -C "$old"
godot --headless --path "$old" --import >/dev/null 2>&1
movie() { # 프로젝트 결과 모드 초 시드
  size "$1"
  SEED=$5 EVENTS_JSON="$tmp/$2.json" godot --path "$1" --write-movie "$tmp/$2.avi" --fixed-fps 60 --resolution 720x1280 res://tools/playthrough.tscn -- "$3" "$4" all 100 2>&1 | grep -E "SCRIPT ERROR" | cut -c1-160 || true
}
mp4() { ffmpeg -y -v error -i "$tmp/$1.avi" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 26 -preset medium -pix_fmt yuv420p -c:a aac -b:a 160k "$out/$2"; }
# 1. 진하기 시트
size "$root"
godot --path . --resolution 720x1280 res://tools/art_sheet.tscn -- "$art" 2>&1 | grep -E "SCRIPT ERROR" | cut -c1-160 || true
python3 "$out/tint_sheet.py" "$art" "$out/tint_sheet.png"
# 2. 장애물 전후 비교: 같은 자리에 놓은 세 종류 + 같은 시드, 같은 순간(대기 1.5초 + 8초). 왼쪽 v0.4.1, 오른쪽 v0.5.0
size "$old"
godot --path "$old" --resolution 720x1280 res://tools/art_sheet.tscn -- "$art_old" 2>&1 | grep -E "SCRIPT ERROR" | cut -c1-160 || true
ffmpeg -y -v error -i "$art_old/near.png" -i "$art/near.png" -filter_complex hstack "$out/compare_near.png"
# 옛 playthrough는 SEED를 몰라 시드 143으로 찍는다 (새 빌드도 143)
size "$old"; EVENTS_JSON="$tmp/old.json" godot --path "$old" --write-movie "$tmp/old.avi" --fixed-fps 60 --resolution 720x1280 res://tools/playthrough.tscn -- clean 11 all 100 2>&1 | grep -E "SCRIPT ERROR" | cut -c1-160 || true
movie "$root" new clean 11 143
ffmpeg -y -v error -ss 9.5 -i "$tmp/old.avi" -ss 9.5 -i "$tmp/new.avi" -frames:v 1 -filter_complex hstack "$out/compare_run.png"
# 3. 처음부터 130BPM까지 색이 진해지는 과정 (소리 포함) + 8마디마다 캡처 띠 (대기 1.5초)
movie "$root" ladder clean 112 143
mp4 ladder ladder_to_130.mp4
python3 - "$tmp/ladder.avi" "$out/ladder_strip.png" <<'PY'
import subprocess, sys
from PIL import Image
src, dst = sys.argv[1:3]
bpms = [100, 105, 110, 115, 120, 125, 130]
t, shots = 1.5, []
for b in bpms:
    at = t + 2.5 * 4 * 60 / b  # 색이 다 따라간 뒤 (2마디 + 조금)
    frame = f"{dst}.{b}.png"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-ss", str(at), "-i", src, "-frames:v", "1", "-vf", "scale=240:-1", frame], check=True)
    shots.append(Image.open(frame).convert("RGB"))
    t += 8 * 4 * 60 / b
strip = Image.new("RGB", (sum(s.width for s in shots), shots[0].height))
x = 0
for s in shots:
    strip.paste(s, (x, 0))
    x += s.width
strip.save(dst)
import os
for b in bpms:
    os.remove(f"{dst}.{b}.png")
PY
# 4. 사람 모델이 죽을 때까지 (소리 포함)
movie "$root" human human 300 "$human_seed"
mp4 human human_seed_$human_seed.mp4
python3 -c "import json,sys; e=[x for x in json.load(open('$tmp/human.json')) if x['type']=='crash']; print('human crash at', e[0]['at'] if e else None)"
ls -la "$out"
