# GDScript Standards

Copy `.editorconfig`, `.gdlintrc`, `project.godot`, `src/`, and `tests/` into a
Godot project. Copy `Mise/conf.d/20-godot.toml` to
`.config/mise/conf.d/20-godot.toml`, then replace `Project Name` and the sample
code with the real project identity and behavior. Use the shared `.gitignore`
and `.gitattributes` alongside these files so Godot-generated state stays
untracked while project resources remain normalized text.

This typed Godot 4.7 baseline pins Godot and GDToolkit. Untyped declarations
and unsafe dynamic operations are compile errors, while idiomatic `:=`
inference remains available. Generated `.godot/` state stays out of version
control; let Godot create `.uid` sidecars and commit them with their source
files.

mise installs both tools. The aqua Godot release exposes a `godot` executable
through `symlink_bins`. GDToolkit comes from the `pypi:` backend: `mise lock`
records its complete dependency graph with wheel hashes in `mise.lock` and a
sidecar under `.config/mise/locks/`, and installs it on the pinned Python.
Graph locking needs mise 2026.9.7 or newer and uv 0.12.10 or newer. Commit
`mise.lock` and the `locks/` directory. Refresh GDToolkit's dependencies with
`mise lock --bump pypi:gdtoolkit`.

The normal workflow is:

```sh
mise install
mise run godot:import
mise run godot:standards
mise run godot:fmt:check
mise run godot:lint
mise run godot:test
mise run godot:standards:check
```

`godot:import` scans new and changed resources headlessly, including generated
`.uid` sidecars that should be committed with their source files.
`godot:lint` runs `gdlint` alongside `godot:check`, which imports the project
headlessly, fails if the import changed committed metadata, then loads every
script under `src/` and `tests/` so Godot parses, type-checks, and resolves its
dependencies and global classes. `godot:test` runs the small native `SceneTree`
test entrypoint after `godot:check`, because both write Godot's import cache.
Replace that task with a pinned project test framework when scene fixtures,
mocks, or parameterized tests justify the dependency.
