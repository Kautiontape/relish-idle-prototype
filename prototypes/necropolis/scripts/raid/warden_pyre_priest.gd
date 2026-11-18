class_name RaidPyrePriest
extends RaidWarden
## The Pyre-priest (MECHANICS 5.3: burns corpses, denies essence; kill its acolytes first): stationary
## at its room's centre over a pyre, with WardenLogic.acolyte_count acolytes (RaidAcolyte children)
## posted behind it from the way in, off the swarm's natural path. While any acolyte lives it is
## warded: every hit lands at attack.ward_mult (WardenLogic.ward_mult), shown as a dashed line from
## each living acolyte into it. Every period_beats it lights burn areas on the ground tell_beats
## ahead (WardenLogic.burn_plan, fixed for the tell): its own on the densest essence or corpses in
## reach, plus one per living acolyte beyond the first, aimed at Relish. On the beat it burns them
## (`ignite`): loose motes inside are destroyed (BURNED −N; carried ones are safe), corpse piles
## lose attack.pile_burn_frac of their mass, undead inside take dmg_unit and Relish dmg_relish (the
## death card: "the Pyre-priest's fire"). Phase 1 while acolytes live; phase 2 (exposed) when the
## last falls; phase 3 at an hp gate: sooner and wider fires.
## The weak point (power): a big undead whose power meets the threshold kills an acolyte in one blow
## (SNUFFED, `snuff`; its pips on the meter are marked as the weak point's) and, fighting the priest,
## goes for the nearest living acolyte (RaidWardenRun.snuff_for).
## The break meter (WardenLogic.pyre_meter): its hp's pips (notched at the phase-3 gate), then
## `wardens.pyre_pips_per_acolyte` per acolyte on the right, spent as they fall.
## Silhouette, drawn as lines: a tall robe under a hood with a flame line rising above it (one band
## across the robe per phase left), the pyre's logs at its feet.

var acolytes: Array[RaidAcolyte] = []
var areas: Array[Vector2] = []  # the lit burn areas while a tell shows (sim state: fixed at the tell's start)
var area_r := 0.0               # their radius (the phase's burn_radius_px at the tell's start)
var lit := false                # a burn tell shows

# telemetry (the bot's `pyre` dict)
var snuffs := 0
var acolyte_kill_s: Array = []  # scene seconds from the wake to each acolyte's fall, in order
var burns := 0                  # burn beats with at least one area
var areas_total := 0            # areas burned, summed
var essence_burned := 0         # loose motes destroyed
var piles_burned := 0           # corpse piles a burn reached
var pile_mass_burned := 0.0
var burn_units := 0             # undead struck (one per undead per burn beat)
var burn_relish := 0            # burn beats that struck Relish (soaked or not)
var burn_soaked := 0            # of them: an ally died in her place (the sacrifice chain)
var dmg_warded := 0.0           # damage that landed through the ward
var dmg_exposed := 0.0          # damage that landed once exposed
var exposed_s := -1.0           # scene seconds from the wake to the last acolyte's fall (-1: never)

var _room := Rect2()
var _meter := {}
var _t0 := 0.0                  # the beat clock's reading at the wake (it starts below 0)
var _next_attack := 0.0
var _last_attack := 0.0
var _tell_for := -1.0           # the _next_attack beat whose areas are marked
var _told := false              # the first tell's "step off the fire" has been shown
var _burn_tells := 0            # burn tells marked (D-d/E Step 4b: every relish_area_every-th aims a fire at her)
var _first_tell_for := -1.0     # draw only: the _next_attack beat of that first tell
var _burnt: Array[Vector2] = [] # draw only: the last burn's areas (its after-image)
var _burnt_r := 0.0
var _burn_flash := 0.0          # draw only (1 -> 0)
var _ward_t := 99.0             # draw only: scene seconds since a hit landed through the ward
var _labels: Array = []         # draw only: {pos, text, key, t}
var _hunters: Array[Node2D] = []   # draw only: power big undead in the acolyte-hunting role now

var _pts := PackedVector2Array()   # scratch for the robe and flame


func configure(p_raid: Node2D, p_spec: Dictionary) -> void:
	super.configure(p_raid, p_spec)
	_meter = WardenLogic.pyre_meter(spec, int(wcfg().get("meter_pips", 12)), int(wcfg().get("pyre_pips_per_acolyte", 2)))
	meter_n = int(_meter["n"])
	meter_notch = _meter["notches"]
	weak_marks.resize(meter_n)
	weak_marks.fill(0)
	var rooms: Array = raid.layout.get("rooms", [])
	var wr := int(raid.layout.get("warden_room", -1))
	_room = rooms[wr] if wr >= 0 and wr < rooms.size() else Rect2(global_position - Vector2(200, 200), Vector2(400, 400))
	var at: Dictionary = spec.get("attack", {})
	var n := WardenLogic.acolyte_count(spec)
	var ar := float(at.get("acolyte_radius_px", 12.0))
	var posts := WardenLogic.acolyte_posts(global_position, _entry(), n, float(at.get("acolyte_ring_px", 160.0)),
		float(at.get("acolyte_arc_deg", 110.0)))
	for i in n:
		var a := RaidAcolyte.new()
		a.configure(self, i, float(at.get("acolyte_hp", 60.0)), ar)
		a.position = WardenLogic.leash_clamp(_room, posts[i], ar + 14.0) - global_position
		add_child(a)
		acolytes.append(a)


## Where the swarm comes in: the gap between the antechamber and this room (else the antechamber's
## centre, else the room's bottom edge).
func _entry() -> Vector2:
	var rooms: Array = raid.layout.get("rooms", [])
	var ar := int(raid.layout.get("ante_room", -1))
	if ar < 0 or ar >= rooms.size():
		return Vector2(_room.get_center().x, _room.end.y)
	var pad := float(raid.layout.get("wall_t", 30.0)) * 0.5 + 4.0
	for g in raid.layout.get("gaps", []):
		var grown := (g as Rect2).grow(pad)
		if grown.intersects(rooms[ar] as Rect2) and grown.intersects(_room):
			return (g as Rect2).get_center()
	return (rooms[ar] as Rect2).get_center()


func living() -> int:
	var n := 0
	for a in acolytes:
		if a.alive:
			n += 1
	return n


func meter_lit() -> int:
	return WardenLogic.pyre_meter_lit(_meter, living(), hp / maxf(1.0, max_hp))


func pip_lit(i: int) -> bool:
	return WardenLogic.pyre_pip_lit(_meter, i, living(), hp / maxf(1.0, max_hp))


## Beats until the next burn (its tell shows for the last tell_beats of them).
func beats_to_burn() -> float:
	return _next_attack - beat()


func _on_wake() -> void:
	_t0 = t
	_next_attack = WardenLogic.period_beats(spec, phase)
	for a in acolytes:
		a.queue_redraw()


func _phase_now() -> int:
	return WardenLogic.pyre_phase(spec, living(), hp / maxf(1.0, max_hp))


func _on_phase_change(old: int, new: int) -> void:
	super._on_phase_change(old, new)
	var tell := _tell()
	var b := beat()
	if b < _next_attack - tell:   # a faster rhythm: pull a burn not yet telegraphed in to the new period
		_next_attack = minf(_next_attack, maxf(b + tell, _last_attack + WardenLogic.period_beats(spec, new)))
	if old == 0 and new > 0 and exposed_s < 0.0:
		exposed_s = snappedf(t - _t0, 0.01)
		if raid.hud != null:
			raid.hud.show_banner("%s IS EXPOSED · its fire grows" % str(spec.get("name", "")).to_upper(),
				float(wcfg().get("wake_banner_s", 3.5)), "danger")


## Every hit on the priest: ward_mult of it while an acolyte lives.
func take_hit(amount: float) -> void:
	if not alive or not awake:
		return
	var m := WardenLogic.ward_mult(spec, living())
	if m < 1.0:
		dmg_warded += amount * m
		_ward_t = 0.0
	else:
		dmg_exposed += amount
	super.take_hit(amount * m)


## A blow on acolyte `a` (RaidAcolyte.hit_from): a big undead whose power meets the weak point snuffs
## it outright; any other blow takes `amount` of its hp.
func acolyte_hit(a: RaidAcolyte, amount: float, attacker: Node2D) -> void:
	if not a.alive or not alive or not awake:
		return
	var u := attacker as RaidUnit
	a.flash = 1.0
	if u != null and u.kind == "big" and WardenLogic.is_snuffer(spec, u.power):
		_acolyte_falls(a, true)
		return
	a.hp -= amount
	a.queue_redraw()
	if a.hp <= 0.0:
		_acolyte_falls(a, false)


func _acolyte_falls(a: RaidAcolyte, snuffed: bool) -> void:
	var living0 := living()
	a.alive = false
	a.snuffed = snuffed
	a.hp = 0.0
	a.queue_redraw()
	acolyte_kill_s.append(snappedf(t - _t0, 0.01))
	flash = 1.0
	if snuffed:
		snuffs += 1
		var pips := WardenLogic.pyre_snuff_pips(_meter, living0, living())
		mark_weak_range(pips.x, pips.y)   # the snuff took these acolyte pips
		RaidSound.play("snuff")
		_label(a.global_position + Vector2(0, -a.radius * 2.2), "SNUFFED", "undead")
		RaidFx.ring(raid.fx_root, a.global_position, Palette.c("undead"), 40.0, 0.45, 3.0)
	else:
		RaidFx.ring(raid.fx_root, a.global_position, Palette.c("vei", 0.8), 30.0, 0.4, 2.5)
	if raid._standalone:
		print("RAID_WARDEN acolyte n=%d snuffed=%s living=%d t=%.2f frame=%d" % [acolyte_kill_s.size(), str(snuffed), living(), t - _t0,
			Engine.get_process_frames()])


func telemetry() -> Dictionary:
	return {"acolytes": acolytes.size(), "acolyte_kill_s": acolyte_kill_s.duplicate(), "snuffs": snuffs, "exposed_s": exposed_s,
		"burns": burns, "areas": areas_total, "essence_burned": essence_burned, "piles_burned": piles_burned,
		"pile_mass_burned": snappedf(pile_mass_burned, 0.01), "burn_units": burn_units, "burn_relish": burn_relish,
		"burn_soaked": burn_soaked, "dmg_warded": snappedf(dmg_warded, 0.1), "dmg_exposed": snappedf(dmg_exposed, 0.1)}


## The undead's target near `pos` within `reach` of walking (RaidWardenRun.target_in): the nearest of
## the priest and its living acolytes (a tie goes to the priest), else null.
func target_near(pos: Vector2, reach: float, r: float):
	var best: Node2D = null
	var bd := INF
	if RaidLogic.warden_in_reach(raid.layout, pos, global_position, reach, r):
		best = self
		bd = pos.distance_to(global_position)
	for a in acolytes:
		if not a.alive:
			continue
		var d := pos.distance_to(a.global_position)
		if d < bd and RaidLogic.warden_in_reach(raid.layout, pos, a.global_position, reach, r):
			best = a
			bd = d
	return best


## The living acolyte nearest `from`, or null.
func nearest_acolyte(from: Vector2) -> RaidAcolyte:
	var pts: Array = []
	var live: Array[RaidAcolyte] = []
	for a in acolytes:
		if a.alive:
			pts.append(a.global_position)
			live.append(a)
	var i := WardenLogic.nearest_index(from, pts)
	return live[i] if i >= 0 else null


func _step(delta: float) -> void:
	if _pack_step(delta):   # its pack runs: no fire tell until a beat after the last falls (one threat at a time)
		_refresh_tell(false)   # no tell runs through a pack: the next one is laid with the assist's current setting
		_next_attack = maxf(_next_attack, WardenLogic.after_rest(beat(), _tell(), float(spec.get("attack", {}).get("pack_rest_beats", 1.0))))
	var b := beat()
	var k := WardenLogic.pyre_phase_knobs(spec, phase)
	_refresh_tell(WardenLogic.is_tell(b, _next_attack, _tell()))   # a flip applies from the next burn's tell, never inside this one
	var showing := WardenLogic.is_tell(b, _next_attack, _tell())
	if showing and _tell_for != _next_attack:
		_tell_for = _next_attack
		_mark_areas(float(k["burn_radius_px"]))
		if not areas.is_empty():
			RaidSound.play("tell")   # once per tell
	lit = showing and not areas.is_empty()
	var rel: RaidRelish = raid.relish
	if lit and rel != null and is_instance_valid(rel) and rel.alive and WardenLogic.in_burn(rel.global_position, areas, area_r, rel.radius):
		raid.danger_targeted()   # her edge warns while she stands in a lit area
	if b >= _next_attack:
		_ignite()
		_last_attack = _next_attack
		_next_attack = _last_attack + float(k["period_beats"])
	# draw-only clocks (read nothing back)
	_burn_flash = maxf(0.0, _burn_flash - delta * 2.0)
	_ward_t += delta
	var hold := float(wcfg().get("pyre_label_s", 0.9))
	for i in range(_labels.size() - 1, -1, -1):
		_labels[i]["t"] = float(_labels[i]["t"]) + delta
		if float(_labels[i]["t"]) >= hold:
			_labels.remove_at(i)
	_update_hunters()


## Visual only, and last: the power big undead hunting an acolyte now, for their rings and lines.
func _update_hunters() -> void:
	_hunters.clear()
	for a in raid.allies:
		if is_instance_valid(a) and a.alive and a.kind == "big" and not (a._snuff as Dictionary).is_empty():
			_hunters.append(a)


## The tell begins: where this beat's fire lands (WardenLogic.burn_plan over what lies in its room
## and reach now; fixed until the beat).
func _mark_areas(r: float) -> void:
	area_r = r
	var reach := float(spec.get("attack", {}).get("reach_px", 520.0))
	var from := global_position
	var motes: Array = []
	for o in raid.get_tree().get_nodes_in_group("raid_essence"):
		if is_instance_valid(o) and not o.absorbing and not o.carried and _reachable(o.global_position, from, reach):
			motes.append(o.global_position)
	var piles: Array = []
	for p in raid.get_tree().get_nodes_in_group("raid_piles"):
		if is_instance_valid(p) and not p._stirred and p._shrink < 0.0 and _reachable(p.global_position, from, reach):
			piles.append(p.global_position)
	var relp := Vector2.INF
	var rel: RaidRelish = raid.relish
	if rel != null and is_instance_valid(rel) and rel.alive and _reachable(rel.global_position, from, reach):
		relp = rel.global_position
	_burn_tells += 1
	var every := int(spec.get("attack", {}).get("relish_area_every", 0))
	var aim := every > 0 and _burn_tells % every == 0 \
		and WardenLogic.lever_on(int(spec.get("tier", 1)), bool(spec.get("first_dungeon", false)), wcfg())
	areas = WardenLogic.burn_plan(spec, phase, living(), from, {"motes": motes, "piles": piles, "relish": relp, "aim": aim})
	if not areas.is_empty() and not _told:
		_told = true
		_first_tell_for = _next_attack


func _reachable(p: Vector2, from: Vector2, reach: float) -> bool:
	return _room.has_point(p) and p.distance_to(from) <= reach


## The beat: burn the marked areas.
func _ignite() -> void:
	if _tell_for != _next_attack or areas.is_empty():
		areas.clear()
		lit = false
		return
	var at: Dictionary = spec.get("attack", {})
	burns += 1
	areas_total += areas.size()
	RaidSound.play("ignite")
	var per: Array[int] = []
	per.resize(areas.size())
	per.fill(0)
	# loose essence: destroyed (carried motes are safe; one being absorbed is already spent)
	var burned := 0
	for o in raid.get_tree().get_nodes_in_group("raid_essence"):
		if not is_instance_valid(o) or o.absorbing or o.carried:
			continue
		var k := _area_of(o.global_position, 0.0)
		if k < 0:
			continue
		per[k] += 1
		burned += 1
		o.remove_from_group("raid_essence")   # same-frame readers (the raise, the bot) no longer see it
		o.queue_free()
	essence_burned += burned
	# corpse piles: lose a share of their mass
	for p in raid.get_tree().get_nodes_in_group("raid_piles"):
		if not is_instance_valid(p) or p._stirred or p._shrink >= 0.0 or _area_of(p.global_position, 0.0) < 0:
			continue
		piles_burned += 1
		pile_mass_burned += p.burn(float(at.get("pile_burn_frac", 0.5)), float(at.get("pile_min_mass", 0.5)))
	# undead inside, once each
	var struck := 0
	for a in raid.allies.duplicate():
		if is_instance_valid(a) and a.alive and _area_of(a.global_position, a.radius) >= 0:
			struck += 1
			a.take_hit(float(at.get("dmg_unit", 6.0)))
	burn_units += struck
	var hit_rel := false
	var rel: RaidRelish = raid.relish
	if rel != null and is_instance_valid(rel) and rel.alive and _area_of(rel.global_position, rel.radius) >= 0:
		hit_rel = true
		burn_relish += 1
		var before: int = raid.allies.size()
		rel.take_hit(float(at.get("dmg_relish", 8.0)), "fire")
		if raid.allies.size() < before:
			burn_soaked += 1   # the chain spent an ally for her
	for i in areas.size():
		if per[i] > 0:
			_label(areas[i], "BURNED −%d" % per[i], "danger")
	_burnt = areas.duplicate()
	_burnt_r = area_r
	_burn_flash = 1.0
	if raid._standalone:
		print("RAID_WARDEN burn n=%d areas=%d burned=%d units=%d relish=%s phase=%d living=%d frame=%d" % [burns, areas.size(),
			burned, struck, str(hit_rel), phase, living(), Engine.get_process_frames()])
	areas.clear()
	lit = false


## The first marked area touching a target of radius `r` at `p`, or -1.
func _area_of(p: Vector2, r: float) -> int:
	for i in areas.size():
		if p.distance_to(areas[i]) <= area_r + r:
			return i
	return -1


func _label(p: Vector2, text: String, key: String) -> void:
	_labels.append({"pos": p, "text": text, "key": key, "t": 0.0})


# ------------------------------------------------------------------- draw ---
func _meter_y() -> float:
	return radius * 1.15 + float(wcfg().get("meter_gap_px", 16.0))


## The robe under a hood, a flame line rising from the hood (it sways; still under reduced motion),
## one band across the robe per phase left, the pyre's logs at its feet, and a dashed ward line to
## each living acolyte (bright while hits land through the ward).
func _draw_glyph(col: Color) -> void:
	var r := radius
	var dim := not awake
	# the ward lines first, under the robe
	var hold := float(wcfg().get("pyre_label_s", 0.9))
	var wcol := Palette.c("vei", 0.9 if _ward_t < hold else 0.55)
	if dim:
		wcol.a *= 0.5
	for a in acolytes:
		if not a.alive:
			continue
		var to := a.position
		var dist := to.length()
		if dist < r + a.radius + 4.0:
			continue
		var dir := to / dist
		var s := r * 0.7
		while s < dist - a.radius - 3.0:
			draw_line(dir * s, dir * minf(s + 9.0, dist - a.radius - 3.0), wcol, 2.4 if _ward_t < hold else 1.8)
			s += 15.0
	# the pyre: three matte logs at its feet (dead wood)
	var dc := Palette.c("dead_lit")
	draw_line(Vector2(-0.85 * r, 1.05 * r), Vector2(0.85 * r, 0.80 * r), dc, 3.0)
	draw_line(Vector2(-0.85 * r, 0.80 * r), Vector2(0.85 * r, 1.05 * r), dc, 3.0)
	draw_line(Vector2(-0.6 * r, 1.12 * r), Vector2(0.6 * r, 1.12 * r), dc, 3.0)
	# the robe: tall and narrow, its hem on the pyre
	_pts.clear()
	for v in [Vector2(-0.2, -0.5), Vector2(-0.62, 0.92), Vector2(0.62, 0.92), Vector2(0.2, -0.5)]:
		_pts.append((v as Vector2) * r)
	if dim:
		draw_polyline(_pts, col, 2.0)
	else:
		LineGlow.polyline(self, _pts, col, 2.8, 0.7, Palette.c("text", 0.9))
	# the hood
	draw_arc(Vector2(0, -0.62 * r), 0.3 * r, PI * 0.9, TAU + PI * 0.1, 18, col, 2.6)
	draw_arc(Vector2(0, -0.56 * r), 0.12 * r, 0.0, TAU, 10, col, 1.8)
	# a band across the robe per phase left (the lowest falls away at each phase)
	var n := rings_left()
	var band_col := col
	band_col.a *= 0.8
	for i in n:
		var y := (-0.15 + 0.3 * float(i)) * r
		var w := 0.2 + (y / r + 0.5) / 1.42 * 0.42   # the robe's half-width at y, inset
		draw_line(Vector2(-w * r * 0.85, y), Vector2(w * r * 0.85, y), band_col, 2.0)
	if drop_t >= 0.0 and n < (spec.get("phases", []) as Array).size():
		var f := drop_t / maxf(0.05, float(wcfg().get("phase_flash_s", 0.6)))
		var y2 := (-0.15 + 0.3 * float(n)) * r + 12.0 * f
		draw_line(Vector2(-0.4 * r, y2), Vector2(0.4 * r, y2), Palette.c("vei", 0.8 * (1.0 - f)), 2.0)
	# the flame over the hood: a teardrop line in `danger` (it is the fire), swaying on its own clock
	var sway := 0.0 if Pulse.reduced_motion or dim else sin(_breath_t * 5.0) * 0.12 * r
	var tip := Vector2(sway, -1.8 * r)
	var base := Vector2(0, -0.95 * r)
	_pts.clear()
	_pts.append(base + Vector2(-0.16 * r, 0))
	_pts.append(base + Vector2(-0.2 * r, -0.3 * r))
	_pts.append(tip)
	_pts.append(base + Vector2(0.2 * r, -0.3 * r))
	_pts.append(base + Vector2(0.16 * r, 0))
	var fcol := Palette.c("danger", 0.45 if dim else 1.0)
	if dim:
		draw_polyline(_pts, fcol, 2.0)
	else:
		LineGlow.polyline(self, _pts, fcol, 2.6, 0.7)
	draw_line(base + Vector2(0, -0.08 * r), base.lerp(tip, 0.55), fcol, 1.6)


## The lit areas (a ground circle you can see you are inside or not), the last burn's after-image,
## and the words: BURNED −N, SNUFFED, WARDED, "step off the fire" the first time, FIRE in each lit
## area under reduced motion (the fill brightens through the tell otherwise).
func _draw_telegraph(ci: CanvasItem) -> void:
	var fs := roundi(float(wcfg().get("label_px", 15)) / zoom())
	var me := global_position
	if lit:
		var tell := _tell()
		var f := 1.0 if Pulse.reduced_motion else clampf((beat() - (_next_attack - tell)) / maxf(0.01, tell), 0.0, 1.0)
		for c in areas:
			var p := c - me
			ci.draw_circle(p, area_r, Palette.c("danger", 0.10 + 0.14 * f))
			LineGlow.ring(ci, p, area_r, Palette.c("danger", 0.6 + 0.4 * f), 3.0, 0.7)
			# flame ticks round the rim (a shape, not only a colour)
			var ticks := 12
			for k in ticks:
				var d := Vector2.RIGHT.rotated(TAU * float(k) / float(ticks) + 0.26)
				ci.draw_line(p + d * (area_r - 2.0), p + d * (area_r + 7.0 + 3.0 * f), Palette.c("danger", 0.85), 2.0)
			if Pulse.reduced_motion:
				_word(ci, p, "FIRE", fs, Palette.c("danger"))
		if _first_tell_for == _next_attack and not areas.is_empty():
			# the first time: say what to do, under the area nearest her
			var at := areas[0]
			var rel: RaidRelish = raid.relish
			if rel != null and is_instance_valid(rel):
				var i := WardenLogic.nearest_index(rel.global_position, areas)
				at = areas[maxi(0, i)]
			_word(ci, at - me + Vector2(0, area_r + fs * 1.1), "step off the fire", fs, Palette.c("text"))
	elif _burn_flash > 0.0:
		var a := 0.3 if Pulse.reduced_motion else 0.3 * _burn_flash
		for c in _burnt:
			ci.draw_circle(c - me, _burnt_r, Palette.c("danger", a))
	# the weak point at work: each hunting big ringed, a line from it to the acolyte it is going for
	for u in _hunters:
		if not is_instance_valid(u) or (u._snuff as Dictionary).is_empty():
			continue
		var ac: Node2D = u._snuff["acolyte"]
		if not is_instance_valid(ac):
			continue
		var from: Vector2 = u.global_position - me
		ci.draw_line(from, ac.global_position - me, Palette.c("undead", 0.7), 2.0)
		LineGlow.ring(ci, from, float(u.radius) + 6.0, Palette.c("undead"), 2.4, 0.8)
	var hold := float(wcfg().get("pyre_label_s", 0.9))
	if _ward_t < hold and living() > 0:
		_word(ci, Vector2(0, -radius * 2.15 - fs * 0.6), "WARDED", fs, Palette.c("vei"))
	for l in _labels:
		_word(ci, (l["pos"] as Vector2) - me, str(l["text"]), fs, Palette.c(str(l["key"])))


## A word centred on `p` (canvas local), `px` tall, on a dark plate so it reads over the fire.
func _word(ci: CanvasItem, p: Vector2, text: String, px: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	ci.draw_rect(Rect2(p + Vector2(-tw * 0.5 - 4.0, -float(px) * 0.75), Vector2(tw + 8.0, float(px) * 1.25)), Palette.c("ground", 0.7))
	ci.draw_string(font, p + Vector2(-tw * 0.5, float(px) * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
