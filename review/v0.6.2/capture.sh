#!/usr/bin/env bash
# v0.6.2 기록: 기둥을 통해 본 뒤 장애물 사진과 밝기 비율. 저장소 뿌리에서 실행.
# 사용: bash review/v0.6.2/capture.sh <임시 폴더>
set -euo pipefail
tmp=$1; out=review/v0.6.2; root=$PWD
mkdir -p "$tmp/see"
trap 'rm -f "$root/override.cfg" "$root"/see_through.*' EXIT
printf '[display]\nwindow/size/window_width_override=1440\nwindow/size/window_height_override=2560\n' > override.cfg
cp "$out/see_through.gd" .
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://see_through.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' > see_through.tscn
godot --headless --path . --import >/dev/null 2>&1
# 앱을 숨긴 채로 띄운다: 화면을 가리지 않고 포커스도 뺏지 않는다
log=$(mktemp); open -W -g -j -n -a /Applications/Godot.app --stdout "$log" --stderr "$log" --args --path "$root" --resolution 1440x2560 res://see_through.tscn -- "$tmp/see"; grep -E "SCRIPT ERROR" "$log" | cut -c1-160 || true; rm -f "$log"
python3 "$out/see_through_report.py" "$tmp/see" "$out"
