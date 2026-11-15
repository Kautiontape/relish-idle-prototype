extends RefCounted
## The mass ledger (MECHANICS §2.1, STATE-API §4.7), preloaded as `GameState.Ledger`. It has no
## class_name: the dungeon's inner class `RaidLogic.Ledger` would hide a global `Ledger` (a parse
## error in raid_logic.gd). `sources` and `sinks` are mass totals since the new game, booked by
## GameState where mass enters or leaves the world; `held` is never stored: it is summed from the
## live state on demand. Invariant, at every substep boundary and at any substep length:
## Σheld + Σsinks == Σsources (error() is the relative miss).
##
## Sources:
##   mint      the raising pits' production (the only true flow in)
##   debug     net mass the debug commands added: grants of bodies, workers (× worker.mass) and
##             backlog, and cmd_debug_set_state's forts. A removal books a negative amount.
##   opening   not a flow: the mass on the board when the count began. A new game's start (the forts'
##             garrisons, opening workers and bodies); for a save written before the ledger, the mass
##             it held at load plus its saved `dungeon` sink.
## Sinks:
##   cleared        k_clear: garrisons clear corpses off the board
##   rot_loss       rotted workers' mass that does not come back as bodies (1 − worker.body_return)
##   rot_overflow   rot return lost to the body cap
##   haul_overflow  a convoy's load lost to the body cap
##   burned         pit burn
##   milled         milled bodies (bone is not mass)
##   vei_fight      the backlog a lost Vei fight destroys
##   dungeon        what a raid writeback lost
##   pool_overflow  the march-back past Vei's pool cap (living above a fort's cap marching home); she
##                  then converts only into the headroom left
##   store_overflow always 0: the store caps (IDLE §6, E2b-2 T3.2) clip gold and bone, which are not
##                  mass; their overflow is the currency tally `stores` below
## Held: every pool of mass, see held().
##
## Beside the mass, a currency tally (not mass, so outside the invariant): `stores` {gold: {overflow},
## bone: {overflow}}, the income each store's cap clipped since the new game (TownSim's gold_overflow,
## bone_overflow; GameState books them in the core step). Saved with the ledger; a save without it reads 0.
## Internal transfers book nothing: the valve split, WORK into workers, muster into WAR, haul pickups,
## combat, drain, Vei's conversion (dead and undead to living) and shipping, surges, the redirect,
## simulacra and the raid writeback's kills, flip and chaff.

const SOURCES := ["mint", "debug", "opening"]
const SINKS := ["cleared", "rot_loss", "burned", "milled", "vei_fight", "dungeon", "pool_overflow",
	"rot_overflow", "haul_overflow", "store_overflow"]
const HELD := ["fort_living", "fort_undead", "corpses", "backlog", "vei_dead", "living_pool", "bodies",
	"workers", "convoys", "work_pending"]
## The capped currency stores the tally covers (IDLE §6).
const STORES := ["gold", "bone"]

var sources := {}
var sinks := {}
var stores := {}  # store -> {overflow: float}, totals since the new game


func _init() -> void:
	reset(0.0)


## A new count: every total 0 but `opening`.
func reset(opening: float) -> void:
	sources = {}
	for k in SOURCES:
		sources[k] = 0.0
	sinks = {}
	for k in SINKS:
		sinks[k] = 0.0
	sources["opening"] = opening
	stores = {}
	for k in STORES:
		stores[k] = {"overflow": 0.0}


func source(key: String, mass: float) -> void:
	assert(sources.has(key), "Ledger: unknown source %s" % key)
	sources[key] = float(sources[key]) + mass


func sink(key: String, mass: float) -> void:
	assert(sinks.has(key), "Ledger: unknown sink %s" % key)
	sinks[key] = float(sinks[key]) + mass


## A store's income its cap clipped this step (gold or bone; not mass).
func overflow(store: String, amount: float) -> void:
	assert(stores.has(store), "Ledger: unknown store %s" % store)
	stores[store]["overflow"] = float(stores[store]["overflow"]) + amount


## `stores` as ledger() and the save show it: a fresh copy.
func stores_copy() -> Dictionary:
	return stores.duplicate(true)


## Every pool of mass, now. Forts' living, undead and dead (corpses); Vei's undead queue (backlog),
## dead queue and living pool; Covington's bodies, workers (× worker.mass) and the loads of convoys
## on their way home; the WORK the valve sent that TownSim takes next substep.
static func held(realm: RealmSim, town: TownSim, work_pending: float, worker_mass: float) -> Dictionary:
	var living := 0.0
	var undead := 0.0
	var dead := 0.0
	for f in realm.forts:
		living += float(f["living"])
		undead += float(f["undead"])
		dead += float(f["dead"])
	var convoys := 0.0
	for c in town.haul["convoys"]:
		convoys += float(c["load"])
	return {
		"fort_living": living, "fort_undead": undead, "corpses": dead,
		"backlog": float(realm.vei["undead_queue"]), "vei_dead": float(realm.vei["dead_queue"]),
		"living_pool": float(realm.vei["living_pool"]),
		"bodies": town.bodies, "workers": town.workers * worker_mass, "convoys": convoys,
		"work_pending": work_pending,
	}


static func total(d: Dictionary) -> float:
	var s := 0.0
	for k in d:
		s += float(d[k])
	return s


## The relative miss of a ledger() dictionary: |Σheld + Σsinks − Σsources| / max(1, |Σsources|).
static func error(l: Dictionary) -> float:
	var src := total(l["sources"])
	return absf(total(l["held"]) + total(l["sinks"]) - src) / maxf(1.0, absf(src))


## The save's `ledger` block (STATE-API §9.1).
func to_dict() -> Dictionary:
	return {"sources": sources.duplicate(), "sinks": sinks.duplicate(), "stores": stores.duplicate(true)}


## Restores the totals from a save's `ledger` block. A block with `sources.opening` was written by
## this ledger: every total is read back (a missing key reads 0). One without it predates the ledger
## (E1 and E2a saves, the fixtures), where only `sinks.dungeon` was real: that sink is kept and
## `opening` is what the save holds now, so the count balances from the load on.
func from_dict(d: Dictionary, held_now: Dictionary) -> void:
	var src: Dictionary = d.get("sources", {})
	var snk: Dictionary = d.get("sinks", {})
	reset(0.0)
	if src.has("opening"):
		for k in SOURCES:
			sources[k] = float(src.get(k, 0.0))
		for k in SINKS:
			sinks[k] = float(snk.get(k, 0.0))
	else:
		sinks["dungeon"] = float(snk.get("dungeon", 0.0))
		sources["opening"] = total(held_now) + float(sinks["dungeon"])
	# the currency tally (E2b-2 T3.2): a save written before it reads 0
	var st: Variant = d.get("stores", {})
	if st is Dictionary:
		for k in STORES:
			var e: Variant = st.get(k, {})
			if e is Dictionary:
				stores[k]["overflow"] = float(e.get("overflow", 0.0))
