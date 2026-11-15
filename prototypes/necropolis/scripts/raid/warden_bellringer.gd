class_name RaidBellringer
extends RaidWarden
## The Bellringer: stationary. A ring slam on the tempo, telegraphed for tell_beats as a tightening
## danger ring plus a faint preview of the slam's full reach. Beef soaks the slam; a beefy big
## undead braced at the bell muffles it. Three phases by hp, each ring faster.
## Silhouette: a heavy bell outline in `vei`, one rib per phase left (a rib falls away at each
## phase), and a clapper line that swings through the tell and strikes the lip on the slam (under
## reduced motion it holds at the struck angle for the whole tell).
## The weak point, shown as it happens: while a beefy big is braced at the bell an `undead` ring
## hugs it with the word BRACED; through the tell (and a muffled slam) a line links each bracing big
## to the bell, so the cause is on screen; a muffled slam's ring goes out dim and dashed with the
## word MUFFLED riding it, as the Huntsman's INTERCEPTED does.

var muffled := false           # the slam in flight (or the next one) is muffled
var _next_attack := 0.0        # beat of the next slam
var _tell_for := -1.0          # the _next_attack beat whose tell has sounded
var _last_attack := 0.0        # beat of the last slam (0 = waking)
var _slam_beat := -1.0         # beat the live slam started, -1 when none
var _slam_prev_r := 0.0
var _slam_muffled := false
var _slams := 0
var slams_muffled := 0         # slams rung while a beefy big braced the bell (autopilot telemetry)
var slams := 0                 # slams rung, for the HUD's "MUFFLED x n of m" (a read-only mirror of _slams)
var toll_at := Vector2.INF     # D-d/E Step 4b: where this tell's toll ring lies (her spot as the tell began; INF: none)
var toll_r := 0.0              # its radius (attack.toll_radius_px)
var tolls := 0                 # tolls rung (telemetry)
var _slam_tells := 0           # slam tells begun (the toll lands on every attack.toll_every-th)
var tolls_struck := 0          # of them, those that struck her
var toll_exit_at := Vector2.INF   # the exit WardenLogic.toll_exit found for this tell's toll (the decent player's step)
var toll_beats := 0            # toll beats with her in the room beyond the slam's reach (telemetry: tolls / toll_beats placed)
var toll_exit_px_max := 0.0    # the longest exit path among the tolls placed (telemetry: the worst-case margin)
var toll_marks := {}           # telemetry: "%.4f" slam beat of each toll placed -> "placed", "struck" or "muffled"
var _toll_word_t := 99.0       # draw only: seconds since a toll resolved
var _toll_word_at := Vector2.ZERO
var _toll_word := ""

var _bell := PackedVector2Array()   # the outline, built once from the radius
var _ribs: Array[PackedVector2Array] = []   # rib i spans the bell at height RIB_Y[i]
var _clap := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var _braced: Array[Node2D] = []   # the big undead bracing the bell now (drawn as links; visual only)
var _link := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])

const BELL_L := [Vector2(0.0, -0.84), Vector2(-0.22, -0.83), Vector2(-0.36, -0.77), Vector2(-0.44, -0.64),
	Vector2(-0.48, -0.44), Vector2(-0.51, -0.18), Vector2(-0.56, 0.10), Vector2(-0.66, 0.34),
	Vector2(-0.82, 0.52), Vector2(-0.95, 0.60), Vector2(-0.95, 0.70)]
const RIB_Y := [-0.10, 0.18, 0.42]   # one rib per phase left: the lowest falls away first


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


## The toll's counts (autopilot telemetry; reads only): tolls placed of toll_beats, tolls struck, the longest exit path.
func telemetry() -> Dictionary:
	return {"tolls": tolls, "tolls_struck": tolls_struck, "toll_beats": toll_beats, "toll_exit_px_max": snappedf(toll_exit_px_max, 0.1)}


## Party big undead touching the bell: [{beef}] for WardenLogic.is_muffled.
func _contacts() -> Array:
	var out: Array = []
	var pad := float(wcfg().get("muffle_pad_px", 14.0))
	for a in raid.allies:
		if is_instance_valid(a) and a.alive and a.kind == "big" \
				and a.global_position.distance_to(global_position) <= a.radius + radius + pad:
			out.append({"beef": a.beef})
	return out


func _step(delta: float) -> void:
	if _pack_step(delta):   # its pack runs: no tell until a beat after the last falls (one threat at a time)
		_next_attack = maxf(_next_attack, ceilf(beat()) + float(spec.get("attack", {}).get("tell_beats", 1.0)) + 1.0)
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
		# the toll: a ring where she stands as the tell begins (in its room); stepping out is the answer
		_slam_tells += 1
		var every := maxi(1, int(at.get("toll_every", 1)))
		toll_r = float(at.get("toll_radius_px", 0.0)) \
			if WardenLogic.lever_on(int(spec.get("tier", 1)), bool(spec.get("first_dungeon", false)), wcfg()) \
			and _slam_tells % every == 0 else 0.0
		var room: Rect2 = (raid.layout["rooms"] as Array)[int(raid.layout["warden_room"])]
		# only where the slam's own ring cannot reach her (inside it, the ring is the threat), and only where an
		# exit exists inside the room, out of both rings, that a human reaches in time (WardenLogic.toll_exit;
		# else that slam tolls nothing)
		toll_at = Vector2.INF
		toll_exit_at = Vector2.INF
		var slam_reach := float(at.get("radius_px", 360.0)) + float(at.get("band_px", 36.0)) * 0.5
		if toll_r > 0.0 and rel0 != null and is_instance_valid(rel0) and rel0.alive \
				and room.has_point(rel0.global_position) and rel0.global_position.distance_to(global_position) > slam_reach + rel0.radius:
			toll_beats += 1
			var budget := (float(at.get("tell_beats", 1.0)) * tempo_s() - float(at.get("toll_react_s", 0.6))) * rel0.speed
			toll_exit_at = WardenLogic.toll_exit(room, rel0.global_position, global_position, toll_r, rel0.radius,
				slam_reach + rel0.radius, float(at.get("toll_exit_margin_px", 16.0)), budget)
			if toll_exit_at != Vector2.INF:
				toll_at = rel0.global_position
				toll_marks["%.4f" % _next_attack] = "placed"
				toll_exit_px_max = maxf(toll_exit_px_max, toll_at.distance_to(toll_exit_at))
	if _slam_beat < 0.0 and b >= _next_attack:
		_slam_beat = _next_attack
		_last_attack = _next_attack
		_slam_prev_r = 0.0
		_slam_muffled = muffled
		_slams += 1
		slams = _slams
		RaidSound.play("muffle" if muffled else "slam")
		if muffled:
			slams_muffled += 1
		if toll_at != Vector2.INF:
			tolls += 1
			var rp: Vector2 = rel0.global_position if rel0 != null and is_instance_valid(rel0) else Vector2.INF
			var in_ring: bool = rp != Vector2.INF and rp.distance_to(global_position) <= float(at.get("radius_px", 360.0)) + float(at.get("band_px", 36.0)) * 0.5 + rel0.radius
			var struck := rel0 != null and is_instance_valid(rel0) and rel0.alive \
				and WardenLogic.toll_strikes(rp, toll_at, toll_r, rel0.radius, muffled, in_ring)
			if struck:
				tolls_struck += 1
				rel0.take_hit(WardenLogic.slam_damage(spec, "relish", 0.0, false), "toll")   # its own source: the card tells it from the slam
			_toll_word = "MUFFLED" if muffled else ("TOLLED" if struck else "")
			toll_marks["%.4f" % _slam_beat] = "muffled" if muffled else ("struck" if struck else "placed")
			_toll_word_at = toll_at
			_toll_word_t = 0.0
			toll_at = Vector2.INF
			toll_exit_at = Vector2.INF
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
	_toll_word_t += delta   # draw-only clock
	_update_braced(b, at)   # visual only, and last


## The toll in the world (tell -> counter -> labelled result): through the tell a `danger` ring where she
## stood as it began, closing on the beat (steady under reduced motion) with TOLL over it; after the slam,
## for `wardens.pack_label_s`, TOLLED (it struck her) or MUFFLED (a braced bell tolls nothing) at that spot.
func _draw_toll(ci: CanvasItem) -> void:
	var fs := roundi(float(wcfg().get("label_px", 15)) / zoom())
	if toll_at != Vector2.INF:
		var at: Dictionary = spec.get("attack", {})
		var tell := float(at.get("tell_beats", 1.0))
		var f := 1.0 if Pulse.reduced_motion else clampf(1.0 - (_next_attack - beat()) / maxf(0.01, tell), 0.0, 1.0)
		var p := toll_at - global_position
		LineGlow.ring(ci, p, toll_r, Palette.c("danger", 0.45 + 0.45 * f), 2.5 / zoom(), 0.6)
		ci.draw_arc(p, toll_r * (1.0 - 0.25 * (1.0 - f)), 0.0, TAU, 40, Palette.c("danger", 0.35), 1.5 / zoom())
		_pack_word(ci, p + Vector2(0, -toll_r - fs * 0.8), "TOLL", fs, Palette.c("danger"))
	elif _toll_word != "" and _toll_word_t < float(wcfg().get("pack_label_s", 1.2)):
		_pack_word(ci, _toll_word_at - global_position, _toll_word, fs, Palette.c("undead") if _toll_word == "MUFFLED" else Palette.c("danger"))


## Who is bracing the bell (the bigs the muffle counts: beef at the threshold, within the pad), kept
## for the links while a tell shows or a muffled slam is out. Reads the allies; changes nothing.
func _update_braced(b: float, at: Dictionary) -> void:
	_braced.clear()
	var showing := (_slam_beat < 0.0 and WardenLogic.is_tell(b, _next_attack, float(at.get("tell_beats", 1.0)))) \
		or (_slam_beat >= 0.0 and _slam_muffled)
	if not showing or not muffled:
		return
	var pad := float(wcfg().get("muffle_pad_px", 14.0))
	var th := float((spec.get("weak_point", {}) as Dictionary).get("threshold", 1.0e9))
	for a in raid.allies:
		if is_instance_valid(a) and a.alive and a.kind == "big" and float(a.beef) >= th \
				and a.global_position.distance_to(global_position) <= a.radius + radius + pad:
			_braced.append(a)


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
			and WardenLogic.slam_crosses(rel.global_position.distance_to(global_position), r_prev, r_now, band) \
			and WardenLogic.slam_damage(spec, "relish", 0.0, _slam_muffled) > 0.0:   # a MUFFLED slam does not reach her
		rel.take_hit(WardenLogic.slam_damage(spec, "relish", 0.0, _slam_muffled), "slam")


# ------------------------------------------------------------------- draw ---
func _build_bell() -> void:
	var left := PackedVector2Array()
	for v in BELL_L:
		left.append((v as Vector2) * radius)
	_bell.clear()
	for v in left:
		_bell.append(v)
	for i in range(left.size() - 1, -1, -1):
		_bell.append(Vector2(-left[i].x, left[i].y))
	_ribs.clear()
	for y in RIB_Y:
		var hw := _half_width(float(y)) * radius - 3.0
		_ribs.append(PackedVector2Array([Vector2(-hw, float(y) * radius), Vector2(hw, float(y) * radius)]))


## The bell's half-width (in radii) at height y (in radii), from the left profile.
func _half_width(y: float) -> float:
	for i in BELL_L.size() - 1:
		var a: Vector2 = BELL_L[i]
		var b: Vector2 = BELL_L[i + 1]
		if y >= a.y and y <= b.y:
			return -lerpf(a.x, b.x, (y - a.y) / maxf(0.0001, b.y - a.y))
	return 0.5


func _meter_y() -> float:
	return radius * 0.70 + float(wcfg().get("meter_gap_px", 16.0))


## The clapper's swing in radians: still at rest, swinging wider through the tell, struck against
## the lip just after the slam (alternate sides). Reduced motion: held at the struck angle.
func _clapper_angle() -> float:
	if not awake:
		return 0.0
	var at: Dictionary = spec.get("attack", {})
	var tell := float(at.get("tell_beats", 1.0))
	var b := beat()
	var side := 1.0 if _slams % 2 == 0 else -1.0
	var struck := float(wcfg().get("clapper_strike_rad", 0.5))
	if _slam_beat >= 0.0 and b - _slam_beat < float(wcfg().get("clapper_hold_beats", 0.25)):
		return -side * struck   # the slam that just rang struck the other side
	if _slam_beat < 0.0 and WardenLogic.is_tell(b, _next_attack, tell):
		if Pulse.reduced_motion:
			return side * struck
		var f := clampf((b - (_next_attack - tell)) / maxf(0.01, tell), 0.0, 1.0)
		return side * struck * (0.3 + 0.7 * f) * sin(_breath_t * float(wcfg().get("clapper_swing_rad_s", 14.0)))
	return 0.0


func _draw_glyph(col: Color) -> void:
	if _bell.is_empty():
		_build_bell()
	var dim := not awake
	var core := Palette.c("text", 0.9)
	if dim:
		draw_polyline(_bell, col, 2.0)
	else:
		LineGlow.polyline(self, _bell, col, 2.8, 0.7, core)
	# the canon: the loop the bell hangs from
	draw_arc(Vector2(0, -0.97 * radius), 0.13 * radius, 0.0, TAU, 16, col, 2.0)
	# ribs: one per phase left
	var n := rings_left()
	var rib_col := col
	rib_col.a *= 0.8
	for i in mini(n, _ribs.size()):
		draw_polyline(_ribs[i], rib_col, 2.0)
	if drop_t >= 0.0 and n < _ribs.size():
		# the rib that just fell away drops and fades
		var f := drop_t / maxf(0.05, float(wcfg().get("phase_flash_s", 0.6)))
		var gone: PackedVector2Array = _ribs[n]
		var off := Vector2(0, 14.0 * f)
		draw_line(gone[0] + off, gone[1] + off, Palette.c("vei", 0.8 * (1.0 - f)), 2.0)
	# the clapper: a line from the crown with a ball, swinging on the tell
	var piv := Vector2(0, -0.66 * radius)
	var tip := piv + Vector2(0, 1.12 * radius).rotated(_clapper_angle())
	_clap[0] = piv
	_clap[1] = tip
	if dim:
		draw_polyline(_clap, col, 2.0)
	else:
		LineGlow.polyline(self, _clap, col, 2.4, 0.5)
	draw_circle(tip, 0.10 * radius, col)


func _draw_telegraph(ci: CanvasItem) -> void:
	_draw_toll(ci)
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
			var fs := roundi(float(wcfg().get("label_px", 15)) / zoom())
			if _slam_muffled:
				# muffled: the ring goes out dim, thin and dashed, and says so as it travels
				ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Palette.c("danger", 0.05 * fade), band)
				var n := 28
				for k in n:
					var a0 := TAU * k / float(n)
					ci.draw_arc(Vector2.ZERO, r, a0, a0 + TAU / float(n) * 0.5, 4, Palette.c("danger", 0.4 * fade), 1.5)
				ci.draw_string(ThemeDB.fallback_font, Vector2(-fs * 4.0, -r - fs * 0.35), "MUFFLED",
					HORIZONTAL_ALIGNMENT_CENTER, fs * 8.0, fs, Palette.c("undead", minf(1.0, 0.4 + fade)))
			else:
				ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Palette.c("danger", 0.12 * fade), band)
				LineGlow.ring(ci, Vector2.ZERO, r, Palette.c("danger", fade), 5.0, 0.8)
	# the cause: each bracing big ringed, and a line from it into the bell, through the tell and a
	# muffled slam (they stand in the swarm at the bell, so the ring is what picks them out)
	for a in _braced:
		if not is_instance_valid(a):
			continue
		var to := a.global_position - global_position
		_link[0] = to.normalized() * radius * 0.45
		_link[1] = to
		LineGlow.polyline(ci, _link, Palette.c("undead"), 3.0, 0.8)
		LineGlow.ring(ci, to, float(a.radius) + 6.0, Palette.c("undead"), 2.4, 0.8)
	if muffled:
		# the brace itself (a state, not the event): an undead ring hugging the bell
		ci.draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 32, Palette.c("undead", 0.6), 2.0)
		if not (_slam_beat >= 0.0 and _slam_muffled):
			var fs2 := roundi(float(wcfg().get("label_px", 15)) / zoom())
			ci.draw_string(ThemeDB.fallback_font, Vector2(-fs2 * 4.0, -radius * 1.25 - fs2 * 0.6), "BRACED",
				HORIZONTAL_ALIGNMENT_CENTER, fs2 * 8.0, fs2, Palette.c("undead"))
