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
var rev := -1
var realm := {}
var relish := {}
var vei := {}
var hud := {}
var haul := {}  # view_town().haul: {target, current, convoys}
var backups := {}  # view_backups(): death is what a death costs now
var party := {}  # view_party()
var unit_names := {}  # big-undead uid -> name (view_big_undead)
var names := {}  # node id -> display name (Covington, Vei, every fort)
var villages: Array = []
var lanes: Array = []
var forts: Array = []
var forts_by_id := {}
var margins := {}  # held fort id -> "safe" | "thin" | "will_fall": the views' (stand-in: IdleLogic)
var supports := {}  # the committed "WAR supports N of M": {n, m}
var projection := {}  # the dragged valve's IdleLogic.projection while the valve is being dragged, else {}
var margin_sig := ""  # the margins now shown (projected or committed): the nodes redraw when it changes

var _villages_by_id := {}
var _last_read_s := -1.0e9


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
	haul = state.view_town().get("haul", {})
	backups = state.view_backups()
	party = state.view_party()
	unit_names.clear()
	for b in state.view_big_undead().get("big_undead", []):
		unit_names[str(b["uid"])] = str(b["name"])
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
		NodeLogic.demo_overlay(forts, vei, hud, relish, node_pos(COVINGTON), flip_cfg)  # TODO(api E2): debug stand-in
	if demo:
		lanes = MapLogic.demo_lanes(forts)  # TODO(api E2): debug stand-in
	else:
		lanes = MapLogic.lanes_from_views(state.view_lanes().get("lanes", []))
	margins = IdleLogic.committed_margins(forts, hud)
	supports = IdleLogic.committed_supports(hud, forts)
	_update_margin_sig()
	return true


## Publishes the dragged valve's projection: the fort chips and "N of M" read it until cleared.
func set_projection(p: Dictionary) -> void:
	projection = p
	_update_margin_sig()


func clear_projection() -> void:
	if projection.is_empty():
		return
	projection = {}
	_update_margin_sig()


## The margin a held fort shows: the projection's while one is set, else the committed one.
func margin_of(id: String) -> String:
	if projection.has("margins") and projection["margins"].has(id):
		return str(projection["margins"][id])
	return str(margins.get(id, ""))


## The "WAR supports N of M" now shown: the projection's while one is set, else the committed.
func supports_now() -> Dictionary:
	return projection["war_supports"] if projection.has("war_supports") else supports


func _update_margin_sig() -> void:
	var parts: Array = []
	for f in forts:
		if bool(f.get("held", false)):
			parts.append("%s:%s" % [f["id"], margin_of(str(f["id"]))])
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
		var r := NodeLogic.outer_radius("vei", 0, float(realm["vei"].get("radius", 0.0)), float(vei.get("backlog", 0.0))) + pad
		var read := float(cfg["fit_vei_reading_px"])
		var rect := Rect2(node_pos(VEI) - Vector2(r + read, r), Vector2((r + read) * 2.0, r * 2.0))
		box = rect if first else box.merge(rect)
	return box


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
