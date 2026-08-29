extends RefCounted
## Pacing sanity: does the math support a few hours of "undead number go up"?
## Simulates hours of play headlessly and prints the curve for the decision log.
## Progression model of active play: slabs built every ~24 min, forge levels
## raise q over time, a raid every 2.5 min, simulacra kept deployed.


func _mk(overrides := {}) -> RealmSim:
	var cfg := TestUtil.load_json("res://configs/realm.json")
	for k in overrides:
		cfg[k] = overrides[k]
	var world := TestUtil.load_json("res://configs/world.json")
	var sim := RealmSim.new()
	sim.setup(world, cfg)
	return sim


func run() -> int:
	var t := TestUtil.new()
	t.suite("pacing")

	# --- doing nothing must not win the game ---------------------------------
	var sim := _mk()
	for i in 3600 * 2:  # 1 sim-hour at dt 0.5
		sim.step(0.5)
	var idle_odds: float = sim.readout()["odds"]
	t.ok(idle_odds < 0.35, "1h idle (base minting only) does not approach victory (odds %.2f)" % idle_odds)

	# --- an active factory ramps to confrontation viability in ~1.5-4h --------
	var sim2 := _mk()
	var raid_timer := 0.0
	var hours_to_60 := -1.0
	var odds_at_30m := -1.0
	var total_steps := 3600 * 2 * 4  # 4 sim-hours at dt 0.5
	for i in total_steps:
		var dt := 0.5
		var h: float = sim2.elapsed / 3600.0
		var slabs: int = 1 + mini(7, int(h * 2.5))
		sim2.t["P_base"] = 2.0 + 6.0 * slabs
		sim2.t["q"] = minf(3.0, 1.2 + 0.45 * h)
		sim2.step(dt)
		raid_timer += dt
		if raid_timer >= 150.0:  # a raid every 2.5 min
			raid_timer = 0.0
			var best: Dictionary = sim2.forts[0]
			for f in sim2.forts:
				if f["living"] > best["living"]:
					best = f
			var killed: float = best["living"] * 0.35
			best["living"] -= killed
			best["dead"] += killed
			var chaff: float = best["dead"] * 0.55
			best["dead"] -= chaff
			sim2.vei["undead_queue"] += chaff
			best["undead"] += best["dead"] * 0.3
			best["dead"] *= 0.7
			while sim2.simulacra.size() < 4:
				sim2.simulacra.append({"fort_id": best["id"], "charges": 400.0, "rate": 4.0})
		if odds_at_30m < 0.0 and sim2.elapsed >= 1800.0:
			odds_at_30m = sim2.readout()["odds"]
		if hours_to_60 < 0.0 and sim2.readout()["odds"] >= 0.6:
			hours_to_60 = sim2.elapsed / 3600.0
	var final_odds: float = sim2.readout()["odds"]
	var ro: Dictionary = sim2.readout()
	print("  [pacing] 30min odds %.3f · 4h odds %.3f · differential %.1f/s · hours to 60%%: %s" %
		[odds_at_30m, final_odds, ro["differential"], ("%.2f" % hours_to_60) if hours_to_60 > 0 else "never"])
	t.ok(odds_at_30m < 0.25, "30 min in, victory still far away (odds %.2f)" % odds_at_30m)
	t.ok(final_odds > 0.55, "active factory reaches viable odds within 4 sim-hours (%.2f)" % final_odds)
	t.ok(hours_to_60 < 0.0 or hours_to_60 > 0.75, "victory is not reachable in under ~45 min of active play")

	# --- quality is the gate: with digestion off, higher q survives garrisons --
	var lo := _mk({"q": 1.0, "P_base": 0.0, "R_vei": 0.0, "S_vei": 0.0})
	var hi := _mk({"q": 3.0, "P_base": 0.0, "R_vei": 0.0, "S_vei": 0.0})
	for s in [lo, hi]:
		for f in s.forts:
			f["undead"] = f["cap"] * 0.3
		for i in 1200:
			s.step(0.5)
	t.ok(hi.vei["undead_queue"] > lo.vei["undead_queue"] * 1.05,
		"higher quality lands more undead at Vei (%.0f vs %.0f)" % [hi.vei["undead_queue"], lo.vei["undead_queue"]])

	return t.failures
