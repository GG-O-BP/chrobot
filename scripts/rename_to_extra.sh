#!/bin/bash
# rename_to_extra.sh
# chrobot → chrobot_extra 리네이밍 스크립트
# 초기 리네이밍 및 업스트림 싱크 시 재사용
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== chrobot → chrobot_extra rename script ==="

# --------------------------------------------------
# 1. 디렉토리/파일 이동
# --------------------------------------------------
echo "[1/5] Moving files and directories..."

# src/chrobot/ → src/chrobot_extra/
if [ -d "src/chrobot" ]; then
  rm -rf "src/chrobot_extra"
  mv "src/chrobot" "src/chrobot_extra"
  echo "  moved src/chrobot/ → src/chrobot_extra/"
fi

# src/chrobot.gleam → src/chrobot_extra.gleam
if [ -f "src/chrobot.gleam" ]; then
  mv "src/chrobot.gleam" "src/chrobot_extra.gleam"
  echo "  moved src/chrobot.gleam → src/chrobot_extra.gleam"
fi

# src/chrobot_ffi.erl → src/chrobot_extra_ffi.erl
if [ -f "src/chrobot_ffi.erl" ]; then
  mv "src/chrobot_ffi.erl" "src/chrobot_extra_ffi.erl"
  echo "  moved src/chrobot_ffi.erl → src/chrobot_extra_ffi.erl"
fi

# test/chrobot_test.gleam → test/chrobot_extra_test.gleam
if [ -f "test/chrobot_test.gleam" ]; then
  mv "test/chrobot_test.gleam" "test/chrobot_extra_test.gleam"
  echo "  moved test/chrobot_test.gleam → test/chrobot_extra_test.gleam"
fi

# --------------------------------------------------
# 2. 파일 내용 치환 (src/, test/, dev/)
# --------------------------------------------------
echo "[2/5] Replacing file contents in src/, test/, dev/..."

# 치환 대상 파일 수집 (.gleam, .erl)
find_targets() {
  find src/ test/ dev/ -type f \( -name '*.gleam' -o -name '*.erl' \) 2>/dev/null || true
}

# 순서가 중요: 더 구체적인 패턴을 먼저 치환
# 1) Erlang 모듈 선언: -module(chrobot_ffi) → -module(chrobot_extra_ffi)
# 2) @external FFI 참조: "chrobot_ffi" → "chrobot_extra_ffi"
# 3) import chrobot/ → import chrobot_extra/
# 4) import chrobot (단독, 줄 끝) → import chrobot_extra
# 5) chrobot. → chrobot_extra. (Gleam 함수 호출)
# 6) chrobot/install (사용자 메시지 내 커맨드) → chrobot_extra/install

for f in $(find_targets); do
  # Skip vendor/ (shouldn't match find paths, but be safe)
  case "$f" in vendor/*) continue;; esac

  sed -i \
    -e 's/-module(chrobot_ffi)/-module(chrobot_extra_ffi)/g' \
    -e 's/"chrobot_ffi"/"chrobot_extra_ffi"/g' \
    -e 's|"src/chrobot/|"src/chrobot_extra/|g' \
    -e 's|"src/protocol"|"src/chrobot_extra/protocol"|g' \
    -e 's/import chrobot\//import chrobot_extra\//g' \
    -e 's/import chrobot$/import chrobot_extra/g' \
    -e 's/chrobot\./chrobot_extra./g' \
    -e 's|chrobot/install|chrobot_extra/install|g' \
    "$f"
done

echo "  content replacements applied"

# --------------------------------------------------
# 3. README.md 치환
# --------------------------------------------------
echo "[3/5] Updating README.md..."

if [ -f "README.md" ]; then
  # \b word boundary로 standalone chrobot만 매칭
  # githubusercontent 포함 줄은 제외 (upstream 이미지 URL 보존)
  sed -i \
    -e '/githubusercontent/!s/\bChrobot\b/Chrobot Extra/g' \
    -e '/githubusercontent/!s/\bchrobot\b/chrobot_extra/g' \
    README.md
  echo "  README.md updated"
fi

# --------------------------------------------------
# 4. gleam.toml 수정
# --------------------------------------------------
echo "[4/5] Updating gleam.toml..."

sed -i \
  -e 's/^name = "chrobot"/name = "chrobot_extra"/' \
  -e 's|user = "JonasGruenwald", repo = "chrobot"|user = "GG-O-BP", repo = "chrobot"|' \
  gleam.toml

echo "  gleam.toml updated"

# --------------------------------------------------
# 4. codegen.sh 수정
# --------------------------------------------------
echo "[5/5] Updating codegen.sh..."

if [ -f "codegen.sh" ]; then
  # codegen.sh 내에서 특별한 chrobot 참조가 있으면 치환
  # (현재는 gleam run -m codegen/generate_bindings 만 사용하므로 변경 불필요)
  echo "  codegen.sh - no changes needed"
fi

echo ""
echo "=== Rename complete! ==="
echo "Next steps:"
echo "  1. Regenerate protocol bindings: gleam run -m codegen/generate_bindings"
echo "  2. Format: gleam format src/ test/"
echo "  3. Build: gleam build"
echo "  4. Update CLAUDE.md manually if needed"
