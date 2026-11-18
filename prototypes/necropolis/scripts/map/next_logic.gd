class_name NextLogic
extends RefCounted
## Pure logic for the objective strip's one next action (no autoloads, so headless tests compile
## it) and for which forts are worth a raid. The strip picks one line by a strict order:
##   opening  the opening's ask (set_opening_ask) beats them all;
##   won      a won game shows the victory line;
##   fall     a held fort about to fall: the smallest fall_s under next_fall_warn_s (a kept fort
##            stays under next_fall_warn_s x next_fall_exit_mult; switch_ratio decides a rival);
##   raid     a refilled raid, a refill that pays off now: the first "refilled" entry of the model's
##            raid set (raid_set, handed in as inp.raids), or the previous pick's target while it
##            is still a refilled entry, as the away panel's ready line {text, kind, target};
##   vei      Vei in reach: view_vei.can_begin, or odds >= next_vei_odds (after a VEI pick it stays
##            while can_begin holds or odds >= next_vei_odds_exit);
##   raid     the blueprint ask: the first "first_clear" entry of the same set (the first dungeon's
##            included), or the previous pick's target while it is still a first-clear entry;
##   plan     the build queue empty (queue, only when view_town carries `queue`), else the
##            standing objective (default), with "Next: <fort>" appended and that fort the click's
##            target: inp.place, MapModel.next_place (next_place).
## Every line but the won line and the opening's valve ask names where to go: a fort, Covington or Vei.
## Clicks resolve through AwayLogic.action, the same resolver as the away panel's lines.
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


## Whether game time went backwards since `last_t` (-1: never read): a different game, so the
## hysteresis memory kept across map mounts (the strip's pick, the raid set) starts over.
static func restarted(last_t: float, now_t: float) -> bool:
	return last_t >= 0.0 and now_t < last_t


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


## The forts worth a raid now, ranked and capped: [{fort, why}], at most raid_tag_max. The one set
## the ring's tag, the fort's static signature and the strip's raid rule share (MapModel computes it
## once per refresh). Who qualifies (`why`):
##   "refilled"    cleared before (`first_clear` false and clears_since_retaken > 0) and its yield
##                 is back to raid_ready_yield or more; a fort in `prev_ids` (the last set) stays
##                 while its yield is at raid_ready_yield_exit or more;
##   "first_clear" its first clear (a guaranteed blueprint) is unspent AND it is the first
##                 dungeon or on the frontier tier (frontier_tier of `forts`).
## Held and overrun forts follow the same rule. Rank: refilled, then the first-dungeon first
## clear, then a frontier first clear; within refilled the higher yield_mult; then the forts in
## `prev_ids` (tags stay put); then the nearer to `from_pos` (Relish's node; `positions` is
## {fort id: world Vector2}, a fort without one ranks after those with one); then world order.
static func raid_set(forts: Array, prev_ids: Array, from_pos: Vector2, positions: Dictionary, c := {}) -> Array:
	if c.is_empty():
		c = cfg()
	var frontier := frontier_tier(forts)
	var keyed: Array = []
	for i in forts.size():
		var f: Dictionary = forts[i]
		var id := str(f.get("id", ""))
		var kept := prev_ids.has(id)
		var why := _why(f, frontier, kept, c)
		if why == "":
			continue
		var cls := 0 if why == REFILLED else (1 if bool(f.get("first_dungeon", false)) else 2)
		var y := float(f.get("yield_mult", 0.0)) if why == REFILLED else 0.0
		var d := from_pos.distance_to(positions[id]) if positions.has(id) else INF
		keyed.append({"cls": cls, "y": y, "new": 0 if kept else 1, "d": d, "i": i, "why": why})
	keyed.sort_custom(_ranks_before)
	var out: Array = []
	for k in keyed.slice(0, int(c["raid_tag_max"])):
		out.append({"fort": forts[k["i"]], "why": k["why"]})
	return out


## raid_set's rank key: class, yield (high first), kept before new, distance, world order.
static func _ranks_before(a: Dictionary, b: Dictionary) -> bool:
	for k in ["cls", "y", "new", "d", "i"]:
		if a[k] != b[k]:
			return a[k] > b[k] if k == "y" else a[k] < b[k]
	return false


## Why a fort qualifies for the raid set (raid_set's rules; `kept`: it was in the last set), or "".
static func _why(f: Dictionary, frontier: int, kept: bool, c: Dictionary) -> String:
	if bool(f.get("first_clear", false)):
		if bool(f.get("first_dungeon", false)) or int(f.get("tier", 1)) == frontier:
			return FIRST_CLEAR
		return ""
	var bar := float(c["raid_ready_yield_exit"] if kept else c["raid_ready_yield"])
	if int(f.get("clears_since_retaken", 0)) > 0 and float(f.get("yield_mult", 0.0)) >= bar:
		return REFILLED
	return ""


## The place the standing objective points at (the strip's default line): the fort that is still
## Vei's (not held) on the frontier (frontier_tier of those forts, or the lowest tier among them
## when none has a first clear left), the nearest to `from_pos` (a fort with no entry in `positions`
## ranks after those with one), then world order. "" when every fort is held.
static func next_place(forts: Array, from_pos: Vector2, positions: Dictionary) -> String:
	var open: Array = forts.filter(func(f): return not bool(f.get("held", false)))
	if open.is_empty():
		return ""
	var tier := frontier_tier(open)
	if tier == 0:
		tier = int(open[0].get("tier", 1))
		for f in open:
			tier = mini(tier, int(f.get("tier", 1)))
	var best := ""
	var best_d := INF
	for f in open:
		if int(f.get("tier", 1)) != tier:
			continue
		var id := str(f.get("id", ""))
		var d := from_pos.distance_to(positions[id]) if positions.has(id) else INF
		if best == "" or d < best_d:
			best = id
			best_d = d
	return best


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
##   raids     MapModel.raids (raid_set's ranked set): the strip reads it, it does not recompute it
##   queue     view_town().queue (an Array, [] when empty)
##   vei       view_vei()
##   readout   MapModel.readout()
##   won       view_hud().won
##   opening   {text, target} from set_opening_ask ({} or empty text: none)
##   place     the standing line's fort id (next_place; "" or absent: the line alone)
## `prev` is the last pick ({} at first): while its rule still holds and its target still
## qualifies, the target is kept (no ping-pong between near-equal candidates), and the fall and
## Vei rules keep a kept pick to their exit thresholds (see the header).
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
	var raids: Array = inp.get("raids", [])
	var refilled := raids.filter(func(r): return str(r["why"]) == REFILLED)
	if not refilled.is_empty():
		return _raid(refilled, prev, c, fort_ids)
	if _vei_in_reach(inp, prev, c):
		return _vei(inp, c, fort_ids)
	var firsts := raids.filter(func(r): return str(r["why"]) == FIRST_CLEAR)
	if not firsts.is_empty():
		return _raid(firsts, prev, c, fort_ids)
	if (inp["queue"] as Array).is_empty():
		return _pick(QUEUE, "queue", str(c["queue_text"]), fort_ids)
	var place := str(inp.get("place", ""))
	var text := HudLogic.objective_text({})
	if place != "" and fort_ids.has(place):
		var named := ""
		for f in inp.get("forts", []):
			if str(f["id"]) == place:
				named = str(f.get("name", place))
		text = str(c["default_next_fmt"]) % [text, named]
	return _pick(DEFAULT, place, text, fort_ids)


## The quiet state: at least one held fort, every held fort's committed margin SAFE, none under
## a targeted tithe (a warned surge the clocks do not count), and the strip's `rule` not the
## opening, won or fall. `inp` is choose's input plus `margins` {id: word}.
static func quiet(inp: Dictionary, rule: String) -> bool:
	if rule == OPENING or rule == WON or rule == FALL:
		return false
	var held := IdleLogic.held_forts(inp.get("forts", []))
	if held.is_empty():
		return false
	var ms: Dictionary = inp.get("margins", {})
	for f in held:
		if str(ms.get(str(f["id"]), "")) != IdleLogic.SAFE or bool(f.get("tithe", {}).get("targeted", false)):
			return false
	return true


## The leave line, from the smallest IdleLogic.fort_horizon among the held forts (the view's
## fall_s): none, every fort holds; at least leave_safe_s,
## "Safe to leave: first fort falls in ~9 h"; under it, "If you leave, Old Sluice falls in ~3 min"
## (never called safe). Words in "next".
static func leave_text(inp: Dictionary, c := {}) -> String:
	if c.is_empty():
		c = cfg()
	var clocks: Dictionary = inp.get("clocks", {})
	var best := -1.0
	var who := {}
	for f in IdleLogic.held_forts(inp.get("forts", [])):
		var h := IdleLogic.fort_horizon(f, clocks.get(str(f["id"]), {}))
		if h >= 0.0 and (best < 0.0 or h < best):
			best = h
			who = f
	if best < 0.0:
		return str(c["leave_hold_text"])
	if best >= float(c["leave_safe_s"]):
		return str(c["leave_fall_fmt"]) % IdleLogic.fmt_fall(best)
	return str(c["leave_risk_fmt"]) % [str(who.get("name", who.get("id", ""))), IdleLogic.fmt_fall(best)]


## The raid line for the first of `list` (one kind of raid_set's entries), or `prev`'s target
## while it is still in the list.
static func _raid(list: Array, prev: Dictionary, c: Dictionary, fort_ids: Array) -> Dictionary:
	var pick: Dictionary = list[0]
	if str(prev.get("rule", "")) == RAID:
		for r in list:
			if str(r["fort"]["id"]) == str(prev.get("target", "")):
				pick = r
	var line := ready_line(pick["fort"], str(pick["why"]), c)
	return _pick(RAID, str(line["target"]), str(line["text"]), fort_ids)


## Vei in reach: can_begin, or her odds at next_vei_odds (next_vei_odds_exit after a VEI pick).
static func _vei_in_reach(inp: Dictionary, prev: Dictionary, c: Dictionary) -> bool:
	if bool(inp.get("vei", {}).get("can_begin", false)):
		return true
	var bar := float(c["next_vei_odds_exit"] if str(prev.get("rule", "")) == VEI else c["next_vei_odds"])
	var ro: Dictionary = inp.get("readout", {})
	return float(ro.get("readiness", ro.get("odds", 0.0))) >= bar  # a decision: the readiness, not the shown odds


static func _vei(inp: Dictionary, c: Dictionary, fort_ids: Array) -> Dictionary:
	var odds := float(inp.get("readout", {}).get("odds", 0.0))
	return _pick(VEI, "vei", str(c["vei_fmt"]) % roundi(clampf(odds, 0.0, 1.0) * 100.0), fort_ids)


static func _pick(rule: String, target: String, text: String, fort_ids: Array) -> Dictionary:
	return {"rule": rule, "target": target, "text": text, "action": AwayLogic.action(target, fort_ids)}


## The held fort the fall rule names: {fort, fall_s}, or {} when none qualifies. A fort enters
## under next_fall_warn_s; `prev`'s fort (after a FALL pick) stays under next_fall_warn_s x
## next_fall_exit_mult, and gives way only to a fort that falls in under switch_ratio of its time.
static func _fall(inp: Dictionary, prev: Dictionary, c: Dictionary) -> Dictionary:
	# the view's fall_s only (the garrison clock; there is no hold timer)
	var clocks: Dictionary = inp.get("clocks", {})
	var warn := float(c["next_fall_warn_s"])
	var kept_id := str(prev.get("target", "")) if str(prev.get("rule", "")) == FALL else ""
	var best := {}
	var kept := {}
	for f in IdleLogic.held_forts(inp.get("forts", [])):
		var s := float(clocks.get(str(f["id"]), {}).get("fall_s", -1.0))
		if s < 0.0:
			continue
		if kept_id != "" and str(f["id"]) == kept_id and s < warn * float(c["next_fall_exit_mult"]):
			kept = {"fort": f, "fall_s": s}
		if s < warn and (best.is_empty() or s < float(best["fall_s"])):
			best = {"fort": f, "fall_s": s}
	if not kept.is_empty() and (best.is_empty() or float(best["fall_s"]) >= float(kept["fall_s"]) * float(c["switch_ratio"])):
		return kept
	return best
