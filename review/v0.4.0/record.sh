#!/usr/bin/env bash
# 소리 포함 mp4 3개와 새 기록 GIF를 Movie Maker로 만든다. 사용: bash review/v0.4.0/record.sh <임시 폴더>  (저장소 뿌리에서 실행)
set -euo pipefail
tmp=$1; out=review/v0.4.0; mkdir -p "$tmp"
trap 'rm -f override.cfg' EXIT
movie() { # 이름 해상도 초 시작BPM 예전최고
  # project.godot의 창 크기 지정이 --resolution보다 앞서므로 녹화 동안만 덮어쓴다
  printf '[display]\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "${2%x*}" "${2#*x}" > override.cfg
  BEST=${5:-} EVENTS_JSON="$tmp/$1.json" godot --path . --write-movie "$tmp/$1.avi" --fixed-fps 60 --resolution "$2" res://tools/playthrough.tscn -- clean "$3" all "$4" 2>&1 | grep -E "^RESULT|SCRIPT ERROR" | cut -c1-200
}
cut_mp4() { # 이름 시작초 길이 결과
  ffmpeg -y -v error -ss "$2" -i "$tmp/$1.avi" -t "$3" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 26 -preset medium -pix_fmt yuv420p -c:a aac -b:a 160k "$out/$4"
}
# 경계 앞뒤 30초: 105의 한 바퀴는 36.571초, 115는 33.391초. 대기 1.5초 포함
movie cross_a 720x1280 66.7 105; cut_mp4 cross_a 8.071 60 boundary_105_110.mp4
movie cross_b 720x1280 63.5 115; cut_mp4 cross_b 4.891 60 boundary_115_120.mp4
movie top 720x1280 30 130; cut_mp4 top 1.5 30 top_130.mp4
# 새 기록 순간: 예전 최고 30을 약 3.3초에 넘는다
for pair in "phone 390x844" "pc 1280x720"; do
  set -- $pair
  movie "record_$1" "$2" 6 100 30
  ffmpeg -y -v error -ss 4.2 -t 1.4 -i "$tmp/record_$1.avi" -vf "fps=30,scale=iw*min(1\,480/iw):-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse" "$out/new_record_$1.gif"
done
ls -la "$out"
