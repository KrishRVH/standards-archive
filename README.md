# Standards Archive

Dormant copy-from catalog for C, C++, Elixir, Fortran, GDScript, Haskell,
JavaScript, Lua, Odin, PHP, Roc, SPARK/Ada, and Zig. These profiles are preserved
for occasional reuse and receive maintenance when needed.

The actively maintained C#, Go, Kotlin, Python, Rust, Shell, TypeScript, and
Markdown/MDX profiles live in
[standards](https://github.com/KrishRVH/standards).

This repository owns a self-contained snapshot of `shared/`, `Mise/`, and
`Dagger/`. Markdown and Shell templates and fixtures support its own repository
checks. The two catalogs have no runtime dependency or synchronization process.
Tool and dependency pins remain fixed until an explicitly requested update;
preserved fixtures do not promise compatibility with future tool releases.

## Adopt a profile

Copy only the parts the target project needs:

1. Copy the files under `shared/` into the project root.
2. Copy `Mise/config.toml` to `.config/mise/config.toml`, `Mise/tasks/hygiene`
   to `.config/mise/tasks/hygiene`, and the relevant `Mise/conf.d/` fragments
   into `.config/mise/conf.d/`.
3. Follow the selected language folder's README and merge any language-specific
   `AGENTS.md` into the shared guide.
4. Review the copied files, replace placeholder names, remove inapplicable
   tooling, and adapt paths to the project.
5. Run `mise install`, `mise run standards`, and `mise run standards:check`
   in the adopting project. Commit its generated lockfiles.

The shared `.gitignore`, `.gitattributes`, and `.gitleaks.toml` carry broad
ecosystem coverage. Copy them whole and keep that coverage when unused.

For optional isolated checks, copy `Mise/conf.d/10-dagger.toml`,
`Dagger/dagger.json`, and `Dagger/dagger/` into the project. See the
[mise guide](Mise/README.md) and [Dagger guide](Dagger/README.md).

## Verify an explicit archive change

[`standards.manifest.toml`](standards.manifest.toml) maps each template to its
fixture, task prefix, and exact mirror paths. Update the corresponding fixture
when changing a template and keep those mirrors byte-for-byte aligned.

List root tasks with `mise tasks`. Run drift and the changed fixture's gate:

```sh
mise run standards:drift
mise run //testers/c:c:standards:check
```

Refresh affected fixture tool locks from the fixture directory:

```sh
cd testers/c
MISE_TRUSTED_CONFIG_PATHS="$PWD/../.." mise lock --platform linux-x64
```

Run the aggregate gate for changes to shared infrastructure or release checks:

```sh
mise run standards:check
```

It runs secret scanning and hygiene before drift, Markdown, Shell, and every
preserved fixture gate. The root mise monorepo discovers `testers/*`; each
fixture owns its deterministic Linux mise lockfile. The
[tester guide](testers/README.md) explains the layout.

The root GitHub workflow supports `workflow_dispatch` only. Hosted checks run
on demand; preserving the archive creates no recurring CI obligation.
