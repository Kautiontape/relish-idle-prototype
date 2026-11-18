extends RefCounted
## TownForecast (Q-f): the "If you leave now" line from the views the town already fetches.

var t: TestUtil
var cfg: Dictionary
var vcfg: Dictionary
var bv: Dictionary


func run() -> int:
	t = TestUtil.new()
	t.suite("town-forecast")
	cfg = TestUtil.configs()
	vcfg = cfg["town"]["view"]
	bv = cfg["buildings_view"]
	_queue()
	_stores()
	_idle_and_forts()
	_fixtures()
	return t.failures


func _views(s: GameState) -> Dictionary:
	var forts: Array = []
	for f in s.view_realm()["forts"]:
		forts.append({"name": String(f["name"]), "held": bool(f["held"]), "margin": String(f["margin"])})
	return {"town": s.view_town(), "hud": s.view_hud(), "forts": forts}


func _queue() -> void:
	var town := {"queue": []}
	t.ok(TownForecast.queue_part({"town": town}, vcfg, bv) == "nothing is queued, so nothing gets built", "an empty queue says nothing gets built")
	town["queue"] = [{"building_id": "inn", "status": "skipped_gate", "reason": "needs_tier"},
		{"building_id": "house", "status": "waiting_funds", "affordable_in_s": 360.0}]
	t.ok(TownForecast.queue_part({"town": town}, vcfg, bv) == "House starts in ~6 min", "the first ungated entry by its affordable_in_s: '%s'" % TownForecast.queue_part({"town": town}, vcfg, bv))
	town["queue"][1]["affordable_in_s"] = -1.0
	t.ok(TownForecast.queue_part({"town": town}, vcfg, bv) == "House can't be afforded at today's income", "a never head says so")
	town["queue"][1]["status"] = "next"
	t.ok(TownForecast.queue_part({"town": town}, vcfg, bv) == "House starts at once", "a next head starts at once")
	town["queue"] = [{"building_id": "inn", "status": "skipped_gate", "reason": "needs_tier"}]
	t.ok(TownForecast.queue_part({"town": town}, vcfg, bv).begins_with("the queue waits on gates (Inn"), "every entry gated: the queue waits on gates")
	t.ok(TownForecast.queue_part({"town": {}}, vcfg, bv) == "", "no queue in the view: no queue part")
	# the M2 review's should-fix 6: a row without affordable_in_s is unknown, not never
	town["queue"] = [{"building_id": "house", "status": "waiting_funds"}]
	t.ok(TownForecast.queue_part({"town": town}, vcfg, bv) == "House starts when it can be paid for",
		"no affordable_in_s: unknown, not never ('%s')" % TownForecast.queue_part({"town": town}, vcfg, bv))
	town["queue"] = [{"building_id": "house", "status": "next"}]
	t.ok(TownForecast.queue_part({"town": town}, vcfg, bv) == "House starts at once", "a next head with no affordable_in_s still starts at once")


func _stores() -> void:
	var fc: Dictionary = vcfg["forecast"]
	var hud := {"rates": [{"id": "gold", "rate": 1.0, "stock": 0.0, "cap": 7200.0}, {"id": "bone", "rate": 1.0, "stock": 0.0, "cap": 360.0},
		{"id": "bodies", "rate": -1.0, "stock": 10.0, "cap": 100.0}]}
	t.ok(TownForecast.store_part({"hud": hud}, fc, vcfg) == "bone full in ~6 min", "the first store to fill is named: '%s'" % TownForecast.store_part({"hud": hud}, fc, vcfg))
	hud["rates"][1]["cap"] = 1.0e9
	hud["rates"][0]["cap"] = 1.0e9
	t.ok(TownForecast.store_part({"hud": hud}, fc, vcfg) == "", "nothing fills within the horizon: no store part")
	hud["rates"][2] = {"id": "bodies", "rate": 0.0, "stock": 100.0, "cap": 100.0}
	t.ok(TownForecast.store_part({"hud": hud}, fc, vcfg) == "bodies is full: more isn't kept", "a full store says more isn't kept")


func _idle_and_forts() -> void:
	var v := {"town": {"workers": {"idle": 10.4}}, "hud": {"split": {"muster_to": "war"}},
		"forts": [{"name": "Vespers", "held": true, "margin": "will_fall"}, {"name": "Ashgate", "held": true, "margin": "safe"},
			{"name": "Greywall", "held": false, "margin": "will_fall"}]}
	var parts := TownForecast.parts_of(v, vcfg, bv)
	t.ok(parts == ["10 idle hands muster to WAR (your forts)", "Vespers will fall"], "idle hands (the Muster stance's WAR) and a held fort that will fall (%s)" % str(parts))
	t.ok(TownForecast.line(v, vcfg, bv) == "If you leave now: 10 idle hands muster to WAR (your forts) · Vespers will fall", "the line: '%s'" % TownForecast.line(v, vcfg, bv))
	t.ok(TownForecast.line({}, vcfg, bv) == "", "nothing to say: no line")


func _fixtures() -> void:
	for fx in ["day1", "midgame_2flips", "pre_vei"]:
		var s := GameState.new(cfg)
		s.debug_enabled = true
		t.ok(s.cmd_debug_load_fixture(fx)["ok"], "(setup) %s loads" % fx)
		s.tick(s.substep_s())  # a step's rates (a fixture loads with none)
		var line := TownForecast.line(_views(s), vcfg, bv)
		t.ok(line.begins_with("If you leave now: ") and line.contains("nothing is queued"), "%s: '%s'" % [fx, line])
