import LeanHammer.MClause
import LeanHammer.RuleM
import LeanHammer.Simp
import LeanHammer.Util.ProofReconstruction

namespace Schroedinger
open Lean
open RuleM
open SimpResult

--TODO: move?
theorem not_of_eq_false (h: p = False) : ¬ p := 
  fun hp => h ▸ hp

--TODO: move?
theorem of_not_eq_false (h: (¬ p) = False) : p := 
  Classical.byContradiction fun hn => h ▸ hn

--TODO: move?
theorem eq_true_of_not_eq_false (h : (¬ p) = False) : p = True := 
  eq_true (of_not_eq_false h)

--TODO: move?
theorem eq_false_of_not_eq_true (h : (¬ p) = True) : p = False := 
  eq_false (of_eq_true h)

--TODO: move?
theorem clausify_and_left (h : (p ∧ q) = True) : p = True := 
  eq_true (of_eq_true h).left

--TODO: move?
theorem clausify_and_right (h : (p ∧ q) = True) : q = True := 
  eq_true (of_eq_true h).right

--TODO: move?
theorem clausify_and_false (h : (p ∧ q) = False) : p = False ∨ q = False := by
  apply @Classical.byCases p
  · intro hp 
    apply @Classical.byCases q
    · intro hq
      exact False.elim $ not_of_eq_false h ⟨hp, hq⟩
    · intro hq
      exact Or.intro_right _ (eq_false hq)
  · intro hp
    exact Or.intro_left _ (eq_false hp)

--TODO: move?
theorem clausify_or (h : (p ∨ q) = True) : p = True ∨ q = True := 
  (of_eq_true h).elim 
    (fun h => Or.intro_left _ (eq_true h))
    (fun h => Or.intro_right _ (eq_true h))

--TODO: move?
theorem clausify_or_false_left (h : (p ∨ q) = False) : p = False := 
  eq_false fun hp => not_of_eq_false h (Or.intro_left _ hp)

--TODO: move?
theorem clausify_or_false_right (h : (p ∨ q) = False) : q = False := 
  eq_false fun hp => not_of_eq_false h (Or.intro_right _ hp)


--TODO: move?
theorem clausify_imp (h : (p → q) = True) : (¬ p) = True ∨ q = True := 
  (Classical.em q).elim 
    (fun hq => Or.intro_right _ (eq_true hq)) 
    (fun hq => Or.intro_left _ (eq_true (fun hp => hq ((of_eq_true h) hp))))

--TODO: move?
theorem clausify_imp_false_left (h : (p → q) = False) : p = True := 
  Classical.byContradiction fun hnp => 
    not_of_eq_false h fun hp => 
      False.elim (hnp $ eq_true hp)

--TODO: move?
theorem clausify_imp_false_right (h : (p → q) = False) : q = False := 
  eq_false fun hq => not_of_eq_false h fun _ => hq

--TODO: move?
theorem clausify_forall {p : α → Prop} (x : α) (h : (∀ x, p x) = True) : p x = True := 
  eq_true (of_eq_true h x)

--TODO: move?
theorem clausify_exists_false {p : α → Prop} (x : α) (h : (∃ x, p x) = False) : p x = False := 
  eq_false (fun hp => not_of_eq_false h ⟨x, hp⟩)

def clausificationStepE (e : Expr) (sign : Bool): 
    RuleM (SimpResult (List (MClause × Option (Expr → MetaM Expr)))) := do
  match sign, e with
  | true, Expr.app (Expr.const ``Not _ _) e _ => do
    let res ← clausificationStepE e false
    res.mapM fun res => res.mapM fun (c, pr?) => do 
      return (c, ← pr?.mapM fun pr => do 
        let pr : Expr → MetaM Expr := fun premise => do
          return ← pr $ ← Meta.mkAppM ``eq_false_of_not_eq_true #[premise]
        return pr)
  | false, Expr.app (Expr.const ``Not _ _) e _ => do
    let res ← clausificationStepE e true
    res.mapM fun res => res.mapM fun (c, pr?) => do 
      return (c, ← pr?.mapM fun pr => do 
        let pr : Expr → MetaM Expr := fun premise => do
          return ← pr $ ← Meta.mkAppM ``eq_true_of_not_eq_false #[premise]
        return pr)
  | true, Expr.app (Expr.app (Expr.const ``And _ _) e₁ _) e₂ _ => do
    let pr₁ : Expr → MetaM Expr := fun premise => do
      return ← Meta.mkAppM ``clausify_and_left #[premise]
    let pr₂ : Expr → MetaM Expr := fun premise => do
      return ← Meta.mkAppM ``clausify_and_right #[premise]
    Applied [(MClause.mk #[Lit.fromExpr e₁], some pr₁), (MClause.mk #[Lit.fromExpr e₂], some pr₂)]
  | true, Expr.app (Expr.app (Expr.const ``Or _ _) e₁ _) e₂ _ =>
    let pr : Expr → MetaM Expr := fun premise => do
      return ← Meta.mkAppM ``clausify_or #[premise]
    Applied [(MClause.mk #[Lit.fromExpr e₁, Lit.fromExpr e₂], some pr)]
  | true, Expr.forallE _ ty b _ => do
    if (← inferType ty).isProp
    then
      if b.hasLooseBVars then
        throwError "Types depending on props are not supported" 
      let pr : Expr → MetaM Expr := fun premise => do
        return ← Meta.mkAppM ``clausify_imp #[premise]
      Applied [(MClause.mk #[Lit.fromExpr (mkNot ty), Lit.fromExpr b], some pr)]
    else 
      let mvar ← mkFreshExprMVar ty
      let pr : Expr → MetaM Expr := fun premise => do
        let mvar ← Meta.mkFreshExprMVar ty
        return ← Meta.mkAppM ``clausify_forall #[mvar, premise]
      Applied [(MClause.mk #[Lit.fromExpr $ b.instantiate1 mvar], some pr)]
  | true, Expr.app (Expr.app (Expr.const ``Exists _ _) ty _) (Expr.lam _ _ b _) _ => do
    clausifyExists ty b
  | false, Expr.app (Expr.app (Expr.const ``And _ _) e₁ _) e₂ _  => 
    let pr : Expr → MetaM Expr := fun premise => do
      return ← Meta.mkAppM ``clausify_and_false #[premise]
    Applied [(MClause.mk #[Lit.fromExpr e₁ false, Lit.fromExpr e₂ false], some pr)]
  | false, Expr.app (Expr.app (Expr.const ``Or _ _) e₁ _) e₂ _ =>
    let pr₁ : Expr → MetaM Expr := fun premise => do
      return ← Meta.mkAppM ``clausify_or_false_left #[premise]
    let pr₂ : Expr → MetaM Expr := fun premise => do
      return ← Meta.mkAppM ``clausify_or_false_right #[premise]
    Applied [(MClause.mk #[Lit.fromExpr e₁ false], some pr₁), 
             (MClause.mk #[Lit.fromExpr e₂ false], some pr₂)]
  | false, Expr.forallE _ ty b _ => do
    if (← inferType ty).isProp
    then 
      if b.hasLooseBVars then
        throwError "Types depending on props are not supported"
      let pr₁ : Expr → MetaM Expr := fun premise => do
        return ← Meta.mkAppM ``clausify_imp_false_left #[premise]
      let pr₂ : Expr → MetaM Expr := fun premise => do
        return ← Meta.mkAppM ``clausify_imp_false_right #[premise]
      Applied [(MClause.mk #[Lit.fromExpr ty], some pr₁),
               (MClause.mk #[Lit.fromExpr b false], some pr₂)]
    else clausifyExists ty (mkNot b)
  | false, Expr.app (Expr.app (Expr.const ``Exists _ _) ty _) (Expr.lam _ _ b _) _ => do
    let mvar ← mkFreshExprMVar ty
    let pr : Expr → MetaM Expr := fun premise => do
      let mvar ← Meta.mkFreshExprMVar ty
      return ← Meta.mkAppM ``clausify_exists_false #[mvar, premise]
    Applied [(MClause.mk #[Lit.fromExpr (b.instantiate1 mvar) false], some pr)]
  | true, Expr.app (Expr.app (Expr.app (Expr.const ``Eq [lvl] _) ty _) e₁ _) e₂ _  =>
    let pr : Expr → MetaM Expr := fun premise => do
      return ← Meta.mkAppM ``of_eq_true #[premise]
    Applied [(MClause.mk #[{sign := true, lhs := e₁, rhs := e₂, lvl := lvl, ty := ty}], some pr)]
  | false, Expr.app (Expr.app (Expr.app (Expr.const ``Eq [lvl] _) ty _) e₁ _) e₂ _  =>
    let pr : Expr → MetaM Expr := fun premise => do
      return ← Meta.mkAppM ``not_of_eq_false #[premise] 
    Applied [(MClause.mk #[{sign := false, lhs := e₁, rhs := e₂, lvl := lvl, ty := ty}], some pr)]
  | true, Expr.app (Expr.app (Expr.app (Expr.const ``Ne [lvl] _) ty _) e₁ _) e₂ _  =>
    let pr : Expr → MetaM Expr := fun premise => do
      return ← Meta.mkAppM ``of_eq_true #[premise]
    Applied [(MClause.mk #[{sign := false, lhs := e₁, rhs := e₂, lvl := lvl, ty := ty}], some pr)]
  | false, Expr.app (Expr.app (Expr.app (Expr.const ``Ne [lvl] _) ty _) e₁ _) e₂ _  =>
    let pr : Expr → MetaM Expr := fun premise => do
      return ← ← Meta.mkAppM ``of_not_eq_false #[premise]
    Applied [(MClause.mk #[{sign := true, lhs := e₁, rhs := e₂, lvl := lvl, ty := ty}], some pr)]
  | _, _ => Unapplicable
where
  clausifyExists ty b := do
    let mVarIds ← (e.collectMVars {}).result
    let ty := ty.abstractMVars (mVarIds.map mkMVar)
    let mVarIdTys ← (mVarIds.mapM (fun mvarId => do ← inferType (mkMVar mvarId)))
    let ty := mVarIdTys.foldr
      (fun mVarIdTy ty => mkForall `_ BinderInfo.default mVarIdTy ty)
      ty
    trace[Meta.debug] "##TY: {ty}"
    let fvar ← mkFreshSkolem `sk (← instantiateMVars ty) b
    let b ← b.instantiate1 (mkAppN fvar (mVarIds.map mkMVar))
    Applied [(MClause.mk #[Lit.fromExpr b], none)]

def clausificationStepLit (l : Lit) : RuleM (SimpResult (List (MClause × Option (Expr → MetaM Expr)))) := do
  match l.rhs with
  | Expr.const ``True _ _ => clausificationStepE l.lhs true
  | Expr.const ``False _ _ => clausificationStepE l.lhs false
  | _ => return Unapplicable
-- TODO: True/False on left-hand side?

-- TODO: Proof reconstruction
def clausificationStep : MSimpRule := fun c => do
  for i in [:c.lits.size] do
    match ← clausificationStepLit c.lits[i] with
    | Applied ds =>
      return Applied $ ds.map fun (d, dproof) => 
        let mkProof : ProofReconstructor := 
          fun (premises : Array Expr) (parents: Array ProofParent) (res : Clause) => do
            Meta.forallTelescope res.toForallExpr fun xs body => do
              let resLits := res.lits.map (fun l => l.map (fun e => e.instantiateRev xs))
              let (parentLits, appliedPremise) ← instantiatePremises parents premises xs
              let parentLits := parentLits[0]
              let appliedPremise := appliedPremise[0]
              
              let mut caseProofs := #[]
              for j in [:parentLits.size] do
                let lit := parentLits[j]
                let pr ← Meta.withLocalDeclD `h lit.toExpr fun h => do
                  if j == i then
                    let resLeft := resLits.toList.take (c.lits.size - 1)
                    let resRight := resLits.toList.drop (c.lits.size - 1)
                    let resRight := (Clause.mk #[] resRight.toArray).toForallExpr
                    let resLits' := (resLeft.map Lit.toExpr).toArray.push resRight
                    -- TODO: use dproof and h
                    let dproof ← match dproof with
                    | none => Meta.mkSorry resRight true
                    | some dproof => dproof h
                    if not (← Meta.isDefEq (← Meta.inferType dproof) resRight) then
                      throwError "Error when reconstructing clausification. Expected type: {resRight}, but got: {dproof}"
                    Meta.mkLambdaFVars #[h] $ ← orIntro resLits' (c.lits.size - 1) dproof
                  else
                    let idx := if j ≥ i then j - 1 else j
                    Meta.mkLambdaFVars #[h] $ ← orIntro (resLits.map Lit.toExpr) idx h
                caseProofs := caseProofs.push $ pr

              let r ← orCases (← parentLits.map Lit.toExpr) body caseProofs
              trace[Meta.debug] "###RES {res}"
              trace[Meta.debug] "###R {← Meta.inferType r}"
              let r ← Meta.mkLambdaFVars xs $ mkApp r appliedPremise
              trace[Meta.debug] "###R {r}"
              r
        (⟨c.lits.eraseIdx i ++ d.lits⟩, mkProof)
    | Removed => 
      return Removed
    | Unapplicable => 
      continue
  return Unapplicable

end Schroedinger