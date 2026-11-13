extends RefCounted
## GameState.load_configs: the one shared config loader (ConfigDb and the
## headless suites both use it).

## Per-process, so concurrent runs (other worktrees) cannot collide.
var TMP := "user://t02_cfg_%d" % OS.get_process_id()


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_rm_tree(path + "/" + sub)
	for fn in d.get_files():
		DirAccess.remove_absolute(path + "/" + fn)
	DirAccess.remove_absolute(path)


func run() -> int:
	var t := TestUtil.new()
	t.suite("game_state_configs")

	var real_errors: Array = []
	var cfg := GameState.load_configs("res://configs", real_errors)
	t.ok(real_errors.is_empty(), "res://configs loads with no duplicates or parse errors: %s" % [real_errors])
	for k in ["realm", "world", "raid", "town", "circle", "palette", "pulse"]:
		t.ok(cfg.has(k), "has key %s" % k)
		var direct = JSON.parse_string(FileAccess.get_file_as_string("res://configs/%s.json" % k))
		t.ok(cfg.get(k) == direct, "%s equals the file parsed directly" % k)
	var needed := {"realm": ["field", "relish"], "economy": ["sim", "opening"], "backups": ["phylactery", "vats", "backups"], "buildings": ["crypt"],
		"vei": ["fronts_required", "break_beats", "loss_backlog_keep"], "town": ["lots"], "raid": ["relish"],
		"world": ["size", "vei", "forts"], "pulse": ["tempo_ms"]}
	for fname in needed:
		t.ok(cfg.get(fname, null) is Dictionary and not cfg[fname].is_empty(), "config %s exists and is non-empty" % fname)
		for key in needed[fname]:
			t.ok(cfg.get(fname, {}).has(key), "config %s has key %s" % [fname, key])
	t.ok(cfg["realm"]["field"].has("slice_budget_cells"), "realm.field.slice_budget_cells present")
	# TownSim reads only these paths, with no numeric fallbacks, so each must be in the configs
	var missing: Array = []
	for path in TownSim.REQUIRED:
		var v: Variant = cfg
		for k in str(path).split("."):
			v = (v as Dictionary).get(k, null) if v is Dictionary else null
		if v == null:
			missing.append(path)
	t.ok(missing.is_empty() and TownSim.REQUIRED.size() > 30, "every TownSim.REQUIRED config path is present: missing %s" % [missing])
	var realm_direct: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://configs/realm.json"))
	var world_direct: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://configs/world.json"))
	t.near(float(cfg["realm"]["R_vei"]), float(realm_direct["R_vei"]), 0.0, "realm.R_vei matches")
	t.ok(cfg["world"]["forts"].size() == world_direct["forts"].size(), "world.forts.size() matches")

	t.ok(GameState.load_configs("res://no_such_dir_t02").is_empty(), "missing dir returns {}")

	# duplicates, parse errors, hidden dirs, sorted order (fixtures under user://)
	_rm_tree(TMP)
	_write(TMP + "/a/dup.json", '{"who": "a"}')
	_write(TMP + "/b/dup.json", '{"who": "b"}')
	_write(TMP + "/bad.json", "{not json")
	_write(TMP + "/.hidden/secret.json", '{"x": 1}')
	_write(TMP + "/ok.json", '{"v": 2}')
	var errs: Array = []
	var got := GameState.load_configs(TMP, errs)
	_rm_tree(TMP)
	t.ok(not DirAccess.dir_exists_absolute(TMP), "fixture dir fully removed (incl. dot-dirs)")
	t.ok(errs.size() == 2, "exactly two load errors reported, got %d: %s" % [errs.size(), errs])
	t.ok(errs.any(func(e): return "duplicate config 'dup'" in e and "/b/dup.json" in e), "duplicate reported, naming the ignored file")
	t.ok(errs.any(func(e): return "failed to parse" in e and "bad.json" in e), "bad JSON reported")
	t.ok(got.has("dup") and got["dup"]["who"] == "a", "duplicate basename keeps the first in sorted order")
	t.ok(not got.has("bad"), "unparseable file skipped")
	t.ok(not got.has("secret"), "dot-directories skipped (loader walks hidden entries, so only its guard skips them)")
	t.ok(got.has("ok") and int(got["ok"]["v"]) == 2, "sibling files still load")
	t.ok(got.size() == 2, "only dup and ok loaded")
	return t.failures
