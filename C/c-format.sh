#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT
readonly MODE="${1:-check}"
readonly SOURCE_ROOT="${2:-$ROOT}"
readonly FORMATTER="${C_CLANG_FORMAT:-clang-format}"
readonly REQUIRED_VERSION="22.1.8"
readonly JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2> /dev/null || nproc 2> /dev/null || echo 4)}"

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

command -v "$FORMATTER" > /dev/null 2>&1 ||
  fail "required formatter is unavailable: $FORMATTER"

version="$("$FORMATTER" --version 2>&1)"
reported_version="$(awk '$1 == "clang-format" && $2 == "version" {print $3; exit}' <<< "$version")"
[[ "$reported_version" == "$REQUIRED_VERSION" ]] ||
  fail "clang-format $REQUIRED_VERSION is required; parsed version: ${reported_version:-<none>}"

case "$MODE" in
  check | write) ;;
  *) fail "usage: $0 [check|write] [source-root]" ;;
esac

list_files() {
  if command -v git > /dev/null 2>&1 &&
    git -C "$SOURCE_ROOT" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    git -C "$SOURCE_ROOT" ls-files --cached --others --exclude-standard -z -- \
      '*.c' '*.h' \
      ':(exclude,glob)**/build/**' ':(exclude,glob)**/build-*/**' \
      ':(exclude,glob)**/vendor/**' ':(exclude,glob)**/third_party/**' |
      while IFS= read -r -d '' file; do
        [[ -f "$SOURCE_ROOT/$file" ]] || continue
        printf '%s/%s\0' "$SOURCE_ROOT" "$file"
      done
  else
    find "$SOURCE_ROOT" \
      -type d \( -name .git -o -name build -o -name 'build-*' -o \
      -name vendor -o -name third_party \) -prune -o \
      -type f \( -name '*.c' -o -name '*.h' \) -print0
  fi
}

files=()
while IFS= read -r -d '' file; do
  files+=("$file")
done < <(list_files)

((${#files[@]} > 0)) || fail "no C sources found under $SOURCE_ROOT"

printf '[INFO] formatter profile: clang-format %s (%s)\n' "$REQUIRED_VERSION" "$MODE"
if [[ "$MODE" == "write" ]]; then
  printf '%s\0' "${files[@]}" | xargs -0 -P "$JOBS" -n 16 "$FORMATTER" -i
else
  printf '%s\0' "${files[@]}" |
    xargs -0 -P "$JOBS" -n 16 "$FORMATTER" --dry-run --Werror
fi
printf '[PASS] formatted presentation gate inspected %d files\n' "${#files[@]}"
