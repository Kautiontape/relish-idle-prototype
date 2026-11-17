class_name VeiFronts
extends RefCounted
## Vei's final test: pure logic (MECHANICS 6, GAMEPLAY 3d). No autoload, no Engine, no ConfigDb;
## every function takes its numbers from `cfg` (configs/vei.json, passed in by the caller) and
## falls back to the approved defaults below for any missing key, so GameState may call
## `have_need` before vei.json is complete. All functions are static and never mutate their
## arguments; state-stepping functions return a new Dictionary.
##
## FRONT_IDS: the four fronts, in the order of GameState.FRONT_IDS.
##
## --- Fronts (the API GameState calls; keep it stable) ----------------------------------
## have_need(info, cfg) -> Array
##   info = {backlog: float, living_pool: float, digest_q: float, big_undead: Array}; each
##   big-undead entry is {uid, stats: {power, beef, wits, presence, speed}, front: String,
##   place: String}. Returns, in FRONT_IDS order, {id, need: float, have: float,
##   cleared: bool, assigned: Array[String]} (assigned = uids counted on that front).
##   have = per_stat * sum(stat of counted units) + per_backlog * backlog + per_q * digest_q
##   need = need_base + need_per_pool * living_pool       cleared = have >= need
##   Counting: front != "" counts on that front wherever the unit is placed (an unknown front
##   id counts nowhere). Otherwise place == "party" counts on the front whose `stat` is the
##   unit's highest stat (ties broken by FRONT_IDS order). Otherwise it counts nowhere.
## fronts_met(fronts) -> int       how many entries are cleared.
## required(cfg) -> int            fronts_required (default 3).
## info_from_boss_seed(seed) -> Dictionary
##   have_need's info from a boss seed (STATE-API 7.2): party entries become big_undead with
##   place "party", carrying their front.
##
## --- Phase 1 (the fronts resolve as streams) -------------------------------------------
## phase1_start(fronts) -> {t: 0.0, fronts: [{id, have, need, progress: 0.0, cleared: false}]}
## phase1_step(state, dt, cfg) -> state
##   t += dt; each uncleared front's progress += clamp(have/need, 0, phase1.max_rate) * dt /
##   phase1.ref_s. A front clears when progress >= 1 AND have >= need; a front with have <
##   need stalls at progress <= have/need and never clears on time alone.
## phase1_add_raise(state, front_id, stat_mults, cfg) -> state
##   have += raise_have_per_mult * sum(stat_mults) on that front (unknown id: no change).
## phase1_outcome(state, cfg) -> String
##   "phase2" when cleared fronts >= required(cfg); else "lost" when t >= phase1_max_s;
##   else "".
##
## --- Phase 2 (the break) ----------------------------------------------------------------
## ferry_rate({living_pool, digest_q}, uncleared, cfg) -> float     (mass/s)
##   (ferry.base + per_pool * living_pool + per_uncleared * uncleared)
##   / (1 + per_q_div * (max(q, 1) - 1)). Rises with pool and uncleared fronts, falls with q.
## raise_value(stat_mults, cfg) -> float      mote_mass * sum(stat_mults).
## break_start() -> {ema: 0.0, streak: 0, beats: 0}
## break_beat(state, raised_value_this_beat, ferry_per_beat, cfg) -> state
##   ema += alpha * (raised - ema), alpha = 1 - e^(-1 / raise_ema_beats); then streak + 1 if
##   ema > ferry_per_beat (strictly), else a lapse: back to 0, or, when cfg.lapse_cost >= 0, down
##   by lapse_cost beats (never below 0). lapse_cost defaults to -1 (the reset). beats += 1.
## broken(state, cfg) -> bool         streak >= break_beats.
##
## --- Backups and result ----------------------------------------------------------------
## next_backup(spent {phylactery, clones}, charges, clones_ready) -> String
##   "phylactery" while spent.phylactery < charges, else "clone" while spent.clones <
##   clones_ready, else "" (none left: the fight is lost).
## boss_result(seed, won, fronts_cleared, relish_deaths, spent, party_lost, backlog_spent)
##   -> Dictionary: the v2 boss result (STATE-API 8.2). run_id and seed_rev come from the
##   seed; unknown and duplicate front ids are filtered; party uids not in the seed's party
##   are dropped. The caller keeps deaths consistent with backups (Results.validate).

const FRONT_IDS := ["giants", "swarm", "carvers", "raw"]

const _DEF_FRONTS := {
	"giants": {"stat": "wits", "per_stat": 1.0, "per_backlog": 0.0, "per_q": 0.0, "need_base": 14.0, "need_per_pool": 0.02},
	"swarm": {"stat": "presence", "per_stat": 1.0, "per_backlog": 0.0000005, "per_q": 0.0, "need_base": 12.0, "need_per_pool": 0.02},
	"carvers": {"stat": "beef", "per_stat": 1.0, "per_backlog": 0.0, "per_q": 3.0, "need_base": 18.0, "need_per_pool": 0.02},
	"raw": {"stat": "power", "per_stat": 1.0, "per_backlog": 0.00000025, "per_q": 0.0, "need_base": 40.0, "need_per_pool": 0.03},
}
const _DEF_FERRY := {"base": 0.5, "per_pool": 0.01, "per_uncleared": 0.5, "per_q_div": 0.25}


# ------------------------------------------------------------------ cfg helpers ----
static func _f(d: Variant, key: String, def: float) -> float:
	if typeof(d) == TYPE_DICTIONARY and d.has(key) and (typeof(d[key]) == TYPE_INT or typeof(d[key]) == TYPE_FLOAT):
		return float(d[key])
	return def


static func _front_cfg(cfg: Dictionary, id: String) -> Dictionary:
	var out: Dictionary = (_DEF_FRONTS[id] as Dictionary).duplicate()
	var fs: Variant = cfg.get("fronts", {})
	if typeof(fs) == TYPE_DICTIONARY and typeof(fs.get(id)) == TYPE_DICTIONARY:
		for k in fs[id]:
			if k == "stat":
				if typeof(fs[id][k]) == TYPE_STRING:
					out[k] = fs[id][k]
			elif typeof(fs[id][k]) == TYPE_INT or typeof(fs[id][k]) == TYPE_FLOAT:
				out[k] = float(fs[id][k])
	return out


static func required(cfg: Dictionary) -> int:
	return int(_f(cfg, "fronts_required", 3.0))


# ------------------------------------------------------------------------ fronts ----
static func _stat(u: Dictionary, stat: String) -> float:
	var s: Variant = u.get("stats", {})
	return _f(s, stat, 0.0)


## The front id an unassigned party unit serves (highest stat; ties by FRONT_IDS order).
static func _front_for(u: Dictionary, fcfg: Dictionary) -> String:
	var best := ""
	var best_v := -INF
	for id in FRONT_IDS:
		var v := _stat(u, String(fcfg[id]["stat"]))
		if v > best_v:
			best_v = v
			best = id
	return best


static func have_need(info: Dictionary, cfg: Dictionary) -> Array:
	var backlog := _f(info, "backlog", 0.0)
	var pool := _f(info, "living_pool", 0.0)
	var q := _f(info, "digest_q", 0.0)
	var fcfg := {}
	var sums := {}
	var assigned := {}
	for id in FRONT_IDS:
		fcfg[id] = _front_cfg(cfg, id)
		sums[id] = 0.0
		assigned[id] = []
	var units: Variant = info.get("big_undead", [])
	if typeof(units) == TYPE_ARRAY:
		for u in units:
			if typeof(u) != TYPE_DICTIONARY:
				continue
			var fid := String(u.get("front", ""))
			if fid == "":
				if String(u.get("place", "")) != "party":
					continue
				fid = _front_for(u, fcfg)
			if not assigned.has(fid):
				continue
			sums[fid] += _stat(u, String(fcfg[fid]["stat"]))
			assigned[fid].append(String(u.get("uid", "")))
	var out: Array = []
	for id in FRONT_IDS:
		var c: Dictionary = fcfg[id]
		var have: float = float(c["per_stat"]) * float(sums[id]) + float(c["per_backlog"]) * backlog \
				+ float(c["per_q"]) * q
		var need: float = float(c["need_base"]) + float(c["need_per_pool"]) * pool
		out.append({"id": id, "need": need, "have": have, "cleared": have >= need, "assigned": assigned[id]})
	return out


static func fronts_met(fronts: Array) -> int:
	var n := 0
	for f in fronts:
		if bool(f.get("cleared", false)):
			n += 1
	return n


static func info_from_boss_seed(seed: Dictionary) -> Dictionary:
	var units: Array = []
	for p in seed.get("party", []):
		units.append({"uid": String(p.get("uid", "")), "stats": p.get("stats", {}),
				"front": String(p.get("front", "")), "place": "party"})
	return {"backlog": _f(seed, "backlog", 0.0), "living_pool": _f(seed, "living_pool", 0.0),
			"digest_q": _f(seed, "digest_q", 0.0), "big_undead": units}


# ------------------------------------------------------------------------ phase 1 ----
static func phase1_start(fronts: Array) -> Dictionary:
	var fs: Array = []
	for f in fronts:
		fs.append({"id": String(f["id"]), "have": float(f["have"]), "need": float(f["need"]),
				"progress": 0.0, "cleared": false})
	return {"t": 0.0, "fronts": fs}


static func phase1_step(state: Dictionary, dt: float, cfg: Dictionary) -> Dictionary:
	var p1: Variant = cfg.get("phase1", {})
	var ref_s := maxf(_f(p1, "ref_s", 20.0), 0.0001)
	var max_rate := _f(p1, "max_rate", 3.0)
	var out := {"t": float(state["t"]) + dt, "fronts": []}
	for f in state["fronts"]:
		var g: Dictionary = f.duplicate()
		if not bool(g["cleared"]):
			var need := float(g["need"])
			var have := float(g["have"])
			var rate := max_rate if need <= 0.0 else clampf(have / need, 0.0, max_rate)
			var prog: float = float(g["progress"]) + rate * dt / ref_s
			if have < need:
				prog = minf(prog, have / need)
			g["progress"] = prog
			g["cleared"] = prog >= 1.0 and have >= need
		out["fronts"].append(g)
	return out


static func phase1_add_raise(state: Dictionary, front_id: String, stat_mults: Array, cfg: Dictionary) -> Dictionary:
	var per := _f(cfg, "raise_have_per_mult", 1.0)
	var sum := 0.0
	for m in stat_mults:
		sum += float(m)
	var out := {"t": state["t"], "fronts": []}
	for f in state["fronts"]:
		var g: Dictionary = f.duplicate()
		if g["id"] == front_id:
			g["have"] = float(g["have"]) + per * sum
		out["fronts"].append(g)
	return out


static func phase1_outcome(state: Dictionary, cfg: Dictionary) -> String:
	if fronts_met(state["fronts"]) >= required(cfg):
		return "phase2"
	if float(state["t"]) >= _f(cfg, "phase1_max_s", 90.0):
		return "lost"
	return ""


# ------------------------------------------------------------------------ phase 2 ----
static func ferry_rate(info: Dictionary, uncleared: int, cfg: Dictionary) -> float:
	var fc: Variant = cfg.get("ferry", {})
	var raw := _f(fc, "base", _DEF_FERRY["base"]) \
			+ _f(fc, "per_pool", _DEF_FERRY["per_pool"]) * _f(info, "living_pool", 0.0) \
			+ _f(fc, "per_uncleared", _DEF_FERRY["per_uncleared"]) * float(uncleared)
	var q := maxf(_f(info, "digest_q", 1.0), 1.0)
	return raw / (1.0 + _f(fc, "per_q_div", _DEF_FERRY["per_q_div"]) * (q - 1.0))


static func raise_value(stat_mults: Array, cfg: Dictionary) -> float:
	var sum := 0.0
	for m in stat_mults:
		sum += float(m)
	return _f(cfg, "mote_mass", 1.0) * sum


static func break_start() -> Dictionary:
	return {"ema": 0.0, "streak": 0, "beats": 0}


static func break_beat(state: Dictionary, raised_value_this_beat: float, ferry_per_beat: float,
		cfg: Dictionary) -> Dictionary:
	var alpha := 1.0 - exp(-1.0 / maxf(_f(cfg, "raise_ema_beats", 4.0), 0.0001))
	var ema := float(state["ema"]) + alpha * (raised_value_this_beat - float(state["ema"]))
	var streak := int(state["streak"]) + 1
	if ema <= ferry_per_beat:
		var lapse := int(_f(cfg, "lapse_cost", -1.0))
		streak = 0 if lapse < 0 else maxi(0, int(state["streak"]) - lapse)
	return {"ema": ema, "streak": streak, "beats": int(state["beats"]) + 1}


static func broken(state: Dictionary, cfg: Dictionary) -> bool:
	return int(state["streak"]) >= int(_f(cfg, "break_beats", 8.0))


# ------------------------------------------------------------------ backups, result ----
static func next_backup(spent: Dictionary, charges: int, clones_ready: int) -> String:
	if int(spent.get("phylactery", 0)) < charges:
		return "phylactery"
	if int(spent.get("clones", 0)) < clones_ready:
		return "clone"
	return ""


static func boss_result(seed: Dictionary, won: bool, fronts_cleared: Array, relish_deaths: int,
		spent: Dictionary, party_lost: Array, backlog_spent: float) -> Dictionary:
	var fronts: Array = []
	for id in fronts_cleared:
		if FRONT_IDS.has(id) and not fronts.has(id):
			fronts.append(id)
	var known: Array = []
	for p in seed.get("party", []):
		known.append(String(p.get("uid", "")))
	var lost: Array = []
	for u in party_lost:
		if known.has(u) and not lost.has(u):
			lost.append(u)
	return {
		"v": 2, "run_id": int(seed.get("run_id", 0)), "seed_rev": int(seed.get("seed_rev", 0)),
		"won": won, "fronts_cleared": fronts, "relish_deaths": relish_deaths,
		"backups_spent": {"phylactery": int(spent.get("phylactery", 0)), "clones": int(spent.get("clones", 0))},
		"party_lost": lost, "backlog_spent": backlog_spent,
	}
