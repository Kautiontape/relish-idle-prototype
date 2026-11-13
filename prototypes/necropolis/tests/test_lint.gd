extends RefCounted
## Autoload lint (MECHANICS 1.1): sim and logic files must stay testable without
## autoloads, so they may never reference Game, ConfigDb or Engine.
## Scanned: res://scripts/sim/*.gd, every *_logic.gd under res://scripts/, and any
## vei_fronts.gd / slab_logic.gd under res://scripts/ (they may not exist yet).

const ROOT := "res://scripts"

static var _re: RegEx


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


## True if the line references the Game, ConfigDb or Engine autoload.
static func has_autoload_ref(line: String) -> bool:
	if _re == null:
		_re = RegEx.new()
		_re.compile("\\b(Game|ConfigDb|Engine)\\s*\\.")
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
		if dir.begins_with(ROOT + "/sim") or f.ends_with("_logic.gd") \
				or f == "vei_fronts.gd" or f == "slab_logic.gd":
			out.append("%s/%s" % [dir, f])
	for d in DirAccess.get_directories_at(dir):
		_collect("%s/%s" % [dir, d], out)


func run() -> int:
	var t := TestUtil.new()
	t.suite("lint")

	# --- detector self-check -------------------------------------------------
	for s in ["Game.realm", "ConfigDb.v(\"x\")", "Engine.time_scale = 1.0", "x = Game .state"]:
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
