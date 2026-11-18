class_name MapOpening
extends Control
## The opening (GAMEPLAY 6, the first 30 seconds), run through the objective strip. While the game
## is young (OpeningLogic.active) it pushes the asks through MapHud.set_opening_ask: drag the
## valve, send Relish to the first dungeon, descend into it, then hands the strip back. During the
## first ask it leads the eye from Covington to the valve panel: Covington's valve glyph, the last
## line_max_px of a solid undead hairline whose chevrons march into the triangle's FLOOD corner (not
## the dashed purple of Relish's route), the triangle's edge and the strip's plate all pulse on the
## beat (Pulse.wave at Covington's hop 0). The strip carries the ask and its reason; clicking it
## during ask 1 flashes the triangle (flash(): full level for one beat). All of it goes the moment
## the player drags or snaps the valve (MapValve.committed sets the "valve" flag in MapSeen, outside
## the save). Reduced motion: the line shows static and bright, its chevrons held still. Logic and words: opening_logic.gd; tuning: configs/map_view.json "opening".

var model: MapModel
var hud: MapHud
var valve: MapValve
var nodes: MapNodes
var seen: MapSeen

var _stage := "?"  # never a real stage: forces the first push
var _cue := -1.0
var _flash_ms := -1.0  # Pulse.now_ms() at the strip click that flashed the triangle (-1: none)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		queue_redraw()


## The strip was clicked during ask 1 (nothing to select): the triangle's opening pulse runs at
## full level for one beat (Pulse's tempo), then goes back to the wave.
func flash() -> void:
	if _stage == OpeningLogic.VALVE:
		_flash_ms = Pulse.now_ms()


## The pulse level now: the beat's wave, or full while a flash holds.
func _level() -> float:
	var since := Pulse.now_ms() - _flash_ms if _flash_ms >= 0.0 else -1.0
	return OpeningLogic.flash_level(since, Pulse.tempo_ms, Pulse.wave(0.0), Pulse.reduced_motion)


func _process(_delta: float) -> void:
	if _stage == OpeningLogic.NONE or _stage == "?":
		return
	var lvl := _level()
	hud.set_opening_pulse(lvl)
	var shown := OpeningLogic.pointer_shown(_stage, valve.is_dragging())
	valve.set_pointer(lvl if shown else 0.0)
	_set_cue(lvl if shown else 0.0)
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
	var seg := OpeningLogic.pointer_segment(from_c, valve.pointer_end(), float(oc["line_start_px"]), float(oc["line_max_px"]))
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	var col := Palette.c("undead", float(oc["line_alpha_base"]) + float(oc["line_alpha_wave"]) * _level())
	var w := float(oc["line_width_px"])
	var halo := float(oc["line_halo_max_px"])
	for l in NodeLogic.capped_layers(col, w, float(oc["line_glow"]), halo):
		draw_line(a, b, l[1], l[0])
	var marks := OpeningLogic.chevrons(a, b, float(oc["chevron_spacing_px"]), float(oc["chevron_half_px"]),
		Pulse.dash_offset(float(oc["line_speed_px_s"]), float(oc["chevron_spacing_px"])))
	if marks.size() >= 4:
		for l in NodeLogic.capped_layers(col, w, float(oc["line_glow"]), halo):
			draw_multiline(marks, l[1], l[0])
	LineGlow.ring(self, b, float(oc["end_ring_r_px"]), col, w, float(oc["line_glow"]))
