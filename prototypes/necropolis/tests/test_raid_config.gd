extends RefCounted
## Config health (dungeon-i M2, after 7b0a47e). Every res://configs JSON parses to a Dictionary, and raid.json's
## words are there and non-empty. A raid.json that fails to parse does not crash the game: ConfigDb keeps {} for
## it and every word the raid reads with a "" fallback draws blank (7b0a47e's bare quote in a _doc did that). This
## suite fails once, naming the file, line and message, and it runs in seconds: `tests/run.sh --only=raid_config`.
## When raid text moves into raid.json, add its path to WORDS (and to FORMATS when the code formats it).

const CONFIG_DIR := "res://configs"

## The raid.json words the raid code reads with a blank or wrong fallback, so a deleted or renamed key fails here.
const WORDS := [
	"death.title", "death.sub", "death.foot", "death.after_clone", "death.after_unmade", "death.after_in", "death.after_shock",
	"gap_end.banner_text", "gap_end.banner_text_boss",
	"hud.stats.ward_head", "hud.stats.living_label", "hud.stats.enemy", "hud.stats.enemies",
	"hud.legend.assist_label", "hud.legend.assist_off", "hud.legend.assist_on",
	"hud.retreat.keep_prefix", "hud.retreat.head_keep", "hud.retreat.head_fall", "hud.retreat.keep_all", "hud.retreat.keep_none",
	"hud.retreat.fort_yours", "hud.retreat.fort_vei", "hud.retreat.fall_revive",
	"hud.hint.trance_text", "hud.hint.exit_text", "hud.hint.idle_text", "hud.hint.idle_sub_text",
	"hud.cues.first_mote_text", "hud.cues.undead_text",
	"hud.stats.essence_meaning", "hud.stats.phyl_none", "hud.stats.phyl_meaning_charged", "hud.stats.phyl_meaning_none_1",
	"hud.stats.phyl_meaning_none_2", "hud.stats.key_pile",
	"hud.goal.goal_break", "hud.goal.goal_held", "hud.goal.chest_row", "hud.goal.no_army", "hud.goal.no_army_short",
	"hud.goal.route_here", "hud.goal.route_ahead_one", "hud.goal.route_ahead_many", "hud.goal.route_next_door", "hud.goal.route_room",
	"hud.goal.rooms_seen", "hud.goal.push_living", "hud.goal.push_at_exit", "hud.goal.push_exit", "hud.goal.push_exit_next",
	"hud.goal.push_exit_rooms", "hud.goal.risk_none", "hud.goal.risk_some",
	"held.banner_text", "held.banner_holds", "held.payoff", "held.payoff_husk", "held.map_effect",
	"death.label_killed_by", "death.label_missed", "death.label_banked", "death.label_lost", "death.label_after", "death.label_shut",
	"death.cause_unnamed", "death.cause_slam", "death.cause_toll", "death.cause_lunge", "death.cause_bash", "death.cause_rush",
	"death.cause_fire", "death.cause_hound", "death.cause_pack", "death.cause_living", "death.cause_wound",
	"death.tell_slam", "death.tell_toll", "death.tell_lunge", "death.tell_arc", "death.tell_fire",
	"death.killed_missed", "death.nothing", "death.lost_bigs", "death.shut_text",
	"clear.title", "clear.label_broken", "clear.label_taken", "clear.label_loot", "clear.label_use", "clear.label_next",
	"clear.taken_text", "clear.loot_none", "clear.next_text",
	"loot_uses.relics", "loot_uses.husk", "loot_uses.remnants", "loot_uses.essence",
	"held_door.entry", "held_door.prompt", "held_door.label_held", "held_door.label_sent", "held_door.label_shut", "held_door.label_freed",
	"held_door.row_held", "held_door.row_shut", "held_door.retreat_sent", "held_door.retreat_held", "held_door.retreat_shut",
	"vei_loss.banner.fronts_held", "vei_loss.banner.horde_ferried", "vei_loss.banner.relish_unmade", "vei_loss.banner_unknown",
	"vei_loss.ended.fronts_held", "vei_loss.ended.horde_ferried", "vei_loss.ended.relish_unmade", "vei_loss.ended_unknown",
	"vei_loss.killed_by_label", "vei_loss.killed_by.weave", "vei_loss.killed_by.living", "vei_loss.killed_by.other",
	"vei_loss.break_label", "vei_loss.break_text", "vei_loss.fronts_label", "vei_loss.fronts_text", "vei_loss.held_clause",
	"vei_loss.pressure_label", "vei_loss.pressure_text", "vei_loss.reserve", "vei_loss.tag",
	"wardens.last_chance", "wardens.last_chance_loose", "wardens.meter_label",
]

## The words the code formats, with the placeholders each must keep ("%d" words go through `%`, which throws without one).
const FORMATS := {
	"hud.stats.enemy": ["%d"], "hud.stats.enemies": ["%d"], "wardens.last_chance_loose": ["%d"],
	"vei_loss.break_text": ["{best}", "{need}"], "vei_loss.fronts_text": ["{fell}", "{total}", "{need}"],
	"vei_loss.held_clause": ["{held}"], "vei_loss.pressure_text": ["{mult}", "{pool}", "{reserve}"], "vei_loss.tag": ["{mult}"],
	"hud.goal.goal_break": ["%s", "%s"], "hud.goal.route_ahead_one": ["%d", "%s"], "hud.goal.route_ahead_many": ["%d", "%s"],
	"hud.goal.route_next_door": ["%s"], "hud.goal.route_room": ["%d", "%d", "%s"], "hud.goal.rooms_seen": ["%d", "%d"],
	"hud.goal.push_living": ["%d"], "hud.goal.push_exit": ["%s"], "hud.goal.push_exit_next": ["%s"], "hud.goal.push_exit_rooms": ["%s", "%d"],
	"hud.goal.risk_some": ["%s"],
	"held.banner_holds": ["%s"], "held.payoff": ["%d", "%d", "%d"], "held.payoff_husk": ["%d"], "held.map_effect": ["%d"],
	"death.cause_slam": ["%s"], "death.cause_toll": ["%s"], "death.cause_lunge": ["%s"], "death.cause_bash": ["%s"], "death.cause_rush": ["%s"],
	"death.cause_fire": ["%s"], "death.cause_hound": ["%s"], "death.cause_pack": ["%s"],
	"death.killed_missed": ["%s", "%s"], "death.lost_bigs": ["%d"], "death.shut_text": ["%s"],
	"clear.title": ["%s"],
	"held_door.label_held": ["%s"], "held_door.label_sent": ["%s"], "held_door.label_shut": ["%s"], "held_door.label_freed": ["%s"],
	"held_door.row_held": ["%s"], "held_door.row_shut": ["%s"],
	"held_door.retreat_sent": ["%s"], "held_door.retreat_held": ["%s"], "held_door.retreat_shut": ["%s"],
}


func run() -> int:
	var t := TestUtil.new()
	t.suite("raid_config")
	_parse_tests(t)
	_word_tests(t)
	_proof_tests(t)
	return t.failures


## Every JSON under res://configs, sorted, skipping dot entries (as GameState.load_configs walks them).
func _json_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files := Array(d.get_files())
	files.sort()
	for f: String in files:
		if not f.begins_with(".") and f.ends_with(".json"):
			out.append(dir.path_join(f))
	var subs := Array(d.get_directories())
	subs.sort()
	for s: String in subs:
		if not s.begins_with("."):
			out.append_array(_json_files(dir.path_join(s)))
	return out


## "" when `text` parses to a Dictionary; else the line (1-based, as an editor counts; Godot's is 0-based) and the
## parser's message.
static func _parse_problem(text: String) -> String:
	var j := JSON.new()
	if j.parse(text) != OK:
		return "line %d: %s" % [j.get_error_line() + 1, j.get_error_message()]
	if not (j.data is Dictionary):
		return "the top level is not an object"
	return ""


static func _dig(d: Dictionary, path: String) -> Variant:
	var v: Variant = d
	for k in path.split("."):
		if not (v is Dictionary) or not (v as Dictionary).has(k):
			return null
		v = (v as Dictionary)[k]
	return v


## Every String leaf that is empty, by dotted path; `_doc*` keys are notes, not words, so they are skipped.
static func _blank_strings(v: Variant, path: String, out: Array) -> void:
	if v is Dictionary:
		for k in v:
			if not str(k).begins_with("_doc"):
				_blank_strings(v[k], (path + "." if path != "" else "") + str(k), out)
	elif v is Array:
		for i in (v as Array).size():
			_blank_strings(v[i], "%s.%d" % [path, i], out)
	elif v is String and (v as String) == "":
		out.append(path)


## What is wrong with raid.json's words, one string per problem (empty when they are all there).
static func _word_problems(raid: Dictionary) -> Array:
	var out: Array = []
	for p in WORDS:
		var v: Variant = _dig(raid, p)
		if not (v is String) or (v as String) == "":
			out.append("%s is missing or blank" % p)
	for p in FORMATS:
		var v: Variant = _dig(raid, p)
		for ph in FORMATS[p]:
			if v is String and not (v as String).contains(ph):
				out.append("%s lost its %s" % [p, ph])
	# each warden a fort names has its tells: warden.gd's WAKES banner reads the first
	var arches: Variant = _dig(raid, "wardens.archetypes")
	var by_fort: Variant = _dig(raid, "wardens.by_fort")
	var ids: Array = []
	if by_fort is Dictionary:
		for f in by_fort:
			if not ids.has(str(by_fort[f])):
				ids.append(str(by_fort[f]))
	if ids.is_empty():
		out.append("wardens.by_fort names no warden")
	for id in ids:
		var tells: Variant = _dig(arches, id + ".tells") if arches is Dictionary else null
		if not (tells is Array) or (tells as Array).is_empty():
			out.append("wardens.archetypes.%s.tells is missing or empty" % id)
	var blanks: Array = []
	_blank_strings(raid, "", blanks)
	for p in blanks:
		out.append("%s is blank" % p)
	return out


func _parse_tests(t: TestUtil) -> void:
	var files := _json_files(CONFIG_DIR)
	t.ok(files.size() >= 15 and files.has(CONFIG_DIR.path_join("raid.json")), "the configs are found, raid.json among them (%d files)" % files.size())
	for p in files:
		var problem := _parse_problem(FileAccess.get_file_as_string(p))
		t.ok(problem == "", "%s parses to a Dictionary%s" % [p, "" if problem == "" else ": " + problem])


func _word_tests(t: TestUtil) -> void:
	var raid: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_DIR.path_join("raid.json")))
	var problems := _word_problems(raid if raid is Dictionary else {})
	t.ok(problems.is_empty(), "raid.json's words are all there and none is blank: %s" % [problems])


## The checks catch what they are for: each break below must be reported.
func _proof_tests(t: TestUtil) -> void:
	# 7b0a47e's break: bare double quotes inside a _doc string
	var bad := "{\n\t\"vei_loss\": {\n\t\t\"_doc\": \"the ruled words \"living in her reserve\" go here\",\n\t\t\"tag\": \"x\"\n\t}\n}\n"
	var pp := _parse_problem(bad)
	t.ok(pp.begins_with("line 3:"), "a bare quote inside a _doc fails the parse, with its line: " + pp)
	t.ok(_parse_problem("") != "" and _parse_problem("[1, 2]") != "", "an empty file and a top-level array are reported")
	t.ok(_parse_problem("{\"a\": {\"_doc\": \"single 'quotes' are fine\"}}") == "", "single quotes inside a _doc parse")

	var real: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_DIR.path_join("raid.json")))
	if not (real is Dictionary):
		t.ok(false, "raid.json parses, so the word proofs can run")
		return
	var blanked: Dictionary = (real as Dictionary).duplicate(true)
	blanked["death"]["title"] = ""
	t.ok(_word_problems(blanked).has("death.title is missing or blank"), "a blank death.title is reported")
	var renamed: Dictionary = (real as Dictionary).duplicate(true)
	renamed["vei_loss"].erase("tag")
	t.ok(_word_problems(renamed).has("vei_loss.tag is missing or blank"), "a deleted (or renamed) vei_loss.tag is reported")
	t.ok(_word_problems({}).has("death.title is missing or blank"), "raid.json parsed as {} (ConfigDb after a parse failure) fails every word")
	var unformatted: Dictionary = (real as Dictionary).duplicate(true)
	unformatted["hud"]["stats"]["enemies"] = "enemies"
	t.ok(_word_problems(unformatted).has("hud.stats.enemies lost its %d"), "a formatted word without its %d is reported")
	var tell_less: Dictionary = (real as Dictionary).duplicate(true)
	tell_less["wardens"]["archetypes"]["huntsman"]["tells"] = []
	t.ok(_word_problems(tell_less).has("wardens.archetypes.huntsman.tells is missing or empty"), "a warden with no tells is reported")
	var stray: Dictionary = (real as Dictionary).duplicate(true)
	stray["demo"]["loot_hint"] = ""
	stray["held_door"]["_doc_geometry"] = ""
	var sp := _word_problems(stray)
	t.ok(sp.has("demo.loot_hint is blank") and sp.size() == 1, "a blank word outside WORDS is reported, and a blank _doc is not: %s" % [sp])
