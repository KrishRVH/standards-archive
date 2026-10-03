# Lean Standards

[Lean](https://lean-lang.org/) is a functional programming language and an
interactive theorem prover in one: programs, their specifications, and the
proofs that connect them are ordinary Lean terms, and a small kernel checks
every proof. The best starting points are the official
[language reference](https://lean-lang.org/doc/reference/latest/) and
[Functional Programming in Lean](https://lean-lang.org/functional_programming_in_lean/).

This is the catalog's strictest profile. It goes further than the SPARK
profile on every axis the toolchain allows: SPARK proves the absence of
run-time errors and declared contracts with automatic provers; this profile
requires a complete functional specification for every definition, proved in
the kernel, rechecked by three independent kernels, and confined to a
constructive axiom base. Where a guard is impossible, the section below says
why and shows the evidence.

## Why Lean Is Here

- Specifications are theorems. A statement such as
  `advanceAll limit count steps = min limit (count + steps.sum)` is checked by
  the kernel, not sampled by a test. Tests then check the compiled code, which
  the kernel never sees.
- The trusted base is small and replaceable. The kernel's output is a
  declaration list other checkers can replay. `leanchecker` replays it in the
  reference kernel, [nanoda](https://github.com/ammkrn/nanoda_lib) in an
  independent Rust kernel, and [lean4lean](https://github.com/digama0/lean4lean)
  in a kernel written, and partly verified, in Lean itself.
- Escape hatches are visible to a program. `sorry`, `native_decide`, axioms,
  `partial`, `unsafe`, `implemented_by`, and `@[extern]` all leave marks in the
  compiled environment, so a metaprogram can reject them mechanically instead
  of trusting a reviewer to spot them.

## Baseline

Copy every file in this folder into a Lean project, and copy
`Mise/conf.d/20-lean.toml` into `.config/mise/conf.d/`. Replace `ProjectName`
and `project_name` in file names, module names, `lakefile.toml`, and the audit
policy (`ProjectNameAudit/Policy.lean` and the roots in `ProjectNameAudit.lean`).
Keep `.lake/` in `.gitignore`; Lake writes dependencies and build output there.

The layout follows Lake's conventions:

- `ProjectName.lean` and `ProjectName/`: the library. Every module uses the
  module system and is imported by the root, which the audit enforces.
- `ProjectNameMain.lean`: the executable. Its root is not named `Main`:
  lean4export ships a `Main` module, and a dependency module of the same name
  would shadow it. The audit rejects any owned module that resolves outside the
  project's build output.
- `ProjectNameTests.lean`: kernel `decide` examples, plus a runtime test
  executable with seeded Plausible properties. `lake test` runs it.
- `ProjectNameAudit.lean` and `ProjectNameAudit/`: the audit, a Lean program
  that is Lake's lint driver. `ProjectNameAudit/Policy.lean` holds every
  project-specific input and every exception, each with its reason.
- `scripts/check.sh`: the steps that orchestrate external programs: the
  independent kernels and the reproducibility check.
- `lean-toolchain`, `lake-manifest.json`: the exact compiler and every
  dependency commit. Both are committed and audited.

The standards workflow is:

```sh
mise run lean:standards
mise run lean:fmt:check
mise run lean:lint
mise run lean:test
mise run lean:kernel
mise run lean:reproduce
mise run lean:standards:check
```

`mise install` builds nanoda from its pinned commit, and the first build
clones the pinned Lake dependencies. After that the gate needs no network, and
`lean:reproduce` proves it. The gate runs on Linux: the offline rebuild uses
`unshare` for a network-less user namespace.

## Guards

Every guard below runs in `lean:standards:check`. The audit's `self-test`
check, which `lean:lint` runs first, elaborates a module that breaks each
source and environment rule and fails unless the rule reports it, and fails if
any rule fires on a compliant control module.

Toolchain and dependencies:

- Lean 4.34.1 is pinned by its GitHub release digest. It is a patch release
  whose three fixes close use-after-free paths its release notes say could be
  extended into a proof of `False`.
- `lean-toolchain` must name exactly the running compiler.
- Every Lake dependency must be on the audit allowlist, come from an https
  GitHub URL, and be pinned to a full commit hash in both `lakefile.toml` and
  `lake-manifest.json`. Each checkout must sit at that commit with no local
  changes.
- `lakefile.lean` is rejected, because a Lean configuration can run code, and
  so is a Batteries `scripts/nolints.json`, because it records linter
  exceptions.
- Lake's downloaded build caches and shared artifact cache are disabled, and
  nothing is written to the home directory.
- `LEAN_ABORT_ON_PANIC` makes every panic fatal. Without it, a Lean program
  that panics continues with a default value and can exit 0; the exporter
  does exactly that for a declaration it cannot find.

Compilation:

- `lake build --iofail` fails on any warning or information message. Owned
  modules turn on `warningAsError`, `linter.missingDocs`, and `linter.all`,
  which enables every core linter, and turn off `autoImplicit` and
  `relaxedAutoImplicit`.
- Library, executable, and test modules use the module system, and
  `lake shake` must find no unused or missing imports in them.

Source rules, from the audit's `source` check on the elaborated syntax:

- Banned keywords: `sorry`, `admit`, `native_decide`, `decide +native`,
  `set_option` (options belong in `lakefile.toml`, so no proof can raise
  `maxHeartbeats` or set `debug.skipKernelTC`), `axiom`, `opaque`, `partial`,
  `unsafe` (outside the audit tool, which must call Lean's importer),
  `noncomputable`, `termination_by`, `decreasing_by`, `#eval` and every other
  `#` command, `run_cmd` and its relatives, and every macro, syntax, notation,
  elaborator, and initializer command.
- Banned attributes: `implemented_by`, `extern`, `export`, `never_extract`,
  and `csimp`.
- Every simplifier call names its lemmas with `only`, and `simp?` and its
  relatives are banned, so no proof depends on the simp set of the day.
- Every binder has a type: declaration binders, `fun`, `∀`, `∃`, `let`,
  `have`, `do` bindings, and `intro`. Every definition states its result type.
  Pattern binders in `match`, `cases`, `induction`, and `for` take their types
  from the value they destructure.
- Every `.lean` file belongs to an owned module root and elaborates on its own.

Formatting, from the audit's `format` check: LF line endings, no tabs, no
trailing whitespace, at most 100 characters per line as in Mathlib, exactly one
final newline, and no invisible or bidirectional control characters, which can
make source read differently from what the compiler sees.

Environment rules, from the audit's `environment` and `test-environment`
checks on the compiled declarations:

- No owned declaration is an axiom, opaque, unsafe, noncomputable, external,
  or replaced by `implemented_by`, and none recurses through a well-founded
  fixpoint: recursion is structural.
- Every owned declaration depends only on `propext` and `Quot.sound`. The
  library is constructive: `Classical.choice` is allowed only by a
  per-declaration exception. The template has three, each with its reason:
  the executable's `main` parses with core `String` operations, which depend on
  `Classical.choice`, and the test runner uses Plausible, which does too.
- Every written library and executable definition appears in the statement of
  at least one owned theorem. `main` is the only exemption.
- Every written owned declaration, theorems included, has a docstring.
- Every Batteries environment linter runs, including those disabled by
  default, such as the ones for theorem docstrings and for explicit variables
  of an `Iff`.
- The compiled IR of every owned function, and of every specialization the
  compiler generated for it, contains no external declaration and calls no
  unsafe function outside a per-declaration exception. The template has one:
  the test runner's specialized array loop reads through `Array.ugetBorrowed`.
- An exception that names no declaration, or that the declaration no longer
  needs, is itself a finding.

Tests:

- `decide` examples check concrete cases in the kernel at build time.
- `lake test` runs the same cases and four Plausible properties, with a fixed
  seed and 1000 samples each, against the native binary: the kernel proves the
  definitions, and the tests check what the compiler made of them.

Independent kernels, from `lean:kernel`:

- `leanchecker --fresh` replays every declaration the library, executable, and
  test roots reach, from the prelude up, in the reference kernel. The audit
  tool's own declarations are replayed too.
- lean4lean replays every owned module, and replays the executable and test
  roots fresh from the prelude.
- lean4export writes the written library and executable declarations, with
  everything they depend on, and nanoda checks the export with its own
  kernel. The library export may use only `propext` and `Quot.sound`; the
  executable export also permits `Classical.choice`.

Reproducibility, from `lean:reproduce`: the project is copied to a fresh
directory with dependency sources but no build output, rebuilt with no network
and an empty home directory, and every owned `.olean`, `.ilean`, and generated
C file must match the original byte for byte. Lean does not document
reproducible output as a guarantee; this gate checks it.

## Exceptions

Exceptions live in `ProjectNameAudit/Policy.lean`, keyed by module and
declaration, each with a comment that says why. Add one only when a dependency
outside the project forces it, as core `String` and Plausible do for the
template. The audit rejects an exception once its declaration is gone or no
longer needs it.

## Not Included

These guards are impossible with the pinned toolchain, or would weaken the
profile:

- A formatter: Lean has none. `lean --help` offers no formatting mode and
  `lake help` lists no formatting command. `lean:fmt` and `lean:fmt:check`
  therefore run the same text rules, and there is nothing to autofix.
- Sanitizers for the compiled code: the bundled clang ships only
  `libclang_rt.builtins.a`, `clang_rt.crtbegin.o`, and `clang_rt.crtend.o`, with
  no AddressSanitizer or UndefinedBehaviorSanitizer runtime to link. Using the
  system compiler instead would leave the C compiler unpinned.
- Coverage of compiled Lean code: no coverage tool exists for Lean's generated
  code. Spec coverage stands in for it: every definition must be the subject of
  a proved theorem.
- Banning calls into external code: every compiled program calls external
  runtime primitives. The IR of `ProjectName.advance` calls `Nat.add` and
  `Nat.decLe`, both `@[extern]`. The audit bans owned external declarations and
  unsafe callees instead.
- `lake shake` on the audit: under the module system, Batteries' linter API is
  `meta`, and calling it from a runtime program requires the whole tool to be
  `meta`. That build of the audit crashed with exit 139 on its first import, so
  the audit stays a classic, non-module program. Its source still passes every
  source and formatting rule, and its declarations are kernel-replayed.
- `#guard`: `lake shake` does not count the compile-time evaluation `#guard`
  needs, and reports its `meta import` as unused. The tests use `decide`
  examples, checked by the kernel, and the runtime test executable instead.
- lean4lean `--fresh` on the library root: lean4lean treats a module argument
  as a prefix and allows `--fresh` only when the prefix names one module, so
  the library is replayed module by module over its imports, while
  `leanchecker --fresh` replays it from the prelude.
- Mathlib: its style linters, including the one for non-terminal `simp`, live
  in Mathlib, which would add hundreds of modules to every build. The audit
  enforces a stricter rule directly: every simplifier call uses `only`.
- elan: it resolves `lean-toolchain` at run time and installs into the home
  directory. mise pins the compiler by digest instead, and the audit checks
  that `lean-toolchain` agrees.
- macOS and Windows: the tool pins cover them, but the gate is verified on
  Linux x64 only, and the reproducibility check needs Linux namespaces.
