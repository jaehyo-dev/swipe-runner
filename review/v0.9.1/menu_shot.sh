#!/usr/bin/env bash
# 메인 화면 캡처 3종 (휴대폰 390x844, PC 1280x720, 짧은 창 800x900). 저장소 뿌리에서: bash review/v0.9.1/menu_shot.sh <결과 폴더>
# 리눅스(WSL)는 화면 없는 X(xvfb)에서 그린다 (창을 띄우지 않음)
set -euo pipefail
out=$1; root=$PWD
mkdir -p "$out"
trap 'rm -f "$root/override.cfg" "$root"/menu_shot.gd "$root"/menu_shot.tscn "$root"/menu_shot.gd.uid' EXIT
cp review/v0.9.1/menu_shot.gd .
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://menu_shot.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' > menu_shot.tscn
for s in 390x844 1280x720 800x900; do
  printf '[display]\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "${s%x*}" "${s#*x}" > override.cfg
  timeout 300 nice -n 10 xvfb-run -a -s "-screen 0 1400x1400x24" godot --rendering-driver opengl3 --path "$root" --fixed-fps 60 --resolution "$s" res://menu_shot.tscn -- "$out/menu_$s" 2>&1 | grep -E "^창|SCRIPT ERROR" || true
done
