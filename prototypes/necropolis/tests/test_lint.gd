extends RefCounted
## Autoload lint (MECHANICS 1.1): sim and logic files must stay testable without
## autoloads, so they may never reference any autoload (derived from
## project.godot) or Engine.
## Scanned: res://scripts/sim/*.gd, every *_logic.gd under res://scripts/, and any
## vei_fronts.gd / slab_logic.gd under res://scripts/ (they may not exist yet).

const ROOT := "res://scripts"

static var _re: RegEx
static var _names: Array[String] = []


## Every autoload registered in project.godot, plus Engine.
static func forbidden_names() -> Array[String]:
	if _names.is_empty():
		for prop in ProjectSettings.get_property_list():
			var n: String = prop["name"]
			if n.begins_with("autoload/"):
				_names.append(n.trim_prefix("autoload/"))
		_names.append("Engine")
	return _names


## True if a script in `dir` is subject to the lint by directory alone.
static func is_sim_dir(dir: String) -> bool:
	return dir == ROOT + "/sim" or dir.begins_with(ROOT + "/sim/")


## Returns the code part of a line: the # comment is removed and the contents of
## "..." / '...' literals are blanked, so neither can trigger the detector.
static func strip_comment(line: String) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				i += 1
			elif c == quote:
				quote = ""
				out += c
		elif c == "\"" or c == "'":
			quote = c
			out += c
		elif c == "#":
			break
		else:
			out += c
		i += 1
	return out


## True if the line references any autoload or Engine.
static func has_autoload_ref(line: String) -> bool:
	if _re == null:
		_re = RegEx.new()
		_re.compile("\\b(%s)\\s*\\." % "|".join(forbidden_names()))
	return _re.search(strip_comment(line)) != null


func _files() -> Array[String]:
	var out: Array[String] = []
	_collect(ROOT, out)
	out.sort()
	return out


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		if is_sim_dir(dir) or f.ends_with("_logic.gd") \
				or f == "vei_fronts.gd" or f == "slab_logic.gd":
			out.append("%s/%s" % [dir, f])
	for d in DirAccess.get_directories_at(dir):
		_collect("%s/%s" % [dir, d], out)


func run() -> int:
	var t := TestUtil.new()
	t.suite("lint")

	# --- detector self-check -------------------------------------------------
	for n in ["Game", "ConfigDb", "Pulse", "Shot", "Engine"]:
		t.ok(forbidden_names().has(n), "forbidden names include %s" % n)
	for d in [ROOT + "/sim", ROOT + "/sim/sub"]:
		t.ok(is_sim_dir(d), "is_sim_dir accepts %s" % d)
	for d in [ROOT + "/simulacra", ROOT + "/simulacra/sim", ROOT, ROOT + "/si"]:
		t.ok(not is_sim_dir(d), "is_sim_dir rejects %s" % d)
	for s in ["Game.realm", "Pulse.wave()", "Shot.x", "ConfigDb.v(\"x\")", "Engine.time_scale = 1.0", "x = Game .state"]:
		t.ok(has_autoload_ref(s), "detector flags: %s" % s)
	for s in ["GameState.load_configs(d)", "var game_cfg := 1", "# Game.realm in a comment",
			"print(\"Engine.time_scale\")", "## doc about Game.state", "EngineThing.x()"]:
		t.ok(not has_autoload_ref(s), "detector ignores: %s" % s)

	# --- scan ----------------------------------------------------------------
	var files := _files()
	t.ok(files.size() > 0, "lint scans at least one file")
	for p in files:
		var n := 0
		for line in FileAccess.get_file_as_string(p).split("\n"):
			n += 1
			if has_autoload_ref(line):
				t.ok(false, "%s:%d: %s" % [p, n, line.strip_edges()])
	if t.failures == 0:
		t.ok(true, "no autoload references in %d sim/logic files" % files.size())
	return t.failures
