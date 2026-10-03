import ProjectNameAudit.Environment
import ProjectNameAudit.Manifest
import ProjectNameAudit.SelfTest
import ProjectNameAudit.Source

/-!
# ProjectName audit

Lake's lint driver. Each subcommand prints its findings and exits nonzero if
there are any:

* `self-test`: proves every source and environment rule fires on a module that
  breaks it, and that none fires on a compliant one.
* `format`: text rules for every owned `.lean` file.
* `source`: ownership and syntax rules for every owned `.lean` file.
* `manifest`: toolchain and dependency pinning.
* `environment`: kernel, axiom, spec, documentation, linter, and IR rules for the
  library and executable.
* `test-environment`: the same rules for the test harness, which defines its own
  `main` and so needs its own environment.
* `library-declarations` and `executable-declarations`: print the written
  declarations of that role, for the external kernel checker.

Without a subcommand, every check runs, each in its own process: importing an
environment with extensions can be done once per process.
-/

open Lean ProjectNameAudit

/-- Library and executable roots, audited in one environment. -/
def shippedRoots : Array Name := #[`ProjectName, `ProjectNameMain]

/-- Test roots, audited separately because they also define `main`. -/
def testRoots : Array Name := #[`ProjectNameTests]

/-- Owned modules, by source path, whose role places them in the given roots' audit. -/
def modulesFor (roles : List Role) : IO (Array Name) := do
  let modules : Array Name := (← sourceFiles).map moduleOf
  pure (modules.filter (fun (module : Name) =>
    match roleOf module with
    | some role => roles.contains role
    | none => false))

/-- Runs one subcommand and returns its exit code. `allowInitializers` re-enables initializer
execution, which each environment import consumes. -/
def runCheck (allowInitializers : BaseIO Unit) (check : String) : IO UInt32 := do
  match check with
  | "self-test" => report check (← selfTest allowInitializers)
  | "format" => report check (← formatAudit)
  | "source" => report check (← sourceAudit allowInitializers)
  | "manifest" => report check (← manifestAudit)
  | "environment" =>
    report check (← environmentAudit shippedRoots (← modulesFor [.library, .executable]))
  | "test-environment" => report check (← environmentAudit testRoots (← modulesFor [.tests]))
  | "library-declarations" =>
    (← roleDeclarations shippedRoots .library).forM (fun (name : Name) => IO.println name)
    pure 0
  | "executable-declarations" =>
    (← roleDeclarations shippedRoots .executable).forM (fun (name : Name) => IO.println name)
    pure 0
  | other =>
    IO.eprintln s!"unknown audit check `{other}`"
    pure 2

/-- Every check, in the order the full audit runs them. -/
def allChecks : List String :=
  ["self-test", "format", "manifest", "source", "environment", "test-environment"]

/-- Runs one check in a child process of this executable and returns its exit code. -/
def runChild (check : String) : IO UInt32 := do
  let child : IO.Process.Child {} ←
    IO.Process.spawn { cmd := (← IO.appPath).toString, args := #[check] }
  child.wait

/-- Runs one requested check, or every check in its own process. -/
unsafe def main (args : List String) : IO UInt32 := do
  initSearchPath (← findSysroot)
  enableInitializersExecution
  match args with
  | [] =>
    let codes : List UInt32 ← allChecks.mapM runChild
    pure (codes.foldl max 0)
  | [check] => runCheck enableInitializersExecution check
  | _ =>
    IO.eprintln "usage: project_name_audit [check]"
    pure 2
