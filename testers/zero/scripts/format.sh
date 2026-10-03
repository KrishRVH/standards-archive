#!/bin/sh
# Check or format the Zero source projection. zero.graph is the compiler
# input, so a write refreshes it from the formatted projection. Writes refuse
# a drifted projection: only a person can tell whether the graph or the source
# holds the intended edit.
set -eu

usage() {
  echo "Usage: $0 [check|write]" >&2
  exit 2
}

# Checks or rewrites one file. It runs in its own process per file, so its
# cleanup trap covers only that file's staged copy.
format_file() {
  mode="$1"
  task="zero:fmt"
  if [ "$mode" = check ]; then
    task="zero:fmt:check"
  fi
  path="$2"
  case "$path" in
    /* | ./*) ;;
    *) path="./$path" ;;
  esac
  if [ -L "$path" ]; then
    printf "%s refuses non-regular source: %s\n" "$task" "$2" >&2
    exit 1
  fi
  if [ ! -e "$path" ]; then
    exit 0
  fi
  if [ ! -f "$path" ]; then
    printf "%s refuses non-regular source: %s\n" "$task" "$2" >&2
    exit 1
  fi

  # zero fmt --check on a package checks only the target's main file.
  if [ "$mode" = check ]; then
    zero fmt --check "$path"
    exit 0
  fi

  tmp="$(mktemp "${path}.zero-fmt.XXXXXX")"
  trap 'rm -f "$tmp"' 0
  trap 'exit 1' 1 2 15
  cp -p "$path" "$tmp"
  zero fmt "$path" > "$tmp"
  if cmp -s "$path" "$tmp"; then
    rm -f "$tmp"
  else
    compare_status=$?
    if [ "$compare_status" -ne 1 ]; then
      printf "zero:fmt could not compare staged source: %s\n" "$2" >&2
      exit 1
    fi
    if ! mv -f "$tmp" "$path"; then
      printf "zero:fmt could not replace source: %s\n" "$2" >&2
      exit 1
    fi
  fi
  trap - 0 1 2 15
}

case "${1:-check}" in
  check | write) mode="${1:-check}" ;;
  check-file | write-file)
    [ "$#" -eq 2 ] || usage
    format_file "${1%-file}" "$2"
    exit 0
    ;;
  *) usage ;;
esac

if ! zero verify-projection .; then
  [ "$mode" = check ] && exit 1
  echo "zero:fmt needs a clean projection. Run 'zero import .' if the .0 source holds the edit, or 'zero export .' if zero.graph does." >&2
  exit 1
fi

list="$(mktemp)"
trap 'rm -f "$list"' EXIT
if command -v git > /dev/null 2>&1 && git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  git ls-files --cached --others --exclude-standard -z -- 'src/*.0' > "$list"
else
  find src \( -type f -o -type l \) -name '*.0' -print0 > "$list"
fi
if [ -s "$list" ]; then
  xargs -0 -n 1 sh "$0" "$mode-file" < "$list"
fi

if [ "$mode" = write ] && ! zero verify-projection . > /dev/null 2>&1; then
  zero import .
fi
