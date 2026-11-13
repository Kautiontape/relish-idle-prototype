extends RefCounted
## GameState.load_configs: the one shared config loader (ConfigDb and the
## headless suites both use it).

const TMP := "user://t02_cfg"


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_rm_tree(path + "/" + sub)
	for fn in d.get_files():
		DirAccess.remove_absolute(path + "/" + fn)
	DirAccess.remove_absolute(path)


func run() -> int:
	var t := TestUtil.new()
	t.suite("game_state_configs")

	var cfg := GameState.load_configs("res://configs")
	for k in ["realm", "world", "raid", "town", "circle", "palette", "pulse"]:
		t.ok(cfg.has(k), "has key %s" % k)
		var direct = JSON.parse_string(FileAccess.get_file_as_string("res://configs/%s.json" % k))
		t.ok(cfg.get(k) == direct, "%s equals the file parsed directly" % k)
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
	var got := GameState.load_configs(TMP)
	_rm_tree(TMP)
	t.ok(got.has("dup") and got["dup"]["who"] == "a", "duplicate basename keeps the first in sorted order")
	t.ok(not got.has("bad"), "unparseable file skipped")
	t.ok(not got.has("secret"), "dot-directories skipped")
	t.ok(got.has("ok") and int(got["ok"]["v"]) == 2, "sibling files still load")
	t.ok(got.size() == 2, "only dup and ok loaded")
	return t.failures
