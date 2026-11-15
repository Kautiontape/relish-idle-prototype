class_name RaidHeldDoor
extends Node2D
## D-e task 6, the held door (raid.json held_door; NOTES-RAID "D-e task 6"). A set piece on one room of
## the route: a niche in its wall holds the cache (loot.json cache, the detour's) behind a door, and a plate
## lies beside the door. The door is open only while the big undead she sent stands on the plate; when she
## leaves the room that big is shut in behind it, out of the fight and out of her party, until the warden
## falls and the door unlocks (it rejoins). A death or a retreat loses it (RaidLogic.held_door_lost, the one
## place that rule lives). How she sends one: standing within order_px of the plate, a left click (the move
## click) on one of her party bigs sends it; a click on the plate sends the nearest. The bot uses the same
## click (`click`). Drawn by shape and words: the door barred when shut and dashed when open, the plate a
## square (dashed when empty, solid when held), a dashed tie from the plate to the door, and its label.
## Nothing moves under reduced motion or otherwise: there is no animation.

var raid: Node2D = null
var site := {}                 # LayoutLogic.held_door_site
var room := -1
var cache: Array = []          # the cache's pickups; out of raid_pickups (so nobody fetches them) while the door is shut
var cache_n := 0               # how many it held
var holder: RaidUnit = null    # the big sent to the plate (null: none, or it fell before it was shut in)
var holder_uid := ""
var holder_name := ""
var state := "unused"          # unused | sent (on its way) | held (on the plate) | shut | freed (the warden fell)
var is_open := false
var fell := 0                  # bigs sent that fell before they were shut in (they are in party_died)
var times := {}                # scene seconds: ordered, open, cache, shut, freed
var _t := 0.0                  # scene seconds (live physics steps)
var _entered := false          # Relish has stood in its room (the entry banner)
var _warden_fallen := false
var _hc := {}


## The door for this layout, carved into it, or null when the fort has none.
static func make(p_raid: Node2D, layout: Dictionary, tier: int, cfg: Dictionary) -> RaidHeldDoor:
	var s := RaidLogic.held_door_site(layout, tier, cfg)
	if s.is_empty():
		return null
	LayoutLogic.carve_held_door(layout, s)
	var d := RaidHeldDoor.new()
	d.raid = p_raid
	d.site = s
	d.room = int(s["room"])
	d._hc = cfg.get("held_door", {})
	d.z_index = 21   # over the walls (20), under the units (30+)
	return d


func _c(key: String, def: float) -> float:
	return float(_hc.get(key, def))


## The cache's relic pickups in the niche (RaidPopulate, after the living; no rng).
func place_cache(tier: int) -> void:
	var lc: Dictionary = ConfigDb.data.get("loot", {}).get("cache", {})
	cache_n = int((lc.get("relics_by_tier", {}) as Dictionary).get(str(clampi(tier, 1, 4)), 0))
	var sp := float(lc.get("spread_px", 18.0))
	var along: Vector2 = site["along"]
	for i in cache_n:
		var pk := RaidPickup.new()
		pk.raid = raid
		pk.kind = "relic"
		pk.cache = true
		pk.position = (site["cache"] as Vector2) + along * (sp * (float(i) - float(cache_n - 1) * 0.5))
		raid.units_root.add_child(pk)
		pk.remove_from_group("raid_pickups")   # behind the shut door: not on the floor yet
		cache.append(pk)


func cache_left() -> int:
	var n := 0
	for pk in cache:
		if is_instance_valid(pk) and not pk.is_queued_for_deletion():
			n += 1
	return n


## A big spent on the door that has not rejoined (sent, on the plate, or shut in).
func committed() -> bool:
	return state in ["sent", "held", "shut"]


## The party bigs standing in her party (the shut-in one is not).
func party_bigs() -> Array:
	var out: Array = []
	for a in raid.allies:
		if is_instance_valid(a) and a.alive and a.role == "party" and a.kind == "big":
			out.append(a)
	return out


## True when Relish can send a big now: no big spent on the door, the warden still standing, she stands
## within order_px of the plate, in its room, with a party big to send.
func can_order() -> bool:
	if state != "unused" or _warden_fallen or raid._ended:
		return false
	var rel: RaidRelish = raid.relish
	if rel == null or not is_instance_valid(rel) or not rel.alive:
		return false
	return rel.global_position.distance_to(site["plate"]) <= _c("order_px", 220.0) \
		and RaidLogic.room_of(raid.layout, rel.global_position) == room and not party_bigs().is_empty()


## The order (the human's left click, and the bot's): on a party big, that big; on the plate, the nearest
## party big to her. True when it sent one (the click is used up: she does not walk there).
func click(world_pos: Vector2) -> bool:
	if not can_order():
		return false
	var bigs := party_bigs()
	var pick: RaidUnit = null
	var bd := INF
	for a in bigs:
		var d := world_pos.distance_to(a.global_position)
		if d <= a.radius + 8.0 and d < bd:
			bd = d
			pick = a
	if pick == null and world_pos.distance_to(site["plate"]) <= _c("plate_px", 36.0) * 0.5 + 8.0:
		bd = INF
		for a in bigs:
			var d2: float = a.global_position.distance_to(raid.relish.global_position)
			if d2 < bd:
				bd = d2
				pick = a
	if pick == null:
		return false
	holder = pick
	holder_uid = pick.uid
	holder_name = _name_of(pick.uid)
	state = "sent"
	times["ordered"] = snappedf(_t, 0.01)
	if pick._route != null:
		pick._route.reset()
	queue_redraw()
	return true


func _name_of(uid: String) -> String:
	for e in raid.seed_data.get("party", []):
		if str(e.get("uid", "")) == uid:
			return str(e.get("name", uid))
	return uid


## The plate's point for the big sent to it while it holds it, else INF (RaidUnit's plate branch).
func plate_for(u: RaidUnit) -> Vector2:
	return site["plate"] if u == holder and (state == "sent" or state == "held") else Vector2.INF


## One live physics step (raid._physics_process, after the warden thread).
func tick(delta: float) -> void:
	_t += delta
	var rel: RaidRelish = raid.relish
	if rel == null or not is_instance_valid(rel):
		return
	var rroom := RaidLogic.room_of(raid.layout, rel.global_position)
	if rroom == room and not _entered:
		_entered = true
		if raid.hud != null:
			raid.hud.show_banner(RaidLogic.HELD_DOOR_ENTRY, 3.0, "vei")
	if (state == "sent" or state == "held") and (holder == null or not is_instance_valid(holder) or not holder.alive):
		# it fell before it was shut in (party_died has it): the door is free to use again
		holder = null
		holder_uid = ""
		holder_name = ""
		fell += 1
		state = "unused"
	if state == "sent" or state == "held":
		var on := holder.global_position.distance_to(site["plate"]) <= _c("hold_px", 18.0)
		state = "held" if on else "sent"
		if rroom >= 0 and rroom != room:
			_shut_in()
	_set_open(state == "held" or state == "freed")
	if not times.has("cache") and cache_n > 0 and cache_left() == 0:
		times["cache"] = snappedf(_t, 0.01)
	queue_redraw()


## She left the room: the big sent to the plate is shut in behind the door (out of her party and the fight:
## off `allies`, parked, never struck).
func _shut_in() -> void:
	state = "shut"
	times["shut"] = snappedf(_t, 0.01)
	raid.allies.erase(holder)
	holder.parked = true
	holder.global_position = site["park"]
	_set_open(false)
	if raid.hud != null:
		raid.hud.show_banner(RaidLogic.held_door_label("shut", holder_name), 3.0, "danger")


## The warden fell: the door unlocks and a shut-in big rejoins her party at the doorstep. With none shut in
## the door stays as it is, and no order is taken from here on.
func on_warden_died() -> void:
	_warden_fallen = true
	if state != "shut" or holder == null or not is_instance_valid(holder):
		return
	state = "freed"
	times["freed"] = snappedf(_t, 0.01)
	holder.parked = false
	holder.global_position = raid.resolve_walls(site["door_out"], holder.radius)
	raid.allies.append(holder)
	_set_open(true)


## Open or shut the door: the plug (the niche and its door) leaves or joins the walls, and the cache joins or
## leaves the floor's pickups. It never shuts on Relish: with her in the doorway it waits until she is out.
## Whatever else stands in the plug as it shuts steps out to the doorstep.
func _set_open(o: bool) -> void:
	if o == is_open:
		return
	var plug: Rect2 = site["plug"]
	var rel: RaidRelish = raid.relish
	if not o and rel != null and is_instance_valid(rel) and plug.grow(rel.radius).has_point(rel.global_position):
		return
	is_open = o
	var iw: Array = raid.layout["inner_walls"]
	if o:
		iw.erase(plug)
		if not times.has("open"):
			times["open"] = snappedf(_t, 0.01)
	else:
		iw.append(plug)
		for u in raid.allies + raid.enemies:
			if is_instance_valid(u) and u.alive and plug.grow(u.radius).has_point(u.global_position):
				u.global_position = raid.resolve_walls(site["door_out"], u.radius)
	for pk in cache:
		if is_instance_valid(pk) and not pk.is_queued_for_deletion():
			if o:
				pk.add_to_group("raid_pickups")
			else:
				pk.remove_from_group("raid_pickups")


## Party uids the door costs this run, for party_lost (RaidEndings.build_result).
func lost_uids(exit: String) -> Array:
	if holder_uid != "" and RaidLogic.held_door_lost(exit, committed()):
		return [holder_uid]
	return []


## The shut-in big's name while it is shut in ("" otherwise): the death card's row.
func shut_name() -> String:
	return holder_name if state == "shut" else ""


## The plate's prompt for the HUD ("" when she cannot send a big now).
func prompt_text() -> String:
	return RaidLogic.held_door_prompt() if can_order() else ""


## The HUD row while a big is spent on the door.
func row_text() -> String:
	return RaidLogic.held_door_row(state, holder_name)


## Measuring only (the bot's `door` dict, capture's): what the door did this run.
func telemetry() -> Dictionary:
	var spent := -1.0   # the time the door cost: scene seconds from the order to the cache in hand (-1: not both)
	if times.has("ordered") and times.has("cache"):
		spent = snappedf(float(times["cache"]) - float(times["ordered"]), 0.01)
	return {"room": room, "side": str(site["side"]), "detour_px": snappedf(float(site["detour_px"]), 0.1),
		"state": state, "big": holder_uid, "fell": fell, "cache": cache_n, "cache_left": cache_left(),
		"times": times.duplicate(), "spent_s": spent}


func _draw() -> void:
	if site.is_empty():
		return
	var z := maxf(0.05, raid.cam.zoom.x) if raid != null and raid.cam != null else 1.0
	var vei := Palette.c("vei")
	var inward: Vector2 = site["inward"]
	var along: Vector2 = site["along"]
	# the door: barred when shut, a dashed frame when open
	var dr: Rect2 = site["door"]
	if is_open:
		_dashed_rect(dr, Palette.c("vei", 0.7), 1.6 / z)
	else:
		draw_rect(dr, Palette.c("vei", 0.85))
		var long := along if absf(along.x) > 0.5 else Vector2(0, 1)
		var span := dr.size.x if absf(along.x) > 0.5 else dr.size.y
		for k in 5:
			var p := dr.position + long * (span * (float(k) + 0.5) / 5.0)
			var across := Vector2(0, dr.size.y) if absf(along.x) > 0.5 else Vector2(dr.size.x, 0)
			draw_line(p, p + across, Palette.c("ground"), 2.4 / z)
	# the plate, and its dashed tie to the door
	var ps := _c("plate_px", 36.0)
	var pc: Vector2 = site["plate"]
	var pr := Rect2(pc - Vector2.ONE * ps * 0.5, Vector2.ONE * ps)
	var held := state == "held"
	if held:
		draw_rect(pr, Palette.c("undead"), false, 2.6 / z)
		draw_rect(pr.grow(-ps * 0.22), Palette.c("undead", 0.8), false, 1.6 / z)
	else:
		_dashed_rect(pr, Palette.c("vei", 0.9), 1.8 / z)
	draw_dashed_line(pc - along * ps * 0.5, dr.get_center() + along * dr.size.dot(along.abs()) * 0.5, Palette.c("vei", 0.6), 1.4 / z, 6.0 / z)
	# the label, on the room side past the plate, on a dark plate of its own (contrast over the floor)
	var fs := roundi(float(_c("label_px", 14.0)) / z)
	var font := ThemeDB.fallback_font
	var at: Vector2 = (site["door_out"] as Vector2).lerp(pc, 0.5) + inward * (ps * 0.5 + 18.0 / z + fs)
	var lines: Array = []
	match state:
		"unused":
			lines = [["HELD DOOR", "vei"], ["a big on the plate holds it · it stays behind", "text"]]
		"sent", "held":
			lines = [[RaidLogic.held_door_label("held" if held else "sent", holder_name), "undead"]]
		"shut":
			lines = [[RaidLogic.held_door_label("shut", holder_name), "danger"]]
		"freed":
			lines = [[RaidLogic.held_door_label("freed", holder_name), "undead"]]
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var lh := float(fs) * 1.25
	var h := lh * lines.size()
	# off a north or south wall the block is centred on `at`, below or above it; off a west or east wall it
	# starts at `at` and runs into the room
	var top := at.y - h * (0.5 if absf(inward.y) < 0.5 else (0.0 if inward.y > 0.0 else 1.0))
	var left := at.x - w * 0.5 if absf(inward.x) < 0.5 else (at.x if inward.x > 0.0 else at.x - w)
	draw_rect(Rect2(left - 6.0 / z, top - 4.0 / z, w + 12.0 / z, h + 6.0 / z), Palette.c("ground", 0.82))
	for i in lines.size():
		var tw := font.get_string_size(str(lines[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(left + (w - tw) * 0.5, top + lh * (i + 1) - fs * 0.3), str(lines[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Palette.c(str(lines[i][1])))


func _dashed_rect(r: Rect2, col: Color, width: float) -> void:
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		draw_dashed_line(c[i], c[(i + 1) % 4], col, width, maxf(3.0, width * 3.0))
