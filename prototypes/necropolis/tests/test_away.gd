extends RefCounted
## The edges of an absence (E2b-2 T3.3c; IDLE I5, §7).
## - No run survives a close, a crash, a load or a gap above idle.gap_s (api-request #4): the dungeon's last
##   cmd_run_checkpoint is saved with the run (`pending_retreat`) and a load ends the run from it through the
##   normal writeback, before the catch-up, on both load paths: a retreat banks exactly that loot with no
##   flip and Relish at_fort; warden_beaten flips the fort; relish_died is a death; no checkpoint banks
##   nothing; a save without pending_retreat (older) forfeits the run as before. A gap in the open game ends
##   the run inside the frame that finds it, run_ended first, before its catch-up. Every run command on the
##   ended run gets its dead-run refusal, during the catch-up too, and changes nothing.
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
	_checkpoint_chunked()
	_end_exceptions()
	_no_checkpoint()
	_old_save()
	_gap_ends_run()
	_dead_run()
	_cleanup()
	return t.failures


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
## banks), relish_died is a death (the party lost, a clone spent, Relish home), as apply_result treats them.
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
	t.ok(_types(evs) == ["loot_banked", "relish_died", "relish_respawned"] and evs[1]["outcome"] == "clone" and evs[1]["at"] == "old-sluice"
		and m.clones_ready == 0 and m.party_uids.is_empty() and m.big_undead.is_empty() and m.view_relish()["state"] == "home"
		and int(m.stats["deaths"]) == deaths + 1 and not m.view_fort("old-sluice")["held"],
		"relish_died: a death (a clone spent, the party lost, Relish home, no flip): %s" % str(_types(evs)))


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
