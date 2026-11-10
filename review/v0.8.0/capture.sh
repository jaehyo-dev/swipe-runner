#!/usr/bin/env bash
# v0.8.0 기록: 방울 배치 캡처, 먹기·끊김·아슬아슬 GIF, 욕심쟁이 모델 mp4(소리 포함), UI 캡처(휴대폰·PC), 웹 콘솔·박자·프레임. 저장소 뿌리에서 실행.
# 사용: PW=<playwright> CHROME=<크로미움> bash review/v0.8.0/capture.sh <임시 폴더>
# 앱은 숨긴 채로 띄운다(open -g -j): 화면을 가리지 않고 포커스도 뺏지 않는다.
set -euo pipefail
tmp=$1; out=review/v0.8.0; root=$PWD
mkdir -p "$tmp"
godot --headless --path . --import >/dev/null 2>&1
trap 'rm -f "$root/override.cfg" "$root"/orb_shots.*' EXIT
gd() { local name=$1; shift; open -W -g -j -n -a /Applications/Godot.app --stdout "$tmp/$name.log" --stderr "$tmp/$name.log" --env "SEED=${SEED:-}" --env "MODEL=${MODEL:-}" --args "$@"; grep -E "SCRIPT ERROR" "$tmp/$name.log" | cut -c1-200 || true; }
size() { printf '[display]\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$1" "$2" > override.cfg; }
if [ -z "${WEB_ONLY:-}" ]; then
cp "$out/orb_shots.gd" .
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://orb_shots.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' > orb_shots.tscn
size 720 1280
want() { [ -z "${STEPS:-}" ] || [[ " $STEPS " == *" $1 "* ]]; }  # STEPS="gif ui"처럼 일부만
# 1. 방울 배치 (모양 넷 × z -10, -25)
if want place; then
mkdir -p "$tmp/place"
gd place --path "$root" --fixed-fps 60 --resolution 720x1280 res://orb_shots.tscn -- "$tmp/place" place
p=$tmp/place
for z in 10 25; do
  ffmpeg -y -v error -i "$p/place_move_z$z.png" -i "$p/place_arc_z$z.png" -i "$p/place_under_z$z.png" -i "$p/place_beside_z$z.png" -filter_complex "hstack=inputs=4,scale=1440:-1" "$out/placement_z$z.png"
done
cp "$p/place.txt" "$out/placement.txt"
fi
# 2. GIF (30fps, 360px 폭)
if want gif; then
mkdir -p "$tmp/gif"
gd gif --path "$root" --fixed-fps 60 --resolution 720x1280 res://orb_shots.tscn -- "$tmp/gif" gif
for g in eat break close; do
  ffmpeg -y -v error -framerate 30 -i "$tmp/gif/$g/%04d.png" -vf "scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse" "$out/$g.gif"
done
cp "$tmp/gif/gif.txt" "$out/gif.txt"
fi
# 3. UI: 휴대폰 390x844, PC 1280x720 (배수 ×3 달리기, 게임 오버)
want ui && for s in 390x844 1280x720; do
  size "${s%x*}" "${s#*x}"
  mkdir -p "$tmp/ui_$s"
  gd "ui_$s" --path "$root" --fixed-fps 60 --resolution "$s" res://orb_shots.tscn -- "$tmp/ui_$s" ui
  cp "$tmp/ui_$s/ui_run.png" "$out/ui_run_$s.png"; cp "$tmp/ui_$s/ui_gameover.png" "$out/ui_gameover_$s.png"
done
size 720 1280
# 4. 욕심쟁이 모델, 처음(100BPM)부터 죽을 때까지 (소리 포함)
if want mp4; then
MODEL=greedy SEED=${MP4_SEED:-20} gd human --path "$root" --write-movie "$tmp/human.avi" --fixed-fps 60 --resolution 720x1280 res://tools/playthrough.tscn -- human 300 all 100
ffmpeg -y -v error -i "$tmp/human.avi" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 27 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k "$out/greedy_model_to_death.mp4"
fi
rm -f orb_shots.gd orb_shots.tscn orb_shots.gd.uid override.cfg
fi
[ -z "${SHOTS_ONLY:-}" ] || exit 0
# 5. 웹: 게임 빌드 캡처·콘솔 오류, 측정 빌드로 박자 오차와 헤드리스 프레임 (v0.7.0과 같은 도구)
mkdir -p "$tmp/web"
godot --headless --path . --export-release "Web" "$tmp/web/index.html" 2>&1 | grep -iE "^(ERROR|SCRIPT ERROR)" || true
bash review/v0.6.1/build_measure.sh "$tmp/m"
(cd "$tmp/web" && python3 -m http.server 8781 >/dev/null 2>&1) & s1=$!
(cd "$tmp/m/build/web" && python3 -m http.server 8782 >/dev/null 2>&1) & s2=$!
trap 'kill $s1 $s2 2>/dev/null || true; rm -f "$root/override.cfg" "$root"/orb_shots.*' EXIT
sleep 1
node review/v0.7.0/check_web.mjs "http://localhost:8781/" "$out" > "$tmp/check_web.json"
node review/v0.6.1/measure_headless.mjs "http://localhost:8782/?mode=accuracy&bpm=100&secs=265" "$tmp/web_accuracy.json" 1710x925
node review/v0.6.1/measure_headless.mjs "http://localhost:8782/?mode=accuracy&bpm=160&secs=60" "$tmp/perf.json" 1710x925
echo "끝: $tmp"
