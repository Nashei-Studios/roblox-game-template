#!/usr/bin/env bash
# Tests for tools/board against a stub `gh` (no network). Run: bash tests/tools/board.test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BOARD="$HERE/../../tools/board"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/work"
FAKE_REPO="stubowner/stubrepo"

cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal gh stub: answers only the calls tools/board makes.
case "$*" in
  "api repos/$STUB_REPO --jq .full_name") echo "$STUB_REPO" ;;
  "api repos/$STUB_REPO/issues/1 --jq .comments") echo 2 ;;
  "api repos/$STUB_REPO/issues/1/comments -f body="*) echo "https://example.invalid/c/3" ;;
  "api --paginate repos/$STUB_REPO/issues/1/comments?"*|"api repos/$STUB_REPO/issues/1/comments?"*)
    b1="$(printf "[Ana's Claude] hola @leon" | base64 | tr -d '\n')"
    b2="$(printf 'mine' | base64 | tr -d '\n')"
    printf '1\tana\t2026-11-11T10:00:00Z\t%s\n2\tleon\t2026-11-11T10:05:00Z\t%s\n' "$b1" "$b2" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/gh"

cd "$TMP/work" && git init -q
export PATH="$TMP/bin:$PATH" STUB_REPO="$FAKE_REPO" BOARD_REPO="$FAKE_REPO" BOARD_LOGIN=leon
fail=0
check() { if [ "$2" = "0" ]; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

out="$(bash "$BOARD" unread)"
printf '%s' "$out" | grep -q '@ana' && printf '%s' "$out" | grep -q 'MENTION'
check "unread shows others and flags the mention" $?
! printf '%s' "$out" | grep -q 'mine'
check "unread hides my own posts" $?
[ -z "$(bash "$BOARD" unread)" ]
check "a second unread is empty (cursor advanced)" $?
[ "$(bash "$BOARD" whoami)" = "leon" ]
check "whoami uses BOARD_LOGIN" $?
! bash "$BOARD" post "no prefix" >/dev/null 2>&1
check "post without the [human's agent] prefix is rejected" $?
bash "$BOARD" post "[Leon's Claude] listo" | grep -q 'example.invalid'
check "post with the prefix returns the comment url" $?
bash "$BOARD" read -n 2 | grep -q '@ana'
check "read prints the last comments" $?
! BOARD_REPO='bad repo' bash "$BOARD" read >/dev/null 2>&1
check "an invalid BOARD_REPO is rejected" $?
exit $fail
