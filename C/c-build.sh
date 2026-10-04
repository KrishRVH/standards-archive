#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT
readonly MODE="${1:-native}"
readonly JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2> /dev/null || nproc 2> /dev/null || echo 4)}"
readonly REQUIRED_CLANG_VERSION="22.1.8"
readonly REQUIRED_GCC_VERSION="15.2.0"
readonly REQUIRED_MINGW_GCC_VERSION="13.0.0"
readonly REQUIRED_CMAKE_VERSION="4.4.0"
readonly REQUIRED_NINJA_VERSION="1.13.2"

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

require_tool() {
  command -v "$1" > /dev/null 2>&1 || fail "required tool is unavailable: $1"
}

require_exact_version() {
  local label="$1"
  local required="$2"
  local actual="$3"

  [[ "$actual" == "$required" ]] ||
    fail "$label $required is required; parsed version: ${actual:-<none>}"
}

clean_preset() {
  local preset="$1"

  cmake -E remove_directory "$ROOT/build/$preset"
}

require_cache_entry() {
  local cache_file="$1"
  local entry="$2"

  grep -Fqx -- "$entry" "$cache_file" ||
    fail "$cache_file does not contain required preset contract: $entry"
}

require_every_compile_command_flag() {
  local compile_database="$1"
  local flag="$2"

  if grep -F '"command"' "$compile_database" |
    grep -Fv -- " $flag " > /dev/null; then
    fail "$compile_database contains an owned translation unit without required flag: $flag"
  fi
}

# Loads the reviewed warning flags for one compiler and build type, the common
# contract plus the family contract, into the array named by the third argument.
load_warning_contract() {
  local compiler_id="$1"
  local build_type="$2"
  local -n contract_flags="$3"
  local family_contract="gcc-debug-flags.txt"
  local contract_file
  local flag

  if [[ "$compiler_id" == "Clang" ]]; then
    family_contract="clang-flags.txt"
  elif [[ "$build_type" == "Release" || "$build_type" == "RelWithDebInfo" ]]; then
    family_contract="gcc-release-flags.txt"
  fi
  contract_flags=()
  for contract_file in common-flags.txt "$family_contract"; do
    while IFS= read -r flag; do
      [[ -n "$flag" && "$flag" != \#* ]] || continue
      contract_flags+=("$flag")
    done < "$ROOT/standards-tests/compiler/$contract_file"
  done
  ((${#contract_flags[@]} > 0)) || fail "the reviewed warning contract is empty"
}

require_warning_contract() {
  local compile_database="$1"
  local compiler_id="$2"
  local build_type="$3"
  local flag
  local -a required_flags=()

  load_warning_contract "$compiler_id" "$build_type" required_flags
  for flag in "${required_flags[@]}"; do
    require_every_compile_command_flag "$compile_database" "$flag"
  done
}

reject_unreviewed_diagnostic_flags() {
  local compile_database="$1"
  local compiler_id="$2"
  local build_type="$3"
  local flag
  local -a reviewed_flags=()
  local -a observed_flags=()
  local -A allowed_flags=()

  load_warning_contract "$compiler_id" "$build_type" reviewed_flags
  for flag in "${reviewed_flags[@]}"; do
    allowed_flags["$flag"]=1
  done

  mapfile -t observed_flags < <(
    grep -F '"command"' "$compile_database" |
      grep -oE -- '-W[^[:space:]"]+' | LC_ALL=C sort -u
  )
  for flag in "${observed_flags[@]}"; do
    [[ -n "${allowed_flags[$flag]+allowed}" ]] ||
      fail "$compile_database contains an unreviewed diagnostic flag: $flag"
  done
  if grep -F '"command"' "$compile_database" |
    grep -E -- ' (-fanalyzer([^[:space:]"]*)?|--analyze|-Xanalyzer|-Xclang [^"[:space:]]*analyzer)' \
      > /dev/null; then
    fail "$compile_database contains an unreviewed compiler analyzer mode"
  fi
}

verify_build_contract() {
  local build_dir="$1"
  local expected_sanitizer="$2"
  local expected_build_type="$3"
  local expected_compiler_id="$4"
  local expected_platform_profile="${5:-iso-hosted}"
  local cache_file="$build_dir/CMakeCache.txt"
  local compile_database="$build_dir/compile_commands.json"
  local compiler_contract
  local command_count
  local configured_compiler
  local expected_compiler
  local expected_compiler_version

  [[ -s "$cache_file" ]] || fail "configured preset cache is missing: $cache_file"
  [[ -s "$compile_database" ]] ||
    fail "owned-target compilation database is missing: $compile_database"
  require_cache_entry "$cache_file" "CMAKE_BUILD_TYPE:STRING=$expected_build_type"
  require_cache_entry "$cache_file" \
    "PROJECT_PLATFORM_PROFILE:STRING=$expected_platform_profile"
  require_cache_entry "$cache_file" "PROJECT_SANITIZER:STRING=$expected_sanitizer"
  require_cache_entry "$cache_file" "PROJECT_WERROR:BOOL=ON"

  compiler_contract="$(find "$build_dir/CMakeFiles" -name CMakeCCompiler.cmake -print -quit)"
  [[ -n "$compiler_contract" ]] ||
    fail "CMake compiler identity contract is missing under $build_dir/CMakeFiles"
  grep -Fq -- "set(CMAKE_C_COMPILER_ID \"$expected_compiler_id\")" "$compiler_contract" ||
    fail "$compiler_contract does not identify the required compiler family: $expected_compiler_id"
  if [[ "$expected_compiler_id" == "Clang" ]]; then
    expected_compiler="$(command -v clang)"
    expected_compiler_version="$REQUIRED_CLANG_VERSION"
  elif [[ "$expected_platform_profile" == "win32" ]]; then
    expected_compiler="$(command -v x86_64-w64-mingw32-gcc)"
    expected_compiler_version="$REQUIRED_MINGW_GCC_VERSION"
  else
    expected_compiler="$(command -v gcc)"
    expected_compiler_version="$REQUIRED_GCC_VERSION"
  fi
  configured_compiler="$(sed -n 's/^set(CMAKE_C_COMPILER "\(.*\)")$/\1/p' \
    "$compiler_contract")"
  [[ -n "$configured_compiler" ]] ||
    fail "$compiler_contract does not record the configured compiler path"
  [[ "$(readlink -f "$configured_compiler")" == "$(readlink -f "$expected_compiler")" ]] ||
    fail "$compiler_contract used $configured_compiler, not the reported compiler $expected_compiler"
  grep -Fq -- "set(CMAKE_C_COMPILER_VERSION \"$expected_compiler_version\")" \
    "$compiler_contract" ||
    fail "$compiler_contract does not record required compiler version $expected_compiler_version"

  command_count="$(grep -c -F '"command"' "$compile_database" || true)"
  [[ "$command_count" =~ ^[1-9][0-9]*$ ]] ||
    fail "$compile_database contains no command-form owned translation units"
  if grep -F '"command"' "$compile_database" | grep -Fv ' -std=c99 ' > /dev/null; then
    fail "$compile_database contains an owned target outside strict C99 mode"
  fi
  if grep -F '"command"' "$compile_database" | grep -Fv ' -Werror ' > /dev/null; then
    fail "$compile_database contains an owned target without the mandatory -Werror policy"
  fi
  require_warning_contract "$compile_database" "$expected_compiler_id" \
    "$expected_build_type"
  if grep -F -- '-std=gnu99' "$compile_database" > /dev/null; then
    fail "$compile_database contains the forbidden GNU99 dialect"
  fi
  if grep -E -- ' (-w|-Wno-[^ "\\]+|-ffreestanding|-fcommon|-fwrapv(-pointer)?|-fno-strict-overflow|-fno-sanitize=[^ "\\]+|-fsanitize-recover=[^ "\\]+|-fomit-frame-pointer|-U( |[^ "\\])[^ "\\]*)' \
    "$compile_database" \
    > /dev/null; then
    fail "$compile_database contains an option that overrides a mandatory diagnostic, language, or sanitizer contract"
  fi
  reject_unreviewed_diagnostic_flags "$compile_database" \
    "$expected_compiler_id" "$expected_build_type"
  if sed 's/ -std=c99 / /g' "$compile_database" |
    grep -E -- ' -std=[^ "\\]+' > /dev/null; then
    fail "$compile_database contains a competing language-dialect option"
  fi
  case "$expected_platform_profile" in
    iso-hosted)
      if grep -E -- '-D[ ]*(_POSIX_C_SOURCE|_FILE_OFFSET_BITS|_WIN32_WINNT|WINVER)=' \
        "$compile_database" > /dev/null; then
        fail "$compile_database exposes a platform API macro in the iso-hosted profile"
      fi
      ;;
    posix-2008)
      if grep -F '"command"' "$compile_database" |
        grep -Fv ' -D_POSIX_C_SOURCE=200809L ' > /dev/null ||
        grep -F '"command"' "$compile_database" |
        grep -Fv ' -D_FILE_OFFSET_BITS=64 ' > /dev/null; then
        fail "$compile_database does not consistently expose the posix-2008 namespace"
      fi
      if sed -e 's/ -D_POSIX_C_SOURCE=200809L / /g' \
        -e 's/ -D_FILE_OFFSET_BITS=64 / /g' "$compile_database" |
        grep -E -- '-D[ ]*(_POSIX_C_SOURCE|_FILE_OFFSET_BITS)=' > /dev/null; then
        fail "$compile_database contains a conflicting posix-2008 feature macro"
      fi
      ;;
    win32)
      if grep -F '"command"' "$compile_database" |
        grep -Fv ' -D_WIN32_WINNT=0x0A00 ' > /dev/null ||
        grep -F '"command"' "$compile_database" |
        grep -Fv ' -DWINVER=0x0A00 ' > /dev/null; then
        fail "$compile_database does not consistently expose the declared win32 namespace"
      fi
      if sed -e 's/ -D_WIN32_WINNT=0x0A00 / /g' \
        -e 's/ -DWINVER=0x0A00 / /g' "$compile_database" |
        grep -E -- '-D[ ]*(_WIN32_WINNT|WINVER)=' > /dev/null; then
        fail "$compile_database contains a conflicting win32 feature macro"
      fi
      ;;
    *) fail "unsupported build-contract platform profile: $expected_platform_profile" ;;
  esac

  if [[ "$expected_sanitizer" == "address-undefined" ]]; then
    if grep -F '"command"' "$compile_database" |
      grep -Fv ' -fsanitize=address,undefined ' > /dev/null; then
      fail "$compile_database contains an owned target without ASan+UBSan instrumentation"
    fi
    if grep -F '"command"' "$compile_database" |
      grep -Fv ' -fno-sanitize-recover=all ' > /dev/null; then
      fail "$compile_database contains recoverable sanitizer instrumentation"
    fi
  else
    if grep -F -- '-fsanitize=' "$compile_database" > /dev/null; then
      fail "$compile_database unexpectedly contains sanitizer instrumentation"
    fi
  fi
}

configure_build_test() {
  local preset="$1"
  local sanitizer="$2"

  printf '[GATE] configure/build/test preset=%s sanitizer=%s\n' "$preset" "$sanitizer"
  clean_preset "$preset"
  cmake --preset "$preset"
  case "$preset" in
    clang-fast) verify_build_contract "$ROOT/build/$preset" "$sanitizer" Debug Clang ;;
    clang-asan-ubsan) verify_build_contract "$ROOT/build/$preset" "$sanitizer" Debug Clang ;;
    clang-release) verify_build_contract "$ROOT/build/$preset" "$sanitizer" Release Clang ;;
    gcc-fast) verify_build_contract "$ROOT/build/$preset" "$sanitizer" Debug GNU ;;
    gcc-release) verify_build_contract "$ROOT/build/$preset" "$sanitizer" Release GNU ;;
    *) fail "no executable build-contract assertion exists for preset: $preset" ;;
  esac
  cmake --build --preset "$preset" --parallel "$JOBS"
  if [[ "$sanitizer" == "address-undefined" ]]; then
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1:strict_string_checks=1 \
      UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
      ctest --preset "$preset" --no-tests=error
  else
    ctest --preset "$preset" --no-tests=error
  fi
}

run_package_consumer() {
  local install_prefix="$ROOT/build/package-install"
  local consumer_build="$ROOT/build/package-consumer"

  printf '[GATE] static/shared install and external package consumers\n'
  clean_preset clang-package
  cmake -E remove_directory "$install_prefix"
  cmake -E remove_directory "$consumer_build"
  cmake --preset clang-package
  verify_build_contract "$ROOT/build/clang-package" none RelWithDebInfo Clang
  cmake --build --preset clang-package --parallel "$JOBS"
  cmake --install "$ROOT/build/clang-package" --prefix "$install_prefix"
  cmake -S "$ROOT/standards-tests/consumer" -B "$consumer_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_PREFIX_PATH="$install_prefix"
  cmake --build "$consumer_build" --parallel "$JOBS"
  "$consumer_build/consumer_static"
  LD_LIBRARY_PATH="$install_prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$consumer_build/consumer_shared"
}

run_native() {
  local clang_version
  local clang_reported_version

  require_tool clang
  clang_version="$(clang --version | head -n 1)"
  clang_reported_version="$(awk '{for (i = 1; i < NF; i++) if ($i == "version") {print $(i + 1); exit}}' <<< "$clang_version")"
  require_exact_version Clang "$REQUIRED_CLANG_VERSION" "$clang_reported_version"
  printf '[INFO] compiler: %s\n' "$clang_version"

  configure_build_test clang-fast none
  configure_build_test clang-asan-ubsan address-undefined
  configure_build_test clang-release none
  run_package_consumer
}

run_portability() {
  local gcc_version
  local gcc_reported_version

  require_tool gcc
  gcc_version="$(gcc --version | head -n 1)"
  gcc_reported_version="${gcc_version##* }"
  require_exact_version GCC "$REQUIRED_GCC_VERSION" "$gcc_reported_version"
  printf '[INFO] compiler: %s\n' "$gcc_version"

  configure_build_test gcc-fast none
  configure_build_test gcc-release none
  "$ROOT/standards-tests/run.sh" gcc
}

run_mingw() {
  require_tool x86_64-w64-mingw32-gcc
  require_tool x86_64-w64-mingw32-windres
  printf '[INFO] exploratory compiler: %s\n' \
    "$(x86_64-w64-mingw32-gcc --version | head -n 1)"
  printf '[GATE] MinGW-w64 win32 profile (compile/link only; target is not executed)\n'
  clean_preset mingw
  cmake --preset mingw
  verify_build_contract "$ROOT/build/mingw" none Release GNU win32
  cmake --build --preset mingw --parallel "$JOBS"
  grep -F -- "standards-tests/platform/win32-api.c" \
    "$ROOT/build/mingw/compile_commands.json" > /dev/null ||
    fail "MinGW gate did not compile the version-gated Win32 API fixture"
}

main() {
  local cmake_version
  local cmake_reported_version
  local ninja_version

  require_tool cmake
  require_tool ninja
  cmake_version="$(cmake --version | head -n 1)"
  ninja_version="$(ninja --version)"
  cmake_reported_version="${cmake_version##* }"
  require_exact_version CMake "$REQUIRED_CMAKE_VERSION" "$cmake_reported_version"
  require_exact_version Ninja "$REQUIRED_NINJA_VERSION" "$ninja_version"
  printf '[INFO] build tools: %s; Ninja %s\n' "$cmake_version" "$ninja_version"

  case "$MODE" in
    native) run_native ;;
    portability) run_portability ;;
    mingw) run_mingw ;;
    verify-preset-contract)
      (($# == 5 || $# == 6)) ||
        fail "usage: $0 verify-preset-contract BUILD_DIR SANITIZER BUILD_TYPE COMPILER_ID [PLATFORM_PROFILE]"
      verify_build_contract "$2" "$3" "$4" "$5" "${6:-iso-hosted}"
      ;;
    *) fail "usage: $0 [native|portability|mingw|verify-preset-contract ...]" ;;
  esac
  printf '[PASS] C %s gate completed every required stage\n' "$MODE"
}

main "$@"
