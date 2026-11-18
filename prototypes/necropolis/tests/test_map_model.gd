extends RefCounted
## Tests for scripts/map/map_model.gd against a real GameState (no autoloads).

const LANE_KEYS := ["id", "from", "to", "kind", "rate", "bias", "why"]


func run() -> int:
	var t := TestUtil.new()
	t.suite("map_model")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	MapLogic.configure(TestUtil.load_json("res://configs/map_view.json"))
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	var r := s.cmd_debug_load_fixture("midgame_2flips")
	t.ok(r["ok"], "fixture loads (%s)" % r["reason"])
	var m := MapModel.new(s)
	t.ok(m.rev == -1 and m.lanes.is_empty(), "nothing is read before the first refresh")
	t.ok(m.refresh(true), "refresh(true) re-reads")
	t.ok(m.rev == s.rev, "the model carries the state's rev")
	t.ok(not m.realm.is_empty() and not m.relish.is_empty() and not m.vei.is_empty() and not m.hud.is_empty(), "every view is cached")
	t.ok(m.villages.size() == 12 and m.forts.size() == 12 and m.forts_by_id.size() == 12, "12 villages and forts")
	t.ok(m.lanes.size() > 0 and m.lanes.all(func(l): return _lane_ok(l)), "lanes have the lane shape (%d rows)" % m.lanes.size())
	t.ok(m.lanes.any(func(l): return l["kind"] == "living"), "the adapter added living rows")
	t.ok(not m.refresh(), "a second refresh at the same rev reads nothing")
	s.tick(1.0)
	t.ok(s.rev != m.rev, "a tick changes rev")
	t.ok(m.refresh(true), "refresh(true) after a tick re-reads")
	t.ok(m.rev == s.rev, "the cached rev is current")

	var realm := s.view_realm()
	t.ok(m.node_pos("covington") == MapModel.to_vec(realm["covington"]["pos"]) and m.has_node("covington"), "covington position")
	t.ok(m.node_pos("vei") == MapModel.to_vec(realm["vei"]["pos"]) and m.has_node("vei"), "vei position")
	var f0: Dictionary = realm["forts"][0]
	t.ok(m.node_pos(f0["id"]) == MapModel.to_vec(f0["pos"]) and m.has_node(f0["id"]), "a fort's position")
	t.ok(m.fort(f0["id"])["id"] == f0["id"] and m.fort("nowhere").is_empty(), "fort() returns the view entry or {}")
	var v0: Dictionary = m.villages[0]
	t.ok(m.node_pos(v0["id"]) == MapModel.to_vec(v0["pos"]) and m.has_node(v0["id"]), "a village's position")
	t.ok(m.node_pos("nowhere") == Vector2.ZERO and not m.has_node("nowhere"), "unknown ids: ZERO and has_node false")
	t.ok(m.hops_of("covington") == 0.0 and m.hops_of(f0["id"]) == 1.0 and m.hops_of("vei") == 2.0, "hops: 0, 1, 2")
	t.ok(m.world_size() == Vector2(2048, 1440), "world size from the view")
	var targets := m.hit_targets()
	t.ok(targets.size() == 2 + 12 + 12 and targets.all(func(c): return c["radius"] > 0.0), "hit targets cover every node")

	# the pits-first stall: the Bone Mill row's reason and the queue row that reads one
	t.ok(m.mill == {"starved": "", "lever": ""} and m.queue_stall.is_empty(), "a healthy town: no stall read")
	var town := {"buildings": [{"building_id": "house", "starved": ""}, {"building_id": "bone_mill", "starved": "pits_first", "lever": "raise_war"}],
		"queue": [{"building_id": "inn", "starved": "", "affordable_in_s": 40.0}, {"building_id": "well", "starved": "pits_first", "affordable_in_s": -1.0}]}
	var st := MapModel.stall_from(town)
	t.ok(st["mill"] == {"starved": "pits_first", "lever": "raise_war"} and st["queue_stall"]["building_id"] == "well", "the mill row and the starved queue row are read")
	t.ok(MapModel.stall_from({"buildings": [], "queue": []}) == {"mill": {"starved": "", "lever": ""}, "queue_stall": {}}, "no mill and no queue: no stall")

	# the demo flag swaps the lanes for the synthetic set
	var d := MapModel.new(s)
	d.demo = true
	d.refresh(true)
	t.ok(d.lanes.any(func(l): return l["kind"] == "dead") and d.lanes.any(func(l): return l["kind"] == "redirect"), "demo lanes cover the dead and redirect kinds")

	# the refresh throttle: a changed rev inside model_refresh_min_s is held back, then taken
	var th := MapModel.new(s)
	th.refresh(true)
	s.tick(1.0)
	t.ok(not th.refresh(), "a rev change inside model_refresh_min_s is deferred")
	OS.delay_msec(int(float(MapLogic.cfg()["model_refresh_min_s"]) * 1000.0) + 20)
	t.ok(th.refresh(), "and read once the interval has passed")
	_builds(t)
	return t.failures


## A finished build's projection reaches the model before the build finishes (the catalog read on the
## slow cadence while one is pending, on the frame path where the sim refreshes it) and outlives it,
## keyed by lot and level; the level snapshot survives a model swap and a new game clears it.
func _builds(t: TestUtil) -> void:
	t.suite("map_model-builds")
	MapModel.reset_statics()
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var m := MapModel.new(s)
	m.refresh(true)
	t.ok(m.mount_rises.is_empty() and MapModel.snap_set, "the first mount of a game announces nothing and takes the snapshot")
	t.ok(MapModel.proj_store.is_empty() and m.built.has("lot-05"), "nothing pending, nothing read; the built lots are known")
	var q := s.cmd_queue_build("house", "lot-08")
	t.ok(bool(q["ok"]), "a house is queued (%s)" % q["reason"])
	m.refresh(true)
	m.read_projections(s.view_town(), true)  # the first read marks the catalog wanted: its rows come back cold
	var warm := false
	var done := {}
	for f in 6000:
		s.tick(1.0 / 60.0, 8)  # the frame path, where the projection refresh runs
		for ev in s.drain_events():
			if str(ev["type"]) == "building_done" and str(ev["lot_id"]) == "lot-08":
				done = ev
		if f % 240 == 239 and done.is_empty():
			m.refresh(true)
			m.read_projections(s.view_town(), true)
			warm = warm or not SetpieceLogic.projection_for(MapModel.proj_store, "lot-08", "house", 1).is_empty()
		if not done.is_empty():
			break
	t.ok(not done.is_empty(), "the house finishes (building_done lot-08, level %s)" % str(done.get("level", "-")))
	t.ok(warm, "the model read a non-empty projection for lot-08:1 before it finished")
	t.ok(not SetpieceLogic.projection_for(MapModel.proj_store, "lot-08", str(done["building_id"]), int(done["level"])).is_empty(), "and it is still there when building_done arrives, keyed by the event's lot and level")
	m.refresh(true)
	t.ok(m.built.get("lot-08", {}).get("level", 0) == 1 and m.mount_rises.is_empty(), "the refresh sees the new level; the diff is for a mount, not a refresh")
	t.ok(not SetpieceLogic.projection_for(MapModel.proj_store, "lot-08", "house", 1).is_empty(), "the projection survives the level rising")
	var text := SetpieceLogic.build_text([{"lot_id": "lot-08", "building_id": "house", "level": 1}], MapModel.proj_store, {"house": "House"})
	t.ok(text.begins_with("House built"), "the callout reads %s" % text)
	# a build that finished while the map was away is found by the next mount's diff
	var s2 := GameState.new(TestUtil.configs())
	s2.debug_enabled = true
	s2.cmd_debug_load_fixture("midgame_2flips")
	var snap_before := MapModel.level_snap.duplicate(true)
	var back := MapModel.new(s)
	back.refresh(true)
	t.ok(back.mount_rises.is_empty(), "a remount with nothing new announces nothing")
	MapModel.level_snap = snap_before
	MapModel.level_snap.erase("lot-08")
	var back2 := MapModel.new(s)
	back2.refresh(true)
	t.ok(back2.mount_rises == [{"lot_id": "lot-08", "building_id": "house", "level": 1}], "a lot that rose since the last mount is announced by the new model's first refresh")
	var other := MapModel.new(s2)
	other.refresh(true)
	t.ok(MapModel.snap_game == str(other.hud.get("game_id", "")), "the snapshot belongs to the game being read")
	MapModel.reset_statics()


func _lane_ok(l: Dictionary) -> bool:
	return l.size() == LANE_KEYS.size() and LANE_KEYS.all(func(k): return l.has(k)) \
		and l["rate"] is float and l["bias"] is float and GameState.LANE_KINDS.has(l["kind"])
