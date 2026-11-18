extends RefCounted
## GameState persistence (STATE-API 9, 4.1 save/load, 4.6 fixtures): the JSON round trip, in-place
## loads, forfeited runs, corrupt and future files, atomic writes, list_saves, determinism, the
## three fixtures and the T1.4 gaps (applied_runs, the dungeon sink, hold and clear counters).
## Headless, no autoloads. Saves go under user://test_saves_<pid>, removed at the end.

var t: TestUtil
var _dir := "user://test_saves_%d" % OS.get_process_id()
## The wall clock pinned for the save-then-load round trips (GameState.clock_override, E2b-2 T3.3b): every
## cmd_load catches up the time since its save, so an unpinned clock gives these 0 or 1 s away, depending on
## timing. Pinned, each is a 0 s load (the identity).
const PINNED := 1_800_000_000


## The shipped configs with town.projection_rows_per_call lifted, so a view refreshes all its build-benefit
## rows in one call: the round trip compares a live state's views with a loaded one's, and under the spread
## refresh (T3.2) the live state would have refreshed more rows than the fresh load.
func _cfgs() -> Dictionary:
	var c := TestUtil.configs()
	c["economy"]["town"]["projection_rows_per_call"] = 1000
	return c


func _mk(seed_val := 1) -> GameState:
	var s := GameState.new(_cfgs())
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


## A state with something in every block: TownSim's stocks, buildings (an extra one, a staff cap, a
## construction whose building_started is still pending), settings, big undead and a party with
## fronts, a flipped fort, village owners, a convoy, Relish on the road, and the E2/E3 placeholders.
func _rich(seed_val := 1) -> GameState:
	var s := _mk(seed_val)
	s.cmd_debug_grant({"gold": 120.5, "bone": 40.25, "bodies": 30.0, "husks": 2, "remnants": 3,
		"big_undead": 3, "backlog": 5000.5})
	s.cmd_set_valve(3.0, 2.0, 1.0)
	s.cmd_set_stance("harvest", true)
	s.cmd_set_job_priority(["haul", "build", "pit", "stall", "mill", "forge", "tend"])
	s.cmd_set_staff_cap("lot-03", 2)
	s.clones_ready = 2
	s.cmd_staff_vat(1, true)
	s.town_sim.place_building("lot-05", "house", 1)
	s.cmd_set_haul_target("ashgate")
	var bus: Array = s.view_big_undead()["big_undead"]
	s.cmd_place_big_undead(bus[2]["uid"], "town:lot-04")
	s.cmd_set_party([bus[0]["uid"], bus[1]["uid"]])
	s.cmd_assign_front(bus[0]["uid"], "giants")
	s.cmd_rename_big_undead(bus[1]["uid"], "Old Gristle")
	s.tick(30.0)
	_flip(s, "old-sluice")
	# the flip started the tithe cycle; a warning on Ashgate rides along in the realm block
	s.realm.tithe["warning"] = {"wave_id": 1, "fort_id": "ashgate", "eta_s": 150.5, "surge": 24.0}
	s.realm.tithe["next_s"] = 150.5
	s.realm.tithe["next_id"] = 2
	s._phylactery_charges = 1
	s.cmd_move_relish("vei")
	s.tick(1.0)
	s.town_sim.start_construction("lot-06", "well", 1)  # its building_started is pending until a step
	s._readout = {"diff_ema": -0.25, "q_raise_ema": 1.5}  # after the last tick, which moves diff_ema
	s._stance_hold = {"harvest": 12.5}  # after the last tick too: E3-1's holds run down each step
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


## Every view but the live field and the seeds, `rev` stripped, village dominance dropped (A6), and
## the session-only values (STATE-API §9.1) dropped: the last substep's split, mint rate and raw
## diff, view_rates' mint, work, war, flood, corpses and backlog, the lanes out of Covington's session rates (FLOOD and
## WAR fallen through to Vei, WORK), and the lane callouts (a lane shown only for its callout goes too).
func _views(s: GameState) -> Dictionary:
	var out := {}
	for name in ApiSchema.VIEWS:
		# view_projection is the readouts at another valve off the session-only split (STATE-API §5.17)
		if name == "view_field" or name == "view_dungeon_seed" or name == "view_boss_seed" or name == "view_projection":
			continue
		if name == "view_fort":
			for f in s.realm.forts:
				out["view_fort:" + f["id"]] = s.view_fort(f["id"])
		elif name == "view_staffing_projection":
			out[name] = s.view_staffing_projection(s.town_sim.ladder)
		else:
			out[name] = s.call(name)
	for k in out:
		out[k].erase("rev")
	for v in out["view_villages"]["villages"]:
		v.erase("dominance")
	out["view_hud"].erase("split")
	out["view_hud"]["rates"][0].erase("rate")
	out["view_vei"].erase("diff")
	for id in ["mint", "work", "war", "flood", "corpses", "backlog"]:
		out["view_rates"]["rates"].erase(id)
	# the build benefit's backlog reads the WAR's fall-through at the last dispatch (RealmSim.war_at),
	# which is session-only, as view_projection's split is (STATE-API §5.10, §5.17)
	for b in out["view_catalog"]["buildings"]:
		(b["projected"] as Dictionary).erase("backlog")
	for b in out["view_town"]["buildings"]:
		(b["upgrade_projected"] as Dictionary).erase("backlog")
	var lanes: Array = []
	for l in out["view_lanes"]["lanes"]:
		if l["rate"] > 0.0 and not (l["from"] == "covington" and (l["to"] == "vei" or l["to"] == "covington")):
			l.erase("why")
			lanes.append(l)
	out["view_lanes"]["lanes"] = lanes
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
	_level_cut()
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
	var b := GameState.new(_cfgs())
	b.save_dir = _dir
	var r := b.from_dict(parsed)
	t.ok(r == {"ok": true, "reason": ""}, "from_dict into a second state is ok: %s" % str(r))
	var db := b.to_dict()
	var why: Array = []
	_diff(d, db, 0.0, "d", why)
	t.ok(db == d, "to_dict after the JSON round trip is equal, types included %s" % str(why))
	t.ok(JSON.stringify(db) == text, "and so is its JSON text")
	var c := GameState.new(_cfgs())
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
	t.ok(d["seed"] is String and d["rng"] is String and d["v"] == 2 and d["api_version"] == GameState.API_VERSION, "seed and rng are strings; v and api_version")
	t.ok(not d.has("legacy") and d["town"]["pending"].size() == 1 and d["town"]["work_pending"] == 0.0
		and d["town"]["haul"]["target"] == "ashgate" and d["backups"]["clones_ready"] == 2, "v2: no legacy block; the town block holds TownSim, its pending event, the WORK in flight (0 from E2b) and the haul target")
	var built: Array = b.view_town()["buildings"].map(func(x): return [x["lot_id"], x["state"], x["staff_cap"]])
	t.ok(built.has(["lot-03", "active", 2]) and built.has(["lot-06", "constructing", -1]) and built.size() == 6,
		"the loaded town: its buildings, a staff cap and the construction (%s)" % str(built))
	b.tick(0.5)
	t.ok(b.drain_events().any(func(e): return e["type"] == "building_started" and e["lot_id"] == "lot-06" and e["upgrade"] == false),
		"the pending building_started comes out of the loaded state's first substep, with upgrade")
	# the generator state survives: the same next number from a loaded copy
	var fresh := _rich()
	var e := GameState.new(_cfgs())
	e.from_dict(JSON.parse_string(JSON.stringify(fresh.to_dict())))
	t.ok(e.rng.randi() == fresh.rng.randi(), "a loaded state draws the same random numbers")


# ----------------------------------------------- identity, counters, session ----
func _in_place_and_ints() -> void:
	var s := _rich()
	var id := s.get_instance_id()
	s.clock_override = PINNED
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
	t.ok(r == {"ok": true, "reason": "", "away_s": 0.0, "capped": false}, "cmd_load ok, nothing to catch up: %s" % str(r))
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
			["essence", d["inventory"]["essence"]], ["forge level", d["town"]["forge"]["level"]],
			["clones", d["backups"]["clones_ready"]], ["raids", d["stats"]["raids"]],
			["staff cap", d["town"]["buildings"][2]["staff_cap"]], ["level", d["town"]["buildings"][0]["level"]],
			["build level", d["town"]["buildings"][0]["build_level"]],
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
	o.clock_override = PINNED
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
	var p := GameState.new(_cfgs())
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
	var q2 := GameState.new(_cfgs())
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
	t.ok(s.run.size() == 6 and not s.run["held"] and s.relish["state"] == "in_dungeon", "a raid is open (its fort wasn't held: v6's `held`)")
	var d := s.to_dict()
	t.ok(d["relish"]["state"] == "at_fort" and d["relish"]["at"] == "old-sluice" and d["relish"]["target"] == "", "the open raid is saved as at_fort at its fort")
	t.ok(JSON.stringify(d).find("in_dungeon") == -1, "in_dungeon never reaches the file")
	t.ok(d["party"].size() == 2, "the party is intact in the file")
	t.ok(s.relish["state"] == "in_dungeon" and not s.run.is_empty(), "the live state is untouched by saving")
	var rv := s.rev
	s.clock_override = PINNED
	var r := s.cmd_save("run")
	t.ok(r["ok"] and s.rev == rv + 1 and s.run["run_id"] == b["run_id"], "cmd_save during a run succeeds and leaves the run alone")
	t.ok(s.cmd_load("run") == {"ok": false, "reason": "busy", "away_s": 0.0, "capped": false}, "cmd_load is busy during a run")
	s.cmd_abort_dungeon()
	var n := GameState.new(_cfgs())
	n.save_dir = _dir
	n.debug_enabled = true
	n.clock_override = PINNED
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
		var f := GameState.new(_cfgs())
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
	broken["town"].erase("workers")
	_write(_slot_path("broken"), JSON.stringify(broken))
	var bstate := s.to_dict()
	bstate["town"]["buildings"][0]["state"] = "melting"
	_write(_slot_path("bstate"), JSON.stringify(bstate))
	var bconvoy := s.to_dict()
	bconvoy["town"]["haul"]["convoys"] = [{"fort": "nowhere", "phase": "out", "t": 0.5, "trip_s": 2.0, "load": 0.0, "crew": 3.0}]
	_write(_slot_path("bconvoy"), JSON.stringify(bconvoy))
	var bmorale := s.to_dict()
	bmorale["town"]["morale"] = "high"
	_write(_slot_path("bmorale"), JSON.stringify(bmorale))
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
	for slot in ["garbage", "array", "string", "nov", "empty", "strv", "broken", "bstate", "bconvoy", "bmorale", "typed", "node",
			"fortset", "partym", "missing"]:
		t.ok(s.cmd_load(slot) == {"ok": false, "reason": "no_save", "away_s": 0.0, "capped": false}, "%s is no_save" % slot)
	for slot in ["future", "zero"]:
		t.ok(s.cmd_load(slot) == {"ok": false, "reason": "bad_version", "away_s": 0.0, "capped": false}, "%s is bad_version" % slot)
	t.ok(s.cmd_load("Bad Slot") == {"ok": false, "reason": "bad_slot", "away_s": 0.0, "capped": false}, "a bad slot name is bad_slot")
	t.ok(s.rev == rv and s.to_dict() == before, "a refused load leaves rev and the state alone")
	var f := GameState.new(_cfgs())
	t.ok(f.from_dict({}) == {"ok": false, "reason": "corrupt"}, "an empty dict is corrupt")
	t.ok(f.from_dict({"v": 1}) == {"ok": false, "reason": "corrupt"}, "v alone is corrupt")
	t.ok(f.from_dict({"v": 99}) == {"ok": false, "reason": "bad_version"}, "v above SAVE_VERSION is bad_version")
	t.ok(f.from_dict({"v": 1.5}) == {"ok": false, "reason": "bad_version"}, "a fractional v is bad_version (the migration fails)")
	t.ok(f.rev == 0, "refused from_dict calls never bump rev")
	var bt := before.duplicate(true)
	bt["realm"]["tithe"]["warning"] = {"wave_id": 1, "fort_id": "nowhere", "eta_s": 1.0, "surge": 1.0}
	t.ok(f.from_dict(bt) == {"ok": false, "reason": "corrupt"}, "a tithe naming an unknown fort is corrupt")
	# town.pending entries and town.rates shapes the later code reads (a crash otherwise)
	var rich := _rich().to_dict()
	t.ok(rich["town"]["pending"].size() == 1 and GameState.new(_cfgs()).from_dict(rich.duplicate(true))["ok"], "the rich save, with a pending event, loads")
	var pend_bad := [[{"level": 1}], [{"type": 3}], [{"type": "building_started", "lot_id": "lot-06", "building_id": "well"}],
		[{"type": "building_started", "lot_id": "lot-06", "building_id": "well", "level": "x"}], [{"type": "tier_up", "level": "x"}]]
	for pb in pend_bad:
		var bp := rich.duplicate(true)
		bp["town"]["pending"] = pb
		t.ok(GameState.new(_cfgs()).from_dict(bp) == {"ok": false, "reason": "corrupt"}, "town.pending %s is corrupt" % str(pb))
	var rates_bad := [{"workers": 3.0}, {"workers": {"in": 1.0}}, {"workers": {"in": "a", "out": 1.0}}, {"bodies": {"out": 1.0}},
		{"gold": []}, {"haul_trip": {}}, {"living": {"in": 1.0, "out": null}}]
	for rb in rates_bad:
		var br := rich.duplicate(true)
		br["town"]["rates"] = rb
		t.ok(GameState.new(_cfgs()).from_dict(br) == {"ok": false, "reason": "corrupt"}, "town.rates %s is corrupt" % str(rb))
	var rok := rich.duplicate(true)
	rok["town"]["rates"] = {}
	t.ok(GameState.new(_cfgs()).from_dict(rok)["ok"], "an empty rates block still loads (TownSim keeps its zeros)")


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
	t.ok(not s.to_dict().has("saved_unix"), "the save dict carries no saved_unix (the file's saved_at is the stamp)")
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
	var kept := s.to_dict()
	s.save_dir = _dir + "/blocker/sub"
	s.cmd_save("slot9")
	t.ok(s.to_dict() == kept, "a failed save leaves to_dict() identical")
	s.drain_events()
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
	var empty := GameState.new(_cfgs())
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
	d.clock_override = PINNED
	d.cmd_save("det")
	d.tick(10.0)
	a.tick(10.0)
	t.ok(a.to_dict()["t"] == d.to_dict()["t"] and a.to_dict()["realm"] == d.to_dict()["realm"], "a save changes nothing about what the sim does next")
	# a loaded copy plays on exactly like the original (the field is the one allowed drift, A6)
	var e := GameState.new(_cfgs())
	e.save_dir = _dir
	e.clock_override = PINNED
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
	t.ok(os_["held"] == true and os_["grace_s"] > 0.0 and os_["zero_s"] == 0.0 and not os_.has("held_s") and os_["flipped_count"] == 1
		and os_["clears_since_retaken"] == 1, "the hold (held, grace_s, zero_s; no held_s), flipped_count and clears_since_retaken are saved")
	t.ok(d["cleared_forts"].has("old-sluice") and d["first_dungeon"] == "", "the cleared forts and the first dungeon are saved")
	var n := GameState.new(_cfgs())
	n.save_dir = _dir
	n.debug_enabled = true
	n.from_dict(JSON.parse_string(JSON.stringify(d)))
	t.ok(n.applied_runs == [run_id, int(b2["run_id"])] and n.ledger()["sinks"]["dungeon"] == sink, "applied_runs and the sink come back")
	var vf := n.view_fort("old-sluice")
	t.ok(vf["flipped_count"] == 1 and vf["clears_since_retaken"] == 1 and not vf["first_clear"] and not vf["first_dungeon"], "the fort's counters and its first-clear flags come back")
	var nf := n.realm.fort_by_id("old-sluice")
	t.ok(nf["held"] and nf["grace_s"] == os_["grace_s"] and nf["zero_s"] == 0.0 and nf["held_s"] == nf["grace_s"], "and its hold, as saved")
	_hold_saves()
	t.ok(n.apply_result("raid", res)["reason"] == "duplicate_run", "a run applied before the save is still a duplicate afterwards")
	n.cmd_debug_set_state({"relish_at": "greywall"})
	var b3 := n.cmd_begin_dungeon("greywall")
	t.ok(b3["ok"] and b3["seed"]["fort"]["first_clear"] and n.next_run_id > int(b2["run_id"]), "a new fort is still a first clear; run ids carry on")
	# E2/E3 placeholders ride along
	var p := _rich()
	var dp := p.to_dict()
	t.ok(dp["realm"]["tithe"] == p.realm.tithe and dp["realm"]["tithe"]["warning"]["fort_id"] == "ashgate"
		and dp["backups"]["phylactery_charges"] == 1 and dp["readout"]["diff_ema"] == -0.25
		and dp["stances"]["hold"] == {"harvest": 12.5}, "the tithe, the readout and the placeholders are saved")
	var q := GameState.new(_cfgs())
	q.from_dict(JSON.parse_string(JSON.stringify(dp)))
	t.ok(q.to_dict() == dp, "and come back")
	t.ok(q.autosave_s() == 30.0, "economy.json sim.autosave_s is 30")
	t.ok(q.view_big_undead()["cap"] == 4, "economy.json big_undead.cap is 4")
	# the realm block carries ids, masses and counters
	t.ok(dp["realm"]["forts"].size() == 12 and dp["realm"]["forts"][0]["id"] == "ashgate", "forts are an array with ids, in world order")
	t.ok(not JSON.stringify(dp["realm"]).contains("pos"), "positions are rebuilt from config, never saved")


# ------------------------------------------------------------------ fixtures ----
func _load_fixture(name: String) -> GameState:
	var s := GameState.new(_cfgs())
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
		# a fixture written before game_id lacks it (a load computes the id from the seed); one written
		# after carries it and the load keeps it. A fixture also keeps the api_version it was written at,
		# and to_dict stamps today's
		var back := s.to_dict()
		var has_id: bool = file.has("game_id")
		if has_id:
			t.ok(back.get("game_id") == file["game_id"], "%s: the load keeps the file's game_id" % name)
		else:
			t.ok(back.get("game_id") == SaveIO.game_id_for(str(file["seed"])), "%s: the id a load computes is its seed's" % name)
			back.erase("game_id")
		# Each migration check below applies to a fixture written before the field (day1, save api_version 3);
		# midgame_2flips and pre_vei were re-saved through the sim at E4 step 3 (today's to_dict: from_dict, the
		# generator's backlog grant, to_dict), so they carry every field and only the round trip at the end judges them.
		# E2b-2 (api_version 6) writes each fort's hold as held, grace_s and zero_s; an older fixture carries
		# held_s, which loads as held with that much grace and the zero clock at 0
		var old_hold: bool = (file["realm"]["forts"][0] as Dictionary).has("held_s")
		var hold_ok := true
		for i in (back["realm"]["forts"] as Array).size():
			if not old_hold:
				break
			var bf: Dictionary = back["realm"]["forts"][i]
			var hs := float(file["realm"]["forts"][i]["held_s"])
			hold_ok = hold_ok and bf["held"] == (hs > 0.0) and bf["grace_s"] == hs and bf["zero_s"] == 0.0
			# and the loot yield (v6): an older fixture has none, so every fort loads at 1
			hold_ok = hold_ok and bf["yield_c"] == 1.0 and bf["yield_t"] == 0.0
			bf["held_s"] = bf["grace_s"]
			for k in ["held", "grace_s", "zero_s", "yield_c", "yield_t"]:
				bf.erase(k)
		t.ok(hold_ok, "%s: %s" % [name, "each fort's held_s loads as held, grace_s = held_s, zero_s 0; its yield at 1" if old_hold
			else "the fixture saves the v6 hold (held, grace_s, zero_s, yield); the round trip judges it"])
		# E2b-2 T3.2 writes the ledger's currency tally (`stores`); an older fixture predates it, so it loads 0
		var no_tally: bool = not (file["ledger"] as Dictionary).has("stores")
		t.ok(not no_tally or back["ledger"]["stores"] == {"gold": {"overflow": 0.0}, "bone": {"overflow": 0.0}},
			"%s: %s" % [name, "the fixture has no currency tally; it loads 0" if no_tally else "the fixture saves its currency tally"])
		if no_tally:
			(back["ledger"] as Dictionary).erase("stores")
		# and the build queue (T3.2): an optional top-level key an older fixture predates; it loads empty
		t.ok(file.has("queue") or back["queue"] == [], "%s: %s" % [name, "the fixture saves its build queue" if file.has("queue")
			else "the fixture has no build queue; it loads empty"])
		if not file.has("queue"):
			back.erase("queue")
		# E3-3 (v8) writes each big undead's filled_slots; an older fixture's big undead lack it, so each loads 1 (the
		# old-save rule)
		var fs_ok := true
		for i in (back["big_undead"] as Array).size():
			if (file["big_undead"][i] as Dictionary).has("filled_slots"):
				continue
			fs_ok = fs_ok and back["big_undead"][i].get("filled_slots") == 1
			(back["big_undead"][i] as Dictionary).erase("filled_slots")
		t.ok(fs_ok, "%s: each of its %d big undead without filled_slots in the file loads 1" % [name, (back["big_undead"] as Array).size()])
		t.ok(back["api_version"] == GameState.API_VERSION, "%s: to_dict stamps today's api_version" % name)
		if int(file["api_version"]) != int(back["api_version"]):
			back["api_version"] = int(file["api_version"])
		t.ok(JSON.stringify(back, "\t") + "\n" == text, "%s: load then to_dict gives the file back (placeholders survive)" % name)
		t.ok(s.rev > 0 and s.drain_events().is_empty() and s.run.is_empty(), "%s: events cleared, no run" % name)
	var day1 := _load_fixture("day1")
	var fresh := _mk(1)
	# E4's A1 day-1 ruling moved the start valve to 0.25/0.60/0.15; day1 was saved at the one before (0.40/0.45/0.15),
	# and fixtures can't be remade, so it is a new game at that valve
	var dd := day1.to_dict()
	var fd := fresh.to_dict()
	var old := {"work": 0.40, "war": 0.45, "flood": 0.15}
	t.ok(dd["valve"]["current"] == old and dd["valve"]["target"] == old, "day1 keeps its saved start valve 0.40/0.45/0.15: %s" % str(dd["valve"]))
	dd["valve"] = fd["valve"]
	t.ok(dd == fd and day1.t == 0.0, "day1 is cmd_new_game(1) at t = 0, but for its saved valve")
	var d1 := day1.town_sim
	t.ok([d1.gold, d1.bone, d1.bodies, d1.workers, d1.living, d1.living_cap()] == [80.0, 30.0, 40.0, 12.0, 10.0, 16.0]
		and d1.buildings.size() == 4, "day1 is BALANCE §0: 80/30/40, 12 workers, 10 living of 16, the 4 start buildings")
	var m := _load_fixture("midgame_2flips")
	t.ok(m.t > 3300.0 and m.t < 3900.0 and m.town_tier == "village", "midgame: about 1 h in, village tier (t=%f)" % m.t)
	t.ok(m.view_town()["next_tier"]["have"] >= 6 and m.town_sim.buildings.has("lot-05") and m.town_sim.buildings["lot-05"]["building_id"] == "house",
		"midgame: a village's buildings, a house among them")
	var held := 0
	for id in ["old-sluice", "ashgate"]:
		var f := m.realm.fort_by_id(id)
		if RealmSim.in_grace(f) and int(f.get("flipped_count", 0)) == 1:
			held += 1
	t.ok(held == 2, "midgame: Old Sluice and Ashgate are flipped and held, in grace")
	var mw: Dictionary = m.realm.tithe["warning"]
	t.ok(m.realm.tithe["started"] and mw["fort_id"] == "ashgate" and m.view_vei()["tithe"]["target"] == "ashgate"
		and m.view_fort("ashgate")["tithe"]["targeted"], "midgame: a tithe warning on Ashgate")
	var vr := m.view_relish()
	t.ok(vr["state"] == "travelling" and vr["at"] == "covington" and vr["target"] == "greywall", "midgame: Relish travels Covington -> Greywall")
	t.ok(m.husks.size() == 2 and m.remnants.size() == 4 and m.big_undead.size() == 3 and m.blueprints == ["embalmer"], "midgame: 2 husks, 4 remnants, 3 big undead, embalmer")
	var places: Array = m.big_undead.map(func(b): return b["place"])
	places.sort()
	t.ok(places == ["crypt", "fort:ashgate", "town:lot-04"], "midgame: crypt, foreman and siege: %s" % str(places))
	t.ok(m.town_sim.forge["level"] == 1 and m.relics == 3 and m.essence == 14, "midgame: forge 1, relics 3, essence 14")
	t.ok(m.town_sim.haul["convoys"].size() == 1 and m.view_town()["haul"]["convoys"].size() == 1, "midgame: a haul convoy in flight")
	var v := _load_fixture("pre_vei")
	t.ok(v.t > 10000.0 and v.town_tier == "city" and not v.won, "pre_vei: about 3 h in, city, not won (t=%f)" % v.t)
	var vt := v.view_town()
	t.ok(vt["next_tier"]["have"] >= 20 and vt["buildings"].all(func(x): return x["state"] != "unpaid")
		and ["walls", "chapel_of_vats", "reliquary"].all(func(id): return vt["lots"].any(func(l): return l["building_id"] == id)),
		"pre_vei: a city of 20 buildings (Walls, a Chapel of Vats, the Reliquary), none unpaid")
	# (E4 step 9, option B) the fixture was made at odds = strain about 0.6; the win odds read its 3 h age as well
	t.near(v.view_vei()["strain"], 0.6, 0.005, "pre_vei: strain about 0.6")
	t.ok(v.view_vei()["odds"] == v.win_odds(v.t, v.view_vei()["strain"]), "pre_vei: odds %.3f, the win odds at its age" % v.view_vei()["odds"])
	t.ok(v.party_uids.size() == 4 and v.big_undead.all(func(b): return b["front"] != "" and b["place"] == "party"), "pre_vei: a party of 4, each on a front")
	t.ok(v._phylactery_charges == 1 and v.view_backups()["clones_ready"] == 1, "pre_vei: 1 phylactery charge, 1 clone ready")
	t.ok(v.view_backups()["phylactery_charges"] == 1 and v.view_relish()["phylactery_charges"] == 1
		and v.view_inventory()["phylactery_charges"] == 1, "pre_vei: the views show the charge")
	var bs := v.cmd_begin_boss()
	t.ok(bs["seed"]["phylactery_charges"] == 1, "pre_vei: the boss seed carries the charge")
	v.cmd_abort_dungeon()
	v.cmd_debug_set_state({"relish_at": "ashgate"})
	t.ok(v.cmd_begin_dungeon("ashgate")["seed"]["phylactery_charges"] == 1, "pre_vei: the raid seed carries the charge")
	v.cmd_abort_dungeon()
	v.cmd_debug_set_state({"relish_at": "vei"})
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
	up["v"] = float(GameState.SAVE_VERSION)
	t.ok(GameState.migrate(up) == d and typeof(GameState.migrate(up)["v"]) == TYPE_INT, "a float v is restored to an int")
	for bad in [0, -1, GameState.SAVE_VERSION + 1, 1.5, "1", null]:
		var x := d.duplicate(true)
		x["v"] = bad
		t.ok(GameState.migrate(x) == {}, "migrate fails with {} for v=%s" % str(bad))
	var nov := d.duplicate(true)
	nov.erase("v")
	t.ok(GameState.migrate(nov) == {}, "migrate fails with {} without v")


## The level cut rule (STATE-API §9.1, the E4 final review's must-fix): a save holding a building above today's
## max_level loads with it at the top. E4 step 10 (4f8b493) cut the Ossuary Tower to one level, and its levels 2
## and 3 had been buyable. A save with the Ossuary at L3, and one mid-upgrade to L2 (its building_started pending
## and an L3 upgrade queued behind it), each load with the Ossuary at L1 and working, and with every block as the
## L1 save's load gives it: the upgrade cancelled with no refund, its event and the queued upgrade dropped, the
## rest (a well under construction with its own pending event, a queued house upgrade) kept. The lower bounds
## are still corrupt. Revert proof: at 2a9e596 SaveIO._town_problem refused both saves ("building", so corrupt).
func _level_cut() -> void:
	var s := _rich()
	t.ok(s.town_sim.place_building("lot-13", "ossuary_tower", 1) and s.cmd_queue_build("", "lot-05")["ok"],
		"level cut: an L1 Ossuary on lot-13 and a house upgrade queued")
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var ref := GameState.new(_cfgs())
	t.ok(ref.from_dict(d.duplicate(true))["ok"], "level cut: the L1 save loads")
	var want := ref.to_dict()
	var oss := func(v: Dictionary) -> Dictionary:
		for b in v["town"]["buildings"]:
			if b["lot_id"] == "lot-13":
				return b
		return {}
	t.ok(SaveIO.clamp_levels(d["town"], TestUtil.configs()["buildings"]) == d["town"], "level cut: a save within every max_level is unchanged")
	var l3 := d.duplicate(true)
	var b3: Dictionary = oss.call(l3)
	b3.merge({"level": 3, "build_level": 3}, true)
	var up := d.duplicate(true)
	var b2: Dictionary = oss.call(up)
	b2.merge({"state": "constructing", "build_level": 2, "progress": 0.4}, true)
	up["town"]["pending"].append({"type": "building_started", "lot_id": "lot-13", "building_id": "ossuary_tower", "level": 2})
	up["queue"].append({"building_id": "ossuary_tower", "lot_id": "lot-13", "upgrade": true, "waited_on": ""})
	t.ok(up["town"]["pending"].size() == 2 and up["queue"].size() == 2, "level cut: the upgrade save holds both events and both entries")
	for c in [["at L3", l3], ["mid-upgrade to L2", up]]:
		var n := GameState.new(_cfgs())
		var r := n.from_dict(c[1])
		var ob: Dictionary = n.town_sim.buildings.get("lot-13", {})
		t.ok(r["ok"] and ob.get("level") == 1 and ob.get("build_level") == 1 and ob.get("state") == "active" and ob.get("progress") == 1.0,
			"level cut: a save with the Ossuary %s loads (%s), the Ossuary at L1 and working (%s)" % [c[0], str(r), str(ob)])
		var diffs := []
		_diff(want, n.to_dict(), 0.0, "", diffs)
		t.ok(diffs.is_empty(), "level cut: and every other block as the L1 save's load %s" % str(diffs))
	for bad in [["level", -1], ["build_level", 0]]:
		var x := d.duplicate(true)
		var bx: Dictionary = oss.call(x)
		bx[bad[0]] = bad[1]
		t.ok(GameState.new(_cfgs()).from_dict(x) == {"ok": false, "reason": "corrupt"}, "level cut: a %s of %d is still corrupt" % bad)
	# Phase I P2 (Q-d): the sanity cap, save.level_sanity_mult (2) × the highest max_level (8) = 16. At 16 the cut rule
	# clamps; past it (17, the review's 1e9, a build_level of 1e9) the save is corrupt, never loaded silently at the top.
	# Revert proof: with fee92d6's save_io.gd all three load ok with the Ossuary at L1, and those three asserts fail
	t.ok(SaveIO.level_sanity_cap(TestUtil.configs()["buildings"], TestUtil.configs()) == 16.0, "level cut: the sanity cap is 2 × 8 = 16")
	var at16 := d.duplicate(true)
	(oss.call(at16) as Dictionary).merge({"level": 16, "build_level": 16}, true)
	var n16 := GameState.new(_cfgs())
	t.ok(n16.from_dict(at16)["ok"] and int(n16.town_sim.buildings["lot-13"]["level"]) == 1, "level cut: an Ossuary at L16 (the cap) loads, clamped to L1")
	for over in [["level", 17], ["level", 1e9], ["build_level", 1e9]]:
		var x := d.duplicate(true)
		var bx: Dictionary = oss.call(x)
		bx["level"] = over[1] if over[0] == "level" else 1
		bx["build_level"] = over[1]
		t.ok(GameState.new(_cfgs()).from_dict(x) == {"ok": false, "reason": "corrupt"}, "level cut: a %s of %s, past the cap, is corrupt" % [over[0], str(over[1])])


## The hold's save keys (STATE-API §9.1, api_version 6): held, grace_s and zero_s round-trip; an older
## save's held_s loads as held with that much grace; a save with neither loads unheld; a wrong type is
## corrupt.
func _hold_saves() -> void:
	var s := _mk(1)
	s.realm.hold("vespers", 0.0)
	var vf := s.realm.fort_by_id("vespers")
	vf["zero_s"] = 33.25
	s.realm.hold("ashgate", 120.5)
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var n := _mk(2)
	t.ok(n.from_dict(d)["ok"], "a save with contested and in-grace forts loads")
	var nv := n.realm.fort_by_id("vespers")
	var na := n.realm.fort_by_id("ashgate")
	t.ok(nv["held"] and nv["grace_s"] == 0.0 and nv["zero_s"] == 33.25 and RealmSim.is_contested(nv), "a contested fort keeps its zero clock")
	t.ok(na["held"] and na["grace_s"] == 120.5 and na["zero_s"] == 0.0 and RealmSim.in_grace(na), "a fort in grace keeps its grace")
	t.ok(not n.realm.fort_by_id("greywall")["held"], "the rest are not held")
	var old: Dictionary = d.duplicate(true)
	for f in old["realm"]["forts"]:
		var hs := 0.0
		if f["id"] == "ashgate":
			hs = 77.0
		f["held_s"] = hs
		for k in ["held", "grace_s", "zero_s"]:
			f.erase(k)
	var o := _mk(2)
	t.ok(o.from_dict(old)["ok"], "a save from before api_version 6 (held_s only) loads")
	var oa := o.realm.fort_by_id("ashgate")
	t.ok(oa["held"] and oa["grace_s"] == 77.0 and oa["zero_s"] == 0.0 and oa["held_s"] == 77.0, "its held_s > 0 is held with that much grace, the zero clock at 0")
	t.ok(not o.realm.fort_by_id("vespers")["held"], "and held_s 0 is not held")
	var none: Dictionary = old.duplicate(true)
	for f in none["realm"]["forts"]:
		f.erase("held_s")
	var z := _mk(2)
	t.ok(z.from_dict(none)["ok"] and z.view_realm()["held_count"] == 0, "a fort with no hold keys at all loads unheld")
	for bad in [["held", "yes"], ["grace_s", "x"], ["zero_s", true], ["held_s", "1"], ["yield_c", "x"], ["yield_t", false]]:
		var c: Dictionary = d.duplicate(true)
		c["realm"]["forts"][0][bad[0]] = bad[1]
		t.ok(_mk(2).from_dict(c)["reason"] == "corrupt", "a fort's %s of the wrong type is corrupt" % bad[0])
