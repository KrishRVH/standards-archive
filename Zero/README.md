# Zero Standards

[Zero](https://github.com/vercel-labs/zerolang) is an experimental systems
language from Vercel Labs, designed for coding agents rather than adapted to
them. Its compiler input is a semantic program graph, not text. The upstream
project calls itself experimental and warns of breaking changes, rough edges,
and security issues; run it in isolated workspaces. The best starting point is
the version-matched guidance the compiler ships with: `zero skills list` and
`zero skills get <name>`.

## Why Zero Is Here

Zero inverts the usual relationship between source text and compiler state:

- `zero.graph` is the package's checked-in graph store and the only compiler
  input. `.0` files are its human-readable projection, kept for review and
  hand edits.
- Agents edit through checked graph patches: `zero patch` validates an edit
  against the whole program before it saves, and node handles stay stable
  across edits, so queries and follow-up patches refer to the same nodes.
- Drift between graph and projection is classified by content hash, never by
  timestamp. `zero verify-projection` fails on drift without writing, and
  `ZERO_STALE=fail` stops compiler commands from silently refreshing the graph.
- Every diagnostic carries a stable code, `zero explain <code>` documents it,
  and `--json` gives tools exact fields.

That makes Zero the catalog's experiment in graph-as-source: what a toolchain
looks like when the primary author is an agent and the reviewer is a person.

## Baseline

Copy `zero.toml`, `zero.graph`, `src/`, `scripts/format.sh`, and
`Mise/conf.d/20-zero.toml` into a Zero project; the shared `.gitignore` covers
its `.zero/` cache. Replace `project-name` in `zero.toml` and the greeting
in `src/main.0`, run `zero import .` to refresh the graph, and commit
`zero.graph` with its projection.

The template is the smallest shape the bootstrap compiler accepts: one `exe`
target whose `main` writes through the `World` capability, plus a
package-local module with inline `test` blocks. The compiler supports only
`exe` targets; a library-only package still names a `main` source.

The standards workflow is:

```sh
mise run zero:standards
mise run zero:fmt:check
mise run zero:lint
mise run zero:test
mise run zero:standards:check
```

`zero:fmt:check` requires both a clean projection and formatted `.0` source.
`zero:lint` and `zero:test` compile the committed graph with
`ZERO_STALE=fail`, so the gate never rewrites `zero.graph`. Tests run without
a C compiler; `zero build` and `zero run` need one, and `zero doctor` reports
which targets the host can build.

`zero:fmt` formats the projection with `zero fmt` and refreshes the graph with
`zero import`. It refuses a drifted projection, because `zero status` cannot
tell which side changed: importing a stale projection silently discards graph
patches. After a hand edit to `.0` source, run `zero import .`; after a graph
patch, run `zero export .`. Then run `zero:fmt`.

`zero.graph` is binary. The shared `.gitattributes` marks it with
`diff=zero-graph`; for readable Git diffs, set
`git config diff.zero-graph.textconv 'zero diff'`.

The task file pins an exact release through mise's GitHub backend, and the
fixture's committed lockfile records the GitHub-published digest. The formatting
adapter requires a POSIX shell.

## Not Included

These generic defaults stay out on purpose:

- The `curl | bash` installer: it installs whatever is latest into
  `~/.zero/bin`, outside any reviewed lock.
- `npx skills add vercel-labs/zerolang`: the compiler already ships
  version-matched skills through `zero skills`, and a separately installed copy
  can drift from the pinned compiler.
- A text-encoded graph store: upstream reserves `--format text` for debugging
  and defaults to binary.
- `.program-graph` artifacts and the `.zero/` cache: they are derived, and
  upstream says not to commit them.
- A build or release task: targets, profiles, and cross-compilers are
  project-specific, and the bootstrap compiler's target matrix is still
  moving.
