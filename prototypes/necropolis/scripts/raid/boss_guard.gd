class_name BossGuard
extends RaidUnit
## One of Vei's guards in the break (vei_boss.gd): the uncleared fronts keep sending them
## (MECHANICS 6), and they hunt Relish and the undead. A living RaidUnit with one change to its
## pick: RaidUnit takes the nearer of Relish and the nearest undead; a guard goes for Relish and
## fights an undead only when one is within `block_px` (it is in the way). So the undead that stand
## round her are her shield, and the sacrifice chain is what a guard that reaches her costs.

var block_px := 70.0


func _pick_target(_cfg: Dictionary) -> void:
	var rel = raid.relish
	var rel_ok: bool = rel != null and is_instance_valid(rel) and rel.alive
	var na = raid.nearest_ally_of(global_position)
	if na != null and (not rel_ok or global_position.distance_to(na.global_position) <= block_px):
		_target = na
	else:
		_target = rel if rel_ok else null
