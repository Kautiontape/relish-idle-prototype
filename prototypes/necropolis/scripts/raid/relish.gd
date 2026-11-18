class_name RaidRelish
extends Node2D
## Relish: a conduit, never a fighter. Click-to-move. If a lethal hit lands and
## any allied undead exists, the nearest ally is sacrificed in her place.
## Her safety is drawn as a state (dungeon only): with no phylactery charge left her halo breaks
## into dashes leaning to `danger`, faint at full hp and stronger as it falls (RaidLogic.exposed_level),
## and each Huntsman catch leaves a crack in her ring at the angle the lunge came from, for the run.

var raid: Node = null
var hp := 30.0
var max_hp := 30.0
var speed := 240.0
var radius := 13.0
var alive := true
var last_hit_src := ""   # what struck her last: "slam", "toll", "lunge", "bash", "rush", "fire", "hound", "pack" or "living" (the death card; never read by the sim)
var hits := {}           # measuring only (the bot's relish_hits; never read by the sim): blows that reached her, by source
var soaked := {}         # of them, the lethal ones an undead took in her place (the conduit rule)
var _struck_t := 99.0    # draw only: seconds since a blow that reached her hp (STRUCK cue)
var _struck_amt := 0.0
var _soaked_t := 99.0    # draw only: seconds since an undead died in her place (SOAKED cue)

var move_target := Vector2.ZERO
var _iframes := 0.0
var _flash := 0.0
var _t := 0.0
var _route: RaidRoute = null   # click-to-move goes through doorways
var _route_goal := Vector2.INF
var _catch_angles := PackedFloat32Array()      # one per Huntsman catch: where the lunge came from
var _cracks: Array[PackedVector2Array] = []    # each catch's jagged stroke, built once
const CRACK_SEP := 0.75                        # radians kept between two catch notches


func configure(p_raid: Node) -> void:
	raid = p_raid
	var r: Dictionary = ConfigDb.data.get("raid", {}).get("relish", {})
	hp = float(r.get("hp", 30.0))
	max_hp = hp
	speed = float(r.get("speed", 240.0))
	radius = float(r.get("radius", 13.0))
	move_target = position
	_route = RaidRoute.new(ConfigDb.data.get("raid", {}).get("combat", {}))
	z_index = 38  # above the trance dim (36): she stays at full strength


func _physics_process(delta: float) -> void:
	if raid == null or raid._ended or not alive:
		return
	_t += delta
	_struck_t += delta   # draw-only clocks (the sim never reads them)
	_soaked_t += delta
	_iframes = maxf(0.0, _iframes - delta)
	_flash = maxf(0.0, _flash - delta * 3.0)
	var d := move_target - global_position
	if d.length() > 6.0:
		var aim := d
		if _route != null and not raid.layout.is_empty():
			if move_target != _route_goal:
				_route_goal = move_target
				_route.reset()
			aim = _route.steer(raid.layout, global_position, move_target, radius, delta) - global_position
			if aim.length() < 1.0:
				aim = d
		var step := aim.normalized() * minf(speed * delta, d.length())
		var start := global_position
		var got: Vector2 = raid.resolve_walls(start + step, radius)
		if (got - start).length() < step.length() * 0.3:
			# blocked by a wall: slide along whichever axis still makes progress
			var gx: Vector2 = raid.resolve_walls(start + Vector2(step.x, 0), radius)
			var gy: Vector2 = raid.resolve_walls(start + Vector2(0, step.y), radius)
			got = gx if (gx - start).length() > (gy - start).length() else gy
		global_position = got
	else:
		global_position = raid.resolve_walls(global_position, radius)
	queue_redraw()


func take_hit(amount: float, src := "") -> void:
	if not alive or _iframes > 0.0:
		return
	if src != "":
		last_hit_src = src   # what struck last (the death card names it); a soaked hit counts too
	var key := src if src != "" else "wound"
	hits[key] = int(hits.get(key, 0)) + 1
	if hp - amount <= 0.0 and raid.has_allies() and RaidLogic.chain_soaks(src, raid.warden_run != null and raid.warden_run.tell_bypass):
		# THE CONDUIT RULE: the nearest allied undead dies in her place (not for a warden's tell-attack:
		# RaidLogic.chain_soaks, D-d/E Step 4b).
		soaked[key] = int(soaked.get(key, 0)) + 1
		_soaked_t = 0.0
		raid.sacrifice_nearest_ally()   # pings the danger edge
		_iframes = float(ConfigDb.data.get("raid", {}).get("relish", {}).get("iframes_s", 0.5))
		_flash = 1.0
		queue_redraw()
		return
	hp -= amount
	_flash = 1.0
	_struck_t = 0.0
	_struck_amt = amount
	raid.danger_hit()
	if hp <= 0.0:
		if raid.try_phylactery():
			queue_redraw()
			return
		alive = false
		raid.on_relish_died()
	queue_redraw()


## A Huntsman catch (dungeon): a notch broken out of her ring near the angle the lunge came from,
## kept for the run (the warden is freed when it dies, so the marks live here). Each notch is a gap
## in the ring, a thin crack into her, and a bold straight radial `danger` tick on a dark under-stroke
## that runs out across every ring round her (halo, trance, hp arcs are all tangential, so the ticks
## read as clock hands and count at the tier-4 zoom). A notch that would land within `CRACK_SEP` of
## an earlier one steps round the ring (lunges often come from the same side), so they never stack.
func mark_catch(from_angle: float) -> void:
	var a := RaidLogic.spread_angle(from_angle, _catch_angles, CRACK_SEP)
	var dir := Vector2.RIGHT.rotated(a)
	var side := dir.orthogonal()
	var ring := radius + 3.5
	var pts := PackedVector2Array()
	var steps := [[radius * 0.3, 0.0], [radius * 0.65, 2.5], [ring - 2.0, -2.0], [ring + 1.0, 0.0]]
	for st in steps:
		pts.append(dir * float(st[0]) + side * float(st[1]))
	_catch_angles.append(a)
	_cracks.append(pts)
	queue_redraw()


func catch_marks() -> int:
	return _cracks.size()


## The hit cue (D-d/E Step 4b), for `relish.hit_cue_s` after a blow. A blow that reached her hp (a warden's
## tell-attack, or anything once no undead stands): a jagged burst round her, sharp spikes on a dark
## under-stroke, and STRUCK −N, in `danger`. A blow an undead took in her place: a smooth closed ring and
## SOAKED, in `undead`. The most recent blow's cue shows. Shape and words read in greyscale; nothing moves,
## so reduced motion shows the same. (A blow that is not lethal always reaches her hp: the chain soaks only
## a lethal one, and never a warden's tell-attack.)
func _draw_hit_cue() -> void:
	var rw: Dictionary = ConfigDb.data.get("raid", {}).get("relish", {})   # the cue's words and its hold
	var hold := float(rw.get("hit_cue_s", 1.2))
	var z: float = maxf(0.05, raid.cam.zoom.x) if raid.cam != null else 1.0
	var fs := roundi(float(ConfigDb.data.get("raid", {}).get("wardens", {}).get("label_px", 15)) / z)
	var text := ""
	var col := Palette.c("danger")
	if _struck_t < hold and _struck_t <= _soaked_t:   # the most recent blow's cue
		var pts := PackedVector2Array()
		for k in 17:
			pts.append(Vector2.RIGHT.rotated(TAU * k / 16.0) * (radius + (17.0 if k % 2 == 0 else 7.0)))
		draw_polyline(pts, Palette.c("ground", 0.95), 6.0)
		draw_polyline(pts, Palette.c("danger"), 2.5)
		text = RaidLogic.word_fmt(rw, "word_struck", [roundi(_struck_amt)])
		col = Palette.c("danger")
	elif _soaked_t < hold:
		draw_arc(Vector2.ZERO, radius + 12.0, 0.0, TAU, 32, Palette.c("ground", 0.95), 6.0)
		draw_arc(Vector2.ZERO, radius + 12.0, 0.0, TAU, 32, Palette.c("undead"), 2.5)
		text = str(rw.get("word_soaked", ""))
		col = Palette.c("undead")
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(-tw * 0.5, -radius - 22.0 - float(fs) * 0.6)
	draw_rect(Rect2(p + Vector2(-4.0, -float(fs) * 0.9), Vector2(tw + 8.0, float(fs) * 1.25)), Palette.c("ground", 0.75))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Phylactery revive: back to `new_hp` with i-frames.
func revive(new_hp: float, iframes_s: float) -> void:
	hp = clampf(new_hp, 1.0, max_hp)
	_iframes = iframes_s
	_flash = 1.0
	queue_redraw()


func _draw() -> void:
	var violet := Palette.c("relish")
	var body := violet
	if _flash > 0.0:
		body = body.lerp(Palette.c("danger"), minf(0.8, _flash))
	# halo breathes on the Pulse beat (steady under reduced motion)
	var beat := 0.6 + 0.4 * Pulse.wave()
	var exposed := 0.0
	if raid != null and not raid.is_boss():
		exposed = RaidLogic.exposed_level(raid.phylactery_left(), hp / maxf(1.0, max_hp), ConfigDb.data.get("raid", {}))
	if exposed > 0.0:
		# no revive left: the halo breaks into dashes and leans to danger (shape and colour)
		var hc := violet.lerp(Palette.c("danger"), 0.35 + 0.65 * exposed)
		hc.a = 0.45 + 0.55 * exposed
		for k in 8:
			var a0 := TAU * k / 8.0 + 0.2
			LineGlow.arc(self, Vector2.ZERO, radius * 1.8, a0, a0 + TAU / 8.0 * 0.62, hc, 1.5 + 1.5 * exposed, 0.5 * beat)
	else:
		LineGlow.ring(self, Vector2.ZERO, radius * 1.8, violet, 1.5, 0.5 * beat)
	draw_circle(Vector2.ZERO, radius, body)
	LineGlow.ring(self, Vector2.ZERO, radius + 3.5, violet, 2.0, beat, Palette.c("text", 0.6))
	draw_circle(Vector2.ZERO, radius * 0.4, Palette.c("text", 0.9))
	for i in _cracks.size():
		# a Huntsman catch: a notch broken out of the ring, a bold tick through it on a dark under-stroke
		var ca := _catch_angles[i]
		var cd := Vector2.RIGHT.rotated(ca)
		draw_arc(Vector2.ZERO, radius + 3.5, ca - 0.4, ca + 0.4, 8, Palette.c("ground"), 6.0)
		draw_polyline(_cracks[i], Palette.c("danger"), 2.0)
		draw_line(cd * (radius + 2.0), cd * (radius + 31.0), Palette.c("ground", 0.95), 7.0)
		draw_line(cd * (radius + 2.0), cd * (radius + 30.0), Palette.c("danger"), 3.5)
	if raid != null and not raid.is_boss() and raid.carried_count() > 0:
		# empty carry slots: faint matte ticks, so "7 of 12" reads at a glance
		var e: Dictionary = ConfigDb.data.get("raid", {}).get("essence", {})
		var used := {}
		for c in raid.carried:
			used[c.carry_slot] = true
		for i in int(e.get("carry_max", 12)):
			if not used.has(i):
				var dir := Vector2.RIGHT.rotated(raid.carry_draw_angle(i))
				var orbit := float(e.get("carry_orbit_px", 24.0))
				draw_line(dir * (orbit - 2.0), dir * (orbit + 2.0), Palette.c("essence", 0.28), 1.5)
	if raid != null and not raid.is_boss() and raid.revived > 0:
		# one small cracked violet ring per spent phylactery; it does not come back
		var rc: Dictionary = ConfigDb.data.get("raid", {}).get("revive", {})
		for i in int(raid.revived):
			var rr: float = float(rc.get("mark_radius_px", 19.0)) + float(rc.get("mark_step_px", 4.0)) * i
			for j in 3:   # three shards with two gaps and a break: reads as cracked
				var a0: float = TAU * j / 3.0 + 0.7 * i + 0.2
				draw_arc(Vector2.ZERO, rr, a0, a0 + TAU / 3.0 - 0.55, 10, Palette.c("relish", 0.8), 1.5)
	if _iframes > 0.0:
		draw_arc(Vector2.ZERO, radius + 8.0, 0, TAU, 24, Palette.c("danger", 0.6), 2.0)
	if raid != null and not raid.is_boss():
		_draw_hit_cue()
	if hp < max_hp:
		_draw_hp_arc(violet)
	# trance focus / cooldown arc around her
	if raid != null and raid.trance != null:
		var tr = raid.trance
		if tr.state == RaidTrance.State.ACTIVE:
			var f: float = tr.focus_frac()
			LineGlow.arc(self, Vector2.ZERO, radius + 11.0, -PI * 0.5, -PI * 0.5 + TAU * f,
				violet, 3.0, 0.5, Palette.c("text"))
		elif tr.state == RaidTrance.State.COOLDOWN or tr.state == RaidTrance.State.LOCKOUT:
			# segmented (one per second of cooldown) so it reads by shape, not hue alone
			var segs := maxi(1, roundi(tr.cooldown_total))
			var left: float = tr.cooldown_frac() * segs
			var step := TAU / segs
			var gap := minf(0.2, step * 0.3)
			for i in segs:
				var fill := clampf(left - i, 0.0, 1.0)
				if fill > 0.0:
					var a0 := -PI * 0.5 + step * i + gap * 0.5
					LineGlow.arc(self, Vector2.ZERO, radius + 11.0, a0, a0 + (step - gap) * fill,
						Palette.c("cooldown"), 2.5, 0.5)


## The HP arc: a ring of segments (one per `hp_seg_hp` hp, so the damage is countable) that
## drains clockwise from the top as she is hurt; `relish`, turning `danger` at or below
## `hp_low_frac`. Empty segments stay as faint tracks.
func _draw_hp_arc(violet: Color) -> void:
	var c: Dictionary = ConfigDb.data.get("raid", {}).get("danger", {})
	var r := radius + float(c.get("hp_arc_gap_px", 18.0))
	var width := float(c.get("hp_arc_width", 3.0))
	var segs := clampi(ceili(max_hp / maxf(0.1, float(c.get("hp_seg_hp", 5.0)))), 1, 12)
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	var col := Palette.c("danger") if frac <= float(c.get("hp_low_frac", 0.34)) else violet
	var step := TAU / segs
	var gap := minf(0.16, step * 0.3)
	for i in segs:
		var a0 := -PI * 0.5 + step * i + gap * 0.5
		var a1 := -PI * 0.5 + step * (i + 1) - gap * 0.5
		var fill := clampf(frac * segs - i, 0.0, 1.0)
		draw_arc(Vector2.ZERO, r, a0, a1, 8, Palette.c("relish", 0.18), width)
		if fill > 0.0:
			LineGlow.arc(self, Vector2.ZERO, r, a0, a0 + (a1 - a0) * fill, col, width, 0.5)
