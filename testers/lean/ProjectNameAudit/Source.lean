import ProjectNameAudit.Finding
import ProjectNameAudit.Policy

/-!
# Source audit

Checks every owned `.lean` file: the text rules that stand in for a formatter,
and syntax rules the compiler cannot express. Files are elaborated again, so the
rules see the same syntax the compiler saw, including scoped notation.
-/

namespace ProjectNameAudit

open Lean System

/-- Keywords no owned file may contain, grouped by what each one does. `isBannedAtom` also bans
every `#` command and every `builtin_` and `register_` command. -/
def bannedAtoms : List String :=
  -- Bypasses the kernel or hides code from it.
  ["sorry", "admit", "native_decide", "bv_decide", "bv_check", "axiom", "opaque", "partial",
    "noncomputable", "decreasing_by", "termination_by", "extern", "test_extern", "init_quot",
    -- Changes options that belong in the Lake configuration.
    "set_option", "unlock_limits",
    -- Runs code during elaboration, or defines syntax, macros, elaborators, simplification
    -- procedures, or initializers.
    "run_cmd", "run_elab", "run_meta", "run_tac", "set_library_suggestions", "macro",
    "macro_rules", "syntax", "declare_syntax_cat", "elab", "elab_rules", "elab_stx_quot",
    "declare_config_elab", "declare_config_elab_legacy", "declare_command_config_elab",
    "declare_command_config_elab_legacy", "declare_core_config_elab",
    "declare_term_config_elab", "declare_simp_like_tactic", "binder_predicate", "notation",
    "infix", "infixl", "infixr", "prefix", "postfix", "initialize", "simproc", "simproc_decl",
    "dsimproc", "dsimproc_decl", "cbv_simproc", "cbv_simproc_decl", "simproc_pattern%",
    "cbv_simproc_pattern%", "grind_propagator", "declare_sint_simprocs",
    "declare_uint_simprocs",
    -- Leaves an unpinned search behind.
    "simp?", "simp?!", "simp_all?", "simp_all?!", "dsimp?", "dsimp?!", "simpa?", "simpa?!",
    "exact?", "apply?", "rw?", "try?", "grind?", "bv_decide?", "mvcgen?"]

/-- Whether a keyword is a `#` command, such as `#eval` or `#print`. The literal openers `#[`
and `#v[` are not commands. -/
def isHashCommand (value : String) : Bool :=
  match value.toList with
  | '#' :: first :: rest =>
    first.isAlpha &&
      rest.all (fun (char : Char) => char.isAlphanum || char == '_' || char == '!' || char == '?')
  | _ => false

/-- Whether an owned file of the given role may not contain a keyword. `builtin_` commands
belong to Lean itself, and every `register_` command declares an initializer. The audit tool
may use `unsafe`, because it must call Lean's importer. -/
def isBannedAtom (role : Role) (value : String) : Bool :=
  bannedAtoms.contains value || isHashCommand value || value.startsWith "builtin_" ||
    value.startsWith "register_" || (value == "unsafe" && role != .audit)

/-- Attributes no owned declaration may carry, grouped by what each one does. `isBannedAttribute`
also bans every `builtin_` attribute and every parser attribute. -/
def bannedAttributes : List Name :=
  -- Replaces or exposes compiled code without kernel checking.
  [`implemented_by, `export, `extern, `never_extract, `csimp, `cpass,
    -- Runs code at initialization, which the audit itself performs when it imports a module.
    `init,
    -- Registers code the elaborator, simplifier, or pretty printer runs.
    `command_elab, `term_elab, `tactic, `macro, `doElem_elab, `doElem_control_info,
    `inductive_elab, `grind_tactic, `try_tactic, `try_suggestion, `library_suggestions,
    `sym_discharger, `sym_simproc, `sym_dsimproc, `frameproc, `simprocAttr, `sevalprocAttr,
    `cbvSimprocAttr, `simprocBuiltinAttr, `sevalprocBuiltinAttr, `cbvSimprocBuiltinAttr,
    `grindPropagatorBuiltinAttr, `delab, `app_unexpander, `formatter, `parenthesizer,
    `combinator_formatter, `combinator_parenthesizer, `category_parenthesizer, `quot_precheck,
    `run_parser_attribute_hooks, `run_builtin_parser_attribute_hooks, `doc_role,
    `doc_directive, `doc_code_block, `doc_command, `doc_block_md, `doc_inline_md,
    `doc_code_block_suggestions, `doc_code_suggestions, `deferred_doc_check,
    -- Registers code a linter runs, including the audit's own linter pass, or exempts a
    -- declaration from a linter.
    `env_linter, `nolint, `missing_docs_handler, `unused_variables_ignore_fn,
    `package_code_quality_check,
    -- Registers code the language server runs.
    `code_action_provider, `command_code_action, `hole_code_action, `server_rpc_method,
    `widget_module]

/-- Whether no owned declaration may carry an attribute. `builtin_` attributes belong to Lean
itself, and every parser attribute registers code the parser runs. -/
def isBannedAttribute (name : Name) : Bool :=
  bannedAttributes.contains name || name.toString.startsWith "builtin_" ||
    name.toString.endsWith "_parser"

/-- The attribute an attribute instance applies, named as Lean's elaborator names it: the
identifier of a simple attribute, otherwise the last component of its syntax kind. -/
def attributeName? (stx : Syntax) : Option Name :=
  if stx.isOfKind ``Lean.Parser.Term.attrInstance then
    let attr : Syntax := stx[1]
    if attr.isOfKind ``Lean.Parser.Attr.simple then some attr[0].getId.eraseMacroScopes
    else
      match attr.getKind with
      | .str _ last => some (Name.mkSimple last)
      | _ => none
  else none

/-- Simplifier tactics that must name their lemmas with `only`. -/
def onlyRequired : List SyntaxNodeKind :=
  [``Lean.Parser.Tactic.simp, ``Lean.Parser.Tactic.simpAll, ``Lean.Parser.Tactic.dsimp,
    ``Lean.Parser.Tactic.simpa, ``Lean.Parser.Tactic.simpaUsingBang,
    ``Lean.Parser.Tactic.simpArith, ``Lean.Parser.Tactic.simpAllArith,
    ``Lean.Parser.Tactic.simpAutoUnfold, ``Lean.Parser.Tactic.dsimpAutoUnfold]

/-- Characters that render invisibly or reorder text, so source can read differently from
what the compiler sees. -/
def invisibleChars : List Char :=
  [0x00A0, 0x00AD, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2028, 0x2029, 0x202A, 0x202B,
    0x202C, 0x202D, 0x202E, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF].map Char.ofNat

/-- The module name a source path compiles to. -/
def moduleOf (path : FilePath) : Name :=
  (path.withExtension "").components.foldl
    (fun (name : Name) (component : String) =>
      if component == "." then name else Name.str name component)
    Name.anonymous

/-- Every `.lean` file under the project, skipping hidden directories such as `.lake`. -/
def sourceFiles : IO (Array FilePath) := do
  let files : Array FilePath ← FilePath.walkDir "."
    (fun (dir : FilePath) => pure !((dir.fileName.getD "").startsWith "."))
  pure ((files.filter (fun (file : FilePath) => file.extension == some "lean")).qsort
    (fun (left : FilePath) (right : FilePath) => left.toString < right.toString))

/-- Text rules: LF line endings, no tabs, no trailing whitespace, no invisible characters,
bounded line length, and exactly one final newline. -/
def textFindings (path : FilePath) (text : String) : Array Finding := Id.run do
  let mut findings : Array Finding := #[]
  let lines : List String := text.splitOn "\n"
  let mut number : Nat := 0
  for line in lines do
    number := number + 1
    let at_ : String := s!"{path}:{number}"
    if line.contains '\r' then
      findings := findings.push ⟨at_, "carriage return; use LF line endings"⟩
    if line.contains '\t' then
      findings := findings.push ⟨at_, "tab character; indent with spaces"⟩
    if line.endsWith " " then
      findings := findings.push ⟨at_, "trailing whitespace"⟩
    if line.any (fun (char : Char) => invisibleChars.contains char) then
      findings := findings.push ⟨at_, "invisible or bidirectional control character"⟩
    if line.length > maxLineLength then
      findings := findings.push ⟨at_, s!"line longer than {maxLineLength} characters"⟩
  if !text.endsWith "\n" || text.endsWith "\n\n" then
    findings := findings.push ⟨s!"{path}", "file must end with exactly one newline"⟩
  pure findings

/-- Whether a simplifier call names its lemmas with `only`, searching its own arguments but
not nested tactic blocks. -/
def hasOnly (stx : Syntax) : Bool :=
  let level1 : Array Syntax := stx.getArgs
  let level2 : Array Syntax := level1.flatMap (fun (child : Syntax) => child.getArgs)
  let level3 : Array Syntax := level2.flatMap (fun (child : Syntax) => child.getArgs)
  (level1 ++ level2 ++ level3).any (fun (child : Syntax) => child.isToken "only")

/-- Whether a binder syntax carries its type. Bare names, holes, and anonymous constructor
patterns do not. -/
def isTypedBinder (binder : Syntax) : Bool :=
  binder.isOfKind ``Lean.Parser.Term.typeAscription ||
    binder.isOfKind ``Lean.Parser.Term.instBinder ||
    (binder.isOfKind ``Lean.Parser.Term.explicitBinder && binder[2].getNumArgs > 0) ||
    (binder.isOfKind ``Lean.Parser.Term.implicitBinder && binder[2].getNumArgs > 0) ||
    (binder.isOfKind ``Lean.Parser.Term.strictImplicitBinder && binder[2].getNumArgs > 0)

/-- The binder rule for one syntax node: every binder that can carry a type does. -/
def binderMessage (stx : Syntax) : Option String :=
  let kind : SyntaxNodeKind := stx.getKind
  if kind == ``Lean.Parser.Term.explicitBinder || kind == ``Lean.Parser.Term.implicitBinder ||
      kind == ``Lean.Parser.Term.strictImplicitBinder then
    if stx[2].getNumArgs == 0 then some "binder without a type" else none
  else if kind == ``Lean.Parser.Command.optDeclSig then
    if stx[0].getArgs.any (fun (binder : Syntax) => !isTypedBinder binder) then
      some "declaration binder without a type"
    else none
  else if kind == ``Lean.Parser.Command.definition || kind == ``Lean.Parser.Command.abbrev then
    if stx[2][1].getNumArgs == 0 then some "definition without a result type" else none
  else if kind == ``Lean.Parser.Command.declSig then
    if stx[0].getArgs.any (fun (binder : Syntax) => !isTypedBinder binder) then
      some "declaration binder without a type"
    else none
  else if kind == ``Lean.Parser.Term.basicFun then
    let untyped : Bool := stx[0].getArgs.any (fun (binder : Syntax) => !isTypedBinder binder)
    if stx[1].getNumArgs == 0 && untyped then some "fun binder without a type" else none
  else if kind == ``Lean.Parser.Term.forall then
    let untyped : Bool := stx[1].getArgs.any (fun (binder : Syntax) => !isTypedBinder binder)
    if stx[2].getNumArgs == 0 && untyped then some "∀ binder without a type" else none
  else if kind == `Lean.unbracketedExplicitBinders then
    if stx[1].getNumArgs == 0 then some "∃ binder without a type" else none
  else if kind == ``Lean.Parser.Term.letIdDecl then
    if stx[2].getNumArgs == 0 then some "let or have without a type" else none
  else if kind == ``Lean.Parser.Term.doIdDecl then
    if stx[1].getNumArgs == 0 then some "do binding without a type" else none
  else if kind == ``Lean.Parser.Tactic.intro then
    if stx[1].getArgs.any (fun (binder : Syntax) => !isTypedBinder binder) then
      some "intro without a type"
    else none
  else none

/-- Syntax rules for one node, given the role of the file it is in. -/
def nodeMessages (role : Role) (stx : Syntax) : List String :=
  let atomRule : List String :=
    match stx with
    | .atom _ value => if isBannedAtom role value then [s!"banned keyword `{value}`"] else []
    | _ => []
  let attributeRule : List String :=
    match attributeName? stx with
    | some name => if isBannedAttribute name then [s!"banned attribute `{name}`"] else []
    | none => []
  let simpRule : List String :=
    if onlyRequired.contains stx.getKind && !hasOnly stx then
      ["simplifier call without `only`"]
    else []
  let nativeRule : List String :=
    if (stx.isOfKind ``Lean.Parser.Tactic.posConfigItem ||
        stx.isOfKind ``Lean.Parser.Tactic.valConfigItem) && stx[1].getId == `native then
      ["native evaluation bypasses the kernel"]
    else []
  let binderRule : List String := (binderMessage stx).toList
  atomRule ++ attributeRule ++ simpRule ++ nativeRule ++ binderRule

/-- The result of elaborating one file: its header and commands as syntax, its messages, and
the environment it produced. -/
structure Elaborated where
  /-- The header followed by every command. -/
  commands : Array Syntax
  /-- Every message elaboration logged. -/
  messages : MessageLog
  /-- The environment after the last command. -/
  env : Environment

/-- Elaborates one file as module `module`. `allowInitializers` must re-enable initializer
execution: each import consumes it. -/
def elaborateFile (allowInitializers : BaseIO Unit) (path : FilePath) (text : String)
    (module : Name) : IO Elaborated := do
  allowInitializers
  let inputCtx : Parser.InputContext := Parser.mkInputContext text path.toString
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ←
    Elab.processHeader header {} messages inputCtx (trustLevel := 1024) (mainModule := module)
  let state : Elab.Frontend.State ←
    Elab.IO.processCommands inputCtx parserState (Elab.Command.mkState env messages {})
  pure (Elaborated.mk (#[header.raw] ++ state.commands) state.commandState.messages
    state.commandState.env)

/-- Syntax findings for one file. -/
def syntaxFindings (allowInitializers : BaseIO Unit) (path : FilePath) (text : String)
    (role : Role) : IO (Array Finding) := do
  let elaborated : Elaborated ← elaborateFile allowInitializers path text (moduleOf path)
  let fileMap : FileMap := text.toFileMap
  let mut findings : Array Finding := #[]
  for message in elaborated.messages.toList do
    if message.severity == .error then
      findings := findings.push
        ⟨s!"{path}:{message.pos.line}", s!"does not elaborate: {← message.data.toString}"⟩
  for command in elaborated.commands do
    for stx in command.topDown do
      for message in nodeMessages role stx do
        let line : Nat := match stx.getPos? with
          | some pos => (fileMap.toPosition pos).line
          | none => 0
        findings := findings.push ⟨s!"{path}:{line}", message⟩
  pure findings

/-- Formatting findings for every owned file: the text rules alone. -/
def formatAudit : IO (Array Finding) := do
  let mut findings : Array Finding := #[]
  for path in ← sourceFiles do
    findings := findings ++ textFindings path (← IO.FS.readFile path)
  pure findings

/-- Source findings for every owned file: ownership and syntax rules. -/
def sourceAudit (allowInitializers : BaseIO Unit) : IO (Array Finding) := do
  let mut findings : Array Finding := #[]
  if ← FilePath.pathExists "lakefile.lean" then
    findings := findings.push ⟨"lakefile.lean", "use lakefile.toml; it cannot run code"⟩
  for path in ← sourceFiles do
    match roleOf (moduleOf path) with
    | none =>
      findings := findings.push ⟨s!"{path}", "not part of an owned module root"⟩
    | some role =>
      findings := findings ++
        (← syntaxFindings allowInitializers path (← IO.FS.readFile path) role)
  pure findings

end ProjectNameAudit
