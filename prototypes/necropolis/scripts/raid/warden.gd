class_name RaidWarden
extends Node2D
## The fortress's warden (MECHANICS 5.3): a large glyph in the last room, drawn in the `vei` accent
## (wardens are Vei's lieutenants; never the living's orange). Dormant and dim until Relish first
## enters its room, then it wakes and runs a beat clock on SCENE time (it slows with the trance).
## Undead target it like an enemy (global_position, radius, take_hit, alive) but it is not in
## `raid.enemies`: no LIVING count, no ledger mass. On death it drops `essence.per_warden` mass-0
## motes and the chest. Subclasses (Bellringer, Huntsman, Shieldwall, Pyre-priest) add the attack and the silhouette: they
## override `_step`, `_phase_now`, `_draw_glyph`, `_draw_telegraph` and may hook `_on_wake` (the
## Shieldwall also `hit_from`, the undead strike that says where it came from; the Pyre-priest
## `take_hit` for its ward and `meter_lit` for its acolytes' pips).
## The break meter (WardenLogic.meter_*): the strength left as pips, phase notches where the phases
## are hp gates, and `weak_marks` on the pips a weak-point window took. The HUD's WardenBlock is the
## meter's full read; a small pip row under the glyph echoes it in the world.

var raid: Node2D = null
var spec := {}
var hp := 100.0
var max_hp := 100.0
var radius := 30.0
var alive := true
var awake := false
var phase := 0                 # index into spec.phases
var t := 0.0                   # scene seconds since the beat clock zero (negative until beat 0)
var flash := 0.0
var drop_t := -1.0             # >= 0 while a ring is dropping away after a phase change

var _breath_t := 0.0

# break meter (pips; see WardenLogic.meter_bands)
var meter_bands: Array[float] = []
var meter_per := 4             # pips per band
var meter_n := 12              # pips in all
var meter_notch: Array[int] = []
var weak_marks := PackedByteArray()   # 1 on each pip a weak-point window took (index 0 = the first pip)
var weak_taken := 0            # pips taken inside weak-point windows, summed over the fight


## Dungeon-only: `p_spec` is `RaidLogic.warden_spec(...)`.
func configure(p_raid: Node2D, p_spec: Dictionary) -> void:
	raid = p_raid
	spec = p_spec
	max_hp = float(spec.get("hp", 100.0))
	hp = max_hp
	radius = float(spec.get("radius", 30.0))
	meter_bands = WardenLogic.meter_bands(spec)
	meter_per = WardenLogic.meter_per_band(meter_bands, int(wcfg().get("meter_pips", 12)))
	meter_n = meter_per * (meter_bands.size() - 1)
	meter_notch = WardenLogic.meter_notches(meter_bands, meter_per)
	weak_marks.resize(meter_n)
	weak_marks.fill(0)
	z_index = 34
	var tg := Telegraph.new()
	tg.warden = self
	tg.z_as_relative = false
	tg.z_index = 37   # above the trance dim (36), under Relish (38), as vei.gd does
	add_child(tg)


func wcfg() -> Dictionary:
	return ConfigDb.data.get("raid", {}).get("wardens", {})


func tempo_s() -> float:
	return Pulse.tempo_ms / 1000.0


## Beats since waking (negative before beat 0).
func beat() -> float:
	return WardenLogic.beat_of(t, tempo_s())


func is_stationary() -> bool:
	return true


## Rings still to come: one per phase from the current one on (VISUAL-LANGUAGE law 9).
func rings_left() -> int:
	return maxi(1, (spec.get("phases", []) as Array).size() - phase)


## Break meter pips lit now (the strength left).
func meter_lit() -> int:
	return WardenLogic.meter_lit(meter_bands, meter_per, hp / maxf(1.0, max_hp))


## Mark the pips between `lit_after` and `lit_before` as taken by a weak-point window.
func mark_weak(lit_before: int, lit_after: int) -> void:
	for i in range(maxi(0, lit_after), mini(lit_before, meter_n)):
		if weak_marks[i] == 0:
			weak_marks[i] = 1
			weak_taken += 1


## True while a weak-point window is open (the Huntsman's stun); the base warden has none.
func in_weak_window() -> bool:
	return false


## Relish entered the warden room. Offsets the clock so beat 0 lands on the next Pulse boundary.
func wake() -> void:
	if awake or not alive:
		return
	awake = true
	t = -(1.0 - WardenLogic.wake_phase(Pulse.now_ms(), Pulse.tempo_ms)) * tempo_s()
	var tells: Array = spec.get("tells", [])
	var first := str(tells[0]) if not tells.is_empty() else ""
	if raid.hud != null:
		raid.hud.show_banner("%s WAKES · %s" % [str(spec.get("name", "")).to_upper(), first],
			float(wcfg().get("wake_banner_s", 3.5)), "danger")
	RaidFx.ring(raid.fx_root, global_position, Palette.c("danger", 0.8), radius * 3.0, 0.7, 3.0)
	if raid._standalone:
		# dev telemetry: how many living are still up (in all, and in this room) when it wakes
		var room: Rect2 = (raid.layout["rooms"] as Array)[int(raid.layout["warden_room"])]
		var near := 0
		for e in raid.enemies:
			if is_instance_valid(e) and e.alive and room.has_point(e.global_position):
				near += 1
		print("RAID_WARDEN wake name=%s hp=%.0f living=%d living_in_room=%d frame=%d" % [str(spec.get("name", "")), max_hp,
			raid.enemies.size(), near, Engine.get_process_frames()])
	_on_wake()


func _on_wake() -> void:
	pass


## An undead's strike (RaidUnit): the Shieldwall reads where it came from; every other warden just
## takes the hit.
func hit_from(amount: float, _attacker: Node2D) -> void:
	take_hit(amount)


func take_hit(amount: float) -> void:
	if not alive or not awake:
		return
	hp -= amount
	flash = 1.0
	if hp <= 0.0:
		hp = 0.0
		_die()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if raid == null or raid._ended or not alive:
		return
	_breath_t += delta
	flash = maxf(0.0, flash - delta * 4.0)
	if drop_t >= 0.0:
		drop_t += delta
		if drop_t >= float(wcfg().get("phase_flash_s", 0.6)):
			drop_t = -1.0
	if awake:
		t += delta
		var ph := _phase_now()
		if ph != phase:
			var old := phase
			phase = ph
			_on_phase_change(old, ph)
		_step(delta)
	queue_redraw()


## The phase the warden's own rule gives right now (Bellringer: hp thresholds).
func _phase_now() -> int:
	return phase


func _on_phase_change(_old: int, new: int) -> void:
	drop_t = 0.0
	flash = 1.0
	RaidFx.ring(raid.fx_root, global_position, Palette.c("vei"), radius * 2.2, float(wcfg().get("phase_flash_s", 0.6)), 4.0)
	RaidFx.ring(raid.fx_root, global_position, Palette.c("text", 0.8), radius * 1.4, 0.4, 2.5)
	if raid._standalone:
		print("RAID_WARDEN phase %d hp=%.0f/%.0f" % [new, hp, max_hp])


## Per awake physics frame, after the clock and phase update.
func _step(_delta: float) -> void:
	pass


## Subclass telegraph drawing, on the z 37 child (centred on the warden).
func _draw_telegraph(_ci: CanvasItem) -> void:
	pass


func _die() -> void:
	alive = false
	var e: Dictionary = raid.rcfg().get("essence", {})
	var n := int(e.get("per_warden", 6))
	for i in n:
		var ang: float = TAU * i / float(maxi(1, n)) + raid.rng_combat.randf() * 0.5
		var spd: float = raid.rng_combat.randf_range(50.0, 110.0)
		raid.spawn_mote(raid.resolve_walls(global_position + Vector2(radius * 0.5, 0).rotated(ang), 6.0),
			0.0, false, Vector2(spd, 0).rotated(ang))
	RaidFx.ring(raid.fx_root, global_position, Palette.c("vei"), radius * 3.5, 0.8, 4.0)
	RaidFx.ring(raid.fx_root, global_position, Palette.c("text", 0.9), radius * 2.0, 0.5, 3.0)
	if raid._standalone:
		print("RAID_WARDEN died")
	raid.warden_run.on_warden_died(self)
	queue_free()


# ------------------------------------------------------------------- draw ---
func _draw() -> void:
	var col := Palette.c("vei", 1.0 if awake else float(wcfg().get("dormant_alpha", 0.32)))
	if awake and flash > 0.0:
		col = col.lerp(Palette.c("text"), minf(0.85, flash))
	_draw_glyph(col)
	if awake:
		_draw_meter_row()


## The silhouette, centred on the warden. The base warden (an archetype with no attack yet) is one
## ring per phase left.
func _draw_glyph(col: Color) -> void:
	var n := rings_left()
	for i in n:
		if awake:
			LineGlow.ring(self, Vector2.ZERO, _ring_r(i), col, 2.6 if i == n - 1 else 2.0, 0.7)
		else:
			draw_arc(Vector2.ZERO, _ring_r(i), 0.0, TAU, 48, col, 2.0)


## Ring i of the base glyph, outermost last: the outer ring is the collision radius.
func _ring_r(i: int) -> float:
	var step := float(wcfg().get("glyph_ring_step", 0.2))
	var n := (spec.get("phases", []) as Array).size()
	return radius * (1.0 - step * float(maxi(0, n - 1 - i)))


## Camera zoom (1 before the camera exists): in-world sizes that must hold on screen divide by it.
func zoom() -> float:
	return maxf(0.05, raid.cam.zoom.x) if raid != null and raid.cam != null else 1.0


## How far below the warden's centre its in-world meter row sits (taller silhouettes push it down).
func _meter_y() -> float:
	return radius + float(wcfg().get("meter_gap_px", 16.0))


## The meter's echo under the glyph: a row of pips as in the HUD (lit `vei`, spent a dim ring, a
## weak-point pip an `undead` ring with a slash), phase notches as short ticks between them. Sized
## in screen px (divided by the zoom). No text: the HUD carries the counts.
func _draw_meter_row() -> void:
	var z := zoom()
	var pr := float(wcfg().get("meter_pip_px", 3.5)) / z
	var step := pr * 2.7
	var gap := pr * 1.6
	var w := step * float(meter_n - 1) + gap * float(meter_notch.size())
	var x := -w * 0.5
	var y := _meter_y() + pr
	var lit := meter_lit()
	for i in meter_n:
		if meter_notch.has(i):
			var nx := x - step * 0.5 + gap * 0.5
			draw_line(Vector2(nx, y - pr * 2.0), Vector2(nx, y + pr * 2.0), Palette.c("vei", 0.85), 1.6 / z)
			x += gap
		var p := Vector2(x, y)
		if i < lit:
			draw_circle(p, pr, Palette.c("vei"))
		elif weak_marks[i] != 0:
			draw_arc(p, pr, 0.0, TAU, 10, Palette.c("undead"), 1.4 / z)
			draw_line(p + Vector2(-pr, pr), p + Vector2(pr, -pr), Palette.c("undead"), 1.4 / z)
		else:
			draw_arc(p, pr * 0.8, 0.0, TAU, 10, Palette.c("text_dim", 0.6), 1.0 / z)
		x += step


## Telegraph layer (z 37): draws whatever the subclass shows for the next attack.
class Telegraph:
	extends Node2D
	var warden: RaidWarden = null

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if warden != null and is_instance_valid(warden) and warden.alive and warden.awake:
			warden._draw_telegraph(self)
