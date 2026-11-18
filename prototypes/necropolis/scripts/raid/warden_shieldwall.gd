class_name RaidShieldwall
extends RaidWarden
## The Shieldwall (MECHANICS 5.3: frontal immunity, wits flankers): stationary at its room's centre,
## it turns its shield toward the densest crowd of undead within reach (WardenLogic.shield_goal; the
## flank-role undead are left out, they keep to its back; Relish when none is in reach) at a limited
## rate. An undead's strike (`hit_from`) from inside the front arc glances (attack.front_mult, the
## word GLANCE, `clang`); from outside it the hit lands (FLANKED, `flank`; in full from the side, at
## attack.back_mult from inside the back arc, ±back_half_deg) and the pips it takes are marked as
## the weak point's. Every period_beats it bashes its front arc, telegraphed
## tell_beats ahead as the lit arc (and the word BASH): planted through the tell, so the lit arc is
## where it lands; undead in the arc take dmg_unit and are shoved away, Relish takes dmg_relish.
## Phases at hp thirds turn faster, widen the arc and bash sooner.
## The weak point (wits): a big undead with wits >= the threshold fighting it walks round to its back
## (RaidWardenRun.flank_for) and strikes only off the shield; it is ringed in `undead` while posted.
## Silhouette, drawn as lines along the facing: a heavy shield arc over the front (one plate behind it
## per phase left; a plate falls away at each phase), a boss on the shield pointing where it faces,
## a helm and spine behind it, and the open back as a dashed arc with the word FLANK.

var facing := 0.0              # radians: the shield's centre bearing (sim state)
var planted := false           # a bash tell shows: the facing holds
var hits := 0                  # undead strikes taken
var glances := 0               # of them on the shield (front arc)
var flanks := 0                # of them from outside it (FLANKED: side or back)
var backs := 0                 # of the flanks: from inside the back arc (the bonus)
var role_hits := 0             # strikes by a flank-role big undead (any arc)
var dmg_glance := 0.0          # damage taken through the shield
var dmg_flank := 0.0           # damage taken from outside it
var dmg_role := 0.0            # of all damage: dealt by flank-role big undead
var bashes := 0
var bash_units := 0            # undead the bashes struck
var bash_relish := 0           # bashes that struck Relish (soaked or not)
var rushing := false           # this bash is a rush (D-d/E 3b): wider and longer, decided as its tell starts
var rushes := 0                # bashes that were rushes
var pins := 0                  # bashes a wits flanker at its back pinned (no rush)
var pinned_tell := false       # this bash's tell was pinned (no rush; with the risk lever off its bash also spares Relish)
var lane := false              # this rush is aimed at her (D-d/E Step 4b): a narrow lane across its room
var rush_relish := 0           # rushes that struck Relish
var pin_broke := false         # this tell's pin did not hold (attack.rush_lane_every): PIN BROKEN, draw and HUD only
var pin_breaks := 0            # tells a wits flanker pinned that were aimed at her all the same (attack.rush_lane_every, D-e task 4)
var _bash_tells := 0           # bash tells begun since the wake (every attack.rush_lane_every-th is aimed at her)
var _base_reach := -1.0        # attack.reach_px as configured (a rush lengthens it for its tell and bash)

var _room := Rect2()
var _goal := 0.0               # the bearing it turns toward
var _goal_t := 0.0             # scene seconds until the goal is re-picked
var _next_attack := 0.0        # beat of the next bash
var _last_attack := 0.0
var _tell_for := -1.0          # the _next_attack beat whose tell has sounded
var _bash_flash := 0.0         # draw only: the bash's after-image (1 -> 0)
var _bash_face := 0.0          # draw only: the facing the last bash struck along
var _glance_t := 99.0          # draw only: scene seconds since the last glance
var _flank_t := 99.0           # draw only: scene seconds since the last flank hit
var _flank_at := 0.0           # draw only: the last flank hit's bearing
var _flankers: Array[Node2D] = []   # draw only: flank-role big undead on their way or posted

var _pts := PackedVector2Array()    # scratch for the sector fill


## The dormant wall faces its room's way in (the antechamber), so the first look reads its front.
func configure(p_raid: Node2D, p_spec: Dictionary) -> void:
	super.configure(p_raid, p_spec)
	var rooms: Array = raid.layout.get("rooms", [])
	var ar := int(raid.layout.get("ante_room", -1))
	if ar >= 0 and ar < rooms.size():
		var to: Vector2 = (rooms[ar] as Rect2).get_center() - global_position
		if to.length() > 1.0:
			facing = to.angle()
	_goal = facing


func _on_wake() -> void:
	var rooms: Array = raid.layout["rooms"]
	_room = rooms[int(raid.layout["warden_room"])]
	var rel: RaidRelish = raid.relish
	if rel != null and is_instance_valid(rel) and (rel.global_position - global_position).length() > 1.0:
		facing = (rel.global_position - global_position).angle()
	_goal = facing
	_next_attack = WardenLogic.period_beats(spec, phase)


func _phase_now() -> int:
	return WardenLogic.bellringer_phase(spec, hp / maxf(1.0, max_hp))


func _on_phase_change(old: int, new: int) -> void:
	super._on_phase_change(old, new)
	# a faster rhythm: pull a bash that is not yet telegraphed in to the new period
	var tell := _tell()
	var b := beat()
	if b < _next_attack - tell:
		_next_attack = minf(_next_attack, maxf(b + tell, _last_attack + WardenLogic.period_beats(spec, new)))


func _tell() -> float:
	return WardenLogic.attack_tell(spec.get("attack", {}))


## The bash arc's half-width now, in degrees: the phase's front, wider by `rush_half_deg` through a rush's
## tell and bash (the bot and the drawn arc read this).
func front_half_deg() -> float:
	if lane:
		return float(spec.get("attack", {}).get("rush_lane_half_deg", 20.0))
	var h := float(WardenLogic.shield_phase(spec, phase)["front_half_deg"])
	return h + (float(spec.get("attack", {}).get("rush_half_deg", 0.0)) if rushing else 0.0)


## The shield's own half-width, in degrees: the phase's front. A rush's wider arc and a lane's narrow one are
## the attack's (front_half_deg), never the shield's (D-d/E quality pass: hit_from read the attack's arc).
func shield_half_deg() -> float:
	return float(WardenLogic.shield_phase(spec, phase)["front_half_deg"])


## True when a point stands on the shield's side (a strike from there glances): the phase's front, a
## rush does not widen the shield.
func is_front(at: Vector2) -> bool:
	return WardenLogic.in_front(facing, global_position, at, shield_half_deg())


## A wits flank-role big undead posted at its back (WardenLogic.shield_pinned) pins it: no rush.
func _pinned() -> bool:
	var pts: Array = []
	var orbit := 0.0
	var wp: Dictionary = spec.get("weak_point", {})
	for a in raid.allies:
		if is_instance_valid(a) and a.alive and a.kind == "big" and WardenLogic.is_flanker(spec, a.wits):
			pts.append(a.global_position)
			orbit = maxf(orbit, radius + a.radius + float(wp.get("flank_gap_px", 3.0)))
	return WardenLogic.shield_pinned(facing, global_position, shield_half_deg(),
		pts, orbit + float(spec.get("attack", {}).get("pin_px", 30.0)))


## D-d/E 3c: `u` holds a post at its back (a wits flanker within its orbit + pin_px, off the shield: the
## stand that pins a rush, `_pinned` for one unit). RaidWardenRun.pack_target keeps such a big on the wall.
func posted(u: RaidUnit) -> bool:
	if not is_instance_valid(u) or not u.alive or u.kind != "big" or not WardenLogic.is_flanker(spec, u.wits):
		return false
	var wp: Dictionary = spec.get("weak_point", {})
	var orbit: float = radius + u.radius + float(wp.get("flank_gap_px", 3.0))
	return WardenLogic.shield_pinned(facing, global_position, shield_half_deg(),
		[u.global_position], orbit + float(spec.get("attack", {}).get("pin_px", 30.0)))


## Beats until the next bash's tell begins (negative while it shows).
func beats_to_tell() -> float:
	return (_next_attack - _tell()) - beat()


func telemetry() -> Dictionary:
	var out := {"hits": hits, "glances": glances, "flanks": flanks, "backs": backs, "role_hits": role_hits,
		"dmg_glance": snappedf(dmg_glance, 0.1), "dmg_flank": snappedf(dmg_flank, 0.1), "dmg_role": snappedf(dmg_role, 0.1),
		"bashes": bashes, "bash_units": bash_units, "bash_relish": bash_relish, "rushes": rushes, "pins": pins,
		"rush_relish": rush_relish}
	if int(spec.get("attack", {}).get("rush_lane_every", 0)) > 0:
		out["pin_breaks"] = pin_breaks   # only with the knob on, so the lines with it off stay byte-identical
	return out


## An undead's strike: glances on the shield, lands from outside it (the weak point's pips).
func hit_from(amount: float, attacker: Node2D) -> void:
	if not alive or not awake or attacker == null:
		return
	var zone := WardenLogic.shield_zone(facing, global_position, attacker.global_position, shield_half_deg(),
		float(spec.get("attack", {}).get("back_half_deg", 50.0)))
	var front := zone == "front"
	var dmg := amount * WardenLogic.shield_mult(spec, zone)
	var u := attacker as RaidUnit
	var big := u != null and u.kind == "big"
	hits += 1
	if big and WardenLogic.is_flanker(spec, u.wits):
		role_hits += 1
		dmg_role += dmg
	var lit0 := meter_lit()
	if front:
		glances += 1
		dmg_glance += dmg
		_glance_t = 0.0
		RaidSound.play("clang")
	else:
		flanks += 1
		if zone == "back":
			backs += 1
		dmg_flank += dmg
		_flank_t = 0.0
		_flank_at = (attacker.global_position - global_position).angle()
		RaidSound.play("flank", {"heavy": big})
	take_hit(dmg)
	if not front:
		mark_weak(lit0, meter_lit())   # the flank took these pips


func _step(delta: float) -> void:
	if _pack_step(delta):   # its pack runs: no bash tell until a beat after the last falls (one threat at a time)
		_next_attack = maxf(_next_attack, ceilf(beat()) + _tell() + float(spec.get("attack", {}).get("pack_rest_beats", 1.0)))
		_end_rush(spec.get("attack", {}))   # a horn over a rush's tell: that rush never lands
	var b := beat()
	var at: Dictionary = spec.get("attack", {})
	var ph := WardenLogic.shield_phase(spec, phase)
	var tell := _tell()
	planted = WardenLogic.is_tell(b, _next_attack, tell)
	_goal_t -= delta
	if _goal_t <= 0.0:
		_goal_t = float(at.get("face_repick_s", 0.15))
		_goal = _pick_goal(float(ph["front_half_deg"]), float(at.get("face_reach_px", 240.0)))
	# planted through the tell and on the bash frame itself: the lit arc is where the bash lands
	if WardenLogic.shield_turns(b, _next_attack, tell):
		facing = WardenLogic.turn_step(facing, _goal, float(ph["turn_deg_s"]), delta)
	if planted:
		if _tell_for != _next_attack:
			_tell_for = _next_attack
			RaidSound.play("tell")   # once per tell
			_begin_tell(at)
		var rel0: RaidRelish = raid.relish
		if rel0 != null and is_instance_valid(rel0) and rel0.alive and WardenLogic.bash_hits(facing, global_position,
				rel0.global_position, front_half_deg(), float(at.get("reach_px", 140.0)), rel0.radius):
			raid.danger_targeted()   # her edge warns while the lit arc covers her
	if b >= _next_attack:
		_bash(ph, at)
		_last_attack = _next_attack
		_next_attack = _last_attack + float(ph["period_beats"])
		_end_rush(at)
	# draw-only clocks and the flankers' rings (read nothing back)
	_glance_t += delta
	_flank_t += delta
	_bash_flash = maxf(0.0, _bash_flash - delta * 2.5)
	_update_flankers()


## The bearing to turn toward: the densest crowd of undead in reach (flankers left out), else Relish
## while she is in its room, else hold.
func _pick_goal(half_deg: float, reach_px: float) -> float:
	var units: Array = []
	for a in raid.allies:
		if is_instance_valid(a) and a.alive and not (a.kind == "big" and WardenLogic.is_flanker(spec, a.wits)):
			units.append(a.global_position)
	var g := WardenLogic.shield_goal(global_position, units, reach_px, half_deg, facing)
	if bool(g["ok"]):
		return float(g["angle"])
	var rel: RaidRelish = raid.relish
	if rel != null and is_instance_valid(rel) and rel.alive and _room.has_point(rel.global_position) \
			and (rel.global_position - global_position).length() > 1.0:
		return (rel.global_position - global_position).angle()
	return _goal


## As a bash tell starts: a rush unless a wits flanker at its back pins it (`attack.rush_px` 0: never).
## A rush lights a wider (`rush_half_deg`) and longer (`rush_px`) arc for its tell and bash: the arc the
## undead and Relish must leave. Its reach is written into attack.reach_px for those two beats, so every
## reader of the arc (the draw, her edge warning, the bot) sees the rush's.
func _begin_tell(at: Dictionary) -> void:
	if _base_reach < 0.0:
		_base_reach = float(at.get("reach_px", 140.0))
	pinned_tell = false
	pin_broke = false
	_bash_tells += 1
	if float(at.get("rush_px", 0.0)) <= 0.0:
		return
	var rel: RaidRelish = raid.relish
	var lever := WardenLogic.lever_on(int(spec.get("tier", 1)), bool(spec.get("first_dungeon", false)), wcfg())
	var aimable := float(at.get("rush_lane_half_deg", 0.0)) > 0.0 and rel != null and is_instance_valid(rel) and rel.alive \
		and lever and _room.has_point(rel.global_position) and rel.global_position.distance_to(global_position) > 1.0
	rushing = not _pinned()
	if not rushing and aimable and WardenLogic.lane_due(_bash_tells, int(at.get("rush_lane_every", 0)), lever):
		# D-e task 4: on every rush_lane_every-th tell the pin does not hold it: the lane comes for her (RUSH, no
		# PINNED); the pin still holds the rush off the other tells
		rushing = true
		pin_broke = true
		pin_breaks += 1
	pinned_tell = not rushing
	if rushing:
		rushes += 1
		if aimable:
			# D-d/E Step 4b: the rush aims at her: it turns to her as the tell begins and lights a lane
			# rush_lane_half_deg wide across its room (stepping out of it is the answer; a pin spares her)
			lane = true
			facing = (rel.global_position - global_position).angle()
			at["reach_px"] = minf(WardenLogic.lane_reach(_room, global_position),
				rel.global_position.distance_to(global_position) + float(at.get("rush_lane_over_px", 80.0)))
		else:
			at["reach_px"] = WardenLogic.rush_reach(_base_reach, float(at.get("rush_px", 0.0)),
				minf(_room.size.x, _room.size.y) * 0.5, float(at.get("rush_room_frac", 0.0)))
	else:
		pins += 1


func _end_rush(at: Dictionary) -> void:
	lane = false
	pin_broke = false
	if rushing:
		rushing = false
		at["reach_px"] = _base_reach


func _bash(ph: Dictionary, at: Dictionary) -> void:
	var half := front_half_deg()
	var reach := float(at.get("reach_px", 140.0))
	var shove := float(at.get("shove_px", 50.0))
	var dmg_u := float(at.get("dmg_unit", 10.0))
	bashes += 1
	_bash_flash = 1.0
	_bash_face = facing
	RaidSound.play("slam")
	var struck := 0
	for a in raid.allies.duplicate():
		if not is_instance_valid(a) or not a.alive:
			continue
		if WardenLogic.bash_hits(facing, global_position, a.global_position, half, reach, a.radius):
			struck += 1
			a.take_hit(dmg_u)
			if a.alive:
				a.global_position = raid.resolve_walls(WardenLogic.shove_point(facing, global_position, a.global_position, shove), a.radius)
	bash_units += struck
	var hit_rel := false
	var rel: RaidRelish = raid.relish
	if rel != null and is_instance_valid(rel) and rel.alive and WardenLogic.bash_strikes_relish(
			WardenLogic.bash_hits(facing, global_position, rel.global_position, half, reach, rel.radius), pinned_tell,
			WardenLogic.lever_on(int(spec.get("tier", 1)), bool(spec.get("first_dungeon", false)), wcfg())):
		hit_rel = true
		bash_relish += 1
		if rushing:
			rush_relish += 1
		rel.take_hit(float(at.get("dmg_relish", 12.0)), "rush" if rushing else "bash")
	if raid._standalone:
		print("RAID_WARDEN bash n=%d units=%d relish=%s rush=%s phase=%d facing=%.0f flanks=%d glances=%d frame=%d" % [bashes, struck,
			str(hit_rel), str(rushing), phase, rad_to_deg(facing), flanks, glances, Engine.get_process_frames()])


## Visual only, and last: the flank-role big undead now going round or posted, for their rings.
func _update_flankers() -> void:
	_flankers.clear()
	for a in raid.allies:
		if is_instance_valid(a) and a.alive and a.kind == "big" and not (a._flank as Dictionary).is_empty():
			_flankers.append(a)


# ------------------------------------------------------------------- draw ---
func _meter_y() -> float:
	return radius * 1.05 + float(wcfg().get("meter_gap_px", 16.0))


## The silhouette along the facing (local +x is the front): the shield arc, its plates, the boss, the
## helm and spine, and the open back dashed. Dormant: thin and unlit.
func _draw_glyph(col: Color) -> void:
	var r := radius
	var h := deg_to_rad(shield_half_deg())   # the shield, not the attack's arc
	draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)
	var dim := not awake
	if dim:
		draw_arc(Vector2.ZERO, r, -h, h, 28, col, 3.0)
	else:
		LineGlow.arc(self, Vector2.ZERO, r, -h, h, col, 6.5, 0.8, Palette.c("text", 0.9))
	# plates behind the shield: one per phase left beyond the first (the innermost falls away first)
	var n := rings_left()
	var plate := col
	plate.a *= 0.8
	for i in range(1, n):
		draw_arc(Vector2.ZERO, r - 7.0 * i, -h * 0.86, h * 0.86, 24, plate, 2.0)
	if drop_t >= 0.0 and n < (spec.get("phases", []) as Array).size():
		var f := drop_t / maxf(0.05, float(wcfg().get("phase_flash_s", 0.6)))
		draw_arc(Vector2(-12.0 * f, 0), r - 7.0 * n, -h * 0.86, h * 0.86, 24, Palette.c("vei", 0.8 * (1.0 - f)), 2.0)
	# the boss: a short spike out of the shield's centre, where it faces
	draw_line(Vector2(r + 2.0, 0), Vector2(r + 11.0, 0), col, 3.0)
	# the bearer behind it: a helm and a spine
	draw_arc(Vector2(-0.3 * r, 0), 0.26 * r, 0.0, TAU, 18, col, 2.2)
	draw_line(Vector2(-0.56 * r, 0), Vector2(-0.82 * r, 0), col, 2.2)
	# the open back (the back arc, where hits take the bonus): dashed, a different shape from the
	# shield as well as fainter; the sides between are bare
	var bh := deg_to_rad(float(spec.get("attack", {}).get("back_half_deg", 50.0)))
	var dashes := maxi(3, int(2.0 * bh * r / 12.0))
	var bcol := col
	bcol.a *= 0.85
	for k in dashes:
		var a0 := PI - bh + 2.0 * bh * float(k) / float(dashes)
		draw_arc(Vector2.ZERO, r, a0, a0 + 2.0 * bh / float(dashes) * 0.55, 4, bcol, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The sector between the shield and the bash's reach, along `face`, as a polygon (local, unrotated).
func _sector(face: float, h: float, r0: float, r1: float) -> PackedVector2Array:
	_pts.clear()
	var seg := 18
	for k in seg + 1:
		_pts.append(Vector2(r1, 0).rotated(face - h + 2.0 * h * float(k) / float(seg)))
	for k in range(seg, -1, -1):
		_pts.append(Vector2(r0, 0).rotated(face - h + 2.0 * h * float(k) / float(seg)))
	return _pts


func _draw_telegraph(ci: CanvasItem) -> void:
	var at: Dictionary = spec.get("attack", {})
	var reach := float(at.get("reach_px", 140.0))
	var h := deg_to_rad(front_half_deg())
	var fs := roundi(float(wcfg().get("label_px", 15)) / zoom())
	var dir := Vector2.RIGHT.rotated(facing)
	# the bash's reach, always faint, so the player learns where the front ends
	ci.draw_arc(Vector2.ZERO, reach, facing - h, facing + h, 32, Palette.c("danger", 0.22), 1.5)
	if planted:
		# the tell: the arc lit (brightening through it; steady under reduced motion), and the word
		var tell := _tell()
		var f := 1.0 if Pulse.reduced_motion else clampf((beat() - (_next_attack - tell)) / maxf(0.01, tell), 0.0, 1.0)
		ci.draw_colored_polygon(_sector(facing, h, radius + 4.0, reach), Palette.c("danger", 0.10 + 0.14 * f))
		LineGlow.arc(ci, Vector2.ZERO, reach, facing - h, facing + h, Palette.c("danger", 0.55 + 0.45 * f), 3.5, 0.7)
		for s in [-1.0, 1.0]:
			var e := Vector2.RIGHT.rotated(facing + h * s)
			ci.draw_line(e * (radius + 4.0), e * reach, Palette.c("danger", 0.8), 2.0)
		_word(ci, dir * (reach + fs * 0.9), "RUSH" if rushing else "BASH", fs, Palette.c("danger"))
		if not rushing and float(at.get("rush_px", 0.0)) > 0.0:
			_word(ci, Vector2(0, -radius * 2.0 - fs * 2.8), "PINNED", fs, Palette.c("undead"))   # the flankers hold it
		elif pin_broke:
			_word(ci, Vector2(0, -radius * 2.0 - fs * 2.8), "PIN BROKEN", fs, Palette.c("danger"))   # D-e task 4: the lane comes all the same
	elif _bash_flash > 0.0:
		# the bash's after-image along the arc it struck (a step, not a fade, under reduced motion)
		var a := 0.3 if Pulse.reduced_motion else 0.3 * _bash_flash
		ci.draw_colored_polygon(_sector(_bash_face, h, radius + 4.0, reach), Palette.c("danger", a))
	# the weak point at work: each flank-role big ringed, a line from its post into the wall's back
	for u in _flankers:
		if not is_instance_valid(u):
			continue
		var to: Vector2 = u.global_position - global_position
		if pin_broke and planted:
			# D-e task 4: their pin does not hold this tell: the ring and the line dashed (shape, not only colour)
			var rr := float(u.radius) + 6.0
			for k in 8:
				var a0 := TAU * float(k) / 8.0
				ci.draw_arc(to, rr, a0, a0 + TAU / 16.0, 4, Palette.c("undead", 0.8), 2.4)
			var n := 6
			for k in n:
				ci.draw_line(to.normalized() * radius + (to - to.normalized() * radius) * (float(k) / n),
					to.normalized() * radius + (to - to.normalized() * radius) * ((float(k) + 0.5) / n), Palette.c("undead", 0.7), 2.0)
		else:
			ci.draw_line(to.normalized() * radius, to, Palette.c("undead", 0.7), 2.0)
			LineGlow.ring(ci, to, float(u.radius) + 6.0, Palette.c("undead"), 2.4, 0.8)
	# words, clear of the crowd at its body (`label_out_px` out): the open back says FLANK until a flank
	# lands, then FLANKED where it landed; GLANCE over the shield (not over the lit arc's BASH)
	var hold := float(wcfg().get("shield_label_s", 0.8))
	var out := radius + float(wcfg().get("shield_label_out_px", 56.0)) + fs * 0.5
	if _flank_t < hold:
		_word(ci, Vector2.RIGHT.rotated(_flank_at) * out, "FLANKED", fs, Palette.c("undead"))
	else:
		_word(ci, -dir * out, "FLANK", fs, Palette.c("text_dim"))
	if _glance_t < hold and not planted:
		_word(ci, dir * out, "GLANCE", fs, Palette.c("text"))


## A word centred on `p` (canvas local), `px` tall.
func _word(ci: CanvasItem, p: Vector2, text: String, px: int, col: Color) -> void:
	var w := float(px) * 8.0
	ci.draw_string(ThemeDB.fallback_font, p + Vector2(-w * 0.5, float(px) * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, w, px, col)
