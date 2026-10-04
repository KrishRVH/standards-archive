#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2> /dev/null || nproc 2> /dev/null || echo 4)}"

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

note() {
  printf '[TEST] %s\n' "$*"
}

require_tool() {
  command -v "$1" > /dev/null 2>&1 || fail "required tool is unavailable: $1"
}

expect_failure() {
  local label="$1"
  shift

  if "$@" > /dev/null 2>&1; then
    fail "$label unexpectedly succeeded"
  fi
  note "$label: rejected as expected"
}

expect_failure_containing() {
  local label="$1"
  local expected_text="$2"
  local output_file="$3"
  shift 3

  if "$@" > "$output_file" 2>&1; then
    fail "$label unexpectedly succeeded"
  fi
  if ! grep -F "$expected_text" "$output_file" > /dev/null; then
    sed -n '1,160p' "$output_file" >&2
    fail "$label failed without the expected diagnostic: $expected_text"
  fi
  note "$label: rejected as expected ($expected_text)"
}

expect_success_containing() {
  local label="$1"
  local expected_text="$2"
  local output_file="$3"
  shift 3

  if ! "$@" > "$output_file" 2>&1; then
    sed -n '1,160p' "$output_file" >&2
    fail "$label unexpectedly failed"
  fi
  if ! grep -F "$expected_text" "$output_file" > /dev/null; then
    sed -n '1,160p' "$output_file" >&2
    fail "$label succeeded without the expected diagnostic: $expected_text"
  fi
  note "$label: warning observed ($expected_text)"
}

require_file_text() {
  local file="$1"
  local expected_text="$2"

  grep -F -- "$expected_text" "$file" > /dev/null ||
    fail "$file does not contain required text: $expected_text"
}

require_compile_flag() {
  local compile_database="$1"
  local flag="$2"

  grep -F -- " $flag " "$compile_database" > /dev/null ||
    fail "$compile_database does not contain the exact compile flag: $flag"
}

reject_file_text() {
  local file="$1"
  local rejected_text="$2"

  if grep -F -- "$rejected_text" "$file" > /dev/null; then
    fail "$file contains forbidden text: $rejected_text"
  fi
}

strict_compile() {
  local compiler="$1"
  local source="$2"
  local output="$3"

  "$compiler" -std=c99 -Wall -Wextra -Wpedantic -Wconversion -Wshadow \
    -Werror "$source" -o "$output"
}

strict_compile_posix() {
  local compiler="$1"
  local source="$2"
  local output="$3"

  "$compiler" -std=c99 -D_POSIX_C_SOURCE=200809L -D_FILE_OFFSET_BITS=64 \
    -Wall -Wextra -Wpedantic -Wconversion -Wshadow -Werror \
    "$source" -o "$output"
}

configure_platform_fixture() {
  local build_dir="$1"
  local platform_profile="$2"
  local source_file="$3"

  cmake -S "$ROOT" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER=clang \
    -DPROJECT_BUILD_CLI=ON \
    -DPROJECT_CLI_SOURCES="$source_file" \
    -DPROJECT_PLATFORM_PROFILE="$platform_profile" \
    -DPROJECT_WERROR=ON \
    -DBUILD_TESTING=OFF
}

configure_cli_fixture() {
  local build_dir="$1"
  local compiler="$2"
  local source_file="$3"
  shift 3

  cmake -S "$ROOT" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER="$compiler" \
    -DPROJECT_BUILD_CLI=ON \
    -DPROJECT_CLI_SOURCES="$source_file" \
    -DPROJECT_PLATFORM_PROFILE=iso-hosted \
    -DPROJECT_WERROR=ON \
    -DBUILD_TESTING=OFF \
    "$@"
}

configure_analyzer_fixture() {
  local build_dir="$1"
  local source_file="$2"

  cmake -S "$ROOT/standards-tests/analyzer" -B "$build_dir" -G Ninja \
    -DCMAKE_C_COMPILER=clang \
    -DFIXTURE_SOURCE="$source_file" > /dev/null
}

run_posix_declaration_contract() {
  local scratch_dir="$1"
  local compiler="$2"
  local fixture="$ROOT/standards-tests/platform/posix-contract.c"

  expect_failure_containing \
    "$compiler rejects undeclared POSIX APIs under strict C99" \
    "CLOCK_MONOTONIC" "$scratch_dir/$compiler-posix-under-iso.log" \
    strict_compile "$compiler" "$fixture" "$scratch_dir/$compiler-iso-posix"
  strict_compile_posix \
    "$compiler" "$fixture" "$scratch_dir/$compiler-declared-posix"
}

run_platform_contract_tests() {
  local scratch_dir="$1"
  local fixture="$ROOT/standards-tests/platform/posix-contract.c"
  local posix_build="$scratch_dir/posix-contract"
  local iso_build="$scratch_dir/iso-contract"

  note "POSIX profile supplies the declared API and large-file contracts"
  configure_platform_fixture "$posix_build" posix-2008 "$fixture"
  "$ROOT/c-build.sh" verify-preset-contract \
    "$posix_build" none Debug Clang posix-2008
  cmake --build "$posix_build" --parallel "$JOBS"
  "$posix_build/project_cli"
  note "POSIX file-offset and monotonic-clock runtime paths passed"

  note "ISO-only profile does not silently expose POSIX interfaces"
  configure_platform_fixture "$iso_build" iso-hosted "$fixture"
  "$ROOT/c-build.sh" verify-preset-contract "$iso_build" none Debug Clang
  expect_failure_containing "POSIX interfaces under iso-hosted" \
    "CLOCK_MONOTONIC" "$scratch_dir/posix-under-iso.log" \
    cmake --build "$iso_build" --parallel "$JOBS"
}

run_runtime_contract_tests() {
  local scratch_dir="$1"
  local fixture_root="$ROOT/standards-tests/fixtures/runtime"
  local fixture

  for fixture in argument-contract allocation-size ownership-cleanup short-read; do
    local build_dir="$scratch_dir/runtime-$fixture"
    note "Runtime contract passes: $fixture"
    configure_cli_fixture "$build_dir" clang "$fixture_root/$fixture.c" \
      -DPROJECT_SANITIZER=address-undefined
    cmake --build "$build_dir" --parallel "$JOBS"
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1:strict_string_checks=1 \
      UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
      "$build_dir/project_cli"
  done
}

run_sanitizer_detection_tests() {
  local scratch_dir="$1"
  local fixture_root="$ROOT/standards-tests/fixtures/sanitizer"
  local fixture
  local expected_text

  for fixture in heap-buffer-overflow signed-overflow; do
    local build_dir="$scratch_dir/sanitizer-$fixture"
    configure_cli_fixture "$build_dir" clang "$fixture_root/$fixture.c" \
      -DPROJECT_SANITIZER=address-undefined
    cmake --build "$build_dir" --parallel "$JOBS"
    if [[ "$fixture" == "heap-buffer-overflow" ]]; then
      expected_text="AddressSanitizer"
    else
      expected_text="runtime error"
    fi
    expect_failure_containing "sanitizer fixture $fixture" "$expected_text" \
      "$scratch_dir/sanitizer-$fixture.log" \
      env ASAN_OPTIONS=detect_leaks=1:halt_on_error=1:strict_string_checks=1 \
      UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
      "$build_dir/project_cli"
  done
}

run_format_tests() {
  local scratch_dir="$1"
  local fixture_root="$ROOT/standards-tests/format"
  local source_dir="$scratch_dir/format source"
  local checkout_dir="$scratch_dir/format checkout"

  note "clang-format golden layout and idempotence"
  clang-format --style="file:$ROOT/.clang-format" --assume-filename=representative.c \
    "$fixture_root/representative.c.in" > "$scratch_dir/formatted.c"
  cmp "$fixture_root/representative.c.expected" "$scratch_dir/formatted.c" ||
    fail "clang-format output differs from the golden fixture"
  clang-format --style="file:$ROOT/.clang-format" "$scratch_dir/formatted.c" > \
    "$scratch_dir/formatted-twice.c"
  cmp "$scratch_dir/formatted.c" "$scratch_dir/formatted-twice.c" ||
    fail "clang-format output is not idempotent"
  expect_failure_containing "wrong clang-format version" "clang-format 22.1.8 is required" \
    "$scratch_dir/wrong-format-version.log" \
    env C_CLANG_FORMAT=/usr/bin/true "$ROOT/c-format.sh" check "$ROOT"

  note "clang-format override accepts an executable path with spaces"
  mkdir "$source_dir"
  cp "$ROOT/.clang-format" "$source_dir/.clang-format"
  cp "$scratch_dir/formatted.c" "$source_dir/example.c"
  ln -s "$(command -v clang-format)" "$scratch_dir/clang format"
  C_CLANG_FORMAT="$scratch_dir/clang format" "$ROOT/c-format.sh" check "$source_dir"

  note "clang-format skips vendored sources in a git checkout"
  mkdir -p "$checkout_dir/src" "$checkout_dir/third_party/upstream" "$checkout_dir/vendor"
  cp "$ROOT/.clang-format" "$checkout_dir/.clang-format"
  cp "$scratch_dir/formatted.c" "$checkout_dir/src/example.c"
  printf 'int  upstream ( void ){return 0;}\n' > "$checkout_dir/third_party/upstream/upstream.c"
  printf 'int  upstream ( void ){return 0;}\n' > "$checkout_dir/vendor/upstream.c"
  git init -q "$checkout_dir"
  "$ROOT/c-format.sh" check "$checkout_dir"
}

run_analyzer_tests() {
  local scratch_dir="$1"
  local analyzer_root="$ROOT/standards-tests/analyzer"
  local positive_build="$scratch_dir/analyzer-positive"
  local duplicate_build="$scratch_dir/analyzer-duplicate"
  local zero_build="$scratch_dir/analyzer-zero"
  local fixture
  local expected

  note "Direct clang-tidy accepts a reasoned cohesive fatal diagnostic"
  configure_analyzer_fixture "$positive_build" \
    "$analyzer_root/fixtures/cohesive-diagnostic.c"
  C_QUALITY_SHOW_CHECKS=0 "$ROOT/c-quality.sh" hard "$ROOT" "$positive_build"

  note "Analyzer overrides accept executable paths with spaces"
  ln -s "$(command -v clang-tidy)" "$scratch_dir/clang tidy"
  ln -s "$(command -v run-clang-tidy)" "$scratch_dir/run clang tidy"
  C_CLANG_TIDY="$scratch_dir/clang tidy" \
    C_RUN_CLANG_TIDY="$scratch_dir/run clang tidy" \
    C_QUALITY_SHOW_CHECKS=0 "$ROOT/c-quality.sh" hard "$ROOT" "$positive_build"

  while IFS='|' read -r fixture expected; do
    local build_dir="$scratch_dir/analyzer-${fixture// /-}"
    local source_file="$analyzer_root/fixtures/$fixture.c"
    if [[ "$fixture" == "header-source-with-spaces" ]]; then
      source_file="$analyzer_root/fixtures/header source with spaces.c"
    fi
    configure_analyzer_fixture "$build_dir" "$source_file"
    expect_failure_containing "analyzer fixture $fixture" "$expected" \
      "$scratch_dir/analyzer-${fixture// /-}.log" \
      env C_QUALITY_SHOW_CHECKS=0 "$ROOT/c-quality.sh" hard "$ROOT" "$build_dir"
  done << 'EOF'
double-free|clang-analyzer-unix.Malloc
use-after-free|clang-analyzer-unix.Malloc
leak-on-path|clang-analyzer-unix.Malloc
null-dereference|clang-analyzer-core.NullDereference
uninitialized-read|clang-analyzer-core.uninitialized.UndefReturn
invalid-shift|clang-analyzer-core.BitwiseShift
mismatched-cleanup|clang-analyzer-unix.Stream
fragmented-diagnostic|cert-err33-c
missing-braces|readability-braces-around-statements
header-source-with-spaces|clang-analyzer-unix.Malloc
EOF

  mkdir "$scratch_dir/missing-cdb"
  expect_failure_containing "missing compilation database" \
    "mandatory analysis requires" "$scratch_dir/missing-cdb.log" \
    "$ROOT/c-quality.sh" hard "$ROOT" "$scratch_dir/missing-cdb"
  expect_failure_containing "missing mandatory clang-tidy" \
    "required tool is unavailable" "$scratch_dir/missing-tidy.log" \
    env C_CLANG_TIDY=clang-tidy-does-not-exist \
    "$ROOT/c-quality.sh" hard "$ROOT" "$positive_build"
  expect_failure_containing "wrong clang-tidy version or executable" \
    "clang-tidy 22.1.8 is required" "$scratch_dir/wrong-tidy.log" \
    env C_CLANG_TIDY=clangd \
    "$ROOT/c-quality.sh" hard "$ROOT" "$positive_build"
  mkdir "$zero_build"
  printf '%s\n' \
    '[' \
    '  {' \
    '    "directory": ".",' \
    '    "command": "clang -c only-a-header.h",' \
    '    "file": "only-a-header.h"' \
    '  }' \
    ']' > "$zero_build/compile_commands.json"
  expect_failure_containing "compilation database with zero C translation units" \
    "analysis selected no .c translation units" "$scratch_dir/zero-cdb.log" \
    env C_QUALITY_SHOW_CHECKS=0 "$ROOT/c-quality.sh" hard "$ROOT" \
    "$zero_build"
  cmake -S "$analyzer_root/duplicate-cdb" -B "$duplicate_build" -G Ninja \
    -DCMAKE_C_COMPILER=clang > /dev/null
  expect_failure_containing "compilation database with duplicate source commands" \
    "one unambiguous C command per source" \
    "$scratch_dir/duplicate-cdb.log" \
    env C_QUALITY_SHOW_CHECKS=0 "$ROOT/c-quality.sh" hard "$ROOT" \
    "$duplicate_build"
}

run_cmake_policy_tests() {
  local scratch_dir="$1"
  local no_tests_build="$scratch_dir/no-tests"
  local contract_build="$scratch_dir/preset-contract"
  local namespace_build="$scratch_dir/preset-namespace-leak"
  local override_build="$scratch_dir/preset-warning-override"
  local expanded_build="$scratch_dir/preset-warning-expansion"
  local interface_target_build="$scratch_dir/interface-target"
  local stripped_target_build="$scratch_dir/preset-stripped-target"
  local werror_off_build="$scratch_dir/preset-werror-off"
  local unregistered_build="$scratch_dir/unregistered-target"
  local excluded_build="$scratch_dir/excluded-directory"
  local reasonless_build="$scratch_dir/reasonless-excluded-directory"
  local self_excluded_build="$scratch_dir/self-excluded-directory"

  expect_failure_containing "unsupported compiler" "Unsupported C compiler 'UnknownVendor'" \
    "$scratch_dir/unsupported-compiler.log" \
    cmake -P "$ROOT/standards-tests/cmake/unsupported-compiler.cmake"

  cmake -S "$ROOT/standards-tests/cmake/no-tests" -B "$no_tests_build" -G Ninja \
    -DCMAKE_C_COMPILER=clang > /dev/null
  cmake --build "$no_tests_build" --parallel "$JOBS" > /dev/null
  expect_failure_containing "mandatory CTest stage with no registered tests" \
    "No tests were found" "$scratch_dir/no-tests.log" \
    ctest --test-dir "$no_tests_build" --no-tests=error
  require_file_text "$ROOT/c-build.sh" "--no-tests=error"

  expect_failure_containing "owned target missing the standards helper" \
    "did not call project_apply_common" "$scratch_dir/unregistered-target.log" \
    cmake -S "$ROOT/standards-tests/cmake/unregistered-target" \
    -B "$unregistered_build" -G Ninja -DCMAKE_C_COMPILER=clang
  expect_failure_containing "interface target passed to the compiled-target helper" \
    "project_apply_common requires an owned compiled target" \
    "$scratch_dir/interface-target.log" \
    cmake -S "$ROOT/standards-tests/cmake/interface-target" \
    -B "$interface_target_build" -G Ninja -DCMAKE_C_COMPILER=clang
  cmake -S "$ROOT/standards-tests/cmake/excluded-directory" \
    -B "$excluded_build" -G Ninja -DCMAKE_C_COMPILER=clang > /dev/null
  expect_failure_containing "third-party directory exception without a reason" \
    "requires a nonempty reason" "$scratch_dir/reasonless-exclusion.log" \
    cmake -S "$ROOT/standards-tests/cmake/excluded-directory" \
    -B "$reasonless_build" -G Ninja -DCMAKE_C_COMPILER=clang \
    -DTEST_MISSING_REASON=ON
  expect_failure_containing "owned root tries to exempt itself" \
    "cannot exempt its calling directory" "$scratch_dir/self-exclusion.log" \
    cmake -S "$ROOT/standards-tests/cmake/excluded-directory" \
    -B "$self_excluded_build" -G Ninja -DCMAKE_C_COMPILER=clang \
    -DTEST_SELF_EXCLUSION=ON

  cmake -S "$ROOT/standards-tests/cmake/stripped-target" \
    -B "$stripped_target_build" -G Ninja -DCMAKE_C_COMPILER=clang \
    -DCMAKE_BUILD_TYPE=Debug > /dev/null
  expect_failure_containing "one owned target replaces its warning policy" \
    "without required flag: -Wall" "$scratch_dir/preset-stripped-target.log" \
    "$ROOT/c-build.sh" verify-preset-contract "$stripped_target_build" \
    none Debug Clang

  configure_cli_fixture "$contract_build" clang \
    "$ROOT/standards-tests/compiler/format-wrapper.c"
  "$ROOT/c-build.sh" verify-preset-contract "$contract_build" none Debug Clang
  expect_failure_containing "preset sanitizer label without instrumentation" \
    "PROJECT_SANITIZER:STRING=address-undefined" \
    "$scratch_dir/preset-sanitizer-contract.log" \
    "$ROOT/c-build.sh" verify-preset-contract "$contract_build" \
    address-undefined Debug Clang
  expect_failure_containing "preset compiler-family mislabel" \
    "required compiler family: GNU" "$scratch_dir/preset-compiler-contract.log" \
    "$ROOT/c-build.sh" verify-preset-contract "$contract_build" none Debug GNU

  configure_cli_fixture "$werror_off_build" clang \
    "$ROOT/standards-tests/compiler/format-wrapper.c" \
    -DPROJECT_WERROR=OFF
  expect_failure_containing "mandatory preset without Werror" \
    "PROJECT_WERROR:BOOL=ON" "$scratch_dir/preset-werror-contract.log" \
    "$ROOT/c-build.sh" verify-preset-contract "$werror_off_build" none Debug Clang

  configure_cli_fixture "$namespace_build" clang \
    "$ROOT/standards-tests/compiler/format-wrapper.c" \
    -DCMAKE_C_FLAGS=-D_POSIX_C_SOURCE=200809L
  expect_failure_containing "ISO preset with leaked POSIX namespace" \
    "platform API macro in the iso-hosted profile" \
    "$scratch_dir/preset-namespace-contract.log" \
    "$ROOT/c-build.sh" verify-preset-contract "$namespace_build" none Debug Clang

  configure_cli_fixture "$override_build" clang \
    "$ROOT/standards-tests/compiler/format-wrapper.c" \
    -DCMAKE_C_FLAGS=-Wno-conversion
  expect_failure_containing "mandatory warning overridden after enablement" \
    "overrides a mandatory diagnostic" \
    "$scratch_dir/preset-warning-override.log" \
    "$ROOT/c-build.sh" verify-preset-contract "$override_build" none Debug Clang

  configure_cli_fixture "$expanded_build" clang \
    "$ROOT/standards-tests/compiler/format-wrapper.c" \
    -DCMAKE_C_FLAGS=-Weverything
  expect_failure_containing "unreviewed warning expansion after policy" \
    "unreviewed diagnostic flag: -Weverything" \
    "$scratch_dir/preset-warning-expansion.log" \
    "$ROOT/c-build.sh" verify-preset-contract "$expanded_build" none Debug Clang
}

run_clang_warning_tests() {
  local scratch_dir="$1"
  local fixture_root="$ROOT/standards-tests/fixtures/compile"
  local fixture

  for fixture in clang-comma vla sign-conversion format-mismatch gnu-extension; do
    local build_dir="$scratch_dir/clang-$fixture"
    configure_cli_fixture "$build_dir" clang "$fixture_root/$fixture.c"
    expect_failure "Clang hard warning fixture $fixture" \
      cmake --build "$build_dir" --parallel "$JOBS"
  done
}

run_gcc_warning_tests() {
  local scratch_dir="$1"
  local build_dir="$scratch_dir/gcc-duplicated-condition"

  require_tool gcc
  configure_cli_fixture "$build_dir" gcc \
    "$ROOT/standards-tests/fixtures/compile/gcc-duplicated-condition.c"
  expect_failure "GCC duplicated condition" \
    cmake --build "$build_dir" --parallel "$JOBS"
}

assert_compile_flag_contract() {
  local scratch_dir="$1"
  local compiler="$2"
  local build_type="$3"
  local family_contract="$4"
  local build_dir="$scratch_dir/flags-$compiler-${build_type,,}"
  local compile_database="$build_dir/compile_commands.json"
  local flag

  note "$compiler $build_type CMake warning contract"
  configure_cli_fixture "$build_dir" "$compiler" \
    "$ROOT/standards-tests/compiler/format-wrapper.c" \
    -DCMAKE_BUILD_TYPE="$build_type"
  cmake --build "$build_dir" --parallel "$JOBS" > /dev/null
  require_compile_flag "$compile_database" "-std=c99"
  reject_file_text "$compile_database" "-std=gnu99"

  while IFS= read -r flag; do
    [[ -n "$flag" && "$flag" != \#* ]] || continue
    require_compile_flag "$compile_database" "$flag"
  done < "$ROOT/standards-tests/compiler/common-flags.txt"
  while IFS= read -r flag; do
    [[ -n "$flag" && "$flag" != \#* ]] || continue
    require_compile_flag "$compile_database" "$flag"
  done < "$ROOT/standards-tests/compiler/$family_contract"

  if [[ "$compiler" == "gcc" && "$build_type" == "Debug" ]]; then
    reject_file_text "$compile_database" " -Wnull-dereference "
  fi
}

verify_warning_resolution() {
  local scratch_dir="$1"
  local compiler="$2"
  local configuration="$3"
  local profile="$compiler-${configuration,,}"
  local output_file="$scratch_dir/$profile-warning-resolution.txt"
  local expected_lines
  local expected_hash
  local actual_lines
  local actual_hash
  local -a common_flags=()
  local -a family_flags=()
  local -a optimization=()

  require_tool sha256sum
  mapfile -t common_flags < "$ROOT/standards-tests/compiler/common-flags.txt"
  if [[ "$compiler" == "clang" ]]; then
    require_tool diagtool
    mapfile -t family_flags < "$ROOT/standards-tests/compiler/clang-flags.txt"
    LC_ALL=C diagtool show-enabled -x c -std=c99 \
      "${common_flags[@]}" "${family_flags[@]}" \
      "$ROOT/standards-tests/compiler/format-wrapper.c" \
      > "$output_file" 2> /dev/null
  else
    mapfile -t family_flags \
      < "$ROOT/standards-tests/compiler/gcc-${configuration,,}-flags.txt"
    if [[ "$configuration" == "Release" ]]; then
      optimization=(-O2)
    fi
    LC_ALL=C gcc -Q --help=warnings -x c -std=c99 \
      "${common_flags[@]}" "${family_flags[@]}" "${optimization[@]}" \
      -c "$ROOT/standards-tests/compiler/format-wrapper.c" -o /dev/null \
      > "$output_file" 2> /dev/null
  fi

  IFS='|' read -r _ expected_lines expected_hash < <(
    grep -F "$profile|" \
      "$ROOT/standards-tests/compiler/warning-resolution.txt"
  )
  [[ -n "$expected_lines" && -n "$expected_hash" ]] ||
    fail "warning resolution contract is missing profile: $profile"
  actual_lines="$(wc -l < "$output_file")"
  actual_hash="$(sha256sum "$output_file" | cut -d' ' -f1)"
  [[ "$actual_lines" == "$expected_lines" && "$actual_hash" == "$expected_hash" ]] ||
    fail "$profile resolved warning set drifted: expected $expected_lines/$expected_hash, found $actual_lines/$actual_hash"
  note "$profile resolved warning set: $actual_lines lines, sha256 $actual_hash"
}

run_warning_diagnostic_matrix() {
  local scratch_dir="$1"
  local compiler="$2"
  local applicability
  local case_macro
  local enabling_flag
  local hardening_mode
  local expected
  local extra_arguments

  note "$compiler hard-warning diagnostic matrix"
  while IFS='|' read -r applicability case_macro enabling_flag hardening_mode \
    expected extra_arguments; do
    [[ -n "$applicability" && "$applicability" != \#* ]] || continue
    if [[ "$applicability" != "both" && "$applicability" != "$compiler" ]]; then
      continue
    fi

    local -a extra=()
    if [[ -n "$extra_arguments" ]]; then
      read -r -a extra <<< "$extra_arguments"
    fi
    if [[ "$hardening_mode" == "exact" ]]; then
      expect_failure_containing "$compiler exact hard diagnostic $case_macro" \
        "$expected" "$scratch_dir/$compiler-$case_macro-hard.log" \
        "$compiler" -std=c99 -c "-D$case_macro" "$enabling_flag" \
        "${extra[@]}" "$ROOT/standards-tests/compiler/warning-fixtures.c" \
        -o /dev/null
    else
      [[ "$hardening_mode" == "blanket" ]] ||
        fail "unknown warning hardening mode: $hardening_mode"
      expect_success_containing "$compiler warning signal $case_macro" "$expected" \
        "$scratch_dir/$compiler-$case_macro-warning.log" \
        "$compiler" -std=c99 -c "-D$case_macro" "$enabling_flag" \
        "${extra[@]}" "$ROOT/standards-tests/compiler/warning-fixtures.c" \
        -o /dev/null
      expect_failure_containing "$compiler Werror promotion $case_macro" "error:" \
        "$scratch_dir/$compiler-$case_macro-hard.log" \
        "$compiler" -std=c99 -c "-D$case_macro" "$enabling_flag" -Werror \
        "${extra[@]}" "$ROOT/standards-tests/compiler/warning-fixtures.c" \
        -o /dev/null
    fi
  done < "$ROOT/standards-tests/compiler/warning-cases.tsv"
}

run_common_definition_contract() {
  local scratch_dir="$1"
  local compiler="$2"
  local fixture_root="$ROOT/standards-tests/compiler"
  # The wording belongs to the linker: GNU ld says "multiple definition";
  # lld and Apple ld64 say "duplicate symbol". grep -F matches either line.
  local common_diagnostic=$'multiple definition\nduplicate symbol'

  note "$compiler tentative-definition linkage contract"
  "$compiler" -std=c99 -fcommon "$fixture_root/common-definition-a.c" \
    "$fixture_root/common-definition-b.c" -o "$scratch_dir/$compiler-common"
  expect_failure_containing "$compiler fno-common definition ownership" \
    "$common_diagnostic" "$scratch_dir/$compiler-fno-common.log" \
    "$compiler" -std=c99 -fno-common "$fixture_root/common-definition-a.c" \
    "$fixture_root/common-definition-b.c" -o "$scratch_dir/$compiler-no-common"
}

run_clang_warning_contracts() {
  local scratch_dir="$1"

  assert_compile_flag_contract "$scratch_dir" clang Debug clang-flags.txt
  verify_warning_resolution "$scratch_dir" clang Debug
  run_warning_diagnostic_matrix "$scratch_dir" clang
  run_common_definition_contract "$scratch_dir" clang
}

run_gcc_warning_contracts() {
  local scratch_dir="$1"

  assert_compile_flag_contract "$scratch_dir" gcc Debug gcc-debug-flags.txt
  assert_compile_flag_contract "$scratch_dir" gcc Release gcc-release-flags.txt
  verify_warning_resolution "$scratch_dir" gcc Debug
  verify_warning_resolution "$scratch_dir" gcc Release
  run_warning_diagnostic_matrix "$scratch_dir" gcc
  run_common_definition_contract "$scratch_dir" gcc
}

# Each group configures its own build directories and log files under the
# shared scratch directory and never writes to the repository, so the groups
# run concurrently. Every group keeps its own log; the logs replay in the
# listed order after all groups finish, so diagnostics stay readable and one
# failure never hides another group's result.
run_groups_concurrently() {
  local scratch_dir="$1"
  shift
  local group
  local index
  local status=0
  local -a pids=()

  for group in "$@"; do
    "$group" "$scratch_dir" > "$scratch_dir/group-$group.log" 2>&1 &
    pids+=("$!")
  done

  for index in "${!pids[@]}"; do
    wait "${pids[$index]}" || status=1
    cat "$scratch_dir/group-${*:index+1:1}.log"
  done

  ((status == 0)) || fail "one or more concurrent regression groups failed"
}

main() {
  require_tool cmake
  require_tool ninja

  scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/c-standards.XXXXXX")"
  trap 'cmake -E remove_directory "$scratch_dir"' EXIT

  case "${1:-native}" in
    native)
      require_tool clang
      require_tool clang-format
      require_tool git
      printf '[INFO] clang: %s\n' "$(clang --version | head -n 1)"
      printf '[INFO] cmake: %s\n' "$(cmake --version | head -n 1)"
      run_posix_declaration_contract "$scratch_dir" clang
      run_format_tests "$scratch_dir"
      run_groups_concurrently "$scratch_dir" \
        run_platform_contract_tests \
        run_cmake_policy_tests \
        run_clang_warning_tests \
        run_clang_warning_contracts \
        run_runtime_contract_tests \
        run_sanitizer_detection_tests \
        run_analyzer_tests
      ;;
    gcc)
      require_tool gcc
      printf '[INFO] gcc: %s\n' "$(gcc --version | head -n 1)"
      run_posix_declaration_contract "$scratch_dir" gcc
      run_gcc_warning_tests "$scratch_dir"
      run_gcc_warning_contracts "$scratch_dir"
      ;;
    *) fail "usage: $0 [native|gcc]" ;;
  esac
  note "standards regressions passed"
}

main "$@"
