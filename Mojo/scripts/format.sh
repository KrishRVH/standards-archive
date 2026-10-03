#!/bin/sh
# Check or format project-owned Mojo source. `mojo format` only rewrites files
# in place, so the check formats a staged copy and compares it.
set -eu

case "${1:-check}" in
  check | write) mode="${1:-check}" ;;
  *)
    echo "Usage: $0 [check|write]" >&2
    exit 2
    ;;
esac

if [ "$mode" = write ]; then
  mojo format --quiet src tests
  exit 0
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R src tests "$stage"
(cd "$stage" && mojo format --quiet src tests)
if ! diff -ru src "$stage/src" || ! diff -ru tests "$stage/tests"; then
  echo "mojo:fmt:check found unformatted source; run mise run mojo:fmt" >&2
  exit 1
fi
