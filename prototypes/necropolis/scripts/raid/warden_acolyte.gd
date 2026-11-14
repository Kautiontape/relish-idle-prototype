class_name RaidAcolyte
extends Node2D
## One of the Pyre-priest's acolytes (MECHANICS 5.3: "kill its acolytes first"): a small living
## caster posted behind the priest (a child of it, freed with it). Undead target it like the warden
## (global_position, radius, take_hit, alive; RaidWardenRun.target_in offers it), but it is not in
## `raid.enemies`: no LIVING count, no ledger mass, no essence or ding when it falls. While it lives
## the priest is warded and it adds burn areas. A strike (`hit_from`) by a big undead whose power
## meets the weak point snuffs it in one blow; the priest decides (RaidPyrePriest.acolyte_hit).
## Drawn as a small hooded glyph in the warden's `vei` (a hood arc over a narrow robe, a head ring
## under the hood), dim while the priest sleeps; once fallen, a matte cross where it stood.

var priest: RaidPyrePriest = null
var index := 0
var hp := 60.0
var max_hp := 60.0
var radius := 12.0
var alive := true
var snuffed := false
var flash := 0.0               # draw only


func configure(p_priest: RaidPyrePriest, i: int, p_hp: float, p_radius: float) -> void:
	priest = p_priest
	index = i
	hp = p_hp
	max_hp = p_hp
	radius = p_radius


## Any undead's blow with no attacker known (the base RaidUnit path never calls this for an acolyte:
## it calls hit_from).
func take_hit(amount: float) -> void:
	hit_from(amount, null)


func hit_from(amount: float, attacker: Node2D) -> void:
	if not alive or priest == null or not is_instance_valid(priest) or not priest.awake or not priest.alive:
		return
	priest.acolyte_hit(self, amount, attacker)


func _process(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 4.0)
		queue_redraw()


# ------------------------------------------------------------------- draw ---
func _draw() -> void:
	var r := radius
	if not alive:
		# fallen: a matte cross where it stood (dead is matte everywhere)
		var dc := Palette.c("dead_lit" if snuffed else "dead")
		draw_line(Vector2(-r * 0.6, -r * 0.6), Vector2(r * 0.6, r * 0.6), dc, 2.0)
		draw_line(Vector2(-r * 0.6, r * 0.6), Vector2(r * 0.6, -r * 0.6), dc, 2.0)
		return
	var has_priest := priest != null and is_instance_valid(priest)
	var alpha := 1.0
	if not has_priest or not priest.awake:
		alpha = float(priest.wcfg().get("dormant_alpha", 0.32)) if has_priest else 0.32
	var col := Palette.c("vei", alpha)
	if flash > 0.0:
		col = col.lerp(Palette.c("text"), minf(0.85, flash))
	# the robe: a narrow trapezoid under the hood
	var robe := PackedVector2Array([Vector2(-0.35 * r, -0.2 * r), Vector2(-0.75 * r, r), Vector2(0.75 * r, r),
		Vector2(0.35 * r, -0.2 * r)])
	draw_polyline(robe, col, 2.0)
	# the hood over a head ring: the hooded caster reads at a glance
	draw_arc(Vector2(0, -0.45 * r), 0.55 * r, PI * 0.95, TAU + PI * 0.05, 14, col, 2.2)
	draw_arc(Vector2(0, -0.4 * r), 0.22 * r, 0.0, TAU, 10, col, 1.6)
	if hp < max_hp:
		var w := 1.6 * r
		var y := r + 5.0
		var frac := clampf(hp / max_hp, 0.0, 1.0)
		draw_line(Vector2(-w * 0.5, y), Vector2(w * 0.5, y), Palette.c("ground", 0.8), 2.0)
		draw_line(Vector2(-w * 0.5, y), Vector2(-w * 0.5 + w * frac, y), Palette.c("vei"), 2.0)
