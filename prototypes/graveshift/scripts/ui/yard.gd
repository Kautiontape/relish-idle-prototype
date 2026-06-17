class_name Yard
extends Control
## The whole prototype: a bird's-eye yard you watch the undead run. Stations are
## blobs; undead are dots that walk between them carrying a speck of cargo; the
## living mill at the inn/market as pure vibe. Drag any undead onto the Quarry or
## Workshop to crew it, drop it on open ground to send it idle. One verb (drag),
## one meter (Supplies), and a front-and-center debug panel — the tuning knobs
## ARE the prototype.
##
## Input is pointer-only (drag), no held keys — desktop trackpad + phone both
## work. GUI delivers MOUSE events to _gui_input (and emulate_mouse_from_touch
## turns phone touches into mouse events too), so we listen for mouse press /
## motion / release — one path that covers desktop and mobile.

const W := 400
const H := 866

var sim: Sim
var rng := RandomNumberGenerator.new()

var dragging: Dictionary = {}    # the worker dict currently under the finger
var show_labels := true

var _font: Font
var dbg_panel: Panel
var dbg_readout: Label
var send_btn: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Transparent to the pointer: drags are caught in _unhandled_input (which runs
	# AFTER the child Buttons/Debug panel consume their own clicks). Full-rect
	# anchors don't resolve against a plain Node parent, so relying on _gui_input
	# here would give the control no hit area.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	rng.randomize()
	sim = Sim.new(rng)
	sim.setup()
	_apply_ui_scale()
	_build_buttons()
	_build_debug()
	ConfigDb.value_changed.connect(_on_config_changed)
	set_process(true)

func _apply_ui_scale() -> void:
	var s := float(ConfigDb.v("stats", "debug_ui_scale"))
	get_window().content_scale_factor = maxf(0.5, s)

func _on_config_changed(_f: String, _k: String, _v: Variant) -> void:
	# Keep the live count of ambient living in sync with its slider.
	pass

func _process(delta: float) -> void:
	sim.tick(delta)
	if dbg_panel.visible:
		_refresh_debug_readout()
	queue_redraw()

# ---------------- drawing ----------------

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(ConfigDb.v("yard", "bg_color")))
	_draw_supplies_bar()
	for s in sim.stations:
		_draw_station(s)
	if sim.living_enabled:
		var lr := float(ConfigDb.v("yard", "living_radius_px"))
		for l in sim.living:
			draw_circle(l["pos"], lr, Color(0.86, 0.6, 0.42, 0.9))
			draw_circle(l["pos"], lr, Color(0.2, 0.12, 0.1, 0.5), false, 1.0)
	for w in sim.workers:
		if not w["dragging"]:
			_draw_worker(w, false)
	if not dragging.is_empty():
		_draw_worker(dragging, true)
	_draw_hint()

func _draw_supplies_bar() -> void:
	var target := maxf(1.0, float(ConfigDb.v("stats", "supplies_target")))
	var frac := clampf(float(sim.supplies) / target, 0.0, 1.0)
	var pad := 10.0
	var bar := Rect2(pad, 12, W - pad * 2, 14)
	draw_rect(bar, Color(0.16, 0.15, 0.2))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(0.78, 0.66, 0.36))
	var txt := "Supplies  %d / %d        %.0f/min" % [sim.supplies, int(target), sim.throughput_per_min()]
	draw_string(_font, Vector2(pad + 2, 23), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.07, 0.07, 0.09))
	draw_string(_font, Vector2(pad + 1, 22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.92, 0.84))

func _draw_station(s: Dictionary) -> void:
	var r := float(ConfigDb.v("yard", "station_radius_px"))
	var pos: Vector2 = s["pos"]
	var col := Color(s["color"])
	var assignable: bool = s["kind"] == "quarry" or s["kind"] == "workshop"
	draw_circle(pos, r, Color(col.r, col.g, col.b, 0.22))
	draw_arc(pos, r, 0, TAU, 40, Color(col.r, col.g, col.b, 0.85), 2.0)
	# Center figure: quarry → bone stock, storehouse → total supplies.
	if s["kind"] == "quarry":
		_text_center(pos, str(int(s["stock"])), 18, Color(0.95, 0.92, 0.84))
	elif s["kind"] == "storehouse":
		_text_center(pos, str(sim.supplies), 18, Color(0.95, 0.92, 0.84))
	# Labels below.
	_text_center(pos + Vector2(0, r + 12), String(s["label"]), 12, Color(0.78, 0.78, 0.84))
	if assignable:
		_text_center(pos + Vector2(0, r + 26), "crew %d" % sim.crew(String(s["id"])), 11, Color(0.62, 0.66, 0.74))

func _draw_worker(w: Dictionary, big: bool) -> void:
	var r := float(ConfigDb.v("yard", "worker_radius_px")) * (1.4 if big else 1.0)
	var pos: Vector2 = w["pos"]
	var col := Color(w["color"])
	draw_circle(pos, r + 1.5, Color(0.06, 0.06, 0.08, 0.9))
	draw_circle(pos, r, col)
	# Carried cargo speck.
	if w["carrying"] == "bone":
		draw_circle(pos + Vector2(0, -r - 3), 3.0, Color(0.85, 0.82, 0.72))
	elif w["carrying"] == "good":
		draw_circle(pos + Vector2(0, -r - 3), 3.0, Color(0.92, 0.76, 0.34))
	# Idle workers show the job they're best at — teaches who goes where.
	if show_labels and String(w["station_id"]) == "" and not big:
		var best := sim.best_station_kind(w)
		var glyph := "Q" if best == "quarry" else "W"
		var gcol := Color(0.6, 0.55, 0.45) if best == "quarry" else Color(0.45, 0.58, 0.72)
		_text_center(pos + Vector2(0, -r - 8), glyph, 11, gcol)
	if big:
		_text_center(pos + Vector2(0, -r - 12), String(w["name"]), 12, Color(0.95, 0.92, 0.84))

func _draw_hint() -> void:
	if sim.crew("quarry") + sim.crew("bench") > 0:
		return
	var msg := "Drag an undead onto the Quarry, then the Workshop, to start the line."
	_text_center(Vector2(W * 0.5, H - 92), msg, 12, Color(0.7, 0.7, 0.78))

func _text_center(center: Vector2, text: String, size: int, color: Color) -> void:
	var wdt := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, center - Vector2(wdt * 0.5, -size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

# ---------------- input: drag to assign ----------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var w := _worker_at(event.position)
			if not w.is_empty():
				dragging = w
				w["dragging"] = true
		elif not dragging.is_empty():
			var st := _station_at(event.position)
			sim.assign(int(dragging["id"]), String(st.get("id", "")))
			dragging["dragging"] = false
			dragging = {}
	elif event is InputEventMouseMotion and not dragging.is_empty():
		dragging["pos"] = event.position
		dragging["target"] = event.position

func _worker_at(pos: Vector2) -> Dictionary:
	var radius := float(ConfigDb.v("yard", "grab_radius_px"))
	var best := {}
	var best_d := radius
	for w in sim.workers:
		var d: float = (w["pos"] as Vector2).distance_to(pos)
		if d <= best_d:
			best_d = d
			best = w
	return best

func _station_at(pos: Vector2) -> Dictionary:
	var radius := float(ConfigDb.v("yard", "station_radius_px")) + 8.0
	for s in sim.stations:
		if (s["pos"] as Vector2).distance_to(pos) <= radius:
			return s
	return {}

# ---------------- overlay controls ----------------

func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(8, H - 44)
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	send_btn = _mk_button("Crypt sends %d" % int(ConfigDb.v("workers", "send_count")), func():
		sim.send_more())
	row.add_child(send_btn)
	row.add_child(_mk_button("Reset", func(): sim.reset()))
	row.add_child(_mk_button("Debug", func(): dbg_panel.visible = not dbg_panel.visible))

func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b

func _build_debug() -> void:
	dbg_panel = Panel.new()
	dbg_panel.position = Vector2(12, 44)
	dbg_panel.size = Vector2(W - 24, H - 110)
	dbg_panel.visible = false
	add_child(dbg_panel)

	var box := VBoxContainer.new()
	box.position = Vector2(12, 10)
	box.size = Vector2(dbg_panel.size.x - 24, dbg_panel.size.y - 20)
	box.add_theme_constant_override("separation", 6)
	dbg_panel.add_child(box)

	box.add_child(_dbg_title("DEBUG · live tunables"))
	box.add_child(_slider_row("Harvest time", "stats", "harvest_time_s", 0.4, 6.0, 0.1))
	box.add_child(_slider_row("Craft time", "stats", "craft_time_s", 0.4, 6.0, 0.1))
	box.add_child(_slider_row("Walk speed", "stats", "base_walk_px", 20, 140, 5))
	box.add_child(_slider_row("Aptitude weight", "stats", "aptitude_strength", 0.0, 0.4, 0.01))
	box.add_child(_living_slider_row())

	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 10)
	var t_living := CheckButton.new()
	t_living.text = "Living"
	t_living.button_pressed = sim.living_enabled
	t_living.toggled.connect(func(on): sim.set_living_enabled(on))
	toggles.add_child(t_living)
	var t_labels := CheckButton.new()
	t_labels.text = "Job hints"
	t_labels.button_pressed = show_labels
	t_labels.toggled.connect(func(on): show_labels = on)
	toggles.add_child(t_labels)
	box.add_child(toggles)

	dbg_readout = Label.new()
	dbg_readout.add_theme_font_size_override("font_size", 13)
	dbg_readout.add_theme_color_override("font_color", Color(0.82, 0.86, 0.78))
	box.add_child(dbg_readout)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.add_child(_mk_button("Reset tunables", func(): ConfigDb.reset_tunables()))
	btns.add_child(_mk_button("Close", func(): dbg_panel.visible = false))
	box.add_child(btns)

func _dbg_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	return l

## A labelled slider bound live to a ConfigDb value.
func _slider_row(label: String, file: String, key: String, lo: float, hi: float, step: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_l := Label.new()
	name_l.text = label
	name_l.custom_minimum_size = Vector2(118, 0)
	name_l.add_theme_font_size_override("font_size", 12)
	row.add_child(name_l)
	var sld := HSlider.new()
	sld.min_value = lo
	sld.max_value = hi
	sld.step = step
	sld.value = float(ConfigDb.v(file, key))
	sld.custom_minimum_size = Vector2(150, 18)
	row.add_child(sld)
	var val_l := Label.new()
	val_l.custom_minimum_size = Vector2(48, 0)
	val_l.add_theme_font_size_override("font_size", 12)
	val_l.text = _fmt(sld.value, step)
	row.add_child(val_l)
	sld.value_changed.connect(func(v):
		ConfigDb.set_v(file, key, v)
		val_l.text = _fmt(v, step))
	return row

## num_living needs to re-seed the ambient crowd when it changes.
func _living_slider_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_l := Label.new()
	name_l.text = "Living count"
	name_l.custom_minimum_size = Vector2(118, 0)
	name_l.add_theme_font_size_override("font_size", 12)
	row.add_child(name_l)
	var sld := HSlider.new()
	sld.min_value = 0
	sld.max_value = 20
	sld.step = 1
	sld.value = float(ConfigDb.v("stats", "num_living"))
	sld.custom_minimum_size = Vector2(150, 18)
	row.add_child(sld)
	var val_l := Label.new()
	val_l.custom_minimum_size = Vector2(48, 0)
	val_l.add_theme_font_size_override("font_size", 12)
	val_l.text = str(int(sld.value))
	row.add_child(val_l)
	sld.value_changed.connect(func(v):
		ConfigDb.set_v("stats", "num_living", v)
		val_l.text = str(int(v))
		sim._set_living_count(int(v)))
	return row

func _fmt(v: float, step: float) -> String:
	return str(int(round(v))) if step >= 1.0 else "%.2f" % v

func _refresh_debug_readout() -> void:
	dbg_readout.text = "quarry crew %d   ·   workshop crew %d   ·   idle %d\nbone stock %d   ·   %.0f supplies/min" % [
		sim.crew("quarry"), sim.crew("bench"), sim.idle_count(),
		int(sim.station_by_id("quarry").get("stock", 0)), sim.throughput_per_min()]
