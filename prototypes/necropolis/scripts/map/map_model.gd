class_name MapModel
extends RefCounted
## The map's one read of the game: caches the views once per GameState.rev change and is
## shared by the routes, nodes, camera, HUD and sidebar. Names no autoload, so it runs headless.

const COVINGTON := "covington"
const VEI := "vei"

var state: GameState
var demo := false  # --lanes=demo: synthetic lanes instead of the view's (debug only)
var nodes_demo := false  # --nodes=demo: E2-only node states overlaid on the views (debug only)
var flip_cfg := {}  # realm.json "flip", for the held grace total (set by world_map)
var realm_cfg := {}  # realm.json: K (odds), readout.sign_eps, relish.travel_speed (set by world_map)
var idle_cap := 0.0  # economy.json worker.idle_cap: the workforce cap's idle part (set by world_map)
var rev := -1
var realm := {}
var relish := {}
var vei := {}
var hud := {}
var haul := {}  # view_town().haul: {target, current, convoys}
var job_slots := 0  # view_town().jobs' slots summed
var town_queue: Array = []  # view_town().queue ([] when empty)
var mill := {}  # the Bone Mill's view_town().buildings row's {starved, lever} ("" each when it is not built or not starved)
var queue_stall := {}  # the queue row that reads a starved reason (only a head that can never be afforded does), else {}
var backups := {}  # view_backups(): death is what a death costs now
var party := {}  # view_party()
var unit_names := {}  # big-undead uid -> name (view_big_undead)
var big_undead := {}  # big-undead uid -> its view_big_undead entry (a siege glyph's strokes)
var names := {}  # node id -> display name (Covington, Vei, every fort)
var villages: Array = []
var lanes: Array = []
var forts: Array = []
var forts_by_id := {}
var margins := {}  # held fort id -> "safe" | "thin" | "will_fall": the views' (stand-in: IdleLogic)
var clocks := {}  # held fort id -> {rate, fall_s}: the committed fall clocks (stand-in: IdleLogic)
var supports := {}  # the committed "WAR supports N of M": {n, m}
var projection := {}  # the dragged valve's IdleLogic.projection while the valve is being dragged, else {}
var margin_sig := ""  # the margins and clocks now shown (projected or committed): the nodes redraw when it changes
var raids: Array = []  # NextLogic.raid_set, once per refresh: [{fort, why}] ranked and capped; the ring's tag and the strip's raid rule

var built := {}  # SetpieceLogic.lot_levels of view_town().buildings: lot id -> {building_id, level}
var mount_rises: Array = []  # the builds that finished since the map was last up (a build done in town, or away): found by this model's first refresh; [] on a new game

var _villages_by_id := {}
var _last_read_s := -1.0e9
var _proj_read_s := -1.0e9  # real seconds of the last view_catalog read for projections
var _first_read := true
# A finished build's callout (SetpieceLogic: a finished build): the last real projection read per pending
# build, and the built levels as of the map's last refresh. Static, so they survive a scene swap to the
# town and back (MapHud's _next is the pattern); the game id says whose they are.
static var proj_store := {}  # "lot:level" -> {building_id, rates}
static var level_snap := {}  # lot id -> {building_id, level}, as of the last refresh of any map model
static var snap_game := ""
static var snap_set := false
static var _raid_why := {}  # fort id -> why, for raids (its keys are the last set's ids: raid_set's memory, kept across map mounts)
static var _raid_t := -1.0  # the game time of the last set: time going backwards is a new game, which clears _raid_why


func _init(game_state: GameState) -> void:
	state = game_state


## Re-reads every view when `state.rev` changed and model_refresh_min_s real seconds have
## passed (or `force`). Returns true when it re-read.
func refresh(force := false) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if not force:
		if state.rev == rev:
			return false
		if now - _last_read_s < float(MapLogic.cfg().get("model_refresh_min_s", 0.0)):
			return false
	_last_read_s = now
	rev = state.rev
	realm = state.view_realm()
	relish = state.view_relish()
	vei = state.view_vei()
	hud = state.view_hud()
	var town := state.view_town()
	haul = town.get("haul", {})
	job_slots = 0
	for j in town.get("jobs", []):
		job_slots += int(j.get("slots", 0))
	town_queue = town["queue"]
	_note_builds(town)
	var stall := stall_from(town)
	mill = stall["mill"]
	queue_stall = stall["queue_stall"]
	backups = state.view_backups()
	party = state.view_party()
	unit_names.clear()
	big_undead.clear()
	for b in state.view_big_undead().get("big_undead", []):
		unit_names[str(b["uid"])] = str(b["name"])
		big_undead[str(b["uid"])] = b
	villages = state.view_villages().get("villages", [])
	forts = realm.get("forts", [])
	forts_by_id.clear()
	names = {COVINGTON: "Covington", VEI: "Vei"}
	for f in forts:
		forts_by_id[f["id"]] = f
		names[str(f["id"])] = str(f["name"])
	_villages_by_id.clear()
	for v in villages:
		_villages_by_id[v["id"]] = v
	if nodes_demo:
		NodeLogic.demo_overlay(forts, vei, hud, relish, node_pos(COVINGTON), flip_cfg,
			float(realm_cfg.get("relish", {}).get("travel_speed", 0.0)))  # TODO(api E2): debug stand-in
		NodeLogic.demo_army(forts, party, big_undead, unit_names)  # TODO(api E2): debug stand-in
	if demo:
		lanes = MapLogic.demo_lanes(forts)  # TODO(api E2): debug stand-in
	else:
		lanes = MapLogic.lanes_from_views(state.view_lanes().get("lanes", []))
	margins = IdleLogic.committed_margins(forts)
	clocks = IdleLogic.committed_clocks(forts)
	supports = IdleLogic.committed_supports(hud)
	_refresh_raids()
	_update_margin_sig()
	return true


## Forgets the statics (a test's fresh start; a new game does this by its game id).
static func reset_statics() -> void:
	proj_store = {}
	level_snap = {}
	snap_game = ""
	snap_set = false


## The finished-build callout's inputs, once per refresh: the built levels against the last
## snapshot (the mount's diff, taken at this model's first refresh), the upgrades' projections the
## town view carries, and, on the slow cadence, the catalog's for the new builds pending.
func _note_builds(town: Dictionary) -> void:
	built = SetpieceLogic.lot_levels(town.get("buildings", []))
	var gid := str(hud.get("game_id", ""))
	var same := snap_set and snap_game == gid
	if not same:
		proj_store = {}  # another game's projections
	if _first_read:
		_first_read = false
		mount_rises = SetpieceLogic.rises(level_snap, built) if same else []
	level_snap = built.duplicate(true)
	snap_game = gid
	snap_set = true
	SetpieceLogic.note_upgrades(proj_store, town.get("buildings", []))
	read_projections(town)


## Reads view_catalog() for the projections of the new builds pending (queued or under construction),
## at most every projection_read_s of real time and only while one is pending: it is the costly read,
## and the sim refreshes the projections only while the catalog is being read (STATE-API §5.10), so
## the first read of a build comes back cold and the next one holds its value. `force` skips the clock.
func read_projections(town: Dictionary, force := false) -> void:
	if not SetpieceLogic.has_pending(town):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now - _proj_read_s < float(MapLogic.cfg().get("projection_read_s", 4.0)):
		return
	_proj_read_s = now
	SetpieceLogic.note_catalog(proj_store, SetpieceLogic.pending_new(town), state.view_catalog().get("buildings", []))


## The store stalls view_town() reports: {mill: {starved, lever} of the Bone Mill row ("" each when it
## is not built or not starved), queue_stall: the queue's head (queue[0]) when it reads a starved reason, else {}}.
static func stall_from(town: Dictionary) -> Dictionary:
	var mill_row := {"starved": "", "lever": ""}
	for b in town.get("buildings", []):
		if str(b.get("building_id", "")) == "bone_mill" and str(b.get("starved", "")) != "":
			mill_row = {"starved": str(b["starved"]), "lever": str(b.get("lever", ""))}
	var head := {}
	var queue: Array = town.get("queue", [])
	if not queue.is_empty() and str(queue[0].get("starved", "")) != "":
		head = queue[0]
	return {"mill": mill_row, "queue_stall": head}


## The raid set (NextLogic.raid_set) from these views, after the demo overlay: ranked from
## Relish's node, with the last set as its memory.
func _refresh_raids() -> void:
	var positions := {}
	for f in forts:
		positions[str(f["id"])] = node_pos(str(f["id"]))
	var now_t := float(hud.get("t", 0.0))
	if NextLogic.restarted(_raid_t, now_t):
		_raid_why.clear()
	_raid_t = now_t
	raids = NextLogic.raid_set(forts, _raid_why.keys(), _raid_from(), positions)
	_raid_why.clear()
	for r in raids:
		_raid_why[str(r["fort"]["id"])] = str(r["why"])


## Where the raid set measures distance from: her `target` while travelling (she is heading there),
## else the node she is `at`, else Covington.
func _raid_from() -> Vector2:
	var ids := [str(relish.get("at", ""))]
	if str(relish.get("state", "")) == "travelling":
		ids.push_front(str(relish.get("target", "")))
	for id in ids:
		if id != "" and has_node(id):
			return node_pos(id)
	return node_pos(COVINGTON)


## Why a fort is in the raid set ("refilled" or "first_clear"), or "" when it is not.
func raid_why(id: String) -> String:
	return str(_raid_why.get(id, ""))


## Publishes the dragged valve's projection: the fort chips and "N of M" read it until cleared.
func set_projection(p: Dictionary) -> void:
	projection = p
	_update_margin_sig()


func clear_projection() -> void:
	if projection.is_empty():
		return
	projection = {}
	_update_margin_sig()


## What a held fort's chip shows, {margin, rate, fall_s}: the projection's while one is set (the
## valve is being dragged), else the committed ones. Not held: {margin: "", rate: 0, fall_s: -1}.
func clock_of(id: String) -> Dictionary:
	var m := str(margins.get(id, ""))
	var ck: Dictionary = clocks.get(id, {})
	if projection.has("margins") and projection["margins"].has(id):
		m = str(projection["margins"][id])
	if projection.has("clocks") and projection["clocks"].has(id):
		ck = projection["clocks"][id]
	return {"margin": m, "rate": float(ck.get("rate", 0.0)), "fall_s": float(ck.get("fall_s", -1.0))}


## The margin a held fort shows (clock_of's).
func margin_of(id: String) -> String:
	return str(clock_of(id)["margin"])


## The "WAR supports N of M" now shown: the projection's while one is set, else the committed.
func supports_now() -> Dictionary:
	return projection["war_supports"] if projection.has("war_supports") else supports


## The chips' text as shown (margin, rate and coarse clock), so the nodes redraw when a chip's
## words change and not on every refresh of a raw fall_s.
func _update_margin_sig() -> void:
	var parts: Array = []
	for f in forts:
		if bool(f.get("held", false)):
			var ck := clock_of(str(f["id"]))
			parts.append("%s:%s:%s:%s" % [f["id"], ck["margin"], MapLogic.fmt_rate(float(ck["rate"])), IdleLogic.fmt_fall(float(ck["fall_s"]))])
	margin_sig = ",".join(parts)


## Whether they are winning: the one reading the top bar and Vei's node both draw. Odds, sign and
## drain_s come from view_hud, the backlog from view_vei; the demo overlay writes the same two.
func readout() -> Dictionary:
	return {"odds": float(hud.get("odds", 0.0)), "sign": int(hud.get("sign", 0)),
		"drain_s": float(hud.get("drain_s", -1.0)), "backlog": float(vei.get("backlog", 0.0))}


static func to_vec(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() >= 2 else Vector2.ZERO


func has_node(id: String) -> bool:
	if id == COVINGTON:
		return realm.has("covington")
	if id == VEI:
		return realm.has("vei")
	return forts_by_id.has(id) or _villages_by_id.has(id)


## World position of covington, vei, a fort or a village; Vector2.ZERO for an unknown id
## (check has_node first).
func node_pos(id: String) -> Vector2:
	if id == COVINGTON:
		return to_vec(realm.get("covington", {}).get("pos"))
	if id == VEI:
		return to_vec(realm.get("vei", {}).get("pos"))
	if forts_by_id.has(id):
		return to_vec(forts_by_id[id].get("pos"))
	if _villages_by_id.has(id):
		return to_vec(_villages_by_id[id].get("pos"))
	return Vector2.ZERO


## Route-graph hops from Covington, for Pulse's wave: Covington 0, forts 1, Vei 2.
func hops_of(id: String) -> float:
	if id == VEI:
		return 2.0
	if forts_by_id.has(id):
		return 1.0
	return 0.0


## The view_fort-shaped entry from view_realm ({} for an unknown id).
func fort(id: String) -> Dictionary:
	return forts_by_id.get(id, {})


func village(id: String) -> Dictionary:
	return _villages_by_id.get(id, {})


## The bounding box of everything drawn at a node (world px): every fort with its ring stack, Covington,
## the villages, and Vei with her whole backlog stack and her odds reading, each grown by
## fit_pad_px, with fit_label_px more below for the name under it. The camera's default fit frames this.
func content_rect() -> Rect2:
	var cfg := MapLogic.cfg()
	var pad := float(cfg["fit_pad_px"])
	var below := float(cfg["fit_label_px"])
	var box := Rect2()
	var first := true
	var items: Array = []
	for f in forts:
		items.append([to_vec(f["pos"]), NodeLogic.outer_radius("fort", int(f["tier"]), 0.0)])
	items.append([node_pos(COVINGTON), NodeLogic.outer_radius("covington", 0, 0.0)])
	for v in villages:
		items.append([to_vec(v["pos"]), float(NodeLogic.ncfg()["village_size_px"])])
	for it in items:
		var r := float(it[1]) + pad
		var rect := Rect2(it[0] - Vector2(r, r), Vector2(r * 2.0, r * 2.0 + below))
		box = rect if first else box.merge(rect)
		first = false
	if realm.has("vei"):
		var rect := _vei_rect()
		box = rect if first else box.merge(rect)
	return box


## Vei with her whole backlog stack, grown by fit_pad_px, and her reading either side (world px).
func _vei_rect() -> Rect2:
	var cfg := MapLogic.cfg()
	var r := NodeLogic.outer_radius("vei", 0, float(realm["vei"].get("radius", 0.0)), float(vei.get("backlog", 0.0))) + float(cfg["fit_pad_px"])
	var read := float(cfg["fit_vei_reading_px"])
	return Rect2(node_pos(VEI) - Vector2(r + read, r), Vector2((r + read) * 2.0, r * 2.0))


## What the default fit keeps clear of the panels (MapLogic.item_rect): every fort's footprint,
## its ring stack and under it the name, the first-dungeon line where it shows and a held fort's
## chip (screen px); then Vei's stack and reading (world px, as content_rect frames them).
func fit_items() -> Array:
	var n := NodeLogic.ncfg()
	var out: Array = []
	for f in forts:
		var second := not NodeLogic.name_tag(f).is_empty()
		var text_px := IdleLogic.name_bottom_px(second)
		if bool(f.get("held", false)):
			text_px = IdleLogic.chip_top_px(second) + IdleLogic.chip_height_px()
		out.append({"pos": to_vec(f["pos"]), "r": NodeLogic.outer_radius("fort", int(f["tier"]), 0.0),
			"below": MapLogic.fort_radius(int(f["tier"])) + float(n["label_off_px"]), "text_px": text_px,
			"half_px": float(MapLogic.cfg()["fit_label_half_px"])})
	if realm.has("vei"):
		out.append({"world": _vei_rect()})
	return out


func world_size() -> Vector2:
	return to_vec(realm.get("size"))


## Click targets for the camera: [{id, pos, radius}] with the drawn world-space radius.
func hit_targets() -> Array:
	var cfg := MapLogic.cfg()
	var out: Array = [
		{"id": COVINGTON, "pos": node_pos(COVINGTON), "radius": float(cfg["cov_hit_radius"])},
		{"id": VEI, "pos": node_pos(VEI), "radius": float(cfg["vei_hit_radius"])},
	]
	for f in forts:
		out.append({"id": f["id"], "pos": to_vec(f["pos"]),
			"radius": MapLogic.fort_radius(int(f["tier"])) + float(cfg["fort_hit_pad"])})
	for v in villages:
		out.append({"id": v["id"], "pos": to_vec(v["pos"]), "radius": float(cfg["village_hit_radius"])})
	return out
