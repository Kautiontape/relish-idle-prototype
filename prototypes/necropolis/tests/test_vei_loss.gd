extends RefCounted
## A lost Vei attempt reads what fell short and what to change before trying again (V-I2 Top three #3; dungeon-i
## Session 7; the manager's ruling of 2026-11-19). Headless, no autoloads. VeiBoss can't load headless, so each fight
## here is a real boss seed (cmd_begin_boss on a fixture) run through the fight's own rules: VeiFronts.phase1_start,
## phase1_add_raise and phase1_step at vei.json phase1.step_s, ended by phase1_outcome, as VeiBoss._step_fronts runs
## them. The card is built by the BossLogic calls VeiBoss._lose_card makes, on the state VeiBoss.fight_state() hands
## them (BossLogic.RESULT_KEYS); that call site is pinned by source text.
## - pre_vei to the timeout (fronts_held): only Swarm is met, so FELL SHORT lists Raw, Giants and Carvers, biggest
##   share first, have and need from the fight's own state in the lane labels' rounding (a raise mid-fight counts);
##   the advice names the two cheapest, the two the fight still needed (never Raw); FRONTS drops its held clause.
## - pre_vei to the break, then a final death: the fronts it needed fell, so only the backups are short ("backups 2 for
##   3 falls"), Raw held but unlisted; the advice is clones, then the skill tip for what struck her last (the guards
##   tip names the fronts that held: "Break through Raw first").
## - a final death in phase 1 (in play only a dev kill: guards and her weave come only in the break): the fronts and
##   the backups, biggest share first; the advice is the fronts line alone.
## - midgame_2flips (nothing met, no backups): five entries, ties in FRONT_IDS order with backups last; the plate at
##   that worst still fits the viewport; items never split across lines.
## - her queue running out lists nothing, and the advice stays TRY NEXT's line.

var t := TestUtil.new()
var vc := {}
var lw := {}
var vf := {}
var dw := {}


func run() -> int:
	vc = TestUtil.load_json("res://configs/vei.json")
	var raid := TestUtil.load_json("res://configs/raid.json")
	lw = raid["vei_loss"]
	vf = raid["vei_fight"]
	dw = raid["death"]
	t.suite("vei_loss_fronts_held")
	_fronts_held()
	t.suite("vei_loss_final_death")
	_final_death()
	t.suite("vei_loss_phase1_death")
	_phase1_death()
	t.suite("vei_loss_order")
	_order()
	t.suite("vei_loss_short_layout")
	_layout()
	t.suite("vei_loss_short_wiring")
	_wiring()
	return t.failures


## A fixture's boss seed, as the fight gets it: Relish moved to Vei, cmd_begin_boss.
func _seed(fx: String) -> Dictionary:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture(fx)["ok"], "(setup) %s loads" % fx)
	if s.view_relish()["state"] != "at_vei":
		s.cmd_debug_set_state({"relish_at": "vei"})
	var bb := s.cmd_begin_boss()
	t.ok(bb["ok"], "(setup) %s: the boss run opens (%s)" % [fx, bb["reason"]])
	return bb["seed"]


## The seed's fronts as VeiBoss._fronts_for reads a live seed: its own entries, in FRONT_IDS order.
func _fronts_of(sd: Dictionary) -> Array:
	t.ok(not BossLogic.seed_fronts_empty(sd), "(setup) the seed carries live fronts")
	var out: Array = []
	for id in VeiFronts.FRONT_IDS:
		for g in sd["fronts"]:
			if str(g["id"]) == id:
				out.append((g as Dictionary).duplicate(true))
	return out


## Phase 1 as the scene runs it: steps of phase1.step_s; `raises` [[t, front_id, mults]] land at their time; it stops
## at the first outcome ("phase2" or "lost") or at `stop_s`. Returns {p1, outcome}.
func _phase1(sd: Dictionary, raises: Array, stop_s: float) -> Dictionary:
	var p1 := VeiFronts.phase1_start(_fronts_of(sd))
	var step := float(vc["phase1"]["step_s"])
	var todo := raises.duplicate()
	var out := ""
	while out == "" and float(p1["t"]) < stop_s:
		while not todo.is_empty() and float(todo[0][0]) <= float(p1["t"]):
			p1 = VeiFronts.phase1_add_raise(p1, str(todo[0][1]), todo[0][2], vc)
			todo.pop_front()
		p1 = VeiFronts.phase1_step(p1, step, vc)
		out = VeiFronts.phase1_outcome(p1, vc)
	return {"p1": p1, "outcome": out}


## VeiBoss.fight_state() for a fight that ended here: phase1_s is the break's start or -1, the cleared list frozen then.
func _state(sd: Dictionary, p1: Dictionary, break_began: bool, deaths: int, spent: Dictionary) -> Dictionary:
	var st := {"seed": sd, "p1": p1, "fronts_cleared": BossLogic.cleared_ids(p1["fronts"]) if break_began else [],
		"phase1_s": float(p1["t"]) if break_began else -1.0, "deaths": deaths, "spent": spent, "party_lost": [], "horde0": 0.0, "horde": 0.0}
	t.ok(st.keys() == BossLogic.RESULT_KEYS, "(setup) the state has fight_state()'s keys")
	return st


func _ids(sf: Dictionary) -> Array:
	return (sf["items"] as Array).map(func(e): return str(e["id"]))


## Each listed front's have, need and gap are the lane labels' (BossLanes lane_text) on the fight's own p1.
func _lane_rounded(sf: Dictionary, p1: Dictionary) -> bool:
	var ok := true
	for e in sf["items"]:
		if str(e["kind"]) != "front":
			continue
		for f in p1["fronts"]:
			if str(f["id"]) == str(e["id"]):
				var h := float(f["have"])
				var n := float(f["need"])
				ok = ok and int(e["have"]) == floori(h + 0.0001) and int(e["need"]) == ceili(n - 0.0001) and int(e["gap"]) == ceili(n - h - 0.0001)
	return ok


func _cause(reason: String, src: String, p1: Dictionary, sf: Dictionary) -> Dictionary:
	return BossLogic.loss_cause(reason, {"last_hit_src": src, "streak_max": 0, "break_beats": int(vc["break_beats"]),
		"fronts_cleared": BossLogic.cleared_ids(p1["fronts"]), "fronts_required": VeiFronts.required(vc),
		"held_listed": int(sf["fronts_needed"]) > 0}, lw)


func _fronts_held() -> void:
	var sd := _seed("pre_vei")
	# a raise of 4 motes at x1.0 on Giants 5 s in: the card reads the fight's own have, not the seed's
	var run := _phase1(sd, [[5.0, "giants", [1.0, 1.0, 1.0, 1.0]]], 200.0)
	var p1: Dictionary = run["p1"]
	t.ok(run["outcome"] == "lost" and float(p1["t"]) >= float(vc["phase1_max_s"]) and BossLogic.cleared_ids(p1["fronts"]) == ["swarm"],
		"pre_vei: only Swarm is met, and phase 1 times out at %.1f s (fronts_held)" % float(p1["t"]))
	var sf := BossLogic.shortfall(_state(sd, p1, false, 0, {}), "fronts_held", vc)
	t.ok(_ids(sf) == ["raw", "giants", "carvers"] and int(sf["fronts_needed"]) == 2,
		"FELL SHORT: the three that held, biggest share first (%s), two more needed" % str(_ids(sf)))
	var shares: Array = (sf["items"] as Array).map(func(e): return float(e["share"]))
	t.ok(shares[0] > shares[1] and shares[1] > shares[2], "the order is the share short: %s" % str(shares))
	t.ok(_lane_rounded(sf, p1), "have, need and gap are the lane labels' on the fight's own state")
	var giants: Dictionary = sf["items"][1]
	t.ok(int(giants["have"]) == 7 and int(sd["fronts"][0]["have"]) == 5, "the raise counts: Giants have 7 at the end against the seed's 5")
	var row := BossLogic.short_row(sf, lw)
	t.ok(row["label"] == "FELL SHORT" and row["text"] == "Raw 16 of 58 · Giants 7 of 14 · Carvers 5 of 10", "the row: " + str(row["text"]))
	var adv := BossLogic.loss_advice("fronts_held", sf, {"last_hit_src": "", "fronts_cleared": ["swarm"]}, lw)
	t.ok(adv["label"] == "BEFORE YOU TRY AGAIN" and adv["text"] == "Put big undead on Carvers (4 more beef) and Giants (7 more wits) at the Vei card.",
		"the advice names the two cheapest, the two the fight needed, never Raw: " + str(adv["text"]))
	t.ok(_cause("fronts_held", "", p1, sf)["text"] == "1 of 4 fell · 3 needed", "FRONTS drops its held clause when FELL SHORT lists them")
	var full := BossLogic.loss_cause("fronts_held", {"fronts_cleared": ["swarm"], "fronts_required": 3}, lw)
	t.ok(full["text"] == "1 of 4 fell · 3 needed · Giants, Carvers and Raw held", "without FELL SHORT it keeps it: " + str(full["text"]))


func _final_death() -> void:
	var sd := _seed("pre_vei")
	# raises that meet Giants and Carvers early: the break begins with three fronts, Raw still held
	var run := _phase1(sd, [[2.0, "giants", _mults(18)], [3.0, "carvers", _mults(8)]], 200.0)
	var p1: Dictionary = run["p1"]
	t.ok(run["outcome"] == "phase2" and BossLogic.cleared_ids(p1["fronts"]) == ["giants", "swarm", "carvers"],
		"pre_vei with raises: the break begins at %.1f s with Raw held" % float(p1["t"]))
	var brought := int(sd["phylactery_charges"]) + int(sd["clones_ready"])
	t.ok(brought == 2, "(setup) pre_vei brings 1 + 1 backups")
	var st := _state(sd, p1, true, brought + 1, {"phylactery": int(sd["phylactery_charges"]), "clones": int(sd["clones_ready"])})
	var sf := BossLogic.shortfall(st, "relish_unmade", vc)
	t.ok(_ids(sf) == ["backups"] and int(sf["fronts_needed"]) == 0 and int(sf["items"][0]["have"]) == 2 and int(sf["items"][0]["need"]) == 3,
		"a final death after the break: only the backups are short (Raw held, but the fight had the fronts it needed)")
	t.ok(BossLogic.short_row(sf, lw)["text"] == "backups 2 for 3 falls", "the row: " + str(BossLogic.short_row(sf, lw)["text"]))
	var cases := [
		["weave", "Grow more clones in the Chapel of Vats' staffed vats. Step off her thread on the beat."],
		["living", "Grow more clones in the Chapel of Vats' staffed vats. Break through Raw first: each front left standing keeps sending guards."],
		["slam", "Grow more clones in the Chapel of Vats' staffed vats."],
		["", "Grow more clones in the Chapel of Vats' staffed vats."],
	]
	for c in cases:
		var adv := BossLogic.loss_advice("relish_unmade", sf, {"last_hit_src": c[0], "fronts_cleared": st["fronts_cleared"]}, lw)
		t.ok(adv["label"] == "BEFORE YOU TRY AGAIN" and adv["text"] == c[1], "struck last by '%s': clones, then its tip if it has one: %s" % [c[0], adv["text"]])
	# the guards tip names the fronts still standing, from the cleared list frozen at the break (the manager's ruling
	# on Session 7): another held front, two (joined as FELL SHORT joins), and none (no guard is sent: no tip)
	var held_cases := [
		[["swarm", "carvers", "raw"], "Grow more clones in the Chapel of Vats' staffed vats. Break through Giants first: each front left standing keeps sending guards."],
		[["giants", "carvers"], "Grow more clones in the Chapel of Vats' staffed vats. Break through Swarm · Raw first: each front left standing keeps sending guards."],
		[["giants", "swarm", "carvers", "raw"], "Grow more clones in the Chapel of Vats' staffed vats."],
	]
	for c in held_cases:
		var adv := BossLogic.loss_advice("relish_unmade", sf, {"last_hit_src": "living", "fronts_cleared": c[0]}, lw)
		t.ok(adv["text"] == c[1], "guards, %s cleared: the tip names what held: %s" % [str(c[0]), adv["text"]])
	# the same fight ending as her queue runs out: nothing fell short, so the row is gone and TRY NEXT stays
	var sh := BossLogic.shortfall(st, "horde_ferried", vc)
	var facts := {"last_hit_src": "", "fronts_cleared": st["fronts_cleared"]}
	t.ok((sh["items"] as Array).is_empty() and BossLogic.short_row(sh, lw).is_empty()
		and BossLogic.loss_advice("horde_ferried", sh, facts, lw) == BossLogic.loss_change("horde_ferried", facts, lw)
		and BossLogic.loss_advice("horde_ferried", sh, facts, lw)["label"] == "TRY NEXT", "her queue ran out: no FELL SHORT, the advice is TRY NEXT's line")
	# no backups at all: she falls once
	var none := sd.duplicate(true)
	none["phylactery_charges"] = 0
	none["clones_ready"] = 0
	var s0 := BossLogic.shortfall(_state(none, p1, true, 1, {}), "relish_unmade", vc)
	t.ok(BossLogic.short_row(s0, lw)["text"] == "backups 0 for 1 fall", "no backups: " + str(BossLogic.short_row(s0, lw)["text"]))


func _mults(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(1.0)
	return out


func _phase1_death() -> void:
	var sd := _seed("pre_vei")
	var run := _phase1(sd, [], 30.0)
	var p1: Dictionary = run["p1"]
	t.ok(run["outcome"] == "", "(setup) pre_vei at 30 s: still phase 1")
	var sf := BossLogic.shortfall(_state(sd, p1, false, 3, {"phylactery": 1, "clones": 1}), "relish_unmade", vc)
	t.ok(_ids(sf) == ["raw", "giants", "carvers", "backups"] and int(sf["fronts_needed"]) == 2,
		"a final death in phase 1: the fronts that held and the backups, biggest share first: %s" % str(_ids(sf)))
	t.ok(BossLogic.short_row(sf, lw)["text"] == "Raw 16 of 58 · Giants 5 of 14 · Carvers 5 of 10 · backups 2 for 3 falls", "the row: " + str(BossLogic.short_row(sf, lw)["text"]))
	var adv := BossLogic.loss_advice("relish_unmade", sf, {"last_hit_src": "living", "fronts_cleared": []}, lw)
	t.ok(adv["text"] == "Put big undead on Carvers (4 more beef) and Giants (9 more wits) at the Vei card.",
		"the advice: the fronts the fight needed, alone (the break, with its guards and weave, never began): " + str(adv["text"]))
	# midgame_2flips: nothing met and no backups, so the fight needed three fronts
	var sm := _seed("midgame_2flips")
	var pm: Dictionary = _phase1(sm, [], 10.0)["p1"]
	var sfm := BossLogic.shortfall(_state(sm, pm, false, 1, {}), "relish_unmade", vc)
	t.ok(_ids(sfm) == ["giants", "backups", "raw", "swarm", "carvers"] and int(sfm["fronts_needed"]) == 3,
		"midgame_2flips: Giants (0 of 14) and the backups tie at the whole share, the front first: %s" % str(_ids(sfm)))
	var am := BossLogic.loss_advice("relish_unmade", sfm, {"last_hit_src": "living", "fronts_cleared": []}, lw)
	t.ok(am["text"] == "Put big undead on Carvers (6 more beef), Giants (14 more wits) and Swarm (18 more presence, or more FLOOD) at the Vei card.",
		"three fronts needed: the three cheapest: " + str(am["text"]))


func _e(id: String, have: float, need: float) -> Dictionary:
	return {"id": id, "have": have, "need": need, "cleared": false, "progress": 0.0}


func _order() -> void:
	var p1 := {"t": 1.0, "fronts": [_e("giants", 10.0, 20.0), _e("swarm", 30.0, 24.0), _e("carvers", 1.0, 2.0), _e("raw", 10.0, 50.0)]}
	var sd := {"phylactery_charges": 1, "clones_ready": 0}
	var st := {"seed": sd, "p1": p1, "fronts_cleared": [], "phase1_s": -1.0, "deaths": 2, "spent": {}, "party_lost": [], "horde0": 0.0, "horde": 0.0}
	var sf := BossLogic.shortfall(st, "relish_unmade", vc)
	t.ok(_ids(sf) == ["raw", "giants", "carvers", "backups"], "share 0.8 first; Giants, Carvers and the backups tie at 0.5 in FRONT_IDS order, backups last: %s" % str(_ids(sf)))
	var adv := BossLogic.short_fix(sf, "relish_unmade", {"last_hit_src": "weave", "fronts_cleared": []}, lw)
	t.ok(adv["text"] == "Put big undead on Carvers (1 more beef) and Giants (10 more wits) at the Vei card.", "the advice takes the two cheapest gaps: " + str(adv["text"]))
	st["phase1_s"] = 4.0
	t.ok(_ids(BossLogic.shortfall(st, "relish_unmade", vc)) == ["backups"], "once the break began, no front is listed")
	st["phase1_s"] = -1.0
	p1["fronts"][0] = _e("giants", 20.0, 20.0)
	p1["fronts"][2] = _e("carvers", 2.0, 2.0)
	t.ok(_ids(BossLogic.shortfall(st, "fronts_held", vc)) == [], "three met (have >= need) lists no front, even before they clear")
	t.ok(BossLogic.short_fix({"items": [], "fronts_needed": 0}, "relish_unmade", {}, lw).is_empty(), "nothing short: no advice of its own")


func _layout() -> void:
	var ccfg: Dictionary = vc["card"]
	var vw := VeiCard.value_w(ccfg)
	var fnt := ThemeDB.fallback_font
	var keep := float(vc["loss_backlog_keep"])
	var budget := 900.0 - 2.0 * 20.0
	var cases := {}
	# the worst: midgame_2flips' five entries and three fronts in the advice, a final death (AFTER, 59 min 59 s)
	var sm := _seed("midgame_2flips")
	sm["death_ends"] = {"outcome": "unmade", "respawn_s": 3599}
	var pm: Dictionary = _phase1(sm, [], 10.0)["p1"]
	var sfm := BossLogic.shortfall(_state(sm, pm, false, 1, {}), "relish_unmade", vc)
	cases["phase-1 death, nothing met"] = [sm, sfm, "relish_unmade", "living", {}, pm]
	# the common one: a final death in the break at her full pool (the GUARDS row), backups short
	var sd := _seed("pre_vei")
	sd["death_ends"] = {"outcome": "unmade", "respawn_s": 3599}
	var pb: Dictionary = _phase1(sd, [[2.0, "giants", _mults(18)], [3.0, "carvers", _mults(8)]], 200.0)["p1"]
	cases["break death"] = [sd, BossLogic.shortfall(_state(sd, pb, true, 3, {}), "relish_unmade", vc), "relish_unmade", "living",
		BossLogic.pressure_row(VeiFronts.pressure_mult(600.0, vc), 600.0, lw), pb]
	var pf: Dictionary = _phase1(sd, [], 200.0)["p1"]
	cases["fronts held"] = [sd, BossLogic.shortfall(_state(sd, pf, false, 0, {}), "fronts_held", vc), "fronts_held", "", {}, pf]
	for name in cases:
		var c: Array = cases[name]
		var info := BossLogic.loss_card(c[0], {"phylactery": 1, "clones": 1}, [], 65.0, c[2], keep, dw, lw)
		var p1: Dictionary = c[5]
		info["cause"] = _cause(c[2], c[3], p1, c[1])
		info["short"] = BossLogic.short_row(c[1], lw)
		info["pressure_row"] = c[4]
		info["change"] = BossLogic.loss_advice(c[2], c[1], {"last_hit_src": c[3], "fronts_cleared": BossLogic.cleared_ids(p1["fronts"])}, lw)
		var rows := VeiCard.rows_for(info, vf)
		var ids: Array = rows.map(func(r): return str(r["id"]))
		var want_head := ["cause", "short"] + (["pressure_row"] if not (c[4] as Dictionary).is_empty() else []) + ["change", "time"]
		t.ok(ids.slice(0, want_head.size()) == want_head, "%s: rows %s (cause, FELL SHORT, the guards when any, the advice, then FIGHT TIME)" % [name, str(ids)])
		var laid := VeiCard.layout_rows(rows, vw, fnt)
		var fits := true
		var whole := true
		for lr in laid:
			for ln in (lr["lines"] as PackedStringArray):
				fits = fits and fnt.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, VeiCard.VALUE_PX).x <= vw
			if str(lr["id"]) == "short":
				var items: Array = lr["items"]
				var rebuilt := PackedStringArray()
				for ln in (lr["lines"] as PackedStringArray):
					for part in ln.split(str(lr["sep"])):
						rebuilt.append(part)
				whole = whole and Array(rebuilt) == items
		var h := VeiCard.plate_h_for(laid, float(ccfg["loss_h_px"]))
		t.ok(fits and whole and h <= budget, "%s: every line within %d px, FELL SHORT's items whole, the plate %d px within %d" % [name, int(vw), int(h), int(budget)])


func _wiring() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/raid/vei_boss.gd")
	var i := src.find("func _lose_card(")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	t.ok(body.contains("var sf := BossLogic.shortfall(fight_state(), end_reason, vcfg())")
		and body.contains("info[\"short\"] = BossLogic.short_row(sf, lw)")
		and body.contains("info[\"change\"] = BossLogic.loss_advice(end_reason, sf, tips, lw)")
		and body.contains("\"held_listed\": int(sf[\"fronts_needed\"]) > 0")
		and not body.contains("Game."), "_lose_card builds FELL SHORT and the advice from fight_state() (no Game.* read)")
	var fs := src.find("func fight_state(")
	var fbody := src.substr(fs, src.find("\nfunc ", fs + 1) - fs)
	for k in BossLogic.RESULT_KEYS:
		t.ok(fbody.contains("\"%s\":" % k), "fight_state() hands shortfall %s" % k)
	var words := ["short_label", "short_front", "short_backups", "short_backups_one", "short_join", "fix_label", "fix_fronts", "fix_backups"]
	var all_s: Array = []
	for k in words:
		all_s.append(str(lw.get(k, "")))
	for id in VeiFronts.FRONT_IDS:
		all_s.append(str(lw["fix_front"].get(id, "")))
	for k in ["weave", "living"]:
		all_s.append(str(lw["tip"].get(k, "")))
	var clean := true
	for s in all_s:
		var low := str(s).to_lower()
		clean = clean and str(s) != "" and not low.contains("api") and not low.contains("todo") and not low.contains("stand-in") \
			and not low.contains("ferr") and not low.contains("backlog")
	t.ok(clean, "the new words are all there, none blank, none with api, TODO, stand-in or the old ferry/backlog words")
	var holes := true
	for id in VeiFronts.FRONT_IDS:
		holes = holes and str(lw["fix_front"][id]).contains("{gap}")
	t.ok(holes and str(lw["short_front"]).contains("{name}") and str(lw["short_front"]).contains("{have}") and str(lw["short_front"]).contains("{need}")
		and str(lw["short_backups"]).contains("{have}") and str(lw["short_backups"]).contains("{need}") and str(lw["fix_fronts"]).contains("{fronts}"),
		"every formatted word keeps its placeholders")
