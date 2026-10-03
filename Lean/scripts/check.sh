#!/usr/bin/env sh
# Lean gate steps that orchestrate external programs. Lean-level rules live in
# the ProjectNameAudit lint driver; this script runs the build, the import
# check, the independent kernels, and the reproducibility check.
set -eu

kernel_roots="ProjectName ProjectNameMain ProjectNameTests"
# lean4lean takes a module prefix and allows --fresh only for a prefix that
# names a single module.
lean4lean_prefixes="ProjectName ProjectNameMain ProjectNameTests ProjectNameAudit"
lean4lean_fresh_roots="ProjectNameMain ProjectNameTests"
shaken_roots="ProjectName ProjectNameMain ProjectNameTests"
targets="ProjectName project_name project_name_tests project_name_audit lean4export lean4lean"

# Owned build outputs whose bytes must not depend on the build directory, the
# network, or the home directory.
build_outputs() {
  (cd "$1/.lake/build" && find lib/lean ir -type f \( -name '*.olean' -o -name '*.olean.*' -o -name '*.ilean' -o -name '*.c' \) | LC_ALL=C sort)
}

# Rechecks the written declarations of one role, with everything they depend
# on, in nanoda, permitting only the given axioms.
nanoda_check() {
  role="$1"
  axioms="$2"
  workdir="$3"
  lake exe project_name_audit "$role-declarations" > "$workdir/$role.names"
  if [ ! -s "$workdir/$role.names" ]; then
    echo "no $role declarations to export" >&2
    exit 1
  fi
  # shellcheck disable=SC2046 # one argument per declaration name
  lake exe lean4export ProjectName ProjectNameMain -- $(cat "$workdir/$role.names") > "$workdir/$role.ndjson"
  cat > "$workdir/$role.json" << CONFIG
{
  "export_file_path": "$workdir/$role.ndjson",
  "use_stdin": false,
  "permitted_axioms": [$axioms],
  "unpermitted_axiom_hard_error": true,
  "nat_extension": true,
  "string_extension": true,
  "print_axioms": false,
  "print_success_message": true
}
CONFIG
  nanoda_bin "$workdir/$role.json"
}

case "${1:-}" in
  build)
    # shellcheck disable=SC2086 # one argument per target
    lake build --iofail $targets
    ;;
  shake)
    for root in $shaken_roots; do
      lake shake "$root"
    done
    ;;
  kernel)
    # Replay every declaration the roots reach, from the prelude up, through the
    # kernel again; then the audit tool's own declarations. The audit proves the
    # roots import every owned module.
    for root in $kernel_roots; do
      lake env leanchecker --fresh "$root"
    done
    # shellcheck disable=SC2046 # one argument per module
    lake env leanchecker $(find ProjectNameAudit.lean ProjectNameAudit -name '*.lean' | sed 's|\.lean$||; s|/|.|g' | LC_ALL=C sort)
    # Replay again in lean4lean: every owned module over its imports, then the
    # executable and test roots from the prelude up.
    for prefix in $lean4lean_prefixes; do
      lake exe lean4lean "$prefix"
    done
    for root in $lean4lean_fresh_roots; do
      lake exe lean4lean --fresh "$root"
    done
    ;;
  nanoda)
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT
    nanoda_check library '"propext", "Quot.sound"' "$workdir"
    nanoda_check executable '"propext", "Quot.sound", "Classical.choice"' "$workdir"
    ;;
  reproduce)
    # Rebuild every target from source in a fresh directory with no network and
    # an empty home directory, then require byte-identical owned outputs.
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT
    mkdir -p "$workdir/home" "$workdir/project/.lake/packages"
    git ls-files -z --cached --others --exclude-standard . | grep -zv '^\.lake/' |
      tar --null -T - -cf - | tar -x -C "$workdir/project"
    # Dependency checkouts keep their git metadata, which Lake verifies, but not
    # their build outputs.
    tar -C .lake/packages --exclude='./*/.lake' -cf - . | tar -x -C "$workdir/project/.lake/packages"
    # shellcheck disable=SC2086 # one argument per target
    (cd "$workdir/project" && unshare --user --map-root-user --net env HOME="$workdir/home" lake build --iofail $targets)
    if [ -n "$(find "$workdir/home" -mindepth 1 -print -quit)" ]; then
      echo "the build wrote to the home directory" >&2
      exit 1
    fi
    build_outputs . > "$workdir/expected.list"
    build_outputs "$workdir/project" > "$workdir/actual.list"
    if ! cmp -s "$workdir/expected.list" "$workdir/actual.list"; then
      echo "the rebuild produced a different set of outputs" >&2
      diff "$workdir/expected.list" "$workdir/actual.list" >&2 || true
      exit 1
    fi
    status=0
    while IFS= read -r output; do
      if ! cmp -s ".lake/build/$output" "$workdir/project/.lake/build/$output"; then
        echo "not reproducible: .lake/build/$output" >&2
        status=1
      fi
    done < "$workdir/expected.list"
    exit "$status"
    ;;
  *)
    echo "usage: scripts/check.sh build|shake|kernel|nanoda|reproduce" >&2
    exit 2
    ;;
esac
