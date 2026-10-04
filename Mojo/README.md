# Mojo Standards

[Mojo](https://mojolang.org/) is a systems language from Modular with
Python-like syntax, built to program CPUs, GPUs, and other accelerators from
one source. It compiles through MLIR, has value semantics and ownership
checked at compile time, and makes compile-time metaprogramming an ordinary
part of the language. The best starting points are the official
[manual](https://mojolang.org/docs/manual/) and
[standard library reference](https://mojolang.org/docs/std/).

Modular publishes the compiler source under Apache 2.0 with LLVM exceptions,
but the PyPI wheels this profile pins declare Modular's
`LicenseRef-MAX-Platform-Software-License` in their metadata; review that
license before redistributing the toolchain.

## Why Mojo Is Here

Mojo earns a place here through a few unusually deliberate choices:

- Python's surface without its runtime model: structs are static, arguments
  have explicit conventions (`imm`, `mut`, `var`), and the compiler checks
  lifetimes and origins instead of relying on a garbage collector.
- Raising is part of a function's signature: only a function declared
  `raises` can fail, so a call that can fail is visible at every boundary.
- Parameters are compile-time values evaluated by the same language, so
  specialization, vector widths, and hardware targets are ordinary code rather
  than a separate template or macro language.
- One language targets CPU and GPU kernels; hardware choice flows through
  parameters and the type system instead of a second dialect.

## Baseline

Copy `src/`, `tests/`, `scripts/format.sh`, and `Mise/conf.d/20-mojo.toml`
into a Mojo project. Rename `src/project_name` to the real package name and
update the test import. Packages live under `src/<package>/__init__.mojo`;
test suites are `tests/test_*.mojo` files whose `main` runs
`TestSuite.discover_tests`.

The standards workflow is:

```sh
mise run mojo:standards
mise run mojo:fmt:check
mise run mojo:lint
mise run mojo:test
mise run mojo:standards:check
```

`mojo:fmt:check` formats a staged copy with `mojo format`, which has no check
mode, and prints the diff. `mojo:lint` precompiles every package under `src`
with `--Werror`, which type-checks the package without running it.
`mojo:test` runs each suite with `--Werror`, so warnings in tests fail too.

The task file pins the official `mojo` PyPI wheel through mise's `pypi`
backend. The fixture's mise lock records the whole wheel graph, including the
compiler, the bundled `mblack` formatter, and the debugger libraries, by
digest. Wheels exist for Linux x64, Linux ARM64, and macOS on Apple Silicon;
the fixture is verified on Linux x64. The toolchain is about 680 MB
installed. `MODULAR_TELEMETRY_ENABLED=0` stops telemetry uploads. The
compiler keeps its compile cache in `~/.cache/modular/.mojo_cache`, outside the
project.

## Not Included

These generic defaults stay out on purpose:

- Pixi or a `pyproject.toml` project: the official guides use them to fetch
  the compiler, but mise already pins and locks it, and a `pyproject.toml`
  would make an adopting repository look like a Python project.
- GPU kernels: the gate must run on any CI host. Add GPU tests in a separate
  task when a project targets an accelerator.
- A precompiled `.mojoc` package as a release artifact: it is tied to the
  exact compiler version that produced it.
