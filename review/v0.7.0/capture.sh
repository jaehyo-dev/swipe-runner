#!/usr/bin/env bash
# v0.7.0 기록: 잘하는 모델이 죽을 때까지 mp4(소리 포함), 압박 단계 0/4/8/12 캡처, 박자 오차, 웹 캡처·콘솔 오류, 헤드리스 프레임 표. 저장소 뿌리에서 실행.
# 사용: PW=<playwright> CHROME=<크로미움> bash review/v0.7.0/capture.sh <임시 폴더>
set -euo pipefail
tmp=$1; out=review/v0.7.0; root=$PWD
mkdir -p "$tmp"
godot --headless --path . --import >/dev/null 2>&1
# 앱을 숨긴 채로 띄운다: 화면을 가리지 않고 포커스도 뺏지 않는다. 표준 출력은 $tmp/<이름>.log
# 창 크기를 720x1280으로 (없으면 화면 크기에 맞춰 줄어든다)
trap 'rm -f "$root/override.cfg" "$root"/pressure_shots.*' EXIT
printf '[display]\nwindow/size/window_width_override=720\nwindow/size/window_height_override=1280\n' > override.cfg
gd() { local name=$1; shift; open -W -g -j -n -a /Applications/Godot.app --stdout "$tmp/$name.log" --stderr "$tmp/$name.log" --env "SEED=${SEED:-}" --env "MODEL=${MODEL:-}" --args "$@"; grep -E "SCRIPT ERROR" "$tmp/$name.log" | cut -c1-160 || true; }
if [ -z "${WEB_ONLY:-}" ]; then
# 1. 잘하는 모델, 처음(100BPM)부터 죽을 때까지. 시드 20 = 난이도 표의 중앙값 근처
MODEL=good SEED=20 gd human --path "$root" --write-movie "$tmp/human.avi" --fixed-fps 60 --resolution 720x1280 res://tools/playthrough.tscn -- human 300 all 100
ffmpeg -y -v error -i "$tmp/human.avi" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 27 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k "$out/good_model_to_death.mp4"
# 2. 압박 단계 0/4/8/12: 사다리를 그 박까지 올려 한 장씩 찍는다 (숨긴 앱은 1분쯤 지나면 그리기가 멈춰 긴 녹화는 쓰지 않는다)
cp "$out/pressure_shots.gd" .
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://pressure_shots.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' > pressure_shots.tscn
mkdir -p "$tmp/pressure"
gd shots --path "$root" --resolution 720x1280 res://pressure_shots.tscn -- "$tmp/pressure"
p=$tmp/pressure
ffmpeg -y -v error -i "$p/pressure_00.png" -i "$p/pressure_04.png" -i "$p/pressure_08.png" -i "$p/pressure_12.png" -filter_complex "hstack=inputs=4,scale=1440:-1" "$out/pressure_0_4_8_12.png"
cp "$p/pressure_shots.txt" "$out/pressure_shots.txt"
rm -f pressure_shots.gd pressure_shots.tscn pressure_shots.gd.uid
rm -f override.cfg
# 3. 데스크톱 박자 오차 (100BPM부터 약 265초). 참고용: 웹 측정(4)이 배포 기준이다
[ "${SKIP_DESKTOP_ACCURACY:-}" ] || gd accuracy --path "$root" res://tools/playthrough.tscn -- accuracy 265
grep "^RESULT" "$tmp/accuracy.log" > "$tmp/accuracy.json" || true
fi  # WEB_ONLY=1이면 1~3을 건너뛴다
[ -z "${SHOTS_ONLY:-}" ] || exit 0  # SHOTS_ONLY=1이면 1~3만
# 4. 웹: 게임 빌드 캡처·콘솔 오류, 측정 빌드로 박자 오차(100BPM부터 265초)와 헤드리스 프레임 (3420x1850, 160BPM 시작 60초)
mkdir -p "$tmp/web"
godot --headless --path . --export-release "Web" "$tmp/web/index.html" 2>&1 | grep -iE "^(ERROR|SCRIPT ERROR)" || true
bash review/v0.6.1/build_measure.sh "$tmp/m"
(cd "$tmp/web" && python3 -m http.server 8771 >/dev/null 2>&1) & s1=$!
(cd "$tmp/m/build/web" && python3 -m http.server 8772 >/dev/null 2>&1) & s2=$!
trap 'kill $s1 $s2 2>/dev/null || true; rm -f "$root/override.cfg" "$root"/pressure_shots.*' EXIT
sleep 1
node "$out/check_web.mjs" "http://localhost:8771/" "$out" > "$tmp/check_web.json"
node review/v0.6.1/measure_headless.mjs "http://localhost:8772/?mode=accuracy&bpm=100&secs=265" "$tmp/web_accuracy.json" 1710x925
node review/v0.6.1/measure_headless.mjs "http://localhost:8772/?mode=accuracy&bpm=160&secs=60" "$tmp/perf.json" 1710x925
echo "끝: $tmp"
