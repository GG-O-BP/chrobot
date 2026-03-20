#!/bin/bash
# rename_to_chrobot.sh
# chrobot_extra → chrobot 리네이밍 역변환 스크립트
# rename_to_extra.sh의 역방향 변환
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== chrobot_extra → chrobot reverse rename script ==="

# --------------------------------------------------
# 1. 디렉토리/파일 이동 (역방향)
# --------------------------------------------------
echo "[1/4] Moving files and directories..."

# src/chrobot_extra/ → src/chrobot/
if [ -d "src/chrobot_extra" ]; then
  rm -rf "src/chrobot"
  mv "src/chrobot_extra" "src/chrobot"
  echo "  moved src/chrobot_extra/ → src/chrobot/"
fi

# src/chrobot_extra.gleam → src/chrobot.gleam
if [ -f "src/chrobot_extra.gleam" ]; then
  mv "src/chrobot_extra.gleam" "src/chrobot.gleam"
  echo "  moved src/chrobot_extra.gleam → src/chrobot.gleam"
fi

# src/chrobot_extra_ffi.erl → src/chrobot_ffi.erl
if [ -f "src/chrobot_extra_ffi.erl" ]; then
  mv "src/chrobot_extra_ffi.erl" "src/chrobot_ffi.erl"
  echo "  moved src/chrobot_extra_ffi.erl → src/chrobot_ffi.erl"
fi

# test/chrobot_extra_test.gleam → test/chrobot_test.gleam
if [ -f "test/chrobot_extra_test.gleam" ]; then
  mv "test/chrobot_extra_test.gleam" "test/chrobot_test.gleam"
  echo "  moved test/chrobot_extra_test.gleam → test/chrobot_test.gleam"
fi

# --------------------------------------------------
# 2. 파일 내용 치환 (src/, test/, dev/)
# --------------------------------------------------
echo "[2/4] Replacing file contents in src/, test/, dev/..."

# 치환 대상 파일 수집 (.gleam, .erl)
find_targets() {
  find src/ test/ dev/ -type f \( -name '*.gleam' -o -name '*.erl' \) 2>/dev/null || true
}

# 순서가 중요: 더 구체적인 패턴을 먼저 치환
# 1) Erlang 모듈 선언
# 2) @external FFI 참조
# 3) codegen 특수 케이스: "src/chrobot_extra/protocol" → "src/protocol"
# 4) 일반 경로: "src/chrobot_extra/ → "src/chrobot/
# 5) import 경로
# 6) import 단독
# 7) 함수 호출
# 8) install 커맨드
for f in $(find_targets); do
  case "$f" in vendor/*) continue;; esac

  sed -i \
    -e 's/-module(chrobot_extra_ffi)/-module(chrobot_ffi)/g' \
    -e 's/"chrobot_extra_ffi"/"chrobot_ffi"/g' \
    -e 's|"src/chrobot_extra/protocol"|"src/protocol"|g' \
    -e 's|"src/chrobot_extra/|"src/chrobot/|g' \
    -e 's/import chrobot_extra\//import chrobot\//g' \
    -e 's/import chrobot_extra\(\r\?\)$/import chrobot\1/g' \
    -e 's/chrobot_extra\./chrobot./g' \
    -e 's|chrobot_extra/install|chrobot/install|g' \
    "$f"
done

echo "  content replacements applied"

# --------------------------------------------------
# 3. README.md 치환
# --------------------------------------------------
echo "[3/4] Updating README.md..."

if [ -f "README.md" ]; then
  # Chrobot Extra → Chrobot (대문자, 단순 문자열 치환)
  # chrobot_extra → chrobot (소문자, _extra 포함이라 오매칭 없음)
  sed -i \
    -e 's/Chrobot Extra/Chrobot/g' \
    -e 's/\bchrobot_extra\b/chrobot/g' \
    README.md
  echo "  README.md updated"
fi

# --------------------------------------------------
# 4. gleam.toml 수정
# --------------------------------------------------
echo "[4/4] Updating gleam.toml..."

sed -i \
  -e 's/^name = "chrobot_extra"/name = "chrobot"/' \
  -e 's|user = "GG-O-BP", repo = "chrobot"|user = "JonasGruenwald", repo = "chrobot"|' \
  gleam.toml

echo "  gleam.toml updated"

echo ""
echo "=== Reverse rename complete! ==="
echo "Next steps:"
echo "  1. Build: gleam build"
echo "  2. Test: gleam test"
