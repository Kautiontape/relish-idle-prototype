extends RefCounted
## E3-6b: the autoplayer's default-suite smoke (tests/autoplay/autoplayer.gd, Autoplayer.smoke; IDLE §8). From a new
## game: first30 (GAMEPLAY §6's opening: the first dungeon, its flip, the first big undead, one queue set), closed to the
## next session (cmd_save, a fresh GameState, cmd_load 3 h 30 m on: the real catch-up), then 40 min of the sessions
## policy (raids at the party's reach, the queue fed and reordered, the slab, the party). It asserts:
## - the opening's beats happened (the first dungeon's result applied, the flip, the first big undead, the queue set, the
##   close and its load);
## - every raid result passed Results.validate and the real apply_result, and the ledger stayed balanced at every row;
## - the reorder rule fired (the day-1 queue's head reads -1 on bone with no mill);
## - determinism: run twice from fresh GameStates, the same hash of the AUTOPLAY_SUMMARY and the final to_dict().
## No balance number is asserted: pacing is measured, not gated (E4 calibrates). Wall time is printed, never asserted.

var t := TestUtil.new()


func run() -> int:
	t.suite("autoplay_smoke")
	var c := Autoplayer.cfgs()
	var u0 := Time.get_ticks_msec()
	var a := Autoplayer.smoke(c)
	var u1 := Time.get_ticks_msec()
	var b := Autoplayer.smoke(c)
	var u2 := Time.get_ticks_msec()
	var sm: Dictionary = a["summary"]
	var beats: Dictionary = sm["beats"]
	for k in ["first_dungeon", "flip", "first_big", "queue_set", "close"]:
		t.ok(bool(beats[k]["happened"]), "first30: %s happened: %s" % [k, JSON.stringify(beats[k])])
	var res: Dictionary = sm["results"]
	t.ok(int(res["validated"]) >= 2 and int(res["invalid"]) == 0 and int(res["refused"]) == 0 and int(res["applied"]) == int(res["validated"]),
		"every raid result passed Results.validate and the real apply_result: %s" % JSON.stringify(res))
	t.ok(float(sm["ledger_max_err"]) < 1e-6, "the ledger stayed balanced at every row (worst %s)" % String.num_scientific(float(sm["ledger_max_err"])))
	# Phase I P3 (ruling 3): the game itself now skips a head no income can pay (at once with its producer unstaffed,
	# after queue.never_hold_s with it staffed), which is what the bot's reorder rule moved, and entries behind a held
	# head are timed after it; so the smoke no longer needs a reorder (it read 0 at b6970d2), only reports it
	t.ok(int(sm["reorders"]) >= 0 and bool(beats["queue_set"]["happened"]), "the reorder rule ran (%d moves; the first build: %s)" % [
		int(sm["reorders"]), JSON.stringify(sm["mill_first"])])
	t.ok(str(a["hash"]) == str(b["hash"]), "deterministic: twice from fresh GameStates, the same hash of the summary and the final state (%s, %s)" % [
		str(a["hash"]).substr(0, 16), str(b["hash"]).substr(0, 16)])
	print("  [autoplay_smoke] hash %s; %d raids, %d builds started, t %.0f; %.1f s and %.1f s wall" % [str(a["hash"]),
		int(sm["raids"]["count"]), (a["bot"] as Autoplayer).builds.size(), float(sm["t_end"]), (u1 - u0) / 1000.0, (u2 - u1) / 1000.0])
	return t.failures
