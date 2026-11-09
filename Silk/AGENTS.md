# Silk Agent Contract

Silk is pre-alpha, and its releases rename and remove standard library APIs.
Trust version-matched sources over memory or silklang.org, which can describe
a different release:

- The standard library source of the pinned release, under
  `$(mise where github:silk-lang/silk)/lib/silk/stdlib`. Its doc comments carry
  checked examples.
- `silk help <command>` for the pinned command line.
- The `reference/` pages of `github.com/silk-lang/silk` at the commit named
  after the `+` in the pinned version.

Follow these rules when you change a Silk package:

- Keep `silk-version` in `silk.toml` equal to the mise pin, and change both
  together.
- Keep tests in the module they test. Import each new module from a reached
  module or list it in `exports`; otherwise Silk never checks it.
- Write doc comments in the style of `documentation-style-guide.md` in those
  `reference/` pages: a summary sentence, then the sections that have
  something to say.
