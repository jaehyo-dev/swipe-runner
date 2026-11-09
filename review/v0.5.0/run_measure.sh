#!/usr/bin/env bash
# 웹 측정 전부: 콜드 시작 15초 3회, 처음부터 130BPM까지 + 곡 이음매, 130BPM 3분. 저장소 뿌리에서 실행.
# 사용: PW=<playwright> CHROME=<크로미움> bash review/v0.5.0/run_measure.sh <측정 빌드 폴더> <결과 폴더>   (진짜 빌드는 build/web)
set -uo pipefail
mb=$1; out=$2; mkdir -p "$out"
python3 -m http.server 8931 --directory build/web >/dev/null 2>&1 & s1=$!
python3 -m http.server 8932 --directory "$mb/build/web" >/dev/null 2>&1 & s2=$!
trap 'kill $s1 $s2 2>/dev/null' EXIT
sleep 1
for i in 1 2 3; do
  READY=1 node review/v0.5.0/measure_frames.mjs "http://localhost:8931/" "$out/cold_$i.json" gpu '[[1,"ArrowLeft"],[2.2,"ArrowUp"],[3.6,"ArrowDown"],[5,"ArrowRight"],[6.4,"ArrowRight"],[7.8,"ArrowUp"]]'
done
node review/v0.5.0/measure_ladder.mjs "http://localhost:8932/?mode=accuracy&secs=268" "$out/ladder.json"; echo ladder exit $?
node review/v0.5.0/measure_ladder.mjs "http://localhost:8932/?mode=accuracy&secs=180&bpm=130" "$out/top130.json"; echo top exit $?
