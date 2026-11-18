extends RefCounted
## P3b (api-request #21, from dungeon-i's P7; the run's manager's brief): the won state. Once Vei is beaten (`won`):
## - `_boss_reason` reads "won" first, so cmd_begin_boss refuses and view_vei's can_begin is false with it;
## - no tithe: no warning, wave or surge (the clock idles: RealmSim.set_won), start_tithe can't restart it, and no held
##   fort is retaken (the zero clock doesn't run); every fort's hold forecast reads zeros;
## - Vei's own lanes stop: no living vei->fort (shipping, reship) and no dead fort->vei (the undead her living destroy
##   stay at the fort as corpses);
## - FLOOD's share goes to WAR (the manager's call): view_hud's split reads flood 0 and WAR the war and flood shares;
## - the player's side runs on: WAR reaches the held forts, the garrisons hold mass, held_for_s and grace count;
## - the ledger balances, and a save after the win loads won (a warning saved in flight comes back idle).
## #21's measurement is the setup, cut to 30 min (about four tithe periods; 6 h of midgame costs ~14 min a run):
## midgame_2flips in 60 s ticks; #21 read 59 warnings, 59 waves and a retake in 6 h, identical with `won` set before P3b.
## Revert proofs (each run once, then restored): _boss_reason without the won line, 2 FAIL (_reason); set_won not
## idling the tithe and start_tithe without its guard, 3 FAIL (_half_hour's tithe counts, _save's in-flight warning);
## step 9 without the won skip, 1 FAIL (_no_retake); _split_of with to_war only, 1 FAIL (_half_hour's split).

var t := TestUtil.new()
var _dir := "user://test_won_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)
const Ledger := preload("res://scripts/sim/ledger.gd")
const SPAN_S := 1800.0  # 30 min: ~4 tithe periods (realm.json tithe.period_s 420)
const TICK := 60.0


func run() -> int:
	t.suite("won")
	_reason()
	_half_hour()
	_no_retake()
	_save()
	_cleanup()
	return t.failures


func _mk(won: bool) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.save_dir = _dir
	s.cmd_debug_load_fixture("midgame_2flips")
	if won:
		s.cmd_debug_set_state({"won": true})
	return s


func _of(evs: Array, type: String) -> Array:
	return evs.filter(func(e): return e["type"] == type)


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)


## "won" comes first: away from Vei, and at her gates, a won game refuses the fight with "won" (cmd_begin_boss and
## view_vei alike); an unbeaten game at her gates may begin.
func _reason() -> void:
	var s := _mk(true)
	t.ok(s.view_vei()["reason"] == "won" and not s.view_vei()["can_begin"], "won, away from Vei: view_vei reads won first: %s" % s.view_vei()["reason"])
	s.cmd_debug_set_state({"relish_at": "vei"})
	var r := s.cmd_begin_boss()
	t.ok(not r["ok"] and r["reason"] == "won" and s.view_vei()["reason"] == "won" and s.run.is_empty(),
		"won, at her gates: cmd_begin_boss refuses with won (%s)" % str(r.get("reason", "")))
	var u := _mk(false)
	u.cmd_debug_set_state({"relish_at": "vei"})
	t.ok(u.view_vei()["can_begin"] and u.view_vei()["reason"] == "", "(control) not won, at her gates: she can begin")


## #21's measurement, both ways, with the valve's FLOOD share up: unbeaten the tithe runs (warnings, waves); beaten,
## nothing of hers over 30 min, and the player's side runs.
func _half_hour() -> void:
	var tally := {}
	for won in [false, true]:
		var s := _mk(won)
		s.cmd_set_valve(2.0, 2.0, 1.0)
		s.drain_events()
		var evs: Array = []
		var held0 := {}
		for f in s.realm.forts:
			if RealmSim.is_held(f):
				held0[f["id"]] = float(f.get("held_for_s", 0.0))
		var shipped := 0.0
		var dead_out := 0.0
		var war_held := 0.0
		var surge := 0.0
		for i in int(SPAN_S / TICK):
			s.tick(TICK)
			evs.append_array(s.drain_events())
			shipped += float(s.realm.vei["r_shipped"])
			for f in s.realm.forts:
				dead_out += float(f["r_dead_out"])
				surge += float(f["r_surge"])
				if held0.has(f["id"]):
					war_held += float(f["r_in"])
		var n := [_of(evs, "tithe_warning").size(), _of(evs, "tithe_wave").size(), _of(evs, "fort_retaken").size()]
		tally[won] = n
		if not won:
			t.ok(n[0] > 0 and n[1] > 0, "(control) not won, 30 min: %d warnings, %d waves, %d retakes" % n)
			continue
		t.ok(n == [0, 0, 0] and not bool(s.realm.tithe["started"]) and s.view_vei()["tithe"]["next_target"] == ""
			and float(s.view_vei()["tithe"]["next_s"]) < 0.0,
			"won, 30 min: no warning, wave or retake (%s, against %s unbeaten); the tithe idles, no next target" % [str(n), str(tally[false])])
		t.ok(shipped == 0.0 and surge == 0.0 and dead_out == 0.0,
			"won: no living vei->fort (shipping %.3f, surge %.3f) and no dead fort->vei (%.3f), summed over the ticks" % [shipped, surge, dead_out])
		var hud: Dictionary = s.view_hud()
		var sp: Dictionary = hud["split"]
		var lanes: Array = s.view_lanes()["lanes"]
		var vei_in := 0.0
		for l in lanes:
			if (l["kind"] == "living" or l["kind"] == "dead") and float(l["rate"]) > 0.0:
				vei_in += float(l["rate"])
		var ages := true
		var mass := 0.0
		for f in s.realm.forts:
			if held0.has(f["id"]):
				ages = ages and RealmSim.is_held(f) and float(f["held_for_s"]) >= float(held0[f["id"]]) + SPAN_S - 1.0
				mass += float(f["undead"])
		t.ok(float(sp["flood"]) == 0.0 and absf(float(sp["war"]) - float(s._split["mint"]) * 0.6 - float(s._split["muster"])) <= 1e-9
			and sp["muster_to"] == "war" and float(s.realm.r_flood) == 0.0,
			"won: FLOOD's share goes to WAR (flood %.3f; war %.3f of a %.3f mint at 2:2:1, muster %.3f)" % [
			float(sp["flood"]), float(sp["war"]), float(s._split["mint"]), float(s._split["muster"])])
		t.ok(vei_in == 0.0, "won: view_lanes' living and dead lanes carry nothing (%.3f)" % vei_in)
		t.ok(war_held > 0.0 and mass > 0.0 and ages,
			"won: WAR still reaches the held forts (%.1f mass/s summed), their garrisons hold %.1f, held_for_s ran the 30 min" % [war_held, mass])
		var zero := true
		for f in s.realm.forts:
			var h: Dictionary = s.view_fort(f["id"])["hold"]
			zero = zero and float(h["need"]) == 0.0 and float(h["fall_s"]) < 0.0 and str(h["margin_cause"]) == ""
		t.ok(zero, "won: every fort's hold forecast reads zeros (no wave comes)")
		s.realm.start_tithe()
		t.ok(not bool(s.realm.tithe["started"]), "won: start_tithe (a flip's) doesn't restart the clock")
		t.ok(Ledger.error(s.ledger()) < 1e-6 * maxf(1.0, Ledger.total(s.ledger()["held"])),
			"won, 30 min: the ledger balances (error %.9f)" % Ledger.error(s.ledger()))


## RealmSim alone, so nothing reaches the fort (no WAR or FLOOD input; GameState would send the muster to WAR once won):
## a held fort past grace with an empty garrison, 10 min of 10 s steps. Unbeaten, Vei's zero clock retakes it after
## hold.break_s (120 s); beaten, it stays held and its clock stays at 0.
func _no_retake() -> void:
	var out := {}
	for won in [false, true]:
		var s := _mk(false)
		var r := s.realm
		r.set_won(won)
		var fid := ""
		for f in r.forts:
			if RealmSim.is_held(f) and fid == "":
				fid = str(f["id"])
				f["grace_s"] = 0.0
				f["held_s"] = 0.0
				f["undead"] = 0.0
		r.events.clear()
		for i in 60:
			r.step(10.0, {"war": 0.0, "flood": 0.0, "digest_q": 1.0})
		var f: Dictionary = r.fort_by_id(fid)
		var ret := r.events.filter(func(e): return e["type"] == "fort_retaken" and e["fort_id"] == fid).size()
		out[won] = [ret, RealmSim.is_held(f), float(f["zero_s"])]
	t.ok(out[false][0] == 1 and out[true][0] == 0 and out[true][1] and out[true][2] == 0.0,
		"a held fort with nothing coming, 10 min: retaken unbeaten (%s), held won (%s)" % [str(out[false]), str(out[true])])


## A save written mid-warning, then won: loaded (1 h away), it is won with the tithe idle, and the hour brings no
## warning, wave or retake; cmd_begin_boss still refuses with won.
func _save() -> void:
	var s := _mk(false)
	var guard := 0
	while (s.realm.tithe["warning"] as Dictionary).is_empty() and guard < 2000:
		s.tick(TICK)
		guard += 1
	t.ok(not (s.realm.tithe["warning"] as Dictionary).is_empty(), "(setup) a warning in flight at t %.0f" % s.t)
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	d["won"] = true  # a save from before P3b: won, with the tithe it had
	var n := GameState.new(TestUtil.configs())
	n.save_dir = _dir
	t.ok(n.from_dict(d)["ok"], "(setup) loaded")
	t.ok(n.won and not bool(n.realm.tithe["started"]) and (n.realm.tithe["warning"] as Dictionary).is_empty()
		and not n.view_vei()["tithe"]["warning"],
		"a won save with a warning in flight loads won, the tithe idle")
	s.cmd_debug_set_state({"won": true})
	t.ok(not bool(s.realm.tithe["started"]) and (s.realm.tithe["warning"] as Dictionary).is_empty(),
		"the win drops the warning in flight at once")
	s.clock_override = CLOCK
	t.ok(s.cmd_save("won")["ok"], "(setup) saved won")
	var a := GameState.new(TestUtil.configs())
	a.save_dir = _dir
	a.clock_override = CLOCK + 3600
	t.ok(a.cmd_load("won")["ok"], "(setup) loaded 1 h on")
	var evs: Array = a.catchup_events()
	t.ok(a.won and _of(evs, "tithe_warning").is_empty() and _of(evs, "tithe_wave").is_empty() and _of(evs, "fort_retaken").is_empty()
		and a.view_vei()["reason"] == "won",
		"a save after the win loads won: 1 h away brings no warning, wave or retake; the fight reads won (%d events)" % evs.size())
