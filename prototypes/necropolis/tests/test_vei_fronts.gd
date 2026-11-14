extends RefCounted
## Pure-logic tests for VeiFronts: front have/need, phase-1 streams, the break-beats rule,
## backup order, the boss result and the boss-seed adapter. No scene tree, no autoloads.


func _u(uid: String, stats: Dictionary, front := "", place := "party") -> Dictionary:
	var s := {"power": 0.0, "beef": 0.0, "wits": 0.0, "presence": 0.0, "speed": 0.0}
	s.merge(stats, true)
	return {"uid": uid, "stats": s, "front": front, "place": place}


func _info(units: Array, backlog := 0.0, pool := 0.0, q := 1.0) -> Dictionary:
	return {"backlog": backlog, "living_pool": pool, "digest_q": q, "big_undead": units}


func _by(fr: Array, id: String) -> Dictionary:
	for f in fr:
		if f["id"] == id:
			return f
	return {}


func _seed() -> Dictionary:
	var st := {"power": 4.0, "beef": 1.0, "wits": 2.0, "presence": 3.0, "speed": 1.0}
	return {
		"v": 2, "kind": "boss", "run_id": 7, "seed_rev": 3, "rng_seed": "abc",
		"backlog": 5000.0, "living_pool": 400.0, "odds": 0.5, "sign": 1, "drain_s": 10.0,
		"digest_q": 2.0, "vei_capacity": 900.0,
		"fronts": [
			{"id": "giants", "need": 22.0, "have": 2.0, "assigned": ["a"]},
			{"id": "swarm", "need": 20.0, "have": 3.0, "assigned": []},
			{"id": "carvers", "need": 26.0, "have": 0.0, "assigned": []},
			{"id": "raw", "need": 52.0, "have": 4.0, "assigned": ["b"]},
		],
		"fronts_required": 3,
		"party": [
			{"uid": "a", "name": "A", "kind": "undead", "role": "tank", "stats": st, "front": "giants"},
			{"uid": "b", "name": "B", "kind": "undead", "role": "dps", "stats": st, "front": ""},
		],
		"phylactery_charges": 1, "clones_ready": 2, "relish_hp": 30.0,
	}


func run() -> int:
	var t := TestUtil.new()
	var cfg := TestUtil.load_json("res://configs/vei.json")

	# --- have / need ---------------------------------------------------------
	t.suite("vei_have_need")
	t.ok(VeiFronts.FRONT_IDS == ["giants", "swarm", "carvers", "raw"], "front ids in contract order")
	var units := [
		_u("g1", {"wits": 5.0}, "giants"),
		_u("g2", {"wits": 3.0, "power": 9.0}, "giants"),
		_u("s1", {"presence": 4.0}, "swarm"),
		_u("c1", {"beef": 6.0}, "carvers"),
		_u("r1", {"power": 7.0}, "raw"),
	]
	var fr := VeiFronts.have_need(_info(units, 10000.0, 500.0, 2.0), cfg)
	t.ok(fr.size() == 4, "four fronts")
	var ids: Array = []
	for f in fr:
		ids.append(f["id"])
	t.ok(ids == VeiFronts.FRONT_IDS, "returned in FRONT_IDS order")
	t.near(float(_by(fr, "giants")["have"]), 8.0, 0.0001, "giants have = sum of wits")
	t.near(float(_by(fr, "swarm")["have"]), 4.0 + 6.0, 0.0001, "swarm have = presence + 0.0006*backlog")
	t.near(float(_by(fr, "carvers")["have"]), 6.0 + 6.0, 0.0001, "carvers have = beef + 3*q")
	t.near(float(_by(fr, "raw")["have"]), 7.0 + 12.0, 0.0001, "raw have = power + 0.0012*backlog")
	t.near(float(_by(fr, "giants")["need"]), 14.0 + 10.0, 0.0001, "giants need = base + 0.02*pool")
	t.near(float(_by(fr, "raw")["need"]), 40.0 + 15.0, 0.0001, "raw need = base + 0.03*pool")
	t.ok(_by(fr, "giants")["assigned"] == ["g1", "g2"], "assigned lists the counted uids")
	var fr0 := VeiFronts.have_need(_info(units, 10000.0, 0.0, 2.0), cfg)
	t.near(float(_by(fr0, "giants")["need"]), 14.0, 0.0001, "pool 0 gives need_base")
	t.ok(float(_by(fr, "giants")["need"]) > float(_by(fr0, "giants")["need"]), "need scales with living pool")

	# --- counting rule -------------------------------------------------------
	t.suite("vei_counting")
	var sp := [
		_u("p1", {"wits": 9.0, "power": 2.0}),                 # party, unassigned: highest is wits -> giants
		_u("p2", {"power": 5.0, "beef": 5.0}),                  # tie power/beef: FRONT_IDS order -> carvers
		_u("p3", {"presence": 3.0, "wits": 3.0, "power": 3.0}),  # three-way tie -> giants
		_u("x1", {"power": 50.0}, "", "crypt"),                 # unassigned, not party: nowhere
		_u("x2", {"power": 50.0}, "", "town:mill"),
		_u("f1", {"power": 8.0}, "raw", "crypt"),               # assigned, crypt: counts
		_u("f2", {"beef": 2.0}, "carvers", "fort:keep"),        # assigned, fort: counts
		_u("a1", {"power": 99.0}, "swarm", "party"),            # assigned party unit goes to its front
	]
	fr = VeiFronts.have_need(_info(sp), cfg)
	t.ok(_by(fr, "giants")["assigned"] == ["p1", "p3"], "unassigned party: highest stat, ties by FRONT_IDS order")
	t.ok(_by(fr, "carvers")["assigned"] == ["p2", "f2"], "beef/power tie goes to carvers; assigned fort unit counts")
	t.ok(_by(fr, "raw")["assigned"] == ["f1"], "assigned crypt unit counts")
	t.ok(_by(fr, "swarm")["assigned"] == ["a1"], "assignment beats the unit's highest stat")
	var all: Array = []
	for f in fr:
		all.append_array(f["assigned"])
	t.ok(not all.has("x1") and not all.has("x2"), "unassigned non-party units count nowhere")
	t.near(float(_by(fr, "swarm")["have"]), 0.0, 0.0001, "assigned unit adds its front's stat (presence 0), not power")
	t.ok(_by(fr, "giants")["assigned"].size() == 2, "no double counting")

	# --- cleared / fronts_met / required ------------------------------------
	t.suite("vei_cleared")
	var cu := [_u("g", {"wits": 14.0}, "giants"), _u("s", {"presence": 11.0}, "swarm")]
	fr = VeiFronts.have_need(_info(cu), cfg)
	t.ok(bool(_by(fr, "giants")["cleared"]), "have == need clears")
	t.ok(not bool(_by(fr, "swarm")["cleared"]), "have < need does not clear")
	t.ok(VeiFronts.fronts_met(fr) == 1, "fronts_met counts cleared fronts")
	t.ok(VeiFronts.required(cfg) == 3, "required reads fronts_required")
	t.ok(VeiFronts.required({}) == 3, "required defaults to 3")
	t.ok(VeiFronts.required({"fronts_required": 2}) == 2, "required honours cfg")

	# --- missing-cfg defaults ------------------------------------------------
	t.suite("vei_defaults")
	var full := VeiFronts.have_need(_info(units, 10000.0, 500.0, 2.0), cfg)
	var d := VeiFronts.have_need(_info(units, 10000.0, 500.0, 2.0), {})
	for i in 4:
		t.near(float(d[i]["have"]), float(full[i]["have"]), 0.0001, "empty cfg have matches approved defaults (%s)" % d[i]["id"])
		t.near(float(d[i]["need"]), float(full[i]["need"]), 0.0001, "empty cfg need matches approved defaults (%s)" % d[i]["id"])
	var part := VeiFronts.have_need(_info(units, 0.0, 100.0), {"fronts": {"giants": {"need_base": 1.0}}})
	t.near(float(_by(part, "giants")["need"]), 1.0 + 0.02 * 100.0, 0.0001, "a partial front entry fills the rest from defaults")
	t.near(float(_by(part, "raw")["need"]), 40.0 + 3.0, 0.0001, "a missing front entry uses defaults")

	# --- phase 1 -------------------------------------------------------------
	t.suite("vei_phase1")
	var mk := func(have: float, need: float) -> Array:
		var a: Array = []
		for id in VeiFronts.FRONT_IDS:
			a.append({"id": id, "have": have, "need": need, "cleared": have >= need, "assigned": []})
		return a
	var st := VeiFronts.phase1_start(mk.call(20.0, 20.0))
	t.ok(float(st["t"]) == 0.0 and st["fronts"].size() == 4, "phase1_start: t 0, four fronts")
	t.ok(float(st["fronts"][0]["progress"]) == 0.0 and not bool(st["fronts"][0]["cleared"]), "starts uncleared at 0 progress")
	var ref: float = float(cfg["phase1"]["ref_s"])
	var s2: Dictionary = st
	var steps := int(ref * 10.0) - 1
	for i in steps:
		s2 = VeiFronts.phase1_step(s2, 0.1, cfg)
	t.ok(not bool(s2["fronts"][0]["cleared"]), "have == need: not cleared just before ref_s")
	for i in 3:
		s2 = VeiFronts.phase1_step(s2, 0.1, cfg)
	t.ok(bool(s2["fronts"][0]["cleared"]), "have == need clears at about ref_s")
	t.near(float(st["t"]), 0.0, 0.0, "phase1_step does not mutate its input")
	var hi := VeiFronts.phase1_step(VeiFronts.phase1_start(mk.call(100.0, 20.0)), ref / 3.0 + 0.01, cfg)
	t.ok(bool(hi["fronts"][0]["cleared"]), "have 5x need is capped at max_rate 3: clears in ref_s/3")
	var lo := VeiFronts.phase1_start(mk.call(10.0, 20.0))
	for i in 2000:
		lo = VeiFronts.phase1_step(lo, 0.5, cfg)
	t.ok(not bool(lo["fronts"][0]["cleared"]), "have < need never clears on time alone")
	t.ok(float(lo["fronts"][0]["progress"]) <= 0.5 + 0.0001, "stalled progress is at most have/need")
	t.ok(VeiFronts.phase1_outcome(lo, cfg) == "lost", "timeout with too few fronts is lost")
	var early := VeiFronts.phase1_step(VeiFronts.phase1_start(mk.call(10.0, 20.0)), 5.0, cfg)
	t.ok(VeiFronts.phase1_outcome(early, cfg) == "", "mid-phase with too few fronts is undecided")
	var win := VeiFronts.phase1_start(mk.call(20.0, 20.0))
	for i in int(ref * 10.0) + 5:
		win = VeiFronts.phase1_step(win, 0.1, cfg)
	t.ok(VeiFronts.phase1_outcome(win, cfg) == "phase2", "three or more cleared fronts go to phase 2")
	var mixed := VeiFronts.phase1_start([
		{"id": "giants", "have": 20.0, "need": 20.0}, {"id": "swarm", "have": 20.0, "need": 20.0},
		{"id": "carvers", "have": 1.0, "need": 20.0}, {"id": "raw", "have": 1.0, "need": 20.0}])
	for i in 1000:
		mixed = VeiFronts.phase1_step(mixed, 0.1, cfg)
	t.ok(VeiFronts.phase1_outcome(mixed, cfg) == "lost", "two of four at timeout is lost")
	var near_miss := VeiFronts.phase1_start(mk.call(18.0, 20.0))
	near_miss = VeiFronts.phase1_step(near_miss, 30.0, cfg)
	t.ok(not bool(near_miss["fronts"][2]["cleared"]), "near miss front is stuck")
	var tipped := VeiFronts.phase1_add_raise(near_miss, "carvers", [1.0, 1.0], cfg)
	t.near(float(tipped["fronts"][2]["have"]), 18.0 + 2.0 * float(cfg["raise_have_per_mult"]), 0.0001, "raise adds per-mult have")
	t.near(float(near_miss["fronts"][2]["have"]), 18.0, 0.0001, "phase1_add_raise does not mutate its input")
	tipped = VeiFronts.phase1_step(tipped, 30.0, cfg)
	t.ok(bool(tipped["fronts"][2]["cleared"]), "a raise tips the near-miss front over")
	t.ok(not bool(tipped["fronts"][3]["cleared"]), "other fronts untouched by the raise")
	t.near(float(VeiFronts.phase1_add_raise(near_miss, "nope", [1.0], cfg)["fronts"][2]["have"]), 18.0, 0.0001, "unknown front id is ignored")

	# --- phase 2: ferry ------------------------------------------------------
	t.suite("vei_ferry")
	var base := VeiFronts.ferry_rate({"living_pool": 100.0, "digest_q": 1.0}, 1, cfg)
	t.ok(base > 0.0, "ferry is positive")
	t.near(base, 0.5 + 0.01 * 100.0 + 0.5, 0.0001, "ferry formula at q 1")
	t.ok(VeiFronts.ferry_rate({"living_pool": 200.0, "digest_q": 1.0}, 1, cfg) > base, "pool up, ferry up")
	t.ok(VeiFronts.ferry_rate({"living_pool": 100.0, "digest_q": 1.0}, 2, cfg) > base, "uncleared up, ferry up")
	t.ok(VeiFronts.ferry_rate({"living_pool": 100.0, "digest_q": 3.0}, 1, cfg) < base, "q up, ferry down")
	t.near(VeiFronts.ferry_rate({"living_pool": 100.0, "digest_q": 3.0}, 1, cfg), base / (1.0 + 0.25 * 2.0), 0.0001, "q divisor formula")
	t.near(VeiFronts.ferry_rate({"living_pool": 100.0, "digest_q": 0.0}, 1, cfg), base, 0.0001, "q below 1 is treated as 1")
	t.ok(VeiFronts.ferry_rate({"living_pool": 100.0, "digest_q": 1.0}, 1, {}) > 0.0, "ferry works with empty cfg")
	t.near(VeiFronts.raise_value([1.0, 2.0, 0.5], cfg), float(cfg["mote_mass"]) * 3.5, 0.0001, "raise_value = mote_mass * sum mults")
	t.near(VeiFronts.raise_value([], cfg), 0.0, 0.0, "no motes, no value")

	# --- phase 2: break ------------------------------------------------------
	t.suite("vei_break")
	var bs := VeiFronts.break_start()
	t.ok(float(bs["ema"]) == 0.0 and int(bs["streak"]) == 0 and int(bs["beats"]) == 0, "break_start is zeroed")
	var need_beats := int(cfg["break_beats"])
	var b := bs
	var alpha := 1.0 - exp(-1.0 / float(cfg["raise_ema_beats"]))
	b = VeiFronts.break_beat(b, 10.0, 1.0, cfg)
	t.near(float(b["ema"]), 10.0 * alpha, 0.0001, "ema moves by alpha")
	t.ok(int(b["streak"]) == 1 and int(b["beats"]) == 1, "first winning beat starts the streak")
	t.near(float(bs["ema"]), 0.0, 0.0, "break_beat does not mutate its input")
	for i in range(need_beats - 2):
		b = VeiFronts.break_beat(b, 10.0, 1.0, cfg)
	t.ok(int(b["streak"]) == need_beats - 1 and not VeiFronts.broken(b, cfg), "one beat short is not broken")
	var bb := VeiFronts.break_beat(b, 10.0, 1.0, cfg)
	t.ok(VeiFronts.broken(bb, cfg), "broken at exactly break_beats")
	var bad := VeiFronts.break_beat(b, 0.0, 100.0, cfg)
	t.ok(int(bad["streak"]) == 0 and not VeiFronts.broken(bad, cfg), "one bad beat resets the streak")
	t.ok(int(VeiFronts.break_beat(bad, 10.0, 1.0, cfg)["streak"]) == 1, "streak restarts from 1")
	var eq := VeiFronts.break_beat(VeiFronts.break_start(), 0.0, 0.0, cfg)
	t.ok(int(eq["streak"]) == 0, "ema equal to ferry is not enough (strictly greater)")
	t.ok(VeiFronts.broken({"ema": 1.0, "streak": 8, "beats": 8}, {}), "broken defaults break_beats to 8")

	# --- backups -------------------------------------------------------------
	t.suite("vei_backups")
	t.ok(VeiFronts.next_backup({"phylactery": 0, "clones": 0}, 2, 1) == "phylactery", "phylactery first")
	t.ok(VeiFronts.next_backup({"phylactery": 1, "clones": 0}, 2, 1) == "phylactery", "phylactery until charges run out")
	t.ok(VeiFronts.next_backup({"phylactery": 2, "clones": 0}, 2, 1) == "clone", "then a ready clone")
	t.ok(VeiFronts.next_backup({"phylactery": 2, "clones": 1}, 2, 1) == "", "then none")
	t.ok(VeiFronts.next_backup({"phylactery": 0, "clones": 0}, 0, 0) == "", "nothing at all")
	t.ok(VeiFronts.next_backup({"phylactery": 0, "clones": 0}, 0, 2) == "clone", "no charges: clone")

	# --- seed adapter and boss result ---------------------------------------
	t.suite("vei_result")
	var seed := _seed()
	t.ok(Results.validate("boss_seed", seed).is_empty(), "hand-built seed is valid")
	var info := VeiFronts.info_from_boss_seed(seed)
	t.near(float(info["backlog"]), 5000.0, 0.0, "info backlog")
	t.near(float(info["living_pool"]), 400.0, 0.0, "info living_pool")
	t.near(float(info["digest_q"]), 2.0, 0.0, "info digest_q")
	t.ok(info["big_undead"].size() == 2, "party becomes big_undead")
	t.ok(info["big_undead"][0]["place"] == "party" and info["big_undead"][0]["front"] == "giants", "party entry: place party, carries front")
	t.ok(info["big_undead"][1]["front"] == "", "unassigned party entry keeps empty front")
	var sfr := VeiFronts.have_need(info, {})
	t.ok(_by(sfr, "giants")["assigned"] == ["a"], "adapter feeds have_need (assigned)")
	t.ok(_by(sfr, "giants")["assigned"].size() == 1 and _by(sfr, "raw")["assigned"] == ["b"], "adapter feeds have_need (fallback: b is power-led)")

	var spent := {"phylactery": 1, "clones": 1}
	var r := VeiFronts.boss_result(seed, true, ["giants", "raw", "swarm"], 2, spent, ["a"], 120.0)
	t.ok(Results.validate("boss", r).is_empty(), "a win with s deaths validates")
	t.ok(int(r["v"]) == 2 and int(r["run_id"]) == 7 and int(r["seed_rev"]) == 3, "v, run_id and seed_rev from the seed")
	t.ok(r["won"] == true and r["relish_deaths"] == 2 and r["backups_spent"] == spent, "fields carried")
	t.near(float(r["backlog_spent"]), 120.0, 0.0, "backlog_spent carried")
	t.ok(r.keys().size() == 9, "exactly v plus the 8 result keys")
	var rl := VeiFronts.boss_result(seed, false, ["giants"], 3, spent, [], 0.0)
	t.ok(Results.validate("boss", rl).is_empty(), "a loss with s+1 deaths validates")
	t.ok(Results.validate("boss", VeiFronts.boss_result(seed, false, [], 2, spent, [], 0.0)).is_empty(), "a loss with s deaths validates")
	var badw := VeiFronts.boss_result(seed, true, [], 3, spent, [], 0.0)
	t.ok(Results.validate("boss", badw).has("bad_deaths"), "a win with s+1 deaths fails validation")
	var badl := VeiFronts.boss_result(seed, false, [], 5, spent, [], 0.0)
	t.ok(Results.validate("boss", badl).has("bad_deaths"), "a loss with s+3 deaths fails validation")
	var f := VeiFronts.boss_result(seed, false, ["raw", "bogus", "raw", "giants"], 0, {"phylactery": 0, "clones": 0}, ["a", "zzz", "a", "b"], 0.0)
	t.ok(f["fronts_cleared"] == ["raw", "giants"], "unknown and duplicate fronts filtered")
	t.ok(f["party_lost"] == ["a", "b"], "unknown and duplicate party uids dropped")
	t.ok(Results.validate("boss", f).is_empty(), "filtered result validates")

	return t.failures
