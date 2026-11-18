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
var _tell_cur := -1.0          # the current tell length in beats (see _tell); -1 until the first read
var _pres := {}                # draw only: the sleeping picture's cached geometry (_build_presence)
var _pres_z := -1.0            # the zoom it was built at
var _pres_n := -1              # and the meter pips
const PLATE_PAD := 4.0         # a name plate's margin around its text, in screen px

# break meter (pips; see WardenLogic.meter_bands)
var meter_bands: Array[float] = []
var meter_per := 4             # pips per band
var meter_n := 12              # pips in all
var meter_notch: Array[int] = []
var weak_marks := PackedByteArray()   # 1 on each pip a weak-point window took (index 0 = the first pip)
var weak_taken := 0            # pips taken inside weak-point windows, summed over the fight

# its pack (spec.pack, WardenLogic.pack_*; the Huntsman's hounds): none unless the spec has one
var horns := 0                 # horns sounded (packs called)
var pack: Array = []           # the current pack's units (pruned as they fall)
var pack_called := 0           # pack units called in all
var pack_down := 0             # of them, fallen
var pack_s := 0.0              # scene seconds a horn sounded or a pack stood
var horn_beat := -1.0          # the beat the pack comes in on while a horn sounds; -1: none
var horn_pts: Array[Vector2] = []   # where it comes in (drawn through the horn)
var pack_down_t := 99.0        # scene seconds since the last pack fell (draw: the labelled result)
var pack_broken := 0           # pack units its counter killed in one blow (MUFFLED / INTERCEPTED / FLANKED / SNUFFED)
var pack_scatters := 0         # packs that broke and left because no undead stood (D-d/E 3c)
var pack_scattered := 0        # their units (gone, not killed: no drops)
var pack_scatter_t := 99.0     # scene seconds since the last pack broke (draw: THE PACK BREAKS · WARD DOWN)
var _pack_words: Array = []    # draw only: [{pos, t}] where a pack unit fell to the counter


## This warden's current tell length in beats: the base (assist off: the same every frame) or the assist's longer
## one, latched so a LONGER WARNINGS flip applies from the next tell and never inside a running one. Every in-tell
## read and draw uses it; `_refresh_tell` (each _step, once `in_tell` is known) is the only writer after the first read.
func _tell() -> float:
	if _tell_cur < 0.0:
		_tell_cur = WardenLogic.attack_tell(spec.get("attack", {}))
	return _tell_cur


## Take the fresh read unless inside a tell (WardenLogic.latch_tell). `in_tell` is the caller's: a window of the
## current length (Bellringer, Shieldwall, Pyre-priest) or a locked lunge (Huntsman).
func _refresh_tell(in_tell: bool) -> void:
	_tell_cur = WardenLogic.latch_tell(_tell(), WardenLogic.attack_tell(spec.get("attack", {})), in_tell)


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


## Whether pip `i` is lit now. The meters are one prefix band (the strength left); the Pyre-priest's
## overrides it (its hp pips and its acolytes' pips are two bands). Both meter draws go through this.
func pip_lit(i: int) -> bool:
	return i < meter_lit()


## Mark the pips between `lit_after` and `lit_before` as taken by a weak-point window.
func mark_weak(lit_before: int, lit_after: int) -> void:
	mark_weak_range(lit_after, lit_before)


## Mark pips `[lo, hi)` as taken by a weak-point window.
func mark_weak_range(lo: int, hi: int) -> void:
	for i in range(maxi(0, lo), mini(hi, meter_n)):
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
	hp -= amount * WardenLogic.pack_ward(spec.get("pack", {}), pack_alive())
	flash = 1.0
	if hp <= 0.0:
		hp = 0.0
		_die()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if raid == null or raid._ended or not alive:
		return
	_breath_t += delta
	for i in range(_pack_words.size() - 1, -1, -1):   # draw-only clock (reads nothing back)
		_pack_words[i]["t"] = float(_pack_words[i]["t"]) + delta
		if float(_pack_words[i]["t"]) >= float(wcfg().get("pack_label_s", 1.2)):
			_pack_words.remove_at(i)
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


## Its pack's units still standing.
func pack_alive() -> int:
	var n := 0
	for u in pack:
		if is_instance_valid(u) and u.alive:
			n += 1
	return n


## One pack tick, for a subclass to call at the top of `_step` (WardenLogic.pack_*): at an hp gate it
## sounds a horn and, on the beat, calls its pack into the far side of its room from Relish. True while
## the horn sounds or any of the pack stands: the warden holds its own attack (one threat at a time).
func _pack_step(delta: float) -> bool:
	var pk: Dictionary = spec.get("pack", {})
	if pk.is_empty():
		return false
	var before := pack.size()
	var standing: Array = []
	for u in pack:
		if is_instance_valid(u) and u.alive:
			standing.append(u)
	pack_down += before - standing.size()
	pack = standing
	if before > 0 and pack.is_empty():
		pack_down_t = 0.0
		_on_pack_down()
		if raid._standalone:
			print("RAID_WARDEN pack down n=%d frame=%d" % [horns, Engine.get_process_frames()])
	if WardenLogic.pack_breaks(pack.size(), horn_beat >= 0.0, raid.has_allies()):
		_scatter_pack()
	if horn_beat < 0.0 and pack.is_empty() and WardenLogic.pack_due(pk, hp / maxf(1.0, max_hp), horns):
		horns += 1
		horn_beat = ceilf(beat() + float(pk.get("horn_beats", 1.0)))
		var room: Rect2 = (raid.layout["rooms"] as Array)[int(raid.layout["warden_room"])]
		var rel: RaidRelish = raid.relish
		var away: Vector2 = rel.global_position if rel != null and is_instance_valid(rel) else global_position
		horn_pts = WardenLogic.pack_spots(room, away, int(pk.get("size", 0)), float(pk.get("spot_inset_px", 50.0)),
			float(pk.get("spot_spread_px", 28.0)))
		RaidSound.play("tell")
		_on_horn()
		if raid._standalone:
			print("RAID_WARDEN horn n=%d hp=%.0f/%.0f frame=%d" % [horns, hp, max_hp, Engine.get_process_frames()])
	if horn_beat >= 0.0:
		pack_s += delta
		if beat() >= horn_beat:
			horn_beat = -1.0
			_loose_pack(pk)
		return true
	if not pack.is_empty():
		pack_s += delta
		return true
	pack_down_t += delta
	pack_scatter_t += delta
	return false


## On the horn's beat: the pack comes in where the horn showed. Its own living: hostile at once, at home
## in its room, massless, and they drop nothing (raid.on_unit_died reads `warden_pack`).
func _loose_pack(pk: Dictionary) -> void:
	var room: Rect2 = (raid.layout["rooms"] as Array)[int(raid.layout["warden_room"])]
	for p in horn_pts:
		var u: RaidUnit = raid.spawn_unit("enemy", str(pk.get("kind", "runner")), raid.resolve_walls(p, float(wcfg().get("pack_spawn_wall_px", 10.0))), true)
		u.mass = 0.0
		u.home_room = room
		u.warden_pack = true
		u._aggro = true
		pack.append(u)
		pack_called += 1
	if raid._standalone:
		print("RAID_WARDEN pack n=%d hounds=%d frame=%d" % [horns, horn_pts.size(), Engine.get_process_frames()])


## No undead stands (D-d/E 3c): the pack never turns on Relish, it breaks. Its units leave the fight (gone,
## not killed: nothing drops, no kill is counted), a horn still sounding calls no one, the ward drops and the
## warden fights her alone with its own attacks; the result shows over it (THE PACK BREAKS · WARD DOWN)
## and on the banner.
func _scatter_pack() -> void:
	var n := 0
	for u in pack:
		if is_instance_valid(u) and u.alive:
			RaidFx.ring(raid.fx_root, u.global_position, Palette.c("text_dim", 0.6), 22.0, 0.4, 2.0)
			u.scatter()
			n += 1
	pack = []
	horn_beat = -1.0
	horn_pts.clear()
	pack_scatters += 1
	pack_scattered += n
	pack_scatter_t = 0.0
	pack_down_t = 99.0   # (the breaking, not NAME DOWN, is the labelled result)
	_on_pack_down()
	if raid.hud != null:
		raid.hud.show_banner("THE PACK BREAKS — ward down", float(wcfg().get("pack_label_s", 1.2)) * 2.0, "undead")
	if raid._standalone:
		print("RAID_WARDEN pack scattered n=%d units=%d frame=%d" % [horns, n, Engine.get_process_frames()])


## The horn just sounded / the pack just fell (a subclass hook: the Huntsman drops a pending lunge and
## waits a tell before the next).
func _on_horn() -> void:
	pass


func _on_pack_down() -> void:
	pass


## A pack unit fell to the counter in one blow (RaidUnit._hit_enemy): counted, and its verb shown there.
func on_pack_broken(at: Vector2) -> void:
	pack_broken += 1
	_pack_words.append({"pos": at, "t": 0.0})
	if raid._standalone:
		print("RAID_WARDEN pack broken n=%d %s frame=%d" % [pack_broken, WardenLogic.pack_verb(spec), Engine.get_process_frames()])


## The pack's counts, for the measuring bot (AUTOPILOT_RESULT `pack`).
func pack_telemetry() -> Dictionary:
	return {"horns": horns, "called": pack_called, "down": pack_down, "broken": pack_broken, "pack_s": snappedf(pack_s, 0.01),
		"scatters": pack_scatters, "scattered": pack_scattered}


## Its pack in the world (tell -> counter -> labelled result): while the horn sounds, a `danger` ring at
## each point the pack comes in (closing on the beat; steady under reduced motion) and HORN over it;
## while the pack stands, "<NAME> · WARDED" over it; for twice `wardens.pack_label_s` after it breaks (no
## undead stood), THE PACK BREAKS · WARD DOWN; for `wardens.pack_label_s` after the last falls,
## "<NAME> DOWN" in `undead`. Sizes in screen px (divided by the zoom).
func _draw_pack(ci: CanvasItem) -> void:
	var pk: Dictionary = spec.get("pack", {})
	if pk.is_empty():
		return
	var fs := roundi(float(wcfg().get("label_px", 15)) / zoom())
	var top := Vector2(0, -radius * 2.0 - fs * 1.6)
	var nm := str(pk.get("name", "pack")).to_upper()
	var hold := float(wcfg().get("pack_label_s", 1.2))
	for w in _pack_words:
		if float(w["t"]) < hold:
			_pack_word(ci, (w["pos"] as Vector2) - global_position, WardenLogic.pack_verb(spec), fs, Palette.c("undead"))
	if horn_beat >= 0.0:
		var f := 1.0 if Pulse.reduced_motion else clampf(1.0 - (horn_beat - beat()) / maxf(0.01, float(pk.get("horn_beats", 1.0))), 0.0, 1.0)
		for p in horn_pts:
			var at: Vector2 = p - global_position
			LineGlow.ring(ci, at, (30.0 - 14.0 * f) / zoom(), Palette.c("danger", 0.55 + 0.4 * f), 2.6 / zoom(), 0.6)
		_pack_word(ci, top, "HORN · %d %s" % [horn_pts.size(), str(pk.get("name", "pack"))], fs, Palette.c("danger"))
	elif pack_alive() > 0:
		_pack_word(ci, top, nm + " · WARDED", fs, Palette.c("vei"))
	elif pack_scatter_t < hold * 2.0:
		_pack_word(ci, top, "THE PACK BREAKS · WARD DOWN", fs, Palette.c("undead"))
	elif pack_down_t < hold:
		_pack_word(ci, top, nm + " DOWN", fs, Palette.c("undead"))


func _pack_word(ci: CanvasItem, p: Vector2, text: String, px: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	ci.draw_rect(Rect2(p + Vector2(-tw * 0.5 - 4.0, -float(px) * 0.75), Vector2(tw + 8.0, float(px) * 1.25)), Palette.c("ground", 0.7))
	ci.draw_string(font, p + Vector2(-tw * 0.5, float(px) * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


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
	if not awake:
		_draw_presence()
	_draw_glyph(col)
	if awake:
		_draw_meter_row()


## A sleeping warden must read as a boss, not a floor mark (dormant only; static, matte): a plinth
## under the glyph, a boss ring with a tick per break pip and a dashed ring outside it, and name
## plates. In-world sizes are screen px (divided by the zoom; the text through a scaled transform).
func _draw_presence() -> void:
	var z := zoom()
	if _pres.is_empty() or not is_equal_approx(z, _pres_z) or meter_n != _pres_n:
		_build_presence(z)   # a sleeping warden's picture is static: rebuilt only when the zoom (or its pips) change
	var lw := 2.0 / z
	var vei_ring: Color = _pres["vei_ring"]
	draw_polyline(_pres["plinth"], _pres["plinth_col"], lw)
	draw_arc(Vector2.ZERO, _pres["rr"], 0.0, TAU, 64, vei_ring, lw)
	draw_multiline(_pres["ticks"], vei_ring, lw)
	for dash in _pres["dashes"]:
		draw_polyline(dash, vei_ring, lw)
	var plates: Array = _pres["plates"]
	var occ: Array = raid.hud.occluder_rects() if raid != null and raid.hud != null and raid.hud.has_method("occluder_rects") else []
	if RaidLogic.plate_hidden(_plate_screen_rect(plates[0], true), occ):
		# the name plate would sit under the HUD (checked each frame; the warden redraws every physics
		# frame): all of it goes below the ring, slid sideways if a HUD block covers that spot too
		var both: Dictionary = _pres["both"]
		var dx := RaidLogic.plate_nudge_x(_plate_screen_rect(both, false), occ, PLATE_PAD * 2.0)
		_draw_plate(both["lines"], (both["anchor"] as Vector2) + Vector2(dx / z, 0.0), false, _pres["plate_a"], both["size"])
		return
	for pl in plates:
		_draw_plate(pl["lines"], pl["anchor"], pl["above"], _pres["plate_a"], pl["size"])


## The screen rect a plate (`pl`, as _draw_plate draws it, above or below its anchor) covers at the camera's spot.
func _plate_screen_rect(pl: Dictionary, above: bool) -> Rect2:
	var sz: Vector2 = pl["size"]
	var a := get_global_transform_with_canvas() * (pl["anchor"] as Vector2)
	var h := sz.y + PLATE_PAD * 2.0
	return Rect2(a.x - sz.x * 0.5 - PLATE_PAD, a.y - h if above else a.y, sz.x + PLATE_PAD * 2.0, h)


## The sleeping picture's geometry at zoom `z`: the plinth's points, the ring's ticks and the dashed ring's
## arcs (the points draw_arc would build), the plates' text, anchors and measured sizes, and the colours.
func _build_presence(z: float) -> void:
	var pc: Dictionary = wcfg().get("presence", {})
	_pres_z = z
	_pres_n = meter_n
	var vei_ring := Palette.c("vei", float(pc.get("ring_alpha", 0.85)))
	# plinth: a flattened ellipse the warden stands on
	var prx := radius * float(pc.get("plinth_rx", 1.35))
	var pry := radius * float(pc.get("plinth_ry", 0.38))
	var pcy := radius * float(pc.get("plinth_y", 0.9))
	var pts := PackedVector2Array()
	var seg := 40
	for i in seg + 1:
		var a := TAU * float(i) / float(seg)
		pts.append(Vector2(cos(a) * prx, pcy + sin(a) * pry))
	# boss ring, a tick per break pip (meter_n) from the top, and a dashed ring outside it
	var rr := radius * float(pc.get("ring_mult", 1.9))
	var tick := float(pc.get("tick_px", 7.0)) / z
	var ticks := PackedVector2Array()
	for i in meter_n:
		var d := Vector2.UP.rotated(TAU * float(i) / float(maxi(1, meter_n)))
		ticks.append(d * rr)
		ticks.append(d * (rr + tick))
	var dr := rr + float(pc.get("dash_gap_px", 7.0)) / z
	var dashes: Array = []
	var n_dash := 48
	for i in n_dash:
		var a0 := TAU * float(i) / float(n_dash)
		var a1 := a0 + TAU / float(n_dash) * 0.5
		var arc := PackedVector2Array()
		for j in 4:   # draw_arc's own points: 4 of them, evenly from a0 to a1
			var th := a0 + (a1 - a0) * float(j) / 3.0
			arc.append(Vector2(cos(th), sin(th)) * dr)
		dashes.append(arc)
	# name plates, clear of the dashed ring
	var name_px := maxi(12, int(pc.get("name_px", 20)))
	var label_px := maxi(12, int(pc.get("label_px", 13)))
	var clear := dr + float(pc.get("plate_gap_px", 6.0)) / z
	var nm := str(spec.get("name", "")).to_upper()
	var above: Array = [["WARDEN", label_px, Palette.c("vei", 0.85)], [nm, name_px, Palette.c("vei")]]
	var below: Array = [["break it to take this fort", label_px, Palette.c("text")]]
	_pres = {"vei_ring": vei_ring, "plinth": pts, "plinth_col": Palette.c("vei", float(pc.get("plinth_alpha", 0.55))),
		"rr": rr, "ticks": ticks, "dashes": dashes, "plate_a": float(pc.get("plate_alpha", 0.8)),
		"plates": [
			{"lines": above, "anchor": Vector2(0.0, -clear), "above": true, "size": _plate_size(above)},
			{"lines": below, "anchor": Vector2(0.0, clear), "above": false, "size": _plate_size(below)},
		],
		"both": {"lines": above + below, "anchor": Vector2(0.0, clear), "size": _plate_size(above + below)}}


## A plate's text block size (the widest line, the lines' heights summed), in screen px.
func _plate_size(lines: Array) -> Vector2:
	var font := ThemeDB.fallback_font
	var w := 0.0
	var h := 0.0
	for ln in lines:
		w = maxf(w, font.get_string_size(str(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(ln[1])).x)
		h += font.get_height(int(ln[1]))
	return Vector2(w, h)


## Text lines (each [text, screen px, colour]) on a dark plate sized to them (`sz`, from _plate_size), centred
## on x = anchor.x, its bottom edge (above) or top edge (below) on the anchor. Drawn in screen px through a transform.
## `box` is the lines' measured size.
func _draw_plate(lines: Array, anchor: Vector2, above: bool, plate_a: float, box: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var pad := PLATE_PAD
	var w := box.x
	var h := box.y
	var z := zoom()
	var top := -(h + pad * 2.0) if above else 0.0
	draw_set_transform(anchor, 0.0, Vector2(1.0 / z, 1.0 / z))
	draw_rect(Rect2(-w * 0.5 - pad, top, w + pad * 2.0, h + pad * 2.0), Palette.c("ground", plate_a))
	var y := top + pad
	for ln in lines:
		var sz := int(ln[1])
		draw_string(font, Vector2(-w * 0.5, y + font.get_ascent(sz)), str(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, w, sz, ln[2])
		y += font.get_height(sz)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
## in screen px (divided by the zoom). The only text is the row's label on a plate under it (raid.json
## wardens.meter_label); the HUD carries the counts.
func _draw_meter_row() -> void:
	var z := zoom()
	var pr := float(wcfg().get("meter_pip_px", 3.5)) / z
	var step := pr * 2.7
	var gap := pr * 1.6
	var w := step * float(meter_n - 1) + gap * float(meter_notch.size())
	var x := -w * 0.5
	var y := _meter_y() + pr
	for i in meter_n:
		if meter_notch.has(i):
			var nx := x - step * 0.5 + gap * 0.5
			draw_line(Vector2(nx, y - pr * 2.0), Vector2(nx, y + pr * 2.0), Palette.c("vei", 0.85), 1.6 / z)
			x += gap
		var p := Vector2(x, y)
		if pip_lit(i):
			draw_circle(p, pr, Palette.c("vei"))
		elif weak_marks[i] != 0:
			draw_arc(p, pr, 0.0, TAU, 10, Palette.c("undead"), 1.4 / z)
			draw_line(p + Vector2(-pr, pr), p + Vector2(pr, -pr), Palette.c("undead"), 1.4 / z)
		else:
			draw_arc(p, pr * 0.8, 0.0, TAU, 10, Palette.c("text_dim", 0.6), 1.0 / z)
		x += step
	# what the row is, in words on a small ground plate under it (awake only: this runs only while awake)
	var label := str(wcfg().get("meter_label", ""))
	if label != "":
		var lpx := int(wcfg().get("meter_label_px", 13))
		var font := ThemeDB.fallback_font
		var box := Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lpx).x + 1.0, font.get_height(lpx))
		_draw_plate([[label, lpx, Palette.c("text")]], Vector2(0.0, y + pr * 2.0 + float(wcfg().get("meter_label_gap_px", 4.0)) / z), false,
			float(wcfg().get("presence", {}).get("plate_alpha", 0.8)), box)


## Telegraph layer (z 37): draws whatever the subclass shows for the next attack.
class Telegraph:
	extends Node2D
	var warden: RaidWarden = null

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if warden != null and is_instance_valid(warden) and warden.alive and warden.awake:
			warden._draw_pack(self)
			warden._draw_telegraph(self)
