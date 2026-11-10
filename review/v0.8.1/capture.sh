#!/usr/bin/env bash
# v0.8.1 기록: PERFECT GIF(한 번, 연속 ×3), 놓친 방울 GIF(1/3 속도), UI 캡처(휴대폰·PC), 웹 콘솔·박자·프레임. 저장소 뿌리에서 실행.
# 사용: bash review/v0.8.1/capture.sh <임시 폴더>   (웹 단계는 PW·CHROME 환경 변수가 필요, SHOTS_ONLY=1이면 건너뜀)
# 앱은 숨긴 채로 띄운다(open -g -j): 화면을 가리지 않고 포커스도 뺏지 않는다.
set -euo pipefail
tmp=$1; out=review/v0.8.1; root=$PWD
mkdir -p "$tmp"
godot --headless --path . --import >/dev/null 2>&1
trap 'rm -f "$root/override.cfg" "$root"/perfect_shots.*' EXIT
gd() { local name=$1; shift; open -W -g -j -n -a /Applications/Godot.app --stdout "$tmp/$name.log" --stderr "$tmp/$name.log" --args "$@"; grep -E "SCRIPT ERROR" "$tmp/$name.log" | cut -c1-200 || true; }
size() { printf '[display]\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$1" "$2" > override.cfg; }
want() { [ -z "${STEPS:-}" ] || [[ " $STEPS " == *" $1 "* ]]; }  # STEPS="gif ui"처럼 일부만
if [ -z "${WEB_ONLY:-}" ]; then
cp "$out/perfect_shots.gd" .
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://perfect_shots.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' > perfect_shots.tscn
# 1. GIF: PERFECT 30fps, 놓친 방울은 매 프레임을 20fps로 (1/3 속도)
if want gif; then
  size 720 1280
  gd gif --path "$root" --fixed-fps 60 --resolution 720x1280 res://perfect_shots.tscn -- "$tmp/gif" gif
  for g in perfect perfect_x3; do
    [ -d "$tmp/gif/$g" ] && ffmpeg -y -v error -framerate 30 -i "$tmp/gif/$g/%04d.png" -vf "scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse" "$out/$g.gif"
  done
  [ -d "$tmp/gif/miss" ] && ffmpeg -y -v error -framerate 20 -i "$tmp/gif/miss/%04d.png" -vf "scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse" "$out/miss_slow3x.gif"
  cp "$tmp/gif/gif.txt" "$out/gif.txt"
fi
# 2. UI: 휴대폰 390x844, PC 1280x720
want ui && for s in 390x844 1280x720; do
  size "${s%x*}" "${s#*x}"
  gd "ui_$s" --path "$root" --fixed-fps 60 --resolution "$s" res://perfect_shots.tscn -- "$tmp/ui_$s" ui
  cp "$tmp/ui_$s/ui_run.png" "$out/ui_perfect_$s.png"; cp "$tmp/ui_$s/ui.txt" "$out/ui_$s.txt"
done
rm -f perfect_shots.gd perfect_shots.tscn perfect_shots.gd.uid override.cfg
fi
[ -z "${SHOTS_ONLY:-}" ] || exit 0
# 3. 웹: 게임 빌드 캡처·콘솔 오류, 측정 빌드로 박자 오차와 헤드리스 프레임 (v0.8.0과 같은 도구)
mkdir -p "$tmp/web"
godot --headless --path . --export-release "Web" "$tmp/web/index.html" 2>&1 | grep -iE "^(ERROR|SCRIPT ERROR)" || true
bash review/v0.6.1/build_measure.sh "$tmp/m"
(cd "$tmp/web" && python3 -m http.server 8781 >/dev/null 2>&1) & s1=$!
(cd "$tmp/m/build/web" && python3 -m http.server 8782 >/dev/null 2>&1) & s2=$!
trap 'kill $s1 $s2 2>/dev/null || true; rm -f "$root/override.cfg" "$root"/perfect_shots.*' EXIT
sleep 1
node review/v0.7.0/check_web.mjs "http://localhost:8781/" "$out" > "$tmp/check_web.json"
node review/v0.6.1/measure_headless.mjs "http://localhost:8782/?mode=accuracy&bpm=100&secs=265" "$tmp/web_accuracy.json" 1710x925
node review/v0.6.1/measure_headless.mjs "http://localhost:8782/?mode=accuracy&bpm=160&secs=60" "$tmp/perf.json" 1710x925
echo "끝: $tmp"
