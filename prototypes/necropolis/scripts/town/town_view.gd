extends Control
## The town view (left of the dock): Covington as a neon street circuit (VISUAL-LANGUAGE §2b).
## TownModel turns the shell's views into lots, buildings, streets and walls; this draws them in
## layers, bottom to top:
##   DriftFloor   the ground's slow current along the streets toward the crypt plaza (law 1);
##   beds         faint street beds (static);
##   lots         one lot node per lot, drawn by its look (town_lot.gd; static: redraws only on
##                change). Empty lots and the looks the model marks `pulse` (staffed, constructing,
##                the crypt with Relish home) are pulsed via `self_modulate` above 1 from Pulse.wave
##                at the lot's street distance from the slab, law 5; never below 1, so a core line
##                never drops under its 3:1 contrast; the rest hold steady. Within Relish's light a
##                lot is lifted by 1 + her brighten, TownAgents.lot_brighten;
##   flow         per frame: street flows (the agents' live streams), the slab's rings (TownFlow)
##                and, under reduced motion, each street's ring number out from the crypt;
##   agents       per frame: undead workers, the living, trade arcs, carts, foremen, Relish
##                (TownAgents steps them, town_agents_layer.gd draws them);
##   walls        tier walls and the tier-up set piece (TownWalls);
##   overlay      labels: the crypt always, any other building on hover; the count badges under
##                staffable buildings ("12 working · 3 short") and the crypt ("5 idle", and
##                "Relish away: slab idle" while she is away);
##   build layer  hover outline and the hovered building's status tag, the day-1 suggestion, the
##                queue's numbered ghosts, the "construction started" flash (town_build_layer.gd);
##   tags         per frame while awake: the output-change floats and the picked agent's ring and
##                tag (town_tags.gd);
##   card         the lot card (town_card.gd), a Control child kept inside this rect; its inspector
##                form opens with the building's status line.
## Agents: a left click within view.agent_hit_px of an agent picks it (before any lot; not while
## placing a building, when a click is for its lot); a click elsewhere, a right click or Escape
## clears the pick.
## Contract: bind(views) on each fetch, on_game_event(ev) from the shell, signal command_issued.
## Build tab hooks: set_placement(building_id, lots) outlines the valid lots in `select` and dims the
## rest; set_selected_lot(id) dashes the inspected lot; clicks emit lot_clicked(lot_id) (hit boxes
## at least view.hit_min_px wide, "" for open ground) and right_clicked. The Build tab also drives
## set_hover_lots / set_suggestion / set_queue / flash_lot and opens the lot card (open_card / close_card).

signal command_issued
signal lot_clicked(lot_id: String)
signal right_clicked
signal suggestion_dismissed

const LotScript := preload("res://scripts/town/town_lot.gd")
const FlowScript := preload("res://scripts/town/town_flow.gd")
const WallsScript := preload("res://scripts/town/town_walls.gd")
const AgentsScript := preload("res://scripts/town/town_agents_layer.gd")
const BuildLayerScript := preload("res://scripts/town/town_build_layer.gd")
const CardScript := preload("res://scripts/town/town_card.gd")
const TagsScript := preload("res://scripts/town/town_tags.gd")

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
var _pick: Node2D
var _place_id := ""
var _place_lots: Array = []
var _selected := ""
var _build: BuildLayerScript
## The lot card (a child of this view); the Build tab fills it, this view places it.
var card: CardScript
var _card_lot := ""
var _sug := {}  # {building_id, label, lots} from the Build tab
var _queue_raw: Array = []  # BuildSort.ghosts() of the queue
var _tags: TagsScript


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	var db: Dictionary = ConfigDb.data
	_v = (db.get("town", {}) as Dictionary).get("view", {})
	_pulse_gain = float(_v.get("lot_pulse_gain", 0.0))
	model = TownModel.new(db.get("town", {}), db.get("buildings_view", {}), db.get("buildings", {}), db.get("economy", {}))
	agents = TownAgents.new(_v, db.get("buildings", {}), db.get("economy", {}), Pulse.tempo_ms / 1000.0, 1,
		(db.get("town", {}) as Dictionary).get("slab", {}))
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
	_pick = _layer("Pick", _draw_pick)
	_build = BuildLayerScript.new()
	_build.name = "BuildLayer"
	_build.model = model
	_build.vcfg = _v
	add_child(_build)
	_tags = TagsScript.new()
	_tags.name = "Tags"
	_tags.model = model
	_tags.agents = agents
	_tags.vcfg = _v
	add_child(_tags)
	card = CardScript.new()
	card.name = "Card"
	card.setup(_v, db.get("buildings_view", {}), db.get("buildings", {}))
	card.resized.connect(_place_card)
	add_child(card)
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
			if _build != null:
				_build.set_hover("")


func _gui_input(event: InputEvent) -> void:
	var m := event as InputEventMouse
	if m != null:
		_set_hover(_building_at(m.position))
		if model != null:
			var over := model.lot_at(m.position, float(_v.get("hit_min_px", 0.0)))
			_build.set_hover(over if over != "" and bool(model.lot(over)["unlocked"]) else "")
	var b := event as InputEventMouseButton
	if b != null and b.pressed and model != null:
		if b.button_index == MOUSE_BUTTON_LEFT:
			if _build.dismiss_rect().has_point(b.position):
				suggestion_dismissed.emit()
				accept_event()
				return
			# placing a building, a click is for its lot; else an agent within its radius wins
			var a: TownAgents.Agent = null if _place_id != "" else agents.agent_at(b.position, float(_v.get("agent_hit_px", 0.0)))
			_tags.set_pick(a)
			accept_event()
			if a == null:  # an agent hit wins only inside its radius; else the lot (or open ground)
				lot_clicked.emit(model.lot_at(b.position, float(_v.get("hit_min_px", 0.0))))
		elif b.button_index == MOUSE_BUTTON_RIGHT:
			_tags.set_pick(null)
			right_clicked.emit()
			accept_event()


## Escape clears a picked agent first (before the Build tab's Escape closes the card).
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_ESCAPE and _tags != null and _tags.pick != null:
		_tags.set_pick(null)
		get_viewport().set_input_as_handled()


## Placement mode for the Build tab: `lots` (lot ids) are outlined in `select`, every other lot is
## dimmed. An empty `building_id` ends it.
func set_placement(building_id: String, lots: Array) -> void:
	_place_id = building_id
	_place_lots = lots.duplicate() if building_id != "" else []
	_apply_dim()
	if _pick != null:
		_pick.queue_redraw()


## The lot the inspector shows (dashed `select` outline); "" for none.
func set_selected_lot(lot_id: String) -> void:
	_selected = lot_id
	if _pick != null:
		_pick.queue_redraw()


## The lots a hovered catalog row fits, outlined thin in `select` (empty ends it).
func set_hover_lots(lots: Array) -> void:
	if _build != null:
		_build.set_row_lots(lots)


## The Build tab's top buildable row ({} or an empty building id for none): its lot nearest the crypt
## gets the suggestion outline and tag. `sug` = {building_id, label, lots}.
func set_suggestion(sug: Dictionary) -> void:
	_sug = sug
	_apply_suggestion()


func _apply_suggestion() -> void:
	if _build == null or model == null:
		return
	if _sug.is_empty():
		_build.set_suggestion("", "")
		return
	var hops := {}
	for l in model.lots:
		hops[l["id"]] = l["hops"]
	_build.set_suggestion(BuildSort.nearest_lot(_sug.get("lots", []), hops), String(_sug.get("label", "")))


## The stand-in queue as BuildSort.ghosts(): numbered ghosts on their lots.
func set_queue(ghosts: Array) -> void:
	_queue_raw = ghosts
	_apply_queue()


func _apply_queue() -> void:
	if _build != null and model != null:
		_build.set_ghosts(model.ghost_layout(_queue_raw))


## The "construction started" flash on a lot, from the next beat.
func flash_lot(lot_id: String) -> void:
	if _build != null:
		_build.flash(lot_id)


## Shows the (already filled) lot card beside `lot_id`.
func open_card(lot_id: String) -> void:
	_card_lot = lot_id
	_card_status()
	card.open()
	_place_card()


## The card's inspector form opens with the building's status line (the model's, as on hover).
func _card_status() -> void:
	if card == null or model == null or _card_lot == "":
		return
	card.set_status(model.lot(_card_lot).get("building", {}).get("status_parts", []))


func close_card() -> void:
	_card_lot = ""
	card.close()


## Beside the lot (right of it, else left), top-aligned and kept inside this view.
func _place_card() -> void:
	if card == null or _card_lot == "" or model == null:
		return
	var l := model.lot(_card_lot)
	if l.is_empty():
		return
	var cfg: Dictionary = _v.get("card", {})
	var gap := float(cfg.get("gap_px", 12.0))
	var edge := float(cfg.get("edge_px", 8.0))
	var r: Rect2 = l["rect"]
	var cs := card.size
	var x := r.end.x + gap
	if x + cs.x > size.x - edge:
		x = r.position.x - gap - cs.x
	x = clampf(x, edge, maxf(size.x - cs.x - edge, edge))
	var y := clampf(r.position.y, edge, maxf(size.y - cs.y - edge, edge))
	card.position = Vector2(x, y)


func _apply_dim() -> void:
	var dim := float(_v.get("placement_dim", 1.0))
	for i in _lots.size():
		var lit: bool = _place_id == "" or (i < model.lots.size() and String(model.lots[i]["id"]) in _place_lots)
		_lots[i].modulate = Color(1, 1, 1, 1.0 if lit else dim)


## Rebuild the display state; lots redraw only where their entry changed. Nothing happens until
## the view has a size (the first bind arrives before layout).
func _refresh() -> void:
	if model == null or size.x < 1.0 or size.y < 1.0:
		return
	var relayout := size != _laid
	model.update(views, Rect2(Vector2.ZERO, size))
	agents.sync(model, views)
	if not model.floats.is_empty():
		_tags.add_floats(model.floats)
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
	_apply_suggestion()
	_apply_queue()
	var st := {}
	for l in model.lots:
		if not (l["building"] as Dictionary).is_empty():
			st[l["id"]] = l["building"]["status_parts"]
	_build.set_statuses(st)
	_card_status()
	_place_card()
	_overlay.queue_redraw()
	_apply_dim()
	_pick.queue_redraw()


func _process(delta: float) -> void:
	if model == null or _lots.is_empty():
		return
	agents.step(delta, Pulse.phase(), Pulse.reduced_motion)
	_agents.queue_redraw()
	for n in _lots:
		# Relish's light lifts the lot by her brighten. Keep view.relish_brighten small: modulate above 1
		# clips the matter colours' saturated channels (a big lift turns living orange amber). Steady
		# looks (calm, unstaffed, unpaid, the crypt with Relish away) don't pulse.
		var k: float = (1.0 + (_pulse_gain * Pulse.wave(n.hops, model.depth) if n.pulses else 0.0)) * (1.0 + n.brighten)
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
		if hovered or String(b["building_id"]) == TownModel.HEART:
			_label(l["rect"], String(b["label"]), "text" if hovered else "text_dim")
		_badges(b)


## Under the building (below its pip row): the count badge, then the crypt's "Relish away" line.
## Small upright text on a ground plate (like the labels) so street lines and agents behind it
## never cut the letters. A badge with open slots draws in `text`, a full one in `text_dim`.
func _badges(b: Dictionary) -> void:
	var lines: Array = []
	if String(b.get("badge", "")) != "":
		lines.append([String(b["badge"]), "text" if int(b.get("short", 0)) > 0 else "text_dim"])
	if String(b.get("away", "")) != "":
		lines.append([String(b["away"]), "text_dim"])
	if lines.is_empty():
		return
	var bc: Dictionary = _v.get("badge", {})
	var font := ThemeDB.fallback_font
	var fs := maxi(int(bc.get("px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var gap := float(bc.get("gap_px", 2.0))
	var pad := float(bc.get("pad_px", 3.0))
	var r: Rect2 = b["rect"]
	var y := r.end.y + gap
	for ln in lines:
		var sz := font.get_string_size(String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var x := clampf(r.get_center().x - sz.x * 0.5, pad + 2.0, maxf(size.x - sz.x - pad - 2.0, pad + 2.0))
		_overlay.draw_rect(Rect2(x - pad, y, sz.x + pad * 2.0, sz.y), Palette.c("ground"))
		_overlay.draw_string(font, Vector2(x, y + font.get_ascent(fs)), String(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Palette.c(String(ln[1])))
		y += sz.y


## `text` centred above `r` on a ground plate so lines behind it never cut through the letters.
func _label(r: Rect2, text: String, key: String) -> void:
	var font := ThemeDB.fallback_font
	var fs := maxi(int(_v.get("label_px", TownUI.MIN_TEXT)), TownUI.MIN_TEXT)
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base := Vector2(r.get_center().x - sz.x * 0.5, r.position.y - font.get_descent(fs) - 2.0)
	var plate := Rect2(base - Vector2(4, font.get_ascent(fs) + 1), Vector2(sz.x + 8, sz.y + 2))
	_overlay.draw_rect(plate, Palette.c("ground"))
	_overlay.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c(key))


# ----------------------------------------------------------------- picks ----
func _draw_pick() -> void:
	if model == null:
		return
	var sel := Palette.c("select")
	for l in model.lots:
		var r: Rect2 = l["rect"]
		if String(l["id"]) in _place_lots:
			var g := r.grow(3.0)
			var pts := PackedVector2Array([g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y), g.position])
			LineGlow.polyline(_pick, pts, sel, 2.0, 0.6)
		elif String(l["id"]) == _selected:
			var g := r.grow(3.0)
			var c := [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]
			for i in 4:
				_pick.draw_dashed_line(c[i], c[(i + 1) % 4], sel, 2.0, 6.0)
