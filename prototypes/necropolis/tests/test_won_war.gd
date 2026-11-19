extends RefCounted
## P9b (ruling 36, the run's manager's brief economy-p9b): once Vei is beaten, WAR goes to the forts. Before it, a won
## pre_vei emptied every fort inside 20 min (the drain ran on to her queue, and with nothing shipped no fort without
## living was a WAR target), while WAR fell through to her queue; a won midgame_2flips' held Ashgate grew to 10 233
## against its cap of 80 (held forts took WAR with no limit). Now (MECHANICS §3.4's "After the win"):
## - no garrison drains (RealmSim.set_won zeroes r_drain), so no fort empties;
## - every fort is a WAR target and takes at most what fills its garrison to its cap (_dispatch, _won_room), so no
##   garrison passes its cap; a raise fills it to its cap, no further (step 1's raise room);
## - WAR falls through to her queue (the realm's sink, view_hud's war_overflow, the valve's won line "lost: your
##   forts are full") only while every garrison is at its cap, and then all of it does.
## Each run is the brief's span: 20 min of live 60 s ticks (0.5 s substeps; the P9 probe's forts emptied inside it),
## then the rest as a gap's catch-up at 10 s core steps (economy idle.catchup_dt_max_s, its longest base step),
## sampled after every tick and every core step.
## Revert proofs (each run once on a scratch copy): set_won keeping r_drain, 7 FAIL (both runs drain, greywall 87.4 to
## 49.9; midgame's tier-2 forts empty; WAR never overflows, so the overflow rows are vacuous; Ashgate ends at 22.4;
## _raise short of the cap); _dispatch's weight without `or won`, 2 FAIL (both runs overflow at every sample while
## garrisons sit below their caps); the won limit for unheld forts only (held forts INF again), 5 FAIL (Ashgate 10 303
## of 80, old-sluice 7 002; the tier-3 and tier-4 forts never get a garrison; _raise); the won limit for forts without living only
## (living forts INF again), 2 FAIL (whitecross 953.5 of 520, greywall 184.7 of 90); step 1 without the raise room,
## 2 FAIL (greywall 143.8 of 90 in midgame, where a simulacrum raises; _raise 138.4 of 80). Asserted only: _won_raise's
## living branch (no fixture raises at a fort with living once won).

var t := TestUtil.new()
const Ledger := preload("res://scripts/sim/ledger.gd")
const LIVE_S := 1200.0
const TICK := 60.0
const CATCHUP_DT := 10.0
const REL := 1e-9  # a garrison "at its cap" within this fraction of it


func run() -> int:
	t.suite("won_war")
	var u0 := Time.get_ticks_msec()
	_span("pre_vei", 7200.0)
	_span("midgame_2flips", 3600.0)
	_raise()
	print("  [won_war] %.1f s wall" % ((Time.get_ticks_msec() - u0) / 1000.0))
	return t.failures


func _mk(fixture: String, span_s: float) -> GameState:
	var c := TestUtil.configs()
	c["economy"]["idle"]["catchup_max_steps"] = (span_s - LIVE_S) / CATCHUP_DT  # the catch-up's base step: 10 s
	var s := GameState.new(c)
	s.debug_enabled = true
	s.cmd_debug_load_fixture(fixture)
	s.cmd_debug_set_state({"won": true})
	return s


static func _full(f: Dictionary) -> bool:
	return float(f["undead"]) >= float(f["cap"]) * (1.0 - REL)


## One won fixture over `span_s`: the garrisons against their caps and each other at every sample, and the overflow
## against the forts' fill.
func _span(fixture: String, span_s: float) -> void:
	var s := _mk(fixture, span_s)
	var t0 := s.t
	var n := s.realm.forts.size()
	var prev: Array[float] = []
	var had: Array[bool] = []  # the fort has held a garrison (U > 0) at a sample
	for f in s.realm.forts:
		prev.append(float(f["undead"]))
		had.append(float(f["undead"]) > 0.0)
	var worst := {"over": 0.0, "over_at": "", "fell": 0.0, "fell_at": "", "emptied": [], "drain": 0.0}
	var tallies := {"samples": 0, "over_ticks": 0, "not_full_over": 0, "full_short": 0, "first_over_t": -1.0}
	var was_full := false
	var sample := func() -> void:
		tallies["samples"] += 1
		var ov := float(s.realm.r_war_to_vei)
		var war := float(s._split["war"])
		var all_full := true
		for i in n:
			var f: Dictionary = s.realm.forts[i]
			var u := float(f["undead"])
			var cap := float(f["cap"])
			worst["drain"] = maxf(float(worst["drain"]), float(f["r_drain"]))
			if u - cap > float(worst["over"]):
				worst["over"] = u - cap
				worst["over_at"] = "%s %.1f of %.0f at t %.0f" % [f["id"], u, cap, s.t]
			# a fort with no living has nothing to take from its garrison once won: it never falls
			if float(f["living"]) <= 0.0 and prev[i] - u > float(worst["fell"]):
				worst["fell"] = prev[i] - u
				worst["fell_at"] = "%s %.3f to %.3f at t %.0f" % [f["id"], prev[i], u, s.t]
			if had[i] and u <= 0.0 and not (worst["emptied"] as Array).has(f["id"]):
				(worst["emptied"] as Array).append(f["id"])
			had[i] = had[i] or u > 0.0
			prev[i] = u
			all_full = all_full and _full(f)
		if ov > 1e-9 * maxf(1.0, war):
			tallies["over_ticks"] += 1
			if float(tallies["first_over_t"]) < 0.0:
				tallies["first_over_t"] = s.t - t0
			if not all_full:
				tallies["not_full_over"] += 1
		# every garrison full when the last step began: none takes any, so all of that step's WAR falls through
		if was_full and absf(ov - war) > 1e-9 * maxf(1.0, war):
			tallies["full_short"] += 1
		was_full = all_full
	for k in int(LIVE_S / TICK):
		s.tick(TICK)
		sample.call()
	s._catchup.begin(s, span_s - LIVE_S, false)
	var dt_cu := float(s._catchup.dt)
	while s._catchup.active:
		s._catchup.run(s, 1)
		sample.call()
	var caps := []
	var ends := []
	for f in s.realm.forts:
		caps.append(int(f["cap"]))
		ends.append(snappedf(float(f["undead"]), 0.1))
	t.ok(absf(s.t - t0 - span_s) < 1e-6 and absf(dt_cu - CATCHUP_DT) < 1e-9 and s.won,
		"(setup) %s won: %.0f s live, then caught up at %.1f s steps to %.0f s on (%d samples)" % [
		fixture, LIVE_S, dt_cu, s.t - t0, int(tallies["samples"])])
	t.ok(float(worst["drain"]) == 0.0 and float(worst["fell"]) <= 1e-9,
		"%s won: no garrison drains (the most r_drain %.3f/s; the largest fall at a fort without living %s%s)" % [
		fixture, float(worst["drain"]), str(float(worst["fell"])), (": " + str(worst["fell_at"])) if float(worst["fell"]) > 1e-9 else ""])
	t.ok((worst["emptied"] as Array).is_empty() and ends.all(func(u): return u > 0.0),
		"%s won: no fort empties (emptied %s); every garrison at the end %s" % [fixture, str(worst["emptied"]), str(ends)])
	t.ok(float(worst["over"]) <= 1e-9 * 520.0,
		"%s won: every garrison at or under its cap at every sample (caps %s; the most over %s%s)" % [
		fixture, str(caps), str(float(worst["over"])), (": " + str(worst["over_at"])) if float(worst["over"]) > 0.0 else ""])
	t.ok(int(tallies["over_ticks"]) > 0 and int(tallies["not_full_over"]) == 0 and int(tallies["full_short"]) == 0,
		"%s won: WAR overflows only while every garrison is at its cap, and then all of it (%d overflowing samples from %.0f s on, %d with a garrison short of its cap, %d full ones short of all of WAR)" % [
		fixture, int(tallies["over_ticks"]), float(tallies["first_over_t"]), int(tallies["not_full_over"]), int(tallies["full_short"])])
	t.ok(Ledger.error(s.ledger()) < 1e-6 * maxf(1.0, Ledger.total(s.ledger()["held"])),
		"%s won: the ledger balances (error %.9f)" % [fixture, Ledger.error(s.ledger())])
	if fixture == "midgame_2flips":
		var a: Dictionary = s.realm.fort_by_id("ashgate")
		t.ok(RealmSim.is_held(a) and _full(a) and float(a["undead"]) <= float(a["cap"]) * (1.0 + REL),
			"midgame_2flips won: held Ashgate's garrison ends at its cap, %.3f of %.0f (10 233 before P9b)" % [float(a["undead"]), float(a["cap"])])


## RealmSim alone: Relish raising at a won held fort with more corpses than room (old-sluice's 63.4 corpses, its
## garrison set to 75 of its cap 80) with WAR to spare, 10 min of 10 s steps. The raise fills the garrison to its cap
## and no further.
func _raise() -> void:
	var s := GameState.new(TestUtil.configs())
	s.debug_enabled = true
	s.cmd_debug_load_fixture("midgame_2flips")
	var r := s.realm
	r.set_won(true)
	var f: Dictionary = r.fort_by_id("old-sluice")
	f["undead"] = 75.0
	var d0 := float(f["dead"])
	var u_most := 0.0
	var raised := 0.0
	for i in 60:
		r.step(10.0, {"war": 50.0, "flood": 0.0, "digest_q": 1.0, "redirect_fort": "old-sluice", "redirect_rate": 20.0})
		u_most = maxf(u_most, float(f["undead"]))
		raised += float(f["r_raised"]) * 10.0
	t.ok(d0 > 50.0 and raised > 0.0, "(setup) old-sluice starts with %.1f corpses; Relish raised %.1f of them" % [d0, raised])
	t.ok(u_most <= float(f["cap"]) * (1.0 + REL) and _full(f),
		"won, Relish raising at a fort full of corpses: the garrison fills to its cap and no further (most %.3f of %.0f)" % [u_most, float(f["cap"])])
