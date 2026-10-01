# mise Standards

Copy `config.toml` to `.config/mise/config.toml`, `tasks/hygiene` to
`.config/mise/tasks/hygiene`, and the selected `conf.d/*.toml` files to
`.config/mise/conf.d/`.

The copyable configuration requires mise `2026.6.12` or newer. That is the
first release supporting the checksum-backed HTTP lock metadata used by the
Odin formatter; it is a minimum, not an executable pin. A language fragment
that needs a later release sets its own `min_version`.

Use `mise run` for project workflows so a developer can build, format, or test
without knowing the underlying toolchain. Dagger is optional; when a project
keeps `conf.d/10-dagger.toml`, the isolated check task pins and invokes it.

Run host utilities such as `git`, `rg`, and `tokei` directly. Native commands
remain available for focused diagnosis. Use `mise exec -- <command>` when a
specific invocation needs the project's pinned tool or environment and no
suitable task exists. Final verification uses the project's mise gates.

`mise run` supplies its own tool environment. Interactive activation and shims
are optional choices for automatic tool selection. Prompt, history,
navigation, and completion tools follow host conventions and run independently
of mise.

The command surface starts strict. Keep the language tasks that fit the project
and relax or remove checks that do not match its risk, lifecycle, or team
tolerance.

Recommended project entrypoints:

```sh
mise install
mise run fmt
mise run fmt:check
mise run lint
mise run test
mise run standards
mise run standards:check
mise run hygiene
mise run secrets
mise run sbom
mise run dagger:standards:check
```

Use mise's own commands, such as `mise install`, `mise tasks`, `mise doctor`,
and `mise lock`, directly; the template does not wrap them in tasks.

`hygiene` checks the tree as it would be committed: tracked and new, non-ignored
files, including sparse and symlinked entries by name. It prints a line
inventory by category with the largest source files, so growth shows in every
run. It fails on:

- history directories such as `briefs/`, `reports/`, or `research/` at the top
  level or under `docs/`;
- leftover file names such as `main.rs.orig`, and versioned ones such as
  `parser_v2.rs`;
- handoff notes such as `HANDOFF.md`, and dated names at the top level or
  directly under `docs/`;
- literal `mise run` invocations of tasks that do not exist, including
  `//project:task` references in a monorepo.

Outside a git work tree, such as the Dagger check's copied source, it reports
that it skipped. Paths in its constants are relative to the directory it runs
in. `ALLOWED_PATHS` names externally owned trees that every rule skips.
`CONTRACT_PATHS` names paths whose version or date names follow an external
contract, such as migrations, a versioned API, or published posts; leftover and
handoff rules still apply there.

The task does not parse source code. Add language-aware rules, such as
versioned identifiers or scripts that no task runs, at the end of its checks,
using a parser or linter where practical.

The task pins its own Python through a `# MISE tools=` header, so run
`mise lock` after copying it. Keep the file executable; mise does not list a
file task without the executable bit.

`standards` applies available safe autofixes and runs each detected language's
local workflow. Some ecosystems expose validation only because they have no
safe formatter. `standards:check` runs the CI-grade aggregate task, the
project's shared `.gitleaks.toml` secret scan, and `hygiene`. `sbom` writes a
fresh CycloneDX JSON SBOM under `sbom/` for release and audit workflows;
`SYFT_SOURCE_NAME` and `SYFT_SOURCE_VERSION` control its source metadata. If
the project includes `10-dagger.toml` and the Dagger module,
`dagger:standards:check` runs `standards:check` inside an official,
digest-pinned `mise` Linux reference container; the
[Dagger guide](../Dagger/README.md) describes its pins and source filtering.

Commit the lockfile generated for the chosen config layout. With this template's
`.config/mise/config.toml` layout, mise writes `.config/mise/mise.lock`. Use
`mise.local.toml` for machine-local overrides.

For CI, prefer an invocation-scoped strict check such as `MISE_LOCKED=1 mise
run standards:check` instead of project-wide `locked = true`, which can also
constrain tools from a developer's global mise configuration.

Language task files are additive. Keep only the `conf.d/20-*.toml` files that
match the project languages; the aggregate `fmt`, `fmt:check`, `lint`, `test`,
`standards`, and `standards:check` tasks dispatch to C, C++, Elixir,
Fortran, GDScript, Haskell, JavaScript, Lua, Odin, PHP, Roc, SPARK/Ada,
and Zig when their project files are detected. Roc dispatch requires
`main.roc`; Odin dispatch requires an owned source file under `src/`
or `tests/`; GDScript dispatch requires `project.godot` and an owned script
under `src/` or `tests/`; JavaScript dispatch requires `package.json` plus
`jsconfig.json`.

Each language fragment expresses static workflow composition with native mise
dependencies and structured task references. Shared install, restore,
manifest, component, and lock prerequisites therefore execute once per
top-level language graph. Read-only independent checks may run concurrently;
formatters and tools that share mutable build state remain sequenced.

Because language fragments are optional, the generic aggregate dispatcher
discovers them at runtime. It runs detected language graphs one at a time,
preventing mixed-language projects from racing over shared package files or
build state. Its one nested `mise run` selects a task whose name is known only
after marker detection. Projects with a fixed stack should replace the
generic aggregate tasks with explicit native dependencies. The dispatcher is a
POSIX shell template verified on Linux; Windows consumers need explicit task
relationships or a reviewed `run_windows` implementation.

The JavaScript task file is Bun-only. If a project uses pnpm, Yarn, or npm,
replace it with a project-specific task file. The workflow uses Oxfmt for
formatting, Oxlint for linting, Knip for the declared dependency boundary, and
`tsc` only for strict `checkJs` analysis.

The Odin task file uses the OLS `odinfmt` nightly for project-scoped developer
formatting and the version-matched compiler as the style, vet, and test
authority. A fail-closed adapter avoids the formatter's unsafe in-place write
path; the non-mutating `fmt:check` remains compiler-owned because `odinfmt` has
no check mode. Its explicit update task relocks and force-reinstalls the mutable
nightly so warm and cold machines converge. The required tests retain native
parallelism and a fresh reported seed while enabling bad-memory failure
tracking, debug AddressSanitizer, and a separate optimized lane. The fixture is
verified on Linux x64 with pinned Clang. Official builds on macOS require the
Xcode command-line tools, and Windows requires MSVC and the Windows SDK; this
repository does not verify those hosts or FreeBSD. The formatter adapter
requires a POSIX shell.

The Roc task file pins the immutable compiler release selected by Roc's
official installers and resolves its official release digests into the mise
lock. Native `roc fmt`, warning-failing `roc check`, and top-level `expect`
tests form the generic gate. The fixture is verified on Linux x64; the declared
tool also maps the official Linux ARM64, macOS x64/Apple Silicon, and Windows
x64 assets. Project-scoped format discovery requires a POSIX shell.

The Lua task file pins Lua 5.4, runs StyLua, installs pinned Luacheck/Busted
rocks into `.lua_modules`, and runs both Luacheck and LuaLS diagnostics. It
requires `luarocks` on PATH for lint/test tooling.

The GDScript task file pins Godot 4.7 and a portable, hashed GDToolkit
environment. It formats and lints owned scripts, then uses headless Godot
import, per-script checks, and resource loading as the language-semantic gate
before running the project test entrypoint.
