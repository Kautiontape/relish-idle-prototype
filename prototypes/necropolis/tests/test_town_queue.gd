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
	_every_reason()
	_upkeep_live()
	_second_click()
	_queue_upgrade_click()
	_debug_flags()
	return t.failures


## review-town-i-r2 item 4: a second Queue click before the next bind was dropped with no word. Now every click is
## sent. The lots an ok command took since the bind count as taken (BuildSort.taken_lots, the Build tab's _free_lot),
## so a second click on the same row, against the same stale views, picks the next free lot and queues for real;
## with no lot left it is refused as no_lot, in words, and the line saying the first was queued stays
## (BuildSort.join_said). Both clicks go through BuildSort.send_queue, the panel's _queue_real rule, which records
## the lot it took in `sent` (the panel's _lots_sent): the test never fills `sent` itself (review-town-i-r3 should-fix 1).
func _second_click() -> void:
	var s := _state("day1")
	s.cmd_debug_grant({"gold": 5000.0, "bone": 2000.0})
	s.tick(s.substep_s())
	var town := s.view_town()  # the views as last bound: no click below re-reads them
	var row: Dictionary = _catalog(s)["house"]
	var lots: Array = row.get("lots", [])
	t.ok(lots.size() >= 2, "(setup) day1 has two or more free lots for a House (%s)" % str(lots))
	var sizes := BuildSort.lot_sizes({"town": town})
	var q0: Array = town.get("queue", [])
	var sent := {}
	var first := BuildSort.queue_lot(row, BuildSort.taken_lots(q0, sent), {}, {}, sizes)
	var r1 := BuildSort.send_queue(s, _build_entry("house", first), sent)
	t.ok(bool(r1.get("ok", false)), "the first click queues a House on %s (%s)" % [first, r1.get("reason", "")])
	t.ok(sent.keys() == [first], "send_queue records the lot the ok click took (%s)" % str(sent.keys()))
	t.ok(BuildSort.queue_lot(row, BuildSort.taken_lots(q0, {}), {}, {}, sizes) == first,
		"without the sent lots, the stale views would hand the second click %s again (the case the old guard dropped)" % first)
	var second := BuildSort.queue_lot(row, BuildSort.taken_lots(q0, sent), {}, {}, sizes)
	var r2 := BuildSort.send_queue(s, _build_entry("house", second), sent)
	t.ok(second != "" and second != first and bool(r2.get("ok", false)),
		"the second click, before any bind, queues on the next lot: %s then %s (%s)" % [first, second, r2.get("reason", "")])
	var nl := BuildSort.send_queue(s, _build_entry("house", ""), sent)
	t.ok(String(nl.get("reason", "")) == "no_lot" and s.view_town()["queue"].size() == q0.size() + 2,
		"a click with no free lot sends nothing: no_lot (%s)" % nl.get("reason", ""))
	var on := {}
	for e in s.view_town().get("queue", []):
		on[String(e.get("lot_id", ""))] = true
	for b in s.view_town().get("buildings", []):
		on[String(b.get("lot_id", ""))] = true
	t.ok(on.has(first) and on.has(second), "both Houses are in the town, queued or started, on their own lots (%s)" % str(on.keys()))
	for l in lots:
		sent[String(l)] = true
	t.ok(BuildSort.queue_lot(row, BuildSort.taken_lots(q0, sent), {}, {}, sizes) == "",
		"every lot sent: the next click has no lot, so the Build tab sends nothing and says no_lot")
	var why := BuildSort.reason_text("no_lot", row, {}, cfg["buildings_view"], vcfg)
	var no := BuildSort.fmt(String(vcfg["queue_text"]["not_queued"]), {"why": why})
	t.ok(why.contains("no free lot") and not why.contains("{"), "no_lot reads '%s'" % why)
	var line := BuildSort.join_said(BuildSort.join_said("", "Queued House on lot 5: starts now."), no)
	t.ok(line.begins_with("Queued House on lot 5: starts now. ") and line.ends_with(no),
		"a refused click after a queued one keeps the queued line and adds why: '%s'" % line)
	t.ok(BuildSort.taken_lots([{"lot_id": "lot-07"}], {"lot-05": true}).keys().size() == 2, "taken: the queue's lots and the sent ones")


## review-town-i-r3: the panel's Queue upgrade never queued. It sent the standing building's own id, which
## cmd_queue_build reads as a new build on a taken lot (lot_taken; unique for the Crypt). Every Queue click now goes
## through BuildSort.send_queue (panel_build.gd needs the autoloads and can't load headless, so the rule _queue_real
## calls is the static, run here on a real day1 GameState with the entry BuildSort.upgrade_entry builds, as
## _on_queue_upgrade does):
## - Queue upgrade sends "" for the building, the API's upgrade form, and queues an upgrade at the next level;
## - a second click on a lot an ok click took, before the next bind, sends nothing (just_queued), for an upgrade and
##   for a card's Queue alike: the panel queues one entry per lot (Queue greys once its lot has one), so a second
##   click is a double-click, never a chained upgrade;
## - a Queue click on a free lot queues a build;
## - the queued line reads as an upgrade at its level, with its own queue row's start or gate.
func _queue_upgrade_click() -> void:
	var s := _state("day1")
	s.cmd_debug_grant({"gold": 5000.0, "bone": 2000.0})
	s.tick(s.substep_s())
	var views := {"town": s.view_town(), "catalog": s.view_catalog(), "hud": s.view_hud(), "inventory": s.view_inventory()}
	var st := BuildSort.stocks(views)
	var bcfg: Dictionary = cfg["buildings"]
	var bview: Dictionary = cfg["buildings_view"]
	var cat := _catalog(s)
	var at := {}
	for b in views["town"]["buildings"]:
		at[String(b["lot_id"])] = b
	t.ok(String(at.get("lot-03", {}).get("building_id", "")) == "charnel_house" and String(at.get("lot-01", {}).get("building_id", "")) == "crypt",
		"(setup) day1 has the Charnel House on lot-03 and the Crypt on lot-01")
	if not (at.has("lot-03") and at.has("lot-01")):
		return
	var sent := {}
	var n0: int = s.view_town()["queue"].size()
	# a relic-free level, funds in hand: it starts now
	var e := BuildSort.upgrade_entry(at["lot-03"], "lot-03", st, bcfg, bview, vcfg)
	t.ok(bool(e["upgrade"]) and e["building_id"] == "charnel_house" and int(e["level"]) == 2, "(setup) the inspector's entry: %s" % str(e))
	var old := s.cmd_queue_build(String(e["building_id"]), "lot-03")
	t.ok(not bool(old["ok"]) and old["reason"] == "lot_taken", "the bug: the old send (its own id) is a new build, refused %s" % old["reason"])
	var r1 := BuildSort.send_queue(s, e, sent)
	var q: Array = s.view_town()["queue"]
	var row: Dictionary = q.back() if q.size() > n0 else {}
	t.ok(bool(r1["ok"]) and q.size() == n0 + 1 and bool(row.get("upgrade", false)) and row.get("lot_id", "") == "lot-03"
		and row.get("building_id", "") == "charnel_house" and int(row.get("level", 0)) == 2,
		"Queue upgrade queues the upgrade of the Charnel House to Lv 2 (%s; %s)" % [r1.get("reason", ""), str(row)])
	var line := BuildSort.queued_line(e, row, float(r1["affordable_in_s"]), cat, st, bview, vcfg)
	t.ok(line == "Queued the upgrade of Charnel House to Lv 2 on lot 3: it starts now.", "its line: '%s'" % line)
	var r2 := BuildSort.send_queue(s, e, sent)
	t.ok(not bool(r2["ok"]) and r2["reason"] == "just_queued" and s.view_town()["queue"].size() == n0 + 1,
		"a second Queue upgrade before the bind sends nothing, no chained upgrade (%s, %d entries)" % [r2["reason"], s.view_town()["queue"].size()])
	var jq := BuildSort.fmt(String(vcfg["queue_text"]["not_queued"]), {"why": BuildSort.reason_text("just_queued", {}, st, bview, vcfg)})
	t.ok(jq == "Not queued: that lot is already in the queue.", "just_queued reads '%s'" % jq)
	# the Crypt: unique, and its Lv 2 costs a relic day1 doesn't hold
	var ec := BuildSort.upgrade_entry(at["lot-01"], "lot-01", st, bcfg, bview, vcfg)
	var oc := s.cmd_queue_build(String(ec["building_id"]), "lot-01")
	t.ok(not bool(oc["ok"]) and oc["reason"] == "unique", "the bug on the Crypt: refused %s" % oc["reason"])
	var rc := BuildSort.send_queue(s, ec, sent)
	q = s.view_town()["queue"]
	var crow: Dictionary = q.back() if q.size() > n0 + 1 else {}
	t.ok(bool(rc["ok"]) and bool(crow.get("upgrade", false)) and crow.get("building_id", "") == "crypt" and crow.get("status", "") == "skipped_gate"
		and crow.get("reason", "") == "no_relics", "the Crypt's upgrade queues and waits for its relic (%s; %s)" % [rc.get("reason", ""), str(crow)])
	var cline := BuildSort.queued_line(ec, crow, float(rc["affordable_in_s"]), cat, st, bview, vcfg)
	t.ok(cline.begins_with("Queued the upgrade of Crypt to Lv 2 on lot 1: waits for 1 relic") and not cline.contains(String(vcfg["queue_text"]["queued_never"])),
		"its line names the relic, not today's income, and says queued once: '%s'" % cline)
	# a Queue click on a free lot queues a build; a second card click on that lot is refused the same way
	var lot := String((cat["house"]["lots"] as Array)[0])
	var rb := BuildSort.send_queue(s, _build_entry("house", lot), sent)
	q = s.view_town()["queue"]
	t.ok(bool(rb["ok"]) and not bool(q.back().get("upgrade", true)) and q.back().get("building_id", "") == "house" and q.back().get("lot_id", "") == lot,
		"a Queue click on free %s queues a House build (%s)" % [lot, rb.get("reason", "")])
	var rr := BuildSort.send_queue(s, _build_entry("house", lot), sent)
	t.ok(not bool(rr["ok"]) and rr["reason"] == "just_queued" and s.view_town()["queue"].size() == n0 + 3,
		"a second card Queue on %s before the bind sends nothing (%s)" % [lot, rr["reason"]])
	t.ok(BuildSort.queued_line(_build_entry("house", lot), q.back(), 0.0, cat, st, bview, vcfg).begins_with("Queued House on %s: " % TownModel.lot_name(lot, vcfg)),
		"a build's line keeps its words")
	# a gated build with its funds in hand: the old line judged by affordable_in_s first and said "it starts now"
	var ei := _build_entry("inn", "lot-13")
	var ri := BuildSort.send_queue(s, ei, sent)
	q = s.view_town()["queue"]
	var iline := BuildSort.queued_line(ei, q.back(), float(ri.get("affordable_in_s", -1.0)), cat, st, bview, vcfg)
	t.ok(bool(ri["ok"]) and q.back().get("status", "") == "skipped_gate" and iline == "Queued Inn on lot 13: waits for its lot to open at a higher tier.",
		"a gated build's line names its gate, not 'it starts now' (affordable_in_s %s): '%s'" % [ri.get("affordable_in_s", ""), iline])
	# the panel's wiring, which no headless test can reach: every Queue goes through _queue_real, which sends with
	# send_queue on _lots_sent; bind clears it and _free_lot skips it
	var pb := FileAccess.get_file_as_string("res://scripts/town/panel_build.gd")
	var qr := _body(pb, "_queue_real")
	t.ok(qr.contains("BuildSort.send_queue(Game.state, e, _lots_sent)") and not qr.contains("cmd_queue_build") and qr.contains("BuildSort.queued_line("),
		"_queue_real sends through send_queue with _lots_sent, and says queued_line")
	t.ok(_body(pb, "_on_queue_upgrade").contains("BuildSort.upgrade_entry(") and _body(pb, "_on_queue_upgrade").contains("_add_queue(")
		and _body(pb, "_on_card_queue").contains("_add_queue(") and _body(pb, "_on_queue").contains("_add_queue(")
		and _body(pb, "_add_queue").contains("_queue_real(e, row)"), "Queue upgrade, the card's Queue and the row's Queue all reach _queue_real")
	t.ok(_body(pb, "bind").contains("_lots_sent = {}") and _body(pb, "_free_lot").contains("_lots_sent"), "bind clears the sent lots; _free_lot skips them")


## review-town-i-r3 should-fix 4: --town-hold and --town-grant do nothing in a normal launch. covington.gd reads them
## through TownSetPiece.debug_has / debug_grant (it needs the autoloads, so the parse is the static). A normal launch
## from the editor is a debug build (debug_enabled true) with none of them; a release build has debug_enabled false.
func _debug_flags() -> void:
	var given := PackedStringArray(["--town-hold", "--town-grant=gold:20000,bone:5000"])
	var normal := PackedStringArray()
	t.ok(not TownSetPiece.debug_has(normal, "town-hold", true) and TownSetPiece.debug_grant(normal, true).is_empty(),
		"a normal launch (a debug build, no args): no hold, no grant")
	t.ok(not TownSetPiece.debug_has(given, "town-hold", false) and TownSetPiece.debug_grant(given, false).is_empty()
		and TownSetPiece.debug_arg(given, "town-grant", false) == "", "a release build (debug off): given, they still do nothing")
	t.ok(TownSetPiece.debug_has(given, "town-hold", true) and TownSetPiece.debug_grant(given, true) == {"gold": 20000.0, "bone": 5000.0},
		"a harness run with them: the hold and the grant")
	t.ok(TownSetPiece.debug_grant(PackedStringArray(["--town-grant=gold:x,bone"]), true).is_empty(), "a malformed grant grants nothing")
	var boot := preload("res://scripts/sim/boot_rule.gd")
	t.ok(boot.is_harness_args(given) and not boot.is_harness_args(normal), "either makes a harness session: no autosave is touched")
	var s := GameState.new(cfg)
	t.ok(not s.debug_enabled and not bool(s.cmd_debug_grant({"gold": 1.0}).get("ok", true)), "a GameState with debug off refuses the grant")
	var cv := FileAccess.get_file_as_string("res://scripts/town/covington.gd")
	t.ok(_body(cv, "_debug_set_pieces").contains("if not Game.state.debug_enabled:\n\t\treturn")
		and _body(cv, "_debug_set_pieces").contains("TownSetPiece.debug_grant(OS.get_cmdline_user_args(), Game.state.debug_enabled)")
		and _body(cv, "_debug_has").contains("TownSetPiece.debug_has(OS.get_cmdline_user_args(), name, Game.state.debug_enabled)"),
		"covington's drivers read them through TownSetPiece, behind debug_enabled")


func _build_entry(bid: String, lot: String) -> Dictionary:
	return {"building_id": bid, "lot_id": lot, "upgrade": false, "level": 1, "cost": {}}


## P2's queue fields (queue_slots, queue_list_max), read directly: a gated entry holds no slot, and the list caps at
## queue_list_max.
func _p2_counts() -> void:
	var rows := [{"status": "skipped_gate"}, {"status": "next"}, {"status": "queued"}]
	var p2 := {"queue": rows, "queue_max": 2, "queue_slots": 2, "queue_list_max": 4}
	t.ok(not BuildSort.queue_list_full(p2), "P2: 3 rows of a 4-row list: not full, whatever the slots say (a gated add holds none)")
	p2["queue"] = rows + [{"status": "skipped_gate"}]
	t.ok(BuildSort.queue_list_full(p2), "P2: the list at queue_list_max is full")
	t.ok(BuildSort.queue_slots_text(p2, vcfg) == "2 of 2 slots held; 2 wait without one",
		"P2: the title counts slot-holding rows, and (the V-I3 round) says the gated rows hold none (%s)" % BuildSort.queue_slots_text(p2, vcfg))
	p2["queue"] = rows
	t.ok(BuildSort.queue_slots_text(p2, vcfg) == "2 of 2 slots held; 1 waits without one", "one gated row: '%s'" % BuildSort.queue_slots_text(p2, vcfg))
	p2["queue"] = rows.slice(1)
	t.ok(BuildSort.queue_slots_text(p2, vcfg) == "2 of 2 slots held", "no gated row: just the slots held: '%s'" % BuildSort.queue_slots_text(p2, vcfg))
	var no_p2 := {"queue": rows, "queue_max": 3}
	t.ok(not BuildSort.queue_list_full(no_p2) and BuildSort.queue_slots_text(no_p2, vcfg) == "",
		"a view without P2's fields: no count of ours (the old every-row rule is gone)")
	var ws := {"status": "skipped_gate", "reason": "wait_slot", "building_id": "house", "lot_id": "lot-05"}
	t.ok(BuildSort.is_gate_wait(ws, vcfg) and BuildSort.skip_text(ws, {}, {}, cfg["buildings_view"], vcfg) == "queued: waits for a slot",
		"P3's wait_slot reads as a wait in its place: '%s'" % BuildSort.skip_text(ws, {}, {}, cfg["buildings_view"], vcfg))
	t.ok(String(BuildSort.ghosts([ws], {}, {}, cfg["buildings_view"], vcfg)[0]["shape"]) == "plain", "a slot wait's ghost is plain, not struck")
	var wr := BuildSort.reason_text("wait_slot", {}, {}, cfg["buildings_view"], vcfg)
	t.ok(wr == String(vcfg["reasons"]["wait_slot"]) and wr.contains("slot"), "wait_slot as a plain reason has its own words, not _unknown: '%s'" % wr)
	var s := _state("day1")
	var town := s.view_town()
	t.ok(town.has("queue_slots") and town.has("queue_list_max"), "the live view has P2's fields")
	t.ok(BuildSort.queue_slots_text(town, vcfg) == "0 of %d slots held" % int(town["queue_max"]) and not BuildSort.queue_list_full(town),
		"the live view: '%s'" % BuildSort.queue_slots_text(town, vcfg))


## The V-I3 round, ruling 3: every reason the queue's walk can give a row (BuildRules._queue_gate's codes, the never
## head's no_gold/no_bone, wait_slot: GameState.REPORT_WAITED_ON plus max_level, unique and lot_too_small, which
## _queue_gate also returns) reads as its own words on the row, skipped or saving, never reasons._unknown ("can't do
## that right now", 05b's two upkeep rows). Revert proof: the upkeep keys dropped.
func _every_reason() -> void:
	var unknown := String(vcfg["reasons"]["_unknown"])
	var codes: Array = GameState.REPORT_WAITED_ON + ["max_level", "unique", "lot_too_small"]
	var bad: Array = []
	for code in codes:
		var e := {"status": "skipped_gate", "reason": code, "building_id": "house", "lot_id": "lot-05", "upgrade": false, "level": 1,
			"cost": {"gold": 40.0, "bone": 10.0, "relics": 1}}
		var line := String(BuildSort.queue_detail(e, {}, {}, cfg["buildings_view"], vcfg)["text"])
		if line.contains(unknown) or line.contains("{") or line.strip_edges() == "" or not (vcfg["reasons"] as Dictionary).has(code):
			bad.append("%s: '%s'" % [code, line])
	for code in ["no_gold", "no_bone"]:
		var e := {"status": "waiting_funds", "reason": code, "building_id": "house", "lot_id": "lot-05", "upgrade": false, "level": 1,
			"cost": {"gold": 40.0, "bone": 10.0, "relics": 0}}
		var line := String(BuildSort.queue_detail(e, {}, {}, cfg["buildings_view"], vcfg)["text"])
		if line.contains(unknown) or line.contains("{"):
			bad.append("%s (saving): '%s'" % [code, line])
	t.ok(bad.is_empty(), "every reason a queue row can carry (%d) has its own words, none '%s': %s" % [codes.size(), unknown, str(bad)])
	var upk := {"status": "skipped_gate", "reason": "upkeep", "building_id": "stables", "lot_id": "lot-15", "upgrade": false, "level": 1, "cost": {}}
	var d := BuildSort.queue_detail(upk, {}, {}, cfg["buildings_view"], vcfg)
	t.ok(BuildSort.is_gate_wait(upk, vcfg) and d["text"] == "queued: waits until your gold income can pay its upkeep" and d["key"] == "text_dim",
		"an upkeep row waits in its place, in its own words, queued rather than struck: '%s'" % d["text"])
	var up := upk.duplicate()
	up["upgrade"] = true  # build_rules: an upgrade of an unpaid building the income test holds off; the same words hold
	t.ok(BuildSort.queue_detail(up, {}, {}, cfg["buildings_view"], vcfg)["text"] == d["text"], "an upgrade held by the income test reads the same")
	t.ok(String(BuildSort.ghosts([upk], {}, {}, cfg["buildings_view"], vcfg)[0]["shape"]) == "plain", "its ghost is plain, not struck")


## The V-I3 round's 05b, live: midgame_2flips with the tour's eight builds queued. Five start at once on the fixture's
## stock; their upkeep turns net gold negative, so the Stables and the House behind them are skipped_gate `upkeep`,
## and their rows say so.
func _upkeep_live() -> void:
	var s := _state("midgame_2flips")
	for pair in [["house", "lot-08"], ["house", "lot-09"], ["bakery", "lot-10"], ["inn", "lot-13"], ["graveyard", "lot-14"],
			["stables", "lot-15"], ["house", "lot-16"], ["bakery", "lot-17"]]:
		s.cmd_queue_build(pair[0], pair[1])
	s.tick(5.0)
	var town := s.view_town()
	var cat := _catalog(s)
	var st := BuildSort.stocks({"town": town, "hud": s.view_hud(), "catalog": s.view_catalog(), "inventory": s.view_inventory()})
	var upk: Array = (town["queue"] as Array).filter(func(e): return String(e["status"]) == "skipped_gate" and String(e["reason"]) == "upkeep")
	t.ok(not upk.is_empty(), "(setup) the tour's 05b queue has rows held by upkeep: %s" % str((town["queue"] as Array).map(func(e): return "%s %s %s" % [e["building_id"], e["status"], e["reason"]])))
	var lines: Array = (town["queue"] as Array).map(func(e): return String(BuildSort.queue_detail(e, cat, st, cfg["buildings_view"], vcfg)["text"]))
	t.ok(not lines.any(func(l): return String(l).contains(String(vcfg["reasons"]["_unknown"]))), "no row of it reads '_unknown': %s" % str(lines))
	var head := BuildSort.queue_slots_text(town, vcfg)
	var gated := (town["queue"] as Array).filter(func(e): return String(e["status"]) == "skipped_gate").size()
	t.ok(gated > 0 and head.ends_with("wait without one") == (gated > 1) and head.begins_with("%d of %d slots held" % [int(town["queue_slots"]), int(town["queue_max"])]),
		"the header says what it counts: '%s'" % head)


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
