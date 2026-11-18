# Dagger Standards

Copy these files into a project as:

```text
Mise/conf.d/10-dagger.toml -> .config/mise/conf.d/10-dagger.toml
dagger.json
dagger/
  package.json
  tsconfig.json
  src/index.ts
```

Start a supported container engine on the host, such as Docker Desktop with
WSL integration, Colima on macOS, or Podman. Check the engine with
`docker info` or `podman info`, then run the task with the pinned Dagger CLI:

```sh
mise run dagger:standards:check
```

For a standalone CLI on WSL or macOS, select the release from the mise fragment
with the installer's `DAGGER_VERSION` variable. Set `BIN_DIR` to a directory
on your path. Check `dagger version`, then run `dagger call --help` from the
project root to list its functions. [Dagger CLI installation](https://docs.dagger.io/getting-started/install/)

Run other Dagger commands with the pinned version through `mise exec`, for
example `mise exec -- dagger develop` after you change the module or the CLI
pin. `dagger.json` names the pinned release as its `engineVersion`, which
`dagger develop` advances; without it, the engine runs the module under legacy
compatibility behavior.

The module copies the mise executable from its official Debian image into
`buildpack-deps:trixie`. The build image supplies the C headers, linker, and
build utilities required by native tools. PHP also requires parser generators
and development libraries for GD, Oniguruma, and ZIP. The module installs
them from signed Debian release and security snapshots. The snapshot date and
both multi-architecture image digests are pinned in `dagger/src/index.ts`.
The module caches tool installs
under `/mise`, enables strict lockfile mode, and runs `mise install` followed
by `mise run standards:check`. The companion mise fragment pins the Dagger CLI.

The module's `packageManager` pins npm 11: npm 12 supports Node.js 24 only from
24.15.0, and the Dagger 0.21.11 TypeScript runtime runs the module on its
default `node:24.13.1-alpine` image.

Known generated and dependency paths, secret-bearing `.env` files, `.git`, and
local mise overrides are filtered before the source crosses into the Dagger
engine; example, sample, and template environment files remain available. The
container copy also honors the project's `.gitignore`. Without `.git`, the
`hygiene` task reports that it skipped; the local `standards:check` runs it.
