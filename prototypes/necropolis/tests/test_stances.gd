extends RefCounted
## E3-1, the stances (MECHANICS §4.5; STATE-API §3 step 1, §5.11): each acts on the job ladder while its condition
## holds. From constructed states (a new game with buildings placed and stocks set):
## - each stance's effect on ladder_effective and the staffing (Vigil tend, Harvest haul, Hearth stall to the top;
##   Muster's idle cap of 0; Thrift's idled buildings), and the priority when two lift at once (config order);
## - `active` is the condition alone, for an off stance too, with no effect; a suspended stance has no effect;
## - the hold stops a second change within stance.hold_s; fired_beat_id and stance_fired at each change;
## - Thrift: it idles eligible buildings in its order until the income covers the upkeep; an L8 raising pit, an L8
##   charnel house, the Market and the Bone Mill are never idled; an idled building reads "idle", pays no upkeep and
##   keeps its caps and tier count;
## - the away report's Thrift line (kind `unpaid`, the lot as target);
## - `projected` against a short live run with the stance toggled (Hearth's gold, Muster's WAR, Thrift's gold);
## - a save -> load round trip keeps the stance state; the old shape (the fixtures') loads as nothing held, never fired;
## - with no stance on, a 12 h catch-up from each fixture is bit-identical to the tip's (TIP);
## - with Thrift and Harvest on, pre_vei caught up 30 min at 10 s steps matches 30 min live at 0.5 s (test_catchup's
##   compare()). tests/slow/stances_catchup.gd has the 6 h midgame_2flips run and Thrift's flicker measure.

var t := TestUtil.new()
var _dir := "user://test_stances_%d" % OS.get_process_id()
const CLOCK := 1_800_000_000  # a "now" for the saves (unix seconds)
## The tip's catch-ups with no stance on (41749be, before the stances went live): each fixture saved and loaded
## 12 h on, the field shrunk as test_catchup's harness has it. identity() hashes the state (to_dict() less its
## stances block and api_version, and from E3-3 less each big undead's filled_slots), the events the catch-up
## collected (less stance_fired) and its away report.
## Re-pinned at E4 step 3 (the standing re-pin rule; the no-stance proof was made at its own commit): K 12000 -> 36M
## with the fixtures' backlog re-saved to match (pre_vei 54M, midgame_2flips 12M, through the sim). day1's state and
## events stay, and its report's backlog line gains "· odds A -> B"; pre_vei's events stay; midgame starts fewer waves
## (4 355 steps). The reports agree with test_backups' and test_big_undead's. The notes below are from before.
## Re-pinned at E4 step 5's A1 (the muster joins FLOOD unless the Muster stance acts; the standing re-pin rule): A1's
## route alone, the same runs as test_backups' A1 re-pin (whose reasons apply: day1's bodies end at 0 below the bone
## edge, midgame_2flips' backlog +230,846 -> +285,393 over 4 356 steps, pre_vei's +1,692,203 -> +1,867,726). The
## states, and midgame_2flips' events for its waves' shifted moments; day1's and pre_vei's events are unchanged. The
## proof tree (A1 with the route forced to WAR, the early-return off, the old start valve) passes the old pins. Was:
## day1 f0770dea… / 31d28a99…, midgame_2flips a78060c3… / d65e73ac… / de13aae3…, pre_vei febd8f3c… / 73b76696….
const TIP := {
	"day1": {"state": "fbc9c79e62dc856e69d09c8468037cb0f6cd426ec5fd46e5e4fa951f89ef8b6b",
		"events": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
		"away": "4f807d582bdab4438a59f072de13bc7190c471c3faba89df978b687cfa3bc958", "steps": 4320, "n_events": 0},
	# midgame's state and away report re-baselined at E3-3's foreman: its Market's foreman (u8, m 1.183, presence +0.064)
	# takes its 12 h gold from +6,912 to +9,094, to the 9,750 cap (193 not stored), so the report's ready line is the
	# stores-full raid prompt and it gains "Gold is full: 193 not stored"; its morale 0.630 -> 0.694. The events are
	# unchanged, and with u8 in the crypt it is the parent's (test_big_undead).
	# Re-baselined again at E3-3's siege: u9's siege blocks 0.6 of every wave at Ashgate (it holds, as before, now
	# through 179 waves, one more starting inside the 12 h: 4 424 steps, 365 events less stance_fired); Old Sluice's
	# retake is unchanged (4 917.2 s). Her backlog gains +224,003 against +216,247, and the report adds "village
	# Bellwether lost to Vei". With u8 and u9 in the crypt it is 0e4f932's (test_big_undead)
	# E4 step 7: the away report only (the full store's line moved from losses to ready), as test_backups' re-pin;
	# state and events unchanged (was 61a7e99c…; pre_vei below was 982d56f5…)
	# E4's in-flight overlay (the standing re-pin rule): the state only, for Bellwether's end owner (player, as live play
	# reads Covington's cell, not none); living at its cap of 26 either way, events and report unchanged (was eddec826…)
	# E4 step 5 B1 (ii) (the standing re-pin rule), as test_backups' re-pin: Old Sluice retaken at 4 618.6 s under the
	# lowest-margin rule (was 4 986.1 s), fort_retaken's two new keys, the retake line's cause. The same proof tree passes
	# the old pins (was ccdf38fd… / 0466a66d… / e0a288bf…)
	"midgame_2flips": {"state": "22a85c67268629792e832f5b20a42cb5fbc08e2598b0f152ca6ded8a0e2af944",
		"events": "f17e78e57a431cf40ea91355d57f364ba071f83bb8bec84836dcc7fbe674c33e",
		"away": "1d3c4855bb029af3b6dfa1433ca9c105a4abfc55f6ccd95432e33da2dcb40af0", "steps": 4356, "n_events": 237},
	# pre_vei re-pinned at E4 step 4's resume rule (the manager's ruling (i); the standing re-pin rule): the second House
	# no longer resumes after the floor, so one event fewer (10, not 11; stance_fired aside), and the away report is
	# test_backups' re-pinned pre_vei report ("Still stopped, ... Build a Market").
	# E4's convoy claim (the standing re-pin rule): pre_vei's state and away report, as test_backups' re-pin (the convoy
	# lands the corpses formed inside each step; the events unchanged). The claim off passes the old pins (was
	# 58a6cc49… / a8a97ed8…).
	"pre_vei": {"state": "de513152d69743260fd894dbb6ca6af748470f4dae3104227ef2955e0cdd70b7",
		"events": "efa1e63ebbc4696325c4165bb19bde5bc21019c63723ee23dab7ee4a6a7bb84d",
		"away": "0915402c0be357206af1a20c74afe1c3041807f967ac0e1d7c7b178a1c0866f8", "steps": 4321, "n_events": 10},
}


func run() -> int:
	t.suite("stances")
	DirAccess.make_dir_recursive_absolute(_dir)
	_config()
	_ladder_effects()
	_muster()
	_off_and_suspended()
	_priority()
	_hold_and_fired()
	_thrift_order()
	_thrift_never()
	_thrift_keeps()
	_thrift_away_line()
	_thrift_upgrade_held()
	_muster_refreshes_projections()
	_projected()
	_round_trip()
	_old_shape()
	_identity()
	_catchup_10s()
	_cleanup()
	return t.failures


func _cleanup() -> void:
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(_dir)


## test_catchup's harness configs: the shipped ones with the field shrunk (8 × 6) and its pre-warm off, then `over`
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


## A new game (day1) under `c`, debug on, saving under the suite's directory.
func _mk(c: Dictionary = {}) -> GameState:
	var s := GameState.new(cfgs() if c.is_empty() else c)
	s.debug_enabled = true
	s.save_dir = _dir
	s.cmd_new_game(1)
	return s


static func _st(s: GameState, id: String) -> Dictionary:
	for e in s.view_stances()["stances"]:
		if e["id"] == id:
			return e
	return {}


## view_town's jobs as {job: staffed}.
static func _staffed(s: GameState) -> Dictionary:
	var out := {}
	for j in s.view_town()["jobs"]:
		out[j["id"]] = float(j["staffed"])
	return out


static func _state_of(s: GameState, lot_id: String) -> String:
	for b in s.view_town()["buildings"]:
		if b["lot_id"] == lot_id:
			return str(b["state"])
	return ""


## Runs one substep that reads the conditions (a beat the stance step hasn't read yet).
static func _beat(s: GameState) -> void:
	s._stance_beat = -1
	s.tick(0.5)


# ---------------------------------------------------------------------------------------------------- config ----
func _config() -> void:
	var c := TestUtil.configs()
	var st: Dictionary = c["economy"]["stance"]
	t.ok(GameState.stance_config_problem(c) == "" and GameState.catchup_config_problem(c) == "",
		"the shipped stance block passes its checks: priority %s, top_job %s, hold_s %s" % [str(st["priority"]), str(st["top_job"]), str(st["hold_s"])])
	var bad := TestUtil.configs()
	(bad["economy"]["stance"]["priority"] as Array).erase("hearth")
	t.ok(GameState.stance_config_problem(bad).find("hearth") >= 0, "a ladder stance missing from stance.priority is a problem: %s" % GameState.stance_config_problem(bad))
	bad = TestUtil.configs()
	bad["economy"]["stance"]["top_job"]["harvest"] = "nope"
	t.ok(GameState.stance_config_problem(bad).find("harvest") >= 0, "a stance lifting no job is a problem: %s" % GameState.stance_config_problem(bad))
	bad = TestUtil.configs()
	(bad["economy"]["stance"] as Dictionary).erase("hold_s")
	t.ok(GameState.catchup_config_problem(bad).find("stance.hold_s") >= 0, "a config without stance.hold_s is a problem now (E3-1): %s" % GameState.catchup_config_problem(bad))


# ---------------------------------------------------------------------------------------------- the effects ----
## Each ladder stance lifts its job to the top of the effective ladder while it acts, and the staffing follows at once
## (the room cache is marked): Harvest takes 3 hands from the build job (a House under way), Hearth 2 from the haul for
## the stalls, Vigil 1 for a staffed vat's tend slot while Relish is away.
func _ladder_effects() -> void:
	# Harvest: bodies under 30% of the cap, a construction under way and 3 workers
	var s := _mk()
	t.ok(s.cmd_build("house", "lot-05")["ok"], "(setup) a House under way: 3 build slots above the haul's")
	s.town_sim.workers = 3.0
	s.town_sim.restaff()
	var before := _staffed(s)
	t.ok(s.cmd_set_stance("harvest", true)["ok"], "(setup) Harvest on")
	t.ok(s.view_town()["ladder_effective"][0] == "build" and not _st(s, "harvest")["active"],
		"Harvest on but not yet active (no beat read since the new game): the ladder is the player's")
	_beat(s)
	var after := _staffed(s)
	var town := s.view_town()
	t.ok(_st(s, "harvest")["active"] and town["ladder_effective"] == ["haul", "build", "pit", "stall", "mill", "forge", "tend"]
		and town["ladder"][0] == "build", "Harvest acting (bodies %.0f under 30%% of %.0f): haul on top of ladder_effective, the ladder kept: %s" % [
		s.town_sim.bodies, s.town_sim.body_cap(), str(town["ladder_effective"])])
	t.ok(float(before.get("build", 0.0)) > 2.9 and float(before.get("haul", 0.0)) < 0.1 and float(after.get("haul", 0.0)) > 2.9 and float(after.get("build", 0.0)) < 0.1,
		"Harvest: the 3 hands move from build to haul (%s -> %s)" % [str(before), str(after)])
	# Hearth: morale under 0.5, 2 workers, the haul above the stalls
	s = _mk()
	s.town_sim.workers = 2.0
	s.town_sim.morale = 0.3
	s.town_sim.restaff()
	before = _staffed(s)
	s.cmd_set_stance("hearth", true)
	_beat(s)
	after = _staffed(s)
	t.ok(_st(s, "hearth")["active"] and s.view_town()["ladder_effective"][0] == "stall" and float(before.get("stall", 0.0)) < 0.1
		and float(after.get("stall", 0.0)) > 1.9, "Hearth acting (morale %.2f): stall on top, the 2 hands go from haul to the stalls (%s -> %s)" % [
		s.town_sim.morale, str(before), str(after)])
	# Vigil: Relish away, a Chapel with vat 0 staffed (its tend slot), 2 workers
	s = _mk()
	s.town_sim.place_building("lot-13", "chapel_of_vats", 1)
	t.ok(s.cmd_staff_vat(0, true)["ok"], "(setup) vat 0 staffed: its tend slot opens")
	s.town_sim.workers = 2.0
	s.town_sim.restaff()
	before = _staffed(s)
	s.cmd_set_stance("vigil", true)
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	_beat(s)
	after = _staffed(s)
	t.ok(_st(s, "vigil")["active"] and s.view_town()["ladder_effective"][0] == "tend" and float(before.get("tend", 0.0)) < 0.1
		and float(after.get("tend", 0.0)) > 0.9, "Vigil acting (Relish %s): tend on top, a hand to the vat (%s -> %s)" % [s.relish["state"], str(before), str(after)])
	s.cmd_debug_set_state({"relish_at": "covington"})
	t.ok(_st(s, "vigil")["active"], "Relish home again: Vigil stays active through its hold")


## Muster: idle workers (12 on day1's 7 slots) -> the idle cap reads 0 while it acts, and the idle hands muster to WAR
## at once: the workforce ends the step at the slots, nobody idle, and view_town's steady_kept is the slots.
func _muster() -> void:
	var s := _mk()
	s.tick(0.5)
	var idle0 := float(s.view_town()["workers"]["idle"])
	var slots := float(s.town_sim.staffing["slots"])
	s.cmd_set_stance("muster", true)
	_beat(s)
	var w: Dictionary = s.view_town()["workers"]
	t.ok(idle0 > 1.0 and _st(s, "muster")["active"] and s.town_sim.idle_cap() == 0.0 and float(w["idle"]) == 0.0
		and absf(float(w["total"]) - slots) < 1e-6 and float(s._split["muster"]) > 0.0,
		"Muster acting: the %.1f idle hands muster to WAR at once (the step's muster %.1f mass/s), the workforce at the %.0f slots, idle cap 0" % [
		idle0, float(s._split["muster"]), slots])
	t.ok(absf(float(w["steady_kept"]) - minf(float(w["steady"]), slots)) < 1e-6, "Muster: steady_kept reads the idle cap of 0 (%.2f)" % float(w["steady_kept"]))
	s.drain_events()
	var held := true
	for i in int(4.0 * float(s._cfgs["economy"]["stance"]["hold_s"]) / s.substep_s()):
		s.tick(s.substep_s())
		held = held and _st(s, "muster")["active"] and float(s.view_town()["workers"]["idle"]) == 0.0
	var offs: Array = s.drain_events().filter(func(e): return e["type"] == "stance_fired" and e["stance_id"] == "muster")
	t.ok(held and offs.is_empty() and float(s.town_sim.rates["workers"]["muster"]) > 0.0,
		"four holds on, nobody idle (Muster's own effect) but the town still musters hands: Muster stays active at every step, no stance_fired (%s)" % str(offs))
	s.cmd_set_stance("muster", false)
	t.ok(s.town_sim.idle_cap() == float(s._cfgs["economy"]["worker"]["idle_cap"]), "Muster off: the idle cap is economy.json's again")


## `active` is the condition alone, for every stance on or off: an off stance whose condition holds is active and has
## no effect. A suspended stance (on, but past the slots) is active and has no effect either, until a slot frees.
func _off_and_suspended() -> void:
	var s := _mk()
	s.town_sim.workers = 2.0
	s.town_sim.morale = 0.3
	s.town_sim.restaff()
	_beat(s)
	t.ok(_st(s, "hearth")["active"] and not _st(s, "hearth")["on"] and s.view_town()["ladder_effective"] == s.view_town()["ladder"]
		and _st(s, "harvest")["active"] and not _st(s, "vigil")["active"],
		"off stances: Hearth (morale %.2f) and Harvest (bodies %.0f) are active, Vigil isn't (Relish home); the ladder is the player's" % [
		s.town_sim.morale, s.town_sim.bodies])
	# three on at home (3 slots), Relish leaves: the newest (Vigil) is suspended, with no effect
	s.town_sim.place_building("lot-13", "chapel_of_vats", 1)
	s.cmd_staff_vat(0, true)
	for id in ["harvest", "hearth", "vigil"]:
		s.cmd_set_stance(id, true)
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	_beat(s)
	var eff: Array = s.view_town()["ladder_effective"]
	t.ok(_st(s, "vigil")["suspended"] and _st(s, "vigil")["active"] and eff.slice(0, 2) == ["haul", "stall"] and eff.find("tend") >= 2,
		"Relish away (2 slots): Vigil, the newest, is suspended though active, so tend stays down; Harvest and Hearth act: %s" % str(eff))
	s.cmd_set_stance("harvest", false)
	t.ok(not _st(s, "vigil")["suspended"] and s.view_town()["ladder_effective"].slice(0, 2) == ["tend", "stall"],
		"Harvest off: a slot frees, Vigil acts at once (tend above Hearth's stall: stance.priority): %s" % str(s.view_town()["ladder_effective"]))


## Two stances lift at once: their jobs go to the top in economy.json stance.priority order (vigil, harvest, hearth
## shipped); the order is config.
func _priority() -> void:
	for pri in [["vigil", "harvest", "hearth"], ["harvest", "hearth", "vigil"]]:
		var s := _mk(cfgs({"economy.stance.priority": pri}))
		s.cmd_set_stance("vigil", true)
		s.cmd_set_stance("harvest", true)
		s.cmd_debug_set_state({"relish_at": "old-sluice"})
		_beat(s)
		var want: Array = ["tend", "haul"] if pri[0] == "vigil" else ["haul", "tend"]
		t.ok(_st(s, "vigil")["active"] and _st(s, "harvest")["active"] and s.view_town()["ladder_effective"].slice(0, 2) == want,
			"stance.priority %s: Vigil and Harvest both act, %s on top: %s" % [str(pri), str(want), str(s.view_town()["ladder_effective"])])


## The hold (stance.hold_s, 20 s): a change can't be undone before it has passed; hold_s_left shows what is left;
## fired_beat_id is the beat of the last change and stance_fired reports each change.
func _hold_and_fired() -> void:
	var s := _mk()
	var hold := float(s._cfgs["economy"]["stance"]["hold_s"])
	s.tick(0.5)
	s.drain_events()
	t.ok(_st(s, "vigil")["fired_beat_id"] == -1 and not _st(s, "vigil")["active"], "Vigil never fired at home: fired_beat_id -1")
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	var t_set := s.t
	s.tick(2.0)
	var fired: Array = s.drain_events().filter(func(e): return e["type"] == "stance_fired" and e["stance_id"] == "vigil")
	var e1 := _st(s, "vigil")
	t.ok(fired.size() == 1 and bool(fired[0]["active"]) and int(fired[0]["beat_id"]) == int(e1["fired_beat_id"]) and e1["active"]
		and int(e1["fired_beat_id"]) == s.beat_at(float(fired[0]["t"])) and float(e1["hold_s_left"]) > hold - 2.0 and float(e1["hold_s_left"]) <= hold,
		"Relish away: at the next beat Vigil turns active (off, as it is): one stance_fired {vigil, true, beat %d}, fired_beat_id %d, hold_s_left %.1f" % [
		int(fired[0]["beat_id"]) if not fired.is_empty() else -1, int(e1["fired_beat_id"]), float(e1["hold_s_left"])])
	var changed_t := float(fired[0]["t"]) if not fired.is_empty() else t_set
	s.cmd_debug_set_state({"relish_at": "covington"})
	s.tick(hold - 3.0)
	var e2 := _st(s, "vigil")
	t.ok(e2["active"] and s.drain_events().filter(func(e): return e["type"] == "stance_fired" and e["stance_id"] == "vigil").is_empty()
		and float(e2["hold_s_left"]) > 0.0 and absf(float(e2["hold_s_left"]) - (changed_t + hold - s.t)) < 1e-6,
		"home again: Vigil holds active for the rest of stance.hold_s (%.1f s left at %.1f s after its change), no stance_fired" % [
		float(e2["hold_s_left"]), s.t - changed_t])
	s.tick(5.0)
	fired = s.drain_events().filter(func(e): return e["type"] == "stance_fired" and e["stance_id"] == "vigil")
	var e3 := _st(s, "vigil")
	t.ok(fired.size() == 1 and not bool(fired[0]["active"]) and not e3["active"] and float(fired[0]["t"]) - changed_t >= hold
		and float(fired[0]["t"]) - changed_t < hold + s._beat_s + s.substep_s() and int(e3["fired_beat_id"]) == int(fired[0]["beat_id"])
		and float(e3["hold_s_left"]) > 0.0,
		"the hold over: Vigil turns inactive at the first beat %.1f s after its change (stance_fired {vigil, false}), fired_beat_id %d, a new hold" % [
		float(fired[0]["t"]) - changed_t if not fired.is_empty() else -1.0, int(e3["fired_beat_id"])])


# --------------------------------------------------------------------------------------------------- Thrift ----
## day1 plus a Statue and a Plaza (decorations, 0.15 gold/s each), a Reliquary (0.2) and a Watchtower (0.08), passive,
## and a House (0.01): 0.68 gold/s of upkeep on 0.3 of trade. Thrift idles the decorations first (the Statue, then the
## Plaza: lot order), then the dearest passive building, the Reliquary, and stops once the income covers what is
## still paid (0.18): the Watchtower and the House work on.
func _thrift_town(c: Dictionary = {}) -> GameState:
	var s := _mk(c)
	for e in [["lot-05", "statue"], ["lot-13", "plaza"], ["lot-23", "reliquary"], ["lot-06", "watchtower"], ["lot-07", "house"]]:
		s.town_sim.place_building(e[0], e[1], 1)
	s.town_sim.gold = 500.0
	return s


func _thrift_order() -> void:
	var s := _thrift_town()
	var income := s.town_sim.trade_income()
	var bill := s.town_sim.gold_bill()
	s.cmd_set_stance("thrift", true)
	_beat(s)
	var idled: Array = s.town_sim._lists()["thrift"]
	t.ok(_st(s, "thrift")["active"] and idled == ["lot-05", "lot-13", "lot-23"],
		"Thrift (income %.2f < upkeep %.2f): it idles the Statue and the Plaza (decorations, lot order), then the Reliquary (the dearest passive), and stops: %s" % [
		income, bill, str(idled)])
	t.ok(_state_of(s, "lot-06") == "active" and _state_of(s, "lot-07") == "active" and s.town_sim.trade_income() >= bill - 0.5 - 1e-9,
		"the Watchtower and the House work on: the income covers what is still paid (%.2f)" % (bill - 0.5))
	# a smaller deficit: the decorations go first even before a dearer passive building
	var d := _thrift_town()
	d.town_sim.place_building("lot-04", "market", 2)
	d.town_sim.living = 20.0
	d.town_sim.restaff()
	t.ok(d.town_sim.thrift_pick() == ["lot-05"], "a deficit of %.2f (trade %.2f): Thrift would idle the Statue alone (a decoration, 0.15), not the dearer Reliquary (passive, 0.2): %s" % [
		d.town_sim.gold_bill() - d.town_sim.trade_income(), d.town_sim.trade_income(), str(d.town_sim.thrift_pick())])
	t.ok(_st(s, "thrift")["active"] and s.town_sim.trade_income() < s.town_sim.gold_bill(), "its condition counts the buildings it idles as paying, so its effect doesn't switch it off")
	s.cmd_set_stance("thrift", false)
	t.ok((s.town_sim._lists()["thrift"] as Array).is_empty() and _state_of(s, "lot-05") == "active" and _state_of(s, "lot-23") == "active",
		"Thrift off: every building it idled works again")
	# no deficit: Thrift's condition doesn't hold and it idles nothing
	var r := _mk()
	r.cmd_set_stance("thrift", true)
	_beat(r)
	t.ok(not _st(r, "thrift")["active"] and (r.town_sim._lists()["thrift"] as Array).is_empty(),
		"day1 (income %.2f covers upkeep %.2f): Thrift isn't active and idles nothing" % [r.town_sim.trade_income(), r.town_sim.gold_bill()])


## Never idled, whatever its upkeep: the WAR chain (an L8 raising pit, an L8 charnel house, the Bone Mill: its classes
## rank from stance.thrift_spares_from on) and a store's earner (the Market). With stance.thrift_upkeep at 0 (every
## building with upkeep qualifies by price) and no living (no trade), Thrift idles every other building with upkeep.
func _thrift_never() -> void:
	var s := _thrift_town(cfgs({"economy.stance.thrift_upkeep": 0.0}))
	s.town_sim.place_building("lot-08", "raising_pit", 8)
	s.town_sim.place_building("lot-15", "charnel_house", 8)
	s.town_sim.place_building("lot-09", "bone_mill", 3)
	s.town_sim.place_building("lot-14", "chapel_of_vats", 1)
	s.town_sim.living = 0.0
	s.town_sim.restaff()
	s.cmd_set_stance("thrift", true)
	_beat(s)
	var idled: Array = s.town_sim._lists()["thrift"]
	var spared := ["lot-02", "lot-03", "lot-04", "lot-08", "lot-09", "lot-15"]
	var none_spared := spared.all(func(lot): return s.town_sim.buildings[lot]["state"] != "thrift")
	t.ok(idled == ["lot-05", "lot-06", "lot-07", "lot-13", "lot-14", "lot-23"] and none_spared and _st(s, "thrift")["active"],
		"Thrift with no trade and stance.thrift_upkeep 0: it idles the Statue, Watchtower, House, Plaza, Chapel and Reliquary %s; never the L8 raising pit, the L8 charnel house, the Bone Mill (the WAR chain), the Market (gold's earner) or the start pit and charnel house %s" % [
		str(idled), str(spared.map(func(lot): return "%s %s L%d" % [lot, s.town_sim.buildings[lot]["building_id"], int(s.town_sim.buildings[lot]["level"])]))])
	s.tick(60.0)
	t.ok(spared.all(func(lot): return s.town_sim.buildings[lot]["state"] != "thrift") and _st(s, "thrift")["active"],
		"a minute on, Thrift still acting: none of them is Thrift's (%s)" % str(spared.map(func(lot): return s.town_sim.buildings[lot]["state"])))


## A Thrift-idled building reads state "idle" in view_town, gives no slots or output, pays no upkeep (the next step's
## gold out drops by it), and keeps its capacity effects (the Reliquary's relic and essence caps, the Chapel's vats)
## and its tier count (next_tier's have).
func _thrift_keeps() -> void:
	var s := _thrift_town()
	s.town_sim.place_building("lot-14", "chapel_of_vats", 1)
	s.tick(0.5)
	var inv0 := s.view_inventory()
	var vats0: int = s.view_backups()["vats"].size()
	var have0 := int(s.view_town()["next_tier"]["have"])
	var out0 := float(s.town_sim.rates["gold"]["out"])
	s.cmd_set_stance("thrift", true)
	_beat(s)
	var row: Dictionary = {}
	for b in s.view_town()["buildings"]:
		if b["lot_id"] == "lot-23":
			row = b
	var inv1 := s.view_inventory()
	t.ok(s.town_sim.buildings["lot-23"]["state"] == "thrift" and row["state"] == "idle" and int(row["slots"]) == 0 and (row["output"] as Dictionary).is_empty(),
		"the Reliquary idled by Thrift: view_town state idle, no slots, no output")
	t.ok(inv1["relics_cap"] == inv0["relics_cap"] and inv1["essence_cap"] == inv0["essence_cap"] and int(s.view_backups()["vats"].size()) == vats0
		and int(s.view_town()["next_tier"]["have"]) == have0,
		"its caps stand (relics %d, essence %d), the vats too (%d), and the tier counts it (have %d)" % [int(inv1["relics_cap"]), int(inv1["essence_cap"]), vats0, have0])
	var idled: Array = s.town_sim._lists()["thrift"]
	var saved := 0.0
	for lot in idled:
		saved += float(s.town_sim._defs[s.town_sim.buildings[lot]["building_id"]]["upkeep_gold"])
	t.near(out0 - float(s.town_sim.rates["gold"]["out"]), saved, 1e-9, "it pays no upkeep: the step's gold out falls by the idled buildings' %s" % str(idled))


## The away report names Thrift (IDLE §7): day1 with a Statue and a Reliquary on 5 living's trade, Thrift idling both,
## saved and loaded 30 min on: one line each in losses, kind `unpaid`, the lot as target, "idled by Thrift", not "ran out".
func _thrift_away_line() -> void:
	var s := _mk()
	s.town_sim.place_building("lot-05", "statue", 1)
	s.town_sim.place_building("lot-23", "reliquary", 1)
	s.town_sim.gold = 500.0
	s.town_sim.living = 5.0
	s.town_sim.restaff()
	s.cmd_set_stance("thrift", true)
	_beat(s)
	t.ok(s.town_sim._lists()["thrift"] == ["lot-05", "lot-23"], "(setup) Thrift idles the Statue and the Reliquary")
	s.clock_override = CLOCK
	s.cmd_save("thrift")
	var n := GameState.new(cfgs())
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = CLOCK + 1800
	n.cmd_load("thrift")
	var lines: Array = n.view_away()["losses"].filter(func(l): return l["kind"] == "unpaid")
	var texts: Array = lines.map(func(l): return l["text"])
	t.ok(texts == ["Statue of Relish idled by Thrift for 30 m: lifted no morale, deaths shook the town harder", "Reliquary idled by Thrift for 30 m"]
		and lines.map(func(l): return l["target"]) == ["lot-05", "lot-23"],
		"30 min away with Thrift idling them: %s" % str(lines))
	t.ok(not texts.any(func(x): return str(x).contains("ran out")), "no line says the gold ran out")


## An upgrade doesn't undo Thrift's idle (qf3 fix 1): a Chapel of Vats L1 (class job, 0.12 upkeep over thrift_upkeep)
## idled by Thrift refuses cmd_upgrade (unpaid), and a queued upgrade waits on unpaid while the gold covers it, the
## building staying `thrift` and the away report's Thrift line running, until Thrift lets it go; then it starts.
func _thrift_upgrade_held() -> void:
	var s := _mk()
	s.town_tier = "village"
	s.town_sim.place_building("lot-09", "bone_mill", 3)  # raises bone's cap over the upgrade's 240
	s.town_sim.place_building("lot-14", "chapel_of_vats", 1)
	s.town_sim.living = 0.0
	s.town_sim.restaff()
	s.town_sim.gold = 2000.0
	s.town_sim.bone = 1000.0
	s.relics = 10
	s.cmd_set_stance("thrift", true)
	_beat(s)
	t.ok(s.town_sim.buildings["lot-14"]["state"] == "thrift", "(setup) Thrift idles the Chapel of Vats: %s" % str(s.town_sim._lists()["thrift"]))
	var r := s.cmd_upgrade("lot-14")
	t.ok(not r["ok"] and r["reason"] == "unpaid" and s.town_sim.buildings["lot-14"]["state"] == "thrift",
		"cmd_upgrade on a Thrift-idled building is refused unpaid and leaves it idled: %s" % str(r))
	var qr := s.cmd_queue_build("", "lot-14")
	t.ok(qr["ok"], "(setup) its upgrade queues: %s" % str(qr))
	for i in 120:
		s.tick(0.5)
	var row: Dictionary = s.view_town()["queue"][0] if not (s.view_town()["queue"] as Array).is_empty() else {}
	t.ok(s.town_sim.gold >= 600.0 and s.town_sim.buildings["lot-14"]["state"] == "thrift" and row.get("status", "") == "skipped_gate"
		and row.get("reason", "") == "unpaid",
		"a minute on with the gold covering it: the Chapel is still idled by Thrift and its queued upgrade waits on unpaid: %s" % str(row))
	s.cmd_set_stance("thrift", false)
	for i in 4:
		s.tick(0.5)
	t.ok(s.town_sim.buildings["lot-14"]["state"] == "constructing" and (s.view_town()["queue"] as Array).is_empty(),
		"Thrift off: the Chapel resumes and the queued upgrade starts: %s" % s.town_sim.buildings["lot-14"]["state"])
	# the away report: the same town saved and loaded 30 min on, Thrift idling it the whole while
	var a := _mk()
	a.town_tier = "village"
	a.town_sim.place_building("lot-09", "bone_mill", 3)
	a.town_sim.place_building("lot-14", "chapel_of_vats", 1)
	a.town_sim.living = 0.0
	a.town_sim.restaff()
	a.town_sim.gold = 2000.0
	a.town_sim.bone = 1000.0
	a.relics = 10
	a.cmd_set_stance("thrift", true)
	# E4 step 5 (A1): the town's trade grew because its muster reached the forts as WAR; the muster joins the FLOOD now,
	# so Muster (the second slot) keeps it WAR and the setup's 30 minutes as they were
	a.cmd_set_stance("muster", true)
	_beat(a)
	a.cmd_queue_build("", "lot-14")
	a.clock_override = CLOCK
	a.cmd_save("thriftup")
	var n := GameState.new(cfgs())
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = CLOCK + 1800
	n.cmd_load("thriftup")
	var lines: Array = n.view_away()["losses"].filter(func(l): return l["kind"] == "unpaid")
	# Thrift stops acting 11 m in (the town's trade grows): its line ends there, and only then does the upgrade start.
	# (15 m before E4 step 5's A1, when the muster reached WAR at the idle cap of 10; Muster's cap of 0 sends more;
	# 19 m before E4's in-flight overlay, when the caught-up Bellwether read none and its migrants never came)
	t.ok(lines.size() == 1 and str(lines[0]["text"]).begins_with("Chapel of Vats") and str(lines[0]["text"]).contains("idled by Thrift for 11 m")
		and n.town_sim.buildings["lot-14"]["level"] == 2,
		"30 min away: Thrift's line for the Chapel ends when Thrift stops (11 m), not at the end of the absence, and the upgrade built after: %s %s" % [
		n.town_sim.buildings["lot-14"]["state"], str(lines)])


## Muster lifts no job, so starting it moves no structure_rev by a job change, yet it changes the idle cap the build
## card's projections are computed with (qf3 fix 3): the rows refreshed before it started are stale at once, not after
## projection_refresh_s. The refresh (StateViews._proj_refresh, what the frame path runs) after Muster starts gives
## the rows a from-scratch refresh gives, and they moved.
func _muster_refreshes_projections() -> void:
	var s := _mk()
	s.tick(0.5)
	_beat(s)
	var idle0 := float(s.view_town()["workers"]["idle"])
	StateViews._proj_refresh(s, ["catalog", "upgrades"], 1000, false)
	var before: Array = s.view_catalog()["buildings"].map(func(r): return (r["projected"] as Dictionary).duplicate())
	s.cmd_set_stance("muster", true)
	_beat(s)
	t.ok(idle0 > 1.0 and _st(s, "muster")["active"] and s.town_sim.idle_cap() == 0.0, "(setup) idle hands, and Muster acts (cap 0)")
	StateViews._proj_refresh(s, ["catalog", "upgrades"], 1000, false)
	var after: Array = s.view_catalog()["buildings"].map(func(r): return (r["projected"] as Dictionary).duplicate())
	var town_after: Array = s.view_town()["buildings"].map(func(b): return (b["upgrade_projected"] as Dictionary).duplicate())
	s._proj_cache = {}
	StateViews._proj_refresh(s, ["catalog", "upgrades"], 1000, false)
	var exact: Array = s.view_catalog()["buildings"].map(func(r): return (r["projected"] as Dictionary).duplicate())
	var town_exact: Array = s.view_town()["buildings"].map(func(b): return (b["upgrade_projected"] as Dictionary).duplicate())
	t.ok(before != exact and not before.any(func(p): return (p as Dictionary).is_empty()),
		"(setup) Muster's idle cap of 0 moves the build card's projections")
	t.ok(after == exact and town_after == town_exact,
		"Muster started: the next refresh recomputes every projected and upgrade_projected row at once (the cap of 0), not after projection_refresh_s")


# ------------------------------------------------------------------------------------------------ projected ----
## view_stances' projected against a live run with the stance toggled (two copies of the same state, one toggled,
## stepped together): Hearth's gold (2 hands to the stalls: +0.30/s) within 2%; Muster's WAR (the idle hands' rot
## mustered instead, read after the lump it sends at once) within 5%; Thrift's gold (the idled buildings' upkeep)
## within 1e-9. An inactive stance projects {}.
func _projected() -> void:
	# Hearth
	var s := _mk()
	s.town_sim.workers = 2.0
	s.town_sim.morale = 0.3
	s.town_sim.restaff()
	_beat(s)
	var p: Dictionary = _st(s, "hearth")["projected"]
	var js := JSON.stringify(s.to_dict())
	var a := _from(js)
	var b := _from(js)
	a.cmd_set_stance("hearth", true)
	a.tick(1.0)
	b.tick(1.0)
	var live := _net(a, "gold") - _net(b, "gold")
	t.ok(float(p.get("gold", 0.0)) > 0.0 and absf(float(p["gold"]) - live) <= 0.02 * absf(live),
		"Hearth's projected gold %+.3f/s against the live change %+.3f/s (2 hands to the stalls)" % [float(p.get("gold", 0.0)), live])
	t.ok(_st(s, "vigil")["projected"] == {} and not _st(s, "vigil")["active"], "Vigil (inactive: Relish home) projects {}")
	# Muster: the idle hands' rot becomes WAR
	var m := _mk()
	m.tick(0.5)
	_beat(m)
	var pm: Dictionary = _st(m, "muster")["projected"]
	js = JSON.stringify(m.to_dict())
	a = _from(js)
	b = _from(js)
	a.cmd_set_stance("muster", true)
	a.tick(1.0)
	b.tick(1.0)
	var war := float(a._split["war"]) - float(b._split["war"])
	t.ok(float(pm.get("war", 0.0)) > 0.0 and absf(float(pm["war"]) - war) <= 0.05 * absf(war) and float(pm.get("workers", 0.0)) < 0.0,
		"Muster's projected WAR %+.3f mass/s against the live change %+.3f after its lump; workers %+.4f/s" % [float(pm.get("war", 0.0)), war, float(pm.get("workers", 0.0))])
	# Thrift: the upkeep it saves
	var th := _thrift_town()
	th.tick(0.5)
	_beat(th)
	var pt: Dictionary = _st(th, "thrift")["projected"]
	js = JSON.stringify(th.to_dict())
	a = _from(js)
	b = _from(js)
	a.cmd_set_stance("thrift", true)
	a.tick(0.5)
	b.tick(0.5)
	var dg := _net(a, "gold") - _net(b, "gold")
	t.ok(absf(float(pt.get("gold", 0.0)) - dg) < 1e-9 and absf(dg - 0.5) < 1e-9,
		"Thrift's projected gold %+.3f/s: the Statue's, the Plaza's and the Reliquary's upkeep (%+.3f/s live)" % [float(pt.get("gold", 0.0)), dg])


## What a round trip must keep of the stances: view_stances less rev and projected (its floats come from the
## state's), ladder_effective, the idle cap and Thrift's buildings.
static func _stances_of(s: GameState) -> Dictionary:
	var v := s.view_stances()
	v.erase("rev")
	for e in v["stances"]:
		(e as Dictionary).erase("projected")
	return {"view": v, "ladder": s.view_town()["ladder_effective"], "idle_cap": s.town_sim.idle_cap(), "thrift": s.town_sim._lists()["thrift"]}


func _from(js: String) -> GameState:
	var s := GameState.new(cfgs())
	s.debug_enabled = true
	s.save_dir = _dir
	s.from_dict(JSON.parse_string(js))
	return s


static func _net(s: GameState, id: String) -> float:
	return float(s.view_rates()["rates"][id]["net"])


# ------------------------------------------------------------------------------------------------ the save ----
## A save -> load round trip keeps the stance state: the toggles, each stance's active, fired_beat_id and hold, and
## Thrift's idled buildings; the two then run on identically.
func _round_trip() -> void:
	var s := _thrift_town()
	s.town_sim.living = 5.0
	s.town_sim.restaff()
	for id in ["harvest", "thrift", "vigil"]:
		s.cmd_set_stance(id, true)
	s.cmd_debug_set_state({"relish_at": "old-sluice"})
	s.tick(3.0)
	var d := s.to_dict()
	var n := _from(JSON.stringify(d))
	t.ok(n.to_dict() == d and _stances_of(n) == _stances_of(s) and (d["stances"] as Dictionary).has("state") and not (d["stances"]["hold"] as Dictionary).is_empty()
		and not (n.town_sim._lists()["thrift"] as Array).is_empty(),
		"save -> load keeps the stance state: %s; Thrift's %s" % [str(d["stances"]), str(n.town_sim._lists()["thrift"])])
	s.drain_events()
	s.tick(30.0)
	n.tick(30.0)
	var fs: Array = s.drain_events().filter(func(e): return e["type"] == "stance_fired")
	var fn: Array = n.drain_events().filter(func(e): return e["type"] == "stance_fired")
	t.ok(_stances_of(n) == _stances_of(s) and fn == fs, "and 30 s on the two run on alike: the same stances and Thrift's buildings, the same %d stance_fired" % fs.size())
	var bad := d.duplicate(true)
	bad["stances"]["state"]["vigil"]["active"] = 1
	t.ok(n.from_dict(bad)["reason"] == "corrupt", "a stances.state entry of another shape is corrupt")


## The old shape, the fixtures' stances {hold: {}, on: []}: nothing held, never fired, nothing active, and the file
## comes back as it was (no state key).
func _old_shape() -> void:
	for fx in GameState.FIXTURES:
		var s := GameState.new(cfgs())
		s.debug_enabled = true
		s.cmd_debug_load_fixture(fx)
		var all_clear := true
		for e in s.view_stances()["stances"]:
			all_clear = all_clear and not e["active"] and e["fired_beat_id"] == -1 and e["hold_s_left"] == 0.0 and e["projected"] == {}
		t.ok(all_clear and s.to_dict()["stances"] == {"on": [], "hold": {}}, "%s: nothing held, never fired; its stances block comes back as it was" % fx)


# ---------------------------------------------------------------------------------------------- catch-up ----
## A fixture saved at CLOCK and loaded `seconds` on (a reporting catch-up at the shipped schedule): {state,
## events, away, steps, n_events}, the hashes of to_dict() less `stances` and `api_version`, of the collected
## events less stance_fired, and of view_away's lines.
func identity(c: Dictionary, fixture: String, seconds: int) -> Dictionary:
	var s := GameState.new(c)
	s.debug_enabled = true
	s.save_dir = _dir
	s.cmd_debug_load_fixture(fixture)
	s.clock_override = CLOCK
	s.cmd_save("identity")
	var n := GameState.new(c)
	n.debug_enabled = true
	n.save_dir = _dir
	n.clock_override = CLOCK + seconds
	n.cmd_load("identity")
	var d := n.to_dict()
	d.erase("stances")
	d.erase("api_version")
	for b in d["big_undead"]:  # E3-3's key on each record (1 for every fixture's)
		b.erase("filled_slots")
	var evs: Array = n.catchup_events().filter(func(e): return e["type"] != "stance_fired")
	var away := n.view_away()
	away.erase("rev")
	return {"state": JSON.stringify(d).sha256_text(), "events": JSON.stringify(evs).sha256_text(),
		"away": JSON.stringify(away).sha256_text(), "steps": n._catchup.steps, "n_events": evs.size()}


## With no stance on, a 12 h catch-up from each fixture is bit-identical to the tip's (TIP): the state, the
## events and the away report hash the same. What differs: the stances block (each condition's active, its hold and
## fired_beat_id, now live) and the stance_fired events.
func _identity() -> void:
	var c := cfgs()
	for fx in GameState.FIXTURES:
		var h := identity(c, fx, 43200)
		t.ok(TIP.get(fx, {}) == h, "%s: with no stance on, 12 h caught up is bit-identical to the tip's (state, events less stance_fired, away report): %s" % [fx, str(h)])


## With stances on, catch-up matches live: pre_vei with Thrift and Muster on (Thrift acts from the first beat, its gold
## running short; Muster too, its workforce pinned with hands to spare), 30 min caught up at 10 s steps
## (idle.catchup_max_steps 180) against 30 min live at 0.5 s, by test_catchup's compare(): the stocks within
## idle.catchup_tol, the held forts, Covington's buildings with their states (Thrift's the same in both), the outcomes
## in order with flips and retakes within the time bound. pre_vei's mint is a step's own instant (its feed; 11.3% apart
## at 10 s with no stance on, IDLE §4), so its rates are judged against the same run with no stance on: no further from
## live than that, plus idle.catchup_tol.
func _catchup_10s() -> void:
	var c := cfgs({"economy.idle.catchup_max_steps": 180})
	var tol := float(c["economy"]["idle"]["catchup_tol"])
	var tc = load("res://tests/test_catchup.gd")
	var runs := {}
	for on in [[], ["thrift", "muster"]]:
		var s := GameState.new(c)
		s.debug_enabled = true
		s.save_dir = _dir
		s.cmd_debug_load_fixture("pre_vei")
		for id in on:
			s.cmd_set_stance(id, true)
		s.clock_override = CLOCK
		s.cmd_save("acc")
		var cu := GameState.new(c)
		cu.debug_enabled = true
		cu.save_dir = _dir
		cu.clock_override = CLOCK + 1800
		cu.cmd_load("acc")
		var live := GameState.new(c)
		live.debug_enabled = true
		live.save_dir = _dir
		live.clock_override = CLOCK
		live.cmd_load("acc")
		live.drain_events()
		live.tick(1800.0)
		var r: Dictionary = tc.compare(cu, cu.catchup_events(), live, live.drain_events(), tol)
		r["acting"] = [cu._stance_acting.keys(), live._stance_acting.keys(), cu.town_sim._lists()["thrift"], live.town_sim._lists()["thrift"]]
		runs[on.size()] = r
	var off: Dictionary = runs[0]
	var r: Dictionary = runs[2]
	var worse: Array = []
	for k in r["rates"]:
		if float(r["rates"][k]) > float(off["rates"][k]) + tol:
			worse.append(k)
	var stocks_ok := (r["stocks"] as Dictionary).values().all(func(e): return float(e) <= tol)
	var acting: Array = r["acting"]
	t.ok(stocks_ok and worse.is_empty() and r["town_same"] and (r["outcomes"] as Array).is_empty() and r["held"][0] == r["held"][1]
		and acting[0] == acting[1] and acting[2] == acting[3] and not (acting[2] as Array).is_empty() and (acting[0] as Array).has("muster"),
		"pre_vei, Thrift and Muster on, 30 min caught up at 10 s against live at 0.5 s: both acting %s, Thrift idling %s in both; %s (no stance on: %s)" % [
		str(acting[0]), str(acting[2]), r["lines"], off["lines"]])
