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
	return t.failures


func _lane_ok(l: Dictionary) -> bool:
	return l.size() == LANE_KEYS.size() and LANE_KEYS.all(func(k): return l.has(k)) \
		and l["rate"] is float and l["bias"] is float and GameState.LANE_KINDS.has(l["kind"])
