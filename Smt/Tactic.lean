import Lean
import Smt.Query
import Smt.Solver

namespace Smt

open Lean
open Lean.Elab
open Lean.Elab.Tactic

initialize
  registerTraceClass `Smt.debug
  registerTraceClass `Smt.debug.attr
  registerTraceClass `Smt.debug.query
  registerTraceClass `Smt.debug.transformer

instance : Lean.KVMap.Value Kind where
  toDataValue
    | Kind.cvc5 => "cvc5"
    | Kind.z3   => "z3"
  ofDataValue?
    | "cvc5" => Kind.cvc5
    | "z3" => Kind.z3
    | _ => none

register_option Smt.solver.kind : Kind := {
  defValue := Kind.cvc5
  descr := "The solver to use for solving the SMT query."
}

register_option Smt.solver.path : String := {
  defValue := "cvc5"
  descr := "The path to the solver used for the solving the SMT query."
}

/-- `smt` converts the current goal into an SMT query and checks if it is
satisfiable. By default, `smt` generates the minimum valid SMT query needed to
assert the current goal. However, that is not always enough:
```lean
def modus_ponens (p q : Prop) (hp : p) (hpq : p → q) : q := by
  smt
```
For the theorem above, `smt` generates the query below:
```smt2
(declare-const q Bool)
(assert (not q))
(check-sat)
```
which is missing the hypotheses `hp` and `hpq` required to prove the theorem. To
pass hypotheses to the solver, use `smt [h₁, h₂, ..., hₙ]` syntax:
```lean
def modus_ponens (p q : Prop) (hp : p) (hpq : p → q) : q := by
  smt [hp, hpq]
```
The tactic then generates the query below:
```smt2
(declare-const q Bool)
(assert (not q))
(declare-const p Bool)
(assert p)
(assert (=> p q))
(check-sat)
```
-/
syntax (name := smt) "smt" ("[" ident,+,? "]")? : tactic

def queryToString (commands : List String) : String :=
  String.intercalate "\n" ("(check-sat)\n" :: commands).reverse

def parseTactic : Syntax → TacticM (List Expr)
  | `(tactic| smt)       => pure []
  | `(tactic| smt [$[$hs],*]) => hs.toList.mapM (fun h => elabTerm h none)
  | _                    => throwUnsupportedSyntax

@[tactic smt] def evalSmt : Tactic := fun stx => withMainContext do
  -- 1. Get the current main goal.
  let goalType ← Tactic.getMainTarget
  let goalId ← Lean.mkFreshFVarId
  Lean.Meta.withLocalDeclD goalId.name (mkNot goalType) fun goal => do
  -- 2. Get the free vars in the goal and the ones passed to the tactic.
  let mut hs := goal :: (← parseTactic stx)
  hs := hs.eraseDups
  -- 3. Generate the SMT query.
  let mut solver := Solver.mk []
  solver ← Query.generateQuery hs solver
  let query := queryToString solver.commands
  -- 4. Run the solver.
  let kind := Smt.solver.kind.get (← getOptions)
  let path := Smt.solver.path.get (← getOptions)
  -- 5. Print the result.
  let res ← solver.checkSat kind path
  logInfo m!"goal: {goalType}\n\nquery:\n{query}\nresult: {res}"

end Smt
