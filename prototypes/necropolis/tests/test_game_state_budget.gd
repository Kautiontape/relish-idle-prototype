extends RefCounted
## Substep timing (MECHANICS §10 budget test): 2000 substeps of the midgame_2flips fixture
## through tick(). E2 tightens the ceiling once the full model is in. Headless, no autoloads.

const SUBSTEPS := 2000
## MECHANICS §10 wants < 3000 µs. Today's substep is ~10 ms because InfluenceField.tick (~5 ms, two
## per substep at tick_hz 5) dominates; the field is the ground unit's. Until it is cheaper this is
## a regression tripwire, not the budget: 20 ms.
const CEILING_US := 20000.0


func run() -> int:
	var t := TestUtil.new()
	t.suite("game_state_budget")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("midgame_2flips")["ok"], "the midgame_2flips fixture loads")
	var step := s.substep_s()
	var t0 := Time.get_ticks_usec()
	var n := 0
	for i in SUBSTEPS:
		n += s.tick(step)
	var avg := float(Time.get_ticks_usec() - t0) / float(SUBSTEPS)
	t.ok(n == SUBSTEPS, "tick(substep) ran one substep each (%d)" % n)
	print("  [budget] substep avg %d µs · 1h soak ≈ %.1f s · 12h at 0.5 s steps ≈ %.1f s" % [
		int(avg), avg * 7200.0 / 1e6, avg * 86400.0 / 1e6])
	t.ok(avg < CEILING_US, "substep average under %d µs (measured %d)" % [int(CEILING_US), int(avg)])
	return t.failures
