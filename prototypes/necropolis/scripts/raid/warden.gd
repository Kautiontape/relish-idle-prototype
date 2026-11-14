class_name RaidWarden
extends Node2D
## The fortress's warden (MECHANICS 5.3): a large multi-ring glyph in the last room. Dormant and
## dim until Relish first enters its room, then it wakes and runs a beat clock on SCENE time (it
## slows with the trance), phased by hp. Undead target it like an enemy (global_position, radius,
## take_hit, alive) but it is not in `raid.enemies`: no LIVING count, no ledger mass. On death it
## drops `essence.per_warden` mass-0 motes and the chest. Subclasses (Bellringer, Huntsman) add
## the attack: they override `_step`, `_phase_now`, `_draw_telegraph` and may hook `_on_wake`.

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


## Dungeon-only: `p_spec` is `RaidLogic.warden_spec(...)`.
func configure(p_raid: Node2D, p_spec: Dictionary) -> void:
	raid = p_raid
	spec = p_spec
	max_hp = float(spec.get("hp", 100.0))
	hp = max_hp
	radius = float(spec.get("radius", 30.0))
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


## Relish entered the warden room. Offsets the clock so beat 0 lands on the next Pulse boundary.
func wake() -> void:
	if awake or not alive:
		return
	awake = true
	t = -(1.0 - Pulse.phase()) * tempo_s()
	var tells: Array = spec.get("tells", [])
	var first := str(tells[0]) if not tells.is_empty() else ""
	if raid.hud != null:
		raid.hud.show_banner("%s WAKES · %s" % [str(spec.get("name", "")).to_upper(), first],
			float(wcfg().get("wake_banner_s", 3.5)), "danger")
	RaidFx.ring(raid.fx_root, global_position, Palette.c("danger", 0.8), radius * 3.0, 0.7, 3.0)
	if raid._standalone:
		print("RAID_WARDEN wake name=%s hp=%.0f" % [str(spec.get("name", "")), max_hp])
	_on_wake()


func _on_wake() -> void:
	pass


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
	RaidFx.ring(raid.fx_root, global_position, Palette.c("living"), radius * 2.2, float(wcfg().get("phase_flash_s", 0.6)), 4.0)
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
	RaidFx.ring(raid.fx_root, global_position, Palette.c("living"), radius * 3.5, 0.8, 4.0)
	RaidFx.ring(raid.fx_root, global_position, Palette.c("text", 0.9), radius * 2.0, 0.5, 3.0)
	if raid._standalone:
		print("RAID_WARDEN died")
	raid.warden_run.on_warden_died(self)
	queue_free()


# ------------------------------------------------------------------- draw ---
func _draw() -> void:
	var col := Palette.c("living")
	var reduced: bool = Pulse.reduced_motion
	if not awake:
		# dormant: one dim ring per phase, no glow
		var dim := Palette.c("living", 0.32)
		for i in rings_left():
			draw_arc(Vector2.ZERO, _ring_r(i), 0.0, TAU, 48, dim, 2.0)
		draw_circle(Vector2.ZERO, radius * 0.16, dim)
		return
	if flash > 0.0:
		col = col.lerp(Palette.c("text"), minf(0.85, flash))
	var breathe := 1.0 + 0.035 * Pulse.wave()   # steady under reduced motion (Pulse.wave is constant)
	var n := rings_left()
	for i in n:
		var r := _ring_r(i) * breathe
		LineGlow.ring(self, Vector2.ZERO, r, col, 2.6 if i == n - 1 else 2.0, 0.7, Palette.c("living_core"))
	if drop_t >= 0.0:
		# the ring that just fell away, shrinking out
		var f := drop_t / maxf(0.05, float(wcfg().get("phase_flash_s", 0.6)))
		draw_arc(Vector2.ZERO, _ring_r(n) * (1.0 + 0.5 * f), 0.0, TAU, 48, Palette.c("living", 0.7 * (1.0 - f)), 2.0)
	# tick marks on the outer ring turn slowly (hold still under reduced motion)
	var spin := 0.0 if reduced else _breath_t * 0.2
	var ro := _ring_r(n - 1) * breathe
	for k in 8:
		var a := TAU * k / 8.0 + spin
		draw_line(Vector2(ro + 4.0, 0).rotated(a), Vector2(ro + 12.0, 0).rotated(a), Palette.c("living", 0.6), 2.0)
	draw_circle(Vector2.ZERO, radius * 0.2, col)
	draw_circle(Vector2.ZERO, radius * 0.08, Palette.c("text", 0.9))
	# a small hp arc under the glyph's outer ring
	var f2 := clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	var rhp := ro + 18.0
	draw_arc(Vector2.ZERO, rhp, PI * 0.15, PI * 0.85, 24, Palette.c("ground", 0.8), 4.0)
	if f2 > 0.0:
		draw_arc(Vector2.ZERO, rhp, PI * 0.15, PI * 0.15 + PI * 0.7 * f2, 24, Palette.c("living"), 4.0)


## Ring i of the glyph, outermost last: the outer ring is the collision radius.
func _ring_r(i: int) -> float:
	var step := float(wcfg().get("glyph_ring_step", 0.2))
	var n := (spec.get("phases", []) as Array).size()
	return radius * (1.0 - step * float(maxi(0, n - 1 - i)))


## Telegraph layer (z 37): draws whatever the subclass shows for the next attack.
class Telegraph:
	extends Node2D
	var warden: RaidWarden = null

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if warden != null and is_instance_valid(warden) and warden.alive and warden.awake:
			warden._draw_telegraph(self)
