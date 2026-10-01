# Tester Mini Projects

These small standalone projects exercise the copyable standards through the
documented `.config/mise` layout. Each fixture commits
`.config/mise/mise.lock` for the Linux tool assets used by the repository gate.
Their job is to prove that a strict template runs after copying, not to require
every downstream project to keep every check.

Run all tester projects from the repository root:

```sh
MISE_TRUSTED_CONFIG_PATHS="$PWD" mise run //testers/...:standards:check
```

The root is an explicit mise monorepo with `testers/*` config roots,
per-fixture lockfiles, and a scheduler width sized for the maintainer
workstation in the root config. The native monorepo scheduler provides
project-prefixed output and failure propagation while every fixture owns its
configuration and tools. Run one fixture through the same root namespace with,
for example:

```sh
mise run //testers/c:standards:check
```

For an isolated check, run one representative fixture in its Dagger reference
container. This task intentionally sits outside the default root gate:

```sh
MISE_TRUSTED_CONFIG_PATHS="$PWD" mise run //testers/c:dagger:standards:check
```

Or run the same host-local gate that the repository aggregate task uses from
inside one fixture:

```sh
cd testers/js
MISE_TRUSTED_CONFIG_PATHS="$PWD/../.." mise run standards:check
```

The fixture list comes from [`standards.manifest.toml`](../standards.manifest.toml).
The root's `testers/*` discovery pattern contains no duplicate profile
inventory; the drift checker proves that every discovered fixture is declared
and every declared fixture exists. Declared mirror files must stay
byte-for-byte aligned with their template source. Undeclared fixture source and
tests are intentionally fixture-owned.

Fixture configurations define no `lock` task. After changing a pinned tool
version or fixture mise config, refresh the affected lockfile from that fixture
directory with mise's native command:

```sh
MISE_TRUSTED_CONFIG_PATHS="$PWD/../.." mise lock --platform linux-x64
```
