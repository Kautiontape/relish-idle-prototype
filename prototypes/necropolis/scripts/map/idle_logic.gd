class_name IdleLogic
extends RefCounted
## Pure logic for the idle surfaces' margins (IDLE section 3; no autoloads, so headless tests
## compile it): whether WAR staging supports a held fort (SAFE / THIN / WILL FALL), "WAR supports
## N of M held forts", and the projection of a dragged valve. Every read is "the real API field
## when GameState has it, else the stand-in here". Tuning: configs/map_view.json "idle".

const SAFE := "safe"
const THIN := "thin"
const WILL_FALL := "will_fall"
const PROJECTION_KEYS := ["split", "workers_steady", "war_supports", "margins"]


static func cfg() -> Dictionary:
	return MapLogic.cfg().get("idle", {})


# --- margins -----------------------------------------------------------------------

## safe when support >= margin_safe_ratio x pressure, thin when >= margin_thin_ratio x pressure,
## else will_fall. No pressure is always safe.
# TODO(api-request #7): view_fort.margin
static func margin(support_rate: float, pressure_rate: float, c := {}) -> String:
	if c.is_empty():
		c = cfg()
	if pressure_rate <= 0.0:
		return SAFE
	if support_rate >= float(c["margin_safe_ratio"]) * pressure_rate:
		return SAFE
	if support_rate >= float(c["margin_thin_ratio"]) * pressure_rate:
		return THIN
	return WILL_FALL


static func held_forts(forts: Array) -> Array:
	var out: Array = []
	for f in forts:
		if bool(f.get("held", false)):
			out.append(f)
	return out


## WAR staging split evenly across the held forts: holding more thins every garrison.
static func support_per_fort(split_war: float, held_count: int) -> float:
	return split_war / float(held_count) if held_count > 0 else 0.0


## {fort_id: margin} for every held fort at a WAR split (mass/s).
# TODO(api-request #7): view_fort.margin
static func margins(forts: Array, split_war: float, c := {}) -> Dictionary:
	var held := held_forts(forts)
	var support := support_per_fort(split_war, held.size())
	var out := {}
	for f in held:
		out[str(f["id"])] = margin(support, float(f.get("ship_in", 0.0)), c)
	return out


## {n, m}: m = the held count, n = how many are not will_fall at that split.
# TODO(api-request #7): view_hud.war_supports
static func war_supports(split_war: float, held: Array, c := {}) -> Dictionary:
	var ms := margins(held, split_war, c)
	var n := 0
	for id in ms:
		if ms[id] != WILL_FALL:
			n += 1
	return {"n": n, "m": held_forts(held).size()}


## Your undead mass at a fort.
# TODO(api-request #7): view_fort.garrison
static func garrison(f: Dictionary) -> float:
	return float(f["garrison"]) if f.has("garrison") else float(f.get("undead", 0.0))


## The garrison as the chip counts it, and as many worker glyphs as the fort draws at near zoom:
## garrison / garrison_unit_mass, rounded half away from zero (fmt_mass's rounding), never negative.
static func garrison_units(f: Dictionary, c := {}) -> int:
	if c.is_empty():
		c = cfg()
	return maxi(roundi(garrison(f) / maxf(float(c.get("garrison_unit_mass", 1.0)), 0.001)), 0)


## The garrison chip's text: garrison_fmt with garrison_units (thousands separated).
static func garrison_text(f: Dictionary, c := {}) -> String:
	if c.is_empty():
		c = cfg()
	return str(c["garrison_fmt"]) % MapLogic.fmt_mass(garrison_units(f, c))


## The committed margins: the view's per-fort field where it has one, else the stand-in at the
## committed WAR split.
static func committed_margins(forts: Array, hud: Dictionary, c := {}) -> Dictionary:
	var fallback := margins(forts, float(hud.get("split", {}).get("war", 0.0)), c)
	var out := {}
	for f in held_forts(forts):
		var id := str(f["id"])
		out[id] = str(f["margin"]) if (f.has("margin") and str(f["margin"]) != "") else str(fallback.get(id, SAFE))
	return out


## The committed "WAR supports N of M": the view's field, else the stand-in at the committed split.
static func committed_supports(hud: Dictionary, forts: Array, c := {}) -> Dictionary:
	if hud.has("war_supports"):
		return hud["war_supports"]
	return war_supports(float(hud.get("split", {}).get("war", 0.0)), forts, c)


# --- projection ------------------------------------------------------------------

## What a dragged valve would do: {split, workers_steady, war_supports: {n, m}, margins}.
## `state` is the GameState (or anything with view_projection): its real projection wins field
## by field; without it the stand-in over `forts` answers.
# TODO(api-request #7): view_projection(valve)
static func projection(state, hud: Dictionary, valve: Dictionary, forts: Array, c := {}) -> Dictionary:
	var held := held_forts(forts)
	var out := ValveLogic.project(hud, valve, held.size())
	var war: float = out["split"]["war"]
	out["margins"] = margins(forts, war, c)
	out["war_supports"] = war_supports(war, held, c)
	if state != null and state.has_method("view_projection"):
		var real: Dictionary = state.view_projection(ValveLogic.normalise(valve))
		for k in PROJECTION_KEYS:
			if real.has(k):
				out[k] = real[k]
	return out


## The projection the valve panel shows: while dragging, the dragged valve's own; otherwise its
## "WAR supports N of M" is the committed one (`committed_now` = MapModel.supports_now()), so the
## panel, the chips and the glyphs share one source while the split slews to the target.
static func panel_projection(proj: Dictionary, committed_now: Dictionary, dragging: bool) -> Dictionary:
	if dragging:
		return proj
	var out := proj.duplicate()
	out["war_supports"] = committed_now
	return out


# --- chip text ---------------------------------------------------------------------

static func word(m: String) -> String:
	return str(cfg().get("words", {}).get(m, ""))


static func color_key(m: String) -> String:
	return str(cfg().get("colors", {}).get(m, "text"))
