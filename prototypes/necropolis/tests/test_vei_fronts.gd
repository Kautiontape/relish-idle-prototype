extends RefCounted
## Pure-logic tests for VeiFronts: front have/need, phase-1 streams, the break-beats rule,
## backup order, the boss result and the boss-seed adapter; and for BossLogic, the boss scene's
## maths (lane geometry, streams, anchors, beat bookkeeping, guards, weaves, the demo seed). No
## scene tree, no autoloads.


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
	var per := float(cfg["raise_have_per_mult"])
	var tip: Array = []   # enough mults of 1.0 to cover the gap of 2 at this tuning
	for i in ceili(2.0 / per - 0.0001):
		tip.append(1.0)
	var tipped := VeiFronts.phase1_add_raise(near_miss, "carvers", tip, cfg)
	t.near(float(tipped["fronts"][2]["have"]), 18.0 + tip.size() * per, 0.0001, "raise adds per-mult have")
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

	_boss_logic(t, cfg)
	return t.failures


func _lanes(cfg: Dictionary) -> Array:
	return BossLogic.lanes(Vector2(2000, 1150), 30.0, Vector2(1000, 230), cfg)


func _boss_logic(t: TestUtil, cfg: Dictionary) -> void:
	# --- lanes ---------------------------------------------------------------
	t.suite("boss_lanes")
	var court := Vector2(1000, 230)
	var ln := _lanes(cfg)
	t.ok(ln.size() == 4, "one lane per front")
	var ids: Array = []
	for l in ln:
		ids.append(l["id"])
	t.ok(ids == VeiFronts.FRONT_IDS, "lanes in FRONT_IDS order")
	var south := true
	var west_to_east := true
	var at_court := true
	for i in ln.size():
		south = south and is_equal_approx((ln[i]["a"] as Vector2).y, 1150.0 - 30.0 - float(cfg["lanes"]["south_margin_px"]))
		at_court = at_court and is_equal_approx((ln[i]["b"] as Vector2).distance_to(court), float(cfg["lanes"]["court_r_px"]))
		if i > 0:
			west_to_east = west_to_east and (ln[i]["a"] as Vector2).x > (ln[i - 1]["a"] as Vector2).x \
				and (ln[i]["b"] as Vector2).x > (ln[i - 1]["b"] as Vector2).x
	t.ok(south, "every lane starts on the same south line")
	t.ok(at_court, "every lane ends court_r_px from Vei")
	t.ok(west_to_east, "lanes run west to east at both ends")
	t.ok((ln[0]["b"] as Vector2).y > court.y and (ln[3]["b"] as Vector2).y > court.y, "lanes end on her south side")
	t.ok(BossLogic.point_at(ln[1], 0.0) == ln[1]["a"] and BossLogic.point_at(ln[1], 1.0) == ln[1]["b"], "point_at spans a..b")
	t.near(BossLogic.lane_len(ln[1]), (ln[1]["a"] as Vector2).distance_to(ln[1]["b"]), 0.001, "lane_len")
	t.near(BossLogic.lane_dir(ln[1]).length(), 1.0, 0.0001, "lane_dir is a unit vector")
	t.ok(BossLogic.lanes(Vector2(2000, 1150), 30.0, court, {}).size() == 4, "lanes work with an empty cfg")

	# --- streams and guard lines --------------------------------------------
	t.suite("boss_streams")
	var s0 := float(cfg["lanes"]["guard_s0"])
	var s1 := float(cfg["lanes"]["guard_s1"])
	t.near(BossLogic.contact_s(0.0, cfg), s0, 0.0001, "contact at progress 0 is guard_s0")
	t.near(BossLogic.contact_s(1.0, cfg), s1, 0.0001, "contact at progress 1 is guard_s1")
	t.near(BossLogic.contact_s(5.0, cfg), s1, 0.0001, "contact clamps above 1")
	t.ok(BossLogic.contact_s(0.5, cfg) > s0 and BossLogic.contact_s(0.5, cfg) < s1, "progress pushes the guard line back")
	t.ok(BossLogic.stream_count(0.0, cfg) == 0 and BossLogic.stream_count(-3.0, cfg) == 0, "no have, no stream")
	t.ok(BossLogic.stream_count(0.1, cfg) == int(cfg["lanes"]["glyphs_min"]), "a little have shows glyphs_min")
	t.ok(BossLogic.stream_count(1.0e6, cfg) == int(cfg["lanes"]["glyphs_max"]), "stream density is capped")
	t.ok(BossLogic.stream_count(30.0, cfg) > BossLogic.stream_count(10.0, cfg), "stream density scales with have")
	t.ok(BossLogic.guard_rows(0.0, cfg) == 1, "a guard line is at least one row")
	t.ok(BossLogic.guard_rows(1.0e6, cfg) == int(cfg["lanes"]["rows_max"]), "guard rows are capped")
	t.ok(BossLogic.guard_rows(50.0, cfg) > BossLogic.guard_rows(15.0, cfg), "guard thickness scales with need")
	var ss := BossLogic.stream_s(10, 0.5, 600.0, 0.0)
	t.ok(ss.size() == 10, "stream_s gives count glyphs")
	var inside := true
	for v in ss:
		inside = inside and v >= 0.0 and v < 0.5
	t.ok(inside, "every glyph sits on 0..s_end")
	t.near(ss[1] - ss[0], 0.05, 0.0001, "glyphs are evenly spaced")
	var sm := BossLogic.stream_s(10, 0.5, 600.0, 12.0)
	t.near(sm[0] - ss[0], 12.0 / 600.0, 0.0001, "march moves the glyphs forward")
	var wrap := BossLogic.stream_s(10, 0.5, 600.0, 30.0)
	t.near(wrap[0], 0.0, 0.0001, "the march wraps a whole spacing")
	t.ok(BossLogic.stream_s(0, 0.5, 600.0, 0.0).is_empty() and BossLogic.stream_s(4, 0.0, 600.0, 0.0).is_empty(), "nothing to draw is empty")

	# --- nearest lane --------------------------------------------------------
	t.suite("boss_nearest")
	t.near(BossLogic.seg_dist(Vector2(5, 3), Vector2(0, 0), Vector2(10, 0)), 3.0, 0.0001, "seg_dist to the middle")
	t.near(BossLogic.seg_dist(Vector2(-4, 3), Vector2(0, 0), Vector2(10, 0)), 5.0, 0.0001, "seg_dist past an end is to the end")
	t.near(BossLogic.seg_t(Vector2(20, 0), Vector2(0, 0), Vector2(10, 0)), 1.0, 0.0, "seg_t clamps")
	for i in 4:
		var p := BossLogic.point_at(ln[i], 0.4) + BossLogic.lane_dir(ln[i]).orthogonal() * 30.0
		t.ok(BossLogic.nearest_lane(p, ln) == i, "a circle beside lane %d feeds lane %d" % [i, i])
	t.ok(BossLogic.nearest_lane(Vector2.ZERO, []) == -1, "no lanes: -1")

	# --- anchors -------------------------------------------------------------
	t.suite("boss_anchors")
	var an := BossLogic.anchors(ln, cfg)
	t.ok(an.size() == int(cfg["anchors"]["count"]), "anchors.count anchors")
	var between := true
	var ls := float(cfg["anchors"]["lane_s"])
	for k in an.size():
		var lx := BossLogic.point_at(ln[k], ls).x
		var rx := BossLogic.point_at(ln[k + 1], ls).x
		between = between and (an[k] as Vector2).x > lx and (an[k] as Vector2).x < rx
	t.ok(between, "one anchor between each pair of lanes")
	t.ok(BossLogic.anchors([], cfg).is_empty(), "no lanes, no anchors")
	t.ok(BossLogic.anchors(ln, {"anchors": {"count": 5}}).size() == 5, "any count spreads along the lanes")

	# --- beats ---------------------------------------------------------------
	t.suite("boss_beats")
	t.near(BossLogic.beat_of(3.428, 1.714), 2.0, 0.0001, "beat_of")
	t.ok(BossLogic.beats_crossed(0.9, 1.1) == 1, "crossing a beat counts one")
	t.ok(BossLogic.beats_crossed(-0.01, 0.0) == 1, "beat 0 counts")
	t.ok(BossLogic.beats_crossed(1.2, 1.3) == 0, "inside a beat counts none")
	t.ok(BossLogic.beats_crossed(0.5, 3.5) == 3, "a long step counts every beat")
	t.ok(BossLogic.beats_crossed(2.0, 1.0) == 0, "going back counts none")
	var t0 := BossLogic.align_t(0.25, 2.0)
	t.near(t0, -1.5, 0.0001, "align_t: beat 0 on the next boundary")
	t.ok(BossLogic.beats_crossed(BossLogic.beat_of(t0, 2.0), BossLogic.beat_of(t0 + 1.5, 2.0)) == 1, "beat 0 lands after the rest of the Pulse beat")
	t.near(BossLogic.ferry_per_beat(2.0, 1.714, cfg), 2.0 * 1.714 * float(cfg["ferry_beat_scale"]), 0.0001, "ferry per beat = F * tempo * scale")
	t.near(BossLogic.ferry_per_beat(-1.0, 1.714, cfg), 0.0, 0.0, "no negative ferry")
	# the break on the beat clock: a raise of V every 4 beats against F per beat
	var fpb := 1.0
	var run := func(v: float, every: int, beats_n: int) -> Dictionary:
		var st := VeiFronts.break_start()
		var mx := 0
		for b in beats_n:
			st = VeiFronts.break_beat(st, v if b % every == 0 else 0.0, fpb, cfg)
			mx = maxi(mx, int(st["streak"]))
			if VeiFronts.broken(st, cfg):
				return {"broken": true, "beat": b, "max": mx}
		return {"broken": false, "beat": -1, "max": mx}
	var strong: Dictionary = run.call(10.0, 4, 60)
	t.ok(bool(strong["broken"]), "raises well above the ferry break her")
	var weak: Dictionary = run.call(2.0, 4, 60)
	t.ok(not bool(weak["broken"]) and int(weak["max"]) < int(cfg["break_beats"]), "raises that dip below the ferry between them never break her")
	t.ok(not bool(run.call(0.0, 1, 60)["broken"]), "no raising, no break")

	# --- horde, accruals, guards --------------------------------------------
	t.suite("boss_horde")
	t.near(BossLogic.horde_step(10.0, 3.0, 1.0), 7.0, 0.0001, "the ferry drains the horde")
	t.near(BossLogic.horde_step(1.0, 3.0, 1.0), 0.0, 0.0, "the horde stops at 0")
	t.near(BossLogic.backlog_spent(100.0, 40.0), 60.0, 0.0, "backlog spent = H0 - H")
	t.near(BossLogic.backlog_spent(100.0, 140.0), 0.0, 0.0, "backlog spent is never negative")
	var ac := BossLogic.accrue(0.6, 2.0, 0.5)
	t.ok(int(ac["n"]) == 1, "accrue: whole events")
	t.near(float(ac["acc"]), 0.6, 0.0001, "accrue: the fraction carries")
	t.near(BossLogic.anchor_mote_rate(4.0, cfg), 4.0 * float(cfg["anchors"]["motes_per_ferry"]), 0.0001, "anchor motes scale with the ferry")
	t.ok(BossLogic.anchor_mote_rate(8.0, cfg) > BossLogic.anchor_mote_rate(2.0, cfg), "the faster she ferries, the more essence")
	var gnone := BossLogic.guard_spawn(0.0, 100.0, 0, 0, cfg)
	t.ok(int(gnone["n"]) == 0, "no uncleared front, no guards")
	var rate := float(cfg["guards"]["rate_per_uncleared"])
	var g1 := BossLogic.guard_spawn(0.0, 2.0 / rate, 1, 0, cfg)
	t.ok(int(g1["n"]) == 2, "one uncleared front sends rate_per_uncleared guards a second")
	t.ok(int(BossLogic.guard_spawn(0.0, 2.0 / rate, 2, 0, cfg)["n"]) == 4, "two uncleared fronts send twice as many")
	var cap := int(cfg["guards"]["cap"])
	var gc := BossLogic.guard_spawn(0.0, 1000.0, 1, cap - 1, cfg)
	t.ok(int(gc["n"]) == 1, "spawns stop at the cap")
	t.ok(float(gc["acc"]) <= 1.0, "at the cap the lanes don't bank a flood")
	t.ok(int(BossLogic.guard_spawn(0.5, 1000.0, 1, cap, cfg)["n"]) == 0, "full: none")

	# --- weaves --------------------------------------------------------------
	t.suite("boss_weaves")
	var o := Vector2(1000, 230)
	var e := BossLogic.ray_to_bounds(o, Vector2(1000, 600), Vector2(2000, 1150), 30.0)
	t.ok(e.is_equal_approx(Vector2(1000, 1120)), "a weave runs on to the south wall")
	var e2 := BossLogic.ray_to_bounds(o, Vector2(1500, 730), Vector2(2000, 1150), 30.0)
	t.ok(is_equal_approx(e2.y, 1120.0) and e2.x > 1500.0, "a diagonal weave is clipped by the first wall")
	var e3 := BossLogic.ray_to_bounds(o, Vector2(1900, 300), Vector2(2000, 1150), 30.0)
	t.ok(is_equal_approx(e3.x, 1970.0), "an east weave stops at the east wall")
	t.ok(BossLogic.ray_to_bounds(o, o, Vector2(2000, 1150), 30.0).is_equal_approx(Vector2(1000, 1120)), "a degenerate aim runs south")
	t.ok(BossLogic.weave_hits(o, e, Vector2(1020, 700), 32.0), "on the thread: hit")
	t.ok(not BossLogic.weave_hits(o, e, Vector2(1060, 700), 32.0), "stepped off the thread: missed")
	t.ok(BossLogic.is_tell(3.5, 4.0, 1.0) and not BossLogic.is_tell(2.9, 4.0, 1.0) and not BossLogic.is_tell(4.0, 4.0, 1.0), "the tell shows one beat ahead")

	# --- the seed and the demo ----------------------------------------------
	t.suite("boss_seed")
	var demo := BossLogic.demo_seed(cfg)
	t.ok(Results.validate("boss_seed", demo).is_empty(), "the demo seed is a valid boss seed")
	t.ok(BossLogic.seed_fronts_empty(demo), "the demo's fronts are economy's pre-E3 zeros")
	t.ok(not BossLogic.seed_fronts_empty(_seed()), "a seed with have/need is used as is")
	t.ok(BossLogic.seed_fronts_empty({}), "no fronts at all: compute them")
	var dfr := VeiFronts.have_need(VeiFronts.info_from_boss_seed(demo), cfg)
	t.ok(VeiFronts.fronts_met(dfr) == 3, "the demo meets 3 of 4 fronts with the default numbers")
	t.ok(not bool(_by(dfr, "raw")["cleared"]), "the demo is short on raw")
	demo["backlog"] = 1.0
	t.ok(float(BossLogic.demo_seed(cfg)["backlog"]) > 1.0, "demo_seed is a copy")
	var pl := BossLogic.party_lanes(BossLogic.demo_seed(cfg), cfg)
	t.ok(int(pl["u1"]) == 2 and int(pl["u2"]) == 2, "assigned carvers lead the carvers lane")
	t.ok(int(pl["u3"]) == 0 and int(pl["u4"]) == 0, "assigned giants lead the giants lane")
	t.ok(int(pl["u5"]) == 1, "an unassigned member leads its highest stat's lane (presence: swarm)")
	var ff := BossLogic.force_fronts(dfr, 2, cfg)
	t.ok(VeiFronts.fronts_met(ff) == 2 and bool(ff[0]["cleared"]) and bool(ff[1]["cleared"]), "--boss-fronts=2: the first two met")
	t.ok(float(ff[2]["have"]) <= float(ff[2]["need"]) * float(cfg["demo"]["force_unmet_frac"]) + 0.0001, "the rest short by force_unmet_frac")
	t.ok(VeiFronts.fronts_met(BossLogic.force_fronts(dfr, 4, cfg)) == 4, "--boss-fronts=4: all met")
	t.ok(VeiFronts.fronts_met(dfr) == 3, "force_fronts does not mutate its input")
	t.ok(BossLogic.backups_left({"phylactery": 1, "clones": 0}, 1, 2) == 2, "backups left")
	t.ok(BossLogic.backups_left({"phylactery": 3, "clones": 5}, 1, 2) == 0, "backups left never negative")
	t.ok(BossLogic.rng_int("42") == 42 and BossLogic.rng_int("-3317425092215838120") == -3317425092215838120, "rng_int reads an int seed")
	t.ok(BossLogic.rng_int("abc") == hash("abc"), "rng_int hashes anything else")

	# --- a window close mid-fight (IDLE I5) ---------------------------------
	t.suite("boss_close")
	var cs := _seed()
	var sp := {"phylactery": 1, "clones": 1}
	for reason in ["", "fronts_held", "horde_ferried", "closed"]:
		var cf := BossLogic.close_fields(reason, 2)
		t.ok(not bool(cf["won"]) and int(cf["relish_deaths"]) == 2, "close mid-fight (%s): lost, deaths = backups spent" % reason)
		var cr := VeiFronts.boss_result(cs, false, [], int(cf["relish_deaths"]), sp, [], 0.0)
		t.ok(Results.validate("boss", cr).is_empty(), "close mid-fight (%s) validates" % reason)
	var cfd := BossLogic.close_fields("relish_unmade", 2)
	t.ok(not bool(cfd["won"]) and int(cfd["relish_deaths"]) == 3, "close in the final-death beat: lost, deaths = spent + 1")
	t.ok(Results.validate("boss", VeiFronts.boss_result(cs, false, [], 3, sp, [], 0.0)).is_empty(), "the final-death close validates")
	var cfw := BossLogic.close_fields("broken", 2)
	t.ok(bool(cfw["won"]) and int(cfw["relish_deaths"]) == 2, "close after she broke: the win, deaths = spent")
	t.ok(Results.validate("boss", VeiFronts.boss_result(cs, true, ["giants"], 2, sp, [], 0.0)).is_empty(), "the win on close validates")
	var c0 := BossLogic.close_fields("", 0)
	t.ok(not bool(c0["won"]) and int(c0["relish_deaths"]) == 0, "close before any death: lost, no deaths")
	t.ok(Results.validate("boss", VeiFronts.boss_result(cs, false, [], 0, {"phylactery": 0, "clones": 0}, [], 0.0)).is_empty(),
		"a close with no backup spent validates")
	t.ok(int(BossLogic.close_fields("", -3)["relish_deaths"]) == 0, "close_fields never counts negative deaths")

	# --- the result's fronts_cleared, whichever phase the fight ended in ----
	t.suite("boss_result_fronts")
	var p1 := VeiFronts.phase1_start([
		{"id": "giants", "have": 30.0, "need": 20.0}, {"id": "swarm", "have": 25.0, "need": 20.0},
		{"id": "carvers", "have": 5.0, "need": 20.0}, {"id": "raw", "have": 5.0, "need": 40.0}])
	for i in 1000:
		p1 = VeiFronts.phase1_step(p1, 0.1, cfg)
	t.ok(VeiFronts.phase1_outcome(p1, cfg) == "lost", "fixture: two of four at the timeout is a phase-1 loss")
	t.ok(BossLogic.cleared_ids(p1["fronts"]) == ["giants", "swarm"], "cleared_ids lists the cleared fronts in order")
	var none := {"phylactery": 0, "clones": 0}
	var lost1 := BossLogic.fight_result(cs, false, p1, [], false, 0, none, [], 0.0, 0.0)
	t.ok(lost1["fronts_cleared"] == ["giants", "swarm"], "a phase-1 loss reports the fronts it cleared")
	t.ok(Results.validate("boss", lost1).is_empty(), "the phase-1 loss validates")
	var died1 := BossLogic.fight_result(cs, false, p1, [], false, 1, none, [], 0.0, 0.0)
	t.ok(died1["fronts_cleared"] == ["giants", "swarm"] and Results.validate("boss", died1).is_empty(),
		"a final death in phase 1 reports them too")
	var mid := VeiFronts.phase1_start([{"id": "giants", "have": 30.0, "need": 20.0}, {"id": "swarm", "have": 5.0, "need": 20.0}])
	t.ok(BossLogic.fight_result(cs, false, mid, [], false, 0, none, [], 0.0, 0.0)["fronts_cleared"] == [],
		"a close before any front clears reports none")
	var brk := BossLogic.fight_result(cs, true, p1, ["giants", "swarm", "carvers"], true, 0, none, [], 100.0, 40.0)
	t.ok(brk["fronts_cleared"] == ["giants", "swarm", "carvers"], "after the break began: the fronts cleared in phase 1")
	t.near(float(brk["backlog_spent"]), 60.0, 0.0001, "backlog spent = H0 - H")
	t.near(float(lost1["backlog_spent"]), 0.0, 0.0, "a phase-1 ending spends no horde")
