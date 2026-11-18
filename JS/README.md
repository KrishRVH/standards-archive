# JavaScript Standards

Copy these files into a Bun-backed JavaScript project and replace
`project-name`, source paths, and test commands with the real project shape.

`package.json` is the executable source of truth for scripts and dependencies.
The baseline combines Oxfmt formatting and Oxlint linting with strict
TypeScript compiler analysis through `checkJs` in `jsconfig.json`. Knip keeps
imports inside the declared dependency boundary. Use JSDoc where
exported boundaries or ambiguous structures need an explicit contract; rely on
inference for implementation details. Do not add a parallel TypeScript source
tree merely to make the checker happy.

This profile is Bun-first: `packageManager`, `@types/bun`, `bun test`, and
TypeScript's `bundler` module resolution model Bun's runtime. Keep native ESM
explicit with `"type": "module"`. Use runtime-valid relative imports or
`package.json` imports rather than TypeScript-only path aliases. Switch to
`NodeNext` and `@types/node` only when Node, rather than Bun, is the runtime.
`bunfig.toml` routes package scripts and `node` shebang subprocesses through
Bun.

Copy the shared `.gitignore` into the project so generated files and local
artifacts stay outside the standards workflow.

The standards workflow is:

```sh
mise run js:lock
mise run js:lock:check
mise run js:standards
mise run js:fmt:check
mise run js:lint
mise run js:type
mise run js:test
mise run js:audit
mise run js:knip
mise run js:standards:check
```

The default `standards` package script applies Oxlint fixes, then Oxfmt and its
import organization. `standards:check` runs Oxlint, Oxfmt, `tsc` against
`jsconfig.json`, Bun tests, a dependency audit, and Knip. The audit exempts
picomatch advisory GHSA-fc5q-39xc-vjpf in development tooling until a fixed
release is available. Remove the exception when the lockfile resolves it.

Do not add pnpm, Yarn, or npm fallback branches to the shared task file.
Generate and commit `bun.lock` before relying on
`js:standards:check`; the CI gate fails when the lockfile is missing.
