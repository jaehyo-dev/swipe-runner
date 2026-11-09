#!/usr/bin/env bash
# 전후 비교, 130BPM mp4, 장애물 읽기 시트를 Movie Maker와 창 실행으로 만든다. 저장소 뿌리에서 실행.
# 사용: bash review/v0.4.1/capture.sh <임시 폴더>  (임시 폴더에 v0.4.0 태그를 풀어 같은 시드·같은 순간을 찍는다)
set -euo pipefail
tmp=$1; out=review/v0.4.1; old=$tmp/old_v0.4.0
mkdir -p "$tmp" "$old"
root=$PWD
git archive v0.4.0 | tar -x -C "$old"
cp tools/playthrough.gd "$old/tools/playthrough.gd"  # 측정 도구만 같은 것을 쓴다 (물방울 없는 빌드도 동작)
godot --headless --path "$old" --import >/dev/null 2>&1
size() { printf '[display]\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "${2%x*}" "${2#*x}" > "$1/override.cfg"; }
trap 'rm -f "$root/override.cfg" "$old/override.cfg"' EXIT
movie() { # 프로젝트 결과 초 BPM
  size "$1" 720x1280
  EVENTS_JSON="$tmp/$2.json" godot --path "$1" --write-movie "$tmp/$2.avi" --fixed-fps 60 --resolution 720x1280 res://tools/playthrough.tscn -- clean "$3" all "$4" 2>&1 | grep -E "^RESULT|SCRIPT ERROR" | cut -c1-120
}
for bpm in 100 130; do
  movie "$old" "old_$bpm" 11 "$bpm"
  movie "$root" "new_$bpm" 11 "$bpm"
  # 대기 1.5초 + 8초 = 같은 음악 시간. 왼쪽 v0.4.0, 오른쪽 v0.4.1
  ffmpeg -y -v error -ss 9.5 -i "$tmp/old_$bpm.avi" -ss 9.5 -i "$tmp/new_$bpm.avi" -frames:v 1 -filter_complex hstack "$out/compare_$bpm.png"
done
movie "$root" top 31.6 130
ffmpeg -y -v error -ss 1.5 -i "$tmp/top.avi" -t 30 -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 26 -preset medium -pix_fmt yuv420p -c:a aac -b:a 160k "$out/play_130.mp4"
# 단계가 오르는 순간 (100 → ... 105 → 110 경계 비교)은 flash는 자동 테스트로 확인
size "$root" 720x1280
godot --path . --resolution 720x1280 res://tools/art_sheet.tscn -- "$tmp" 2>&1 | grep -E "SCRIPT ERROR" || true
python3 "$out/read_sheet.py" "$tmp" "$out/read_sheet.png"
