#!/bin/sh
# Check that every committed package interface (.mbti) matches what
# `moon info` generates. moon info only writes in place, so the check
# regenerates interfaces in a staged copy of the module and compares them.
set -eu

staged="$(mktemp -d)"
trap 'rm -rf "$staged"' 0
trap 'exit 1' 1 2 15

tar -cf - --exclude=./_build --exclude=./.git --exclude=./target . | tar -xf - -C "$staged"
moon -C "$staged" info --quiet

list_interfaces() {
  (cd "$1" && find . \( -name _build -o -name .git -o -name .mooncakes -o -name target \) -prune -o -type f -name '*.mbti' -print | LC_ALL=C sort)
}

list_interfaces . > "$staged/.committed"
list_interfaces "$staged" > "$staged/.generated"
status=0
if ! cmp -s "$staged/.committed" "$staged/.generated"; then
  echo "moonbit:info:check found added or removed interfaces; run 'mise run moonbit:info'" >&2
  diff "$staged/.committed" "$staged/.generated" >&2 || true
  status=1
fi
while IFS= read -r path; do
  if [ -f "$path" ] && ! cmp -s "$path" "$staged/$path"; then
    echo "moonbit:info:check found a stale interface: $path; run 'mise run moonbit:info'" >&2
    diff "$path" "$staged/$path" >&2 || true
    status=1
  fi
done < "$staged/.generated"
exit "$status"
