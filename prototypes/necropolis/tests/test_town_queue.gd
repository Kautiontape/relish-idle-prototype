extends RefCounted
## The Build tab's real queue (town-i M2, Q-e): a gated entry reads "queued: waits for <tier>" and keeps its place,
## the start comes from the view's `affordable_in_s` (R2), a never-affordable head names its store and its
## `starved` cause, the reorder order cmd_reorder_queue takes, and the mill's starved cause in the HUD.

var t: TestUtil
var cfg: Dictionary
var vcfg: Dictionary


func run() -> int:
	t = TestUtil.new()
	t.suite("town-queue")
	cfg = TestUtil.configs()
	vcfg = cfg["town"]["view"]
	_swap()
	_gate_wait()
	_affordable()
	_never()
	_hud_starved()
	_foreman_menu()
	_away_label()
	_catchup()
	_spread_refresh()
	_hud_idle_short()
	_muster_words()
	_review_m2()
	_vat_costed()
	_p2_counts()
	return t.failures


## P2's queue fields when present (queue_slots, queue_list_max), today's count as the fallback (TODO(P2 merge)).
func _p2_counts() -> void:
	var rows := [{"status": "skipped_gate"}, {"status": "next"}, {"status": "queued"}]
	var p2 := {"queue": rows, "queue_max": 2, "queue_slots": 2, "queue_list_max": 4}
	t.ok(not BuildSort.queue_list_full(p2), "P2: 3 rows of a 4-row list: not full, whatever the slots say (a gated add holds none)")
	p2["queue"] = rows + [{"status": "skipped_gate"}]
	t.ok(BuildSort.queue_list_full(p2), "P2: the list at queue_list_max is full")
	t.ok(BuildSort.queue_slots_text(p2, vcfg) == "2 of 2 slots", "P2: the title counts slot-holding rows (%s)" % BuildSort.queue_slots_text(p2, vcfg))
	var old := {"queue": rows, "queue_max": 3}
	t.ok(BuildSort.queue_list_full(old) and BuildSort.queue_slots_text(old, vcfg) == "3 of 3 slots",
		"today (no P2 fields): every row counts toward queue_max")
	t.ok(not BuildSort.queue_list_full({"queue": rows}) and BuildSort.queue_slots_text({"queue": rows}, vcfg) == "",
		"no queue_max in the view: never full by our count, no slots text")
	var s := _state("day1")
	var town := s.view_town()
	t.ok(town.has("queue_max") and BuildSort.queue_slots_text(town, vcfg) == "0 of %d slots" % int(town["queue_max"]),
		"the live view: '%s'" % BuildSort.queue_slots_text(town, vcfg))


## C-c: away_report makes the shell re-read every view; a catching_up refusal reads as a wait in every reason map.
func _catchup() -> void:
	var shell := FileAccess.get_file_as_string("res://scripts/town/covington.gd")  # needs the Game autoload: source only
	var at := shell.find("\"away_report\"")
	t.ok(at > 0 and shell.find("_dirty = true", at) > at and shell.find("_dirty = true", at) - at < 400,
		"the shell sets _dirty on away_report (a full re-read on the next frame)")
	var maps := {"view.reasons": vcfg["reasons"], "behaviour.refusals": vcfg["behaviour"]["refusals"],
		"crypt.reasons": vcfg["crypt"]["reasons"], "backups.craft_reasons": vcfg["backups"]["craft_reasons"],
		"backups.staff_reasons": vcfg["backups"]["staff_reasons"]}
	for k in maps:
		var w := String((maps[k] as Dictionary).get("catching_up", ""))
		t.ok(w.contains("catching up") and w.contains("moment"), "%s.catching_up says to wait: '%s'" % [k, w])
	var txt := BuildSort.reason_text("catching_up", {}, {}, cfg["buildings_view"], vcfg)
	t.ok(txt == String(vcfg["reasons"]["catching_up"]), "a build refused with catching_up reads the wait: '%s'" % txt)
	var line := TownUI.refusal("catching_up", txt, "Refused: %s." % txt)
	t.ok(line == "Catching up on your time away: try again in a moment." and TownUI.refusal("no_gold", "x", "Refused: x.") == "Refused: x.",
		"a catching_up refusal is said as a wait, not 'Refused: …' ('%s'); other refusals keep their line" % line)
	for p in ["panel_build", "panel_crypt", "panel_backups"]:
		var src := FileAccess.get_file_as_string("res://scripts/town/%s.gd" % p)
		t.ok(src.contains("TownUI.refusal("), "%s words its refusals through TownUI.refusal" % p)


## A function's body in `src`, from its `func name(` line to the next top-level func or doc comment ("" when absent).
static func _body(src: String, name: String) -> String:
	var at := src.find("func %s(" % name)
	if at < 0:
		return ""
	var end := src.length()
	for mark in ["\nfunc ", "\n## ", "\nstatic func "]:
		var e := src.find(mark, at + 1)
		if e > 0:
			end = mini(end, e)
	return src.substr(at, end - at)


## The redraw after a build start (town-i M2, C-d's town half): every refresh but the setup's is spread, one piece a
## frame. A command's drops the binds still pending (they hold the views from before it) and binds the tab on show
## first; phase A keeps the views the Build tab reads together, phase B the stances and the fort digest. Source
## only (the shell needs the Game autoload); the frame times are in the M2 report.
func _spread_refresh() -> void:
	var shell := FileAccess.get_file_as_string("res://scripts/town/covington.gd")
	var proc := _body(shell, "_process")
	var d := proc.find("if _dirty:")
	var b := proc.find("_refresh_b()")
	var l := proc.find("_later.pop_front()")
	var r := proc.find("_refresh_a(false)")
	t.ok(d > 0 and proc.find("_refresh_a(true)", d) > d and b > d and l > b and r > l,
		"_process takes one piece a frame: a command's phase A, else phase B, else one bind, else a due refresh")
	t.ok(not proc.contains("_fetch()"), "a command no longer fetches and binds everything in one frame")
	var a := _body(shell, "_refresh_a")
	t.ok(a.contains("_fetch_views_a()") and a.contains("if cmd:") and a.contains("_later = []"),
		"a command's phase A drops the pending binds")
	var rb := _body(shell, "_refresh_b")
	t.ok(rb.contains("_fetch_views_b(_pending)") and rb.contains("now.push_front(tab)") and rb.contains("TownModel.merge_pending("),
		"phase B binds the tab on show first after a command, and merges otherwise")
	var va := _body(shell, "_fetch_views_a")
	var vb := _body(shell, "_fetch_views_b")
	t.ok(["view_town()", "view_catalog()", "view_hud()", "view_rates()"].all(func(v): return va.contains(v))
		and not va.contains("view_realm") and not va.contains("view_stances"), "phase A: town, catalog, hud and rates together")
	t.ok(vb.contains("view_stances()") and vb.contains("view_realm()") and vb.contains("tab_suggestion("),
		"phase B: the stances, the fort digest and the shared suggestion")
	t.ok(_body(shell, "_fetch").contains("_fetch_views()") and _body(shell, "_fetch_views").contains("_fetch_views_b(_fetch_views_a())"),
		"the setup's fetch still binds everything at once, from both phases")
	var take := _body(shell, "_take")
	t.ok(take.contains("_update_goal(views)") and take.contains("_check_replay(views)"), "the goal and the replay read the full set")


## Q-g, the HUD idle line's truncation: the workers cell clipped "5 idle: build a Bone Mill (−0.00/s workers now,
## −0.39/s bodie". The cell takes the short line (the job count, no "or let them muster"); the tooltip keeps the
## whole one with its projected rates.
func _hud_idle_short() -> void:
	var bv: Dictionary = cfg["buildings_view"]
	var bc: Dictionary = cfg["buildings"]
	var row := {"building_id": "charnel_house", "cost": {"gold": 10.0, "bone": 0.0, "relics": 0}, "count": 0, "lot_size": 1,
		"max_level": 2, "requires": {"tier": "village", "blueprint": "", "building": ""}, "can_build": true, "reason": "",
		"lots": ["lot-06"], "projected": {"bodies": 0.4, "gold": -0.03}}
	var v := {"town": {"workers": {"idle": 10.0, "muster": 0.1}, "buildings": [], "jobs": [], "next_tier": {}},
		"hud": {"rates": [{"id": "gold", "rate": 0.2}, {"id": "bone", "rate": 0.2}]}, "catalog": {"buildings": [row]}, "fort_names": {}}
	var whole := HudModel.parts_text(HudModel.idle_parts(v, vcfg, bv, bc))
	var short := HudModel.parts_text(HudModel.idle_parts(v, vcfg, bv, bc, {}, true))
	var label := BuildSort.label_of("charnel_house", bv)
	t.ok(whole.contains("bodies now") and whole.ends_with("or let them muster"), "the tooltip's line keeps the rates: '%s'" % whole)
	t.ok(short == "10 idle: build a %s (+%d jobs)" % [label, BuildSort.job_slots("charnel_house", bc)],
		"the cell's line is short: '%s' (%d characters)" % [short, short.length()])
	t.ok(short.length() <= 48, "short enough for the workers cell beside '+0.03/s idle → FLOOD' (%d ≤ 48)" % short.length())
	var hud_src := FileAccess.get_file_as_string("res://scripts/town/town_hud.gd")
	t.ok(hud_src.contains("_tab, true)") and hud_src.contains(", whole].filter(") and hud_src.contains("tooltip_text = tip"),
		"the HUD binds the short line and tooltips the whole one (after the muster's tip)")


## The manager's ruling 5 on M2: one flow, one name. The HUD's "+0.06/s → WAR" was the idle muster, the same flow the
## forecast's "idle hands muster to FLOOD" names, so the two read as a contradiction. Every town line now names the
## muster's real destination (view_hud.split.muster_to: FLOOD, Vei's queue, unless the Muster stance sends it to WAR).
func _muster_words() -> void:
	var hcfg: Dictionary = vcfg["hud"]
	var flood := {"hud": {"split": {"muster_to": "flood"}}}
	var war := {"hud": {"split": {"muster_to": "war"}}}
	t.ok(HudModel.muster_word(flood, hcfg) == "idle → FLOOD" and HudModel.muster_word(war, hcfg) == "idle → WAR",
		"the HUD's word after the muster rate names its destination")
	t.ok(HudModel.muster_tip(flood, hcfg).contains("Vei's queue") and HudModel.muster_tip(war, hcfg).contains("Muster stance"),
		"its tooltip says where that is ('%s')" % HudModel.muster_tip(flood, hcfg))
	t.ok(HudModel.muster_to({"town": {"workers": {"muster_to": "war"}}}) == "war" and HudModel.muster_to({}) == "flood",
		"view_town's muster_to stands in when view_hud's split is missing; FLOOD when neither says (the rule without the stance)")
	t.ok(HudModel.muster_name(flood, vcfg) == "FLOOD (Vei's queue)" and HudModel.muster_name(war, vcfg) == "WAR (your forts)",
		"the forecast and the idle line name it with where it goes")
	var fv := {"town": {"workers": {"idle": 10.0}, "queue": []}, "hud": {"split": {"muster_to": "flood"}}}
	t.ok(TownForecast.parts_of(fv, vcfg, cfg["buildings_view"]).has("10 idle hands muster to FLOOD (Vei's queue)"),
		"the forecast: FLOOD by the view (%s)" % str(TownForecast.parts_of(fv, vcfg, cfg["buildings_view"])))
	var hud_src := FileAccess.get_file_as_string("res://scripts/town/town_hud.gd")
	t.ok(hud_src.contains("HudModel.muster_word(views, _hcfg)") and not String(vcfg["hud"]["text"].get("war", "")).contains("WAR"),
		"the HUD row reads its word from the view; no fixed '→ WAR' is left")
	# the real views agree with each other: the forecast's destination is the HUD's
	var s := GameState.new(cfg)
	s.debug_enabled = true
	s.cmd_debug_load_fixture("day1")
	s.tick(s.substep_s())
	var rv := {"hud": s.view_hud(), "town": s.view_town()}
	t.ok(HudModel.muster_to(rv) == String(rv["town"]["workers"]["muster_to"]),
		"day1: view_hud's split and view_town's workers name the same destination ('%s')" % HudModel.muster_to(rv))


## The M2 review's should-fixes 1-3 (reports/review-town-i-m2.md): a queue row's click finds its entry in today's queue
## before sending (the head may have started), one queue command per bind, and the refusal words in town.json.
func _review_m2() -> void:
	var a := {"building_id": "inn", "lot_id": "lot-13", "upgrade": false}
	var b := {"building_id": "house", "lot_id": "lot-05", "upgrade": false}
	var c := {"building_id": "market", "lot_id": "lot-07", "upgrade": true}
	var shown := [a, b, c]
	t.ok(BuildSort.live_index(shown, 2, [a, b, c]) == 2, "nothing moved: the same index")
	t.ok(BuildSort.live_index(shown, 2, [b, c]) == 1 and BuildSort.live_index(shown, 1, [b, c]) == 0,
		"the head started: each clicked entry is found one place up, not its old index's neighbour")
	t.ok(BuildSort.live_index(shown, 0, [b, c]) == -1, "the entry clicked has left the queue: -1, nothing is sent")
	var up2 := {"building_id": "market", "lot_id": "lot-07", "upgrade": true}
	t.ok(BuildSort.live_index([c, up2], 1, [c, up2]) == 1 and BuildSort.live_index([c, up2], 1, [up2]) == -1,
		"two upgrades of one lot: the same occurrence, or -1 once one has gone")
	t.ok(BuildSort.live_index(shown, 5, [a]) == -1 and BuildSort.live_index(shown, -1, [a]) == -1, "an index out of range: -1")
	var pb := FileAccess.get_file_as_string("res://scripts/town/panel_build.gd")
	var mq := _body(pb, "_move_queue")
	t.ok(mq.contains("BuildSort.live_index(") and mq.contains("cmd_unqueue(at)") and mq.contains("swap_order(live.size(), at, delta)"),
		"unqueue and reorder send the live index")
	t.ok(_body(pb, "_queue_real").contains("if _q_sent:") and _body(pb, "bind").contains("_q_sent = false"),
		"a second queue click before the next bind is dropped")
	t.ok(not pb.contains("Not queued: %s") and String(vcfg["queue_text"]["not_queued"]).contains("{why}"),
		"'Not queued' comes from town.json queue_text.not_queued")


## Q-g, the vat toggle's preview against the real staffing, in the costed case: with no idle hands to cover it,
## toggling a vat moves workers between jobs. The Backups tab's preview is the diff of two view_staffing_projection
## calls (BackupsModel.staffing_costs); after the real cmd_staff_vat and a substep, each job's staffing is the
## projection's. (The window check on pre_vei only saw "idle hands cover it", which can't tell a wrong preview.)
func _vat_costed() -> void:
	var s := GameState.new(cfg)
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("pre_vei")["ok"], "(setup) pre_vei")
	s.tick(s.substep_s())
	var idle := float(s.view_town()["workers"]["idle"])
	s.cmd_debug_grant({"workers": -(idle + 0.5)})  # no idle hands: a vat's tend job must take them from another job
	s.tick(s.substep_s())
	var vats: Array = s.view_backups().get("vats", [])
	t.ok(not vats.is_empty() and float(s.view_town()["workers"]["idle"]) < 1.0,
		"(setup) pre_vei has vats and no idle hand (%.2f idle)" % float(s.view_town()["workers"]["idle"]))
	if vats.is_empty():
		return
	# tend first on the ladder: the ladder fills top-down, so a tend slot below every job would take no one (the
	# preview then says "staffing takes no hand from a job", which is the rule); on top it takes from the lowest job
	var ladder: Array = (s.view_town()["ladder"] as Array).duplicate()
	ladder.erase("tend")
	ladder.push_front("tend")
	t.ok(s.cmd_set_job_priority(ladder)["ok"], "(setup) tend first on the ladder")
	s.tick(s.substep_s())
	var vat: Dictionary = vats[0]
	for v in vats:  # a ready vat holds its clone and takes no tend slot: a growing one does
		if not bool(v["ready"]):
			vat = v
			break
	var slot := int(vat["slot"])
	var on := not bool(vat["staffed"])
	var order: Array = TownBehaviour.effective(s.view_town())
	var before: Array = s.view_staffing_projection(order, {}).get("jobs", [])
	var after: Array = s.view_staffing_projection(order, {slot: on}).get("jobs", [])
	var diff := TownBehaviour.staffing_diff(before, after)
	var preview := BackupsModel.staffing_cost_text(diff, vcfg.get("job_labels", {}), vcfg["backups"], not on, 0.0)
	t.ok(not diff.is_empty(), "the costed case: toggling vat %d %s moves workers (%s); preview '%s'" % [slot, "on" if on else "off", str(diff), preview])
	t.ok(s.cmd_staff_vat(slot, on)["ok"], "(setup) the real toggle")
	s.tick(s.substep_s())
	var real := {}
	for j in s.view_town()["jobs"]:
		real[String(j["id"])] = float(j["staffed"])
	var off: Array = []
	for j in after:
		if absf(float(j["staffed"]) - float(real.get(String(j["id"]), 0.0))) > 0.51:
			off.append("%s projected %.2f real %.2f" % [j["id"], float(j["staffed"]), float(real.get(String(j["id"]), 0.0))])
	t.ok(off.is_empty(), "after the toggle each job's staffing is the projection's the preview was made from (%s)" % ("match" if off.is_empty() else ", ".join(off)))


## The foreman menu offers job buildings only (buildings.json jobs), a Chapel even while no vat is staffed.
func _foreman_menu() -> void:
	var blds := [{"building_id": "chapel_of_vats", "lot_id": "lot-13", "level": 1, "slots": 0},
		{"building_id": "house", "lot_id": "lot-05", "level": 1, "slots": 0},
		{"building_id": "market", "lot_id": "lot-04", "level": 1, "slots": 2},
		{"building_id": "bone_mill", "lot_id": "lot-09", "level": 0, "slots": 2}]
	var ids: Array = CryptLogic.foreman_lots(blds, {}, cfg["buildings"]).map(func(l): return l["lot_id"])
	t.ok(ids == ["lot-13", "lot-04"], "foreman menu: the Chapel (jobs, no slots open) and the Market; no House, no unbuilt mill (%s)" % str(ids))


## The crypt's away line rides on its badge line, so nothing draws a second line where a foreman stands.
func _away_label() -> void:
	var lines := TownModel.badge_lines({"badge": "10 idle", "away": "Relish away: slab idle"}, " · ")
	t.ok(lines.size() == 1 and lines[0][0] == "10 idle · Relish away: slab idle", "away label: one line with the badge (%s)" % str(lines))
	t.ok(TownModel.badge_lines({"away": "Relish away: slab idle"}, " · ") == [["Relish away: slab idle", "text_dim"]], "away label alone: one line")
	t.ok(TownModel.badge_lines({"badge": "1 short", "short": 1}, " · ") == [["1 short", "text"]] and TownModel.badge_lines({}, " · ").is_empty(),
		"a short badge reads in text; nothing draws nothing")


func _state(fixture: String) -> GameState:
	var s := GameState.new(cfg)
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture(fixture)["ok"], "(setup) %s loads" % fixture)
	return s


func _catalog(s: GameState) -> Dictionary:
	var out := {}
	for r in s.view_catalog()["buildings"]:
		out[String(r["building_id"])] = r
	return out


func _swap() -> void:
	t.ok(BuildSort.swap_order(3, 0, 1) == [1, 0, 2], "reorder: moving the head down swaps it with the second")
	t.ok(BuildSort.swap_order(3, 2, -1) == [0, 2, 1], "reorder: moving the last up swaps it with the one above")
	t.ok(BuildSort.swap_order(3, 2, 1) == [0, 1, 2] and BuildSort.swap_order(3, 0, -1) == [0, 1, 2], "reorder: out of range is the identity")
	var s := _state("day1")
	s.cmd_debug_grant({"gold": 500.0, "bone": 200.0})
	t.ok(s.cmd_queue_build("house", "lot-05")["ok"] and s.cmd_queue_build("well", "lot-06")["ok"], "(setup) two entries queued")
	var r: Dictionary = s.cmd_reorder_queue(BuildSort.swap_order(2, 0, 1))
	var q: Array = s.view_town()["queue"]
	t.ok(r["ok"] and q.size() == 2 and q[0]["building_id"] == "well" and q[1]["building_id"] == "house",
		"reorder: cmd_reorder_queue takes swap_order's permutation (%s)" % str(q.map(func(e): return e["building_id"])))


## Midgame is a Village: a Town-tier building that fits a free lot queues, the walk skips it as needs_tier, and the row
## says it waits for Town. (Day 1's free lots are all size 1; every Village building is size 2.)
func _gate_wait() -> void:
	var s := _state("midgame_2flips")
	var cat := _catalog(s)
	var bid := ""  # a Village building a free day-1 lot fits
	for id in cat:
		if cat[id]["reason"] == "needs_tier" and cat[id]["requires"]["tier"] == "town" and not (cat[id]["lots"] as Array).is_empty() \
				and cat[id]["requires"]["blueprint"] == "":
			bid = id
			break
	t.ok(bid != "" and BuildSort.can_queue(cat[bid], vcfg), "(setup) midgame has a tier-gated Town row with a free lot (%s), so its Queue shows" % bid)
	if bid == "":
		return
	var r: Dictionary = s.cmd_queue_build(bid, String(cat[bid]["lots"][0]))
	t.ok(r["ok"], "a tier-gated %s queues (the T3.2 ruling): %s" % [bid, r.get("reason", "")])
	var e: Dictionary = s.view_town()["queue"][0]
	var st := BuildSort.stocks({"town": s.view_town(), "hud": s.view_hud(), "catalog": s.view_catalog(), "inventory": s.view_inventory()})
	t.ok(e["status"] == "skipped_gate" and e["reason"] == "needs_tier" and BuildSort.is_gate_wait(e, vcfg),
		"its row is skipped_gate needs_tier: a gate it waits out")
	var line := BuildSort.skip_text(e, cat, st, cfg["buildings_view"], vcfg)
	t.ok(line == "queued: waits for Town", "the row reads 'queued: waits for Town': '%s'" % line)
	var g: Array = BuildSort.ghosts([e], cat, st, cfg["buildings_view"], vcfg)
	t.ok(g[0]["shape"] == "plain" and g[0]["text"] == line, "its canvas ghost is plain, not struck, with the same words")
	var taken := e.duplicate()
	taken["reason"] = "lot_taken"
	t.ok(not BuildSort.is_gate_wait(taken, vcfg) and BuildSort.skip_text(taken, cat, st, cfg["buildings_view"], vcfg).begins_with("skipped: "),
		"a lot taken by another build is a real skip: 'skipped: …'")
	var rel := e.duplicate()
	rel["reason"] = "no_relics"
	rel["cost"] = {"gold": 0.0, "bone": 0.0, "relics": 2}
	t.ok(BuildSort.skip_text(rel, cat, st, cfg["buildings_view"], vcfg) == "queued: waits for 2 relics: raid a fort",
		"a relic gate reads 'queued: waits for 2 relics: raid a fort'")
	t.ok(BuildSort.queue_etas([e], st, cat, s.view_town(), 1.0, vcfg) == [""], "a gated row has no start time (it says why instead)")


## The start comes from the view's affordable_in_s: 0 now, > 0 a wait.
func _affordable() -> void:
	var st := {"gold": 0.0, "bone": 0.0, "rates": {"gold": 1.0, "bone": 1.0}}
	var head := {"building_id": "house", "lot_id": "lot-05", "status": "waiting_funds", "cost": {"gold": 999.0, "bone": 0.0},
		"affordable_in_s": 120.0, "level": 1}
	var later := head.duplicate()
	later["status"] = "queued"
	later["affordable_in_s"] = 0.0
	var etas := BuildSort.queue_etas([head, later], st, {}, {}, -1.0, vcfg)
	t.ok(String(etas[0]).begins_with("starts in ~2 min"), "a head affordable in 120 s starts in ~2 min, not the local estimate: '%s'" % etas[0])
	t.ok(String(etas[1]).begins_with(String(vcfg["queue_text"]["eta_later_now"])), "affordable now behind it: '%s'" % etas[1])


func _never() -> void:
	var e := {"status": "waiting_funds", "affordable_in_s": -1.0, "short": {"gold": 0.0, "bone": 25.0}, "starved": "pits_first",
		"cost": {"gold": 0.0, "bone": 25.0}, "building_id": "house", "level": 1}
	var line := BuildSort.never_text(e, vcfg)
	t.ok(line.begins_with("can't be afforded at today's bone income") and line.contains("raise WAR"),
		"a never-affordable head names its store and the pits-first cause with its lever: '%s'" % line)
	var behind := {"status": "queued", "affordable_in_s": -1.0, "short": {"gold": 0.0, "bone": 0.0}}
	t.ok(BuildSort.never_text(behind, vcfg) == String(vcfg["queue_text"]["eta_behind"]), "an entry stuck behind it says it waits for the one ahead")
	t.ok(BuildSort.queue_etas([e], {"gold": 0.0, "bone": 0.0, "rates": {}}, {}, {}, -1.0, vcfg)[0] == line, "the queue's ETA line is that text")


func _hud_starved() -> void:
	var views := {"hud": {"rates": [{"id": "bone", "rate": 0.0, "stock": 10.0, "cap": 300.0}]},
		"town": {"buildings": [{"building_id": "bone_mill", "level": 1, "staffed": 2.0, "starved": "pits_first"}]}}
	var hcfg: Dictionary = vcfg["hud"]
	var line := HudModel.stuck_line("bone", "bone_mill", views, hcfg, cfg["buildings_view"])
	t.ok(line.contains("the pits take every body before the Bone Mill") and line.contains("raise WAR"),
		"the HUD names the mill's own cause and its lever: '%s'" % line)
	views["town"]["buildings"][0]["starved"] = "no_bodies"
	line = HudModel.stuck_line("bone", "bone_mill", views, hcfg, cfg["buildings_view"])
	t.ok(line.contains("no bodies coming in"), "no bodies at all reads so: '%s'" % line)
	views["town"]["buildings"][0]["starved"] = ""
	line = HudModel.stuck_line("bone", "bone_mill", views, hcfg, cfg["buildings_view"])
	t.ok(line.contains("is starved: no bodies"), "with no cause given the old line stands: '%s'" % line)
