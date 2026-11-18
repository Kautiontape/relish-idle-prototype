extends RefCounted
## P3b (api-request #22, the run's manager's ruling of 2026-11-18): a beaten Vei stays beaten through a gap. When Vei
## breaks the boss scene calls cmd_boss_won(run_id, result) with the v2 boss result its win card will send; from then a
## gap above idle.gap_s, a load of a save holding the run, or an abort resolves the run as that win (the card's press's
## writeback: `won`, vei_result once), never a forfeit, and the card's later press reads duplicate_run. Setup: pre_vei
## (Relish at Vei's gates), a boss run begun, the win recorded with no backups spent.
## - the record: ok; refusals no_run, wrong_run, wrong_kind, not_won and apply_result's (bad_backups); it changes no
##   state but the run's record (Relish still in_boss, not won);
## - a gap: run_ended {boss, outcome won, cause gap} first, then vei_result (won) once; won; the press: duplicate_run;
## - a save and a load 1 h on: pending_retreat carries won_result; the load applies it (won, vei_result once, Relish
##   at_vei, the run applied), and a save whose won_result isn't a won result of that run is corrupt;
## - an abort applies it too; without a record the gap still forfeits (test_away's _gap_ends_run).
## Revert proof (run once, then restored): end_open without the won_result branch, 5 FAIL (the gap, the load and the
## abort forfeit, and the press after the gap and after the load reads wrong_run).

var t := TestUtil.new()
var _dir := "user://test_boss_won_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)


func run() -> int:
	t.suite("boss_won")
	_record()
	_gap()
	_load()
	_abort()
	_cleanup()
	return t.failures


func _mk() -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.save_dir = _dir
	s.cmd_debug_load_fixture("pre_vei")
	return s


## pre_vei with a boss run open; the seed in meta "seed".
func _boss() -> GameState:
	var s := _mk()
	var b := s.cmd_begin_boss()
	t.ok(b["ok"], "(setup) a boss run at pre_vei: %s" % str(b.get("reason", "")))
	s.set_meta("seed", b["seed"])
	s.drain_events()
	return s


static func _won(sd: Dictionary, over := {}) -> Dictionary:
	var r := {"v": 2, "run_id": sd["run_id"], "seed_rev": sd["seed_rev"], "won": true, "fronts_cleared": [],
		"relish_deaths": 0, "backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "backlog_spent": 0.0}
	r.merge(over, true)
	return r


static func _of(evs: Array, type: String) -> Array:
	return evs.filter(func(e): return e["type"] == type)


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)


func _record() -> void:
	var s := _boss()
	var sd: Dictionary = s.get_meta("seed")
	var id := int(sd["run_id"])
	t.ok(s.cmd_boss_won(id + 7, _won(sd))["reason"] == "wrong_run", "another run's id: wrong_run")
	t.ok(s.cmd_boss_won(id, _won(sd, {"won": false}))["reason"] == "not_won", "a lost fight: not_won")
	var k := int(sd["phylactery_charges"]) + 1
	var bb := s.cmd_boss_won(id, _won(sd, {"backups_spent": {"phylactery": k, "clones": 0}, "relish_deaths": k}))
	t.ok(bb["reason"] == "bad_backups", "apply_result's own checks, unapplied: %d phylactery charges spent of %d, bad_backups (%s)" % [
		k, k - 1, str(bb["reason"])])
	var rv := s.rev
	var r := s.cmd_boss_won(id, _won(sd))
	t.ok(r["ok"] and s.rev == rv + 1 and not s.won and s.view_relish()["state"] == "in_boss" and not s.run.is_empty()
		and s.drain_events().is_empty(), "the win recorded: ok, nothing applied yet (Relish in_boss, not won, no event)")
	var n := _mk()
	t.ok(n.cmd_boss_won(1, _won(sd))["reason"] == "no_run", "no run open: no_run")
	n.cmd_debug_set_state({"relish_at": "old-sluice"})
	var rd := n.cmd_begin_dungeon("old-sluice")
	if rd["ok"]:
		t.ok(n.cmd_boss_won(int(rd["run_id"]), _won(sd, {"run_id": int(rd["run_id"])}))["reason"] == "wrong_kind", "a raid open: wrong_kind")


func _gap() -> void:
	var s := _boss()
	var sd: Dictionary = s.get_meta("seed")
	var id := int(sd["run_id"])
	t.ok(s.cmd_boss_won(id, _won(sd))["ok"], "(setup) the win recorded")
	s.tick(100.0, s.max_substeps_per_frame())
	var q := s.drain_events()
	t.ok(q.size() >= 2 and q[0]["type"] == "run_ended" and q[0]["kind"] == "boss" and q[0]["outcome"] == "won" and q[0]["cause"] == "gap"
		and _of(q, "vei_result").size() == 1 and bool(_of(q, "vei_result")[0]["won"]) and s.won and s.run.is_empty()
		and s.applied_runs.has(id) and s.view_relish()["state"] == "at_vei",
		"a 100 s gap after the win: run_ended (boss, won) first, vei_result (won) once, won, Relish at_vei: %s" % str(q.map(func(e): return e["type"]).slice(0, 4)))
	var p := s.apply_result("boss", _won(sd))
	t.ok(not p["ok"] and p["reason"] == "duplicate_run" and _of(s.drain_events(), "vei_result").is_empty(),
		"the card's press after it: duplicate_run, applied once (%s)" % str(p.get("reason", "")))


func _load() -> void:
	var s := _boss()
	var sd: Dictionary = s.get_meta("seed")
	var id := int(sd["run_id"])
	t.ok(s.cmd_boss_won(id, _won(sd))["ok"], "(setup) the win recorded")
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	t.ok((d["pending_retreat"] as Dictionary).has("won_result") and bool(d["pending_retreat"]["won_result"]["won"]),
		"the save's pending_retreat carries the recorded win")
	s.clock_override = CLOCK
	t.ok(s.cmd_save("bw")["ok"], "(setup) saved")
	var n := GameState.new(TestUtil.configs())
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = CLOCK + 3600
	t.ok(n.cmd_load("bw")["ok"], "(setup) loaded 1 h on")
	var evs: Array = n.drain_events()
	evs.append_array(n.catchup_events())
	t.ok(n.won and n.run.is_empty() and n.applied_runs.has(id) and n.view_relish()["state"] == "at_vei"
		and _of(evs, "vei_result").size() == 1 and n.view_vei()["reason"] == "won",
		"a load of the save: the win applied once (won, vei_result x%d, Relish at_vei, the fight reads won)" % _of(evs, "vei_result").size())
	var p := n.apply_result("boss", _won(sd))
	t.ok(not p["ok"] and p["reason"] == "duplicate_run", "the card's press after the load: duplicate_run (%s)" % str(p.get("reason", "")))
	for bad in [{"won": false}, {"run_id": id + 3}]:
		var x: Dictionary = JSON.parse_string(JSON.stringify(d))
		(x["pending_retreat"]["won_result"] as Dictionary).merge(bad, true)
		var c := GameState.new(TestUtil.configs())
		t.ok(not c.from_dict(x)["ok"], "a saved won_result with %s is corrupt" % str(bad))


func _abort() -> void:
	var s := _boss()
	var sd: Dictionary = s.get_meta("seed")
	var id := int(sd["run_id"])
	t.ok(s.cmd_boss_won(id, _won(sd))["ok"], "(setup) the win recorded")
	var r := s.cmd_abort_dungeon()
	var q := s.drain_events()
	t.ok(r["ok"] and s.won and s.run.is_empty() and _of(q, "vei_result").size() == 1 and s.applied_runs.has(id),
		"an abort after the win applies it (won, vei_result once), never a forfeit")
