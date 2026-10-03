#!/bin/sh
# Check or test project-owned Vx source with the pinned compiler toolchain.
set -eu

usage() {
  echo "Usage: $0 [lint|test]" >&2
  exit 2
}

case "${1:-}" in
  lint | test) mode="$1" ;;
  *) usage ;;
esac

if [ "$mode" = lint ]; then
  # Type, placement, and contract checks need no LLVM backend. vxc exits
  # nonzero on errors but zero on warnings, so read the versioned report.
  report="$(mktemp)"
  list="$(mktemp)"
  trap 'rm -f "$report" "$list"' EXIT
  find src tests -type f -name '*.vx' | sort > "$list"
  status=0
  while IFS= read -r file; do
    if ! vxc --action print-ast --diagnostics-json "$report" "$file" > /dev/null; then
      status=1
    elif ! grep -q '"warning_count": 0,' "$report"; then
      printf "vx:lint found warnings: %s\n" "$file" >&2
      status=1
    fi
  done < "$list"
  exit "$status"
fi

# vxc reads only `llvm-config --libdir`, to link the MLIR runner libraries.
# conda-forge ships those in libmlir, apart from llvmdev's llvm-config.
LLVM_CONFIG_PATH="$(pwd)/scripts/llvm-config"
ffi_lib="$(mise where conda:libffi)/lib"
LIBRARY_PATH="$ffi_lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
LD_LIBRARY_PATH="$ffi_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LLVM_CONFIG_PATH LIBRARY_PATH LD_LIBRARY_PATH

found=0
for file in tests/*_test.vx; do
  [ -e "$file" ] || continue
  found=1
  printf "vx:test %s\n" "$file"
  vxc "$file"
done
if [ "$found" -eq 0 ]; then
  echo "vx:test found no tests/*_test.vx programs" >&2
  exit 1
fi
