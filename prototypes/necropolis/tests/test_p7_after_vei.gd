extends RefCounted
## P7, after Vei falls (briefs/p7-after-vei.md item 3): a save made after the win loads into the same end state.
## `won` itself round-trips in save_io; these checks pin what P7 reads from it after a load: the town's won head,
## step and next: line (TownGuide), and the map's end state at mount (the victory settles, the Vei card offers no
## BEGIN). A not-won save of the same game is the control: it loads into the realm's usual step.
## (Once economy's api-request #21 lands, view_vei().can_begin is false with reason "won" after the win; the card
## check below holds either way.)

var t: TestUtil
var cfg: Dictionary
var gcfg: Dictionary
var hcfg: Dictionary
var bview: Dictionary
var _dir := "user://test_p7_after_vei_%d" % OS.get_process_id()


func run() -> int:
	t = TestUtil.new()
	t.suite("p7-after-vei")
	cfg = TestUtil.configs()
	gcfg = cfg["town"]["view"]["guide"]
	hcfg = cfg["town"]["view"]["hud"]
	bview = cfg["buildings_view"]
	DirAccess.make_dir_recursive_absolute(_dir)
	_save_after_win()
	_clean()
	return t.failures


func _views(s: GameState) -> Dictionary:
	var forts: Array = []
	for f in s.view_realm().get("forts", []):
		forts.append({"id": String(f["id"]), "name": String(f["name"]), "held": bool(f["held"]),
			"flipped_count": int(f.get("flipped_count", 0)), "first_dungeon": bool(f.get("first_dungeon", false))})
	return {"town": s.view_town(), "forts": forts, "catalog": s.view_catalog(), "hud": s.view_hud(),
		"inventory": s.view_inventory()}


func _goal(s: GameState) -> Dictionary:
	return TownGuide.goal(_views(s), gcfg, hcfg, bview)


## pre_vei, the fight begun and won through apply_result (the router's path), saved, then loaded into a fresh state.
func _won_state() -> GameState:
	var s := GameState.new(cfg)
	s.debug_enabled = true
	s.save_dir = _dir
	t.ok(bool(s.cmd_debug_load_fixture("pre_vei").get("ok", false)), "(setup) pre_vei loads")
	var nb := s.cmd_begin_boss()
	t.ok(bool(nb.get("ok", false)), "(setup) the fight begins")
	var r := s.apply_result("boss", {"v": 2, "run_id": nb.get("run_id", -1), "seed_rev": nb.get("seed_rev", -1), "won": true,
		"fronts_cleared": [], "relish_deaths": 0, "backups_spent": {"phylactery": 0, "clones": 0}, "party_lost": [], "backlog_spent": 0.0})
	t.ok(bool(r.get("ok", false)) and bool(s.view_hud().get("won", false)), "(setup) the win is written back: %s" % str(r))
	s.drain_events()
	return s


func _load(slot: String) -> GameState:
	var n := GameState.new(cfg)
	n.debug_enabled = true
	n.save_dir = _dir
	var l := n.cmd_load(slot)
	t.ok(bool(l.get("ok", false)), "(setup) slot %s loads: %s" % [slot, str(l)])
	return n


func _save_after_win() -> void:
	var s := _won_state()
	var before := _goal(s)
	t.ok(bool(s.cmd_save("p7_won").get("ok", false)), "(setup) the won game saves")
	var n := _load("p7_won")
	t.ok(bool(n.view_hud().get("won", false)) and bool(n.view_vei().get("won", false)), "after the load the game is still won (view_hud and view_vei)")
	t.ok(String(n.view_relish().get("state", "")) == String(s.view_relish().get("state", "")) and int(n.view_relish().get("run_id", -1)) == -1,
		"after the load Relish is where the win left her (%s), with no run open" % String(n.view_relish().get("state", "")))
	# the town: the same won head, step and next: line before and after the load
	var after := _goal(n)
	t.ok(String(after.get("id", "")) == "won" and String(after["head"]) == String(gcfg["goal"]["won_head"])
		and String(after["text"]) == String(gcfg["goal"]["won"]) and String(after["short"]) == String(gcfg["goal"]["won_short"]),
		"the loaded town's plate and next: line are the won ones: '%s' / '%s' / '%s'" % [after.get("head", ""), after.get("text", ""), after.get("short", "")])
	t.ok(after == before, "the loaded town says what it said before the save")
	var nl := TownGuide.step(_views(n), gcfg, hcfg, bview)
	t.ok(String(nl["short"]) == String(gcfg["goal"]["won_short"]), "the top bar's next: line after the load: '%s'" % nl["short"])
	# the control: the same game saved before the win loads into the realm's usual step and head
	var c := GameState.new(cfg)
	c.debug_enabled = true
	c.save_dir = _dir
	c.cmd_debug_load_fixture("pre_vei")
	t.ok(bool(c.cmd_save("p7_not_won").get("ok", false)), "(setup) the same game, not won, saves")
	var cg := _goal(_load("p7_not_won"))
	t.ok(String(cg.get("id", "")) != "won" and String(cg.get("head", "")) == String(gcfg["goal"]["head"]),
		"the control: a save from before the win loads with the game's goal and its '%s' step" % cg.get("id", ""))


func _clean() -> void:
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)
