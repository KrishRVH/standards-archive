# Julia Standards

[Julia](https://julialang.org/) is a dynamically typed language that compiles
each method for the concrete argument types it meets, through LLVM, so generic
numeric code runs at native speed without a second implementation language. The
best starting points are the official [manual](https://docs.julialang.org/) and
the [Pkg documentation](https://pkgdocs.julialang.org/).

## Why Julia Is Here

Julia earns a place here through a few choices the rest of the catalog does not
make:

- Multiple dispatch is the organizing principle. A function is a set of
  methods selected by the types of all its arguments, so independent packages
  compose: a new type gains behavior by adding methods to existing functions,
  and a new function works on existing types, without wrappers or inheritance.
- Type-specialized compilation removes the two-language split common in
  scientific code. The prototype and the fast kernel are the same Julia, and
  the abstractions cost nothing once the compiler has specialized them.
- Pkg is unusually reproducible. `Manifest.toml` records the exact version and
  content hash of every registered dependency, workspaces share one
  manifest across the package, its tests, and its tools, and
  `Pkg.is_manifest_current` detects a manifest resolved from a different
  project file.

It overlaps the active Python profile in domain, not in design: Python reaches
for native extensions where Julia relies on dispatch and specialization.

## Baseline

Copy `Project.toml`, `Manifest.toml`, `src/`, `test/`, `tools/`,
`scripts/format.sh`, and `Mise/conf.d/20-julia.toml` into a Julia package; the
shared `.gitignore` covers its `.julia/` depot. Replace `ProjectName` in the
module, file, and project names, generate a fresh package UUID with
`julia -e 'using UUIDs; println(uuid4())'`, put it in all three
`Project.toml` files, then run `mise run julia:update` and commit the
regenerated `Manifest.toml`.

The template is one package with a workspace of two members. `test/` holds the
`Pkg.test` environment and `tools/` holds the formatter and static analyzers,
so neither adds a dependency to the package itself. One root `Manifest.toml`
pins all three environments.

The standards workflow is:

```sh
mise run julia:standards
mise run julia:fmt:check
mise run julia:lint
mise run julia:test
mise run julia:standards:check
```

- `julia:install` fails when the manifest no longer matches any workspace
  project file, then instantiates exactly what the manifest records.
- `julia:fmt` and `julia:fmt:check` run [Runic](https://github.com/fredrikekre/Runic.jl)
  over Git-tracked and unignored `.jl` files. Runic has no options, like
  `gofmt`, so formatting carries no policy to review.
- `julia:lint` runs [Aqua](https://github.com/JuliaTesting/Aqua.jl) for package
  hygiene (method ambiguities, unbound type parameters, stale dependencies,
  missing compat entries, type piracy) and
  [JET](https://github.com/aviatesk/JET.jl) for errors inferred from the
  package's code, such as undefined names and impossible calls.
- `julia:test` runs `Pkg.test` with depwarns as errors and without
  re-resolving, so a test run never rewrites the manifest.
- `julia:update` re-resolves and upgrades the manifest on purpose.

The mise profile pins an exact Julia release from the official binary
downloads with their published SHA-256 checksums, and sets
`JULIA_DEPOT_PATH` to a project-local `.julia/` depot. Registries, packages,
and precompile caches stay in the project; the trailing empty entry appends
only Julia's bundled standard-library depots, never `~/.julia`. A cold gate
downloads and precompiles the tools, which takes under a minute on the
reference workstation; a warm gate takes a few seconds. JET releases track
Julia minor releases closely, so upgrade Julia and JET together. The fixture
is verified on Linux x64; the declared tool also maps the official Linux
ARM64, macOS, and Windows x64 archives. The formatting adapter requires a
POSIX shell.

## Not Included

These generic defaults stay out on purpose:

- juliaup: it installs and switches channels outside a reviewed lock. An
  exact release with checksums already exists.
- JuliaFormatter: its configuration surface and major-version changes both
  alter output. Runic has neither.
- A shared `~/.julia` depot: it couples projects through one package and
  precompile store, and makes cold and warm gates differ between machines.
- Documenter, PackageCompiler, precompile workloads, and Revise: they serve
  documentation sites, deployment, load latency, and interactive work. Add
  them when a project needs them.
- `Aqua` and `JET` inside `test/runtests.jl`, as many packages do: keeping
  them in `tools/` holds the test environment to the package's real test
  dependencies and gives the lint gate its own task.
