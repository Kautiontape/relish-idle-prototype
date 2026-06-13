class_name RaidDirector
extends Node2D
## Phase 1 raid (§9): one authored tomb — 5 chambers + climax, doorway-
## connected, generous doorways, fixed camera framing per chamber. Climax v1 =
## KILL the boss. Death = total reset.

signal raid_won
signal raid_lost
signal chamber_changed(index: int, name: String, total: int)
signal boss_engaged(boss: RRUnit)

var battlefield: Battlefield
var trance: TranceController
var command: CommandController
var chambers: Array = []
var layout: Dictionary = {}
var current := 0
var boss: RRUnit = null
var _units_by_chamber: Array = []
var _rooms: Array = []          # per chamber {top, bot, center}
var _fired_waves: Dictionary = {}
var _ended := false
var _cleared_announced := false
var _advancing := false        # slide-to-next-chamber in progress (fire once)
var _door_glows: Array = []     # FxDoorGlow per doorway (red locked / blue open)

func _ready() -> void:
	layout = ConfigDb.tomb_layout()
	chambers = ConfigDb.chambers_sorted()
	_compute_rooms()
	battlefield = Battlefield.new()
	add_child(battlefield)
	battlefield.build_arena(_tomb_outline())
	battlefield.relish_died.connect(_on_relish_died)
	battlefield.enemy_killed.connect(_on_enemy_killed)
	trance = TranceController.new()
	trance.battlefield = battlefield
	add_child(trance)
	command = CommandController.new()
	command.battlefield = battlefield
	add_child(command)
	_populate()
	_register_doorways()
	battlefield.make_camera(_rooms[0]["center"])
	_spawn_squad()
	# Deferred so main can connect chamber_changed/boss_engaged after add_child.
	_activate_chamber.call_deferred(0)

## Corridor centers — the escort system steers idle minions toward whichever
## of these Relish is heading for. Each also gets a door glow (red=locked,
## blue=cleared) the player can read from inside the room.
func _register_doorways() -> void:
	var w := float(layout["room_w"])
	var cw := float(layout["corridor_w"])
	var ch := float(layout["corridor_h"])
	for i in range(0, chambers.size() - 1):
		var cx := clampf(-w / 2.0 + float(chambers[i]["door_x"]) * w, -w / 2.0 + cw / 2.0 + 20.0, w / 2.0 - cw / 2.0 - 20.0)
		var door := Vector2(cx, float(_rooms[i]["top"]) - ch / 2.0)
		battlefield.doorways.append(door)
		var glow := FxDoorGlow.new()
		glow.position = door
		battlefield.fx_root.add_child(glow)
		_door_glows.append(glow)

func handle_input(ev: InputEvent) -> bool:
	if trance.handle_input(ev):
		return true
	return command.handle_input(ev)

# ---- Tomb geometry: chambers stack upward (negative y), joined by corridors ----

func _compute_rooms() -> void:
	var room_h := float(layout["room_h"])
	var stride := room_h + float(layout["corridor_h"])
	for i in chambers.size():
		var bot := -i * stride
		var top := bot - room_h
		_rooms.append({"top": top, "bot": bot, "center": Vector2(0, (top + bot) / 2.0)})

## Single rectilinear union polygon: rooms ∪ corridors. Walls and navmesh both
## come from this outline.
func _tomb_outline() -> PackedVector2Array:
	var w := float(layout["room_w"])
	var cw := float(layout["corridor_w"])
	var n := chambers.size()
	var left := -w / 2.0
	var right := w / 2.0
	var pts := PackedVector2Array()
	# Left boundary, top room downward
	pts.append(Vector2(left, _rooms[n - 1]["top"]))
	for i in range(n - 1, 0, -1):
		var below: int = i - 1
		var cx := clampf(left + float(chambers[below]["door_x"]) * w, left + cw / 2.0 + 20.0, right - cw / 2.0 - 20.0)
		pts.append(Vector2(left, _rooms[i]["bot"]))
		pts.append(Vector2(cx - cw / 2.0, _rooms[i]["bot"]))
		pts.append(Vector2(cx - cw / 2.0, _rooms[below]["top"]))
		pts.append(Vector2(left, _rooms[below]["top"]))
	pts.append(Vector2(left, _rooms[0]["bot"]))
	# Bottom edge, then right boundary upward
	pts.append(Vector2(right, _rooms[0]["bot"]))
	for i in range(0, n - 1):
		var cx2 := clampf(left + float(chambers[i]["door_x"]) * w, left + cw / 2.0 + 20.0, right - cw / 2.0 - 20.0)
		pts.append(Vector2(right, _rooms[i]["top"]))
		pts.append(Vector2(cx2 + cw / 2.0, _rooms[i]["top"]))
		pts.append(Vector2(cx2 + cw / 2.0, _rooms[i + 1]["bot"]))
		pts.append(Vector2(right, _rooms[i + 1]["bot"]))
	pts.append(Vector2(right, _rooms[n - 1]["top"]))
	return pts

func _zone_point(chamber_idx: int, zone: Array) -> Vector2:
	var w := float(layout["room_w"])
	var room: Dictionary = _rooms[chamber_idx]
	var room_h := float(layout["room_h"])
	var m := float(layout["wall_margin"])
	var x := battlefield.rng.randf_range(-w / 2.0 + m + float(zone[0]) * (w - 2 * m), -w / 2.0 + m + float(zone[2]) * (w - 2 * m))
	var y := battlefield.rng.randf_range(float(room["top"]) + m + float(zone[1]) * (room_h - 2 * m), float(room["top"]) + m + float(zone[3]) * (room_h - 2 * m))
	return Vector2(x, y)

# ---- Population ----

func _populate() -> void:
	for i in chambers.size():
		var spawned: Array = []
		for grp in chambers[i]["spawns"]:
			for j in int(grp["count"]):
				var u := EntityFactory.make_enemy(grp["type"])
				u.active = (i == 0)
				battlefield.spawn_unit(u, _zone_point(i, grp["zone"]))
				spawned.append(u)
				if u.is_boss:
					boss = u
		_units_by_chamber.append(spawned)
		for spos in chambers[i].get("sarcophagi", []):
			var s := Sarcophagus.new()
			var w := float(layout["room_w"])
			var room_h := float(layout["room_h"])
			s.position = Vector2(-w / 2.0 + float(spos[0]) * w, float(_rooms[i]["top"]) + float(spos[1]) * room_h)
			battlefield.add_child(s)
			command.interactables.append(s)

func _spawn_squad() -> void:
	var bot := float(_rooms[0]["bot"])
	var rel := EntityFactory.make_relish()
	battlefield.spawn_unit(rel, Vector2(0, bot - 110))
	var squad: Array = EntityFactory.default_loadout()
	for i in squad.size():
		battlefield.spawn_unit(squad[i], Vector2(-130.0 + 65.0 * i, bot - 180))

func _activate_chamber(i: int) -> void:
	current = i
	GameState.current_chamber = i + 1
	_cleared_announced = false
	for u in _units_by_chamber[i]:
		if is_instance_valid(u):
			u.active = true
	for u in battlefield.living(RRUnit.Faction.PLAYER):
		u.reset_chamber_flags()  # Persistence: once per CHAMBER (§11)
	if battlefield.relish != null:
		# The anchor only pulls her through corridors. Once she's inside the
		# chamber it releases — otherwise she'd wander to the room center
		# after every fight or finished command.
		battlefield.relish.relish_anchor = Vector2.INF
	chamber_changed.emit(i, chambers[i]["name"], chambers.size())
	if chambers[i].get("climax", false) and boss != null:
		boss_engaged.emit(boss)

## Slide to the next chamber. Hard-order idle minions through the door so the
## camera doesn't strand them, slide the camera, activate the next chamber, and
## when the slide ends snap any unit still off-screen to a ring behind Relish
## (an off-screen teleport — invisible, but the horde never gets left behind).
func _begin_advance(i: int) -> void:
	_advancing = true
	var through := float(ConfigDb.v("stats", "escort_through_px"))
	var goal: Vector2 = battlefield.doorways[i] + Vector2(0, -through)
	var idx := 0
	for u in battlefield.living(RRUnit.Faction.PLAYER):
		if u.kind == RRUnit.Kind.RELISH:
			continue
		if u.cmd == RRUnit.Cmd.NONE:
			u.order_move(goal + Vector2(30.0 * (idx % 5 - 2), 16.0 * (idx / 5)))
			idx += 1
	var tw := create_tween()
	tw.tween_property(battlefield.camera, "position", _rooms[i + 1]["center"], 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(_gather_stragglers)
	_activate_chamber(i + 1)

func _gather_stragglers() -> void:
	_advancing = false
	var rel: RRUnit = battlefield.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive:
		return
	var rect := _camera_world_rect()
	var idx := 0
	for u in battlefield.living(RRUnit.Faction.PLAYER):
		if u.kind == RRUnit.Kind.RELISH or rect.has_point(u.global_position):
			continue
		# Behind her, toward the door she came from (+y is back/down), in a ring.
		var ring := float(ConfigDb.v("stats", "follow_relish_distance_px"))
		var spot := rel.global_position + Vector2(0, ring * 0.6) \
			+ Vector2(ring * 0.5, 0).rotated(TAU * float(idx) / 8.0)
		u.snap_to(battlefield.clamp_to_nav(spot))
		idx += 1

func _camera_world_rect() -> Rect2:
	var cam := battlefield.camera
	var vp := battlefield.get_viewport_rect().size
	var half := Vector2(vp.x / (2.0 * cam.zoom.x), vp.y / (2.0 * cam.zoom.y))
	return Rect2(cam.position - half, half * 2.0)

func _chamber_cleared(i: int) -> bool:
	for u in _units_by_chamber[i]:
		if is_instance_valid(u) and u.alive:
			return false
	return true

func _process(_delta: float) -> void:
	if _ended:
		return
	# Boss waves
	if boss != null and is_instance_valid(boss) and boss.alive and boss.active:
		var frac: float = boss.hp / boss.max_hp
		var climax := chambers.size() - 1
		for w in chambers[climax].get("waves", []):
			var key: float = w["at_hp_frac"]
			if frac <= float(key) and not _fired_waves.has(key):
				_fired_waves[key] = true
				for grp in w["spawns"]:
					for j in int(grp["count"]):
						var u := EntityFactory.make_enemy(grp["type"])
						battlefield.spawn_unit(u, _zone_point(climax, grp["zone"]))
						_units_by_chamber[climax].append(u)
				battlefield.spawn_ding(boss.global_position + Vector2(0, -60), "THE TOMB ANSWERS", Color(1, 0.5, 0.4))
	# Auto-advance (§8.3). The exit unlocks when the chamber clears; Relish only
	# has to reach the doorway ZONE (not fully cross into the next room) to start
	# the slide — that dead-air crossing was giving the horde time to act goofy.
	if current < chambers.size() - 1 and _chamber_cleared(current) and not _advancing:
		if not _cleared_announced:
			_cleared_announced = true
			battlefield.spawn_ding(_rooms[current]["center"], "CHAMBER CLEAR", Color(0.6, 1.0, 0.7))
			if current < _door_glows.size():
				_door_glows[current].set_open(true)  # red → blue, "come on in"
			if battlefield.relish != null:
				battlefield.relish.relish_anchor = _rooms[current + 1]["center"]
		var rel: RRUnit = battlefield.relish
		if rel != null and rel.alive \
				and rel.global_position.distance_to(battlefield.doorways[current]) < float(ConfigDb.v("stats", "exit_zone_px")):
			_begin_advance(current)

func _on_enemy_killed(u: RRUnit) -> void:
	if u.is_boss and not _ended:
		_ended = true
		await get_tree().create_timer(2.5).timeout  # let the shower ding
		raid_won.emit()

func _on_relish_died() -> void:
	if _ended:
		return
	_ended = true
	Engine.time_scale = 1.0
	await get_tree().create_timer(1.5).timeout
	raid_lost.emit()
