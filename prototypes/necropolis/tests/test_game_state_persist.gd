extends RefCounted
## GameState persistence (STATE-API 9, 4.1 save/load, 4.6 fixtures): the JSON round trip, in-place
## loads, forfeited runs, corrupt and future files, atomic writes, list_saves, determinism, the
## three fixtures and the T1.4 gaps (applied_runs, the dungeon sink, hold and clear counters).
## Headless, no autoloads. Saves go under user://test_saves_<pid>, removed at the end.

var t: TestUtil
var _dir := "user://test_saves_%d" % OS.get_process_id()


func _mk(seed_val := 1) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.save_dir = _dir
	s.cmd_new_game(seed_val)
	return s


func _raid_result(sd: Dictionary, over := {}) -> Dictionary:
	var r := {
		"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "fort_id": sd["fort"]["id"],
		"warden_beaten": false, "retreated": true, "relish_died": false, "revived_in_place": 0,
		"killed_living_mass": 0.0, "raised": [], "chaff_mass": 0.0, "garrison_mass": sd["garrison_in_mass"],
		"party_lost": [], "loot": {"relics": 0, "blueprints": [], "husks": [], "remnants": [], "essence": 0},
	}
	r.merge(over, true)
	return r


## Flips `fort` (Relish is put there, a raid is opened and won). Returns the applied result.
func _flip(s: GameState, fort: String, loot_over := {}) -> Dictionary:
	s.cmd_debug_set_state({"relish_at": fort})
	var b := s.cmd_begin_dungeon(fort)
	var loot := {"relics": 1, "blueprints": ["embalmer"], "husks": [{"kind": "hulk"}],
		"remnants": [{"aspect": "beef", "rarity": "rare", "magnitude": 2}], "essence": 5}
	loot.merge(loot_over, true)
	var res := _raid_result(b["seed"], {"warden_beaten": true, "retreated": false, "killed_living_mass": 20.0,
		"raised": [{"score": 80, "count": 2, "mass": 5.0}], "chaff_mass": 2.0, "loot": loot})
	var ar := s.apply_result("raid", res)
	res["_applied"] = ar["ok"]
	return res


## A state with something in every block: stores, settings, big undead and a party with fronts, a
## flipped fort, village owners, a convoy, Relish on the road, and the E2/E3 placeholders.
func _rich(seed_val := 1) -> GameState:
	var s := _mk(seed_val)
	s.cmd_debug_grant({"gold": 120.5, "bone": 40.25, "bodies": 30.0, "husks": 2, "remnants": 3,
		"big_undead": 3, "backlog": 5000.5})
	s.cmd_set_valve(3.0, 2.0, 1.0)
	s.cmd_set_stance("harvest", true)
	s.cmd_set_job_priority(["haul", "build", "pit", "stall", "mill", "forge", "tend"])
	s.cmd_set_staff_cap("lot-03", 2)
	s.town["vats"] = 2
	s.cmd_staff_vat(1, true)
	s.apply_town_result({"assignments": {"trade": 1, "forge": 0, "jobs": 1, "gather": 1, "slab": 0}, "idle_undead": 3})
	s.cmd_set_haul_target("ashgate")
	var bus: Array = s.view_big_undead()["big_undead"]
	s.cmd_place_big_undead(bus[2]["uid"], "town:lot-04")
	s.cmd_set_party([bus[0]["uid"], bus[1]["uid"]])
	s.cmd_assign_front(bus[0]["uid"], "giants")
	s.cmd_rename_big_undead(bus[1]["uid"], "Old Gristle")
	s.tick(30.0)
	_flip(s, "old-sluice")
	s._tithe = {"warning": {"fort_id": "ashgate", "eta_s": 150.5}}
	s._phylactery_charges = 1
	s._readout = {"diff_ema": -0.25, "q_raise_ema": 1.5}
	s._stance_hold = {"harvest": 12.5}
	s.cmd_move_relish("vei")
	s.tick(1.0)
	s.cmd_set_time_scale(1.0)
	s.towns[0]["control"] = "green"  # after the last tick, which would recompute them from the field
	s.towns[1]["control"] = "orange"
	s.green_towns = 1
	return s


# ------------------------------------------------------------------- helpers ----
func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _slot_path(slot: String) -> String:
	return "%s/%s.json" % [_dir, slot]


## Every view but the live field and the seeds, `rev` stripped, village dominance dropped (A6).
func _views(s: GameState) -> Dictionary:
	var out := {}
	for name in ApiSchema.VIEWS:
		if name == "view_field" or name == "view_dungeon_seed" or name == "view_boss_seed":
			continue
		if name == "view_fort":
			for f in s.realm.forts:
				out["view_fort:" + f["id"]] = s.view_fort(f["id"])
		else:
			out[name] = s.call(name)
	for k in out:
		out[k].erase("rev")
	for v in out["view_villages"]["villages"]:
		v.erase("dominance")
	return out


## Deep difference, floats within eps (relative or absolute).
func _diff(a: Variant, b: Variant, eps: float, path: String, out: Array) -> void:
	if out.size() > 5:
		return
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		for k in a:
			if not b.has(k):
				out.append("%s.%s missing in b" % [path, str(k)])
			else:
				_diff(a[k], b[k], eps, "%s.%s" % [path, str(k)], out)
		for k in b:
			if not a.has(k):
				out.append("%s.%s missing in a" % [path, str(k)])
	elif typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if a.size() != b.size():
			out.append("%s size %d vs %d" % [path, a.size(), b.size()])
			return
		for i in a.size():
			_diff(a[i], b[i], eps, "%s[%d]" % [path, i], out)
	elif typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		if absf(a - b) > eps * maxf(1.0, maxf(absf(a), absf(b))):
			out.append("%s %s vs %s" % [path, str(a), str(b)])
	elif typeof(a) != typeof(b) or a != b:
		out.append("%s %s vs %s" % [path, str(a), str(b)])


func _events_of(s: GameState) -> Array:
	return s.drain_events().map(func(e): return e["type"])


func _rm_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(dir + "/" + sub)
	DirAccess.remove_absolute(dir)


func _cleanup() -> bool:
	_rm_tree(_dir)
	return not DirAccess.dir_exists_absolute(_dir)


func run() -> int:
	t = TestUtil.new()
	t.suite("game-state-persist")
	_round_trip()
	_in_place_and_ints()
	_open_runs()
	_bad_files()
	_saves_and_list()
	_determinism()
	_gaps()
	_fixtures()
	_migrate()
	t.ok(_cleanup(), "the test save directory is gone")
	return t.failures


# ------------------------------------------------------------- the round trip ----
func _round_trip() -> void:
	var a := _rich()
	var d := a.to_dict()
	var errs: Array = []
	ApiSchema.non_finite(d, "to_dict", errs)
	t.ok(errs.is_empty(), "to_dict holds no INF or NaN %s" % str(errs))
	var text := JSON.stringify(d)
	var parsed: Variant = JSON.parse_string(text)
	t.ok(parsed is Dictionary, "to_dict survives JSON.stringify and parse_string")
	var b := GameState.new(TestUtil.configs())
	b.save_dir = _dir
	var r := b.from_dict(parsed)
	t.ok(r == {"ok": true, "reason": ""}, "from_dict into a second state is ok: %s" % str(r))
	var db := b.to_dict()
	var why: Array = []
	_diff(d, db, 0.0, "d", why)
	t.ok(db == d, "to_dict after the JSON round trip is equal, types included %s" % str(why))
	t.ok(JSON.stringify(db) == text, "and so is its JSON text")
	var c := GameState.new(TestUtil.configs())
	c.from_dict(JSON.parse_string(text))
	t.ok(_views(b) == _views(c), "two loads of one file show identical views")
	var diffs: Array = []
	_diff(_views(a), _views(b), 1e-9, "views", diffs)
	t.ok(diffs.is_empty(), "the loaded views match the live ones to 1e-9 %s" % str(diffs))
	a.from_dict(JSON.parse_string(text))
	t.ok(_views(a) == _views(b), "after a self-load the views are identical")
	t.ok(b.view_relish()["state"] == "travelling" and b.view_relish()["target"] == "vei", "Relish is still on the road")
	t.ok(b.field.green.size() == 128 * 90 and not is_zero_approx(b.field.green[b.field.cell_of(b.realm.cov_pos).y * 128 + b.field.cell_of(b.realm.cov_pos).x]),
		"the field is pre-warmed on load (not saved)")
	t.ok(b.towns[0]["control"] == "green" and b.towns[1]["control"] == "orange" and b.green_towns == 1, "village owners come back from `villages`")
	t.ok(not text.contains("in_dungeon") and not text.contains("in_boss") and not text.contains("debug_enabled")
		and not text.contains("time_scale") and not text.contains("paused") and not text.contains("\"rev\""), "session-only fields are not saved")
	t.ok(d["seed"] is String and d["rng"] is String and d["v"] == 1 and d["api_version"] == GameState.API_VERSION, "seed and rng are strings; v and api_version")
	# the generator state survives: the same next number from a loaded copy
	var fresh := _rich()
	var e := GameState.new(TestUtil.configs())
	e.from_dict(JSON.parse_string(JSON.stringify(fresh.to_dict())))
	t.ok(e.rng.randi() == fresh.rng.randi(), "a loaded state draws the same random numbers")


# ----------------------------------------------- identity, counters, session ----
func _in_place_and_ints() -> void:
	var s := _rich()
	var id := s.get_instance_id()
	t.ok(s.cmd_save("one")["ok"], "saved")
	var before := s.to_dict()
	s.cmd_debug_grant({"gold": 500.0, "husks": 1})
	s.cmd_set_valve(1.0, 1.0, 1.0)
	s.tick(10.0)
	s.cmd_pause(true)
	s.cmd_set_time_scale(4.0)
	s.drain_events()
	s.cmd_set_stance("vigil", true)
	s._emit({"type": "x"})
	var rv := s.rev
	var rid := s.next_run_id
	var uid := s.next_uid
	var r := s.cmd_load("one")
	t.ok(r == {"ok": true, "reason": ""}, "cmd_load ok: %s" % str(r))
	t.ok(s.get_instance_id() == id, "the same state object survives a load")
	t.ok(s.rev == rv + 1, "a load adds exactly 1 to rev")
	t.ok(s.time_scale == 1.0 and not s.paused and s.drain_events().is_empty(), "time scale 1, unpaused, events cleared")
	var kept := before.duplicate(true)
	kept["next_uid"] = uid  # the counters never go back (checked below)
	kept["next_run_id"] = rid
	var why: Array = []
	_diff(kept, s.to_dict(), 0.0, "d", why)
	t.ok(s.to_dict() == kept, "the saved state is back %s" % str(why))
	t.ok(s.next_uid >= uid and s.next_run_id >= rid, "counters never go backwards (%d>=%d, %d>=%d)" % [s.next_uid, uid, s.next_run_id, rid])
	var old: Dictionary = _read_json(_slot_path("one"))
	t.ok(old["next_run_id"] == before["next_run_id"] and old["next_uid"] == before["next_uid"], "the file kept the older counters")
	# ints come back as ints
	var d := s.to_dict()
	for pair in [["next_run_id", d["next_run_id"]], ["next_uid", d["next_uid"]], ["relics", d["inventory"]["relics"]],
			["essence", d["inventory"]["essence"]], ["slabs", d["legacy"]["town"]["slabs"]],
			["idle_undead", d["legacy"]["idle_undead"]], ["raids", d["stats"]["raids"]],
			["staff cap", d["town"]["staff_caps"]["lot-03"]], ["level", d["town"]["lots"][0]["level"]],
			["flipped", d["realm"]["forts"][1]["flipped_count"]], ["magnitude", d["inventory"]["remnants"][0]["magnitude"]],
			["applied run", d["applied_runs"][0]]]:
		t.ok(typeof(pair[1]) == TYPE_INT, "%s is an int after a load" % pair[0])
	# a second state loading an older file keeps its own higher counters
	var o := _mk()
	for i in 3:
		o.cmd_debug_set_state({"relish_at": "ashgate"})
		o.cmd_begin_dungeon("ashgate")
		o.cmd_abort_dungeon()
	o.cmd_debug_grant({"husks": 3})
	o.cmd_save("early")
	for i in 3:
		o.cmd_begin_dungeon("ashgate")
		o.cmd_abort_dungeon()
	o.cmd_debug_grant({"remnants": 2})
	var rid2 := o.next_run_id
	var uid2 := o.next_uid
	t.ok(o.cmd_load("early")["ok"], "an older save loads")
	t.ok(o.next_run_id == rid2 and o.next_uid == uid2, "next_run_id and next_uid never go backwards across a load")
	# a hand-edited file whose counter is behind its own items cannot mint a duplicate uid
	var dd := o.to_dict()
	dd["next_uid"] = 1
	var p := GameState.new(TestUtil.configs())
	p.from_dict(JSON.parse_string(JSON.stringify(dd)))
	p.debug_enabled = true
	var mint: Array = p.cmd_debug_grant({"husks": 1})["applied"]["minted"]
	var uids := {}
	for h in p.husks:
		uids[h["uid"]] = true
	t.ok(uids.size() == p.husks.size() and mint.size() == 1, "next_uid is lifted above the saved uids")
	# float canon: nothing in the dict changes through a JSON text round trip
	var q := _rich(7)
	q.tick(13.3)
	var qd := q.to_dict()
	var qp: Dictionary = JSON.parse_string(JSON.stringify(qd))
	var q2 := GameState.new(TestUtil.configs())
	q2.from_dict(qp)
	var qw: Array = []
	_diff(qd, q2.to_dict(), 0.0, "d", qw)
	t.ok(q2.to_dict() == qd, "every float in to_dict is its own JSON round trip %s" % str(qw))


# ----------------------------------------------------------------- open runs ----
func _open_runs() -> void:
	var s := _mk()
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	s.cmd_debug_grant({"big_undead": 2})
	var bus: Array = s.view_big_undead()["big_undead"]
	s.cmd_set_party([bus[0]["uid"], bus[1]["uid"]])
	var b := s.cmd_begin_dungeon("old-sluice")
	t.ok(s.run.size() == 5 and s.relish["state"] == "in_dungeon", "a raid is open")
	var d := s.to_dict()
	t.ok(d["relish"]["state"] == "at_fort" and d["relish"]["at"] == "old-sluice" and d["relish"]["target"] == "", "the open raid is saved as at_fort at its fort")
	t.ok(JSON.stringify(d).find("in_dungeon") == -1, "in_dungeon never reaches the file")
	t.ok(d["party"].size() == 2, "the party is intact in the file")
	t.ok(s.relish["state"] == "in_dungeon" and not s.run.is_empty(), "the live state is untouched by saving")
	var rv := s.rev
	var r := s.cmd_save("run")
	t.ok(r["ok"] and s.rev == rv + 1 and s.run["run_id"] == b["run_id"], "cmd_save during a run succeeds and leaves the run alone")
	t.ok(s.cmd_load("run") == {"ok": false, "reason": "busy"}, "cmd_load is busy during a run")
	s.cmd_abort_dungeon()
	var n := GameState.new(TestUtil.configs())
	n.save_dir = _dir
	n.debug_enabled = true
	t.ok(n.cmd_load("run")["ok"], "the run file loads")
	t.ok(n.run.is_empty() and n.view_relish()["state"] == "at_fort" and n.view_relish()["can_descend"], "a load forfeits the run: at_fort, no run")
	t.ok(n.party_uids.size() == 2 and n.next_run_id > int(b["run_id"]), "the party is intact and the run id is not reused")
	t.ok(n.cmd_begin_dungeon("old-sluice")["ok"], "a new run can open after the load")
	# the boss
	var m := _mk()
	m.cmd_debug_set_state({"relish_at": "vei"})
	m.cmd_begin_boss()
	var md := m.to_dict()
	t.ok(md["relish"]["state"] == "at_vei" and md["relish"]["at"] == "vei" and JSON.stringify(md).find("in_boss") == -1, "an open boss run is saved as at_vei")
	# a file that claims an open run is corrupt
	for st in ["in_dungeon", "in_boss"]:
		var bad := _rich().to_dict()
		bad["relish"]["state"] = st
		var f := GameState.new(TestUtil.configs())
		t.ok(f.from_dict(bad) == {"ok": false, "reason": "corrupt"}, "a saved relish.state %s is corrupt" % st)


# ----------------------------------------------------------------- bad files ----
func _bad_files() -> void:
	var s := _rich()
	DirAccess.make_dir_recursive_absolute(_dir)
	_write(_slot_path("garbage"), "{not json")
	_write(_slot_path("array"), "[1, 2, 3]")
	_write(_slot_path("string"), "\"hello\"")
	_write(_slot_path("nov"), "{\"x\": 1}")
	_write(_slot_path("empty"), "")
	var strv := s.to_dict()
	strv["v"] = "1"
	_write(_slot_path("strv"), JSON.stringify(strv))
	var future := s.to_dict()
	future["v"] = GameState.SAVE_VERSION + 1
	_write(_slot_path("future"), JSON.stringify(future))
	var zero := s.to_dict()
	zero["v"] = 0
	_write(_slot_path("zero"), JSON.stringify(zero))
	var broken := s.to_dict()
	broken.erase("legacy")
	_write(_slot_path("broken"), JSON.stringify(broken))
	var typed := s.to_dict()
	typed["realm"]["forts"][0]["living"] = "lots"
	_write(_slot_path("typed"), JSON.stringify(typed))
	var node := s.to_dict()
	node["relish"]["at"] = "nowhere"
	_write(_slot_path("node"), JSON.stringify(node))
	var fortset := s.to_dict()
	fortset["realm"]["forts"].remove_at(3)
	_write(_slot_path("fortset"), JSON.stringify(fortset))
	var partym := s.to_dict()
	partym["party"] = ["u999"]
	_write(_slot_path("partym"), JSON.stringify(partym))
	var before := s.to_dict()
	var rv := s.rev
	for slot in ["garbage", "array", "string", "nov", "empty", "strv", "broken", "typed", "node", "fortset", "partym", "missing"]:
		t.ok(s.cmd_load(slot) == {"ok": false, "reason": "no_save"}, "%s is no_save" % slot)
	for slot in ["future", "zero"]:
		t.ok(s.cmd_load(slot) == {"ok": false, "reason": "bad_version"}, "%s is bad_version" % slot)
	t.ok(s.cmd_load("Bad Slot") == {"ok": false, "reason": "bad_slot"}, "a bad slot name is bad_slot")
	t.ok(s.rev == rv and s.to_dict() == before, "a refused load leaves rev and the state alone")
	var f := GameState.new(TestUtil.configs())
	t.ok(f.from_dict({}) == {"ok": false, "reason": "corrupt"}, "an empty dict is corrupt")
	t.ok(f.from_dict({"v": 1}) == {"ok": false, "reason": "corrupt"}, "v alone is corrupt")
	t.ok(f.from_dict({"v": 99}) == {"ok": false, "reason": "bad_version"}, "v above SAVE_VERSION is bad_version")
	t.ok(f.from_dict({"v": 1.5}) == {"ok": false, "reason": "bad_version"}, "a fractional v is bad_version (the migration fails)")
	t.ok(f.rev == 0, "refused from_dict calls never bump rev")


# --------------------------------------------------------- saves and listing ----
func _saves_and_list() -> void:
	var s := _rich()
	s.drain_events()
	var rv := s.rev
	var r := s.cmd_save("slot1")
	var now := int(Time.get_unix_time_from_system())
	t.ok(r["ok"] and r["reason"] == "" and typeof(r["saved_at"]) == TYPE_INT and absi(int(r["saved_at"]) - now) <= 2
		and r["path"] == _slot_path("slot1"), "cmd_save: ok, saved_at (int, now) and path")
	t.ok(s.rev == rv + 1 and s.drain_events().is_empty(), "a non-auto save bumps rev once and emits nothing")
	t.ok(s.saved_unix == r["saved_at"] and s.to_dict()["saved_unix"] == r["saved_at"], "cmd_save stamps saved_unix")
	t.ok(_mk().to_dict()["saved_unix"] == 0, "a never-saved state has saved_unix 0")
	var files := Array(DirAccess.get_files_at(_dir))
	t.ok(files.has("slot1.json") and not files.any(func(f: String): return f.ends_with(".tmp")), "the file is there and no .tmp is left")
	var file: Dictionary = _read_json(_slot_path("slot1"))
	t.ok(file["slot"] == "slot1" and file["saved_at"] == r["saved_at"] and file["summary"] is String, "the file adds slot, saved_at and summary")
	var rex := RegEx.new()
	rex.compile("^\\d+:\\d\\d · [A-Z][a-z]+ · odds \\d\\.\\d\\d$")
	t.ok(rex.search(file["summary"]) != null, "summary reads like '0:00 · Hamlet · odds 0.00': %s" % file["summary"])
	var want := s.to_dict()
	want["slot"] = "slot1"
	want["saved_at"] = r["saved_at"]
	want["summary"] = file["summary"]
	t.ok(FileAccess.get_file_as_string(_slot_path("slot1")) == JSON.stringify(want), "the file is to_dict() plus the three file keys")
	var a := s.cmd_save("auto")
	t.ok(a["ok"] and _events_of(s) == ["autosaved"], "slot auto emits autosaved")
	s.cmd_save("auto")
	var ev := s.drain_events()
	t.ok(ev.size() == 1 and ev[0]["slot"] == "auto" and ev[0]["saved_at"] >= file["saved_at"], "autosaved carries slot and saved_at")
	# overwrite: the second save of a slot replaces the first and leaves no .tmp
	t.ok(not Array(DirAccess.get_files_at(_dir)).any(func(f: String): return f.ends_with(".tmp")), "no .tmp after repeated saves")
	# refusals
	var bad: Array = ["", "A", "a b", "a/b", "../x", "a.b", "é", "x".repeat(33), "a\n", "UP"]
	for slot in bad:
		rv = s.rev
		var br := s.cmd_save(slot)
		var evs := s.drain_events()
		t.ok(br == {"ok": false, "reason": "bad_slot", "saved_at": 0, "path": ""} and s.rev == rv
			and evs.size() == 1 and evs[0]["type"] == "save_failed" and evs[0]["slot"] == slot and evs[0]["reason"] == "bad_slot",
			"slot %s: bad_slot, save_failed, rev alone" % JSON.stringify(slot))
	t.ok(s.cmd_save("x".repeat(32))["ok"] and s.cmd_save("a-b_9")["ok"], "32 characters, dash, underscore and digits are fine")
	s.drain_events()
	var keep := s.save_dir
	DirAccess.make_dir_recursive_absolute(_dir)
	_write(_dir + "/blocker", "x")
	print("  (an ERROR about not creating a directory is expected next)")
	s.save_dir = _dir + "/blocker/sub"
	rv = s.rev
	var wf := s.cmd_save("auto")
	var wev := s.drain_events()
	t.ok(wf == {"ok": false, "reason": "write_failed", "saved_at": 0, "path": ""} and s.rev == rv, "an unwritable directory is write_failed")
	t.ok(wev.size() == 1 and wev[0]["type"] == "save_failed" and wev[0]["slot"] == "auto" and wev[0]["reason"] == "write_failed", "save_failed carries slot and reason")
	s.save_dir = keep
	# a missing directory is created
	s.save_dir = _dir + "/deep/er"
	t.ok(s.cmd_save("made")["ok"] and FileAccess.file_exists(_dir + "/deep/er/made.json"), "a missing save_dir is created")
	s.save_dir = keep
	# list_saves: newest first, ties by slot, corrupt omitted
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir + "/" + f)
	var base := s.to_dict()
	var stamps := {"old": 100, "new": 300, "mid": 200, "zzz": 300, "aaa": 300}
	for slot in stamps:
		var d := base.duplicate(true)
		d["slot"] = slot
		d["saved_at"] = stamps[slot]
		d["summary"] = "sum " + slot
		_write(_slot_path(slot), JSON.stringify(d))
	_write(_slot_path("garbage"), "{oops")
	_write(_slot_path("nov"), "{\"saved_at\": 999}")
	_write(_slot_path("arr"), "[]")
	_write(_dir + "/leftover.json.tmp", JSON.stringify(base))
	_write(_dir + "/readme.txt", "hi")
	rv = s.rev
	var list := s.list_saves()
	var errs: Array = []
	ApiSchema.check(list, ApiSchema.LIST_SAVES, "list_saves", errs)
	t.ok(errs.is_empty() and s.rev == rv, "list_saves matches its schema and does not bump rev %s" % str(errs))
	t.ok(list.map(func(e): return e["slot"]) == ["aaa", "new", "zzz", "mid", "old"], "newest first, ties by slot, corrupt and .tmp omitted: %s" % str(list.map(func(e): return e["slot"])))
	t.ok(list[0]["saved_at"] == 300 and list[0]["summary"] == "sum aaa" and list[4]["saved_at"] == 100, "saved_at and summary come from the file")
	var empty := GameState.new(TestUtil.configs())
	empty.save_dir = _dir + "/nothing-here"
	t.ok(empty.list_saves() == [], "a missing directory lists nothing")


# --------------------------------------------------------------- determinism ----
func _script(s: GameState) -> void:
	s.cmd_debug_grant({"gold": 50.0, "husks": 1, "remnants": 2, "big_undead": 2, "relics": 2, "essence": 10})
	s.cmd_set_valve(2.0, 1.0, 1.0)
	s.cmd_move_relish("old-sluice")
	s.cmd_debug_skip_time(20.0)
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var bus: Array = s.view_big_undead()["big_undead"]
	s.cmd_set_party([bus[0]["uid"]])
	var b := s.cmd_begin_dungeon("old-sluice")
	s.apply_result("raid", _raid_result(b["seed"], {"warden_beaten": true, "retreated": false, "killed_living_mass": 10.0,
		"loot": {"relics": 1, "blueprints": ["embalmer"], "husks": [{"kind": "lich"}], "remnants": [], "essence": 3}}))
	s.cmd_move_relish("covington")
	s.cmd_debug_skip_time(15.0)


func _determinism() -> void:
	var a := _mk(11)
	var b := _mk(11)
	_script(a)
	_script(b)
	var da := a.to_dict()
	t.ok(da == b.to_dict() and JSON.stringify(da) == JSON.stringify(b.to_dict()), "the same seed and command log give identical to_dict()")
	var c := _mk(12)
	_script(c)
	t.ok(c.to_dict() != da, "another seed gives another save")
	t.ok(da["seed"] == "11" and da["t"] > 30.0, "the seed is recorded; time has passed")
	# saving does not disturb the run of the sim
	var d := _mk(11)
	_script(d)
	d.cmd_save("det")
	d.tick(10.0)
	a.tick(10.0)
	t.ok(a.to_dict()["t"] == d.to_dict()["t"] and a.to_dict()["realm"] == d.to_dict()["realm"], "a save changes nothing about what the sim does next")
	# a loaded copy plays on exactly like the original (the field is the one allowed drift, A6)
	var e := GameState.new(TestUtil.configs())
	e.save_dir = _dir
	e.cmd_load("det")
	e.tick(10.0)
	var de := e.to_dict()
	var dd := d.to_dict()
	var why: Array = []
	_diff(dd["realm"], de["realm"], 1e-9, "realm", why)
	t.ok(why.is_empty() and absf(dd["t"] - de["t"]) < 1e-9, "a loaded copy's realm ticks on like the original %s" % str(why))


# --------------------------------------------------------- the T1.4 gaps (8) ----
func _gaps() -> void:
	var s := _mk(3)
	s.cmd_debug_grant({"big_undead": 1})
	var res := _flip(s, "old-sluice")
	t.ok(res["_applied"], "a flipping raid applied")
	res.erase("_applied")
	var run_id: int = res["run_id"]
	# a dungeon sink: a raid that loses raised mass
	s.cmd_debug_set_state({"relish_at": "ashgate", "forts": {"ashgate": {"dead": 50.0, "undead": 0.0}}})
	var b2 := s.cmd_begin_dungeon("ashgate")
	s.apply_result("raid", _raid_result(b2["seed"], {"killed_living_mass": 0.0, "raised": [{"score": 50, "count": 3, "mass": 12.0}], "garrison_mass": 0.0, "chaff_mass": 0.0}))
	var sink := float(s.ledger()["sinks"]["dungeon"])
	t.ok(sink > 0.0, "the raid wrote a dungeon sink (%f)" % sink)
	var d := s.to_dict()
	t.ok(d["applied_runs"] == [run_id, int(b2["run_id"])] and d["ledger"]["sinks"]["dungeon"] == sink, "applied_runs and the dungeon sink are saved")
	var os_: Dictionary = {}
	for f in d["realm"]["forts"]:
		if f["id"] == "old-sluice":
			os_ = f
	t.ok(os_["held_s"] > 0.0 and os_["flipped_count"] == 1 and os_["clears_since_retaken"] == 1, "held_s, flipped_count and clears_since_retaken are saved")
	t.ok(d["cleared_forts"].has("old-sluice") and d["first_dungeon"] == "", "the cleared forts and the first dungeon are saved")
	var n := GameState.new(TestUtil.configs())
	n.save_dir = _dir
	n.debug_enabled = true
	n.from_dict(JSON.parse_string(JSON.stringify(d)))
	t.ok(n.applied_runs == [run_id, int(b2["run_id"])] and n.ledger()["sinks"]["dungeon"] == sink, "applied_runs and the sink come back")
	var vf := n.view_fort("old-sluice")
	t.ok(vf["flipped_count"] == 1 and vf["clears_since_retaken"] == 1 and not vf["first_clear"] and not vf["first_dungeon"], "the fort's counters and its first-clear flags come back")
	t.ok(n.apply_result("raid", res)["reason"] == "duplicate_run", "a run applied before the save is still a duplicate afterwards")
	n.cmd_debug_set_state({"relish_at": "greywall"})
	var b3 := n.cmd_begin_dungeon("greywall")
	t.ok(b3["ok"] and b3["seed"]["fort"]["first_clear"] and n.next_run_id > int(b2["run_id"]), "a new fort is still a first clear; run ids carry on")
	# E2/E3 placeholders ride along
	var p := _rich()
	var dp := p.to_dict()
	t.ok(dp["realm"]["tithe"] == p._tithe and dp["backups"]["phylactery_charges"] == 1 and dp["readout"]["diff_ema"] == -0.25
		and dp["stances"]["hold"] == {"harvest": 12.5}, "placeholders are saved")
	var q := GameState.new(TestUtil.configs())
	q.from_dict(JSON.parse_string(JSON.stringify(dp)))
	t.ok(q.to_dict() == dp, "and come back")
	t.ok(q.autosave_s() == 30.0, "economy.json sim.autosave_s is 30")
	t.ok(q.view_big_undead()["cap"] == 4, "economy.json big_undead.cap is 4")
	# the realm block carries ids, masses and counters
	t.ok(dp["realm"]["forts"].size() == 12 and dp["realm"]["forts"][0]["id"] == "ashgate", "forts are an array with ids, in world order")
	t.ok(not JSON.stringify(dp["realm"]).contains("pos"), "positions are rebuilt from config, never saved")


# ------------------------------------------------------------------ fixtures ----
func _load_fixture(name: String) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.save_dir = _dir
	var r := s.cmd_debug_load_fixture(name)
	t.ok(r == {"ok": true, "reason": ""}, "fixture %s loads: %s" % [name, str(r)])
	return s


func _fixtures() -> void:
	for name in GameState.FIXTURES:
		var text := FileAccess.get_file_as_string("res://tests/fixtures/%s.json" % name)
		var file: Variant = JSON.parse_string(text)
		t.ok(file is Dictionary and file["v"] == GameState.SAVE_VERSION, "%s.json is a save at the current v" % name)
		var s := _load_fixture(name)
		t.ok(JSON.stringify(s.to_dict(), "\t") + "\n" == text, "%s: load then to_dict gives the file back (placeholders survive)" % name)
		t.ok(s.rev > 0 and s.drain_events().is_empty() and s.run.is_empty(), "%s: events cleared, no run" % name)
	var day1 := _load_fixture("day1")
	var fresh := _mk(1)
	fresh.saved_unix = 1794556800  # the fixtures carry a fixed stamp
	t.ok(day1.to_dict() == fresh.to_dict() and day1.t == 0.0, "day1 is cmd_new_game(1) at t = 0")
	t.ok(day1.res["gold"] == 30.0 and day1.res["materials"] == 12.0 and day1.idle_undead == 6, "day1 keeps the legacy start stocks at E1")
	var m := _load_fixture("midgame_2flips")
	t.ok(m.t > 3300.0 and m.t < 3900.0 and m.town_tier == "village", "midgame: about 1 h in, village tier (t=%f)" % m.t)
	var held := 0
	for id in ["old-sluice", "ashgate"]:
		var f := m.realm.fort_by_id(id)
		if float(f.get("held_s", 0.0)) > 0.0 and int(f.get("flipped_count", 0)) == 1:
			held += 1
	t.ok(held == 2, "midgame: Old Sluice and Ashgate are flipped and held")
	t.ok(m._tithe.has("warning") and m._tithe["warning"]["fort_id"] == "ashgate", "midgame: a tithe warning on Ashgate")
	var vr := m.view_relish()
	t.ok(vr["state"] == "travelling" and vr["at"] == "covington" and vr["target"] == "greywall", "midgame: Relish travels Covington -> Greywall")
	t.ok(m.husks.size() == 2 and m.remnants.size() == 4 and m.big_undead.size() == 3 and m.blueprints == ["embalmer"], "midgame: 2 husks, 4 remnants, 3 big undead, embalmer")
	var places: Array = m.big_undead.map(func(b): return b["place"])
	places.sort()
	t.ok(places == ["crypt", "fort:ashgate", "town:lot-04"], "midgame: crypt, foreman and siege: %s" % str(places))
	t.ok(m.town["forge_level"] == 1 and m.relics == 3 and m.essence == 14, "midgame: forge 1, relics 3, essence 14")
	t.ok(m.gather["phase"] == "out" and m.view_town()["haul"]["convoys"].size() == 1, "midgame: a haul convoy in flight")
	var v := _load_fixture("pre_vei")
	t.ok(v.t > 10000.0 and v.town_tier == "city" and not v.won, "pre_vei: about 3 h in, city, not won (t=%f)" % v.t)
	t.near(v.view_vei()["odds"], 0.6, 0.005, "pre_vei: odds about 0.6")
	t.ok(v.party_uids.size() == 4 and v.big_undead.all(func(b): return b["front"] != "" and b["place"] == "party"), "pre_vei: a party of 4, each on a front")
	t.ok(v._phylactery_charges == 1 and v.view_backups()["clones_ready"] == 1, "pre_vei: 1 phylactery charge, 1 clone ready")
	t.ok(v.view_vei()["can_begin"] and v.view_relish()["state"] == "at_vei", "pre_vei: Relish at Vei, cmd_begin_boss would succeed")
	t.ok(v.cmd_begin_boss()["ok"], "pre_vei: cmd_begin_boss succeeds")
	# the reasons of cmd_debug_load_fixture
	var s := _mk()
	s.debug_enabled = false
	t.ok(s.cmd_debug_load_fixture("day1") == {"ok": false, "reason": "not_debug"}, "fixtures need debug")
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("nope") == {"ok": false, "reason": "unknown_fixture"}, "an unknown fixture name")
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	s.cmd_begin_dungeon("old-sluice")
	var rv := s.rev
	t.ok(s.cmd_debug_load_fixture("day1") == {"ok": false, "reason": "busy"} and s.rev == rv, "busy during a run")
	s.cmd_abort_dungeon()
	DirAccess.make_dir_recursive_absolute(_dir + "/fx")
	s.fixture_dir = _dir + "/fx"
	t.ok(s.cmd_debug_load_fixture("day1") == {"ok": false, "reason": "bad_fixture"}, "a missing fixture file is bad_fixture")
	_write(_dir + "/fx/day1.json", "{broken")
	t.ok(s.cmd_debug_load_fixture("day1") == {"ok": false, "reason": "bad_fixture"}, "an unparseable one too")
	_write(_dir + "/fx/day1.json", JSON.stringify({"v": 1}))
	t.ok(s.cmd_debug_load_fixture("day1") == {"ok": false, "reason": "bad_fixture"}, "and a corrupt one")
	_write(_dir + "/fx/day1.json", JSON.stringify({"v": 99}))
	t.ok(s.cmd_debug_load_fixture("day1") == {"ok": false, "reason": "bad_fixture"}, "and a future one")


# ------------------------------------------------------------------- migrate ----
func _migrate() -> void:
	var s := _rich()
	var d := s.to_dict()
	var m := GameState.migrate(d)
	t.ok(m == d and not is_same(m, d), "migrate at SAVE_VERSION is the identity (a copy)")
	m["relish"]["at"] = "x"
	t.ok(d["relish"]["at"] != "x", "the copy is deep")
	var up := d.duplicate(true)
	up["v"] = 1.0
	t.ok(GameState.migrate(up) == d and typeof(GameState.migrate(up)["v"]) == TYPE_INT, "a float v is restored to an int")
	for bad in [0, -1, GameState.SAVE_VERSION + 1, 1.5, "1", null]:
		var x := d.duplicate(true)
		x["v"] = bad
		t.ok(GameState.migrate(x) == {}, "migrate fails with {} for v=%s" % str(bad))
	var nov := d.duplicate(true)
	nov.erase("v")
	t.ok(GameState.migrate(nov) == {}, "migrate fails with {} without v")
