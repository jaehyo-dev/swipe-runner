#!/usr/bin/env bash
# 실제 크롬 전체 화면 측정 (사용자가 직접 실행): 60초 동안 창이 화면을 덮는다. 저장소 뿌리에서 실행.
# 사용: PW=<playwright 폴더> bash review/v0.6.1/run_mac_user.sh <임시 폴더>
set -euo pipefail
tmp=$1; here=$PWD/review/v0.6.1
bash "$here/build_measure.sh" "$tmp/m"
cd "$tmp/m/build/web"; python3 -m http.server 8762 >/dev/null 2>&1 & server=$!
trap 'kill $server' EXIT
sleep 1
cd "$tmp"; node "$here/measure_mac.mjs" "http://localhost:8762/?mode=accuracy&bpm=160&secs=60" "$tmp/mac_full.json" full
