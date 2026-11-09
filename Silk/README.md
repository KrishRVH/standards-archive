# Silk Standards

[Silk](https://silklang.org/) is a systems language with typed effects. It has
Rust-style ownership and borrowing with no garbage collector, compiles through
LLVM to native code and WebAssembly, and its compiler is written in Silk. The
best starting points are the official
[documentation](https://silklang.org/docs/get-started/overview) and the
[language tour](https://silklang.org/docs/get-started/a-tour-of-silk).

Silk is pre-alpha. Upstream says the language is still being designed and any
API may change without notice. Development releases are frequent and often
carry migration notes, and silklang.org can describe a different release than
the pinned one. This profile is a small, reproducible way to explore the
language, not a claim that its ecosystem has converged.

## Why Silk Is Here

Silk puts side effects and dependencies into function types:

- An `effect fn` lists its failures and the services it needs in its
  signature: `-> A ! E ? R`. Calling it builds an effect value, and `run`
  performs it. A caller must declare each failure in its own row or handle
  it, for example with `Effect.result`.
- Services are dependency injection checked by the compiler. A function names
  a `Logger` or an `Allocator` in its requirement row, and its caller provides
  one with `Effect.provideMut`. A test hands the same code an in-memory fake
  with no change to the code; the test runner provides no services, so a test
  cannot declare a requirement row.
- Ownership transfers are written: passing an owned value needs `move`, and
  the compiler names the missing `move` instead of copying silently.
- One `silk` command checks, formats, tests, documents, and runs
  documentation examples. The formatter has no style options, and every
  compiler diagnostic carries a stable code.

That combination of a typed effect system in the style of TypeScript's Effect
with the ownership model of a systems language is why Silk belongs in this
catalog.

## Baseline

Copy `silk.toml`, `src/`, `scripts/check.sh`, and `Mise/conf.d/20-silk.toml`
into a Silk project; the shared `.gitignore` covers its `build/` directory.
Replace `project-name` in `silk.toml`, and `project_name` in the documentation
example's import, with the real package name. An import spells a hyphen in the
package name as an underscore.

The template is a library package with one exported module. `src/lib.silk`
holds a bounded counter whose `increment` fails with a typed `LimitError`, its
tests, and a documentation example. Tests live in the module they test, as
upstream recommends. `LimitError` implements `Debug`, so a program that lets
it escape `main` still starts and reports it.

The standards workflow is:

```sh
mise run silk:standards
mise run silk:fmt:check
mise run silk:lint
mise run silk:test
mise run silk:standards:check
```

`silk:fmt` runs `silk format`, which formats `silk.toml` and every `.silk` file
under the source root. `silk:fmt:check` runs it with `--check`. Neither
formats the code in documentation examples.

`silk:lint` and `silk:test` run `scripts/check.sh`, which fails on what the
Silk tools report but exit zero for. `silk:lint` fails on:

- Any `silk check` diagnostic. The compiler exits zero on warnings, such as an
  unused import or local, and refuses a `[lints]` table in `silk.toml`.
- A documentation link that resolves to no declaration, including links on
  private declarations and tests, which `silk doc --include-private` reports.
- A `.silk` file under `src/` that a test build does not read, according to
  `silk hash --list --test`. Silk checks, tests, and documents only the
  modules it reaches by imports from the root module and the exported
  modules. An unreached module is never type-checked, and its tests never
  run. Import a new module from a reached one, or list it in `exports`.

The script assumes the default `src` source root and requires a POSIX shell.

`silk:test` runs `silk test --no-cache`, because an unchanged rerun otherwise
reports earlier passing results without running the tests. It then runs
`silk doctest`, which type-checks each `silk` example in the documentation of
public declarations and builds and runs each example that declares `main`.
`silk doctest` exits zero when an example compiles with warnings, so the
script fails on any diagnostic it prints. It also fails when it collects no
examples, so a package keeps at least one `# Examples` program or removes that
step.

The task file pins an exact development release through mise's GitHub backend.
Every Silk release is a prerelease, which mise lists for updates only with
`prerelease = true`. The fixture's committed lockfile records the
GitHub-published digest. Keep
`silk-version` in `silk.toml` equal to the pin: the `silk` tool runs the
compiler release that the project selects, and exits with status 3 when that
release is not installed. Read the release notes before updating both.

Silk emits LLVM 22 bitcode and links through Clang 22 or later, and the
fragment pins conda-forge Clang 22. Silk links Linux programs against stub glibc
libraries that it writes itself, so the build needs no sysroot. It uses an
`ld.lld` beside Clang when one is present; the conda-forge Clang has none, so
links use the GNU `ld` from Clang's own prefix. The fixture is verified on
Linux x64 only.

## Not Included

These generic defaults stay out on purpose:

- The `curl | sh` installer, `silk use`, and `SILK_AUTO_INSTALL`: they install
  compiler releases into `~/.silk`, outside any reviewed lock.
- The official LLVM release archive that Silk's own CI uses: its `ld.lld`
  needs `libxml2.so.2`, which newer distributions such as Ubuntu 26.04 do not
  ship, and Silk always prefers that linker when it sits beside Clang.
- The minisign signature each Silk release carries: mise verifies the
  GitHub-published SHA-256 digest that the lock records instead.
- A build task: `silk build` only checks a `kind = "library"` package, which
  `silk:lint` already does. Program and native-library outputs, targets, and
  profiles are project-specific.
- WebAssembly and WASI targets: their tests need Wasmtime, and the gate
  checks the host target only.
