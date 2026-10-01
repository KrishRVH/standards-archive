# Agent Guide

Read `shared/AGENTS.md` first, then `README.md`. This file adds the archive's
rules and wins where they differ.

This is a dormant copy-from catalog. Maintain it only for explicitly requested
work. `standards.manifest.toml` owns the profile inventory and fixture mapping.
`shared/`, `Mise/`, `Dagger/`, and language folders are copyable templates.
Root Markdown and Shell tooling supports repository checks, without language
templates or fixtures. Shared tooling is an independent snapshot; each catalog
owns its changes.

## Editing

- Keep copyable files neutral, with conventional `src`/`tests` paths and no
  machine paths or dependency on the active standards repository.
- Keep broad ecosystem coverage in template ignore, attribute, and allowlist
  files, including ecosystems without a profile here.
- Keep language-specific guidance in that language's `AGENTS.md`.
- Update a changed template's matching fixture, exact manifest mirrors, and
  affected lockfiles. Every discovered `testers/*` fixture must be declared,
  and every declared fixture must exist.
- Commit deterministic mise and package lockfiles. Keep dependencies, build
  output, caches, coverage, and local state untracked.
- Keep the root workflow manual-only: `workflow_dispatch` is its only trigger.

## Verification

Run `mise tasks` and read the definitions of tasks you use. After template,
shared task, manifest, or fixture-configuration changes, run
`mise run standards:drift`. Use the manifest's `tester` and `task_prefix` to run
an affected gate, for example `mise run //testers/c:c:standards:check`.

Refresh fixture locks with `mise lock --platform linux-x64` from their fixture
directory and the root lock with `mise lock` from the repository root. Run
`mise run standards:check` for shared or aggregate infrastructure changes,
release validation, or an explicit request. It scans secrets and hygiene,
then checks drift, Markdown, Shell, and all preserved fixtures.
