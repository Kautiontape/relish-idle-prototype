extends RefCounted
## Pacing mechanics on RealmSim alone, through step(dt, inputs). Only mechanics are asserted: higher
## q lands more undead at Vei, nothing goes negative, idle base minting doesn't win quickly. The
## active-model curve is printed as information; pacing gates are IDLE §8's and move to the E3
## autoplayer (BALANCE §1's thresholds are retired).
## Active model: a pit every ~24 min (the mint P_base + P_per_pit · pits, its feed bonus left out),
## the opening valve, q rising, a raid every 2.5 min with Relish's tide on the raided fort, and four
## simulacra kept deployed.


func _mk(overrides := {}) -> RealmSim:
	var all := TestUtil.configs()
	var cfg: Dictionary = (all["realm"] as Dictionary).duplicate(true)
	for k in overrides:
		cfg[k] = overrides[k]
	var world: Dictionary = (all["world"] as Dictionary).duplicate(true)
	var sim := RealmSim.new()
	sim.setup(world, cfg)
	return sim


func _negative(sim: RealmSim) -> bool:
	for f in sim.forts:
		if f["living"] < -1e-9 or f["dead"] < -1e-9 or f["undead"] < -1e-9:
			return true
	return sim.vei["undead_queue"] < -1e-9 or sim.vei["dead_queue"] < -1e-9 or sim.vei["living_pool"] < -1e-9


func run() -> int:
	var t := TestUtil.new()
	t.suite("pacing")
	var all := TestUtil.configs()
	var cfg: Dictionary = all["realm"]
	var v: Dictionary = all["economy"]["opening"]["valve"]
	var base_mint: float = float(cfg["P_base"]) + float(cfg["P_per_pit"])  # one pit, no feed bonus

	# --- doing nothing must not win the game ---------------------------------
	var sim := _mk()
	var idle := {"war": base_mint * float(v["war"]), "flood": base_mint * float(v["flood"]), "digest_q": float(cfg["q"]["q0"])}
	for i in 3600 * 2:  # 1 sim-hour at dt 0.5
		sim.step(0.5, idle)
	var idle_odds: float = sim.readout()["odds"]
	t.ok(idle_odds < 0.35, "1h idle (base minting only) does not approach victory (odds %.2f)" % idle_odds)
	t.ok(not _negative(sim), "no negative pool after 1h idle")

	# --- the active model's curve, printed as information ---------------------
	var sim2 := _mk()
	var raid_timer := 0.0
	var hours_to_60 := -1.0
	var odds_at_30m := -1.0
	var raid_fort := ""
	var neg := false
	for i in 3600 * 2 * 4:  # 4 sim-hours at dt 0.5
		var dt := 0.5
		var h: float = sim2.elapsed / 3600.0
		var pits: int = 1 + mini(7, int(h * 2.5))
		var mint: float = float(cfg["P_base"]) + float(cfg["P_per_pit"]) * pits
		sim2.step(dt, {"war": mint * float(v["war"]), "flood": mint * float(v["flood"]),
			"digest_q": minf(3.0, 1.2 + 0.45 * h), "tide_fort": raid_fort,
			"tide_bias": float(cfg["relish"]["tide_bias"])})
		raid_timer += dt
		if raid_timer >= 150.0:  # a raid every 2.5 min
			raid_timer = 0.0
			var best: Dictionary = sim2.forts[0]
			for f in sim2.forts:
				if f["living"] > best["living"]:
					best = f
			raid_fort = best["id"]
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
		if _negative(sim2):
			neg = true
		if odds_at_30m < 0.0 and sim2.elapsed >= 1800.0:
			odds_at_30m = sim2.readout()["odds"]
		if hours_to_60 < 0.0 and sim2.readout()["odds"] >= 0.6:
			hours_to_60 = sim2.elapsed / 3600.0
	var ro: Dictionary = sim2.readout()
	print("  [pacing] (info) 30min odds %.3f · 4h odds %.3f · differential %.1f/s · hours to 60%%: %s" %
		[odds_at_30m, ro["odds"], ro["differential"], ("%.2f" % hours_to_60) if hours_to_60 > 0 else "never"])
	t.ok(not neg, "no negative pool over the 4h active model")

	# --- quality is the gate: with digestion off, higher q survives garrisons --
	var lo := _mk({"R_vei": 0.0, "S_vei": 0.0})
	var hi := _mk({"R_vei": 0.0, "S_vei": 0.0})
	for pair in [[lo, 1.0], [hi, 3.0]]:
		var s: RealmSim = pair[0]
		for f in s.forts:
			f["undead"] = f["cap"] * 0.3
		for i in 1200:
			s.step(0.5, {"digest_q": pair[1]})
	t.ok(hi.vei["undead_queue"] > lo.vei["undead_queue"] * 1.05,
		"higher quality lands more undead at Vei (%.0f vs %.0f)" % [hi.vei["undead_queue"], lo.vei["undead_queue"]])

	return t.failures
