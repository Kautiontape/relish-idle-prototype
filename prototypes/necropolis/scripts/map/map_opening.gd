class_name MapOpening
extends Control
## The opening (GAMEPLAY 6, the first 30 seconds), run through the objective strip. While the game
## is young (OpeningLogic.active) it pushes the asks through MapHud.set_opening_ask: drag the
## valve, send Relish to the first dungeon, descend into it, then hands the strip back. During the
## first ask it leads the eye from Covington to the valve panel: Covington's valve glyph, a short
## dashed hairline in screen space, the triangle's edge and the strip's plate all pulse on the
## beat (Pulse.wave at Covington's hop 0), with a one-line hint by the panel. All of it goes the
## moment the player drags or snaps the valve (MapValve.committed sets the "valve" flag in MapSeen,
## outside the save). Reduced motion: the line and the hint show static and bright, nothing
## moves. Logic and words: opening_logic.gd; tuning: configs/map_view.json "opening".

var model: MapModel
var hud: MapHud
var valve: MapValve
var nodes: MapNodes
var seen: MapSeen

var _stage := "?"  # never a real stage: forces the first push
var _hint: Label
var _cue := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var oc := OpeningLogic.cfg()
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MapType.style_label(_hint, "text", int(oc["hint_font_px"]))
	_hint.text = str(oc["hint_text"])
	_hint.add_theme_stylebox_override("normal", MapUi.plate_box(float(oc["hint_plate_alpha"]), int(oc["hint_pad_px"])))
	_hint.visible = false
	add_child(_hint)
	valve.committed.connect(_on_committed)


func _on_committed(_v: Dictionary) -> void:
	seen.mark(MapSeen.VALVE)
	refresh()


## The ask now up, from the model's views: pushed to the strip only when it changes (a push
## re-lays the HUD out).
func refresh() -> void:
	var st := OpeningLogic.stage(float(model.hud.get("t", 0.0)), model.forts, model.relish, seen.has(MapSeen.VALVE))
	if st == _stage:
		return
	_stage = st
	var a := OpeningLogic.ask(st, model.forts)
	hud.set_opening_ask(str(a["text"]), str(a["target"]))
	if st == OpeningLogic.NONE:
		_set_cue(0.0)
		valve.set_pointer(0.0)
		_hint.visible = false
		queue_redraw()


func _process(_delta: float) -> void:
	if _stage == OpeningLogic.NONE or _stage == "?":
		return
	var lvl := OpeningLogic.level(Pulse.wave(0.0), Pulse.reduced_motion)
	hud.set_opening_pulse(lvl)
	var shown := OpeningLogic.pointer_shown(_stage, valve.is_dragging())
	valve.set_pointer(lvl if shown else 0.0)
	_set_cue(lvl if shown else 0.0)
	_hint.visible = shown
	if shown:
		_hint.reset_size()
		var r := valve.get_global_rect()
		_hint.position = Vector2(r.position.x, r.position.y - _hint.size.y - float(OpeningLogic.cfg()["hint_gap_px"]))
	queue_redraw()


## Covington's glyph brightens with the pulse; its static layer is redrawn only when the level moved.
func _set_cue(level: float) -> void:
	var same := level == _cue if level == 0.0 else absf(level - _cue) < float(OpeningLogic.cfg()["cue_eps"])
	if same:
		return
	_cue = level
	nodes.ctx.valve_cue = level
	nodes.redraw_covington()


func _draw() -> void:
	if not OpeningLogic.pointer_shown(_stage, valve.is_dragging()):
		return
	var oc := OpeningLogic.cfg()
	var from_c: Vector2 = get_viewport().get_canvas_transform() * model.node_pos(MapModel.COVINGTON)
	var b := valve.pointer_end()
	var dir := (b - from_c).normalized()
	var a := from_c + dir * float(oc["line_start_px"])
	var lvl := OpeningLogic.level(Pulse.wave(0.0), Pulse.reduced_motion)
	var col := Palette.c("relish", float(oc["line_alpha_base"]) + float(oc["line_alpha_wave"]) * lvl)
	var period := float(oc["line_dash_px"]) + float(oc["line_gap_px"])
	var segs := OpeningLogic.dashes(a, b, float(oc["line_dash_px"]), float(oc["line_gap_px"]), Pulse.dash_offset(float(oc["line_speed_px_s"]), period))
	if segs.size() >= 2:
		for l in NodeLogic.capped_layers(col, float(oc["line_width_px"]), float(oc["line_glow"]), float(oc["line_halo_max_px"])):
			draw_multiline(segs, l[1], l[0])
	LineGlow.ring(self, b, float(oc["end_ring_r_px"]), col, float(oc["line_width_px"]), float(oc["line_glow"]))
