#!/usr/bin/env bash
# v0.9.0 기록: 메인 화면(첫 실행·4판째 이후, 휴대폰·PC), 시작 전환 GIF, 게임 오버 → 메인 GIF, ^ 기호 z -45, 웹 확인(콘솔·소리). 저장소 뿌리에서 실행.
# 사용: bash review/v0.9.0/capture.sh <임시 폴더>   (웹 단계는 PW·CHROME 환경 변수가 필요, SHOTS_ONLY=1이면 건너뜀, STEPS="menu gif mark"처럼 일부만)
set -euo pipefail
tmp=$1; out=review/v0.9.0; root=$PWD
mkdir -p "$tmp"
godot --headless --path . --import >/dev/null 2>&1
trap 'rm -f "$root/override.cfg" "$root"/menu_shots.*' EXIT
# 리눅스(WSL): 화면 없는 X(xvfb)에서 소프트웨어 OpenGL로 그린다. 맥은 숨긴 앱으로
if [ "$(uname)" = Linux ]; then
gd() { local name=$1; shift; timeout 300 xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 "$@" >"$tmp/$name.log" 2>&1; grep -E "SCRIPT ERROR" "$tmp/$name.log" | cut -c1-200 || true; }
else
gd() { local name=$1; shift; open -W -g -j -n -a /Applications/Godot.app --stdout "$tmp/$name.log" --stderr "$tmp/$name.log" --args "$@"; grep -E "SCRIPT ERROR" "$tmp/$name.log" | cut -c1-200 || true; }
fi
size() { printf '[display]\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$1" "$2" > override.cfg; }
want() { [ -z "${STEPS:-}" ] || [[ " $STEPS " == *" $1 "* ]]; }
gif() {  # 프레임 폴더 → GIF (폭 360, 30fps). ffmpeg가 없으면 PIL로
  if command -v ffmpeg >/dev/null; then
    ffmpeg -y -v error -framerate 30 -i "$1/%04d.png" -vf "scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse" "$2"
  else
    python3 -c 'import sys,glob;from PIL import Image;f=[Image.open(p).convert("RGB") for p in sorted(glob.glob(sys.argv[1]+"/*.png"))];f=[i.resize((360,i.height*360//i.width),Image.LANCZOS).quantize(128) for i in f];f[0].save(sys.argv[2],save_all=True,append_images=f[1:],duration=33,loop=0)' "$1" "$2"
  fi
}
if [ -z "${WEB_ONLY:-}" ]; then
cp "$out/menu_shots.gd" .
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://menu_shots.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' > menu_shots.tscn
# 1. 메인 화면: 휴대폰 390x844, PC 1280x720
want menu && for s in 390x844 1280x720; do
  size "${s%x*}" "${s#*x}"
  gd "menu_$s" --path "$root" --fixed-fps 60 --resolution "$s" res://menu_shots.tscn -- "$tmp/menu_$s" menu
  cp "$tmp/menu_$s/menu_first.png" "$out/menu_first_$s.png"; cp "$tmp/menu_$s/menu_later.png" "$out/menu_later_$s.png"; cp "$tmp/menu_$s/menu.txt" "$out/menu_$s.txt"
done
# 2. GIF: 시작 전환, 게임 오버 → 메인 (720x1280)
want gif && for m in start home; do
  size 720 1280
  gd "$m" --path "$root" --fixed-fps 60 --resolution 720x1280 res://menu_shots.tscn -- "$tmp/$m" "$m"
  gif "$tmp/$m/$m" "$out/$m.gif"
  cp "$tmp/$m/$m.txt" "$out/$m.txt"
done
[ -f "$tmp/home/gameover.png" ] && cp "$tmp/home/gameover.png" "$out/gameover_home_button.png"
# 3. ^ 기호 z -45 (720x1280)
if want mark; then
  size 720 1280
  gd mark --path "$root" --fixed-fps 60 --resolution 720x1280 res://menu_shots.tscn -- "$tmp/mark" mark
  cp "$tmp/mark/mark_z45.png" "$tmp/mark/mark_z45_zoom.png" "$tmp/mark/mark.txt" "$out/"
fi
rm -f menu_shots.gd menu_shots.tscn menu_shots.gd.uid override.cfg
fi
[ -z "${SHOTS_ONLY:-}" ] || exit 0
# 4. 웹: 게임 빌드 캡처·콘솔 오류·소리 크기
mkdir -p "$tmp/web"
godot --headless --path . --export-release "Web" "$tmp/web/index.html" 2>&1 | grep -iE "^(ERROR|SCRIPT ERROR)" || true
(cd "$tmp/web" && exec python3 -m http.server 8781 >/dev/null 2>&1) & s1=$!
trap 'kill $s1 2>/dev/null || true; rm -f "$root/override.cfg" "$root"/menu_shots.*' EXIT
sleep 1
node review/v0.9.0/check_web.mjs "http://localhost:8781/" "$out" > "$out/check_web.json"
echo "끝: $tmp"
