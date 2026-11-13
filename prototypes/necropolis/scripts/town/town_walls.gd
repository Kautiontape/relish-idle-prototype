extends Node2D
## Covington's tier walls (VISUAL-LANGUAGE §2e: "a tier-up: the walls draw themselves around
## Covington"). Every reached tier's wall ring is drawn, open at the gate. On a tier_up event the
## new ring draws itself from the gate around the town over view.tierup_beats beats with a bright
## leading head, then stays. Reduced motion: it appears whole at once and flashes for one beat.
## Static otherwise: it redraws only on a tier change or while the set piece runs.

var model: TownModel
var vcfg: Dictionary = {}

var _raised := {}  # tier -> true: rings an event raised, kept even before the views report the tier
var _shown: Array = []  # the tiers drawn last time, to redraw only on change
var _anim := ""  # the tier drawing itself, or ""
var _anim_ms := 0.0
var _flash_until := 0.0  # Pulse.now_ms() until which the reduced-motion flash holds
var _head: Node2D  # the leading head, overbright through its modulate (view.tierup_head.gain)


func _ready() -> void:
	set_process(false)
	_head = Node2D.new()
	_head.name = "TierUpHead"
	_head.draw.connect(_draw_head)
	add_child(_head)
	var k := float(vcfg.get("tierup_head", {}).get("gain", 1.0))
	_head.modulate = Color(k, k, k)


## Call after every model.update(): redraws if the set of drawn tiers changed (or `force`).
func sync_model(force := false) -> void:
	var now := _tiers()
	if force or now != _shown:
		_shown = now
		queue_redraw()


## The set piece. `t` is the tier just reached.
func tier_up(t: String) -> void:
	if model == null or model.wall_ring(t).size() < 2:
		return
	_raised[t] = true
	if Pulse.reduced_motion:
		_anim = ""
		_flash_until = Pulse.now_ms() + Pulse.tempo_ms
	else:
		_anim = t
		_anim_ms = Pulse.now_ms()
	_shown = _tiers()
	set_process(true)
	queue_redraw()


func _tiers() -> Array:
	var out: Array = []
	for t in model.tiers:
		if _raised.has(t) or not model.walls(t).is_empty():
			out.append(t)
	return out


func _frac() -> float:
	var dur := float(vcfg.get("tierup_beats", 1.0)) * Pulse.tempo_ms
	return clampf((Pulse.now_ms() - _anim_ms) / dur, 0.0, 1.0) if dur > 0.0 else 1.0


func _process(_delta: float) -> void:
	if _anim != "" and (Pulse.reduced_motion or _frac() >= 1.0):
		_anim = ""
	if _anim == "" and _flash_until > 0.0 and Pulse.now_ms() >= _flash_until:
		_flash_until = 0.0
	if _anim == "" and _flash_until <= 0.0:
		set_process(false)
	queue_redraw()
	_head.queue_redraw()


func _draw() -> void:
	if model == null:
		return
	var ink := Palette.c("town")
	var w := float(vcfg.get("wall_w_px", 1.5))
	var glow := float(vcfg.get("wall_glow", 0.5))
	if _flash_until > 0.0:
		glow = minf(glow + float(vcfg.get("tierup_flash", 0.0)), 1.0)
		w *= 1.0 + float(vcfg.get("tierup_flash", 0.0))
	for t in _shown:
		if t == _anim:
			continue
		LineGlow.polyline(self, model.wall_ring(t), ink, w, glow)
	if _anim == "":
		return
	var pls: Array[PackedVector2Array] = [model.wall_ring(_anim)]
	var part := TownModel.truncate(pls, _frac())
	if part.is_empty():
		return
	LineGlow.polyline(self, part[0], ink, w, glow)


## The leading head of the drawing wall: its last stretch at full glow and double width, and a hot
## point where the line is being laid (overbright through _head's modulate, still Palette `town`).
func _draw_head() -> void:
	if _anim == "":
		return
	var pls: Array[PackedVector2Array] = [model.wall_ring(_anim)]
	var part := TownModel.truncate(pls, _frac())
	if part.is_empty():
		return
	var drawn: PackedVector2Array = part[0]
	var spec: Dictionary = vcfg.get("tierup_head", {})
	var ink := Palette.c("town")
	var w := float(vcfg.get("wall_w_px", 1.5))
	var glow := float(spec.get("glow", 1.0))
	var total := 0.0
	for i in range(1, drawn.size()):
		total += drawn[i - 1].distance_to(drawn[i])
	var head_len := float(spec.get("len_px", 0.0)) * model.scale
	LineGlow.polyline(_head, _tail(drawn, minf(head_len, total)), ink, w * float(spec.get("w_mul", 1.0)), glow)
	var tip := drawn[drawn.size() - 1]
	LineGlow.ring(_head, tip, w * float(spec.get("ring_mul", 1.0)), ink, float(spec.get("ring_w_px", 1.0)), glow)
	_head.draw_circle(tip, w * float(spec.get("dot_mul", 1.0)), ink)


## The last `length` px of polyline `p`.
static func _tail(p: PackedVector2Array, length: float) -> PackedVector2Array:
	var out := PackedVector2Array([p[p.size() - 1]])
	var left := length
	for i in range(p.size() - 1, 0, -1):
		var seg := p[i].distance_to(p[i - 1])
		if seg >= left:
			out.append(p[i].lerp(p[i - 1], left / seg) if seg > 0.0 else p[i - 1])
			break
		out.append(p[i - 1])
		left -= seg
	out.reverse()
	return out
