extends Node
## Autoload "GameState". The crypt's material pool — forms + remnants to build
## with, scraps to feed the pit, the raised shelf, and the ossuary itself.
## Phase-2 economy (persistence, town income, the real raid round-trip) is
## faked or deferred; this is the build-expression + floor test only.

signal materials_changed
signal shelf_changed

var rng := RandomNumberGenerator.new()
var forms: Array = []      # available form ids (strings; duplicates allowed)
var remnants: Array = []   # available remnant dicts
var scraps := 0
var shelf: Array = []      # raised creatures (derived snapshot + display_name)
var ossuary: Ossuary

func _ready() -> void:
	rng.randomize()
	ossuary = Ossuary.new(rng)

func reset() -> void:
	forms.clear()
	remnants.clear()
	scraps = 0
	shelf.clear()
	ossuary.fullness = 0.0
	materials_changed.emit()
	shelf_changed.emit()

## Fake the raid: a juicy, varied haul so build expression has range to express.
func grant_raid_haul() -> void:
	for i in rng.randi_range(2, 4):
		forms.append(Loot.roll_husk(rng))
	for i in rng.randi_range(5, 8):
		remnants.append(Loot.roll_remnant(rng))
	scraps += int(ConfigDb.v("ossuary", "scraps_per_raid"))
	materials_changed.emit()

func feed_ossuary() -> bool:
	var chunk := int(ConfigDb.v("ossuary", "feed_chunk"))
	if scraps <= 0:
		return false
	chunk = mini(chunk, scraps)
	scraps -= chunk
	ossuary.feed(chunk)
	materials_changed.emit()
	return true

func pull_ossuary() -> Dictionary:
	var out := ossuary.pull()
	forms.append(out["form_id"])
	remnants.append(out["remnant"])
	materials_changed.emit()
	return out

func take_form(id: String) -> void:
	forms.erase(id)
	materials_changed.emit()

func return_form(id: String) -> void:
	if id != "":
		forms.append(id)
		materials_changed.emit()

func take_remnant(r: Dictionary) -> void:
	remnants.erase(r)
	materials_changed.emit()

func return_remnant(r: Dictionary) -> void:
	if not r.is_empty():
		remnants.append(r)
		materials_changed.emit()

func raise_creature(derived: Dictionary, custom_name := "") -> void:
	var c := derived.duplicate(true)
	c["display_name"] = custom_name if custom_name.strip_edges() != "" else String(derived["name"])
	shelf.append(c)
	shelf_changed.emit()
