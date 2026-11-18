extends RefCounted
## The edges of an absence (E2b-2 T3.3c; IDLE I5, §7).
## - No run survives a close, a crash, a load or a gap above idle.gap_s (api-request #4): the dungeon's last
##   cmd_run_checkpoint is saved with the run (`pending_retreat`) and a load ends the run from it through the
##   normal writeback, before the catch-up, on both load paths: a retreat banks exactly that loot with no
##   flip and Relish at_fort; warden_beaten flips the fort; relish_died is a death; no checkpoint banks
##   nothing; a save without pending_retreat (older) forfeits the run as before. A gap in the open game ends
##   the run inside the frame that finds it, run_ended first, before its catch-up. Every run command on the
##   ended run gets its dead-run refusal, during the catch-up too, and changes nothing.
## - Relish walks home from a retaken fort (IDLE I5), live and in a catch-up alike: from the retake's moment
##   inside its step, relish_returned after its fort_retaken, view_relish().returned (saved); a retake
##   elsewhere, or while she is in its dungeon, moves nothing; a catch-up step ends at her arrival.
## - The away report (IDLE §7, api-request #7 d): a catch-up over a known window gives the expected lines in
##   each section (a retake, with and without Relish's walk home, a village lost, a build finished, queued
##   builds started with when and why, an overflow, a refill, husks, an empty queue); the stream totals are
##   the ledger's and the stores' changes; every number token parses under the map's two patterns; shown
##   and dismissing; nothing lost gives an empty losses; away_report is queued once.
## - R2: ready names the queue's head still waiting (a House on day1 with no bone and no mill, after 8 h: can't be
##   afforded, with bone's 0/s; a midgame Inn: affordable in its minutes), and prompts a raid when gold and bone are full and the
##   queue is empty (not when a store is under full_tol of its cap, nor with a gated entry queued).
## - W: the report reads as a returning player speaks: "<name> stopped for <time>, gold ran out: <what it stopped>"
##   (briefly under a minute; no tail when it stopped nothing), "<name> started <time> after you left, <why>", "at the
##   current income of", "needs relics: raid a fort", "Gold filled up, <n> not stored: queue more, or raid for relics"
##   (a ready line since E4 step 7), and the raid prompt in place of
##   "Queue empty"; every line of the reports is filled.
## Saves go under user://test_away_<pid>, removed at the end. The field is shrunk (8 × 6) and its pre-warm
## off, as tests/test_catchup.gd does.

var t := TestUtil.new()
var _dir := "user://test_away_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)
## Two checkpoints' loot: the second replaces the first.
const LOOT_A := {"relics": 1, "blueprints": [], "husks": [{"kind": "zombie"}], "remnants": [], "essence": 3}
const LOOT_B := {"relics": 2, "blueprints": ["embalmer"], "husks": [{"kind": "hulk"}, {"kind": "skeleton"}],
	"remnants": [{"aspect": "beef", "rarity": "rare", "magnitude": 2}], "essence": 7}


func run() -> int:
	t.suite("away")
	DirAccess.make_dir_recursive_absolute(_dir)
	_checkpoint_load()
	_checkpoint_revive()
	_checkpoint_chunked()
	_end_exceptions()
	_no_checkpoint()
	_old_save()
	_gap_ends_run()
	_dead_run()
	_walk_home_live()
	_walk_home_catchup()
	_walk_home_arrival()
	_arrival_same_step()
	_report()
	_never_head_line()
	_starved_hold()
	_grow_report()
	_cleanup()
	return t.failures


## Phase I P3 (the run's manager's ruling 1 on handoff 4: Grow acts during catch-up, so the away checks run a Grow-on
## case): pre_vei with Grow turned on (its save loads with it off), loaded 2 h on. Grow starts over a dozen upgrades in
## the catch-up; the report's build-finished line is every building_done of it in order, Grow's among them, with
## `lots` (api-request #19) the lots in the names' order, and every Grow start that finished inside the window is on it at
## its level. At market.price ×2: pre_vei's own gold net is negative (0.60 against 1.07 g/s), so Grow's upkeep test would
## pass over every pick (test_catchup.grow_price).
func _grow_report() -> void:
	var c := cfgs()
	c["economy"]["market"]["price"] = float(c["economy"]["market"]["price"]) * 2.0
	var s := _mk(c)
	s.cmd_debug_load_fixture("pre_vei")
	t.ok(s.cmd_set_stance("grow", true)["ok"], "(setup) Grow on in pre_vei")
	s.drain_events()
	var n := _away(c, s, "grow", 7200)
	var evs := n.catchup_events()
	var done_lots: Array = []
	var done_at := {}  # "lot/level" -> true for each building_done
	for e in evs:
		if e["type"] == "building_done":
			done_lots.append(str(e["lot_id"]))
			done_at["%s/%d" % [e["lot_id"], int(e["level"])]] = true
	var grows := 0
	var grow_done := 0
	for e in evs:
		if e["type"] == "grow_started":
			grows += 1
			if done_at.has("%s/%d" % [e["lot_id"], int(e["level"])]):
				grow_done += 1
	var rep := n.view_away()
	var line: Dictionary = {}
	for l in rep["gains"]:
		if l["kind"] == "build" and l.has("lots"):
			line = l
	var count := int(str(line.get("text", "0")).get_slice(" ", 0)) if not line.is_empty() else 0
	print("  [away] pre_vei with Grow on, 2 h away: %d Grow starts, %d of them finished; builds line: %s; ready: %s" % [grows, grow_done,
		str(line.get("text", "")), str(rep["ready"].map(func(l): return l["text"]))])
	t.ok(grows >= 10 and grow_done >= 10 and not line.is_empty() and line["lots"] == done_lots and count == done_lots.size(),
		"with Grow on: the report's build-finished line holds every finish of the catch-up in order (%d), Grow's %d among them, its lots in the names' order" % [
		done_lots.size(), grow_done])


## Phase I P3, ruling 3's hold timeout (the run's manager's option (iv) of 2026-11-18; STATE-API §10 A14): a staffed
## mill starved of input. midgame_2flips as shipped: its mill staffed, its pits eating every body (pits_first: rot
## 0.29 bodies/s against the pits' 0.6, no haul), bone at 50, the mill's level 2 (190 bone) queued and a House (which
## 50 bone pays) behind it, stepped until the head first reads dry (its never_since set), then saved. The head reads
## −1.0 with its producer staffed, so it holds the queue for queue.never_hold_s, then is skipped like the unstaffed
## case: loaded 1, 4, 8 and 24 h on, the House started at never_since + the hold, and the mill's level 2 stays skipped
## with A1's pits_first line (afford_starved_last_fmt; no move down, it is passed). The start is the same caught up in
## one go, in chunks and live (within a substep: Catchup.build_start_s clips at the hold's end). Revert proofs:
## head_never without held_out (nothing starts in 24 h); build_start_s without the hold clip (the one-go start
## lands on the next 10 s step after the hold's end, so the live check fails).
func _starved_hold() -> void:
	var c := TestUtil.configs()
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var hold := float(c["economy"]["queue"]["never_hold_s"])
	var s := _mk(c)
	s.cmd_debug_load_fixture("midgame_2flips")
	s.tick(0.5)
	var mill := ""
	for lot_id in s.town_sim.buildings:
		if str(s.town_sim.buildings[lot_id]["building_id"]) == "bone_mill":
			mill = str(lot_id)
	s.town_sim.bone = 50.0
	t.ok(mill != "" and s.cmd_queue_build("", mill)["ok"] and s.cmd_queue_build("house", str(BuildRules.free_lots(s, 1)[0]))["ok"],
		"(setup) midgame_2flips: the mill's level 2 on 50 bone, a House behind it")
	for i in 120:
		if s.build_queue[0].has("never_since"):
			break
		s.tick(s.substep_s())
	var since := float(s.build_queue[0].get("never_since", -1.0))
	var r0: Dictionary = s.view_town()["queue"][0]
	t.ok(since >= 0.0 and r0["status"] == "waiting_funds" and r0["starved"] == "pits_first" and float((s.town_sim.staffing["jobs"]["mill"] as Dictionary)["staffed"]) > 0.0,
		"(setup) the mill staffed, its pits first: the head reads dry and holds, never_since %.1f" % since)
	s.drain_events()
	# P3b (the P3 review's should-fix 2): an edited save whose never_since is ahead of its t loads at t, so the head
	# holds no longer than a hold that started now. Revert proof: SaveIO.apply taking it as saved (t + 5 000 s).
	var ed: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	ed["queue"][0]["never_since"] = s.t + 5000.0
	var el := _mk(c)
	t.ok(el.from_dict(ed)["ok"] and absf(float(el.build_queue[0].get("never_since", -1.0)) - el.t) <= 1e-6,
		"a saved never_since 5 000 s past the save's t loads clamped to t (%.1f, t %.1f)" % [
		float(el.build_queue[0].get("never_since", -1.0)) if not el.build_queue.is_empty() else -1.0, el.t])
	var starts := {}
	for away in [3600, 14400, 28800, 86400]:
		var n := _away(c, s, "hold", away)
		var st: Array = n.catchup_events().filter(func(e): return e["type"] == "queue_started")
		var rows: Array = n.view_town()["queue"]
		var row: Dictionary = rows[0] if rows.size() == 1 else {}
		var at := float(st[0]["t"]) if st.size() == 1 else -1.0
		starts[away] = at
		var want := str(rep["afford_starved_last_fmt"]).format({"name": StateViews._building_name(n, rep, "bone_mill", int(row.get("level", 0))),
			"short": StateViews._fmt_count(rep, ceilf(float((row.get("short", {"bone": 0.0}) as Dictionary)["bone"]))), "rate": StateViews._fmt_rate(rep, 0.0)})
		var l := _find(n.view_away(), "ready", "queue")
		print("  [away] the starved mill, %d h: the House at hold + %.6f s; ready %s" % [away / 3600, at - since - hold, str(l.get("text", ""))])
		t.ok(st.size() == 1 and st[0]["building_id"] == "house" and at >= since + hold and at <= since + hold + s.substep_s()
			and BuildRules.never_row(row) and row["building_id"] == "bone_mill" and row["starved"] == "pits_first" and l == {"text": want, "kind": "queue", "target": "queue"},
			"%d h away: the House started at the hold's end (%.3f s after never_since), the mill's level 2 is skipped with the pits_first line: %s" % [
			away / 3600, at - since, str(l.get("text", ""))])
	var ch := _away(c, s, "hold", 3600, true)
	var frames := 0
	while ch.catching_up() and frames < 5000:
		ch.tick(1.0 / 60.0, ch.max_substeps_per_frame())
		frames += 1
	var cst: Array = ch.catchup_events().filter(func(e): return e["type"] == "queue_started")
	var live := _away(c, s, "hold", 0)
	var lt := -1.0
	for i in int((hold + 30.0) / live.substep_s()):
		live.tick(live.substep_s())
		var ls: Array = live.drain_events().filter(func(e): return e["type"] == "queue_started")
		if not ls.is_empty():
			lt = float(ls[0]["t"])
			break
	var one := float(starts[3600])
	t.ok(cst.size() == 1 and absf(float(cst[0]["t"]) - one) <= 1e-6 and lt >= 0.0 and absf(lt - one) <= live.substep_s(),
		"the hold counts the same caught up in one go (%.6f), in chunks (%.6f) and live (%.6f), within a substep" % [
		one - since, (float(cst[0]["t"]) if cst.size() == 1 else -1.0) - since, lt - since])


## Phase I P3, ruling 3: a head with no path to its funds is skipped (BuildRules.head_never), and the away report still
## names it with its store's rate and lever, the never form without the move down: "Raising Pit can't be afforded at the
## current income of 0/s bone: build a Bone Mill". Revert proof: without away_report's never_row branch, no queue line.
func _never_head_line() -> void:
	var c := TestUtil.configs()
	var s := _mk(c)
	s.cmd_new_game(1)
	s.tick(s.substep_s())
	s.town_sim.gold = 100.0
	s.town_sim.bone = 30.0
	t.ok(s.cmd_queue_build("raising_pit", "lot-05")["ok"], "(setup) a Raising Pit queued with no mill")
	var n := _away(c, s, "never_head", 3600)
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var want := str(rep["afford_never_last_fmt"]).format({"name": "Raising Pit", "store": str(rep["afford_stores"]["bone"]),
		"rate": "0/s", "raise": str(rep["afford_raise"]["bone"])})
	var texts: Array = (n.view_away()["ready"] as Array).map(func(l): return str(l["text"]))
	t.ok(n.build_queue.size() == 1 and BuildRules.never_row(n.view_town()["queue"][0]) and texts.has(want),
		"after 1 h away the Pit is still skipped, and the report reads \"%s\": %s" % [want, str(texts)])
	# Phase I P3's housekeeping: with a Bone Mill under construction (level 0) the lever is afford_raise_building's,
	# not "build a Bone Mill" (one is started). Revert proof: without afford_text's _producer_constructing branch the
	# line reads afford_raise's words and this fails
	var m := _mk(c)
	m.cmd_new_game(1)
	m.tick(m.substep_s())
	m.town_sim.gold = 100.0
	m.town_sim.bone = 30.0
	t.ok(m.cmd_queue_build("bone_mill", "lot-06")["ok"] and m.cmd_queue_build("raising_pit", "lot-05")["ok"],
		"(setup) a Bone Mill (gold only), then a Raising Pit")
	for i in 30:
		m.tick(m.substep_s())
	var mill_lot: Dictionary = m.town_sim.buildings.get("lot-06", {})
	var prow := {}
	for r in m.view_town()["queue"]:
		if str(r["building_id"]) == "raising_pit":
			prow = r
	t.ok(str(mill_lot.get("state", "")) == "constructing" and int(mill_lot.get("level", -1)) == 0 and not prow.is_empty()
		and float(prow["affordable_in_s"]) < 0.0,
		"(setup) the Mill is under construction at level 0 and the Pit can't be afforded: %s, %s" % [str(mill_lot), str(prow)])
	var line := StateViews.afford_text(m, rep, prow, "bone", BuildRules.queue_net(m), false)
	var want_b := str(rep["afford_never_last_fmt"]).format({"name": "Raising Pit", "store": str(rep["afford_stores"]["bone"]),
		"rate": "0/s", "raise": str(rep["afford_raise_building"]["bone"])})
	t.ok(line == want_b and not line.contains(str(rep["afford_raise"]["bone"])),
		"a Bone Mill under construction: \"%s\" (want \"%s\")" % [line, want_b])


# ------------------------------------------------------------------------------ helpers ----
## The shipped configs with the field shrunk and its pre-warm off (test_catchup.gd's), then `over`
## ({"file.section.key": value}).
static func cfgs(over := {}) -> Dictionary:
	var c := TestUtil.configs()
	var fld: Dictionary = c["realm"]["field"]
	fld["w"] = 8
	fld["h"] = 6
	c["economy"]["sim"]["prewarm_ticks"] = 0
	for path in over:
		var keys: PackedStringArray = str(path).split(".")
		var d: Dictionary = c
		for i in keys.size() - 1:
			d = d[keys[i]]
		d[keys[-1]] = over[path]
	return c


func _mk(c: Dictionary) -> GameState:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = _dir
	return s


## A new game a few substeps in with two big undead in the party and Relish in Old Sluice's dungeon (the
## first dungeon). Returns the state; the seed is its meta "seed".
func _raid(c: Dictionary, clones := 0) -> GameState:
	var s := _mk(c)
	s.cmd_new_game(1)
	s.tick(2.0)
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	s.cmd_debug_grant({"big_undead": 2})
	var bus: Array = s.view_big_undead()["big_undead"]
	s.cmd_set_party([bus[0]["uid"], bus[1]["uid"]])
	s.clones_ready = clones
	var b := s.cmd_begin_dungeon("old-sluice")
	t.ok(b["ok"], "(setup) a raid is open at Old Sluice")
	s.set_meta("seed", b["seed"])
	s.drain_events()
	return s


## Saves `s` to `slot` at CLOCK; a fresh state loads it with the clock `away` s on.
func _away(c: Dictionary, s: GameState, slot: String, away: int, chunked := false) -> GameState:
	s.clock_override = CLOCK
	t.ok(s.cmd_save(slot)["ok"], "(setup) %s saved" % slot)
	s.drain_events()
	var n := _mk(c)
	n.clock_override = CLOCK + away
	n.set_meta("saved_t", s.t)
	n.set_meta("load", n.cmd_load(slot, chunked))
	return n


## What `s` holds of the loot kinds: relics, essence, blueprints, husk kinds, remnant aspects.
static func _holds(s: GameState) -> Dictionary:
	var husks: Array = s.husks.map(func(h): return str(h["kind"]))
	var rems: Array = s.remnants.map(func(r): return "%s/%s/%d" % [r["aspect"], r["rarity"], int(r["magnitude"])])
	return {"relics": s.relics, "essence": s.essence, "blueprints": s.blueprints.duplicate(), "husks": husks, "remnants": rems}


## `before` with `loot` banked on top (no cap reached in these tests).
static func _plus(before: Dictionary, loot: Dictionary) -> Dictionary:
	var out := before.duplicate(true)
	out["relics"] += int(loot["relics"])
	out["essence"] += int(loot["essence"])
	for b in loot["blueprints"]:
		if not out["blueprints"].has(b):
			out["blueprints"].append(b)
	for h in loot["husks"]:
		out["husks"].append(str(h["kind"]))
	for r in loot["remnants"]:
		out["remnants"].append("%s/%s/%d" % [r["aspect"], r["rarity"], int(r["magnitude"])])
	return out


static func _types(evs: Array) -> Array:
	return evs.map(func(e): return str(e["type"]))


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)


# ------------------------------------------------------------- §1 the run's end on load ----
## A checkpoint, then a second (it replaces the first), then a save and a load: the load banks exactly the
## last checkpoint, with no flip and Relish at_fort at its fort, through the normal writeback (a 0 s load is
## the live retreat with that loot: the same to_dict and events). Its events are queued before the catch-up
## (a 300 s load: loot_banked at the save's t, in the queue, not among the catch-up's events).
func _checkpoint_load() -> void:
	var c := cfgs()
	var s := _raid(c)
	var run_id := int(s.run["run_id"])
	var before := _holds(s)
	var held0: bool = s.view_fort("old-sluice")["held"]
	t.ok(s.cmd_run_checkpoint(run_id, LOOT_A)["ok"] and s.cmd_run_checkpoint(run_id, LOOT_B, "retreated")["ok"], "(setup) two checkpoints")
	var d := s.to_dict()
	t.ok(d.has("pending_retreat") and d["pending_retreat"] == {"run_id": run_id, "kind": "raid", "fort_id": "old-sluice",
		"seed_rev": int(s.run["seed_rev"]), "loot": LOOT_B, "outcome": "retreated"} and d["relish"]["state"] == "at_fort"
		and d["relish"]["at"] == "old-sluice" and JSON.stringify(d).find("in_dungeon") == -1,
		"the save holds the run as pending_retreat with the last checkpoint; Relish at_fort, never in_dungeon: %s" % str(d.get("pending_retreat")))
	var n := _away(c, s, "cp", 0)
	var evs := n.drain_events()
	t.ok(_holds(n) == _plus(before, LOOT_B), "the load banks exactly the last checkpoint: %s" % str(_holds(n)))
	t.ok(n.run.is_empty() and n.view_relish()["state"] == "at_fort" and n.view_relish()["at"] == "old-sluice"
		and n.view_fort("old-sluice")["held"] == held0 and int(n.view_fort("old-sluice")["flipped_count"]) == 0,
		"no flip, Relish at_fort at Old Sluice, the run closed")
	t.ok(n.applied_runs.has(run_id) and n.party_uids.size() == 2, "the run is an applied run; the party is intact")
	t.ok(_types(evs) == ["loot_banked"] and int(evs[0]["relics"]) == 2 and int(evs[0]["essence"]) == 7
		and evs[0]["blueprints"] == ["embalmer"] and (evs[0]["minted"] as Array).size() == 3 and float(evs[0]["t"]) == s.t,
		"its loot_banked is queued at the save's t: %s" % str(evs))
	# the same retreat applied live, on the state that was saved
	var live := _mk(c)
	live.from_dict(JSON.parse_string(JSON.stringify(d)))  # (from_dict itself ends the saved run the same way)
	var why: Array = []
	_diff(live.to_dict(), n.to_dict(), 0.0, "d", why)
	t.ok(why.is_empty(), "the load is from_dict's end of the run: the same to_dict %s" % str(why.slice(0, 4)))
	var ref := _raid(c)
	var rid := int(ref.run["run_id"])
	ref.cmd_run_checkpoint(rid, LOOT_B)
	var r := ref.apply_result("raid", StateRuns.end_result(ref.run, LOOT_B, "retreated"))
	why = []
	var rd := ref.to_dict()
	var nd := n.to_dict()
	for k in ["applied_runs", "next_run_id"]:
		rd.erase(k)
		nd.erase(k)
	_diff(rd, nd, 0.0, "d", why)
	t.ok(r["ok"] and why.is_empty(), "a 0 s load is the live retreat with that loot: the same to_dict %s" % str(why.slice(0, 4)))
	# with time away: the run ends first, its events queued; the catch-up's are collected
	var m := _away(c, _with_checkpoint(c, LOOT_B), "cp2", 300)
	var q := m.drain_events()
	var lb := q.filter(func(e): return e["type"] == "loot_banked")
	t.ok(lb.size() == 1 and float(lb[0]["t"]) == float(m.get_meta("saved_t")) and _holds(m) == _plus(before, LOOT_B)
		and not m.catchup_events().any(func(e): return e["type"] == "loot_banked"),
		"300 s away: loot_banked is queued at the save's t (before the catch-up), not collected: %s" % str(_types(q)))
	t.ok(m.t == float(m.get_meta("saved_t")) + 300.0 and m.view_relish()["state"] == "at_fort", "then the catch-up ran its 300 s with Relish at_fort")


## api-request #20 (dungeon-i; Phase I P3): the checkpoint carries the run's phylactery revives. A raid opened with 2
## charges checkpoints LOOT_B with one revive; the save's pending_retreat carries revived_in_place 1, and the load's end
## of the run spends that charge (1 left), as the live retreat with the revive does. Out of bounds (−1, above the
## seed's min(charges, max_per_dungeon)) is `invalid`; a checkpoint with none saves as before (no key); a save whose
## count is above its charges is corrupt. Revert proof: end_open passing 0 revives (the charge comes back: 2 left).
func _checkpoint_revive() -> void:
	var c := cfgs()
	var s := _mk(c)
	s.cmd_new_game(1)
	s.tick(2.0)
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	s.cmd_debug_grant({"big_undead": 2})
	var bus: Array = s.view_big_undead()["big_undead"]
	s.cmd_set_party([bus[0]["uid"], bus[1]["uid"]])
	s._phylactery_charges = 2
	var b := s.cmd_begin_dungeon("old-sluice")
	var sd: Dictionary = b.get("seed", {}) if b.has("seed") and b["seed"] is Dictionary else s.view_dungeon_seed("old-sluice")
	var cap := StateRuns.revive_cap(sd)
	t.ok(b["ok"] and cap >= 1, "(setup) a raid at Old Sluice with 2 charges (revive cap %d)" % cap)
	var run_id := int(s.run["run_id"])
	t.ok(s.cmd_run_checkpoint(run_id, LOOT_B, "retreated", -1)["reason"] == "invalid" and s.cmd_run_checkpoint(run_id, LOOT_B, "retreated", cap + 1)["reason"] == "invalid",
		"a revive count below 0 or above the seed's cap (%d) is invalid" % cap)
	t.ok(s.cmd_run_checkpoint(run_id, LOOT_B)["ok"] and not (s.to_dict()["pending_retreat"] as Dictionary).has("revived_in_place"),
		"a checkpoint with no revive saves pending_retreat as before (no revived_in_place)")
	t.ok(s.cmd_run_checkpoint(run_id, LOOT_B, "retreated", 1)["ok"], "a checkpoint with one revive")
	var d := s.to_dict()
	t.ok(int((d["pending_retreat"] as Dictionary).get("revived_in_place", 0)) == 1, "the save's pending_retreat carries it: %s" % str(d["pending_retreat"]))
	var n := _away(c, s, "cp_rev", 0)
	t.ok(n.run.is_empty() and n._phylactery_charges == 1, "the load's end of the run spends the charge: %d of 2 left" % n._phylactery_charges)
	var ref := _mk(c)
	ref.from_dict(JSON.parse_string(JSON.stringify(d)))
	var live := StateRuns.end_result({"run_id": run_id, "seed_rev": int(d["pending_retreat"]["seed_rev"]), "fort_id": "old-sluice"}, LOOT_B, "retreated", 1)
	t.ok(ref._phylactery_charges == 1 and int(live["revived_in_place"]) == 1, "from_dict ends it the same way, the result carrying the revive")
	var bad: Dictionary = JSON.parse_string(JSON.stringify(d))
	bad["pending_retreat"]["revived_in_place"] = 3
	var cr := _mk(c)
	t.ok(not cr.from_dict(bad)["ok"], "a pending_retreat with more revives (3) than the save's charges (2) is corrupt")
	# P3b (the P3 review's should-fix 2): within the charges (2) but over the seed's max_per_dungeon (1), an edited
	# save's count is clamped to 1 on load, so the run ends as the retreat it was (loot banked, one charge spent), not
	# forfeited. Revert proof: apply_pending without the clamp (apply_result refuses 2 revives: the run is forfeited).
	var over: Dictionary = JSON.parse_string(JSON.stringify(d))
	over["pending_retreat"]["revived_in_place"] = 2
	var co := _mk(c)
	var co_ok: bool = co.from_dict(over)["ok"]
	var banked := co.drain_events().filter(func(e): return e["type"] == "loot_banked")
	t.ok(int(sd["phylactery_max_per_dungeon"]) == 1 and co_ok and co.run.is_empty() and co._phylactery_charges == 1 and banked.size() == 1,
		"2 revives in a save whose seed allows 1 a dungeon: clamped to 1, the run ends as a retreat (%d charge left, %d loot_banked)" % [
		co._phylactery_charges, banked.size()])


## A raid with one checkpoint of `loot` (and `outcome`), its t in meta "saved_t" once saved by _away.
func _with_checkpoint(c: Dictionary, loot: Dictionary, outcome := "retreated", clones := 0) -> GameState:
	var s := _raid(c, clones)
	t.ok(s.cmd_run_checkpoint(int(s.run["run_id"]), loot, outcome)["ok"], "(setup) a %s checkpoint" % outcome)
	return s


## The shell's chunked load (cmd_load(slot, true)) ends the run before the catch-up's first chunk: the loot
## is banked and loot_banked queued at the save's t when it returns, and the chunks leave it in the queue.
func _checkpoint_chunked() -> void:
	var c := cfgs()
	var s := _with_checkpoint(c, LOOT_B)
	var before := _holds(s)
	var t0 := s.t
	s.clock_override = CLOCK
	s.cmd_save("chunk")
	var n := _mk(c)
	n.clock_override = CLOCK + 3600
	var r := n.cmd_load("chunk", true)
	t.ok(r["ok"] and n.catching_up() and n.t == t0 and _holds(n) == _plus(before, LOOT_B) and n.run.is_empty()
		and n.view_relish()["state"] == "at_fort", "cmd_load(slot, true): the run is over and its loot banked before the first chunk")
	var q: Array = []
	var frames := 0
	while n.catching_up() and frames < 1000:
		n.tick(1.0 / 60.0, n.max_substeps_per_frame())
		frames += 1
	q.append_array(n.drain_events())
	var lb := q.filter(func(e): return e["type"] == "loot_banked")
	t.ok(not n.catching_up() and lb.size() == 1 and float(lb[0]["t"]) == t0 and q[0]["type"] == "loot_banked",
		"after %d frames the loot_banked is still queued first, at the save's t: %s" % [frames, str(_types(q).slice(0, 4))])


## The two exits that already happened while the player was there: warden_beaten flips the fort (and
## banks), relish_died is a death (the party lost, a clone spent, Relish dead until her respawn, then home), as
## apply_result treats them.
func _end_exceptions() -> void:
	var c := cfgs()
	var w := _with_checkpoint(c, LOOT_B, "warden_beaten")
	var n := _away(c, w, "win", 0)
	var evs := n.drain_events()
	var vf := n.view_fort("old-sluice")
	t.ok(vf["held"] and int(vf["flipped_count"]) == 1 and n.cleared_forts.has("old-sluice") and n.first_dungeon_id == ""
		and n.view_relish()["state"] == "at_fort" and _types(evs) == ["loot_banked", "fort_flipped"],
		"warden_beaten: the fort flips, its first clear is spent, Relish at_fort: %s" % str(_types(evs)))
	var dd := _with_checkpoint(c, LOOT_A, "relish_died", 1)
	var deaths := int(dd.stats["deaths"])
	var m := _away(c, dd, "died", 0)
	evs = m.drain_events()
	var clone_s := float(c["backups"]["backups"]["clone_respawn_s"])
	t.ok(_types(evs) == ["loot_banked", "relish_died"] and evs[1]["outcome"] == "clone" and evs[1]["at"] == "old-sluice"
		and m.clones_ready == 0 and m.party_uids.is_empty() and m.big_undead.is_empty() and m.view_relish()["state"] == "dead"
		and m.view_relish()["dead_s_left"] == clone_s and m.view_relish()["respawn_with_clone"]
		and int(m.stats["deaths"]) == deaths + 1 and not m.view_fort("old-sluice")["held"],
		"relish_died: a death (a clone spent, the party lost, Relish dead for clone_respawn_s, no flip): %s" % str(_types(evs)))
	m.tick(clone_s)
	t.ok(m.drain_events().filter(func(e): return e["type"] == "relish_respawned").size() == 1 and m.view_relish()["state"] == "home",
		"then she respawns home from the clone after clone_respawn_s")


## No checkpoint: a save mid-run banks nothing, as before; the run is a retreat with empty loot (no flip,
## Relish at_fort, the party intact).
func _no_checkpoint() -> void:
	var c := cfgs()
	var s := _raid(c)
	var before := _holds(s)
	var run_id := int(s.run["run_id"])
	t.ok(s.to_dict()["pending_retreat"]["loot"] == StateRuns.empty_loot() and s.to_dict()["pending_retreat"]["outcome"] == "retreated",
		"no checkpoint: pending_retreat has empty loot and retreated")
	var n := _away(c, s, "none", 0)
	var evs := n.drain_events()
	t.ok(_holds(n) == before and n.run.is_empty() and n.view_relish()["state"] == "at_fort" and n.party_uids.size() == 2
		and not n.view_fort("old-sluice")["held"] and n.applied_runs.has(run_id), "nothing banked, at_fort, the party intact, no flip")
	t.ok(_types(evs) == ["loot_banked"] and int(evs[0]["relics"]) == 0 and int(evs[0]["essence"]) == 0 and (evs[0]["minted"] as Array).is_empty(),
		"its loot_banked banks nothing: %s" % str(evs))


## A save written before T3.3c has no pending_retreat: the run is forfeited as before (no writeback, no
## event, not an applied run, Relish at_fort). A malformed pending_retreat makes the save corrupt.
func _old_save() -> void:
	var c := cfgs()
	var s := _with_checkpoint(c, LOOT_B)
	var before := _holds(s)
	var run_id := int(s.run["run_id"])
	var d := s.to_dict()
	d.erase("pending_retreat")
	var n := _mk(c)
	t.ok(n.from_dict(JSON.parse_string(JSON.stringify(d)))["ok"], "(setup) the old-style save loads")
	t.ok(_holds(n) == before and n.run.is_empty() and n.view_relish()["state"] == "at_fort" and n.drain_events().is_empty()
		and not n.applied_runs.has(run_id) and n.cmd_begin_dungeon("old-sluice")["ok"],
		"without pending_retreat the run is forfeited as before: nothing banked, no event, not applied, a new run opens")
	var bad := s.to_dict()
	for patch in [["outcome", "won"], ["kind", "town"], ["fort_id", "vei"], ["loot", {"relics": -1}], ["run_id", "x"]]:
		var b := bad.duplicate(true)
		b["pending_retreat"][patch[0]] = patch[1]
		t.ok(_mk(c).from_dict(b) == {"ok": false, "reason": "corrupt"}, "a pending_retreat with %s = %s is corrupt" % [patch[0], str(patch[1])])


# ----------------------------------------------------------------- §1 the gap in the open game ----
## A frame above idle.gap_s with a run open (the machine asleep in a dungeon): inside that frame the run ends
## from its checkpoint, run_ended {run_id, kind, outcome, cause: "gap"} first, then the writeback's events,
## all queued live, then the catch-up runs (still under way after the frame, the run already closed). A gap of
## idle.report_min_s or more collects its catch-up's events but still queues these.
func _gap_ends_run() -> void:
	var c := cfgs()
	for gap in [120.0, 900.0]:
		var s := _with_checkpoint(c, LOOT_B, "warden_beaten")
		var run_id := int(s.run["run_id"])
		var t0 := s.t
		var cap := s.max_substeps_per_frame()
		s.tick(gap, cap)
		var q := s.drain_events()
		t.ok(s.run.is_empty() and s.catching_up() and s.view_relish()["run_id"] == -1 and s.view_fort("old-sluice")["held"],
			"a %.0f s gap: inside its frame the run is over (flipped) and the catch-up is under way" % gap)
		t.ok(q.size() >= 3 and q[0] == {"type": "run_ended", "run_id": run_id, "kind": "raid", "outcome": "warden_beaten", "cause": "gap", "t": t0}
			and q[1]["type"] == "loot_banked" and q[2]["type"] == "fort_flipped" and float(q[1]["t"]) == t0,
			"run_ended comes first, then loot_banked and fort_flipped, at the gap's start: %s" % str(_types(q).slice(0, 4)))
		var frames := 0
		while s.catching_up() and frames < 1000:
			s.tick(1.0 / 60.0, cap)
			q.append_array(s.drain_events())
			frames += 1
		var late := q.slice(3).all(func(e): return float(e["t"]) >= t0)
		var collected := s.catchup_events()
		t.ok(not s.catching_up() and s.t >= t0 + gap and late and not collected.any(func(e): return e["type"] in ["run_ended", "loot_banked"]),
			"then the catch-up ran (%d frames): none of the run's events among its %d collected" % [frames, collected.size()])
	# a boss run is forfeited by a gap: run_ended (retreated), no writeback, the party intact, Relish at_vei
	var b := _mk(c)
	b.cmd_debug_load_fixture("pre_vei")
	var party := b.party_uids.duplicate()
	var fight: float = b.ledger()["sinks"]["vei_fight"]
	var bb := b.cmd_begin_boss()
	b.drain_events()
	b.tick(100.0, b.max_substeps_per_frame())
	var bq := b.drain_events()
	t.ok(bb["ok"] and bq[0]["type"] == "run_ended" and bq[0]["kind"] == "boss" and bq[0]["outcome"] == "retreated"
		and not bq.any(func(e): return e["type"] == "vei_result") and b.party_uids == party and b.run.is_empty()
		and b.view_relish()["state"] == "at_vei" and not b.applied_runs.has(int(bb["run_id"])) and float(b.ledger()["sinks"]["vei_fight"]) == fight,
		"a boss run's gap: run_ended (boss, retreated), forfeited (no vei_result, no vei_fight sink, the party intact, Relish at_vei, not applied)")


## Every run command on an ended run is refused cleanly, during the gap's catch-up and after it, and changes
## nothing: cmd_run_checkpoint and cmd_abort_dungeon say no_run, apply_result duplicate_run (the ended raid's
## id is an applied run) or wrong_run (an ended boss run, not applied, as cmd_abort_dungeon leaves it).
func _dead_run() -> void:
	var c := cfgs()
	var s := _with_checkpoint(c, LOOT_B)
	var sd: Dictionary = s.get_meta("seed")
	var run_id := int(sd["run_id"])
	var late := StateRuns.end_result({"run_id": run_id, "seed_rev": sd["seed_rev"], "fort_id": "old-sluice", "seed": sd}, LOOT_A, "warden_beaten")
	s.tick(200.0, s.max_substeps_per_frame())
	for phase in ["during the catch-up", "after it"]:
		if phase == "after it":
			while s.catching_up():
				s.tick(1.0 / 60.0, s.max_substeps_per_frame())
		s.drain_events()
		var d0 := s.to_dict()
		var rv := s.rev
		var got := [s.cmd_run_checkpoint(run_id, LOOT_A, "warden_beaten"), s.cmd_abort_dungeon(), s.apply_result("raid", late)]
		t.ok(got[0] == {"ok": false, "reason": "no_run"} and got[1] == {"ok": false, "reason": "no_run", "run_id": -1}
			and got[2]["reason"] == "duplicate_run" and s.rev == rv and s.to_dict() == d0 and s.drain_events().is_empty()
			and s.catching_up() == (phase == "during the catch-up"),
			"%s: checkpoint no_run, abort no_run, the late result duplicate_run, nothing changed: %s" % [phase, str(got.map(func(r): return r["reason"]))])
	var b := _mk(c)
	b.cmd_debug_load_fixture("pre_vei")
	var bb := b.cmd_begin_boss()
	var bres := {"v": 2, "run_id": bb["run_id"], "seed_rev": bb["seed_rev"], "won": true, "fronts_cleared": [], "relish_deaths": 0,
		"backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "backlog_spent": 0.0}
	t.ok(b.cmd_run_checkpoint(int(bb["run_id"]), LOOT_A)["reason"] == "wrong_kind", "a boss run has nothing to bank: wrong_kind")
	b.tick(100.0, b.max_substeps_per_frame())
	b.drain_events()
	var bd0 := b.to_dict()
	var brv := b.rev
	var bgot := [b.cmd_run_checkpoint(int(bb["run_id"]), LOOT_A), b.cmd_abort_dungeon(), b.apply_result("boss", bres)]
	t.ok(bgot.map(func(r): return r["reason"]) == ["no_run", "no_run", "wrong_run"] and b.rev == brv and b.to_dict() == bd0 and b.catching_up(),
		"an ended boss run during its catch-up: no_run, no_run, wrong_run (not an applied run), nothing changed: %s" % str(bgot.map(func(r): return r["reason"])))


# ------------------------------------------------------------- §2 Relish walks home ----
## A new game with Greywall held and contested (no grace), her living there, no WAR (all FLOOD) and Relish
## standing at `relish_at`: the garrison sits at 0, so it is broken hold.break_s later, less the 0.3 s its zero
## clock starts at (so the retake lands inside a substep, at 121.7 s). With `siege`, a big undead sieges it too.
func _greywall(c: Dictionary, relish_at := "greywall", siege := false) -> GameState:
	var s := _mk(c)
	s.cmd_new_game(1)
	s.tick(2.0)
	if siege:
		s.cmd_debug_grant({"big_undead": 1})
		s.cmd_place_big_undead(s.view_big_undead()["big_undead"][0]["uid"], "fort:greywall")
	s.cmd_debug_set_state({"relish_at": relish_at, "valve": {"work": 0.0, "war": 0.0, "flood": 1.0},
		"forts": {"greywall": {"living": 60.0, "undead": 0.0, "dead": 0.0}}})
	s.realm.hold("greywall", 0.0)
	s.realm.fort_by_id("greywall")["zero_s"] = 0.3
	s.drain_events()
	return s


## Ticks `s` at 0.5 s until a fort is retaken (at most 400 substeps); returns that substep's events.
func _until_retaken(s: GameState) -> Array:
	for i in 400:
		s.tick(0.5)
		var evs := s.drain_events()
		if evs.any(func(e): return e["type"] == "fort_retaken"):
			return evs
	return []


## Live: the fort she stands at is retaken, and from the retake's moment inside its substep she walks home
## to Covington at relish.travel_speed: relish_returned {fort_id, cause: "retaken"} after its fort_retaken
## and the siege's big_undead_returned, at the same t; view_relish().returned shows it, and it is saved; she
## arrives home. A retake of a fort she isn't at moves nothing; nor does one while she is in its dungeon (the
## run goes on, and she stands there when it ends).
func _walk_home_live() -> void:
	var c := cfgs()
	var s := _greywall(c, "greywall", true)
	t.ok(s.view_relish()["returned"] == {} and not s.to_dict()["relish"].has("returned"), "(setup) nothing returned yet: returned is {}, not saved")
	var got := _until_retaken(s).filter(func(e): return e["type"] in ["fort_retaken", "big_undead_returned", "relish_returned"])
	var after := s.view_relish()
	var t_end := s.t
	t.ok(got.size() == 3 and _types(got) == ["fort_retaken", "big_undead_returned", "relish_returned"]
		and got[2] == {"type": "relish_returned", "fort_id": "greywall", "cause": "retaken", "t": got[0]["t"]},
		"fort_retaken, big_undead_returned, then relish_returned {greywall, retaken} at its t: %s" % str(got))
	var t_r := float(got[0]["t"]) if not got.is_empty() else 0.0
	var gw := s._node_xy("greywall")
	var walked := sqrt(pow(float(after["pos"][0]) - gw[0], 2.0) + pow(float(after["pos"][1]) - gw[1], 2.0))
	t.ok(t_r > t_end - 0.5 and t_r < t_end and after["state"] == "travelling" and after["target"] == "covington"
		and absf(walked - s.travel_speed() * (t_end - t_r)) < 1e-6,
		"she starts home from the retake's moment inside the substep: %.4f px walked by its end (%.4f s at %.0f px/s)" % [walked, t_end - t_r, s.travel_speed()])
	t.ok(after["returned"] == {"fort_id": "greywall", "cause": "retaken", "t": t_r}, "view_relish().returned: %s" % str(after["returned"]))
	for i in 20:
		s.tick(0.5)
	var home := s.view_relish()
	t.ok(home["state"] == "home" and home["at"] == "covington" and home["returned"]["fort_id"] == "greywall", "she arrives home; returned keeps the last one")
	var n := _mk(c)
	n.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	t.ok(n.view_relish()["returned"] == home["returned"] and s.to_dict()["relish"]["returned"] == home["returned"], "returned is saved and loads")
	var bad := s.to_dict()
	bad["relish"]["returned"] = {"fort_id": "nowhere", "cause": "retaken", "t": 1.0}
	t.ok(_mk(c).from_dict(bad) == {"ok": false, "reason": "corrupt"}, "a saved returned naming an unknown fort is corrupt")
	# a retake elsewhere moves nothing
	var e := _greywall(c, "ashgate")
	var seen := _types(_until_retaken(e))
	t.ok(seen.has("fort_retaken") and not seen.has("relish_returned") and e.view_relish()["state"] == "at_fort" and e.view_relish()["at"] == "ashgate"
		and e.view_relish()["returned"] == {}, "Greywall retaken with Relish at Ashgate: she stays, nothing returned")
	# in its dungeon: the run goes on; when it ends she stands at the fort
	var d := _greywall(c, "greywall")
	var b := d.cmd_begin_dungeon("greywall")
	seen = _types(_until_retaken(d))
	t.ok(b["ok"] and seen.has("fort_retaken") and not seen.has("relish_returned") and d.view_relish()["state"] == "in_dungeon" and not d.run.is_empty(),
		"retaken while she is in its dungeon: the run goes on, no walk")
	var r := d.apply_result("raid", StateRuns.end_result(d.run, StateRuns.empty_loot(), "retreated"))
	t.ok(r["ok"] and d.view_relish()["state"] == "at_fort" and d.view_relish()["at"] == "greywall" and d.view_relish()["returned"] == {},
		"the run ends as a retreat: she stands at Greywall, nothing returned")


## Vei's and Covington's stocks of `a` against `b` (each within idle.catchup_tol of max(|b|, 1)), as
## [the ids that differ]. Covington's living are left out: they follow the villages the field gives (its
## migrants), and on this shrunk field with no pre-warm a new game's first 10 min end with 1 village yours live
## and none caught up wherever Relish stands (16 living against 10.1 with her at Greywall, at Ashgate or home):
## the field's residual (IDLE §4), not her walk.
static func _stocks_differ(a: GameState, b: GameState, tol: float) -> Array:
	var out: Array = []
	var pairs := {
		"backlog": [a.realm.vei["undead_queue"], b.realm.vei["undead_queue"]], "vei_dead": [a.realm.vei["dead_queue"], b.realm.vei["dead_queue"]],
		"pool": [a.realm.vei["living_pool"], b.realm.vei["living_pool"]], "workers": [a.town_sim.workers, b.town_sim.workers],
		"gold": [a.town_sim.gold, b.town_sim.gold], "bone": [a.town_sim.bone, b.town_sim.bone],
	}
	for k in pairs:
		var x := float(pairs[k][0])
		var y := float(pairs[k][1])
		if absf(x - y) > tol * maxf(absf(y), 1.0):
			out.append("%s %.4f vs %.4f" % [k, x, y])
	return out


## The same through a catch-up (one simulation, I1): saved before the retake and loaded 10 min later at 10 s
## steps (idle.catchup_max_steps 60), she is home with the same `returned` (its t within a step of live's)
## and Vei's and Covington's stocks within idle.catchup_tol of live 0.5 s. With her walk longer than a step
## (relish.travel_speed 10 px/s, 31.7 s from Greywall), a catch-up step ends at her arrival, at its own time.
func _walk_home_catchup() -> void:
	for speed in [0.0, 10.0]:
		var over := {"economy.idle.catchup_max_steps": 60}
		if speed > 0.0:
			over["realm.relish.travel_speed"] = speed
		var c := cfgs(over)
		var s := _greywall(c)
		var live := _mk(c)
		live.from_dict(s.to_dict())
		live.drain_events()
		live.tick(600.0)
		var n := _away(c, s, "walk", 600)
		var lr := live.view_relish()
		var nr := n.view_relish()
		var lt := float(lr["returned"].get("t", -1.0))
		var nt := float(nr["returned"].get("t", -1.0))
		var label := "the shipped speed" if speed == 0.0 else "%.0f px/s" % speed
		t.ok(lr["state"] == "home" and nr["state"] == "home" and nr["pos"] == lr["pos"] and nr["returned"]["fort_id"] == "greywall"
			and nr["returned"]["cause"] == "retaken" and lt > 0.0 and absf(nt - lt) < 10.0,
			"%s: home in both, returned at %.2f s (catch-up) and %.2f s (live)" % [label, nt, lt])
		var tol := float(c["economy"]["idle"]["catchup_tol"])
		var diff := _stocks_differ(n, live, tol)
		t.ok(diff.is_empty(), "%s: Vei's and Covington's stocks within %.0f%% of live %s" % [label, tol * 100.0, str(diff)])
		if speed > 0.0:
			var m := _mk(c)
			m.from_dict(s.to_dict())
			m._catchup.begin(m, 600.0, true)
			m._catchup.trace = []
			m._catchup.run(m)
			var gw := m._node_xy("greywall")
			var cv := m._node_xy("covington")
			var arrive: float = nt + (sqrt(pow(float(cv[0]) - float(gw[0]), 2.0) + pow(float(cv[1]) - float(gw[1]), 2.0)) - GameState.ARRIVE_EPS) / speed
			var ends: Array = (m._catchup.trace as Array).map(func(x): return float(x[0]) + float(x[1]))
			t.ok(ends.any(func(x): return absf(x - arrive) < 1e-6) and m.view_relish()["state"] == "home",
				"%s: a catch-up step ends at her arrival, %.4f s (her walk from %.4f s)" % [label, arrive, nt])


## Her arrival and a retake inside one catch-up step: she walks home only if she stood there at the retake.
## Sent from Covington to Greywall (316.6 px, 1.44 s at 220 px/s) with Greywall's break due `at` s on, then
## caught up 60 s at 10 s steps (the first clipped at her arrival) and run live at 0.5 s: retaken 0.5 s on,
## before she gets there, she stays at Greywall in both (no relish_returned: the fort fell before she
## arrived, and she stands at a Vei fort as at any); retaken 5 s on, after, she walks home in both.
func _walk_home_arrival() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 6})
	var brk := float(c["realm"]["hold"]["break_s"])
	for at in [0.5, 5.0]:
		var s := _greywall(c, "covington")
		s.realm.fort_by_id("greywall")["zero_s"] = brk - at
		s.cmd_move_relish("greywall")
		s.drain_events()
		var live := _mk(c)
		live.from_dict(s.to_dict())
		live.drain_events()
		live.tick(60.0)
		var lq := _types(live.drain_events())
		var n := _away(c, s, "arrive", 60)
		var nq := _types(n.catchup_events())
		var walks: bool = float(at) > 1.44
		var want := "home" if walks else "at_fort"
		t.ok(lq.has("fort_retaken") and nq.has("fort_retaken") and lq.has("relish_returned") == walks and nq.has("relish_returned") == walks
			and live.view_relish()["state"] == want and n.view_relish()["state"] == want and n.view_relish()["pos"] == live.view_relish()["pos"],
			"retaken %.1f s on (%s her arrival): %s in both, relish_returned %s" % [at, "after" if walks else "before", want, str(walks)])

## The arrival rule inside the arrival's own step, live (GameState._emit_realm). Sent from Covington to
## Greywall (arrival 1.44 s on), with its break due at 1.40 s (just before) or 1.48 s (just after): both
## inside the 1.0-1.5 s substep at 0.5 s, and inside the one 10 s core step. Before her arrival she stays
## at the fort (no relish_returned); after it she walks home (relish_returned, at the retake's t). Run
## through _core_step at 0.5 s (three steps) and at 10 s (one).
func _arrival_same_step() -> void:
	var c := cfgs({})
	var brk := float(c["realm"]["hold"]["break_s"])
	for at in [1.40, 1.48]:
		var walks: bool = float(at) > 1.44
		for dt in [0.5, 10.0]:
			var s := _greywall(c, "covington")
			s.realm.fort_by_id("greywall")["zero_s"] = brk - float(at)
			s.cmd_move_relish("greywall")
			s.drain_events()
			var t0 := s.t
			var evs: Array = []
			for i in int(round(3.0 if dt == 0.5 else 1.0)):
				s._core_step(dt)
				evs.append_array(s.drain_events())
			var rt := evs.filter(func(e): return e["type"] == "fort_retaken")
			var back := evs.filter(func(e): return e["type"] == "relish_returned")
			var st: String = s.view_relish()["state"]
			t.ok(rt.size() == 1 and absf(float(rt[0]["t"]) - t0 - float(at)) < 1e-6,
				"dt %.1f, due %.2f s on: Greywall retaken at %.2f s" % [dt, at, float(rt[0]["t"]) - t0 if not rt.is_empty() else -1.0])
			t.ok(back.size() == (1 if walks else 0) and (not walks or back[0] == {"type": "relish_returned", "fort_id": "greywall", "cause": "retaken", "t": rt[0]["t"]})
				and (st != "at_fort" if walks else st == "at_fort"),
				"dt %.1f, retaken %s her arrival (1.44 s): relish_returned %s, she is %s (home or on her way)" % [dt, "after" if walks else "before", str(walks), st])


# ------------------------------------------------------------------- §3 the away report ----
## The map's two number patterns (scripts/map/away_logic.gd, AwayLogic._compile), copied: a signed rate
## ending in /s, and a mass (a bare number, thousands commas allowed).
const RATE_RE := "^[+\\-−]?\\d[\\d,\\.]*/s$"
const MASS_RE := "^[+\\-−]?\\d[\\d,\\.]*$"


## Every line of a report, section-tagged: [[section, line], ...].
static func _lines(rep: Dictionary) -> Array:
	var out: Array = []
	for k in ["gains", "ready", "losses"]:
		for l in rep[k]:
			out.append([k, l])
	return out


## The first line of `kind` in a section whose text has `needle` ({} when none).
static func _find(rep: Dictionary, section: String, kind: String, needle := "") -> Dictionary:
	for l in rep[section]:
		if l["kind"] == kind and (needle == "" or str(l["text"]).contains(needle)):
			return l
	return {}


## The number tokens of `text` as floats (commas dropped, the signs kept, /s cut).
static func _numbers(text: String) -> Array:
	var out: Array = []
	for tok in text.split(" ", false):
		var s := tok.replace(",", "").replace("−", "-").trim_suffix("/s").trim_prefix("+")
		if s.is_valid_float():
			out.append(float(s))
	return out


## midgame_2flips set up for a 12 h report with a line in every section: Ashgate's loot yield spent (it
## refills), Tarnish (Vei's by the end) set yours, gold granted to 5 000 (it reaches its cap), the fixture's 2
## husks with a free crypt slot, and an empty queue. Old Sluice is retaken about 82 min in.
func _report_start(c: Dictionary) -> GameState:
	var s := _mk(c)
	s.cmd_debug_load_fixture("midgame_2flips")
	var ash := s.realm.fort_by_id("ashgate")
	s._spend_yield(ash)
	for tw in s.towns:
		if tw["id"] == "tarnish":
			tw["control"] = "green"
	s.cmd_debug_grant({"gold": 5000.0 - s.town_sim.gold})
	s.drain_events()
	return s


## A gold-short midgame_2flips with two queued builds for a 1 h report: an Inn on lot-13 (the fixture is a
## village already, so it starts at the first step, at once) and a Bakery on lot-08 that waits on gold once
## the Inn has spent it.
func _queue_start(c: Dictionary) -> GameState:
	var s := _mk(c)
	s.cmd_debug_load_fixture("midgame_2flips")
	s.cmd_debug_grant({"gold": 156.0 - s.town_sim.gold})
	t.ok(s.cmd_queue_build("inn", "lot-13")["ok"] and s.cmd_queue_build("bakery", "lot-08")["ok"], "(setup) an Inn and a Bakery queued")
	s.drain_events()
	return s


## Sections (IDLE §7): a 12 h catch-up of _report_start's midgame_2flips gives the streams first (in
## idle.report.streams' order, kind stream), Ashgate refilled (gains) and "raid it" (ready, its target the
## fort), the 2 husks (target slab), the empty queue with its stores full, so the raid prompt in place of "Queue
## empty" (W), and gold full, "Gold filled up, 2,162 not stored: queue more, or raid for relics" (ready since E4
## step 7, target the queue); Old Sluice retaken and Tarnish lost (losses); a 1 h
## catch-up of _queue_start's gives the builds finished and each queued build's start with when and why: "Inn
## started right away", "Bakery started 6 m after you left, when the gold came in" (W).
func _report_sections(c: Dictionary, n: GameState, q: GameState) -> void:
	var rep := n.view_away()
	print("  [away] the 12 h report: %s" % JSON.stringify(rep))
	t.ok(rep["shown"] and rep["away_s"] == 43200.0 and rep["capped"] == false, "shown, away_s 43200, not capped")
	var streams: Array = c["economy"]["idle"]["report"]["streams"]
	var labels: Dictionary = c["economy"]["idle"]["report"]["stream_labels"]
	var lines: Array = rep["gains"].slice(0, streams.size()).map(func(l): return str(l["text"]))
	var heads_ok := lines.size() == streams.size()
	for i in mini(lines.size(), streams.size()):
		heads_ok = heads_ok and str(lines[i]).begins_with(str(labels[streams[i]]) + " ")
	t.ok(heads_ok and rep["gains"].slice(0, streams.size()).all(func(l): return l["kind"] == "stream" and l["target"] == ""),
		"the gains open with the %d streams' labels, in order: %s" % [streams.size(), str(lines)])
	# the V-I1 round (map-i): the backlog line is labelled with the glossary's word, as STRAIN's tooltip says it
	var bl_head := str(labels["backlog"])
	t.ok(bl_head == "Vei's queue", "the backlog stream reads as Vei's queue: %s" % bl_head)
	t.ok(str(rep["gains"][0]["text"]).begins_with(bl_head + " ▲ +") or str(rep["gains"][0]["text"]).begins_with(bl_head + " ▼ −"), "the backlog carries its arrow: %s" % rep["gains"][0]["text"])
	# E4 step 3: "away: +N, odds A → B", the odds now as view_vei reads them, and rising with the backlog; as whole
	# percents like the top bar's YOUR ODDS since the V-I1 round ("your odds 5% → 8%")
	var bl_line := str(rep["gains"][0]["text"])
	var odds_tail := bl_line.get_slice(" · your odds ", 1)
	var o_from := int(odds_tail.get_slice(" → ", 0).trim_suffix("%"))
	var o_to := int(odds_tail.get_slice(" → ", 1).trim_suffix("%"))
	t.ok(bl_line.contains(" · your odds ") and odds_tail.get_slice(" → ", 1) == StateViews.odds_pct(float(n.view_vei()["odds"]))
		and odds_tail.get_slice(" → ", 1) == "%d%%" % roundi(float(n.view_vei()["odds"]) * 100.0)
		and (o_to >= o_from if bl_line.begins_with(bl_head + " ▲") else o_to <= o_from),
		"the backlog line ends with Vei's odds before and after in percent, the after one view_vei's: %s" % bl_line)
	t.ok(_find(rep, "gains", "refilled") == {"text": "Ashgate refilled", "kind": "refilled", "target": ""}, "gains: Ashgate refilled")
	t.ok(_find(rep, "ready", "raid") == {"text": "Ashgate refilled: raid it", "kind": "raid", "target": "ashgate"}, "ready: Ashgate refilled: raid it")
	t.ok(_find(rep, "ready", "slab") == {"text": "2 husks: raise at the slab", "kind": "slab", "target": "slab"}, "ready: 2 husks: raise at the slab")
	# W: gold and bone end full with the queue empty, so the raid prompt shows and "Queue empty" doesn't
	t.ok(_find(rep, "ready", "queue").is_empty() and _find(rep, "ready", "raid", "stores are full")
		== {"text": "Your stores are full and the queue is empty: raid a fort for relics", "kind": "raid", "target": ""},
		"ready: the stores full and the queue empty, the raid prompt in place of Queue empty: %s" % str(rep["ready"].map(func(l): return l["text"])))
	var os_text := _retaken_text(c, n, "old-sluice", "Old Sluice", false)
	t.ok(_find(rep, "losses", "retaken") == {"text": os_text, "kind": "retaken", "target": "old-sluice"},
		"losses: Old Sluice retaken, with its fort_retaken's WAR and Vei's pressure: %s" % os_text)
	# (E3-3: with u9's siege blunting Ashgate's waves the report loses Bellwether first, then Tarnish)
	t.ok(_find(rep, "losses", "village_lost", "Tarnish") == {"text": "village Tarnish lost to Vei", "kind": "village_lost", "target": ""}, "losses: village Tarnish lost")
	var over := float(n.ledger()["stores"]["gold"]["overflow"])
	# E4 step 7: the full store is a ready action now (target the queue), and no longer a loss
	var ol := _find(rep, "ready", "overflow")
	t.ok(over > 1.0 and not ol.is_empty() and ol["text"] == "Gold filled up, %s not stored: queue more, or raid for relics" % _commas(roundi(over))
		and ol["target"] == "queue", "ready: %s" % str(ol.get("text", "")))
	t.ok(_find(rep, "losses", "overflow").is_empty(), "no overflow line among the losses (E4 step 7): %s" % str(rep["losses"].map(func(l): return l["text"])))
	t.ok(_find(rep, "ready", "overflow", "Bone").is_empty() and float(n.ledger()["stores"]["bone"]["overflow"]) < 1.0,
		"no bone line: its %.2f bone of overflow is under idle.report.overflow_min" % float(n.ledger()["stores"]["bone"]["overflow"]))
	# the queue
	var qr := q.view_away()
	print("  [away] the 1 h queue report's gains: %s" % JSON.stringify(qr["gains"]))
	var starts: Array = q.catchup_events().filter(func(e): return e["type"] == "queue_started")
	t.ok(starts.size() == 2 and starts[1]["waited_on"] == "no_gold", "(setup) both started, the Bakery after waiting on gold: %s" % str(starts))
	# each start's line is its template on its own waited_on ("" started at once), its time since you left
	var words: Dictionary = c["economy"]["idle"]["report"]["waited_on"]
	var want_lines: Array = []
	for e in starts:
		var name := "Inn" if e["building_id"] == "inn" else "Bakery"
		var mins := int((float(e["t"]) - q.t + 3600.0) / 60.0)
		want_lines.append("%s started right away" % name if e["waited_on"] == "" else "%s started %d m after you left, %s" % [name, mins, words[str(e["waited_on"])]])
	var got_lines: Array = qr["gains"].filter(func(l): return l["kind"] == "build" and str(l["text"]).contains(" started ")).map(func(l): return l["text"])
	t.ok(got_lines == want_lines and got_lines.has("Inn started right away") and str(got_lines.back()).begins_with("Bakery started ")
		and str(got_lines.back()).ends_with(" m after you left, when the gold came in"),
		"each queued start with when and why (the Inn at once, the Bakery once the gold came in): %s" % str(got_lines))
	t.ok(not _find(qr, "gains", "build", "2 builds finished").is_empty(), "the builds finished: %s" % str(qr["gains"].filter(func(l): return l["kind"] == "build").map(func(l): return l["text"])))
	# api-request #19 (town-i; Phase I P3): the finished line's `lots`, each building_done's lot in the names' order;
	# no other line has the key. Revert proof: without away_report's `lots`, the first check fails
	var fin := _find(qr, "gains", "build", "2 builds finished")
	var rp: Dictionary = c["economy"]["idle"]["report"]
	var dones: Array = q.catchup_events().filter(func(e): return e["type"] == "building_done")
	var done_lots: Array = dones.map(func(e): return str(e["lot_id"]))
	var names := PackedStringArray(dones.map(func(e): return StateViews._building_name(q, rp, str(e["building_id"]), int(e["level"]))))
	t.ok(fin.get("lots", []) == done_lots and done_lots.size() == 2 and str(fin.get("text", "")).contains(str(rp["list_sep"]).join(names)),
		"#19: the finished line's lots %s, in the order of its names %s: %s" % [str(fin.get("lots", [])), str(names), str(fin.get("text", ""))])
	var others: Array = (qr["gains"] + qr["ready"] + qr["losses"]).filter(func(l): return l.has("lots") and l != fin)
	t.ok(others.is_empty(), "#19: no other line carries lots: %s" % str(others))


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


## Consistency: each stream line's total is the ledger's and the stores' change over the absence (to its
## rounding), and its rate that total over away_s (to its two significant digits): the mint the ledger's
## sources.mint, the backlog, workers (in workers) and bodies its held pools, gold, bone and living the town's.
func _report_consistency(s: GameState, n: GameState) -> void:
	var rep := n.view_away()
	var wm := s.worker_mass()
	var la := s.ledger()
	var lb := n.ledger()
	var want := {
		"mint": float(lb["sources"]["mint"]) - float(la["sources"]["mint"]),
		"backlog": float(lb["held"]["backlog"]) - float(la["held"]["backlog"]),
		"workers": (float(lb["held"]["workers"]) - float(la["held"]["workers"])) / wm,
		"bodies": float(lb["held"]["bodies"]) - float(la["held"]["bodies"]),
		"gold": n.town_sim.gold - s.town_sim.gold, "bone": n.town_sim.bone - s.town_sim.bone, "living": n.town_sim.living - s.town_sim.living,
	}
	var labels: Dictionary = cfgs()["economy"]["idle"]["report"]["stream_labels"]
	var bad: Array = []
	for l in rep["gains"]:
		if l["kind"] != "stream":
			continue
		var id := ""  # the stream whose label (economy.json idle.report.stream_labels) opens the line
		for sid in labels:
			if str(l["text"]).begins_with(str(labels[sid]) + " "):
				id = str(sid)
		var nums := _numbers(str(l["text"]).get_slice(" · your odds ", 0))  # the backlog line's odds tail is checked above
		var total := float(want[id])
		var rate := total / 43200.0
		var ok := nums.size() == 2 and absf(nums[1] - total) <= 0.5 and absf(nums[0] - rate) <= maxf(0.05 * absf(rate), 0.0005)
		if not ok:
			bad.append("%s: %s against %.4f/s · %.3f" % [id, str(nums), rate, total])
	t.ok(bad.is_empty() and want.size() == 7, "every stream's total is the ledger's or the stores' change, its rate that over away_s%s" % (
		"" if bad.is_empty() else ": " + "; ".join(PackedStringArray(bad))))


## Tokens: every token with a digit in every line of the reports here parses under the map's rule (a rate
## or a mass), so nothing is glued to a word. The backlog line's odds are whole percents (the V-I1 round), which the
## map draws as text, as the valve's payoff line does ("percentages stay out of the rate face"): a percent token is
## allowed after " · your odds " only.
func _report_tokens(reps: Array) -> void:
	var rate := RegEx.new()
	rate.compile(RATE_RE)
	var mass := RegEx.new()
	mass.compile(MASS_RE)
	var pct := RegEx.create_from_string("^\\d{1,3}%$")
	var bad: Array = []
	var n := 0
	var n_pct := 0
	for rep in reps:
		for pair in _lines(rep):
			var text := str(pair[1]["text"])
			var odds_at := text.find(" · your odds ")
			var at := 0
			for tok in text.split(" ", false):
				var pos := text.find(tok, at)
				at = pos + tok.length()
				if RegEx.create_from_string("\\d").search(tok) == null:
					continue
				n += 1
				if odds_at >= 0 and pos > odds_at and pct.search(tok) != null:
					n_pct += 1
				elif rate.search(tok) == null and mass.search(tok) == null:
					bad.append("'%s' in '%s'" % [tok, text])
	t.ok(bad.is_empty() and n > 20 and n_pct > 0, "%d number tokens, each a rate or a mass under the map's patterns, or one of %d odds percents%s" % [
		n, n_pct, "" if bad.is_empty() else ": " + str(bad)])


## Shown (IDLE §7, STATE-API §5.19): a reporting catch-up's report is shown; cmd_dismiss_away sets shown false
## (ok, +1 rev; the lines stay); a gap under idle.report_min_s leaves it as it is and one at or above it
## replaces it; it isn't saved: a load replaces it (a 0 s load with none), a new game clears it; a chunked
## load's shows once its catch-up is done, and dismissing meanwhile is refused (catching_up).
func _report_shown() -> void:
	var c := cfgs()
	var n := _away(c, _report_start(c), "shown", 1200)
	var rep := n.view_away()
	t.ok(rep["shown"] and not rep["gains"].is_empty(), "(setup) a 20 min load shows its report")
	var rv := n.rev
	t.ok(n.cmd_dismiss_away() == {"ok": true, "reason": ""} and n.rev == rv + 1, "cmd_dismiss_away: ok, +1 rev")
	var after := n.view_away()
	t.ok(not after["shown"] and after["gains"] == rep["gains"] and after["losses"] == rep["losses"] and after["away_s"] == rep["away_s"],
		"dismissed: shown false, the lines kept")
	t.ok(not n.to_dict().has("away") and JSON.stringify(n.to_dict()).find("Queue empty") == -1, "the report isn't saved")
	var cap := n.max_substeps_per_frame()
	n.tick(120.0, cap)
	while n.catching_up():
		n.tick(1.0 / 60.0, cap)
	t.ok(n.view_away() == after.merged({"rev": n.rev}, true), "a 120 s gap (under idle.report_min_s) leaves the report as it was")
	n.tick(900.0, cap)
	while n.catching_up():
		n.tick(1.0 / 60.0, cap)
	var g := n.view_away()
	t.ok(g["shown"] and g["away_s"] == 900.0, "a 900 s gap replaces it with its own, shown: away_s %.0f" % float(g["away_s"]))
	var z := _away(c, n, "shown0", 0)
	t.ok(z.view_away() == {"rev": z.rev, "shown": false, "away_s": 0.0, "capped": false, "gains": [], "ready": [], "losses": []},
		"a 0 s load: no report (a load replaces the last)")
	n.cmd_new_game(2)
	t.ok(not n.view_away()["shown"] and n.view_away()["gains"].is_empty(), "a new game clears it")
	var ch := _mk(c)
	ch.clock_override = CLOCK + 7200
	ch.cmd_load("shown", true)
	t.ok(ch.catching_up() and not ch.view_away()["shown"] and ch.cmd_dismiss_away()["reason"] == "catching_up",
		"a chunked load: no report until its catch-up is done, and dismissing is refused meanwhile (catching_up)")
	while ch.catching_up():
		ch.tick(1.0 / 60.0, ch.max_substeps_per_frame())
	t.ok(ch.view_away()["shown"] and ch.view_away()["away_s"] == 7200.0, "then its report shows")


## Nothing lost: a new game left 10 min loses nothing (no retake, no village, no overflow): losses is empty (the
## map prints "Nothing lost.").
func _report_nothing_lost() -> void:
	var c := cfgs()
	var s := _mk(c)
	s.cmd_new_game(1)
	s.tick(2.0)
	var rep := _away(c, s, "none_lost", 600).view_away()
	t.ok(rep["shown"] and rep["losses"].is_empty() and not rep["gains"].is_empty(), "a new game away 10 min: shown, losses empty: %s" % str(rep["losses"]))


## The event: away_report {away_s, capped} is queued once per report, at its end, after the run's own events
## and none of the catch-up's (a load's, a chunked load's, a 900 s gap's); a 120 s gap queues none.
func _report_event() -> void:
	var c := cfgs()
	var s := _with_checkpoint(c, LOOT_A)
	var n := _away(c, s, "ev", 1800)
	var q := n.drain_events()
	var ar := q.filter(func(e): return e["type"] == "away_report")
	t.ok(ar.size() == 1 and ar[0] == {"type": "away_report", "away_s": 1800.0, "capped": false, "t": n.t} and _types(q) == ["loot_banked", "away_report"],
		"a load: loot_banked (the run's end) then one away_report {1800, false} at the end: %s" % str(_types(q)))
	var cc := cfgs({"economy.idle.catchup_max_s": 600.0})
	var m := _mk(cc)
	m.clock_override = CLOCK + 1800
	m.cmd_load("ev", true)
	var mq: Array = []
	while m.catching_up():
		m.tick(1.0 / 60.0, m.max_substeps_per_frame())
		mq.append_array(m.drain_events())
	mq.append_array(m.drain_events())
	var mar := mq.filter(func(e): return e["type"] == "away_report")
	t.ok(mar.size() == 1 and mar[0]["away_s"] == 600.0 and mar[0]["capped"] == true and m.view_away()["capped"],
		"a chunked load capped at 600 s: one away_report {600, true}")
	for gap in [120.0, 900.0]:
		var g := _mk(c)
		g.cmd_new_game(1)
		g.tick(2.0)
		g.drain_events()
		var gq: Array = []
		g.tick(gap, g.max_substeps_per_frame())
		while g.catching_up():
			gq.append_array(g.drain_events())
			g.tick(1.0 / 60.0, g.max_substeps_per_frame())
		gq.append_array(g.drain_events())
		var n_ar := gq.filter(func(e): return e["type"] == "away_report").size()
		t.ok(n_ar == (1 if gap >= 600.0 else 0), "a %.0f s gap queues %d away_report" % [gap, n_ar])



## The away report's tests on one 12 h catch-up of _report_start's midgame_2flips and one 1 h of
## _queue_start's (each shared by the sections, the consistency and the tokens), then the rest.
func _report() -> void:
	var c := cfgs()
	var s := _report_start(c)
	var n := _away(c, s, "rep", 43200)
	var q := _away(c, _queue_start(c), "repq", 3600)
	_report_sections(c, n, q)
	_report_consistency(s, n)
	var g := _mk(c)
	g.cmd_new_game(1)
	g.tick(2.0)
	g.tick(900.0, g.max_substeps_per_frame())
	while g.catching_up():
		g.tick(1.0 / 60.0, g.max_substeps_per_frame())
	# R2: the queue's head still waiting (never, and in minutes) and the raid prompt, their reports' tokens checked too
	var r2: Array = [_report_deadlock(c).view_away(), _report_wait(c).view_away(), _report_never_last(c).view_away()]
	r2.append_array(_report_full(c))
	r2.append_array(_report_self(c))  # F1: the stuck line for its store's own producer, with and without an entry behind
	r2.append_array(_report_move_down(c))  # F2: "move it down" only when it lets another entry start
	r2.append_array(_report_wall(c))  # W2: the relics wall, when no entry can start
	r2.append_array(_report_brief_start(c))  # W2: a start that waited, under a minute in
	r2.append(_report_upkeep(c))  # E4 step 4: the entry the upkeep gate holds
	var reps: Array = [n.view_away(), q.view_away(), g.view_away(), _away(c, _greywall(c), "tokw", 600).view_away()] + r2
	_report_shown()
	_report_nothing_lost()
	_report_event()
	_report_walked_home()
	reps.append_array(_report_unpaid())  # W: every unpaid form (for a time, briefly, with and without its tail)
	_report_tokens(reps)
	_report_filled(reps)
	_report_config()
	_report_words()
	_report_afford_words()


## W (the run's manager): every line of the reports above, built through the away path, is filled (no "{…}" left,
## none empty), and between them they render each form W reworded: the unpaid line for a time and briefly, with its
## tail and without; a start after you left and right away; a full store (E4 step 7: "filled up, … not stored: queue
## more, or raid for relics"); each stuck form "at the current income
## of"; and the raid prompt with "Queue empty" not beside it. (The relics forms, which no head reaches through the
## walk today, are rendered through StateViews.afford_text in _report_afford_words.)
func _report_filled(reps: Array) -> void:
	var texts: Array = []
	var bad: Array = []
	for rep in reps:
		for pair in _lines(rep):
			var text := str(pair[1]["text"])
			texts.append(text)
			if text.strip_edges() == "" or text.contains("{") or text.contains("}"):
				bad.append(text)
	t.ok(bad.is_empty() and texts.size() > 50, "%d report lines, each filled, no {…} left%s" % [texts.size(), "" if bad.is_empty() else ": " + str(bad)])
	var forms := {
		"unpaid_fmt": func(x: String): return x.contains(" stopped for ") and x.contains(" ran out: "),
		"unpaid_brief_fmt": func(x: String): return x.contains(" stopped briefly, ") and x.contains(" ran out: "),
		"unpaid_none_fmt": func(x: String): return x.contains(" stopped for ") and x.ends_with(" ran out"),
		"unpaid_none_brief_fmt": func(x: String): return x.contains(" stopped briefly, ") and x.ends_with(" ran out"),
		"started_fmt": func(x: String): return x.contains(" started ") and x.contains(" m after you left, when "),
		"started_now_fmt": func(x: String): return x.ends_with(" started right away"),
		"started_brief_fmt": func(x: String): return x.contains(" started within a minute of you leaving, ") and not x.contains(" 0 m "),
		"afford_relics_last_fmt": func(x: String): return x.ends_with(" needs relics: raid a fort"),
		"overflow_fmt": func(x: String): return x.begins_with("Gold filled up, ") and x.ends_with(" not stored: queue more, or raid for relics"),
		"afford_never_fmt": func(x: String): return x.contains(" can't be afforded at the current income of ") and x.contains(": move it down, or build a "),
		"afford_never_last_fmt": func(x: String): return x.contains(" can't be afforded at the current income of ") and x.contains(": build a ") and not x.contains("move it down"),
		# Phase I P3 (ruling 3): afford_never_self_fmt (a Bone Mill level at −1.0 with a move down) needs a head held
		# with its mill staffed and not pits_first, so a staffed mill with no bodies at all: the workforce's rot always
		# brings some, so no state the walk reaches gives it. _report_afford_words renders it through afford_text
		"afford_never_self_last_fmt": func(x: String): return x.contains(" can't be afforded at the current income of ") and x.ends_with(", and nothing else makes bone"),
		"afford_starved_fmt": func(x: String): return x.contains(" bone short at the current income of ") and x.ends_with(": the pits are eating every body. Raise WAR, or move it down"),
		"afford_starved_last_fmt": func(x: String): return x.contains(" bone short at the current income of ") and x.ends_with(": the pits are eating every body. Raise WAR"),
		"full_raid": func(x: String): return x == "Your stores are full and the queue is empty: raid a fort for relics",
		"queue_empty": func(x: String): return x == "Queue empty: plan the next build",
	}
	var missing: Array = []
	for k in forms:
		if not texts.any(forms[k]):
			missing.append(k)
	t.ok(missing.is_empty(), "the reports render each reworded form through the away path%s" % ("" if missing.is_empty() else ", not: " + str(missing)))
	var both := reps.filter(func(r): return r["ready"].any(func(l): return l["kind"] == "raid" and l["target"] == "") and r["ready"].any(func(l): return l["kind"] == "queue"))
	t.ok(both.is_empty() and texts.filter(func(x: String): return x.contains("today's") or x.contains("stores kept") or x.contains("wasted") or x.contains(" unpaid ")).is_empty(),
		"no report shows the raid prompt beside a queue line, and none says today's, stores kept, wasted or unpaid")


## A retake's loss line as economy.json words it (B1 (ii)): its collected fort_retaken's war_in and pressure_mult,
## one decimal each; "" when no fort_retaken for `id` was collected.
static func _retaken_text(c: Dictionary, n: GameState, id: String, fort_name: String, walked: bool) -> String:
	var rep: Dictionary = c["economy"]["idle"]["report"]
	for e in n.catchup_events():
		if e["type"] == "fort_retaken" and e["fort_id"] == id:
			return str(rep["retaken_home_fmt"] if walked else rep["retaken_fmt"]).format({"fort": fort_name,
				"war": "%.1f" % float(e["war_in"]), "mult": "%.1f" % float(e["pressure_mult"])})
	return ""


## The losses' walk-home line: Greywall retaken while Relish stood there, during a 10 min load's catch-up:
## "Greywall retaken (WAR …/s against Vei's pressure, … times base), Relish walked home: raid it to win it back",
## and view_relish().returned tells it too.
func _report_walked_home() -> void:
	var c := cfgs()
	var n := _away(c, _greywall(c), "walked", 600)
	var l := _find(n.view_away(), "losses", "retaken")
	var want := _retaken_text(c, n, "greywall", "Greywall", true)
	t.ok(want != "" and l == {"text": want, "kind": "retaken", "target": "greywall"}
		and n.view_relish()["returned"]["fort_id"] == "greywall" and n.catchup_events().any(func(e): return e["type"] == "relish_returned"),
		"losses: Greywall retaken, Relish walked home (her relish_returned collected; view_relish().returned): %s" % str(l))


## pre_vei with `gold` left, run `live_s` live (0.5 s substeps), then saved and loaded `away` s on. The loaded
## state's meta "unpaid_at_save" is the lots unpaid when it was saved, in lot order.
func _unpaid_start(c: Dictionary, slot: String, gold: float, live_s: float, away: int) -> GameState:
	var s := _mk(c)
	s.cmd_debug_load_fixture("pre_vei")
	s.town_sim.gold = gold
	for i in int(live_s / 0.5):
		s.tick(0.5)
	s.drain_events()
	var at_save: Array = []
	for l in c["town"]["lots"]:
		if s.town_sim.buildings.get(l["id"], {}).get("state", "") == "unpaid":
			at_save.append(str(l["id"]))
	var n := _away(c, s, slot, away)
	n.set_meta("unpaid_at_save", at_save)
	return n


## Each building's unpaid seconds within the absence, as the report must count them, written out from the
## collected events: the spells between unpaid true and false, from the start for `at_start` (unpaid when you
## left), to the end for one still open. {lot_id: seconds}.
static func _unpaid_secs(n: GameState, at_start: Array, away: float) -> Dictionary:
	var t0 := n.t - away
	var open := {}
	var secs := {}
	for l in at_start:
		open[l] = t0
		secs[l] = 0.0
	for e in n.catchup_events():
		if e["type"] != "building_unpaid":
			continue
		var l := str(e["lot_id"])
		if bool(e["unpaid"]):
			open[l] = float(e["t"])
			secs[l] = float(secs.get(l, 0.0))
		else:
			secs[l] = float(secs.get(l, 0.0)) + float(e["t"]) - float(open.get(l, t0))
			open.erase(l)
	for l in open:
		secs[l] = float(secs[l]) + n.t - float(open[l])
	return secs


## R1 (the run's manager; IDLE §7, STATE-API §5.19), worded by W as a returning player reads it: the losses name
## each building that went unpaid while you were away, one line each in lot order, "<label> stopped for <time>,
## <store> ran out: <what it stopped>" (kind unpaid, target its lot), the store each one its buildings.json upkeep
## is above 0 in (gold, for every building today), "briefly" in place of "for <time>" under a minute in all, and no
## tail when it stopped nothing (a House: only capacity; the Watchtower, whose only working effect nothing reads
## yet). (a) pre_vei saved with 5 gold and loaded 1 h on: its floor comes about 10 s into the catch-up, the
## Statue, the houses, the Well, the Bakery, the Inn, the Graveyard, the Watchtower and the Walls go unpaid, the two
## houses come back; nothing of the WAR chain has a line. (b) the same floor reached live before the save: the
## buildings unpaid when you left count from the start, so the Statue, never paid again, reads the whole hour. (c)
## that save loaded 45 s on: each of the nine stopped "briefly". (d) (a) with the Statue's upkeep in bone too
## (buildings.json patched): its line names both stores, joined by list_sep, "gold · bone ran out". Returns the
## four reports.
func _report_unpaid() -> Array:
	var c := cfgs()
	var both := cfgs({"buildings.statue.upkeep": {"gold": float(c["buildings"]["statue"]["upkeep"]["gold"]), "bone": 0.01}})
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var words: Dictionary = rep["unpaid_stopped"]
	var floor_lots := ["lot-05", "lot-06", "lot-07", "lot-08", "lot-12", "lot-15", "lot-16", "lot-17", "lot-23"]
	var cases := [["a: the floor during the absence", c, _unpaid_start(c, "unpaid_a", 5.0, 0.0, 3600), 3600.0],
		["b: unpaid when you left", c, _unpaid_start(c, "unpaid_b", 5.0, 60.0, 3600), 3600.0],
		["c: unpaid when you left, back 45 s on", c, _unpaid_start(c, "unpaid_c", 5.0, 60.0, 45), 45.0],
		["d: the Statue paying gold and bone", both, _unpaid_start(both, "unpaid_d", 5.0, 0.0, 3600), 3600.0]]
	var saved: Array = cases.map(func(cs): return (cs[2] as GameState).get_meta("unpaid_at_save"))
	t.ok(saved[0].is_empty() and saved[1] == floor_lots and saved[2] == floor_lots and saved[3].is_empty(),
		"(setup) a, d: nothing unpaid at the save; b, c: the floor's nine lots unpaid at the save: %s" % str(saved[1]))
	var shipped := {"gold": "gold", "bone": "bone"}  # each store as the shipped afford_stores words it
	var tail := ": lifted no morale, deaths shook the town harder"
	var out: Array = []
	for i in cases.size():
		var cs: Array = cases[i]
		var cc: Dictionary = cs[1]
		var n: GameState = cs[2]
		var at_start: Array = n.get_meta("unpaid_at_save")
		var r := n.view_away()
		out.append(r)
		var lines: Array = r["losses"].filter(func(l): return l["kind"] == "unpaid")
		var secs := _unpaid_secs(n, at_start, float(cs[3]))
		var lots: Array = secs.keys()
		lots.sort()
		var want: Array = []
		for l in lots:
			var bid := str(n.town_sim.buildings[l]["building_id"])
			var said: Array = []
			for k in GameState.unpaid_keys(cc["buildings"][bid], rep["unpaid_inert"]):
				if not said.has(words[k]):
					said.append(words[k])
			var paid: Array = []  # each store its buildings.json upkeep is above 0 in
			for k in ["gold", "bone"]:
				if float(cc["buildings"][bid]["upkeep"].get(k, 0.0)) > 0.0:
					paid.append(shipped[k])
			var s := float(secs[l])
			var head := "%s stopped %s, %s ran out" % [StateViews._building_name(n, rep, bid, int(n.town_sim.buildings[l]["level"])),
				"briefly" if s < 60.0 else "for " + StateViews._when(rep, s), " · ".join(PackedStringArray(paid))]
			want.append({"text": head + (": " + ", ".join(PackedStringArray(said)) if not said.is_empty() else ""), "kind": "unpaid", "target": l})
		print("  [away] %s: %s" % [cs[0], JSON.stringify(lines)])
		t.ok(lines == want and lots == floor_lots,
			"%s: one line per building unpaid during the absence, in lot order, its time from the events: %s" % [cs[0], str(lines.map(func(l): return l["text"]))])
		var statue: Dictionary = _find(r, "losses", "unpaid", "Statue")
		var house: Dictionary = _find(r, "losses", "unpaid", "House")
		# F2: nothing in the sim reads hint_precision, so a shed Watchtower stopped nothing: W, its line has no tail
		var tower: Dictionary = _find(r, "losses", "unpaid", "Watchtower")
		var tower_s := float(secs.get(tower.get("target", ""), -1.0))
		var tower_want := "Watchtower stopped briefly, gold ran out" if i == 2 else "Watchtower stopped for %s, gold ran out" % StateViews._when(rep, tower_s)
		t.ok(n.town_sim.buildings.get(tower.get("target", ""), {}).get("building_id", "") == "watchtower" and tower.get("text", "") == tower_want,
			"%s: the Watchtower, whose only working effect nothing reads yet, stopped nothing, so its line has no tail: %s" % [cs[0], tower.get("text", "")])
		t.ok(str(house.get("text", "")).ends_with(", gold ran out") and not str(house.get("text", "")).contains(": ")
			and lines.all(func(l): return l["target"] == "lot-12" or (str(l["text"]).contains(", gold ran out") and not str(l["text"]).contains(" · "))),
			"%s: a house, only capacity, stopped nothing (no tail), and every line but the Statue's says gold ran out: %s" % [cs[0], house.get("text", "")])
		var ev_t := 0.0
		for e in n.catchup_events():
			if e["type"] == "building_unpaid" and e["lot_id"] == "lot-12":
				ev_t = float(e["t"])
				break
		var statue_want: String = ["Statue of Relish stopped for %s, gold ran out%s" % [StateViews._when(rep, n.t - ev_t), tail],
			"Statue of Relish stopped for 1 h 0 m, gold ran out" + tail, "Statue of Relish stopped briefly, gold ran out" + tail,
			"Statue of Relish stopped for %s, gold · bone ran out%s" % [StateViews._when(rep, n.t - ev_t), tail]][i]
		var why: String = ["counts from its unpaid event (%.0f s after you left) to the end" % (ev_t - n.t + 3600.0),
			"unpaid when you left and never paid again, reads the whole hour", "unpaid the whole 45 s, stopped briefly",
			"paying gold and bone, names both stores"][i]
		t.ok(statue.get("target", "") == "lot-12" and statue.get("text", "") == statue_want and (ev_t > 0.0) == at_start.is_empty(),
			"%s: the Statue, its morale and its shock relief stopped, %s: %s" % [cs[0], why, statue.get("text", "")])
	return out


## Every waited_on template rendered through the away report's own code (StateViews._why_started, then the
## queue start's started_fmt with a name and a time): 12 reasons in the shipped config, each non-empty with
## no {placeholder} left. And a building's name in a report line is its buildings_view.json label, the
## capitalised id when it has none (StateViews._building_name, with level_fmt past level 1).
func _report_words() -> void:
	var c := cfgs()
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var words: Dictionary = rep["waited_on"]
	t.ok(words.size() == 14 and words.has("wait_slot"), "idle.report.waited_on has 14 reasons, upkeep (E4 step 4's gate) the 13th, wait_slot (Phase I P3, A14's amendment) the 14th (%d: %s)" % [words.size(), str(words.keys())])
	var bad: Array = []
	for w in words:
		var why := StateViews._why_started(rep, str(w))
		var line := str(rep["started_fmt"]).format({"name": "Bakery", "when": StateViews._when(rep, 400.0), "why": why})
		if why.strip_edges() == "" or line.contains("{") or line.contains("}") or not line.contains(why) or why == str(w):
			bad.append("%s -> %s" % [w, line])
	t.ok(bad.is_empty(), "each of the %d waited_on templates renders to a non-empty line with nothing unfilled%s" % [words.size(), "" if bad.is_empty() else ": " + str(bad)])
	var s := _mk(c)
	t.ok(StateViews._building_name(s, rep, "walls", 1) == "Walls and Gate" and StateViews._building_name(s, rep, "walls", 2) == "Walls and Gate level 2",
		"a building's name is its buildings_view label: walls is \"%s\"" % StateViews._building_name(s, rep, "walls", 1))
	t.ok(StateViews._building_name(s, rep, "no_such_hut", 1) == "No Such Hut" and StateViews._building_name(s, rep, "no_such_hut", 3) == "No Such Hut level 3",
		"an id with no label falls back to its id capitalised (String.capitalize): \"%s\"" % StateViews._building_name(s, rep, "no_such_hut", 1))


## The report's text is config (economy.json idle.report), read with no fallback: the shipped block has every
## key (GameState.REPORT_KEYS) and a word for every waited_on reason; without a key, or a reason's words,
## report_config_problem names it (setup reports it as an error).
func _report_config() -> void:
	var c := TestUtil.configs()
	t.ok(GameState.report_config_problem(c) == "", "the shipped idle.report has every key and every waited_on reason")
	var a := TestUtil.configs()
	(a["economy"]["idle"]["report"] as Dictionary).erase("retaken_fmt")
	var b := TestUtil.configs()
	(b["economy"]["idle"]["report"]["waited_on"] as Dictionary).erase("no_bone")
	var d := TestUtil.configs()
	(d["economy"]["idle"] as Dictionary).erase("report")
	t.ok(GameState.report_config_problem(a).contains("retaken_fmt") and GameState.report_config_problem(b).contains("no_bone")
		and GameState.report_config_problem(d).contains("missing"),
		"a missing template, a missing reason's words and a missing block are each named: %s | %s | %s" % [
			GameState.report_config_problem(a), GameState.report_config_problem(b), GameState.report_config_problem(d)])
	# R1: the unpaid line's templates, and its words for what each building stops (every job and working effect in
	# buildings.json); a capacity effect needs none
	var u := TestUtil.configs()
	(u["economy"]["idle"]["report"] as Dictionary).erase("unpaid_fmt")
	var w := TestUtil.configs()
	(w["economy"]["idle"]["report"]["unpaid_stopped"] as Dictionary).erase("haul")
	var x := TestUtil.configs()
	(x["economy"]["idle"]["report"]["unpaid_inert"] as Array).clear()  # F2: hint_precision is a working effect again: it needs words
	var y := TestUtil.configs()
	(y["economy"]["idle"]["report"]["unpaid_inert"] as Array).append("no_such_effect")
	var z := TestUtil.configs()
	z["economy"]["idle"]["report"]["unpaid_inert"] = ["hint_precision", 7]
	var cap := TestUtil.configs()
	cap["buildings"]["house"]["effects"]["vat_slots"] = 1  # a capacity effect: kept while unpaid, nothing to word
	t.ok(GameState.report_config_problem(u).contains("unpaid_fmt") and GameState.report_config_problem(w).contains("haul")
		and GameState.report_config_problem(w).contains("charnel_house") and GameState.report_config_problem(x).contains("watchtower")
		and GameState.report_config_problem(cap) == "",
		"the unpaid line's template and each job's and working effect's words are checked, not a capacity effect's: %s | %s | %s" % [
			GameState.report_config_problem(u), GameState.report_config_problem(w), GameState.report_config_problem(x)])
	# F2: the inert list (effect keys nothing reads yet) is a list of strings, each an effect some building has
	t.ok(GameState.report_config_problem(y).contains("no_such_effect") and GameState.report_config_problem(z).contains("non-string")
		and GameState.report_config_problem(TestUtil.configs()) == "",
		"an inert key no building has, and a non-string one, are each named: %s | %s" % [GameState.report_config_problem(y), GameState.report_config_problem(z)])
	# W: the unpaid line's brief and tailless forms and the relics line's two are required like the rest; unpaid_none
	# (now the tailless forms) and afford_raise.relics (now the relics line) are gone, and the shipped block has neither
	var named: Array = []
	for k in ["unpaid_brief_fmt", "unpaid_none_fmt", "unpaid_none_brief_fmt", "afford_relics_last_fmt", "started_brief_fmt"]:
		var m := TestUtil.configs()
		(m["economy"]["idle"]["report"] as Dictionary).erase(k)
		named.append(GameState.report_config_problem(m))
	var shipped: Dictionary = TestUtil.configs()["economy"]["idle"]["report"]
	t.ok(named.size() == 5 and range(5).all(func(i): return str(named[i]).contains(["unpaid_brief_fmt", "unpaid_none_fmt", "unpaid_none_brief_fmt", "afford_relics_last_fmt", "started_brief_fmt"][i]))
		and not shipped.has("unpaid_none") and not shipped.has("afford_relics_fmt") and not GameState.REPORT_KEYS.has("afford_relics_fmt") and not (shipped["afford_raise"] as Dictionary).has("relics") and not GameState.REPORT_KEYS.has("unpaid_none"),
		"W's new templates are each named when missing; unpaid_none and afford_raise.relics are dropped: %s" % str(named))

static func _diff(a: Variant, b: Variant, rel: float, path: String, why: Array) -> void:
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k):
				why.append(path + "." + str(k) + " missing")
			else:
				_diff(a[k], b[k], rel, path + "." + str(k), why)
		for k in b:
			if not a.has(k):
				why.append(path + "." + str(k) + " extra")
	elif a is Array and b is Array:
		if a.size() != b.size():
			why.append("%s: size %d vs %d" % [path, a.size(), b.size()])
		else:
			for i in a.size():
				_diff(a[i], b[i], rel, "%s[%d]" % [path, i], why)
	elif (a is float or a is int) and (b is float or b is int):
		if absf(float(a) - float(b)) > rel * maxf(1.0, maxf(absf(float(a)), absf(float(b)))):
			why.append("%s: %s vs %s" % [path, str(a), str(b)])
	elif a != b:
		why.append("%s: %s vs %s" % [path, str(a), str(b)])


# ------------------------------------------------- R2: the queue's head and the raid prompt ----
## day1 a step in with its bone spent (TownSim's stock set to 0) and no Bone Mill, a House then a Well queued: the
## House waits on bone at 0/s and the Well behind it. (The review's first overnight, a House, a Well, a Bakery and a
## Bone Mill, deadlocked on the Mill's 20 bone until F1 priced its level 1 in gold only; tests/test_day1_queues.gd.)
func _deadlock_start(c: Dictionary) -> GameState:
	var s := _mk(c)
	s.cmd_debug_load_fixture("day1")
	s.tick(0.5)
	s.town_sim.bone = 0.0
	for p in [["house", "lot-05"], ["well", "lot-06"]]:
		t.ok(s.cmd_queue_build(p[0], p[1])["ok"], "(setup) %s queued on %s" % p)
	s.drain_events()
	return s


## day1 a step in with gold and bone set to `gold` and `bone` (TownSim's stocks; −1 leaves one at its cap), and
## each of `queue` queued.
func _stores_start(c: Dictionary, gold: float, bone: float, queue := []) -> GameState:
	var s := _mk(c)
	s.cmd_debug_load_fixture("day1")
	s.tick(0.5)
	s.town_sim.gold = s.town_sim.gold_cap() if gold < 0.0 else gold
	s.town_sim.bone = s.town_sim.bone_cap() if bone < 0.0 else bone
	for p in queue:
		t.ok(s.cmd_queue_build(p[0], p[1])["ok"], "(setup) %s queued on %s" % p)
	s.drain_events()
	return s


## R2 (the E2b-2 vision review's item 3; IDLE §7, STATE-API §5.19): the review's "come back and nothing happened"
## night. day1 with no bone and no mill, a House and a Well behind it, loaded 8 h on: nothing started, and the House,
## the head, can never be afforded at the current income, so `ready` says so with bone's net rate and what raises it:
## "House can't be afforded at the current income of 0/s bone: build a Bone Mill" (kind queue, target queue), the
## queue's own −1.0 and the net view_rates shows. No "Queue empty". Phase I P3 (ruling 3): with no mill both are
## skipped on no_bone (BuildRules.never_row: the Well needs bone too), holding nothing, and only the first on a store
## gets the line (the Well's would repeat it); no move down (a skipped entry is passed already).
func _report_deadlock(c: Dictionary) -> GameState:
	var n := _away(c, _deadlock_start(c), "deadlock", 28800)
	var rep := n.view_away()
	var rows: Array = n.view_town()["queue"]
	var words: Array = rep["gains"].filter(func(l): return l["kind"] == "build" and str(l["text"]).contains(" started ")).map(func(l): return l["text"])
	t.ok(rows.size() == 2 and rows[0]["building_id"] == "house" and BuildRules.never_row(rows[0]) and rows[0]["reason"] == "no_bone"
		and rows[0]["affordable_in_s"] == -1.0 and BuildRules.never_row(rows[1]) and words.is_empty(),
		"(setup) 8 h on, nothing started: the House and the Well behind it are skipped on bone at −1.0: %s %s" % [str(rows.map(func(r): return r["status"])), str(words)])
	var net := float(n.view_rates()["rates"]["bone"]["net"])
	var want := "House can't be afforded at the current income of %s bone: build a Bone Mill" % StateViews._fmt_rate(c["economy"]["idle"]["report"], net)
	var qs: Array = (rep["ready"] as Array).filter(func(l): return l["kind"] == "queue")
	print("  [away] the deadlocked night's ready: %s" % JSON.stringify(rep["ready"]))
	t.ok(qs == [{"text": want, "kind": "queue", "target": "queue"}] and net == 0.0,
		"ready: one queue line, the House's, with bone's net (0/s) and what raises it, no \"move it down\" and no Queue empty: %s" % str(qs))
	return n


## F2 (the phase review): "move it down" only when some other entry could start if the stuck head weren't ahead of
## it (StateViews._move_down_helps: the queue's walk less the head, a row that isn't skipped_gate with
## affordable_in_s >= 0). Phase I P3 (ruling 3): only a head that holds the queue can be moved down, one whose
## producer is staffed and whose hold (queue.never_hold_s) hasn't run out; a head with no mill is skipped (and its
## line is _report_deadlock's). So the case is gold's: pre_vei, its four stalls staffed and its full upkeep over its
## income (net −0.47/s, trade_starved ""), gold set to 290 and the bone at its cap, the Inn's level 2 (300 gold) at the
## head, loaded 5 min on (inside the hold), then (a) the Well's level 2 (60 gold: an upgrade, so the upkeep gate
## passes it), which could start: "Inn level 2 can't be afforded at the current income of −0.47/s gold: move it down,
## or build a Market"; (b) the Crypt's level 2 (gated: no relics): no entry could take its place, so no move down.
func _report_move_down(c: Dictionary) -> Array:
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var out: Array = []
	for cs in [["the Well's level 2 behind it, which can start", "lot-07", true], ["only a gated entry behind it", "lot-01", false]]:
		var s := _mk(c)
		s.cmd_debug_load_fixture("pre_vei")
		s.tick(0.5)
		s.town_sim.gold = 290.0
		s.town_sim.bone = s.town_sim.bone_cap()
		s.relics = 0
		t.ok(s.cmd_queue_build("", "lot-15")["ok"] and s.cmd_queue_build("", cs[1])["ok"], "(setup) the Inn's level 2, then the upgrade on %s" % cs[1])
		s.drain_events()
		var n := _away(c, s, "move_down", 300)
		var rows: Array = n.view_town()["queue"]
		var head: Dictionary = rows[0] if not rows.is_empty() else {}
		var behind: Dictionary = rows[1] if rows.size() > 1 else {}
		var gnet := float(BuildRules.queue_net(n)["gold"])
		t.ok(rows.size() == 2 and head.get("building_id", "") == "inn" and head.get("status", "") == "waiting_funds" and head.get("reason", "") == "no_gold"
			and head.get("affordable_in_s", 0.0) == -1.0 and head.get("starved", "x") == "" and (behind.get("status", "") == "skipped_gate") != cs[2] and gnet < 0.0,
			"(setup) %s: the Inn holds on gold at −1.0 (net %.3f/s, stalls staffed), the entry behind it is %s" % [cs[0], gnet, str(behind.get("status", ""))])
		var want := "Inn level 2 can't be afforded at the current income of %s gold: %sbuild a Market" % [StateViews._fmt_rate(rep, gnet),
			"move it down, or " if cs[2] else ""]
		var r := n.view_away()
		var l := _find(r, "ready", "queue")
		print("  [away] move it down, %s: %s" % [cs[0], str(l.get("text", ""))])
		t.ok(l == {"text": want, "kind": "queue", "target": "queue"} and str(l["text"]).contains("move it down") == cs[2],
			"ready: %s, \"move it down\" %s: %s" % [cs[0], "offered" if cs[2] else "not offered", str(l)])
		out.append(r)
	return out


## F1 (the run's manager): with nothing queued behind the head, "move it down" can't help, so the line drops it
## (idle.report.afford_never_last_fmt): day1 with no bone and no mill, a House alone, loaded 10 min on: "House can't
## be afforded at the current income of 0/s bone: build a Bone Mill". Phase I P3 (ruling 3): with no mill it is skipped.
func _report_never_last(c: Dictionary) -> GameState:
	var s := _mk(c)
	s.cmd_debug_load_fixture("day1")
	s.tick(0.5)
	s.town_sim.bone = 0.0
	t.ok(s.cmd_queue_build("house", "lot-05")["ok"], "(setup) a House queued alone on no bone")
	s.drain_events()
	var n := _away(c, s, "never_last", 600)
	var rows: Array = n.view_town()["queue"]
	t.ok(rows.size() == 1 and BuildRules.never_row(rows[0]) and rows[0]["affordable_in_s"] == -1.0,
		"(setup) 10 min on, the House is skipped on bone at −1.0, nothing behind it: %s" % str(rows.map(func(r): return r["status"])))
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var want := "House can't be afforded at the current income of %s bone: build a Bone Mill" % StateViews._fmt_rate(rep, float(n.view_rates()["rates"]["bone"]["net"]))
	var l := _find(n.view_away(), "ready", "queue")
	print("  [away] the head alone, never: %s" % str(l.get("text", "")))
	t.ok(l == {"text": want, "kind": "queue", "target": "queue"} and not str(l["text"]).contains("move it down"),
		"ready: nothing behind the House, so no \"move it down\": %s" % str(l))
	return n


## F1 (the run's manager): when the head is its own store's producer (idle.report.afford_producer, an upgrade
## included), "build a Bone Mill" would name itself, so the line says afford_raise_self's fact instead, true at this
## commit (loot.json gives no bone; only a mill makes it): "Bone Mill level 2 can't be afforded at the current income of
## 0/s bone, and nothing else makes bone", with ": move it down" when an entry is behind it. A constructed state,
## since F1 left day1 no such case: midgame_2flips, with its bone set to 50 and the mill's level 2 (190 bone) queued,
## alone and with a House behind it, each loaded 10 min on, its mill's staff cap at 0 (it makes 0 bone/s, and wants
## none). E4 (the run's manager's A1 day-1 ruling): with the mill staffed, midgame_2flips' pits eat every body (its
## starved pits_first), so the line names the bone short and the lever instead, ahead of F1's fact (afford_starved_fmt:
## "Bone Mill level 2 can't be afforded, 140 bone short at the current income of 0/s bone: the pits are eating every
## body. Raise WAR, or move it down"); a new mill wouldn't help, so neither form says to build one. Phase I P3 (ruling
## 3): unstaffed, the mill's level is skipped at once (no move down; the House behind it starts), so its line is
## afford_never_self_last_fmt with or without the House; staffed, it holds inside queue.never_hold_s, so these load
## 5 min on (_starved_hold has the same state past the hold).
func _report_self(c: Dictionary) -> Array:
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var out: Array = []
	for staffed in [false, true]:
		out.append_array(_report_self_one(c, rep, staffed))
	return out


func _report_self_one(c: Dictionary, rep: Dictionary, staffed: bool) -> Array:
	var out: Array = []
	for behind in [false, true]:
		var s := _mk(c)
		s.cmd_debug_load_fixture("midgame_2flips")
		s.tick(0.5)
		var mill := ""
		for lot_id in s.town_sim.buildings:
			if s.town_sim.buildings[lot_id]["building_id"] == "bone_mill":
				mill = str(lot_id)
		s.town_sim.bone = 50.0
		if not staffed:
			t.ok(s.cmd_set_staff_cap(mill, 0)["ok"], "(setup) the mill's staff cap at 0")
		t.ok(mill != "" and s.cmd_queue_build("", mill)["ok"], "(setup) the Bone Mill's next level queued on %s" % mill)
		if behind:
			t.ok(s.cmd_queue_build("house", str(BuildRules.free_lots(s, 1)[0]))["ok"], "(setup) a House queued behind it")
		s.drain_events()
		var n := _away(c, s, "self", 300)
		var rows: Array = n.view_town()["queue"]
		var row: Dictionary = rows[0] if not rows.is_empty() else {}
		var held: bool = row.get("status", "") == "waiting_funds"
		t.ok(rows.size() == (2 if behind and staffed else 1) and row.get("building_id", "") == "bone_mill" and row.get("reason", "") == "no_bone"
			and held == staffed and BuildRules.never_row(row) != staffed
			and row.get("affordable_in_s", 0.0) == -1.0 and absf(float(n.view_rates()["rates"]["bone"]["net"])) <= BuildRules.NET_EPS,
			"(setup) 5 min on, the mill's level %d %s on bone at −1.0, bone at 0/s%s" % [int(row.get("level", 0)), "holds" if staffed else "is skipped",
			(", a House behind it" if staffed else ", the House behind it started") if behind else ""])
		var name := StateViews._building_name(n, rep, "bone_mill", int(row.get("level", 0)))
		t.ok(str(row.get("starved", "")) == ("pits_first" if staffed else ""), "(setup) the head's starved: %s" % str(row.get("starved", "")))
		var want := "%s can't be afforded at the current income of %s bone, and nothing else makes bone" % [name, StateViews._fmt_rate(rep, 0.0)]
		if staffed:
			want = str(rep["afford_starved_fmt" if behind else "afford_starved_last_fmt"]).format({"name": name,
				"short": StateViews._fmt_count(rep, ceilf(float(row["short"]["bone"]))), "rate": StateViews._fmt_rate(rep, 0.0)})
		var r := n.view_away()
		var l := _find(r, "ready", "queue")
		print("  [away] its own producer, never%s%s: %s" % [", staffed" if staffed else "", ", an entry behind" if behind else "", str(l.get("text", ""))])
		t.ok(l == {"text": want, "kind": "queue", "target": "queue"} and not str(l["text"]).substr(name.length()).contains(StateViews._building_name(n, rep, "bone_mill", 1)),
			"ready: the mill stuck on bone never says to build a Bone Mill, and says what is true%s%s: %s" % [
			" (the pits eat every body: raise WAR)" if staffed else " (unstaffed: nothing else makes bone)",
			(" (with \"move it down\": a House is behind it)" if staffed else " (skipped: no move down)") if behind else " (nothing behind it: no move down)", str(l)])
		out.append(r)
	return out


## A head waiting on gold with gold coming in: midgame_2flips with 10 gold and an Inn queued (150 gold), loaded
## 10 min on: still waiting, "Inn is waiting on gold: affordable in <its affordable_in_s, rounded up to the
## minute>".
func _report_wait(c: Dictionary) -> GameState:
	var s := _mk(c)
	s.cmd_debug_load_fixture("midgame_2flips")
	s.tick(0.5)
	s.cmd_debug_grant({"gold": 10.0 - s.town_sim.gold})
	t.ok(s.cmd_queue_build("inn", "lot-13")["ok"], "(setup) an Inn queued on 10 gold")
	s.drain_events()
	var n := _away(c, s, "wait", 600)
	var row: Dictionary = n.view_town()["queue"][0] if n.view_town()["queue"].size() == 1 else {}
	var a := float(row.get("affordable_in_s", -1.0))
	t.ok(row.get("status", "") == "waiting_funds" and row.get("reason", "") == "no_gold" and a > 0.0,
		"(setup) 10 min on the Inn still waits on gold, affordable in %.1f s" % a)
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var want := "Inn is waiting on gold: affordable in %s" % StateViews._when(rep, ceilf(a / 60.0) * 60.0)
	var l := _find(n.view_away(), "ready", "queue")
	t.ok(l == {"text": want, "kind": "queue", "target": "queue"} and ceilf(a / 60.0) >= 1.0,
		"ready: the Inn waits on gold, its wait rounded up to the minute: %s" % str(l))
	return n


## The raid prompt (R2; the run's manager, from Shawn's "needs relics: raid a fort"): an absence that ends with gold
## and bone each within idle.report.full_tol of its cap and the queue empty gets "Your stores are full and the queue
## is empty: raid a fort for relics" (kind raid, target ""), in place of "Queue empty" (W: no build can be planned
## without relics, so the two never show together). day1 has no bone income, so its bone stays where it is set: full
## (at the cap, and at 99.5% of it, inside the 1%): the prompt and no "Queue empty"; not full (50%, and 98%, just
## outside): "Queue empty" and no prompt; and full with a gated entry queued (the crypt's level 2, no relics: it
## holds nothing, so the stores stay full): neither. Each loaded 10 min on.
func _report_full(c: Dictionary) -> Array:
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var prompt := {"text": str(rep["full_raid"]), "kind": "raid", "target": ""}
	var tol := float(rep["full_tol"])
	var bcap := float(c["economy"]["bone"]["cap"])  # day1 has no Bone Mill: the base cap
	var cases := [["at the caps", -1.0, [], true], ["bone at 99.5% of its cap", bcap * (1.0 - tol / 2.0), [], true],
		["bone at half its cap", bcap * 0.5, [], false], ["bone at 98% of its cap", bcap * (1.0 - 2.0 * tol), [], false],
		["full, a gated entry queued", -1.0, [["", "lot-01"]], false]]
	var reps: Array = []
	for cs in cases:
		var s := _stores_start(c, -1.0, cs[1], cs[2])
		var n := _away(c, s, "full", 600)
		var r := n.view_away()
		reps.append(r)
		var full: bool = n.town_sim.gold >= n.town_sim.gold_cap() * (1.0 - tol) and n.town_sim.bone >= n.town_sim.bone_cap() * (1.0 - tol)
		var has: bool = r["ready"].has(prompt)
		var empty: bool = r["ready"].has({"text": str(rep["queue_empty"]), "kind": "queue", "target": "queue"})
		t.ok(has == cs[3] and full == (cs[1] < 0.0 or cs[1] >= bcap * (1.0 - tol)) and empty == ((cs[2] as Array).is_empty() and not has),
			"%s (gold %.1f of %.0f, bone %.1f of %.0f, queue %d): the raid prompt %s, Queue empty %s" % [cs[0], n.town_sim.gold, n.town_sim.gold_cap(),
			n.town_sim.bone, n.town_sim.bone_cap(), n.build_queue.size(), "shown" if has else "not shown", "shown" if empty else "not shown"])
	return reps


## E4 step 4 (the ruling (3) gate): pre_vei, a City on one Market whose full upkeep is over its gold income, with a House
## queued on a free lot. The upkeep gate holds it through the absence (skipped_gate, reason upkeep), and `ready` has
## idle.report.afford_upkeep_fmt for it: its name, the gold income now, and the Market to build (kind queue, target queue).
func _report_upkeep(c: Dictionary) -> Dictionary:
	var s := _mk(c)
	s.cmd_debug_load_fixture("pre_vei")
	s.tick(0.5)
	var lots: Array = []
	for r in s.view_catalog()["buildings"]:
		if r["building_id"] == "house":
			lots = r["lots"]
	t.ok(not lots.is_empty() and s.cmd_queue_build("house", str(lots[0]))["ok"], "(setup) pre_vei: a House queued on %s" % str(lots.slice(0, 1)))
	s.drain_events()
	var n := _away(c, s, "upkeep", 600)
	var rows: Array = n.view_town()["queue"]
	var line: Array = (n.view_away()["ready"] as Array).filter(func(l): return str(l["text"]).contains("can't pay its upkeep"))
	var want := str(c["economy"]["idle"]["report"]["afford_upkeep_fmt"]).format({"name": "House",
		"rate": StateViews._fmt_rate(c["economy"]["idle"]["report"], n.town_sim.gold_income())})
	t.ok(rows.size() == 1 and rows[0]["status"] == "skipped_gate" and rows[0]["reason"] == "upkeep",
		"pre_vei's full upkeep over its income: the House is held by the upkeep gate through the absence: %s/%s" % [rows[0]["status"] if not rows.is_empty() else "", rows[0]["reason"] if not rows.is_empty() else ""])
	t.ok(line.size() == 1 and str(line[0]["text"]) == want and line[0]["kind"] == "queue" and line[0]["target"] == "queue",
		"ready names it: \"%s\"" % (str(line[0]["text"]) if not line.is_empty() else ""))
	return n.view_away()


## W2 (the run's manager, for Shawn; IDLE §7): the relics wall. The queue's walk gates a relic shortfall, so a relic-gated
## entry is `skipped_gate`, never a waiting head, and a queue of only those used to get no `ready` line. When the absence
## ends with no entry able to start (no row `next`, no `waiting_funds` head that will be afforded; an entry `queued`
## behind a head at −1.0 can't start either, case (f): House, Well queued, gated Crypt) and one is gated
## on `no_relics`, `ready` has "Crypt level 2 needs relics: raid a fort" for the first such entry (kind queue, target
## queue, no rate, no "move it down"), with the stores full or not, and never the raid prompt (which a non-empty queue
## never had). (a) relic-gated only, stores full; (b) the same, not full; (c) an entry that waits on gold with a finite
## time, plus a gated one: the town is still building, no wall; (d) an empty queue with full stores: the raid prompt as
## before, no wall; (e) a House stuck at −1.0 on bone ahead of the gated entry: both lines, the head's first. Phase I
## P3 (ruling 3): with no mill the House is skipped (it holds nothing), and in (f) so is the Well behind it (it needs
## bone too), whose line would repeat the House's: still two lines, the House's and the wall.
func _report_wall(c: Dictionary) -> Array:
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var wall := {"text": "Crypt level 2 needs relics: raid a fort", "kind": "queue", "target": "queue"}
	var prompt := {"text": str(rep["full_raid"]), "kind": "raid", "target": ""}
	var empty := {"text": str(rep["queue_empty"]), "kind": "queue", "target": "queue"}
	var bcap := float(c["economy"]["bone"]["cap"])
	var out: Array = []
	var cases := [["(a) relic-gated only, stores full", -1.0, -1.0, [["", "lot-01"]], [wall]],
		["(b) relic-gated only, stores not full", 50.0, bcap * 0.5, [["", "lot-01"]], [wall]],
		["(d) empty queue, stores full", -1.0, -1.0, [], [prompt]],
		["(e) a House stuck on bone, then the gated entry", -1.0, 0.0, [["house", "lot-05"], ["", "lot-01"]], ["house", wall]],
		["(f) a House stuck on bone, a Well queued behind it, then the gated entry", -1.0, 0.0,
			[["house", "lot-05"], ["well", "lot-06"], ["", "lot-01"]], ["house", wall]]]
	for cs in cases:
		var n := _away(c, _stores_start(c, cs[1], cs[2], cs[3]), "wall", 600)
		var r := n.view_away()
		var got: Array = (r["ready"] as Array).filter(func(l): return l["kind"] == "queue" or l["kind"] == "raid")
		var shape: bool = (got.size() == 2 and str(got[0]["text"]).begins_with("House can't be afforded") and got[1] == wall) if cs[4][0] is String else got == cs[4]
		print("  [away] the wall, %s: %s" % [cs[0], JSON.stringify(got.map(func(l): return l["text"]))])
		t.ok(shape and got.has(wall) == (cs[0] != "(d) empty queue, stores full") and got.has(prompt) == (cs[3] as Array).is_empty()
				and not got.has(empty) and not got.any(func(l): return str(l["text"]).contains("needs relics") and str(l["text"]).contains("move it down")),
			"%s: ready has %s%s" % [cs[0], "the wall" if got.has(wall) else "no wall", " and the raid prompt" if got.has(prompt) else ""])
		out.append(r)
	# (c) the Inn waits on gold with a finite time, a gated Crypt upgrade behind it: still building, so no wall
	var s := _mk(c)
	s.cmd_debug_load_fixture("midgame_2flips")
	s.tick(0.5)
	s.cmd_debug_grant({"gold": 10.0 - s.town_sim.gold})
	s.relics = 0
	var crypt := ""
	for lot_id in s.town_sim.buildings:
		if str(s.town_sim.buildings[lot_id]["building_id"]) == "crypt":
			crypt = str(lot_id)
	t.ok(crypt != "" and s.cmd_queue_build("inn", "lot-13")["ok"] and s.cmd_queue_build("", crypt)["ok"], "(setup) an Inn and a Crypt upgrade queued, no relics")
	s.drain_events()
	var n := _away(c, s, "wall_c", 600)
	var rows: Array = n.view_town()["queue"]
	t.ok(rows.size() == 2 and rows[0]["status"] == "waiting_funds" and float(rows[0]["affordable_in_s"]) > 0.0 and rows[1]["status"] == "skipped_gate"
		and rows[1]["reason"] == "no_relics", "(setup) the Inn waits on gold, the Crypt upgrade is gated on relics")
	var r := n.view_away()
	var qlines: Array = (r["ready"] as Array).filter(func(l): return l["kind"] == "queue").map(func(l): return str(l["text"]))
	print("  [away] the wall, (c) an entry that can start plus a gated one: %s" % JSON.stringify(qlines))
	t.ok(qlines.size() == 1 and qlines[0].begins_with("Inn is waiting on gold") and not qlines.any(func(x: String): return x.contains("needs relics")),
		"(c) one entry that can start plus a relic-gated one: the Inn's line only, no wall")
	out.append(r)
	return out


## W2: a queued start that waited but began under a minute after you left reads "Inn started within a minute of you
## leaving, when the gold came in", not "0 m after" and not "right away" (which stays for a start that didn't wait);
## a start from a minute on keeps "started 6 m after you left". midgame_2flips with gold set 20 s short of the Inn.
func _report_brief_start(c: Dictionary) -> Array:
	var s := _mk(c)
	s.cmd_debug_load_fixture("midgame_2flips")
	s.tick(0.5)
	var cost := float(BuildRules.construction_cost(s, "inn", 1)["gold"])
	var net := float(BuildRules.queue_net(s)["gold"])
	s.cmd_debug_grant({"gold": cost - 20.0 * net - s.town_sim.gold})
	t.ok(net > 0.0 and s.cmd_queue_build("inn", "lot-13")["ok"], "(setup) an Inn queued about 20 s short of its gold (net %.3f/s)" % net)
	s.drain_events()
	var n := _away(c, s, "brief_start", 600)
	var r := n.view_away()
	var started: Array = (r["gains"] as Array).filter(func(l): return l["kind"] == "build" and str(l["text"]).contains("started"))
	print("  [away] a start under a minute: %s" % JSON.stringify(started.map(func(l): return l["text"])))
	t.ok(started.size() == 1 and started[0]["text"] == "Inn started within a minute of you leaving, when the gold came in",
		"a start that waited under a minute: %s" % JSON.stringify(started))
	return [r]


## Every new template renders through the report's own code (StateViews.afford_text) to a line with nothing
## unfilled, for each store a head can wait on and the stores the tables word (gold, bone, relics), each stuck form
## (F1: with an entry behind and without, for a building and for its store's own producer); the prompt too. A stuck
## line says "move it down" only with an entry behind, and a producer's never names itself after its name. W: each
## gold and bone stuck form reads "at the current income of <rate> <store>", the rate a token of its own; one short of
## relics reads Shawn's "needs relics: raid a fort", with no rate and no income, ", or move it down" only with an
## entry behind. The words are true of the configs (F1's truth check): each store's producer offers the job that
## makes it (stall: gold, mill: bone, TownSim's only incomes) and no other building does ("nothing else makes ..."),
## afford_raise names that producer ("build a Market"), and loot.json gives relics at every tier ("raid a fort") and
## no gold or bone anywhere (so a raid is no fix for those). And report_config_problem names a missing template,
## store, producer or self text, a producer that isn't a building, or a full_tol out of [0, 1).
func _report_afford_words() -> void:
	var c := cfgs()
	var rep: Dictionary = c["economy"]["idle"]["report"]
	var s := _mk(c)
	var bad: Array = []
	var shown: Array = []
	var relic_lines: Array = []
	var net := {"gold": 0.21, "bone": 0.0, "relics": 0.0}
	var prod: Dictionary = rep["afford_producer"]
	for store in ["gold", "bone", "relics"]:
		var bids := ["bakery"] + ([prod[store]] if prod.has(store) else [])
		for bid in bids:
			var own: bool = prod.get(store, "") == bid
			var own_name := StateViews._building_name(s, rep, str(bid), 1)
			for a in [-1.0, 30.0, 4000.0]:
				for behind in [true, false]:
					var row := {"building_id": bid, "level": 2, "affordable_in_s": a, "reason": "no_gold"}
					var line := StateViews.afford_text(s, rep, row, store, net, behind)
					var name := StateViews._building_name(s, rep, str(bid), 2)
					var relics: bool = store == "relics" and a < 0.0
					var raise := str(rep["afford_raise_self" if own else "afford_raise"][store]) if a < 0.0 and not relics else ""
					var income := " at the current income of %s %s" % [StateViews._fmt_rate(rep, float(net[store])), str(rep["afford_stores"][store])]
					if (line.strip_edges() == "" or line.contains("{") or line.contains("}") or not line.contains(str(rep["afford_stores"][store]))
							or (raise != "" and not line.contains(raise)) or (a < 0.0 and line.contains("move it down") != (behind and not relics))
							or (own and line.substr(name.length()).contains(own_name)) or (a < 0.0 and not relics and not line.contains(income))):
						bad.append("%s %s %s %s -> %s" % [store, bid, a, behind, line])
					if a < 0.0:
						shown.append(line)
					if relics:
						relic_lines.append(line)
	print("  [away] the stuck forms: %s" % JSON.stringify(shown))
	var prompt := str(rep["full_raid"])
	t.ok(bad.is_empty() and prompt.strip_edges() != "" and not prompt.contains("{"), "each new template renders with nothing unfilled%s" % (
		"" if bad.is_empty() else ": " + str(bad)))
	t.ok(relic_lines == ["Bakery level 2 needs relics: raid a fort", "Bakery level 2 needs relics: raid a fort"]
		and relic_lines.all(func(l): return l.contains("needs relics: raid a fort") and not l.contains("/s") and not l.contains("income")),
		"a head short of relics: \"needs relics: raid a fort\", no rate, the move down only with an entry behind: %s" % str(relic_lines))
	# the truth check: who makes each store, and what a raid gives
	var makes := {"gold": "stall", "bone": "mill"}  # TownSim: gold comes only from stalls, bone only from milling
	var lies: Array = []
	for store in makes:
		var by: Array = []
		for bid in c["buildings"]:
			if int(c["buildings"][bid].get("jobs", {}).get(makes[store], 0)) > 0:
				by.append(bid)
		var pname := StateViews._building_name(s, rep, str(prod.get(store, "")), 1)
		if by != [prod.get(store, "")] or not str(rep["afford_raise"][store]).contains(pname):
			lies.append("%s: made by %s, the producer %s, \"%s\"" % [store, str(by), str(prod.get(store, "")), rep["afford_raise"][store]])
	var loot_keys := _keys_deep(c["loot"])
	if loot_keys.has("gold") or loot_keys.has("bone"):
		lies.append("loot.json gives gold or bone, so a raid is a fix: %s" % str(loot_keys))
	var chests: Dictionary = c["loot"]["chest_by_tier"]
	if chests.is_empty() or not chests.values().all(func(ch): return int(ch.get("relics", [0, 0])[1]) > 0):
		lies.append("a chest tier gives no relics: \"%s\"" % rep["afford_relics_last_fmt"])
	t.ok(lies.is_empty(), "each raise text is true of the configs (only a Market makes gold, only a Bone Mill bone, raids give relics and neither)%s" % (
		"" if lies.is_empty() else ": " + str(lies)))
	var probs: Array = []
	for k in ["afford_wait_fmt", "afford_never_fmt", "full_raid", "full_tol", "afford_never_last_fmt", "afford_never_self_fmt",
			"afford_never_self_last_fmt", "afford_producer", "afford_raise_self"]:
		var m := TestUtil.configs()
		(m["economy"]["idle"]["report"] as Dictionary).erase(k)
		probs.append([k, GameState.report_config_problem(m)])
	var r1 := TestUtil.configs()
	(r1["economy"]["idle"]["report"]["afford_raise"] as Dictionary).erase("bone")
	probs.append(["afford_raise.bone", GameState.report_config_problem(r1)])
	var r2 := TestUtil.configs()
	(r2["economy"]["idle"]["report"]["afford_stores"] as Dictionary).erase("relics")
	probs.append(["afford_stores.relics", GameState.report_config_problem(r2)])
	var r3 := TestUtil.configs()
	r3["economy"]["idle"]["report"]["full_tol"] = 1.5
	probs.append(["full_tol", GameState.report_config_problem(r3)])
	# F1: the producers and their self words
	var p1 := TestUtil.configs()
	(p1["economy"]["idle"]["report"]["afford_producer"] as Dictionary).erase("gold")
	probs.append(["afford_producer.gold", GameState.report_config_problem(p1)])
	var p2 := TestUtil.configs()
	p2["economy"]["idle"]["report"]["afford_producer"]["bone"] = "bone_mil"
	probs.append(["afford_producer.bone", GameState.report_config_problem(p2)])
	var p3 := TestUtil.configs()
	(p3["economy"]["idle"]["report"]["afford_raise_self"] as Dictionary).erase("bone")
	probs.append(["afford_raise_self.bone", GameState.report_config_problem(p3)])
	var p4 := TestUtil.configs()
	p4["economy"]["idle"]["report"]["afford_producer"]["essence"] = "reliquary"
	probs.append(["afford_producer.essence", GameState.report_config_problem(p4)])
	print("  [away] the F1 config problems: %s" % str(probs.slice(probs.size() - 4).map(func(p): return p[1])))
	var unnamed := probs.filter(func(p): return not str(p[1]).contains(str(p[0]).split(".")[0]) or not str(p[1]).contains(str(p[0]).split(".")[-1]))
	t.ok(unnamed.is_empty(), "report_config_problem names each missing R2 or F1 template, table store, producer and self text, a producer that isn't a building, and an out-of-range full_tol%s" % (
		"" if unnamed.is_empty() else ": " + str(unnamed)))


## Every key of `v` at any depth (loot.json's tables).
static func _keys_deep(v: Variant) -> Array:
	var out: Array = []
	if v is Dictionary:
		for k in v:
			out.append(str(k))
			out.append_array(_keys_deep(v[k]))
	elif v is Array:
		for x in v:
			out.append_array(_keys_deep(x))
	return out
