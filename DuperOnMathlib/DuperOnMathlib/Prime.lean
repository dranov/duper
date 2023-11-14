import Duper.Tactic
import Mathlib.Data.Nat.Prime
import Mathlib.Tactic.Linarith

namespace Nat

set_option auto.tptp.solver.name "zipperposition"

#check Nat.prime_def_lt -- Reproving this theorem using duper:

/- Note: This example struggles when full preprocessing is enabled. It can be solved reasonably quickly
   if preprocessing is set to monomorphization or no_preprocessing -/
theorem prime_def_lt_DUPER {p : ℕ} : Prime p ↔ 2 ≤ p ∧ ∀ m < p, m ∣ p → m = 1 := by
  have : 2 ≤ p → 0 < p := by intro; linarith
  duper [*, Nat.prime_def_lt'', Nat.le_of_dvd, Nat.lt_of_le_of_ne, Nat.lt_irrefl] {preprocessing := monomorphization}

#check Nat.prime_def_lt' -- Reproving this theorem using duper:

theorem prime_def_lt'_DUPER {p : ℕ} : Prime p ↔ 2 ≤ p ∧ ∀ (m : ℕ), 2 ≤ m → m < p → ¬m ∣ p := by
  constructor
  · have : ¬ 2 ≤ 1 := by duper [Nat.two_le_iff]
    duper [*, prime_def_lt_DUPER]
  · have : (∀ (m : ℕ), 2 ≤ m → m < p → ¬m ∣ p) →  ∀ m < p, m ∣ p → m = 1
    · duper [Nat.two_le_iff, Nat.not_eq_zero_of_lt, Nat.eq_zero_of_zero_dvd]
    duper [*, prime_def_lt_DUPER]

#check prime_def_le_sqrt -- Reproving this theorem using duper:

-- h2 times out if reduceInstances is set to false
theorem prime_def_le_sqrt_DUPER' {p : ℕ} : Prime p ↔ 2 ≤ p ∧ ∀ m, 2 ≤ m → m ≤ sqrt p → ¬m ∣ p := by
  constructor
  · have : ∀ m, 2 ≤ m → 1 < m := by intros; linarith
    duper [*, prime_def_lt', sqrt_lt_self, Nat.lt_of_le_of_lt]
  · intro h
    rw [prime_def_lt']
    refine ⟨h.1, ?_⟩
    have h₂ : ∀ m, 2 ≤ m → m < p → m ∣ p → 2 ≤ (p / m) := by
      duper [*, Nat.lt_irrefl, Nat.dvd_iff_div_mul_eq, Nat.mul_zero, Nat.one_mul, two_le_iff] {portfolioInstance := 1}
    duper [*, Nat.div_dvd_of_dvd, Nat.dvd_iff_div_mul_eq, le_sqrt, Nat.mul_le_mul_right,
      Nat.mul_le_mul_left, mul_comm, Nat.le_total] {portfolioInstance := 1}
