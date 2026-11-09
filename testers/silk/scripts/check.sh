#!/bin/sh
# Check or test a Silk package, failing on what the Silk tools report but exit
# zero for: compiler warnings, documentation links that name no declaration,
# source modules that no root reaches, and warnings in documentation examples.
# Silk checks, tests, and documents only the modules it reaches by imports from
# the root module and the exported modules, so an unreached module is never
# type-checked and its tests never run.
set -eu

usage() {
  echo "Usage: $0 [lint|test]" >&2
  exit 2
}

case "${1:-}" in
  lint | test) mode="$1" ;;
  *) usage ;;
esac

report="$(mktemp)"
trap 'rm -f "$report"' EXIT

if [ "$mode" = test ]; then
  # An unchanged rerun otherwise reports earlier passing results.
  silk test --no-cache
  # Example results go to standard output and example diagnostics to standard
  # error, which a passing run leaves empty.
  if ! silk doctest 2> "$report" || [ -s "$report" ]; then
    cat "$report" >&2
    echo "silk:test found failing or warning documentation examples" >&2
    exit 1
  fi
  exit 0
fi

documentation="$(mktemp)"
inputs="$(mktemp)"
sources="$(mktemp)"
trap 'rm -f "$report" "$documentation" "$inputs" "$sources"' EXIT
status=0

# Without progress rows, a clean check writes nothing. Errors exit nonzero and
# warnings exit zero, so any output fails.
if ! silk check --progress never > "$report" 2>&1 || [ -s "$report" ]; then
  cat "$report" >&2
  echo "silk:lint found compiler diagnostics" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  # silk doc warns on standard error about each link that resolves to nothing.
  # Private declarations and tests are documented only with --include-private.
  if ! silk doc --include-private -o "$documentation" > /dev/null 2> "$report" || [ -s "$report" ]; then
    cat "$report" >&2
    echo "silk:lint found unresolved documentation links" >&2
    status=1
  fi
fi

# Version 1 of the hash listing names each source a test build reads as
# `read <digest> <path>`, relative to the package directory.
silk hash --list --test > "$inputs"
if [ "$(sed -n 1p "$inputs")" != "silk-hash 1" ]; then
  echo "silk:lint cannot read this silk hash --list format" >&2
  exit 1
fi
if command -v git > /dev/null 2>&1 && git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  git ls-files --cached --others --exclude-standard -- 'src/*.silk' > "$sources"
else
  find src -type f -name '*.silk' > "$sources"
fi
while IFS= read -r path; do
  # The index still lists a tracked file deleted from the work tree.
  [ -e "$path" ] || continue
  if ! awk -v path="$path" '$1 == "read" && $2 != "missing" && substr($0, length($1 $2) + 3) == path { found = 1 } END { exit !found }' "$inputs"; then
    printf "silk:lint found a module that no root reaches: %s. Import it from a reached module or list it in exports.\n" "$path" >&2
    status=1
  fi
done < "$sources"

exit "$status"
