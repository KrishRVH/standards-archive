#!/usr/bin/env bats

setup() {
  # shellcheck disable=SC2154 # Bats defines BATS_TEST_DIRNAME at runtime.
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "checks every filename in Git and non-Git projects" {
  # shellcheck disable=SC2154 # Bats defines BATS_TEST_TMPDIR at runtime.
  local workspace="${BATS_TEST_TMPDIR}/filename-discovery"
  local mode name
  local -a names=('ordinary.sh' 'space name.sh' 'é.sh' 'quote"file.sh' $'line\nbreak.sh')
  for mode in plain git; do
    for name in "${names[@]}"; do
      mkdir -p "${workspace}/${mode}/scripts"
      printf '#!/usr/bin/env bash\nif\n' > "${workspace}/${mode}/scripts/${name}"
      if [ "${mode}" = git ]; then
        git init --quiet "${workspace}/${mode}"
        git -C "${workspace}/${mode}" add .
      fi

      run bash -c 'cd "$1" && "$2" syntax' -- \
        "${workspace}/${mode}" "${PROJECT_ROOT}/scripts/shell-standards.sh"

      [[ "${status}" -ne 0 ]]
      [[ "${output}" != *"No standalone shell scripts"* ]]
      rm -f "${workspace}/${mode}/scripts/${name}"
    done
  done
}

@test "rejects executable glue without a shebang" {
  # shellcheck disable=SC2154 # Bats defines BATS_TEST_TMPDIR at runtime.
  local workspace="${BATS_TEST_TMPDIR}/missing-shebang"
  mkdir -p "${workspace}/scripts"
  printf 'printf "deploy\\n"\n' > "${workspace}/scripts/deploy"
  chmod +x "${workspace}/scripts/deploy"

  run bash -c 'cd "$1" && "$2" policy' -- \
    "${workspace}" "${PROJECT_ROOT}/scripts/shell-standards.sh"

  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"scripts/deploy: project glue scripts need a recognized shell shebang."* ]]
}

@test "checks root filenames beginning with a dash as paths" {
  # shellcheck disable=SC2154 # Bats defines BATS_TEST_TMPDIR at runtime.
  local workspace="${BATS_TEST_TMPDIR}/leading-dash"
  local command
  mkdir -p "${workspace}"
  printf '#!/usr/bin/env bash\nprintf "hello\\n"\n' > "${workspace}/-leading.sh"
  printf '#!/usr/bin/env bats\n@test "runs a root Bats file" { true; }\n' > "${workspace}/-leading.bats"

  for command in fmt fmt-check lint syntax test; do
    run bash -c 'cd "$1" && "$2" "$3"' -- \
      "${workspace}" "${PROJECT_ROOT}/scripts/shell-standards.sh" "${command}"
    [[ "${status}" -eq 0 ]]
  done
}

@test "fails when Git cannot enumerate project files" {
  # shellcheck disable=SC2154 # Bats defines BATS_TEST_TMPDIR at runtime.
  local workspace="${BATS_TEST_TMPDIR}/broken-index"
  mkdir -p "${workspace}/scripts"
  printf '#!/usr/bin/env bash\nif\n' > "${workspace}/scripts/broken.sh"
  git init --quiet "${workspace}"
  printf 'corrupt' > "${workspace}/.git/index"

  run bash -c 'cd "$1" && "$2" syntax' -- \
    "${workspace}" "${PROJECT_ROOT}/scripts/shell-standards.sh"

  [[ "${status}" -ne 0 ]]
  [[ "${output}" != *"No standalone shell scripts"* ]]
}

@test "accepts a shebang without a trailing newline" {
  # shellcheck disable=SC2154 # Bats defines BATS_TEST_TMPDIR at runtime.
  local workspace="${BATS_TEST_TMPDIR}/unterminated-shebang"
  mkdir -p "${workspace}/scripts"
  printf '#!/usr/bin/env bash' > "${workspace}/scripts/deploy"
  chmod +x "${workspace}/scripts/deploy"

  run bash -c 'cd "$1" && "$2" policy' -- \
    "${workspace}" "${PROJECT_ROOT}/scripts/shell-standards.sh"

  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

@test "ignores non-shell shebangs containing a shell name" {
  # shellcheck disable=SC2154 # Bats defines BATS_TEST_TMPDIR at runtime.
  local workspace="${BATS_TEST_TMPDIR}/lookalike-shebang"
  mkdir -p "${workspace}/scripts"
  printf '#!/usr/bin/bashful\nif\n' > "${workspace}/scripts/deploy"
  chmod +x "${workspace}/scripts/deploy"

  run bash -c 'cd "$1" && "$2" lint' -- \
    "${workspace}" "${PROJECT_ROOT}/scripts/shell-standards.sh"

  [[ "${status}" -eq 0 ]]
}

@test "skips experimental zsh formatting" {
  # shellcheck disable=SC2154 # Bats defines BATS_TEST_TMPDIR at runtime.
  local workspace="${BATS_TEST_TMPDIR}/zsh-formatting"
  mkdir -p "${workspace}/scripts"
  printf '%s\n' \
    '#!/usr/bin/env zsh' \
    'value="hello world"' \
    "print -r -- \"\${(q)value}\"" > "${workspace}/scripts/example.zsh"

  run bash -c 'cd "$1" && "$2" fmt-check' -- \
    "${workspace}" "${PROJECT_ROOT}/scripts/shell-standards.sh"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" = "No shfmt-compatible shell files found." ]]
}

@test "ignores shell files in nested generated directories outside Git" {
  # shellcheck disable=SC2154 # Bats defines BATS_TEST_TMPDIR at runtime.
  local workspace="${BATS_TEST_TMPDIR}/nested-generated"
  local directory
  local -a generated_directories=(
    "${workspace}/project/.godot/generated"
    "${workspace}/project/.lua_modules/share"
    "${workspace}/project/.venv/bin"
    "${workspace}/project/packages/app/node_modules/package"
    "${workspace}/project/pkg/__pycache__"
    "${workspace}/project/sbom/generated"
  )
  for directory in "${generated_directories[@]}"; do
    mkdir -p "${directory}"
    printf '#!/usr/bin/env bash\nif\n' > "${directory}/broken.sh"
  done
  export GIT_CEILING_DIRECTORIES="${workspace}"

  run bash -c 'cd "$1" && "$2" syntax' -- \
    "${workspace}/project" "${PROJECT_ROOT}/scripts/shell-standards.sh"

  [[ "${status}" -eq 0 ]]
  [[ "${output}" = "No standalone shell scripts found for syntax checks." ]]
}

@test "rejects shell symlinks without changing their targets" {
  # shellcheck disable=SC2154 # Bats defines BATS_TEST_TMPDIR at runtime.
  local workspace="${BATS_TEST_TMPDIR}/shell-symlink"
  local external="${BATS_TEST_TMPDIR}/external.sh"
  local expected="${BATS_TEST_TMPDIR}/external.expected.sh"

  mkdir -p "${workspace}/scripts"
  printf '#!/usr/bin/env bash\nif true;then echo external;fi\n' > "${external}"
  cp "${external}" "${expected}"
  ln -s "${external}" "${workspace}/scripts/external.sh"
  git init --quiet "${workspace}"
  git -C "${workspace}" add scripts/external.sh

  run bash -c 'cd "$1" && "$2" fmt' -- \
    "${workspace}" "${PROJECT_ROOT}/scripts/shell-standards.sh"

  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"scripts/external.sh: shell source symlinks are not supported."* ]]
  cmp -s "${expected}" "${external}"
}
