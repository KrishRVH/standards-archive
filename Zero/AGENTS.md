# Zero Agent Contract

`zero.graph` is the compiler input; `.0` files are its projection. Load the
version-matched workflow with `zero skills get agent` before editing.

- Edit through `zero patch`. Edit `.0` text only for changes no patch
  operation expresses, then run `zero import .`.
- Never delete `zero.graph` to force a reimport.
- Never run `zero import` over a projection while the graph holds unexported
  patches: it discards them. Run `zero export .` first.
- Commit `zero.graph` with its projection. Keep `.zero/` and `.program-graph`
  artifacts untracked.
- Run `zero explain <code>` for any diagnostic code before repairing it.
