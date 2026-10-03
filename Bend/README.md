# Bend Standards

[Bend](https://bend-lang.com/) is a pure, affine, dependently typed language
with Python-shaped syntax. It compiles to C for CPUs and GPUs, or to
JavaScript, and checks proofs written in the same language as the code. The
best starting point is the guide that ships with the compiler: `bend guide`.

Bend 2 is young and says so: expect bugs, and expect the language, Base
library, and project conventions to change. Bend 1 programs do not carry
forward. This profile is a small, reproducible way to explore the language,
not a claim that its ecosystem has converged.

## Why Bend Is Here

Bend earns a place here through a few unusual choices:

- Laws are part of the language. A `law` states a property in a type, and a
  `def` of the same name proves it. There are no tactics: a proof is an
  ordinary term the checker reads.
- Termination is mandatory. Recursion must shrink a matched input, mutual
  recursion is refused, and `@unsafe` code is named whenever a check relies on
  it. Proofs cannot hide behind a loop.
- Quantities are explicit. Values are affine by default, `+` marks reusable
  `Data`, and `-` marks erased arguments that exist only for the checker.
- Parallelism is a call form. `a b = f(x) g(y)` forks two independent calls,
  and `f!(x)` hands a call to the GPU, from one generated C file.

Its most distinctive convention is law-driven development. A project keeps
`LAWS.bend`, the open claims a human writes, beside `PROOF.bend`, which proves
each law. `bend PROOF.bend` prints ALL PROOFS CHECK only when every law holds.
The claims become the specification an implementation, human or AI, must
satisfy mechanically. That experiment is why Bend belongs in this catalog.

## Baseline

Copy `src/project_name.bend`, `LAWS.bend`, `PROOF.bend`, and
`Mise/conf.d/20-bend.toml` into a Bend project. Rename `project_name` in the
file name, imports, and task paths. Replace the sample laws with the project's
own claims, and keep `LAWS.bend` and `PROOF.bend` at the project root where
Bend expects them.

The standards workflow is:

```sh
mise run bend:standards
mise run bend:fmt:check
mise run bend:lint
mise run bend:test
mise run bend:standards:check
```

The mise profile pins an exact release with its published digests for Linux
and macOS; Bend publishes no Windows build. `bend:lint` type- and
termination-checks the package entry point, and `bend:test` checks every law
through `PROOF.bend`. Bend has no formatter, so `bend:fmt` and `bend:fmt:check`
run the same compiler check. The profile sets `BEND_NO_TELEMETRY` so checks
skip the daily update request and leave the home directory alone.

Follow the guide that matches the pinned compiler, and revise this template as
stable conventions emerge.

## Not Included

These generic defaults stay out on purpose:

- The `curl | sh` installer or `bend update`: both track the latest release
  without a reviewed configuration diff.
- `bend PROOF.bend --verdict`: the second check by the Lean-proven kernel needs
  a pinned Lean toolchain of about 600 MB. Add it when a project's claims need
  that assurance.
- Native builds with `-o`: they need clang, and GPU calls need CUDA or Metal.
  Add a build task when the project ships an executable.
- BendHub publishing: a publish is public and permanent. Keep it a deliberate
  manual step.
