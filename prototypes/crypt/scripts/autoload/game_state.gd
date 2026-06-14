extends Node
## Autoload "GameState". The crypt's command center: a persistent HORDE of undead
## (the population you organize) plus the raw materials to grow it (forms,
## remnants, scraps) and the Maw to recycle surplus. Raids churn it; Vei ends it.
## Town / jobs / loadouts are faked — this tests whether managing the horde is fun.

signal horde_changed
signal materials_changed

var rng := RandomNumberGenerator.new()
var horde: Array = []         # unit dicts (Horde.make_*)
var forms: Array = []         # raw form ids waiting to be raised
var remnants: Array = []      # spare remnant dicts
var scraps := 0
var ossuary: Ossuary
var custom_tags: Array = []   # player-coined {id,label,color}
var won := false
var raids_completed := 0
var next_threat := {}
var _next_id := 1

func _ready() -> void:
	rng.randomize()
	ossuary = Ossuary.new(rng)
	_seed_start()
	_roll_next_threat()

func _take_id() -> int:
	var i := _next_id
	_next_id += 1
	return i

func _seed_start() -> void:
	for i in int(ConfigDb.v("horde", "start_forms")):
		forms.append(Loot.roll_husk(rng))
	for i in int(ConfigDb.v("horde", "start_remnants")):
		remnants.append(Loot.roll_remnant(rng))
	for i in int(ConfigDb.v("horde", "start_hollows")):
		horde.append(Horde.make_hollow(_take_id(), Loot.roll_husk(rng)))
	scraps += int(ConfigDb.v("ossuary", "scraps_per_raid"))

# ---- Growing the horde ----

func raise_hollow(form_id: String) -> void:
	if not forms.has(form_id):
		return
	forms.erase(form_id)
	horde.append(Horde.make_hollow(_take_id(), form_id))
	horde_changed.emit()
	materials_changed.emit()

## Bulk volume: every spare form rises as a Hollow at once (one-click horde).
func raise_all_hollows() -> int:
	var n := forms.size()
	for id in forms:
		horde.append(Horde.make_hollow(_take_id(), id))
	forms.clear()
	if n > 0:
		horde_changed.emit()
		materials_changed.emit()
	return n

func raise_kitted(form_id: String, used_remnants: Array) -> void:
	if not forms.has(form_id):
		return
	forms.erase(form_id)
	for r in used_remnants:
		remnants.erase(r)
	horde.append(Horde.make_kitted(_take_id(), form_id, used_remnants))
	horde_changed.emit()
	materials_changed.emit()

# ---- Organizing (the player's taxonomy) ----

func add_custom_tag(label: String, color: String) -> String:
	var id := "t%d" % _take_id()
	custom_tags.append({"id": id, "label": label, "color": color})
	return id

func tag_units(ids: Array, tag_id: String) -> void:
	for u in horde:
		if u["id"] in ids and not (tag_id in u["tags"]):
			u["tags"].append(tag_id)
	horde_changed.emit()

func untag_units(ids: Array, tag_id: String) -> void:
	for u in horde:
		if u["id"] in ids:
			u["tags"].erase(tag_id)
	horde_changed.emit()

func all_tags() -> Array:
	var out: Array = (ConfigDb.data["tags"]["presets"] as Array).duplicate(true)
	out.append_array(custom_tags)
	return out

func tag_def(tag_id: String) -> Dictionary:
	for t in all_tags():
		if t["id"] == tag_id:
			return t
	return {"id": tag_id, "label": tag_id, "color": "#888888"}

# ---- Shredding (the surplus valve) ----

func shred_units(ids: Array) -> int:
	var fill := 0
	var keep: Array = []
	for u in horde:
		if u["id"] in ids:
			var w := maxi(1, int(round(Loot.minion_worth(u))))
			ossuary.feed(w)
			fill += w
		else:
			keep.append(u)
	horde = keep
	horde_changed.emit()
	materials_changed.emit()
	return fill

func feed_scraps() -> bool:
	var chunk := int(ConfigDb.v("ossuary", "feed_chunk"))
	if scraps <= 0:
		return false
	chunk = mini(chunk, scraps)
	scraps -= chunk
	ossuary.feed(chunk)
	materials_changed.emit()
	return true

func feed_remnant(r: Dictionary) -> int:
	if not remnants.has(r):
		return 0
	var units := maxi(1, int(round(Loot.remnant_worth(r))))
	remnants.erase(r)
	ossuary.feed(units)
	materials_changed.emit()
	return units

func pull_ossuary() -> Dictionary:
	var out := ossuary.pull()
	forms.append(out["form_id"])
	remnants.append(out["remnant"])
	materials_changed.emit()
	return out

# ---- The loop ----

## "Let's go." A raid just happens: composition sets losses, the haul refills.
func _roll_next_threat() -> void:
	next_threat = CombatSim.roll_raid(rng)

func jar_size() -> int:
	return int(ConfigDb.v("horde", "jar_base")) + int(floor(sqrt(float(raids_completed))))

## "Let's go." Pick a party (up to jar_size) — only THEY march and take losses.
func raid(party_ids: Array) -> Dictionary:
	var party: Array = []
	for u in horde:
		if int(u["id"]) in party_ids:
			party.append(u)
	var threat: Dictionary = next_threat if not next_threat.is_empty() else CombatSim.roll_raid(rng)
	var res := CombatSim.resolve_raid(party, threat, rng)
	var lost: Array = []
	for i in (res["lost_indices"] as Array):
		lost.append(party[i])
	for u in lost:
		horde.erase(u)
	var cfg: Dictionary = ConfigDb.data["raid"]
	var gf := rng.randi_range(int(cfg["haul_forms"][0]), int(cfg["haul_forms"][1]))
	var gr := rng.randi_range(int(cfg["haul_remnants"][0]), int(cfg["haul_remnants"][1]))
	var gh := rng.randi_range(int(cfg["haul_hollows"][0]), int(cfg["haul_hollows"][1]))
	for i in gf:
		forms.append(Loot.roll_husk(rng))
	for i in gr:
		remnants.append(Loot.roll_remnant(rng))
	for i in gh:
		horde.append(Horde.make_hollow(_take_id(), Loot.roll_husk(rng)))
	scraps += int(cfg["haul_scraps"])
	raids_completed += 1
	_roll_next_threat()
	horde_changed.emit()
	materials_changed.emit()
	return {"threat": threat, "coverage": float(res["coverage"]), "lost": lost,
		"gained_forms": gf, "gained_remnants": gr, "gained_hollows": gh, "scraps": int(cfg["haul_scraps"]),
		"party_size": party.size()}

func fight_vei() -> Dictionary:
	var res := CombatSim.resolve_vei(horde)
	res["army"] = horde.size()
	if res["won"]:
		won = true
	else:
		_wipe()
	horde_changed.emit()
	materials_changed.emit()
	return res

func _wipe() -> void:
	horde.clear()
	forms.clear()
	remnants.clear()
	scraps = 0
	raids_completed = 0
	ossuary.fullness = 0.0
	_seed_start()
	_roll_next_threat()

func reset() -> void:
	won = false
	_wipe()
	horde_changed.emit()
	materials_changed.emit()

# ---- Reads for the UI ----

func composition() -> Dictionary:
	return Horde.composition(horde)

func vei_fronts() -> Array:
	return CombatSim.vei_fronts(horde)
