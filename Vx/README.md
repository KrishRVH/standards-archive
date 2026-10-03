# Vx Standards

[Vx](https://vxlang.org/) is a systems programming language for machines that
are no longer a single processor. It compiles through MLIR to native x86-64 and
AArch64 code, NVIDIA PTX, and Apple accelerator instructions. The best starting
points are the official [documentation](https://vxlang.org/docs/) and the
[language reference](https://github.com/vx-lang/Vx/tree/main/docs/lang).

Vx is at v0.0.2, a research-stage compiler. Its syntax, standard library,
diagnostics, and project conventions may all change. It defines no package
manifest or test runner yet. This profile is a small, reproducible way to
explore the language, not a claim that its ecosystem has converged.

## Why Vx Is Here

Vx puts heterogeneous hardware into the type system:

- Where a value lives, such as `Memory::CPU_DRAM` or `Memory::GPU_HBM`, and
  where code runs, such as `Topology::GPU[0]`, are types. Reading device memory
  from a host, or host memory from a device, is a compile error that names the
  missing `transfer`, not a runtime fault.
- Data crosses address spaces only through an explicit `transfer`, and work
  moves to a device only through `spawn on(Topology::...)`. Placement and data
  movement stay visible in the source.
- Machine files declare memories, capacities, and bus costs, so one program can
  be admitted against several hardware models with `vxc --machine`. Capacity
  overruns become compile errors rather than out-of-memory crashes hours into a
  run.
- `requires` and `ensures` contracts are proved at compile time with z3. A
  contract the prover cannot establish rejects the program.

Most languages leave memory placement to a runtime API. Vx's experiment is
whether the compiler can own it, which is why it belongs in this catalog this
early.

## Baseline

Copy `src/`, `tests/`, `scripts/`, and `Mise/conf.d/20-vx.toml` into a Vx
project. Replace `project_name` in file names and the test's `import` with the
real module name.

The fixture is CPU-only and runs without a GPU. Its library proves a small
contract, and its test program imports the library from the project root with
`import src::project_name;` and checks results with the standard library's
`std::googletest`. A failed expectation aborts the program, so every
`tests/*_test.vx` program is a test.

The standards workflow is:

```sh
mise run vx:standards
mise run vx:fmt:check
mise run vx:lint
mise run vx:test
mise run vx:standards:check
```

`vx:fmt` formats Git-tracked and unignored `.vx` files with the bundled
`vx-format`. That formatter only rewrites files in place and has no check mode,
so `scripts/format.sh` formats a staged copy, compares it, and rejects symlinks.
`vx-format` accepts some sources that fail to parse, so `vx:lint` stays the
parser of record.

`vx:lint` runs the compiler's type, placement, borrow, and contract checks on
every `.vx` file under `src/` and `tests/`, without code generation. The
compiler exits zero on warnings, so the task reads warning counts from its
versioned `--diagnostics-json` report and fails on any warning.

`vx:test` runs each `tests/*_test.vx` program through the compiler's JIT. The
release binaries do not bundle LLVM. At run time `vxc` calls `mlir-translate`,
`opt`, `llc`, and `clang` from LLVM 22, and it links the MLIR runner libraries
and libffi. The fragment pins those from conda-forge, and it pins z3 for
contract proofs. The conda-forge packages put `llvm-config` and the unversioned
MLIR runner libraries in separate packages. `vxc` asks `llvm-config` only for
`--libdir`, so `scripts/llvm-config` answers that one query with the pinned
`libmlir` path. The installed toolchain is about 4 GB.

The committed fixture lock verifies Linux x64. The fragment also names the
macOS arm64 compiler and z3 assets, but this repository does not verify them.
The scripts require a POSIX shell.

## Not Included

These generic defaults stay out on purpose:

- The `curl | sh` installer: it resolves the latest release and the host's
  system LLVM at install time. The fragment pins an exact release with digests
  and a reviewed LLVM.
- The CUDA build and GPU, NPU, or Apple Neural Engine examples: they need hardware the gate
  cannot assume. Add a `--machine` admission check when a project targets real
  devices.
- `--verify-seams`: it proves cross-device transfer obligations, and a
  CPU-only fixture has no seams to prove.
- A package manifest, build system, or external test framework: Vx defines
  none yet. Revise this template as upstream conventions emerge.
