class_name DebugCmds
extends RefCounted
## The debug commands' bodies (STATE-API 4.6), static only, taking the GameState they act on: grant,
## set_state, skip_time and load_fixture, and the validators and minting they use. GameState keeps the
## public cmd_debug_* methods, with their signatures, and forwards here.


static func is_num(gs: GameState, v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


static func is_count(gs: GameState, v: Variant) -> bool:
	return is_num(gs, v) and float(v) >= 0.0 and float(v) == floorf(float(v))


static func mint_husk(gs: GameState) -> String:
	var h := {
		"uid": gs._mint_uid("h"), "kind": GameState.HUSK_KINDS[gs.rng.randi_range(0, GameState.HUSK_KINDS.size() - 1)],
		"rarity": GameState.RARITIES[gs.rng.randi_range(0, GameState.RARITIES.size() - 1)],
	}
	gs.husks.append(h)
	return h["uid"]


static func mint_remnant(gs: GameState) -> String:
	var r := {
		"uid": gs._mint_uid("r"), "aspect": GameState.STATS[gs.rng.randi_range(0, GameState.STATS.size() - 1)],
		"rarity": GameState.RARITIES[gs.rng.randi_range(0, GameState.RARITIES.size() - 1)],
		"magnitude": gs.rng.randi_range(1, 5),
	}
	gs.remnants.append(r)
	return r["uid"]


## Its role is SlabLogic's for its highest stat (town.json slab.role_by_stat; ties go in STATS
## order), so a granted big undead carries a role id the town and dungeon scenes know.
static func mint_big_undead(gs: GameState) -> String:
	var uid := gs._mint_uid("u")
	var st := {}
	var top := ""
	for s in GameState.STATS:
		st[s] = gs.rng.randf_range(1.0, 10.0)
		if top == "" or st[s] > st[top]:
			top = s
	var roles: Variant = gs._sec("town", "slab").get("role_by_stat", {})
	gs.big_undead.append({
		"uid": uid, "name": "Big " + uid, "kind": GameState.HUSK_KINDS[gs.rng.randi_range(0, GameState.HUSK_KINDS.size() - 1)],
		"role": str((roles if roles is Dictionary else {}).get(top, "hollow")), "stats": st, "place": "crypt", "front": "",
	})
	return uid


static func debug_fail(gs: GameState, reason: String, key: String) -> Dictionary:
	return {"ok": false, "reason": reason, "key": key, "applied": {}}


static func grant(gs: GameState, amounts: Dictionary) -> Dictionary:
	if not gs.debug_enabled:
		return debug_fail(gs, "not_debug", "")
	for k in amounts:
		if not GameState.DEBUG_GRANT_KEYS.has(k):
			return debug_fail(gs, "unknown_key", str(k))
	for k in amounts:
		var counted: bool = k == "husks" or k == "remnants" or k == "big_undead"
		if not (is_count(gs, amounts[k]) if counted else is_num(gs, amounts[k])):
			return debug_fail(gs, "bad_value", str(k))
	var applied := {}
	var minted: Array = []
	for k in amounts:
		var v := float(amounts[k])
		match k:
			"gold", "bodies", "living", "bone", "workers":
				applied[k] = grant_town(gs, k, v)
				if k == "bodies" or k == "workers":
					gs._ledger.source("debug", float(applied[k]) * (gs.worker_mass() if k == "workers" else 1.0))
			"backlog":
				var old: float = gs.realm.vei["undead_queue"]
				gs.realm.vei["undead_queue"] = maxf(0.0, old + v)
				applied[k] = gs.realm.vei["undead_queue"] - old
				gs._ledger.source("debug", float(applied[k]))
			"relics":
				var old := gs.relics
				gs.relics = clampi(old + int(v), 0, maxi(gs._cap_of("relics"), old))
				applied[k] = gs.relics - old
			"essence":
				var old := gs.essence
				gs.essence = clampi(old + int(v), 0, maxi(gs._cap_of("essence"), old))
				applied[k] = gs.essence - old
			"husks":
				for i in int(v):
					minted.append(mint_husk(gs))
				applied[k] = int(v)
			"remnants":
				for i in int(v):
					minted.append(mint_remnant(gs))
				applied[k] = int(v)
			"big_undead":
				var room := maxi(0, gs._cap_of("big_undead") - gs.big_undead.size())
				var n := mini(int(v), room)
				for i in n:
					minted.append(mint_big_undead(gs))
				applied[k] = n
	applied["minted"] = minted
	gs.rev += 1
	return {"ok": true, "reason": "", "key": "", "applied": applied}


## A grant to one of TownSim's stocks (workers in workers, the rest in their units): floored at 0;
## bodies and living are capped at body_cap() and living_cap(), but a grant never pulls an over-cap
## stock down (E1 I4). Workers are a float (staffing is fractional) and restaff at once. Returns the
## applied delta.
static func grant_town(gs: GameState, key: String, v: float) -> float:
	var old := float(gs.town_sim.get(key))
	var hi := INF
	if key == "bodies":
		hi = gs.town_sim.body_cap()
	elif key == "living":
		hi = gs.town_sim.living_cap()
	var now := clampf(old + v, 0.0, maxf(hi, old))
	gs.town_sim.set(key, now)
	if key == "workers":
		gs.town_sim.restaff()
	return now - old


static func valid_valve(gs: GameState, v: Variant) -> bool:
	if not (v is Dictionary):
		return false
	var sum := 0.0
	for k in ["work", "war", "flood"]:
		if not v.has(k) or not is_num(gs, v[k]) or float(v[k]) < 0.0:
			return false
		sum += float(v[k])
	return sum > 0.0


static func valid_forts(gs: GameState, v: Variant) -> bool:
	if not (v is Dictionary):
		return false
	for id in v:
		if gs.realm.fort_by_id(str(id)).is_empty() or not (v[id] is Dictionary):
			return false
		for k in v[id]:
			if not ["living", "undead", "dead"].has(k) or not is_num(gs, v[id][k]) or float(v[id][k]) < 0.0:
				return false
	return true


static func set_state(gs: GameState, patch: Dictionary) -> Dictionary:
	if not gs.debug_enabled:
		return {"ok": false, "reason": "not_debug", "key": ""}
	for k in patch:
		if not GameState.DEBUG_STATE_KEYS.has(k):
			return {"ok": false, "reason": "unknown_key", "key": str(k)}
	for k in patch:
		var v: Variant = patch[k]
		var good := false
		match k:
			"time_scale":
				good = is_num(gs, v) and float(v) > 0.0 and float(v) <= 100.0
			"paused", "won":
				good = typeof(v) == TYPE_BOOL
			"relish_at":
				good = typeof(v) == TYPE_STRING and gs._node_valid(v)
			"valve":
				good = valid_valve(gs, v)
			"forge_level":
				good = is_count(gs, v)
			"forts":
				good = valid_forts(gs, v)
		if not good:
			return {"ok": false, "reason": "bad_value", "key": str(k)}
	if patch.has("relish_at") and not gs.run.is_empty():
		return {"ok": false, "reason": "busy", "key": "relish_at"}
	for k in patch:
		var v: Variant = patch[k]
		match k:
			"time_scale":
				gs.time_scale = float(v)
			"paused":
				gs.paused = v
			"won":
				gs.won = v
			"relish_at":
				gs._place_relish(v)
			"valve":
				gs.valve = GameState._normalised(float(v["work"]), float(v["war"]), float(v["flood"]))
				gs.valve_target = gs.valve.duplicate()
				gs._valve_callout()
			"forge_level":
				gs.town_sim.forge = {"level": int(float(v)), "progress": 0.0}  # TownSim's q forge level
			"forts":
				for id in v:
					var f := gs.realm.fort_by_id(str(id))
					for m in v[id]:
						var old: float = f[m]
						f[m] = minf(float(v[id][m]), float(f["cap"]))
						gs._ledger.source("debug", float(f[m]) - old)
	gs.rev += 1
	return {"ok": true, "reason": "", "key": ""}


static func skip_time(gs: GameState, seconds: float) -> Dictionary:
	if not gs.debug_enabled:
		return {"ok": false, "reason": "not_debug", "substeps": 0}
	if not is_finite(seconds) or seconds <= 0.0 or seconds > 86400.0:
		return {"ok": false, "reason": "bad_value", "substeps": 0}
	var n := gs._advance(seconds, 0)
	gs.rev += 1
	return {"ok": true, "reason": "", "substeps": n}


## §4.6, E1. Loads <fixture_dir>/<name>.json through from_dict.
static func load_fixture(gs: GameState, name: String) -> Dictionary:
	if not gs.debug_enabled:
		return {"ok": false, "reason": "not_debug"}
	if not gs.run.is_empty():
		return {"ok": false, "reason": "busy"}
	if not GameState.FIXTURES.has(name):
		return {"ok": false, "reason": "unknown_fixture"}
	var d := SaveIO.read_file("%s/%s.json" % [gs.fixture_dir, name])
	if d.is_empty() or not gs.from_dict(d)["ok"]:
		return {"ok": false, "reason": "bad_fixture"}
	return {"ok": true, "reason": ""}
