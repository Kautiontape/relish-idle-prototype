class_name NextLogic
extends RefCounted
## Pure logic for the objective strip's one next action (no autoloads, so headless tests compile
## it) and for which forts are worth a raid. The strip picks one line by priority from the views:
##   1. fall    a held fort about to fall (the smallest fall_s under next_fall_warn_s);
##   2. raid    a refilled raid (raid_ready "refilled"), as the away panel's ready line {text, kind, target};
##   3. vei     Vei can be begun (view_vei.can_begin): beats the first-clear asks;
##   4. raid    a first-clear raid on the frontier (raid_ready "first_clear");
##   5. queue   the build queue empty (only when view_town carries `queue`);
##   6. vei     Vei's odds >= next_vei_odds without can_begin;
##   7. default the standing objective.
## The opening's ask (set_opening_ask) beats them all; a won game shows the victory line. Clicks
## resolve through AwayLogic.action, the same resolver as the away panel's lines.
## Tuning and words: configs/map_view.json "next".

const OPENING := "opening"
const WON := "won"
const FALL := "fall"
const RAID := "raid"
const QUEUE := "queue"
const VEI := "vei"
const DEFAULT := "default"

const REFILLED := "refilled"
const FIRST_CLEAR := "first_clear"


static func cfg() -> Dictionary:
	return MapLogic.cfg().get("next", {})


# --- raid-worthiness ------------------------------------------------------------------

## The frontier tier: the lowest tier among the forts that still have their first clear, so
## progression runs tier 1, then tier 2, and so on. 0 when every fort has been cleared.
static func frontier_tier(forts: Array) -> int:
	var best := 0
	for f in forts:
		if bool(f.get("first_clear", false)):
			var t := int(f.get("tier", 1))
			if best == 0 or t < best:
				best = t
	return best


## Why a fort's raid is ready, or "". The one rule every caller shares (the ring marker, the
## strip, the away panel's ready line):
##   "refilled"    cleared before (`first_clear` false and clears_since_retaken > 0) and its
##                 yield is back to raid_ready_yield or more;
##   "first_clear" its first clear (a guaranteed blueprint) is unspent AND it is the first
##                 dungeon or on the frontier tier (frontier_tier of `forts`);
##   ""            anything else (held and overrun forts follow the same rule).
static func raid_ready(f: Dictionary, forts: Array, c := {}) -> String:
	if c.is_empty():
		c = cfg()
	return _why(f, frontier_tier(forts), c)


static func _why(f: Dictionary, frontier: int, c: Dictionary) -> String:
	if bool(f.get("first_clear", false)):
		if bool(f.get("first_dungeon", false)) or int(f.get("tier", 1)) == frontier:
			return FIRST_CLEAR
		return ""
	if int(f.get("clears_since_retaken", 0)) > 0 and float(f.get("yield_mult", 0.0)) >= float(c["raid_ready_yield"]):
		return REFILLED
	return ""


## The ready forts in preference order: refilled before first clear, then the first-dungeon
## fort, then world order. [{fort, why}].
static func ready_forts(forts: Array, c := {}) -> Array:
	if c.is_empty():
		c = cfg()
	var frontier := frontier_tier(forts)
	var keyed: Array = []
	for i in forts.size():
		var why := _why(forts[i], frontier, c)
		if why != "":
			keyed.append([0 if why == REFILLED else 1, 0 if bool(forts[i].get("first_dungeon", false)) else 1, i, why])
	keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	return keyed.map(func(k): return {"fort": forts[k[2]], "why": k[3]})


## A ready fort as the away panel's ready line: {text, kind: "raid", target: fort id}.
static func ready_line(f: Dictionary, why: String, c := {}) -> Dictionary:
	if c.is_empty():
		c = cfg()
	var fmt := str(c["refilled_fmt"] if why == REFILLED else c["first_clear_fmt"])
	return {"text": fmt % str(f.get("name", f.get("id", ""))), "kind": RAID, "target": str(f.get("id", ""))}


# --- the next action --------------------------------------------------------------------

## The strip's line. `inp`:
##   forts     view_realm().forts (the model's, demo overlay included)
##   clocks    {fort id: {rate, fall_s}} (the committed clocks)
##   queue     view_town().queue, or null when the view has none
##   vei       view_vei()
##   readout   MapModel.readout()
##   won       view_hud().won
##   opening   {text, target} from set_opening_ask ({} or empty text: none)
## `prev` is the last pick ({} at first): while its rule is still the one chosen and its target
## still qualifies, the target is kept (no ping-pong between near-equal candidates), unless a
## fort now falls in under switch_ratio of the kept one's time.
## Returns {rule, target, text, action}; action is AwayLogic.action's.
static func choose(inp: Dictionary, prev := {}, c := {}) -> Dictionary:
	if c.is_empty():
		c = cfg()
	var fort_ids: Array = (inp.get("forts", []) as Array).map(func(f): return str(f["id"]))
	var op: Dictionary = inp.get("opening", {})
	if str(op.get("text", "")) != "":
		return _pick(OPENING, str(op.get("target", "")), str(op["text"]), fort_ids)
	if bool(inp.get("won", false)):
		return _pick(WON, "", HudLogic.objective_text({"won": true}), fort_ids)
	var fall := _fall(inp, prev, c)
	if not fall.is_empty():
		return _pick(FALL, str(fall["fort"]["id"]), str(c["fall_fmt"]) % [str(fall["fort"].get("name", "")),
			IdleLogic.fmt_fall(float(fall["fall_s"]))], fort_ids)
	var ready := ready_forts(inp.get("forts", []), c)
	var refilled := ready.filter(func(r): return r["why"] == REFILLED)
	if not refilled.is_empty():
		return _raid(refilled, prev, c, fort_ids)
	if bool(inp.get("vei", {}).get("can_begin", false)):
		return _vei(inp, c, fort_ids)
	if not ready.is_empty():
		return _raid(ready, prev, c, fort_ids)
	var queue = inp.get("queue", null)
	if queue is Array and (queue as Array).is_empty():
		return _pick(QUEUE, "queue", str(c["queue_text"]), fort_ids)
	var odds := float(inp.get("readout", {}).get("odds", 0.0))
	if odds >= float(c["next_vei_odds"]):
		return _vei(inp, c, fort_ids)
	return _pick(DEFAULT, "", HudLogic.objective_text({}), fort_ids)


## The raid line for the first of `list` (or `prev`'s target while it is still in the list).
static func _raid(list: Array, prev: Dictionary, c: Dictionary, fort_ids: Array) -> Dictionary:
	var pick: Dictionary = list[0]
	if str(prev.get("rule", "")) == RAID:
		for r in list:
			if str(r["fort"]["id"]) == str(prev.get("target", "")):
				pick = r
	var line := ready_line(pick["fort"], str(pick["why"]), c)
	return _pick(RAID, str(line["target"]), str(line["text"]), fort_ids)


static func _vei(inp: Dictionary, c: Dictionary, fort_ids: Array) -> Dictionary:
	var odds := float(inp.get("readout", {}).get("odds", 0.0))
	return _pick(VEI, "vei", str(c["vei_fmt"]) % roundi(clampf(odds, 0.0, 1.0) * 100.0), fort_ids)


static func _pick(rule: String, target: String, text: String, fort_ids: Array) -> Dictionary:
	return {"rule": rule, "target": target, "text": text, "action": AwayLogic.action(target, fort_ids)}


## The held fort the fall rule names: {fort, fall_s}, or {} when none falls inside
## next_fall_warn_s. Sticky to `prev`'s fort as `choose` says.
static func _fall(inp: Dictionary, prev: Dictionary, c: Dictionary) -> Dictionary:
	var clocks: Dictionary = inp.get("clocks", {})
	var warn := float(c["next_fall_warn_s"])
	var best := {}
	var kept := {}
	for f in IdleLogic.held_forts(inp.get("forts", [])):
		var s := float(clocks.get(str(f["id"]), {}).get("fall_s", -1.0))
		if s < 0.0 or s >= warn:
			continue
		if best.is_empty() or s < float(best["fall_s"]):
			best = {"fort": f, "fall_s": s}
		if str(prev.get("rule", "")) == FALL and str(f["id"]) == str(prev.get("target", "")):
			kept = {"fort": f, "fall_s": s}
	if not kept.is_empty() and float(best["fall_s"]) >= float(kept["fall_s"]) * float(c["switch_ratio"]):
		return kept
	return best
