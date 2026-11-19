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
	# Phase I P3's odds split: readout() carries readiness (falls back to odds) and backups (-1 when unknown)
	var ro0 := m.readout()
	var hud0 := m.hud.duplicate()
	if not hud0.has("readiness"):
		t.ok(ro0["readiness"] == ro0["odds"] and ro0["backups"] == -1, "no readiness/backups in view_hud: readiness is the odds, backups -1")
	m.hud["readiness"] = 0.62
	m.hud["odds"] = 0.05
	m.hud["backups"] = 3
	var ro1 := m.readout()
	t.ok(ro1["readiness"] == 0.62 and ro1["odds"] == 0.05 and ro1["backups"] == 3, "present: readiness and backups are carried, odds stays the shown one")
	m.hud.erase("readiness")
	m.hud.erase("backups")
	t.ok(m.readout()["readiness"] == 0.05 and m.readout()["backups"] == -1, "absent again: readiness falls back to odds")
	m.hud = hud0

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
	t.ok(st["mill"] == {"starved": "pits_first", "lever": "raise_war"} and st["queue_stall"].is_empty(), "the mill row is read; a starved second row is not the head")
	var town2 := {"buildings": [], "queue": [{"building_id": "well", "starved": "pits_first", "lever": "raise_war", "affordable_in_s": -1.0}]}
	t.ok(MapModel.stall_from(town2)["queue_stall"]["building_id"] == "well", "a starved head (queue[0]) is read")
	var living := {"buildings": [], "queue": [{"building_id": "inn", "starved": "living_first", "lever": "raise_living", "affordable_in_s": -1.0}]}
	t.ok(not HudLogic.pits_stalled(MapModel.stall_from(living)["mill"], MapModel.stall_from(living)["queue_stall"]), "a living_first head is not a bone stall")
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
	_slab_names(t)
	_won_forts(t)
	return t.failures


## A big undead that still carries the mint default ("Big u1") shows its slab name on the map: through
## `unit_names` (CryptLogic.display_names with town.json slab, set by world_map as slab_cfg). With an empty
## slab_cfg the model falls back to the view's own name, the mint default.
## The V-I3 round, ruling 2: the model stamps view_hud.won on each fort (NodeLogic.name_tag and CardLogic.fort_state
## word it), and the raid tags stay on a won game because a raid really starts there: on a won pre_vei, Relish walks to
## each fort in the model's raid set and cmd_begin_dungeon opens its run.
func _won_forts(t: TestUtil) -> void:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("pre_vei")
	var m := MapModel.new(s)
	m.refresh(true)
	t.ok(m.forts.all(func(f): return f.has("won") and not bool(f["won"])), "a live game: every fort reads won false")
	s.cmd_debug_set_state({"won": true})
	m.refresh(true)
	t.ok(bool(m.hud["won"]) and m.forts.all(func(f): return bool(f["won"])) and bool(m.fort(str(m.forts[0]["id"]))["won"]), "won: every fort reads won true")
	var tagged: Array = m.forts.filter(func(f): return m.raid_why(str(f["id"])) != "")
	t.ok(not tagged.is_empty(), "(setup) a won pre_vei still tags forts to raid: %s" % str(tagged.map(func(f): return f["id"])))
	var opened: Array = []
	for f in tagged:
		var g := GameState.new(TestUtil.configs())
		g.debug_enabled = true
		g.cmd_debug_load_fixture("pre_vei")
		g.cmd_debug_set_state({"won": true, "relish_at": str(f["id"])})
		var b := g.cmd_begin_dungeon(str(f["id"]))
		if bool(b["ok"]) and g.won and not (b["seed"] as Dictionary).is_empty():
			opened.append(f["id"])
	t.ok(opened.size() == tagged.size(), "a raid really starts at every fort the won map tags 'raid': %s of %s" % [str(opened), str(tagged.map(func(f): return f["id"]))])
	# the closing round: the card's retreat line at each of those forts, through MapModel's stamp and fort_card
	var lines := {}
	for f in tagged:
		lines[_retreat_block(m, str(f["id"]))] = true
	t.ok(lines.keys() == ["Retreat at any exit: keep all you found; the fort isn't yours."],
		"won: every fort the map tags 'raid' says it isn't yours, not that it stays Vei's: %s" % str(lines.keys()))
	s.cmd_debug_set_state({"won": false})
	m.refresh(true)
	t.ok(_retreat_block(m, str(tagged[0]["id"])) == "Retreat at any exit: keep all you found; the fort stays Vei's.", "the same fort on a live game: it stays Vei's")


## The fort card's retreat line for fort `id` as the map builds it (CardBlocksLogic.fort_card on the model's fort).
func _retreat_block(m: MapModel, id: String) -> String:
	var card := CardBlocksLogic.fort_card(m.fort(id), "", {}, m.names, TestUtil.load_json("res://configs/loot.json"), {"party": []},
		TestUtil.load_json("res://configs/raid.json"), TestUtil.load_json("res://configs/economy.json"), 0.0)
	for b in card["blocks"]:
		if str(b.get("id", "")) == "retreat":
			return str(b["text"])
	return ""


func _slab_names(t: TestUtil) -> void:
	t.suite("map_model-slab-names")
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	t.ok(s.cmd_debug_load_fixture("midgame_2flips")["ok"], "fixture loads")
	s.cmd_debug_grant({"big_undead": 1})
	var bigs: Array = s.view_big_undead()["big_undead"]
	t.ok(not bigs.is_empty(), "a big undead exists")
	var b: Dictionary = bigs[bigs.size() - 1]
	var uid := str(b["uid"])
	var slab: Dictionary = TestUtil.configs()["town"]["slab"]
	t.ok(str(b["name"]) == str(slab["default_name_prefix"]) + uid and str(b["kind"]) != "", "it carries the mint default name %s and a kind (%s)" % [b["name"], b["kind"]])
	var want := SlabLogic.display_name(b, slab)
	t.ok(want != "" and want != str(b["name"]), "the slab names it differently from the default: %s" % want)
	var m := MapModel.new(s)
	m.slab_cfg = slab
	m.refresh(true)
	t.ok(m.unit_names.get(uid, "") == want, "slab_cfg set: unit_names[%s] is the slab name %s (got %s)" % [uid, want, m.unit_names.get(uid, "")])
	t.ok(m.unit_names == CryptLogic.display_names(bigs, slab), "and the whole map is CryptLogic.display_names'")
	var plain := MapModel.new(s)
	plain.refresh(true)
	t.ok(plain.slab_cfg.is_empty() and plain.unit_names.get(uid, "") == str(b["name"]), "empty slab_cfg: unit_names falls back to the view's plain name (%s)" % b["name"])
	# a name the player chose is kept even with the slab on
	s.big_undead[s.big_undead.size() - 1]["name"] = "Gravel"
	var kept := MapModel.new(s)
	kept.slab_cfg = slab
	kept.refresh(true)
	t.ok(kept.unit_names.get(uid, "") == "Gravel", "a renamed big undead keeps its own name under slab_cfg")


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
	# the catalog is read only for a NEW build: a queue of upgrades, or one under construction, needs none
	var cs := CountingState.new(TestUtil.configs())
	var cm := MapModel.new(cs)
	cm.read_projections({"queue": [{"upgrade": true, "lot_id": "lot-05", "building_id": "house"}], "buildings": []}, true)
	cm.read_projections({"queue": [], "buildings": [{"state": "constructing", "level": 1, "lot_id": "lot-05", "building_id": "house"}]}, true)
	t.ok(cs.catalog_reads == 0, "an upgrade queued or under construction reads no catalog (%d reads)" % cs.catalog_reads)
	cm.read_projections({"queue": [{"lot_id": "lot-08", "building_id": "house"}], "buildings": []}, true)
	t.ok(cs.catalog_reads == 1, "a new build queued reads it once (%d reads)" % cs.catalog_reads)
	MapModel.reset_statics()


## A GameState that counts view_catalog() calls.
class CountingState extends GameState:
	var catalog_reads := 0

	func view_catalog() -> Dictionary:
		catalog_reads += 1
		return super.view_catalog()


func _lane_ok(l: Dictionary) -> bool:
	return l.size() == LANE_KEYS.size() and LANE_KEYS.all(func(k): return l.has(k)) \
		and l["rate"] is float and l["bias"] is float and GameState.LANE_KINDS.has(l["kind"])
