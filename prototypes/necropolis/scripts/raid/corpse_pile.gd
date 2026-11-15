class_name RaidPile
extends Node2D
## A grey, matte corpse pile. Dead matter never glows. When Relish walks close
## the pile stirs: its mass converts into 2-4 essence orbs.
## Countable (VISUAL-LANGUAGE law 9): a small "xN" badge in the swarm-badge style, N = its mass
## rounded (the bodies in it), in matte text (`text_dim`, `dead_lit` while her light is on it). The
## first dungeon's massless teaching pile has no badge: it holds no bodies to count.

var raid: Node = null
var mass := 4.0
var look_mass := -1.0       # >= 0: size the lumps as if the pile held this (the massless first pile)

var _stirred := false
var _shrink := -1.0
var _lumps: Array = []
var _lit := false           # Relish's light falls on it (dead_lit, still matte)
var _badge := ""            # "xN", built once (the mass is fixed until it stirs)
var _base := 9.0


func _ready() -> void:
	z_index = 12
	add_to_group("raid_piles")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 13.0 + position.y * 7.0) + 11
	var base := clampf(9.0 + (mass if look_mass < 0.0 else look_mass) * 0.7, 9.0, 26.0)
	_base = base
	if roundi(mass) >= 1:
		_badge = "×%d" % roundi(mass)
	var n := rng.randi_range(3, 5)
	for i in n:
		_lumps.append({
			"off": Vector2(rng.randf_range(-base, base), rng.randf_range(-base * 0.6, base * 0.6)),
			"r": rng.randf_range(base * 0.4, base * 0.75),
			"shade": rng.randf_range(0.0, 1.0),
		})
	queue_redraw()


func _process(delta: float) -> void:
	if _shrink >= 0.0:
		_shrink += delta
		scale = Vector2.ONE * maxf(0.01, 1.0 - _shrink / 0.25)
		if _shrink >= 0.25:
			queue_free()
		return
	if raid == null:
		return
	var rel = raid.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive:
		if not _stirred:
			_set_lit(false)
		return
	var d: float = global_position.distance_to(rel.global_position)
	var rcfg: Dictionary = ConfigDb.data.get("raid", {})
	# Relish's violet falls on the dead near her (matte, never emits)
	if not _stirred:
		_set_lit(d <= float(rcfg.get("relish", {}).get("light_radius_px", 220.0)))
		if d <= float(rcfg.get("essence", {}).get("stir_radius_px", 90.0)):
			stir()


func _set_lit(on: bool) -> void:
	if on != _lit:
		_lit = on
		queue_redraw()


## The Pyre-priest's fire reached the pile (RaidPyrePriest._ignite): it loses `frac` of its mass,
## and burns away under `min_mass` (WardenLogic.pile_after_burn). The badge and the lumps follow the
## mass left. Returns the mass burned.
func burn(frac: float, min_mass: float) -> float:
	if _stirred or _shrink >= 0.0:
		return 0.0
	var left := WardenLogic.pile_after_burn(mass, frac, min_mass)
	var gone := mass - left
	mass = left
	if mass <= 0.0:
		remove_from_group("raid_piles")
		_shrink = 0.0   # it shrinks away (_process frees it)
		return gone
	_badge = "×%d" % roundi(mass) if roundi(mass) >= 1 else ""
	var k := clampf(9.0 + mass * 0.7, 9.0, 26.0) / maxf(1.0, _base)
	_base *= k
	for l in _lumps:
		l["off"] = (l["off"] as Vector2) * k
		l["r"] = float(l["r"]) * k
	queue_redraw()
	return gone


## The pile stirs: convert its mass into essence orbs.
func stir() -> void:
	if _stirred:
		return
	_stirred = true
	_set_lit(true)  # her light is on it as it stirs; it stays matte
	remove_from_group("raid_piles")
	if raid != null:
		var e: Dictionary = ConfigDb.data.get("raid", {}).get("essence", {})
		var n: int = raid.rng_combat.randi_range(int(e.get("stir_orbs_min", 2)), int(e.get("stir_orbs_max", 4)))
		n = maxi(1, n)
		for i in n:
			var ang: float = raid.rng_combat.randf() * TAU
			# the first dungeon's pile is massless (it mints no mass) and still stirs
			raid.spawn_mote(global_position + Vector2(raid.rng_combat.randf_range(4, 16), 0).rotated(ang),
				mass / n, false, Vector2(float(e.get("pop_speed_px", 85.0)), 0).rotated(ang))
	_shrink = 0.0


func _draw() -> void:
	# Dead is matte: flat fills only, never a glow stroke.
	var base := Palette.c("dead_lit" if _lit else "dead")
	var dark := base.darkened(0.2)
	for l in _lumps:
		draw_circle(l["off"], l["r"], base.lerp(dark, l["shade"]))
	# a couple of matte bone slivers
	var bone := base.lightened(0.3)
	draw_line(Vector2(-6, 2), Vector2(5, -3), bone, 2.0)
	draw_line(Vector2(-2, 5), Vector2(7, 4), bone, 2.0)
	if _badge != "" and _shrink < 0.0:
		# the count, about swarm.font_px on screen at any zoom (redrawn only when the light changes)
		var z := maxf(0.05, raid.cam.zoom.x) if raid != null and raid.cam != null else 1.0
		var fs := maxi(8, roundi(float(ConfigDb.data.get("raid", {}).get("swarm", {}).get("font_px", 16)) * 0.85 / z))
		var font := ThemeDB.fallback_font
		var tw := font.get_string_size(_badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(_base * 0.9, -_base * 0.75)
		var pad := 4.0 / z
		draw_rect(Rect2(at + Vector2(-pad, -fs), Vector2(tw + pad * 2.0, fs + pad)), Palette.c("ground", 0.8))
		draw_string(font, at, _badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c("dead_lit" if _lit else "text_dim"))
