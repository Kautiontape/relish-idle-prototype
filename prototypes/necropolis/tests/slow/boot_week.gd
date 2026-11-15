extends RefCounted
## The shell's chunked boot after a week away, headless (E2b-2 T3.3c, the run's manager; IDLE §4, I5).
## The Game shell (autoload/game.gd) boots a normal launch with cmd_load("auto", true) and its autosave waits
## out a catch-up; nothing else drives that path headless: a headless launch is always a harness session
## (BootRule: no load), and under --script, where the suites run, game.gd doesn't compile (its _ready reads the
## ConfigDb autoload, which doesn't exist there). So this suite compiles the shell's own source with two
## substitutions, made by exact match and checked (the suite fails if the shell's text moves): ConfigDb.data
## becomes GameState.load_configs("res://configs") (the same loader ConfigDb uses), and the boot rule's
## harness decision becomes false (a normal launch). Everything else runs as shipped: _boot()'s normal branch
## (cmd_load("auto", true)), _process()'s frames (the tick at the frame's real time with the substep cap, the
## autosave clock that waits out a catch-up, the drained events re-emitted as game_event) and autosave().
## - The save: midgame_2flips with Relish in Greywall's dungeon and a checkpoint, saved as "auto" into this
##   suite's own user:// directory (never user://saves), the clock (clock_override) 7 days on at the boot.
## - It reaches a steady state: the run is over before the first chunk (its loot banked), the catch-up
##   finishes (view_catchup().active false, 604 800 s done), live substeps resume, the away report is shown;
##   the autosave, due during the catch-up, writes nothing until it is done and then saves.
## - During the catch-up a scene's commands (a valve set, a build, a move, a dungeon begin, the run commands)
##   get catching_up, or the dead-run refusal (no_run, duplicate_run) for the ended run, and nothing is
##   logged: the suite counts every error and script error the engine logs while it runs (a Logger), and
##   expects none.
## It prints the catch-up's frames and wall time (not asserted: the machine is shared).

var t := TestUtil.new()
const CLOCK := 1_800_000_000
const WEEK := 604800
const FRAME := 1.0 / 60.0
const CONFIG_REF := "ConfigDb.data"
const HARNESS_REF := "BootRule.is_harness(OS.get_cmdline_user_args(), OS.get_cmdline_args(), DisplayServer.get_name() == \"headless\")"


## Every error and script error the engine logs while the suite runs (warnings aside: the brief's check is 0
## SCRIPT ERROR and 0 ERROR lines).
class Errors extends Logger:
	var lines: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_ERROR or error_type == ERROR_TYPE_SCRIPT:
			lines.append("%d %s:%d %s %s %s" % [error_type, file, line, function, code, rationale])


const LOOT := {"relics": 1, "blueprints": [], "husks": [{"kind": "wraith"}], "remnants": [], "essence": 5}


func run() -> int:
	t.suite("boot-week")
	var errors := Errors.new()
	OS.add_logger(errors)
	var dir := "user://test_boot_week_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	_boot(dir, errors)
	OS.remove_logger(errors)
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(dir)
	return t.failures


## The shell's own source (autoload/game.gd) compiled with the two substitutions (see the header), or null.
func _shell_script() -> GDScript:
	var src := FileAccess.get_file_as_string("res://autoload/game.gd")
	# a substitution that doesn't match fails loudly and stops the suite: the unpatched shell must not run
	var subs := [["the config read (ConfigDb.data)", CONFIG_REF, "GameState.load_configs(\"res://configs\")"],
		["the harness decision (BootRule.is_harness(...))", HARNESS_REF, "false"]]
	for sb in subs:
		var hit := src.contains(sb[1])
		t.ok(hit, "the shell's source still has %s, which this suite substitutes" % sb[0])
		if not hit:
			push_error("boot_week: substitution not found in autoload/game.gd: %s; not running the unsubstituted shell" % sb[0])
			return null
	var gd := GDScript.new()
	gd.source_code = src.replace(CONFIG_REF, subs[0][2]).replace(HARNESS_REF, subs[1][2])
	var err := gd.reload()
	t.ok(err == OK, "the patched shell compiles (%d)" % err)
	return gd if err == OK else null


func _boot(dir: String, errors: Errors) -> void:
	var cfgs := GameState.load_configs("res://configs")
	# the save: midgame_2flips, Relish arrived at Greywall and in its dungeon with a checkpoint
	var s := GameState.new(cfgs)
	s.debug_enabled = true
	s.save_dir = dir
	s.cmd_debug_load_fixture("midgame_2flips")
	for i in 20:
		if s.relish["state"] != "travelling":
			break
		s.tick(0.5)
	var b := s.cmd_begin_dungeon("greywall")
	var run_id := int(b.get("run_id", -1))
	t.ok(b["ok"] and s.cmd_run_checkpoint(run_id, LOOT)["ok"], "(setup) a raid at Greywall with a checkpoint")
	var relics0 := s.relics
	var late := StateRuns.end_result(s.run, LOOT, "retreated")
	s.clock_override = CLOCK
	t.ok(s.cmd_save("auto")["ok"], "(setup) saved as auto in the suite's own directory")
	var gd := _shell_script()
	if gd == null:
		return
	var shell: Node = gd.new()
	var events: Array = []
	shell.game_event.connect(func(ev: Dictionary) -> void: events.append(ev))
	# _ready's steps, with the suite's configs and directory, then the boot itself
	shell.state.setup(cfgs)
	shell.state.debug_enabled = OS.is_debug_build()
	shell.state.save_dir = dir
	shell.state.clock_override = CLOCK + WEEK
	shell._boot()
	var st: GameState = shell.state
	t.ok(shell.autosave_enabled and st.catching_up() and st.view_catchup()["total_s"] == float(WEEK) and st.run.is_empty()
		and st.relics == relics0 + int(LOOT["relics"]) and st.view_relish()["state"] == "at_fort",
		"a normal launch: cmd_load(auto, true); the run ended before the first chunk (its loot banked), a week's catch-up pending")
	shell._autosave_acc = st.autosave_s() - 1.0  # the 30 s autosave comes due one real second into the catch-up
	var saved_at0 := int(TestUtil.load_json("%s/auto.json" % dir).get("saved_at", -1))
	var frames := 0
	var probed := false
	var probe: Array = []
	var saved_during := false
	var t_wall := Time.get_ticks_usec()
	while st.catching_up() and frames < 20000:
		shell._process(FRAME)
		frames += 1
		if st.catching_up() and (events.any(func(e): return e["type"] == "autosaved")
				or (frames % 200 == 0 and int(TestUtil.load_json("%s/auto.json" % dir).get("saved_at", -1)) != saved_at0)):
			saved_during = true  # (the frame that finishes the catch-up may save at once: that is after it)
		if frames == 120 and st.catching_up():
			probed = true
			var rv := st.rev
			probe = [
				st.cmd_set_valve(1.0, 1.0, 1.0)["reason"], st.cmd_build("house", "lot-08")["reason"],
				st.cmd_move_relish("covington")["reason"], st.cmd_begin_dungeon("greywall")["reason"],
				st.cmd_run_checkpoint(run_id, LOOT)["reason"], st.cmd_abort_dungeon()["reason"], st.apply_result("raid", late)["reason"],
				shell.autosave()["reason"],
			]
			t.ok(st.rev == rv, "the refused commands left rev alone")
	var wall := float(Time.get_ticks_usec() - t_wall) / 1e6
	var done := st.view_catchup()
	t.ok(probed and probe == ["catching_up", "catching_up", "catching_up", "catching_up", "no_run", "no_run", "duplicate_run", "catching_up"],
		"during the catch-up a scene's commands get catching_up, the ended run's no_run / duplicate_run, the autosave catching_up: %s" % str(probe))
	t.ok(not st.catching_up() and not done["active"] and done["done_s"] == float(WEEK) and frames > 100,
		"the catch-up finished: %s after %d frames" % [str(done), frames])
	t.ok(not saved_during, "the autosave, due one real second in, wrote nothing while the catch-up ran (no autosaved, auto.json still the save's)")
	var t0 := st.t
	for i in 120:
		shell._process(FRAME)
	var autos := events.filter(func(e): return e["type"] == "autosaved")
	t.ok(st.t >= t0 + 1.5 and not st.catching_up(), "live substeps resumed: %.2f s of sim in 2 s of frames" % (st.t - t0))
	t.ok(autos.size() == 1 and int(TestUtil.load_json("%s/auto.json" % dir).get("saved_at", -1)) == CLOCK + WEEK,
		"then the autosave saved, once, stamped at the boot's now")
	var reports := events.filter(func(e): return e["type"] == "away_report")
	t.ok(reports.size() == 1 and reports[0]["away_s"] == float(WEEK) and st.view_away()["shown"], "one away_report; view_away shown")
	t.ok(events.any(func(e): return e["type"] == "loot_banked") and events[0]["type"] == "loot_banked", "the run's loot_banked reached the scenes first")
	print("  [boot-week] a week caught up in %d frames, %.2f s of wall time (not asserted: the machine is shared)" % [frames, wall])
	print("  [boot-week] the report: %s" % JSON.stringify(st.view_away()))
	t.ok(errors.lines.is_empty(), "no error logged during the boot (%d): %s" % [errors.lines.size(), str(errors.lines.slice(0, 5))])
	shell.free()
