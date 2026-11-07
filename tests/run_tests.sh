#!/usr/bin/env bash
# 게임 자동 테스트 실행 (리소스 가져오기를 먼저 실행해 둘 것)
# 사용: bash tests/run_tests.sh   (Godot 경로는 GODOT 환경 변수로 바꿀 수 있음)
# Godot는 실행 스크립트가 파싱에 실패해도 종료 코드 0으로 끝나므로,
# 실행기가 끝까지 돌아 "결과:" 줄을 찍었는지도 확인한다.
set -uo pipefail
log=$(mktemp)
trap 'rm -f "$log"' EXIT
"${GODOT:-godot}" --headless --path . -s res://tests/run_tests.gd 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
if ! grep -q "^결과: 통과 [0-9]*, 실패 [0-9]*$" "$log"; then
	echo "테스트 실행기가 끝까지 실행되지 않았습니다 (스크립트 파싱·로드 오류 확인)" >&2
	exit 1
fi
exit "$code"
