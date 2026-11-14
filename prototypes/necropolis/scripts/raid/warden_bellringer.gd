class_name RaidBellringer
extends RaidWarden
## The Bellringer: stationary. A ring slam on the tempo, telegraphed for tell_beats as a tightening
## danger ring plus a faint preview of the slam's full reach. Beef soaks the slam; a beefy big
## undead braced at the bell muffles it. Three phases by hp, each ring faster.

var muffled := false           # the slam in flight (or the next one) is muffled
var _next_attack := 0.0        # beat of the next slam
var _tell_for := -1.0          # the _next_attack beat whose tell has sounded
var _last_attack := 0.0        # beat of the last slam (0 = waking)
var _slam_beat := -1.0         # beat the live slam started, -1 when none
var _slam_prev_r := 0.0
var _slam_muffled := false
var _slams := 0
var slams_muffled := 0         # slams rung while a beefy big braced the bell (autopilot telemetry)


func _on_wake() -> void:
	_next_attack = WardenLogic.period_beats(spec, phase)


func _phase_now() -> int:
	return WardenLogic.bellringer_phase(spec, hp / maxf(1.0, max_hp))


func _on_phase_change(old: int, new: int) -> void:
	super._on_phase_change(old, new)
	# a faster rhythm: pull a slam that is not yet telegraphed in to the new period
	var tell := float(spec.get("attack", {}).get("tell_beats", 1.0))
	var b := beat()
	if b < _next_attack - tell:
		_next_attack = minf(_next_attack, maxf(b + tell, _last_attack + WardenLogic.period_beats(spec, new)))


## Party big undead touching the bell: [{beef}] for WardenLogic.is_muffled.
func _contacts() -> Array:
	var out: Array = []
	var pad := float(wcfg().get("muffle_pad_px", 14.0))
	for a in raid.allies:
		if is_instance_valid(a) and a.alive and a.kind == "big" \
				and a.global_position.distance_to(global_position) <= a.radius + radius + pad:
			out.append({"beef": a.beef})
	return out


func _step(_delta: float) -> void:
	muffled = WardenLogic.is_muffled(spec, _contacts())
	var b := beat()
	var at: Dictionary = spec.get("attack", {})
	var rel0: RaidRelish = raid.relish
	if rel0 != null and is_instance_valid(rel0) and rel0.alive and _slam_beat < 0.0 \
			and WardenLogic.is_tell(b, _next_attack, float(at.get("tell_beats", 1.0))) \
			and rel0.global_position.distance_to(global_position) <= float(at.get("radius_px", 360.0)):
		raid.danger_targeted()   # her edge warns while the slam tell reaches her
	if _slam_beat < 0.0 and _tell_for != _next_attack and WardenLogic.is_tell(b, _next_attack, float(at.get("tell_beats", 1.0))):
		_tell_for = _next_attack
		RaidSound.play("tell")   # once per tell
	if _slam_beat < 0.0 and b >= _next_attack:
		_slam_beat = _next_attack
		_last_attack = _next_attack
		_slam_prev_r = 0.0
		_slam_muffled = muffled
		_slams += 1
		RaidSound.play("muffle" if muffled else "slam")
		if muffled:
			slams_muffled += 1
		_next_attack = _last_attack + WardenLogic.period_beats(spec, phase)
		if raid._standalone:
			print("RAID_WARDEN slam n=%d muffled=%s phase=%d bigs_at_bell=%d frame=%d" % [_slams, str(_slam_muffled), phase, _contacts().size(), Engine.get_process_frames()])
	if _slam_beat >= 0.0:
		var r := WardenLogic.slam_radius(spec, b - _slam_beat)
		if r < 0.0:
			_slam_beat = -1.0
		else:
			_apply_slam(_slam_prev_r, r, float(at.get("band_px", 36.0)))
			_slam_prev_r = r


func _apply_slam(r_prev: float, r_now: float, band: float) -> void:
	for a in raid.allies.duplicate():
		if not is_instance_valid(a) or not a.alive:
			continue
		var d: float = a.global_position.distance_to(global_position)
		if WardenLogic.slam_crosses(d, r_prev, r_now, band):
			var big: bool = a.kind == "big"
			a.take_hit(WardenLogic.slam_damage(spec, "big" if big else "unit", a.beef if big else 0.0, _slam_muffled))
	var rel: RaidRelish = raid.relish
	if rel != null and is_instance_valid(rel) and rel.alive \
			and WardenLogic.slam_crosses(rel.global_position.distance_to(global_position), r_prev, r_now, band):
		rel.take_hit(WardenLogic.slam_damage(spec, "relish", 0.0, _slam_muffled))


func _draw_telegraph(ci: CanvasItem) -> void:
	var at: Dictionary = spec.get("attack", {})
	var tell := float(at.get("tell_beats", 1.0))
	var b := beat()
	var reach := float(at.get("radius_px", 360.0))
	var band := float(at.get("band_px", 36.0))
	var danger := Palette.c("danger")
	if _slam_beat < 0.0 and WardenLogic.is_tell(b, _next_attack, tell):
		var f := clampf((b - (_next_attack - tell)) / maxf(0.01, tell), 0.0, 1.0)
		# faint preview of the slam's full reach, so the player learns it
		LineGlow.ring(ci, Vector2.ZERO, reach, Palette.c("danger", float(wcfg().get("tell_preview_alpha", 0.16))), 2.0, 0.0)
		# the tightening ring at the bell
		var r0 := radius * float(wcfg().get("tell_ring_start", 2.6))
		LineGlow.ring(ci, Vector2.ZERO, lerpf(r0, radius * 1.15, f), Palette.c("danger", 0.45 + 0.5 * f), 3.0, 0.6)
	if _slam_beat >= 0.0:
		var r := WardenLogic.slam_radius(spec, b - _slam_beat)
		if r > 0.0:
			var fade := 1.0 - r / maxf(1.0, reach) * 0.5
			ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Palette.c("danger", 0.12 * fade), band)
			if _slam_muffled:
				# thinner and dashed: the bell is smothered
				var n := 28
				for k in n:
					var a0 := TAU * k / float(n)
					LineGlow.arc(ci, Vector2.ZERO, r, a0, a0 + TAU / float(n) * 0.5, Palette.c("danger", 0.7 * fade), 2.0, 0.3)
			else:
				LineGlow.ring(ci, Vector2.ZERO, r, Palette.c("danger", fade), 5.0, 0.8)
	if muffled:
		var font := ThemeDB.fallback_font
		ci.draw_string(font, Vector2(-40, -radius * 1.6 - 22.0), "MUFFLED", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 16, Palette.c("undead"))
		ci.draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 32, Palette.c("undead", 0.6), 2.0)
