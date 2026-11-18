class_name RaidVei
extends Node2D
## Vei in her final test (MECHANICS 6, VISUAL-LANGUAGE 2c): the largest glyph on the field, cream
## and gold rings at her court. She has no hp and is not a target: she breaks when Relish's raise
## rate holds above her ferry rate (vei_boss.gd, VeiFronts). The palette has no gold key, so the
## gold is `vei` at full weight on alternate rings with a `text` core, the cream `vei` at a lighter
## weight between them.
##
## Her weaves hunt Relish on the tempo (phase 2): `weave_step(beat)` each physics frame. A weave is
## laid tell_beats ahead as a `danger` thread from her across where Relish stands (the tell, on a
## z 37 child above the trance dim; `boss.danger_targeted()` while Relish is on it) and lands on the
## beat: Relish on the thread takes `weaves.dmg` (relish.take_hit, through the sacrifice chain). The
## first weave is a set piece: a longer tell, the thread drawing itself out from her, a flare and a
## banner (boss.on_first_weave). On victory her rings unravel stroke by stroke (`unravel_f`); on a
## loss she brightens as the lanes drain into her (`feed_f`). Numbers: vei.json court, weaves.

var boss: Node2D = null
var radius := 72.0
var rings := 4
var strokes := 8
var alive := true            # she is never killed; kept for duck-typed readers
var unravel_f := -1.0        # >= 0: 0..1 of her strokes gone (the victory set piece)
var feed_f := -1.0           # >= 0: 0..1 of the lanes drained into her (a loss)

# weaves
var weaves_on := false
var next_beat := 0.0         # the beat the next weave lands on
var tell_on := false
var tell_from := Vector2.ZERO   # world points of the laid thread
var tell_to := Vector2.ZERO
var tell_start := 0.0        # beat the tell was laid
var tell_len := 1.0          # this tell's length in beats
var first_done := false      # the first weave has landed
var hold_tell := false       # DEV (--boss-hold-tell): the first tell holds and never lands
var weaves := 0              # weaves landed
var hits := 0                # weaves that caught Relish
var cur_beat := 0.0

var _t := 0.0
var _flare := 0.0
var _land_t := -1.0          # >= 0: seconds into the landing flash
var _land_a := Vector2.ZERO
var _land_b := Vector2.ZERO
var _land_hit := false
var _tg: Telegraph = null
var _meter: MeterRow = null


func wcfg() -> Dictionary:
	return ConfigDb.data.get("vei", {}).get("weaves", {})


func configure(p_boss: Node2D, cfg: Dictionary) -> void:
	boss = p_boss
	var c: Dictionary = cfg.get("court", {})
	radius = float(c.get("radius_px", 72.0))
	rings = maxi(1, int(c.get("rings", 4)))
	strokes = maxi(1, int(c.get("strokes", 8)))
	z_index = 34
	_tg = Telegraph.new()
	_tg.vei = self
	_tg.z_as_relative = false
	_tg.z_index = 37   # above the trance dim (36), under Relish (38)
	add_child(_tg)
	_meter = MeterRow.new()
	_meter.vei = self
	add_child(_meter)


## Phase 2 begins: the first weave lands on `first_beat`.
func start_weaves(first_beat: float) -> void:
	weaves_on = true
	next_beat = first_beat


func stop_weaves() -> void:
	weaves_on = false
	tell_on = false


func flare() -> void:
	_flare = 1.0


func _relish_ok() -> bool:
	var r = boss.relish
	return r != null and is_instance_valid(r) and r.alive


func _reach() -> float:
	return float(wcfg().get("width_px", 64.0)) * 0.5 + (boss.relish.radius if _relish_ok() else 0.0)


## Per physics frame in phase 2 (scene time: it slows with the trance), `beat` on the boss's clock.
func weave_step(beat: float) -> void:
	cur_beat = beat
	if not weaves_on or not _relish_ok():
		return
	var w := wcfg()
	var tb := WardenLogic.attack_tell(w, "first_tell_beats" if not first_done else "tell_beats")
	if not tell_on and beat >= next_beat - tb:
		_lay(beat, tb)
	if not tell_on:
		return
	if BossLogic.weave_hits(tell_from, tell_to, boss.relish.global_position, _reach()):
		boss.danger_targeted()
	if beat >= next_beat and not (hold_tell and not first_done):
		_land(w)


func _lay(beat: float, tb: float) -> void:
	tell_on = true
	tell_start = beat
	tell_len = tb
	tell_from = global_position
	var lay: Dictionary = boss.layout
	tell_to = BossLogic.ray_to_bounds(global_position, boss.relish.global_position, lay["size"], float(lay["wall_t"]))
	if not first_done:
		_flare = 1.0
		boss.on_first_weave()


func _land(w: Dictionary) -> void:
	tell_on = false
	weaves += 1
	_land_a = tell_from
	_land_b = tell_to
	_land_t = 0.0
	_land_hit = _relish_ok() and BossLogic.weave_hits(tell_from, tell_to, boss.relish.global_position, _reach())
	next_beat += float(w.get("period_beats", 4.0))
	first_done = true
	_flare = maxf(_flare, 0.5)
	if _land_hit:
		hits += 1
		boss.relish.take_hit(float(w.get("dmg", 12.0)))


func _process(delta: float) -> void:
	var real := delta / maxf(0.05, Engine.time_scale)
	_t += delta
	_flare = maxf(0.0, _flare - real * 1.4)
	if _land_t >= 0.0:
		_land_t += real
		if _land_t >= float(wcfg().get("flash_s", 0.35)):
			_land_t = -1.0
	queue_redraw()


# ------------------------------------------------------------------- draw ---
## Ring i (0 innermost) radius.
func ring_r(i: int) -> float:
	return radius * (0.42 + 0.58 * float(i + 1) / float(rings))


func _draw() -> void:
	var t0 := BossDev.pt()
	_draw_vei()
	BossDev.pa("vei", t0)


func _draw_vei() -> void:
	var reduced: bool = Pulse.reduced_motion
	var vei := Palette.c("vei")
	var core := Palette.c("text")
	var total := rings * strokes
	var gone := 0
	if unravel_f >= 0.0:
		gone = clampi(floori(total * unravel_f + 0.0001), 0, total)
	var beat: float = boss.beat_wave() if boss != null else Pulse.wave()   # on the boss's beat
	var bright := 1.0 + 0.25 * _flare
	if feed_f >= 0.0:
		bright += 0.4 * feed_f
	if gone < total:
		LineGlow.ring(self, Vector2.ZERO, radius * 1.7, Palette.c("vei", clampf(0.35 * bright, 0.0, 1.0)), 1.5, 0.4)
	# rings from the outside in; strokes leave outermost ring first, one by one
	var k := 0
	for ri in range(rings - 1, -1, -1):
		var r := ring_r(ri) * (1.0 + 0.03 * beat)
		var gold := (rings - 1 - ri) % 2 == 0
		var span := TAU / strokes
		var gap := span * 0.16
		var dirn := 1.0 if ri % 2 == 0 else -1.0
		var spin := 0.0 if reduced else _t * 0.12 * dirn
		for si in strokes:
			if k < gone:
				k += 1
				continue
			k += 1
			var a0 := span * si + spin + gap * 0.5
			var col := vei if gold else Palette.c("vei", 0.62)
			col.a = clampf(col.a * bright, 0.0, 1.0)
			# gold rings glow; the cream rings between them are single bright strokes (no halo stack)
			LineGlow.arc(self, Vector2.ZERO, r, a0, a0 + span - gap, col, 3.0 if gold else 2.0, 0.6 if gold else 0.0,
				core if gold else col)
	if gone < total:
		draw_circle(Vector2.ZERO, radius * 0.2, Palette.c("vei", clampf(0.9 * bright, 0.0, 1.0)))
		draw_circle(Vector2.ZERO, radius * 0.09, Palette.c("text", 0.95))
	if _flare > 0.0 and not reduced:
		LineGlow.ring(self, Vector2.ZERO, radius * (1.2 + 0.8 * (1.0 - _flare)), Palette.c("vei", 0.7 * _flare), 2.5, 0.6)


## The break meter's echo under her rings, as the wardens' row (warden.gd _draw_meter_row): break_beats
## pips lit by the streak, a notch every notch_every pips, a lapse's pips a slashed `danger` ring while
## it shows. Sized in screen px (divided by the zoom). No text: the HUD carries the counts. A child
## of Vei so it redraws only when its inputs change (her rings spin, so her own _draw runs every
## frame): the key holds every number _draw reads, compared as ints each frame.
class MeterRow:
	extends Node2D
	var vei: RaidVei = null
	var _key := PackedInt32Array()
	var _next := PackedInt32Array()

	func _process(_d: float) -> void:
		var boss = vei.boss if vei != null else null
		if boss == null:
			return
		var vc: Dictionary = boss.vcfg()
		var mc: Dictionary = vc.get("meter", {})
		_next.resize(11)
		_next[10] = 1 if _shown(boss, vc) else 0
		_next[0] = 1 if float(boss.phase1_s) >= 0.0 else 0
		_next[1] = roundi((maxf(0.05, boss.cam.zoom.x) if boss.cam != null else 1.0) * 1000.0)
		_next[2] = int(vc.get("break_beats", 8))
		_next[3] = int(boss.brk.get("streak", 0))
		_next[4] = int(mc.get("notch_every", 5))
		_next[5] = roundi(float(mc.get("pip_px", 3.5)) * 100.0)
		_next[6] = roundi(float(mc.get("gap_px", 16.0)) * 100.0)
		_next[7] = int(boss.lapse_lo)
		_next[8] = int(boss.lapse_hi) if float(boss._lapse_t) > 0.0 else -1
		_next[9] = roundi(vei.radius * 100.0)
		if _next != _key:
			_key = _next.duplicate()
			queue_redraw()

	## The row under her is the close-to-the-break signal (the HUD meter is the full one): shown once
	## the streak is within meter.row_close_pips of break_beats (0: always), and while a lapse flashes.
	func _shown(boss, vc: Dictionary) -> bool:
		if float(boss.phase1_s) < 0.0:
			return false
		var close := int(vc.get("meter", {}).get("row_close_pips", 0))
		if close <= 0 or float(boss._lapse_t) > 0.0:
			return true
		return int(boss.brk.get("streak", 0)) >= int(vc.get("break_beats", 8)) - close

	func _draw() -> void:
		var t0 := BossDev.pt()
		if vei != null and vei.boss != null and _shown(vei.boss, vei.boss.vcfg()):
			_draw_row()
		BossDev.pa("vei", t0)

	func _draw_row() -> void:
		var boss = vei.boss
		var vc: Dictionary = boss.vcfg()
		var mc: Dictionary = vc.get("meter", {})
		var z: float = maxf(0.05, boss.cam.zoom.x) if boss.cam != null else 1.0
		var n := int(vc.get("break_beats", 8))
		var st := int(boss.brk.get("streak", 0))
		var notch := maxi(1, int(mc.get("notch_every", 5)))
		var pr := float(mc.get("pip_px", 3.5)) / z
		var step := pr * 2.7
		var gap := pr * 1.6
		var w := step * float(n - 1) + gap * floorf(float(n - 1) / float(notch))
		var x := -w * 0.5
		var y := vei.radius + float(mc.get("gap_px", 16.0)) / z + pr
		var lo: int = boss.lapse_lo
		var hi: int = boss.lapse_hi if float(boss._lapse_t) > 0.0 else -1
		for i in n:
			if i > 0 and i % notch == 0:
				var nx := x - step * 0.5 + gap * 0.5
				draw_line(Vector2(nx, y - pr * 2.0), Vector2(nx, y + pr * 2.0), Palette.c("vei", 0.85), 1.6 / z)
				x += gap
			var p := Vector2(x, y)
			if i < st:
				draw_circle(p, pr, Palette.c("vei"))
			elif i >= lo and i < hi:
				draw_arc(p, pr, 0.0, TAU, 10, Palette.c("danger"), 1.4 / z)
				draw_line(p + Vector2(-pr, pr), p + Vector2(pr, -pr), Palette.c("danger"), 1.4 / z)
			else:
				draw_arc(p, pr * 0.8, 0.0, TAU, 10, Palette.c("text_dim", 0.6), 1.0 / z)
			x += step


## The weave telegraph (z 37, above the trance dim): the laid thread while it tells, and the
## landing flash.
class Telegraph:
	extends Node2D
	var vei: RaidVei = null
	var _shown := false

	## Redraw only while a tell or a landing flash shows (and once more to clear it).
	func _process(_d: float) -> void:
		var on := vei != null and (vei.tell_on or vei._land_t >= 0.0)
		if on or _shown:
			queue_redraw()
		_shown = on

	func _draw() -> void:
		var t0 := BossDev.pt()
		_draw_tell()
		BossDev.pa("tele", t0)

	func _draw_tell() -> void:
		if vei == null:
			return
		var w := vei.wcfg()
		var half := float(w.get("width_px", 64.0)) * 0.5
		if vei.tell_on:
			var f := clampf((vei.cur_beat - vei.tell_start) / maxf(0.05, vei.tell_len), 0.0, 1.0)
			var a := to_local(vei.tell_from)
			var b := to_local(vei.tell_to)
			var reach := 1.0
			if not vei.first_done and not Pulse.reduced_motion:
				reach = clampf(f * 2.0, 0.08, 1.0)   # the first weave draws itself out from her
			var e := a.lerp(b, reach)
			var dir := (b - a).normalized()
			var side := dir.orthogonal() * half
			var edge := Palette.c("danger", 0.35 + 0.35 * f)
			draw_line(a + side, e + side, edge, 1.5)
			draw_line(a - side, e - side, edge, 1.5)
			LineGlow.polyline(self, PackedVector2Array([a, e]), Palette.c("danger", 0.55 + 0.45 * f), 2.0 + 2.0 * f, 0.7)
			# beat ticks along the thread: one per beat of tell left, so its timing counts down
			var left := ceili(maxf(0.0, vei.tell_len - (vei.cur_beat - vei.tell_start)) - 0.001)
			for i in left:
				var p := a.lerp(e, 0.25 + 0.12 * i)
				draw_line(p + side * 0.5, p - side * 0.5, Palette.c("danger", 0.9), 2.0)
		if vei._land_t >= 0.0:
			var g := clampf(vei._land_t / maxf(0.05, float(w.get("flash_s", 0.35))), 0.0, 1.0)
			var a2 := to_local(vei._land_a)
			var b2 := to_local(vei._land_b)
			LineGlow.polyline(self, PackedVector2Array([a2, b2]), Palette.c("vei", 1.0 - g), half * 0.6, 0.8,
				Palette.c("danger", 1.0 - g))
