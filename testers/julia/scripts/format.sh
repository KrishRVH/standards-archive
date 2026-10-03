#!/bin/sh
# Check or format Git-tracked and unignored Julia sources with Runic.
set -eu

case "${1:-check}" in
  check) runic_mode="--check --diff" ;;
  write) runic_mode="--inplace" ;;
  *)
    echo "Usage: $0 [check|write]" >&2
    exit 2
    ;;
esac

tmp="$(mktemp)"
raw="$(mktemp)"
trap 'rm -f "$tmp" "$raw"' EXIT
# The project-local depot under .julia/ holds third-party sources; never format it.
if command -v git > /dev/null 2>&1 && git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  git ls-files --cached --others --exclude-standard -z -- '*.jl' ':(exclude).julia/**' > "$raw"
  # Keep only listed files that still exist; the loop runs in the child shell.
  # shellcheck disable=SC2016
  xargs -0 sh -c 'for file do [ ! -f "$file" ] || printf "%s\0" "$file"; done' sh < "$raw" > "$tmp"
else
  find . -type d \( -name .git -o -name .julia \) -prune -o -type f -name '*.jl' -print0 > "$tmp"
fi
if [ -s "$tmp" ]; then
  # Word splitting of the mode flags is intended.
  # shellcheck disable=SC2086
  xargs -0 julia --project=tools -m Runic $runic_mode < "$tmp"
fi
