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
var villages: Array = []
var lanes: Array = []
var forts: Array = []
var forts_by_id := {}

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
	villages = state.view_villages().get("villages", [])
	forts = realm.get("forts", [])
	forts_by_id.clear()
	for f in forts:
		forts_by_id[f["id"]] = f
	_villages_by_id.clear()
	for v in villages:
		_villages_by_id[v["id"]] = v
	if nodes_demo:
		NodeLogic.demo_overlay(forts, vei, hud, relish, node_pos(COVINGTON), flip_cfg)  # TODO(api E2): debug stand-in
	if demo:
		lanes = MapLogic.demo_lanes(forts)  # TODO(api E2): debug stand-in
	else:
		lanes = MapLogic.lanes_from_views(state.view_lanes().get("lanes", []), forts, hud)
	return true


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
