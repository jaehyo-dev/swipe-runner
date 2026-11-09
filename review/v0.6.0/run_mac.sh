#!/usr/bin/env bash
# 맥북 실제 크롬 측정 전부. 다른 프로그램이 CPU를 많이 쓰면 결과가 오염되므로 한가해질 때까지 기다렸다가 잰다.
# 사용: PW=<playwright> bash review/v0.6.0/run_mac.sh <결과 폴더> <v0.5.1 측정 빌드 주소> <v0.6.0 측정 빌드 주소>   (주소는 끝에 / 까지)
# 부하가 가장 큰 160BPM(레이저 6줄, 빛 줄기 48개, 조각 가장 많음)에서 잰다.
out=$1; O="$2?mode=accuracy&bpm=160"; N="$3?mode=accuracy&bpm=160"
cd "$(dirname "$0")"
quiet() {  # 다른 프로세스 합계 CPU가 80% 아래로 내려갈 때까지 (최대 5분)
  for i in $(seq 1 60); do
    busy=$(ps -Ao %cpu,command | grep -vE "ps -Ao|mac-|run_mac" | awk '{s+=$1} END {print int(s)}')
    [ "$busy" -lt 80 ] && break
    sleep 5
  done
  echo "기다린 뒤 CPU 합계 $busy%"
}
run() { quiet; node measure_mac.mjs "$1" "$out/$2.json" "$3" $4; }
run "$3control.html?secs=30" control full
run "$O&secs=60" old_full full; run "$N&secs=60" new_full full
run "$O&secs=60" old_1280x800 1280x800; run "$N&secs=60" new_1280x800 1280x800
run "$N&secs=60" new_cpu4 full cpu4
run "$N&secs=15&off=guard" cost_none full uncapped
for o in msaa glow mirror sky laser streak shard drops hero; do run "$N&secs=15&off=guard,$o" cost_$o full uncapped; done
run "$N&secs=180" new_3min full
run "${3}?mode=accuracy&secs=200" new_ladder_real full
echo DONE
