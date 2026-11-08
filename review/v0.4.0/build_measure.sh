#!/usr/bin/env bash
# 측정용 빌드: 저장소를 건드리지 않고 임시 복사본에서 시작 장면을 tools/playthrough.tscn으로 바꿔 내보낸다.
# 사용: bash review/v0.4.0/build_measure.sh <임시 폴더>   결과: <임시 폴더>/build/web
set -euo pipefail
dest=$1
mkdir -p "$dest"
rsync -a --delete --exclude .git --exclude review --exclude build --exclude logs ./ "$dest/"
mkdir -p "$dest/build/web"; touch "$dest/build/.gdignore"
cd "$dest"
python3 - <<'PY'
import re
s=open('project.godot',encoding='utf-8').read()
s=re.sub(r'run/main_scene="[^"]*"','run/main_scene="res://tools/playthrough.tscn"',s)
open('project.godot','w',encoding='utf-8').write(s)
s=open('export_presets.cfg',encoding='utf-8').read()
s=s.replace('exclude_filter="tests/*, tools/*, ','exclude_filter="')
open('export_presets.cfg','w',encoding='utf-8').write(s)
PY
godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . --export-release "Web" "$PWD/build/web/index.html" 2>&1 | grep -iE "^(ERROR|SCRIPT ERROR)" || true
test -s build/web/index.pck
