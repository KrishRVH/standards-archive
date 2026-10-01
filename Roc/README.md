# Roc Standards

[Roc](https://www.roc-lang.org/) describes itself as a fast, friendly,
functional language. It compiles to machine code or WebAssembly, keeps the
language small, and aims to make static types feel helpful rather than
ceremonial. The best starting points are the official
[current documentation](https://www.roc-lang.org/docs/main/) and
[tutorial](https://www.roc-lang.org/tutorial).

Roc is not ready for a 0.1 release. Its project conventions, tooling, and
compatibility promises are therefore less settled than those of the other
languages in this catalog. This profile is a small, reproducible way to explore
the language, not a claim that its ecosystem has converged. The compiler,
syntax, standard library, and recommended project shape may all change.

## Why Roc Is Here

Roc earns a place here through a few unusually thoughtful choices:

- Decidable principal type inference lets the compiler infer the most general
  type for an expression without requiring annotations everywhere.
- Records and tag unions make domain states explicit. Roc prefers descriptive
  states such as `[Loading, Loaded(Artist), Errored(LoadingErr)]` over nulls or
  a universal optional type.
- Pure functions are the ordinary case, while effectful functions are visible
  through their `!` suffix. Lightweight top-level `expect` declarations and a
  non-configurable formatter are built into the language toolchain.
- The compiler targets low-level outputs instead of inheriting the runtime and
  data-model compromises of a higher-level virtual machine.

Its most distinctive feature is the
[application and platform architecture](https://www.roc-lang.org/platforms).
Every application chooses exactly one platform, and that platform supplies the
application's I/O primitives, memory-management strategy, and host integration.
The application author sees a Roc API; the platform's host can be implemented
in a systems language such as Zig, Rust, or C.

That boundary survives into the produced program. Roc compiles the application
to an object file, combines it with the platform's already-built host binary,
and links both into one executable. The host starts the process and decides
when to call the Roc application. Domain logic and runtime capabilities are
therefore separated by the architecture itself, with consequences for
portability, security, embedding, and domain-specific performance. That
experiment is why Roc belongs in this catalog before 0.1.

## Baseline

Copy `main.roc`, `Project.roc`, `scripts/format.sh`, and
`Mise/conf.d/20-roc.toml` into a Roc project. Replace `Project` in the module
name, filename, and package exposure with the real package name. Keep
`main.roc` as the package root, or update the explicit task paths when the
project chooses another root.

The fixture stops at a package boundary and chooses no platform. An executable
must deliberately select and review the platform that defines its capabilities;
the template does not hide a universal application platform.

The standards workflow is:

```sh
mise run roc:standards
mise run roc:fmt:check
mise run roc:lint
mise run roc:test
mise run roc:standards:check
```

The mise profile pins an immutable compiler nightly so this repository can
reproduce its checks. The executable configuration and committed lockfile are
the source of truth for that operational detail. Formatting, static checks,
and top-level `expect` tests use the compiler directly, without adding a
package manager, test framework, or invented ecosystem policy.

Follow the current official documentation, and revise this template as stable
conventions emerge.

## Not Included

These generic defaults stay out on purpose:

- A floating installer or `latest` URL: it can change without a reviewed
  configuration diff, and an exact immutable tag with digests exists.
- A headerless Echo app: it is a compiler convenience platform with one output
  operation, not a reusable package boundary.
- An external platform: I/O requirements are project-specific. Add one when an
  executable needs it.
- An external formatter, linter, or test runner: the compiler already owns all
  three contracts.
