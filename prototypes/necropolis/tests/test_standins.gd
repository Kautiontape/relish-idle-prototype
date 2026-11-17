extends RefCounted
## E3-6a: the balance stand-ins (configs/balance_standins.json) and the headless raid resolver the autoplayer resolves
## raids with (tests/autoplay/standin_resolver.gd, StandinResolver: a library this suite calls by its class_name; the
## runner only discovers tests/test_*.gd, so it is never run as a suite). BALANCE §8, IDLE §8.
## - shape: the shipped file has every key the resolver reads (StandinResolver.problem), the GUESS and the held
##   door's label, and nothing under scripts/sim/ names it.
## - validity: N_VALID seeds in each of seven cases (tiers 1-4, the first dungeon, a held fort, the held door), each
##   issued by cmd_begin_dungeon on a real game: every result passes Results.validate("raid") and the real
##   apply_result, the ledger stays balanced after each, the same seed resolves byte-identically, and a held fort's
##   clear raises counter_garrison_cleared.
## - convergence: N_DRAWS draws per entry at yield 1.0: the death rate, the flip (or a held clear's retreat) rate and
##   the mean loot per kind are within Z standard errors of the entry (binomial for the rates, the sample's for the
##   means); then yield 0.5 halves the dropped kinds and leaves essence (BALANCE §8).
## - the phylactery revive, determinism, the held door (its gate, its big in party_lost, its relics) and opts.deaths.

const Ledger := preload("res://scripts/sim/ledger.gd")
const N_VALID := 200
const N_DRAWS := 2000
const Z := 4.0  # the tolerance, in standard errors either way
const TOL := 1e-6  # the ledger invariant, relative (STATE-API §4.7)
const KINDS := ["relics", "remnants", "husks", "blueprints", "essence"]

var t := TestUtil.new()
var _cfgs: Dictionary
var _sb: Dictionary


func run() -> int:
	t.suite("standins")
	_cfgs = TestUtil.configs()
	_sb = _cfgs.get("balance_standins", {})
	_shape()
	_validity()
	_convergence()
	_yield()
	_revive()
	_masses()
	_determinism()
	_door()
	_opts()
	return t.failures


# ------------------------------------------------------------------ helpers ---
func _fort(id: String) -> Dictionary:
	for f in _cfgs["world"]["forts"]:
		if str(f["id"]) == id:
			return f
	return {}


## The dungeon unit's own "party of tier T" seed at a world fort (RaidLogic.profile_seed: no phylactery charge, first
## flags false, yield 1), with `patch` laid over it (its "fort" key merged into the seed's fort).
func _profile(id: String, party_tier: int, patch := {}) -> Dictionary:
	var sd := RaidLogic.profile_seed(_fort(id), party_tier, _cfgs["raid"])
	for k in patch:
		if k == "fort":
			for fk in patch["fort"]:
				sd["fort"][fk] = patch["fort"][fk]
		else:
			sd[k] = patch[k]
	return sd


func _first_seed() -> Dictionary:
	return _profile("old-sluice", 1, {"fort": {"first_dungeon": true, "first_clear": true}, "chest_husk": true,
		"starter_units": 8, "garrison_units": 0, "garrison_in_mass": 0.0, "undead": 0.0, "party": []})


## `n` resolves of `sd`, its rng_seed varied: the exits, the runs with a revive or the door's big lost, and each loot
## kind's mean and standard error.
func _draws(sd: Dictionary, opts: Dictionary, n := N_DRAWS) -> Dictionary:
	var s := sd.duplicate(true)
	var c := {"n": n, "relish_died": 0, "warden_beaten": 0, "retreated": 0, "revived": 0, "max_revived": 0,
		"door_taken": 0, "door_lost": 0, "door_lost_on_win": 0}
	var sum := {}
	var sq := {}
	for k in KINDS:
		sum[k] = 0.0
		sq[k] = 0.0
	for i in n:
		s["rng_seed"] = str(9001 + 7919 * i)
		var o := StandinResolver.resolve(s, _sb, _cfgs, opts)
		var r: Dictionary = o["result"]
		for ex in ["relish_died", "warden_beaten", "retreated"]:
			if r[ex]:
				c[ex] += 1
		c["revived"] += 1 if int(r["revived_in_place"]) > 0 else 0
		c["max_revived"] = maxi(int(c["max_revived"]), int(r["revived_in_place"]))
		if o["notes"]["door_taken"]:
			c["door_taken"] += 1
			if (r["party_lost"] as Array).has(o["notes"]["door_uid"]):
				c["door_lost"] += 1
				c["door_lost_on_win"] += 1 if r["warden_beaten"] else 0
		var lc := RaidLogic.loot_counts(r["loot"])
		for k in KINDS:
			sum[k] += float(lc[k])
			sq[k] += float(lc[k]) * float(lc[k])
	c["mean"] = {}
	c["se"] = {}
	for k in KINDS:
		var m: float = sum[k] / n
		c["mean"][k] = m
		c["se"][k] = sqrt(maxf(0.0, sq[k] / n - m * m) / n)
	return c


## An entry's expected loot per run at death rate `d` and yield `y`: mean_loot on a win, kept_frac of it on a death,
## the dropped kinds × y (essence unscaled), plus the chest's guaranteed husk and first-clear blueprint on a win.
func _expect(e: Dictionary, d: float, first_clear: bool, chest_husk: bool, y := 1.0) -> Dictionary:
	var out := {}
	for k in KINDS:
		var m := float(e["mean_loot"][k])
		out[k] = ((1.0 - d) * m + d * m * float(e["kept_frac"][k])) * (1.0 if k == "essence" else y)
	out["husks"] += (1.0 - d) * (1.0 if chest_husk else 0.0)
	out["blueprints"] += (1.0 - d) * (1.0 if first_clear else 0.0)
	return out


func _rate(what: String, got: int, n: int, p: float) -> void:
	var tol := Z * sqrt(p * (1.0 - p) / n) + 1e-9
	var x := float(got) / n
	t.ok(absf(x - p) <= tol, "%s: %d/%d = %.4f against %.4f (± %.4f)" % [what, got, n, x, p, tol])


func _mean(what: String, got: float, se: float, want: float) -> void:
	var tol := Z * se + 1e-9
	t.ok(absf(got - want) <= tol, "%s: %.4f against %.4f (± %.4f)" % [what, got, want, tol])


func _game() -> GameState:
	var s := GameState.new(_cfgs)
	s.cmd_new_game(7)
	s.debug_enabled = true
	return s


## Party of `want` bigs: the ones the game has first, then minted.
func _set_party(s: GameState, want: int) -> void:
	var pool: Array = []
	for b in s.big_undead:
		pool.append(str(b["uid"]))
	if pool.size() < want:
		pool.append_array(s.cmd_debug_grant({"big_undead": want - pool.size()})["applied"]["minted"])
	s.cmd_set_party(pool.slice(0, want))


# -------------------------------------------------------------------- shape ---
func _shape() -> void:
	t.ok(StandinResolver.problem(_sb) == "", "the shipped stand-ins have every key the resolver reads: '%s'" % StandinResolver.problem(_sb))
	var cut := _sb.duplicate(true)
	(cut["2"] as Dictionary).erase("death_t_frac")
	var cut2 := _sb.duplicate(true)
	(cut2["held"] as Dictionary).erase("duration_mult")
	var cut3 := _sb.duplicate(true)
	(cut3["held_door"]["mass"]["died"] as Dictionary).erase("killed_frac")
	t.ok(StandinResolver.problem(cut) == "balance_standins 2 has no death_t_frac"
		and StandinResolver.problem(cut2) == "balance_standins held has no duration_mult"
		and StandinResolver.problem(cut3) == "balance_standins held_door.mass.died has no killed_frac",
		"a missing key is named: %s / %s / %s" % [StandinResolver.problem(cut), StandinResolver.problem(cut2), StandinResolver.problem(cut3)])
	t.ok(int(_sb["v"]) == 0 and _sb["measured_at"] == "afb8dab" and int(_sb["score"]) == 70, "v0, measured at afb8dab, score 70")
	var sourced := true
	for name in StandinResolver.TABLES:
		var src: Variant = _sb[name]["source"]
		sourced = sourced and src is Dictionary and (src as Dictionary).has("deaths") and (src as Dictionary).has("loot_outcomes_mass")
	t.ok(sourced and _sb["held"]["source"] == "GUESS"
		and str(_sb["held_door"]["source"]["label"]).contains("rows grade-doorb-* in calibration-dd-raw.tsv, afb8dab"),
		"every measured entry names its source rows; held is labelled GUESS; the held door carries its label")
	var named: Array = []
	for f in DirAccess.get_files_at("res://scripts/sim"):
		if f.ends_with(".gd") and FileAccess.get_file_as_string("res://scripts/sim/" + f).contains("balance_standins"):
			named.append(f)
	t.ok(named.is_empty(), "nothing under scripts/sim/ reads balance_standins: %s" % str(named))


# ----------------------------------------------------------------- validity ---
func _forts_for(c: String) -> Array:
	match c:
		"1":
			return ["ashgate", "greywall", "old-sluice"]
		"2", "held_door":
			return ["vespers", "chime-fort", "lantern-keep"]
		"3":
			return ["hollow-redoubt", "pale-bastion", "mourners-gate"]
		"4":
			return ["the-stair", "whitecross", "sable-hold"]
		"first_dungeon":
			return ["old-sluice"]
	return ["ashgate", "vespers", "pale-bastion", "sable-hold", "greywall", "lantern-keep", "mourners-gate", "the-stair"]


func _validity() -> void:
	for c in ["1", "2", "3", "4", "first_dungeon", "held", "held_door"]:
		var s := _game()
		var r := RandomNumberGenerator.new()
		r.seed = hash("standins " + c)
		var forts := _forts_for(c)
		var bad := {"begin": 0, "invalid": 0, "repeat": 0, "table": 0, "apply": 0, "ledger": 0, "cleared": 0}
		var why: Array = []
		var exits := {"warden_beaten": 0, "retreated": 0, "relish_died": 0}
		var revived := 0
		var worst := Ledger.error(s.ledger())
		for i in N_VALID:
			var fid: String = forts[i % forts.size()]
			var f := s.realm.fort_by_id(fid)
			if c == "held":
				if not RealmSim.is_held(f):
					s.realm.hold(fid, 0.0)
			elif RealmSim.is_held(f):
				s.realm.release(fid)
			if c == "first_dungeon":
				s.first_dungeon_id = fid
				s.cleared_forts.erase(fid)
			else:
				s.first_dungeon_id = ""
			var cap := float(f["cap"])
			var liv := 0.0 if c == "held" and i % 5 == 0 else cap * r.randf_range(0.05, 0.95)
			s.cmd_debug_set_state({"forts": {fid: {"living": liv, "dead": cap * r.randf_range(0.0, 0.5),
				"undead": cap * r.randf_range(0.0, 0.4)}}})
			_set_party(s, 2 + i % 2 if c == "held_door" else (0 if c == "first_dungeon" else i % 4))
			s._phylactery_charges = i % 3
			s.cmd_debug_set_state({"relish_at": fid})
			var b := s.cmd_begin_dungeon(fid)
			if not b["ok"]:
				bad["begin"] += 1
				why.append("begin %s: %s" % [fid, b["reason"]])
				continue
			var sd: Dictionary = b["seed"]
			var opts := {"held": RealmSim.is_held(f), "door": c == "held_door", "blueprints": s.blueprints.duplicate()}
			var o := StandinResolver.resolve(sd, _sb, _cfgs, opts)
			var res: Dictionary = o["result"]
			var errs := Results.validate("raid", res)
			if not errs.is_empty():
				bad["invalid"] += 1
				why.append("invalid: %s" % str(errs))
			if var_to_str(StandinResolver.resolve(sd, _sb, _cfgs, opts)) != var_to_str(o):
				bad["repeat"] += 1
			if o["notes"]["table"] != c:
				bad["table"] += 1
				why.append("table %s at %s" % [o["notes"]["table"], fid])
			var ar := s.apply_result("raid", res)
			if not ar["ok"]:
				bad["apply"] += 1
				why.append("apply: %s %s" % [ar["reason"], str(ar["errors"])])
			var err := Ledger.error(s.ledger())
			worst = maxf(worst, err)
			if err > TOL:
				bad["ledger"] += 1
			var evs := s.drain_events()
			for ex in exits:
				exits[ex] += 1 if res[ex] else 0
			revived += int(res["revived_in_place"])
			if c == "held" and res["retreated"]:
				var cleared := false
				for ev in evs:
					cleared = cleared or (ev["type"] == "counter_garrison_cleared" and ev["fort_id"] == fid)
				if not cleared or float(res["killed_living_mass"]) != float(sd["living"]):
					bad["cleared"] += 1
		print("  [standins] validity %s: %d runs, exits %s, revives %d, worst ledger error %s" % [c, N_VALID, str(exits), revived, String.num_scientific(worst)])
		t.ok(bad["begin"] == 0 and bad["table"] == 0, "%s: cmd_begin_dungeon issued all %d seeds, each resolved on its entry %s" % [c, N_VALID, str(why.slice(0, 3))])
		t.ok(bad["invalid"] == 0 and bad["apply"] == 0, "%s: all %d results pass Results.validate and the real apply_result %s" % [c, N_VALID, str(why.slice(0, 3))])
		t.ok(bad["ledger"] == 0, "%s: the ledger balances after every writeback (worst %s)" % [c, String.num_scientific(worst)])
		t.ok(bad["repeat"] == 0, "%s: the same seed resolves byte-identically, %d of %d" % [c, N_VALID - bad["repeat"], N_VALID])
		if c == "first_dungeon":
			t.ok(exits["relish_died"] == 0 and exits["warden_beaten"] == N_VALID, "first dungeon: never a death (0/60 and 0/20 in the rows)")
		else:
			var outcomes: bool = exits["relish_died"] > 0 and exits["warden_beaten" if c != "held" else "retreated"] > 0
			t.ok(outcomes and revived > 0, "%s: both outcomes and a revive came up: %s, %d revives" % [c, str(exits), revived])
		if c == "held":
			t.ok(bad["cleared"] == 0 and exits["retreated"] > 0, "held: every clear is a retreat that killed the seed's living, and raised counter_garrison_cleared")


# -------------------------------------------------------------- convergence ---
func _convergence() -> void:
	var cases := {"1": _profile("ashgate", 1), "2": _profile("vespers", 2), "3": _profile("pale-bastion", 3),
		"4": _profile("the-stair", 4), "first_dungeon": _first_seed()}
	for name in cases:
		var sd: Dictionary = cases[name]
		var e: Dictionary = _sb[name]
		var d := float(e["death_rate"])
		var c := _draws(sd, {})
		_rate("%s: the death rate" % name, c["relish_died"], N_DRAWS, d)
		_rate("%s: the flip rate" % name, c["warden_beaten"], N_DRAWS, 1.0 - d)
		var want := _expect(e, d, bool(sd["fort"]["first_clear"]), bool(sd["chest_husk"]))
		for k in KINDS:
			_mean("%s: mean %s a run" % [name, k], c["mean"][k], c["se"][k], want[k])
		print("  [standins] convergence %s: died %.4f (%.4f), flip %.4f, loot %s against %s" % [name, float(c["relish_died"]) / N_DRAWS,
			d, float(c["warden_beaten"]) / N_DRAWS, _fmt(c["mean"]), _fmt(want)])
	# a held fort (GUESS): the tier's death rate × 0.5, a clear is a retreat, its loot RaidLoot.held_clear's
	var hd := _profile("hollow-redoubt", 3)
	var dh := float(_sb["3"]["death_rate"]) * float(_sb["held"]["death_rate_mult"])
	var ch := _draws(hd, {"held": true})
	_rate("held (t3): the death rate", ch["relish_died"], N_DRAWS, dh)
	_rate("held (t3): the clear (retreat) rate", ch["retreated"], N_DRAWS, 1.0 - dh)
	t.ok(ch["warden_beaten"] == 0, "held: never warden_beaten")
	var hc: Dictionary = _cfgs["loot"]["held_clear"]
	var hw := {"relics": 0.0, "remnants": 0.0, "husks": 0.0, "blueprints": 0.0, "essence": 0.0}
	for pair in [["relics", "relics"], ["remnants", "remnants"], ["essence", "essence_motes"]]:
		hw[pair[0]] = (1.0 - dh) * (float(hc[pair[1]][0]) + float(hc[pair[1]][1])) * 0.5
	# E4 step 2: held_clear also rolls the tier's chest husk at husk_chance x yield
	hw["husks"] = (1.0 - dh) * float(_cfgs["loot"]["chest_by_tier"]["3"]["husk_chance"]) * float(hd["fort"].get("yield_mult", 1.0))
	for k in KINDS:
		_mean("held (t3): mean %s a run (held_clear)" % k, ch["mean"][k], ch["se"][k], hw[k])
	print("  [standins] convergence held (t3): died %.4f (%.4f), retreat %.4f, loot %s against %s" % [float(ch["relish_died"]) / N_DRAWS,
		dh, float(ch["retreated"]) / N_DRAWS, _fmt(ch["mean"]), _fmt(hw)])
	# the held door: the t3 party at vespers (its arm (b))
	var dd := _profile("vespers", 3)
	var ed: Dictionary = _sb["held_door"]
	var cd := _draws(dd, {"door": true})
	_rate("held_door: the death rate", cd["relish_died"], N_DRAWS, float(ed["death_rate"]))
	_rate("held_door: the flip rate", cd["warden_beaten"], N_DRAWS, 1.0 - float(ed["death_rate"]))
	var wd := _expect(ed, float(ed["death_rate"]), false, false)
	for k in KINDS:
		_mean("held_door: mean %s a run" % k, cd["mean"][k], cd["se"][k], wd[k])
	print("  [standins] convergence held_door: died %.4f (%.4f), flip %.4f, loot %s against %s" % [float(cd["relish_died"]) / N_DRAWS,
		float(ed["death_rate"]), float(cd["warden_beaten"]) / N_DRAWS, _fmt(cd["mean"]), _fmt(wd)])


func _fmt(d: Dictionary) -> String:
	var parts: Array = []
	for k in KINDS:
		parts.append("%s %.3f" % [k, float(d[k])])
	return "{" + ", ".join(parts) + "}"


## yield_mult 0.5 (a reclear) halves the dropped kinds, as the scene's RaidLoot rolls do, and leaves essence.
func _yield() -> void:
	var e: Dictionary = _sb["3"]
	var d := float(e["death_rate"])
	var full := _draws(_profile("pale-bastion", 3), {})
	var half := _draws(_profile("pale-bastion", 3, {"fort": {"yield_mult": 0.5}}), {})
	var want := _expect(e, d, false, false, 0.5)
	for k in ["relics", "remnants", "husks", "essence"]:
		_mean("yield 0.5: mean %s a run" % k, half["mean"][k], half["se"][k], want[k])
	print("  [standins] yield 0.5 against 1.0 (t3): relics %.3f / %.3f, remnants %.3f / %.3f, husks %.3f / %.3f, essence %.3f / %.3f" % [
		half["mean"]["relics"], full["mean"]["relics"], half["mean"]["remnants"], full["mean"]["remnants"],
		half["mean"]["husks"], full["mean"]["husks"], half["mean"]["essence"], full["mean"]["essence"]])
	t.ok(half["mean"]["relics"] < 0.6 * full["mean"]["relics"] and half["mean"]["remnants"] < 0.6 * full["mean"]["remnants"],
		"yield 0.5 roughly halves the relics and remnants")


## A phylactery charge revives her in place once (at most max_per_dungeon), then the rest of the run rolls again.
func _revive() -> void:
	var d := float(_sb["4"]["death_rate"])
	var one := _draws(_profile("the-stair", 4, {"phylactery_charges": 1, "phylactery_max_per_dungeon": 1}), {})
	_rate("one charge: runs with a revive in place", one["revived"], N_DRAWS, d)
	_rate("one charge: deaths (two in a row)", one["relish_died"], N_DRAWS, d * d)
	var two := _draws(_profile("the-stair", 4, {"phylactery_charges": 2, "phylactery_max_per_dungeon": 1}), {})
	t.ok(two["max_revived"] == 1 and one["max_revived"] == 1, "at most phylactery_max_per_dungeon (1) revive a run, even with 2 charges")
	var none := _draws(_profile("the-stair", 4), {}, 400)
	t.ok(none["revived"] == 0, "no charge, no revive")


## The masses follow the dungeon's rules on the seed's own fort: one bucket at score 70, its fresh mass capped at the
## killed living plus the dead; score 70 is a soldier, so nothing leaves as chaff; what stays is bounded by the
## garrison taken in plus the mass raised (LedgerV2); a held clear kills exactly the seed's living.
func _masses() -> void:
	var rc: Dictionary = _cfgs["raid"]
	var bad := {"bucket": 0, "fresh": 0, "chaff": 0, "bound": 0}
	var sample := ""
	for held in [false, true]:
		var sd := _profile("vespers", 2)
		for i in 300:
			sd["rng_seed"] = str(77 + i)
			var o := StandinResolver.resolve(sd, _sb, _cfgs, {"held": held})
			var r: Dictionary = o["result"]
			var b: Array = r["raised"]
			var fresh := float(b[0]["mass"]) if b.size() == 1 else -1.0
			var cnt := int(b[0]["count"]) if b.size() == 1 else -1
			if b.size() != 1 or int(b[0]["score"]) != 70:
				bad["bucket"] += 1
			elif absf(fresh - minf(cnt * RaidLogic.mass_per_enemy(sd["living"], sd["fort"]["cap"], rc),
					float(r["killed_living_mass"]) + float(sd["dead"]))) > 1e-9:
				bad["fresh"] += 1
			if float(r["chaff_mass"]) != 0.0:
				bad["chaff"] += 1
			if float(r["garrison_mass"]) > float(sd["garrison_in_mass"]) + fresh + 1e-9 \
					or (held and r["retreated"] and float(r["killed_living_mass"]) != float(sd["living"])):
				bad["bound"] += 1
			if i == 0:
				var ex := "relish_died" if r["relish_died"] else ("retreated" if r["retreated"] else "warden_beaten")
				sample += "%s %s: killed %.1f, raised %s, garrison %.1f, chaff %.1f; " % ["held" if held else "fresh",
					ex, r["killed_living_mass"], str(b), r["garrison_mass"], r["chaff_mass"]]
	print("  [standins] masses at vespers (living %.1f, dead %.1f, garrison in 60): %s" % [float(_profile("vespers", 2)["living"]),
		float(_profile("vespers", 2)["dead"]), sample])
	t.ok(RaidLogic.score_class(70, rc) == "soldier" and bad["bucket"] == 0 and bad["fresh"] == 0,
		"one bucket at score 70, its fresh mass count × mass_per_enemy capped at killed + dead: %s" % str(bad))
	t.ok(bad["chaff"] == 0 and bad["bound"] == 0, "score 70 raises soldiers, so no chaff leaves; garrison ≤ garrison in + raised; a held clear kills the seed's living: %s" % str(bad))


func _determinism() -> void:
	for sd in [_profile("vespers", 3), _first_seed(), _profile("whitecross", 4)]:
		var a := StandinResolver.resolve(sd, _sb, _cfgs, {"door": true})
		var b := StandinResolver.resolve(sd.duplicate(true), _sb, _cfgs, {"door": true})
		t.ok(var_to_str(a) == var_to_str(b) and JSON.stringify(a) == JSON.stringify(b),
			"%s: the same seed gives a byte-identical result" % sd["fort"]["id"])
	var seen := {}
	var sd := _profile("vespers", 2)
	for i in 20:
		sd["rng_seed"] = str(i + 1)
		seen[var_to_str(StandinResolver.resolve(sd, _sb, _cfgs, {})["result"])] = true
	t.ok(seen.size() == 20, "a different rng_seed changes it: 20 seeds, %d different results" % seen.size())


func _door() -> void:
	var rc: Dictionary = _cfgs["raid"]
	var on := {"door": true}
	var take: Dictionary = StandinResolver.resolve(_profile("vespers", 3), _sb, _cfgs, on)["notes"]
	var chime: Dictionary = StandinResolver.resolve(_profile("chime-fort", 3), _sb, _cfgs, on)["notes"]
	t.ok(take["door_taken"] and take["table"] == "held_door" and take["door_uid"] == "p2" and chime["door_uid"] == "p1",
		"t2 with two bigs: the door is taken, its big the dungeon's pick (p2, beef 4, at the Bellringer's vespers; p1, speed 4, at chime-fort)")
	var gates := {
		"a t3 fort (pale-bastion), two bigs": [_profile("pale-bastion", 3), on],
		"a t4 fort (the-stair), three bigs": [_profile("the-stair", 4), on],
		"one big at vespers (one big always declines)": [_profile("vespers", 2), on],
		"opts.door false": [_profile("vespers", 3), {}],
		"a held fort": [_profile("vespers", 3), {"door": true, "held": true}],
		"the first dungeon": [_profile("vespers", 3, {"fort": {"first_dungeon": true}}), on]}
	for what in gates:
		var n: Dictionary = StandinResolver.resolve(gates[what][0], _sb, _cfgs, gates[what][1])["notes"]
		t.ok(not n["door_taken"] and n["table"] != "held_door", "declined: %s (entry %s)" % [what, n["table"]])
	t.ok(StandinResolver.door_pick(_profile("vespers", 3), rc, on) == 1, "door_pick is the index in the party")
	# its big: lost on a death (the whole party is), rejoined on a win
	var c := _draws(_profile("vespers", 3), on)
	t.ok(c["door_taken"] == N_DRAWS and c["door_lost"] == c["relish_died"] and c["door_lost_on_win"] == 0 and c["relish_died"] > 0,
		"the door's big is in party_lost on each of the %d deaths and on none of the %d wins" % [c["relish_died"], c["warden_beaten"]])
	var found := {"died": false, "won": false}
	for i in 200:
		var o := StandinResolver.resolve(_profile("vespers", 3, {"rng_seed": str(31 + i)}), _sb, _cfgs, on)
		var r: Dictionary = o["result"]
		if r["relish_died"] and not found["died"]:
			found["died"] = (r["party_lost"] as Array).has("p2") and (r["party_lost"] as Array).has("p1")
		if r["warden_beaten"] and not found["won"]:
			found["won"] = not (r["party_lost"] as Array).has("p2")
	t.ok(found["died"] and found["won"], "a death lists the door's big p2 with the party in party_lost; a win leaves p2 out (it rejoined)")
	# its relics: above a declined door's (the t2 entry) at the same fort and party
	var off := _draws(_profile("vespers", 3), {})
	t.ok(c["mean"]["relics"] > off["mean"]["relics"] + Z * (c["se"]["relics"] + off["se"]["relics"]),
		"the held door's relics a run %.3f are above the declined door's %.3f (rows: 190 against 142 in 60)" % [c["mean"]["relics"], off["mean"]["relics"]])


## opts.deaths "frozen" rolls the frozen bot's death rate.
func _opts() -> void:
	var e: Dictionary = _sb["2"]
	var c := _draws(_profile("vespers", 2), {"deaths": "frozen"})
	_rate("deaths frozen (t2): the death rate is death_rate_frozen", c["relish_died"], N_DRAWS, float(e["death_rate_frozen"]))
	var o := StandinResolver.resolve(_profile("vespers", 2), _sb, _cfgs, {"deaths": "frozen"})
	t.ok(o["notes"]["deaths"] == "frozen" and o["notes"]["death_rate"] == float(e["death_rate_frozen"]), "notes name the frozen rate")
