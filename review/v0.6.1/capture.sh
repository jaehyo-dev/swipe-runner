#!/usr/bin/env bash
# v0.6.1 기록: 전후 비교, 읽기 시트, 진하기 시트, 단계 빛남, 지나가는 장면, 밝기 순서 표. 저장소 뿌리에서 실행.
# 사용: bash review/v0.6.1/capture.sh <임시 폴더>
set -euo pipefail
tmp=$1; out=review/v0.6.1; old=$tmp/old_v0.6.0; root=$PWD
mkdir -p "$tmp/art" "$tmp/cmp_new" "$tmp/cmp_old" "$tmp/pass" "$old"
scene() { printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://%s.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' "$1" > "$2/$1.tscn"; }
size() { printf '[display]\nwindow/size/window_width_override=720\nwindow/size/window_height_override=1280\n' > "$1/override.cfg"; }
trap 'rm -f "$root/override.cfg" "$root"/moment_shots.* "$root"/pass_shots.*' EXIT
# 창이 있어야 그려지므로 앱을 숨긴 채로 띄운다: 화면을 가리지 않고 포커스도 뺏지 않는다. 숨기면 느려지지만 결과는 같다.
gd() { local log; log=$(mktemp); open -W -g -j -n -a /Applications/Godot.app --stdout "$log" --stderr "$log" --env "SEED=${SEED:-}" --env "EVENTS_JSON=${EVENTS_JSON:-}" --args "$@"; grep -E "SCRIPT ERROR" "$log" | cut -c1-160 || true; rm -f "$log"; }
# 전후 비교: 같은 시드, 같은 순간 (100BPM, 160BPM)
git archive v0.6.0 | tar -x -C "$old"
for d in "$old" "$root"; do cp "$out/moment_shots.gd" "$d/"; scene moment_shots "$d"; size "$d"; done
cp "$out/pass_shots.gd" "$root/"; scene pass_shots "$root"
godot --headless --path "$old" --import >/dev/null 2>&1
godot --headless --path "$root" --import >/dev/null 2>&1
gd --path "$old" --resolution 720x1280 res://moment_shots.tscn -- "$tmp/cmp_old"
gd --path "$root" --resolution 720x1280 res://moment_shots.tscn -- "$tmp/cmp_new"
for b in 100 160; do ffmpeg -y -v error -i "$tmp/cmp_old/moment_$b.png" -i "$tmp/cmp_new/moment_$b.png" -filter_complex "hstack" "$out/compare_$b.png"; done
# 읽기 시트, 진하기 시트, 단계 빛남
gd --path "$root" --resolution 720x1280 res://tools/art_sheet.tscn -- "$tmp/art"
python3 "$out/read_sheet.py" "$tmp/art" "$out/read_sheet.png"
python3 "$out/tint_sheet.py" "$tmp/art" "$out/tint_sheet.png" | tee "$tmp/saturation.txt"
ffmpeg -y -v error -i "$tmp/art/sparkle.png" -i "$tmp/art/stage_up.png" -filter_complex "hstack" "$out/stage_up.png"
# 장애물이 주인공을 지나쳐 가는 장면
gd --path "$root" --resolution 720x1280 res://pass_shots.tscn -- "$tmp/pass"
for k in block low high; do ffmpeg -y -v error -i "$tmp/pass/pass_${k}_z0.png" -i "$tmp/pass/pass_${k}_z1.png" -i "$tmp/pass/pass_${k}_z2.png" -i "$tmp/pass/pass_${k}_z3.png" -i "$tmp/pass/pass_${k}_z4.png" -filter_complex "hstack=inputs=5,scale=1500:-1" "$tmp/pass_$k.png"; done
ffmpeg -y -v error -i "$tmp/pass_block.png" -i "$tmp/pass_low.png" -i "$tmp/pass_high.png" -filter_complex "vstack=inputs=3" "$out/pass_by.png"
# 밝기 순서 표
godot --headless --path "$root" -s tools/brightness_report.gd 2>/dev/null | grep '^|' > "$tmp/brightness.txt"
