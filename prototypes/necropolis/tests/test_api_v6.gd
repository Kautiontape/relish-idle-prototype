extends RefCounted
## STATE-API v6 additions (economy E2b-2 T3.1 onward; later E2b-2 tasks add to v6): the held forts'
## contest (fort_retaken's cause "broken", big_undead_returned, the save's hold keys). Headless, no
## autoloads.

var t: TestUtil


func _mk(seed_val := 1) -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(seed_val)
	s.debug_enabled = true
	return s


func run() -> int:
	t = TestUtil.new()
	_version()
	_retake()
	return t.failures


func _version() -> void:
	t.suite("api-v6")
	var s := _mk()
	t.ok(GameState.API_VERSION == 6 and s.to_dict()["api_version"] == 6, "API_VERSION is 6")
	for f in s.to_dict()["realm"]["forts"]:
		t.ok(f["held"] is bool and f["grace_s"] is float and f["zero_s"] is float and not f.has("held_s"),
			"%s: the save writes held, grace_s, zero_s (no held_s)" % f["id"])


## A contested Greywall with a siege big undead, no WAR (all FLOOD: no WORK, so no muster) and her
## living there: broken after break_s; fort_retaken {fort_id, cause: "broken"} then
## big_undead_returned {uid, fort_id}, both in the contract; the big undead is in the crypt.
func _retake() -> void:
	t.suite("api-v6-retake")
	var s := _mk()
	t.ok(s.cmd_debug_grant({"big_undead": 1})["ok"], "a big undead (setup)")
	var uid: String = s.view_big_undead()["big_undead"][0]["uid"]
	t.ok(s.cmd_place_big_undead(uid, "fort:greywall")["ok"], "placed at Greywall as siege")
	s.cmd_debug_set_state({"valve": {"work": 0.0, "war": 0.0, "flood": 1.0}, "forts": {"greywall": {"living": 60.0, "undead": 0.0}}})
	s.realm.hold("greywall", 0.0)
	s.drain_events()
	var got: Array = []
	for i in int(float(s._cfg()["hold"]["break_s"]) / s.substep_s()) + 2:
		s.tick(s.substep_s())
		got.append_array(s.drain_events().filter(func(e): return e["type"] in ["fort_retaken", "big_undead_returned"]))
	t.ok(got.size() == 2 and got[0]["type"] == "fort_retaken" and got[0]["cause"] == "broken" and got[0]["fort_id"] == "greywall"
		and got[1] == {"type": "big_undead_returned", "uid": uid, "fort_id": "greywall", "t": got[0]["t"]},
		"fort_retaken {greywall, broken}, then big_undead_returned {uid, fort_id} at its t: %s" % str(got))
	for e in got:
		var errs: Array = []
		ApiSchema.check(e, ApiSchema.EVENTS[e["type"]], e["type"], errs)
		t.ok(errs.is_empty(), "%s matches the contract%s" % [e["type"], "" if errs.is_empty() else ": " + str(errs)])
	t.ok(s.view_big_undead()["big_undead"][0]["place"] == "crypt" and s.view_fort("greywall")["siege"] == [] and not s.view_fort("greywall")["held"],
		"the big undead is back in the crypt; Greywall is no longer held")
