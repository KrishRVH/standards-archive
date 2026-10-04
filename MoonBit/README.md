# MoonBit Standards

[MoonBit](https://www.moonbitlang.com/) is a statically typed language with a
Rust-like surface and an ML-family core. It compiles to WebAssembly (both
linear-memory and GC), JavaScript, and native code through C or LLVM, from
one vertically integrated toolchain: `moon` builds, checks, formats, tests,
documents, and publishes. The best starting points are the official
[documentation](https://docs.moonbitlang.com/) and
[language tour](https://tour.moonbitlang.com/).

MoonBit is pre-1.0. The language, core library, manifest formats, and
toolchain behavior may all change between releases. This profile is a small,
reproducible way to explore the language, not a claim that its ecosystem has
converged.

## Why MoonBit Is Here

MoonBit is designed from the start for code written with AI assistance, and
the design shows in the toolchain rather than in a plugin:

- Source is organized in independent top-level blocks separated by `///|`.
  The order of blocks is irrelevant, so a tool can generate, review, or
  replace one block without re-reading its neighbors.
- `moon info` writes each package's public interface to a generated
  `pkg.generated.mbti` file. An unchanged interface is a reviewable claim
  that a change is an internal refactor; a changed one is the API diff.
- Tests live next to the code: blackbox tests in `*_test.mbt` see only the
  public API, whitebox tests in `*_wbtest.mbt` see the package, and snapshot
  tests refresh with `moon test --update`.
- The compiler, formatter, test runner, and interface generator share one
  build graph and one diagnostic format, so a check needs no extra tools.

That combination of fine-grained edit units and a committed interface
contract is why MoonBit belongs in this catalog.

## Baseline

Copy `moon.mod`, `src/`, `scripts/interface.sh`, and
`Mise/conf.d/20-moonbit.toml` into a MoonBit project, and keep `_build/`,
`.mooncakes/`, and `target/` out of version control. Replace
`owner/project_name` in `moon.mod` with the real module name, rename
`@project_name` in the tests, and run `mise run moonbit:standards` to
regenerate the interface.

The template is one library package in `src/` with blackbox tests. It targets
`wasm-gc`, which runs tests through the bundled `moonrun` without a C
compiler. A project that targets `native`, `llvm`, or `js` must change
`preferred_target` and the core bundle target in the task file together.

The standards workflow is:

```sh
mise run moonbit:standards
mise run moonbit:fmt:check
mise run moonbit:info:check
mise run moonbit:lint
mise run moonbit:test
mise run moonbit:standards:check
```

`moonbit:lint` and `moonbit:test` run with `--deny-warn`, so a warning in
source or tests fails the gate. `moonbit:info:check` regenerates every
package interface in a staged copy and fails when a committed `.mbti` file is
stale, added, or missing; `moonbit:standards` runs `moon info` and then
`moon fmt` to update both. Commit the generated `.mbti` files with the
change that alters them.

The mise profile pins the exact toolchain release from MoonBit's versioned
download path and its published digest, plus the matching core library. The
core archive has no published digest, so the task file records the one this
profile reviewed. The archive's executables arrive without permission bits,
so a post-install step sets them, as the official installer does. The core
library is bundled for `wasm-gc` inside the pinned install on first use.
Checks write nothing outside the project and the mise install directory; the
registry cache under `~/.moon` appears only once a project adds dependencies.
The fixture is verified on Linux x64; the declared tool also maps the
official Linux ARM64 and macOS Apple Silicon archives. The interface check
requires a POSIX shell and `tar`.

## Not Included

These generic defaults stay out on purpose:

- The `curl | bash` installer and `moon upgrade`: both track the latest
  release outside a reviewed configuration diff.
- The `moon new` scaffold's Copilot workflow, pre-commit hook, and agent
  guide: the workflow installs the latest toolchain on every run, the hook
  duplicates the gate, and the guide belongs in the project's own
  `AGENTS.md`.
- `moon add` and registry dependencies: the template has none, and adding one
  is a reviewed project decision that also commits its resolved versions.
- `moon prove`: formal verification of annotated contracts is a separate,
  costlier discipline. Add it when a project's contracts justify that cost.
- Native and LLVM backends: they need a system C toolchain. Add a target when
  the project ships one.
