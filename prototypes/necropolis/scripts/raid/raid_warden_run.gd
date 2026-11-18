class_name RaidWardenRun
extends RefCounted
## The dungeon's warden thread: builds the warden at the centre of its room, tracks Relish's room
## for the wake and the antechamber's last chance, opens the chest, and ends the run
## `warden_beaten`. A held fort, or the boss arena, has none of it (every method is a no-op).

var warden: RaidWarden = null
var tell_bypass := false       # the risk gate for this fort (WardenLogic.lever_on): tell-attacks skip the chain
var chest: RaidChest = null
var last_chance_done := false
var warden_name := ""   # the spec's name, kept after the warden dies (the death card names it)

var _raid: Node2D
var _room := -2


func _init(p_raid: Node2D) -> void:
	_raid = p_raid


func active() -> bool:
	return not _raid.is_boss() and not _raid.held and int(_raid.layout.get("warden_room", -1)) >= 0


## Build the warden (dungeon, not held). Dormant until Relish enters its room.
func build() -> void:
	if not active():
		return
	var rooms: Array = _raid.layout["rooms"]
	var fort: Dictionary = _raid.seed_data.get("fort", {})
	var w := RaidLogic.warden_spec({"id": str(fort.get("id", "")), "tier": _raid.fort_tier(),
		"archetype": str(_raid.seed_data.get("warden", {}).get("archetype", "")),
		"first_dungeon": bool(fort.get("first_dungeon", false))}, _raid.rcfg())
	var node: RaidWarden
	match str(w["archetype"]):
		"huntsman":
			node = RaidHuntsman.new()
		"bellringer":
			node = RaidBellringer.new()
		"shieldwall":
			node = RaidShieldwall.new()
		"pyre_priest":
			node = RaidPyrePriest.new()
		_:
			node = RaidWarden.new()   # an archetype with no attack yet is the inert base glyph
	node.position = (rooms[int(_raid.layout["warden_room"])] as Rect2).get_center()
	_raid.units_root.add_child(node)
	node.configure(_raid, w)
	warden_name = str(w.get("name", ""))
	warden = node
	tell_bypass = WardenLogic.lever_on(int(w["tier"]), bool(w["first_dungeon"]), _raid.rcfg().get("wardens", {}))


## Per physics frame: room tracking (wake, last chance).
func tick() -> void:
	if not active() or _raid.relish == null or not _raid.relish.alive:
		return
	var room := RaidLogic.room_of(_raid.layout, _raid.relish.position)
	if room < 0 or room == _room:
		return   # a doorway band belongs to no room
	_room = room
	if room == int(_raid.layout.get("ante_room", -1)) and not last_chance_done:
		last_chance()
	if room == int(_raid.layout["warden_room"]) and warden != null and is_instance_valid(warden):
		warden.wake()


## Bodyguard post for a party big undead while an awake Huntsman hunts: {point, relish} when `u`
## is a fast-enough big undead (speed_stat >= the weak point's threshold), else {}. None while its
## hounds run (D-d/E Step 4.1): the Huntsman holds its lunge then, so its speed bigs leave the post to
## hunt the hounds (pack_target, INTERCEPTED in one blow) and take it again when the last falls (a full
## tell before the next lunge). Held at her side, they let the hounds wipe the army away from her.
func guard_for(u: RaidUnit) -> Dictionary:
	if warden == null or not is_instance_valid(warden) or not warden.alive or not warden.awake \
			or str(warden.spec.get("archetype", "")) != "huntsman" or u.kind != "big" or warden.pack_alive() > 0:
		return {}
	var rel: RaidRelish = _raid.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive:
		return {}
	var th := float((warden.spec.get("weak_point", {}) as Dictionary).get("threshold", 1.0e9))
	if u.speed_stat < th:
		return {}
	var guards: Array = []
	for a in _raid.allies:
		if is_instance_valid(a) and a.alive and a.kind == "big" and a.speed_stat >= th:
			guards.append(a)
	var at: Dictionary = warden.spec.get("attack", {})
	return {"point": WardenLogic.guard_point(rel.global_position, warden.global_position,
		float(at.get("guard_px", 46.0)), maxi(0, guards.find(u)), guards.size(), float(at.get("guard_spread_px", 18.0))),
		"relish": rel.global_position}


## Flank post for a party big undead fighting an awake Shieldwall: {point, front, warden} when `u` is
## a big undead whose wits meet the weak point (WardenLogic.is_flanker) and whose target is the wall,
## else {}. `point` is where it walks next (round the orbit toward its post behind the wall: the
## flankers spread `flank_spread_deg` apart), `front` whether it stands on the shield's side now (it
## holds its blow there).
func flank_for(u: RaidUnit) -> Dictionary:
	if warden == null or u.kind != "big" or u._target != warden or not is_instance_valid(warden) \
			or not (warden is RaidShieldwall) or not warden.alive or not warden.awake:
		return {}
	var sw := warden as RaidShieldwall
	if not WardenLogic.is_flanker(sw.spec, u.wits):
		return {}
	var flankers: Array = []
	for a in _raid.allies:
		if is_instance_valid(a) and a.alive and a.kind == "big" and a._target == sw and WardenLogic.is_flanker(sw.spec, a.wits):
			flankers.append(a)
	var wp: Dictionary = sw.spec.get("weak_point", {})
	var ang := WardenLogic.flank_angle(sw.facing, maxi(0, flankers.find(u)), flankers.size(), float(wp.get("flank_spread_deg", 34.0)))
	var orbit: float = sw.radius + u.radius + float(wp.get("flank_gap_px", 3.0))
	return {"point": WardenLogic.flank_step(sw.global_position, u.global_position, ang, orbit, float(wp.get("flank_step_deg", 40.0))),
		"front": sw.is_front(u.global_position), "warden": sw}


## Acolyte-hunting post for a party big undead fighting an awake Pyre-priest: {acolyte} (the living
## acolyte nearest it) when `u` is a big undead whose power meets the weak point (WardenLogic.is_snuffer)
## and whose target is the priest or one of its acolytes, while any acolyte lives; else {}.
func snuff_for(u: RaidUnit) -> Dictionary:
	if warden == null or u.kind != "big" or not is_instance_valid(warden) or not (warden is RaidPyrePriest) \
			or not warden.alive or not warden.awake:
		return {}
	var pp := warden as RaidPyrePriest
	if u._target == null or not is_instance_valid(u._target) or not (u._target == pp or u._target is RaidAcolyte):
		return {}
	if not WardenLogic.is_snuffer(pp.spec, u.power):
		return {}
	var a := pp.nearest_acolyte(u.global_position)
	return {} if a == null else {"acolyte": a}


## The pack's counter (WardenLogic.pack_breaker): `u` is a big undead whose stat meets the awake warden's
## weak point, and the warden has a pack.
func breaks_pack(u: RaidUnit) -> bool:
	if warden == null or not is_instance_valid(warden) or not warden.alive or not warden.awake or u.kind != "big":
		return false
	var v := RaidLogic.unit_stat(u, str((warden.spec.get("weak_point", {}) as Dictionary).get("stat", "")))
	return WardenLogic.pack_breaker(warden.spec, v)


## The pack unit nearest `u` while a pack stands and `u` breaks it (its target), else null. At the
## Shieldwall (D-d/E 3c) pinning outranks the hunt: a wits big holding its post at the wall's back
## (RaidShieldwall.posted) keeps the wall as its target (its flank role, where it strikes the pack units
## that come to it: RaidUnit._pack_in_reach); the hunt goes to the pack breakers not posted there. (No
## clause for a bash tell: the wall holds its bash while its pack stands, so no tell shows then.)
func pack_target(u: RaidUnit):
	if not breaks_pack(u):
		return null
	if warden is RaidShieldwall and warden.pack_alive() > 0 \
			and (warden as RaidShieldwall).posted(u):
		return warden
	var best = null
	var bd := INF
	for e in warden.pack:
		if is_instance_valid(e) and e.alive:
			var d: float = u.global_position.distance_to(e.global_position)
			if d < bd:
				bd = d
				best = e
	return best


## The awake warden when it is within `reach` of walking from pos for an undead of `radius` (an enemy
## for the undead, on the same walking leash as the enemies), else null. A Pyre-priest offers the
## nearest of itself and its living acolytes (RaidPyrePriest.target_near).
func target_in(pos: Vector2, reach: float, radius := 0.0):
	if warden == null or not is_instance_valid(warden) or not warden.alive or not warden.awake:
		return null
	if warden is RaidPyrePriest:
		return (warden as RaidPyrePriest).target_near(pos, reach, radius)
	return warden if RaidLogic.warden_in_reach(_raid.layout, pos, warden.global_position, reach, radius) else null


## The antechamber's last chance (MECHANICS 5.3): trance ready now, the next completed raise
## starts no cooldown, and every loose mote in the room is lit again.
func last_chance() -> void:
	last_chance_done = true
	_raid.trance.grant_free()
	var wc: Dictionary = _raid.rcfg().get("wardens", {})
	var rect: Rect2 = (_raid.layout["rooms"] as Array)[int(_raid.layout["ante_room"])]
	var lit := 0
	for o in _raid.get_tree().get_nodes_in_group("raid_essence"):
		if is_instance_valid(o) and not o.absorbing and not o.carried and rect.has_point(o.global_position):
			o.ignite(float(wc.get("ignite_s", 0.8)))
			lit += 1
	# "N essence to bank": what lies loose in the room, capped by the carry room left; live while it shows
	_raid.hud.show_banner_live(func() -> String:
		return RaidLogic.last_chance_banner(RaidLogic.bankable(_loose_in(rect), _raid.carried_count(), _raid.rcfg())),
		float(wc.get("last_chance_banner_s", 3.5)), "essence")
	if _raid._standalone:
		print("RAID_WARDEN last_chance lit=%d" % lit)


## Loose essence in `rect` (neither carried nor being absorbed), for the last-chance banner.
func _loose_in(rect: Rect2) -> int:
	var n := 0
	for o in _raid.get_tree().get_nodes_in_group("raid_essence"):
		if is_instance_valid(o) and not o.absorbing and not o.carried and rect.has_point(o.global_position):
			n += 1
	return n


func on_warden_died(w: RaidWarden) -> void:
	var c := RaidChest.new()
	c.raid = _raid
	c.position = _raid.resolve_walls(w.position, 14.0)
	_raid.units_root.add_child(c)
	chest = c
	if _raid._dev != null:
		_raid._dev.on_warden_died(w)   # the measuring bot's last read of its counts
	warden = null
	if _raid.held_door != null:
		_raid.held_door.on_warden_died()   # the held door unlocks: a shut-in big rejoins (D-e task 6)


## Relish opened the chest: merge its loot into what was found, then the victory beat, then the
## run ends warden_beaten (loot is everything found plus the carried essence, as for a retreat).
## The win is pending from here: a window close inside the beat finishes it as the win.
func on_chest_opened(c: RaidChest) -> void:
	var e: RaidEndings = _raid.endings
	if e.ended:
		return
	_raid.found_loot = RaidLogic.merge_loot(_raid.found_loot, _raid.chest_loot())
	e.ended = true
	e.pending_exit = RaidLogic.pending_on("chest_opened")
	_raid.trance.force_end()
	var wc: Dictionary = _raid.rcfg().get("wardens", {})
	RaidFx.ring(_raid.fx_root, c.global_position, Palette.c("vei"), 120.0, 0.9, 5.0)
	RaidFx.ring(_raid.fx_root, _raid.relish.global_position, Palette.c("relish"), 80.0, 0.8, 4.0)
	if _raid._standalone:
		print("RAID_WARDEN chest opened")
	var cards: Array = []   # the clear card, freed with the win (a standalone result panel replaces it)
	var finish_win := func() -> void:
		if not is_instance_valid(_raid):
			return   # the scene was freed during the beat
		for k in cards:
			if is_instance_valid(k):
				k.queue_free()
		# the card's path finishes with the result frozen at chest open (e.win_result); the bot has none and builds it now
		e.finish(e.win_result if not e.win_result.is_empty() else e.build_result("warden_beaten"))   # finish guards a double: the card's click and its timer both land here
	if RaidAutopilot.enabled():   # the measuring bot never sees the card: the banner and the victory_s beat, as before
		_raid.hud.show_banner("THE WARDEN IS BEATEN · loot banked", float(wc.get("victory_s", 1.5)) + 1.0, "vei")
		_raid.get_tree().create_timer(float(wc.get("victory_s", 1.5))).timeout.connect(finish_win)
		return
	# everyone else: the clear card names what was won; a click/SPACE or `clear.card_s` ends it
	# the win is built ONCE, now (the chest's loot is merged): the card, the HUD and the emit all read this one dict,
	# so motes drifting into her slots during the card change nothing. A window close emits it too (close_request).
	e.win_result = e.build_result("warden_beaten")
	var won := RaidLogic.loot_counts(e.win_result["loot"])
	_raid.hud.on_clear(won)
	var card := RaidClearCard.new()
	_raid.hud.add_child(card)
	cards.append(card)
	card.setup(RaidLogic.clear_card_title(_raid.fort_name()), RaidLogic.clear_card_rows(warden_name, won))
	card.dismissed.connect(finish_win)
	_raid.get_tree().create_timer(float(_raid.rcfg().get("clear", {}).get("card_s", 12.0))).timeout.connect(finish_win)
