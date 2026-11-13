extends Control
## The town view (left of the dock): Covington as a neon street circuit (VISUAL-LANGUAGE §2b).
## TownModel turns the shell's views into lots, buildings, streets and walls; this draws them in
## layers, bottom to top:
##   DriftFloor   the ground's slow current along the streets toward the crypt plaza (law 1);
##   beds         faint street beds (static);
##   lots         one lot node per lot (static: redraws only on change, pulsed via `self_modulate`
##                above 1 from Pulse.wave at the lot's street distance from the slab, law 5; never
##                below 1, so a core line never drops under its 3:1 contrast; within Relish's light
##                it is lifted by 1 + her brighten, TownAgents.lot_brighten);
##   flow         per frame: street flows (the agents' live streams) and the slab's rings (TownFlow);
##   agents       per frame: undead workers, the living, trade arcs, carts, foremen, Relish
##                (TownAgents steps them, town_agents_layer.gd draws them);
##   walls        tier walls and the tier-up set piece (TownWalls);
##   overlay      labels: the crypt always, any other building on hover.
## Contract: bind(views) on each fetch, on_game_event(ev) from the shell, signal command_issued.

signal command_issued

const LotScript := preload("res://scripts/town/town_lot.gd")
const FlowScript := preload("res://scripts/town/town_flow.gd")
const WallsScript := preload("res://scripts/town/town_walls.gd")
const AgentsScript := preload("res://scripts/town/town_agents_layer.gd")

var model: TownModel
var agents: TownAgents
var views := {}

var _v: Dictionary = {}
var _floor: DriftFloor
var _beds: Node2D
var _lot_layer: Node2D
var _lots: Array = []  # a LotScript node per model lot, same order
var _flow: FlowScript
var _agents: AgentsScript
var _walls: WallsScript
var _overlay: Node2D
var _laid := Vector2.ZERO
var _hover := ""
var _pulse_gain := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	var db: Dictionary = ConfigDb.data
	_v = (db.get("town", {}) as Dictionary).get("view", {})
	_pulse_gain = float(_v.get("lot_pulse_gain", 0.0))
	model = TownModel.new(db.get("town", {}), db.get("buildings_view", {}), db.get("buildings", {}), db.get("economy", {}))
	agents = TownAgents.new(_v, db.get("buildings", {}), db.get("economy", {}), Pulse.tempo_ms / 1000.0)
	_beds = _layer("Beds", _draw_beds)
	_lot_layer = _layer("Lots")
	_flow = FlowScript.new()
	_flow.name = "Flow"
	_flow.model = model
	_flow.vcfg = _v
	_flow.agents = agents
	add_child(_flow)
	_agents = AgentsScript.new()
	_agents.name = "Agents"
	_agents.model = model
	_agents.vcfg = _v
	_agents.agents = agents
	add_child(_agents)
	_walls = WallsScript.new()
	_walls.name = "Walls"
	_walls.model = model
	_walls.vcfg = _v
	add_child(_walls)
	_overlay = _layer("Labels", _draw_labels)
	_refresh()


func _layer(n: String, painter := Callable()) -> Node2D:
	var l := Node2D.new()
	l.name = n
	if painter.is_valid():
		l.draw.connect(painter)
	add_child(l)
	return l


func bind(v: Dictionary) -> void:
	views = v
	_refresh()


func on_game_event(ev: Dictionary) -> void:
	if String(ev.get("type", "")) == "tier_up" and _walls != null:
		_walls.tier_up(String(ev.get("tier", "")))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_refresh()
		NOTIFICATION_MOUSE_EXIT:
			_set_hover("")


func _gui_input(event: InputEvent) -> void:
	var m := event as InputEventMouse
	if m != null:
		_set_hover(_building_at(m.position))


## Rebuild the display state; lots redraw only where their entry changed. Nothing happens until
## the view has a size (the first bind arrives before layout).
func _refresh() -> void:
	if model == null or size.x < 1.0 or size.y < 1.0:
		return
	var relayout := size != _laid
	model.update(views, Rect2(Vector2.ZERO, size))
	agents.sync(model, views)
	if relayout:
		_laid = size
		while _lots.size() < model.lots.size():
			var n: LotScript = LotScript.new()
			n.model = model
			n.vcfg = _v
			_lot_layer.add_child(n)
			_lots.append(n)
		_beds.queue_redraw()
	for i in model.lots.size():
		_lots[i].set_lot(model.lots[i], relayout)
		_lots[i].set_brighten(agents.lot_brighten[i] if i < agents.lot_brighten.size() else 0.0)
	_flow.slab_rect = _crypt_rect()
	if relayout:
		_build_floor()
	elif _floor != null and _flow.slab_rect.size.x > 0.0 and _floor.source != _flow.slab_rect.get_center():
		_floor.set_source(_flow.slab_rect.get_center())  # the crypt arrived after the first layout
	_walls.sync_model(relayout)
	_overlay.queue_redraw()


func _process(delta: float) -> void:
	if model == null or _lots.is_empty():
		return
	agents.step(delta, Pulse.phase(), Pulse.reduced_motion)
	_agents.queue_redraw()
	for n in _lots:
		# Relish's light lifts the lot by her brighten. Keep view.relish_brighten small: modulate above 1
		# clips the matter colours' saturated channels (a big lift turns living orange amber).
		var k: float = (1.0 + _pulse_gain * Pulse.wave(n.hops, model.depth)) * (1.0 + n.brighten)
		n.self_modulate = Color(k, k, k)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ground"))


## The crypt's footprint; the slab sits at its centre (the town's tempo and the floor's exhale
## source). An empty rect if the town has no crypt.
func _crypt_rect() -> Rect2:
	for l in model.lots:
		if String(l["building"].get("building_id", "")) == "crypt":
			return l["building"]["rect"]
	return Rect2()


func _build_floor() -> void:
	if _floor != null:
		remove_child(_floor)
		_floor.queue_free()
	_floor = DriftFloor.new()
	_floor.name = "Floor"
	add_child(_floor)
	move_child(_floor, 0)
	var crypt := _crypt_rect()
	_floor.setup(Rect2(Vector2.ZERO, size), model.drift_at, crypt.get_center() if crypt.size.x > 0.0 else size * 0.5,
		String(_v.get("floor_tint", "")))


# ------------------------------------------------------------------ beds ----
func _draw_beds() -> void:
	var bed: Dictionary = _v.get("bed", {})
	var line: Dictionary = _v.get("bed_line", {})
	var bc := Palette.c(String(bed.get("key", "graticule")), float(bed.get("alpha", 1.0)))
	var lc := Palette.c(String(line.get("key", "contour")), float(line.get("alpha", 1.0)))
	var bw := float(bed.get("width_px", 1.0)) * model.scale
	var lw := float(line.get("width_px", 1.0))
	for s in model.streets:
		_beds.draw_line(s["from"], s["to"], bc, bw)
	for id in model.nodes:
		_beds.draw_circle(model.nodes[id], bw * 0.5, bc)
	for s in model.streets:
		_beds.draw_line(s["from"], s["to"], lc, lw)
	var jr := float(_v.get("junction_px", 0.0))
	if jr > 0.0:
		for id in model.nodes:
			_beds.draw_circle(model.nodes[id], jr, lc)


# ---------------------------------------------------------------- labels ----
func _building_at(p: Vector2) -> String:
	for l in model.lots:
		if not l["building"].is_empty() and (l["rect"] as Rect2).has_point(p):
			return String(l["id"])
	return ""


func _set_hover(id: String) -> void:
	if id != _hover:
		_hover = id
		if _overlay != null:
			_overlay.queue_redraw()


func _draw_labels() -> void:
	for l in model.lots:
		var b: Dictionary = l["building"]
		if b.is_empty():
			continue
		var hovered: bool = l["id"] == _hover
		if hovered or String(b["building_id"]) == "crypt":
			_label(l["rect"], String(b["label"]), "text" if hovered else "text_dim")


## `text` centred above `r` on a ground plate so lines behind it never cut through the letters.
func _label(r: Rect2, text: String, key: String) -> void:
	var font := ThemeDB.fallback_font
	var fs := maxi(int(_v.get("label_px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base := Vector2(r.get_center().x - sz.x * 0.5, r.position.y - font.get_descent(fs) - 2.0)
	var plate := Rect2(base - Vector2(4, font.get_ascent(fs) + 1), Vector2(sz.x + 8, sz.y + 2))
	_overlay.draw_rect(plate, Palette.c("ground"))
	_overlay.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c(key))
