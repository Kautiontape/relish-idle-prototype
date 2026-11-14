class_name BossGuard
extends RaidUnit
## One of Vei's guards in the break (vei_boss.gd): the uncleared fronts keep sending them
## (MECHANICS 6), and they hunt Relish and the undead. A living RaidUnit with one change to its
## pick: RaidUnit takes the nearer of Relish and the nearest undead; a guard goes for Relish and
## fights an undead only when one is within `block_px` (it is in the way). So the undead that stand
## round her are her shield, and the sacrifice chain is what a guard that reaches her costs.
## A backup's revive shockwave (`knock`) throws a guard back and it loses her for a moment.
## With `life_left` > 0 the guard falls back to the line when it runs out (vei.json guards.life_s):
## guards then never outnumber rate x life, so a dip in her army can't snowball into a pile-up.

var block_px := 70.0
var life_left := 0.0           # seconds until it falls back to the line (0: it stays until killed)
var _knock := Vector2.ZERO     # px/s while thrown back
var _knock_left := 0.0


## Thrown back from `from` to `dist` px over `secs`, then `recover_s` without a target or a strike.
func knock(from: Vector2, dist: float, secs: float, recover_s: float) -> void:
	var d := global_position - from
	var dir := d.normalized() if d.length() > 1.0 else Vector2.RIGHT.rotated(raid.rng_combat.randf() * TAU)
	_knock = dir * maxf(0.0, dist - d.length()) / maxf(secs, 0.01)
	_knock_left = secs
	_strike_t = maxf(_strike_t, secs + recover_s)
	_target = null
	_think_t = secs + recover_s   # no re-pick until it recovers: it wanders, she gets a moment


func _physics_process(delta: float) -> void:
	if life_left > 0.0 and raid != null and not raid._ended and alive:
		life_left -= delta
		if life_left <= 0.0:
			raid.recall_guard(self)
			return
	if _knock_left > 0.0 and raid != null and not raid._ended and alive:
		_knock_left -= delta
		global_position = raid.resolve_walls(global_position + _knock * delta, radius)
		queue_redraw()
		return
	super._physics_process(delta)


func _pick_target(_cfg: Dictionary) -> void:
	var rel = raid.relish
	var rel_ok: bool = rel != null and is_instance_valid(rel) and rel.alive
	var na = raid.nearest_ally_of(global_position)
	if na != null and (not rel_ok or global_position.distance_to(na.global_position) <= block_px):
		_target = na
	else:
		_target = rel if rel_ok else null
