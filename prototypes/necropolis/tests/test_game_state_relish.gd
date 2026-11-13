extends RefCounted
## GameState: Relish's travel (STATE-API 4.2, 5.8), the legacy realm mirror and the
## legacy teleport. Headless, no autoloads.

const COV := Vector2(1780, 1270)
const SLUICE := Vector2(1420, 1305)


func _mk() -> GameState:
	var s := GameState.new(TestUtil.configs())
	s.cmd_new_game(1)
	s.debug_enabled = true
	return s


func run() -> int:
	var t := TestUtil.new()
	t.suite("game-state-relish")

	# --- start state and view keys ---
	var s := _mk()
	var v := s.view_relish()
	var keys := ["rev", "state", "at", "target", "pos", "heading", "speed", "eta_s", "dead_s_left",
		"respawn_with_clone", "phylactery_charges", "clones_ready", "can_descend", "reason", "run_id",
		"run_kind", "effects"]
	t.ok(v.size() == keys.size() and keys.all(func(k): return v.has(k)), "view_relish has exactly the contract keys")
	t.ok(v["state"] == "home" and v["at"] == "covington" and v["target"] == "", "starts home at covington")
	t.ok(v["pos"] == [1780.0, 1270.0] and v["pos"][0] is float, "pos is Covington's, as floats")
	t.ok(v["heading"] == 0.0 and v["speed"] == 0.0 and v["eta_s"] == -1.0, "heading 0, speed 0, eta -1")
	t.ok(v["can_descend"] == false and v["reason"] == "not_at_fort", "home cannot descend")
	t.ok(v["run_id"] == -1 and v["run_kind"] == "" and v["clones_ready"] == 0 and v["phylactery_charges"] == 0, "no run")
	t.ok(v["effects"] == {"tide_fort": "", "redirect_fort": "", "home": true}, "effects: home only")
	s.town["vats"] = 2
	t.ok(s.view_relish()["clones_ready"] == 2, "clones_ready is the legacy vat count")
	s.town["vats"] = 0

	# --- travel ETA and arrival ---
	var eta := COV.distance_to(SLUICE) / 220.0
	var rv := s.rev
	var r := s.cmd_move_relish("old-sluice")
	t.ok(r["ok"] and r["reason"] == "" and absf(r["eta_s"] - eta) < 1e-3, "move_relish returns the ETA (%.3f)" % r["eta_s"])
	t.ok(s.rev == rv + 1, "a successful command bumps rev")
	v = s.view_relish()
	t.ok(v["state"] == "travelling" and v["target"] == "old-sluice" and v["at"] == "covington", "travelling, at = where she left")
	t.ok(v["speed"] == 220.0 and absf(v["eta_s"] - eta) < 1e-3, "speed 220, eta set")
	t.ok(absf(v["heading"] - atan2(35.0, -360.0)) < 1e-6, "heading points at the target")
	s.tick(1.0)
	v = s.view_relish()
	t.ok(absf(Vector2(v["pos"][0], v["pos"][1]).distance_to(COV) - 220.0) < 1e-3, "220 px after one second")
	t.ok(absf(v["eta_s"] - (eta - 1.0)) < 1e-3, "eta counts down")
	t.ok(s.realm.relish["state"] == "idle" and s.realm.relish["at"] == "covington", "legacy channel idle while travelling")
	s.tick(2.0)
	v = s.view_relish()
	t.ok(v["state"] == "at_fort" and v["at"] == "old-sluice" and v["target"] == "", "arrival at a fort: at_fort")
	t.ok(v["pos"] == [1420.0, 1305.0] and v["speed"] == 0.0 and v["eta_s"] == -1.0, "stands exactly on the node")
	t.ok(v["can_descend"] == true and v["reason"] == "", "can descend at a fort")
	t.ok(s.realm.relish["state"] == "idle" and s.realm.relish["at"] == "old-sluice", "legacy channel idle at the fort")
	var h: float = v["heading"]
	s.tick(5.0)
	t.ok(s.view_relish()["heading"] == h, "she keeps her last heading when stopped")

	# no-op moves
	rv = s.rev
	r = s.cmd_move_relish("old-sluice")
	t.ok(r["ok"] and r["eta_s"] == 0.0 and s.view_relish()["state"] == "at_fort", "move to where she stands: no-op ok, eta 0")
	r = s.cmd_move_relish("covington")
	t.ok(r["ok"] and r["eta_s"] > 1.0, "move home")
	var r2 := s.cmd_move_relish("covington")
	t.ok(r2["ok"] and absf(r2["eta_s"] - r["eta_s"]) < 1e-9 and s.view_relish()["target"] == "covington",
		"moving to the current target is a no-op ok")
	s.tick(10.0)
	t.ok(s.view_relish()["state"] == "home" and s.realm.relish["state"] == "raising" and s.realm.relish["at"] == "covington",
		"arrival at Covington: home, legacy raising restored")

	# vei
	r = s.cmd_move_relish("vei")
	t.ok(r["ok"], "move to vei")
	s.tick(r["eta_s"] + 1.0)
	t.ok(s.view_relish()["state"] == "at_vei" and s.view_relish()["at"] == "vei", "arrival at Vei: at_vei")
	t.ok(s.view_relish()["reason"] == "not_at_fort" and s.view_relish()["can_descend"] == false, "Vei is not a fort")

	# --- retarget mid-travel starts from pos ---
	s = _mk()
	s.cmd_move_relish("old-sluice")
	s.tick(1.0)
	var pos: Array = s.view_relish()["pos"]
	r = s.cmd_move_relish("ashgate")
	var ash := Vector2(1560, 1160)
	t.ok(r["ok"] and absf(r["eta_s"] - Vector2(pos[0], pos[1]).distance_to(ash) / 220.0) < 1e-3, "retarget eta from the current pos")
	t.ok(s.view_relish()["pos"] == pos and s.view_relish()["at"] == "covington", "retarget keeps pos and at")
	s.tick(r["eta_s"] + 0.5)
	t.ok(s.view_relish()["state"] == "at_fort" and s.view_relish()["at"] == "ashgate", "arrives at the new target")

	# --- cancel ---
	s = _mk()
	t.ok(s.cmd_cancel_travel() == {"ok": false, "reason": "not_travelling", "eta_s": 0.0}, "cancel when still: not_travelling")
	s.cmd_move_relish("old-sluice")
	rv = s.rev
	s.tick(1.0)
	r = s.cmd_cancel_travel()
	t.ok(r["ok"] and absf(r["eta_s"] - 1.0) < 1e-3, "cancel turns back: 220 px out is 1.0 s home")
	t.ok(s.view_relish()["target"] == "covington" and s.view_relish()["at"] == "covington", "retargeted to at")
	r2 = s.cmd_cancel_travel()
	t.ok(r2["ok"] and absf(r2["eta_s"] - r["eta_s"]) < 1e-9, "cancel again: no-op ok")
	s.tick(1.5)
	t.ok(s.view_relish()["state"] == "home" and s.realm.relish["state"] == "raising", "cancelled trip ends home")
	# cancel from a leg that left a fort
	s = _mk()
	s.legacy_teleport_relish("old-sluice")
	s.cmd_move_relish("ashgate")
	s.tick(0.5)
	s.cmd_cancel_travel()
	s.tick(10.0)
	t.ok(s.view_relish()["state"] == "at_fort" and s.view_relish()["at"] == "old-sluice", "cancel returns to the fort she left")

	# --- refusals ---
	s = _mk()
	rv = s.rev
	r = s.cmd_move_relish("nowhere")
	t.ok(r == {"ok": false, "reason": "unknown_node", "eta_s": 0.0} and s.rev == rv, "unknown_node, rev untouched")
	t.ok(s.cmd_move_relish("")["reason"] == "unknown_node", "empty id is unknown")
	var vid: String = TestUtil.configs()["world"]["towns"][0]["id"]
	t.ok(s.cmd_move_relish(vid)["reason"] == "unknown_node", "village ids are unknown nodes")
	s.relish["state"] = "dead"
	t.ok(s.cmd_move_relish("nowhere")["reason"] == "dead", "dead is checked before unknown_node")
	t.ok(s.legacy_teleport_relish("old-sluice")["reason"] == "dead", "teleport refuses when dead")
	s.relish["state"] = "home"
	s.legacy_teleport_relish("old-sluice")
	var b := s.cmd_begin_dungeon("old-sluice")
	t.ok(b["ok"], "begin dungeon")
	t.ok(s.cmd_move_relish("covington")["reason"] == "in_dungeon", "in_dungeon refuses a move")
	t.ok(s.legacy_teleport_relish("covington")["reason"] == "in_dungeon", "teleport refuses in a dungeon")
	t.ok(s.realm.raiding == true and s.realm.relish["state"] == "idle", "realm.raiding while a run is open")
	s.cmd_abort_dungeon()
	t.ok(s.realm.raiding == false, "realm.raiding clears when the run closes")
	s.legacy_teleport_relish("vei")
	s.cmd_begin_boss()
	t.ok(s.cmd_move_relish("covington")["reason"] == "in_boss", "in_boss refuses a move")
	t.ok(s.cmd_cancel_travel()["reason"] == "not_travelling", "cancel in a boss run: not_travelling")

	# --- legacy_teleport_relish ---
	s = _mk()
	s.cmd_move_relish("ashgate")
	s.tick(0.5)
	rv = s.rev
	r = s.legacy_teleport_relish("old-sluice")
	v = s.view_relish()
	t.ok(r == {"ok": true, "reason": ""} and s.rev == rv + 1, "teleport ok, bumps rev")
	t.ok(v["state"] == "at_fort" and v["at"] == "old-sluice" and v["target"] == "" and v["pos"] == [1420.0, 1305.0],
		"teleport puts her at the fort, standing")
	t.ok(s.realm.relish["at"] == "old-sluice" and s.realm.relish["state"] == "idle", "teleport mirrors to the realm")
	s.legacy_teleport_relish("vei")
	t.ok(s.view_relish()["state"] == "at_vei", "teleport to vei: at_vei")
	s.legacy_teleport_relish("covington")
	t.ok(s.view_relish()["state"] == "home" and s.realm.relish["state"] == "raising", "teleport home: home, raising")
	t.ok(s.legacy_teleport_relish("zzz")["reason"] == "unknown_node", "teleport: unknown_node")

	# --- legacy raid flag still feeds realm.raiding ---
	s = _mk()
	s.begin_raid("old-sluice")
	t.ok(s.realm.raiding and s.raiding_fort_id() == "old-sluice", "legacy begin_raid still flags the realm")
	s.end_raid()
	t.ok(not s.realm.raiding and s.raiding_fort_id() == "", "legacy end_raid clears it")

	# --- staying home leaves the legacy mint untouched; leaving stops the home mint ---
	var home := _mk()
	var away := _mk()
	away.cmd_move_relish("old-sluice")
	home.tick(60.0)
	away.tick(60.0)
	t.ok(home.realm.cov["r_out"] > away.realm.cov["r_out"], "the home mint (P_relish) stops while she is away")

	# --- paused sim: travel holds ---
	s = _mk()
	s.cmd_move_relish("old-sluice")
	s.cmd_pause(true)
	t.ok(s.tick(5.0) == 0 and s.view_relish()["state"] == "travelling", "no travel while paused")
	return t.failures
