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
	"hud.hint.trance_text", "hud.hint.exit_text", "hud.hint.idle_text", "hud.hint.idle_sub_text", "hud.hint.trance_sub_text",
	"trace_notch.live_head", "trace_notch.live_head_keep", "trace_notch.live_tail", "trace_notch.live_ladder", "trace_notch.live_none",
	"hud.cues.first_mote_text", "hud.cues.undead_text",
	"hud.stats.essence_meaning", "hud.stats.phyl_none", "hud.stats.phyl_meaning_charged", "hud.stats.phyl_meaning_none_1",
	"hud.stats.phyl_meaning_none_2", "hud.stats.key_pile",
	"hud.goal.goal_break", "hud.goal.goal_held", "hud.goal.chest_row", "hud.goal.no_army", "hud.goal.no_army_short",
	"hud.goal.route_here", "hud.goal.route_ahead_one", "hud.goal.route_ahead_many", "hud.goal.route_next_door", "hud.goal.route_room",
	"hud.goal.rooms_seen", "hud.goal.push_living", "hud.goal.push_at_exit", "hud.goal.push_exit", "hud.goal.push_exit_next",
	"hud.goal.push_exit_rooms", "hud.goal.risk_none", "hud.goal.risk_some", "hud.goal.risk_essence",
	"death.wait_s", "death.wait_min", "death.wait_min_s",
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
	"vei_loss.pressure_label", "vei_loss.pressure_text", "vei_loss.reserve", "vei_loss.tag", "vei_loss.change_label",
	"vei_loss.change.weave", "vei_loss.change.living", "vei_loss.change.horde_ferried", "vei_loss.change.fronts_held",
	"vei_loss.change.fronts_held_flood", "vei_loss.change.fallback",
	"vei_loss.short_label", "vei_loss.short_front", "vei_loss.short_backups", "vei_loss.short_backups_one", "vei_loss.short_join",
	"vei_loss.fix_label", "vei_loss.fix_fronts", "vei_loss.fix_backups", "vei_loss.fix_front.giants", "vei_loss.fix_front.swarm",
	"vei_loss.fix_front.carvers", "vei_loss.fix_front.raw", "vei_loss.tip.weave", "vei_loss.tip.living",
	"vei_loss.join_and", "vei_loss.join_comma", "vei_loss.front_names.giants", "vei_loss.front_names.swarm",
	"vei_loss.front_names.carvers", "vei_loss.front_names.raw", "wardens.words.join_and", "wardens.words.join_comma",
	"wardens.last_chance", "wardens.last_chance_loose", "wardens.meter_label",
	"wardens.words.plate_head", "wardens.words.plate_foot", "wardens.words.wake_banner", "wardens.words.exposed_banner",
	"wardens.words.beaten_banner", "wardens.words.pack_broke_banner", "wardens.words.pack_horn", "wardens.words.pack_warded",
	"wardens.words.pack_broke", "wardens.words.pack_down", "wardens.words.pack_teach", "wardens.words.pack_teach_weak",
	"wardens.words.pack_label", "wardens.words.word_muffled", "wardens.words.word_intercepted", "wardens.words.word_flanked",
	"wardens.words.word_snuffed", "wardens.words.word_broken", "wardens.words.word_tolled", "wardens.words.word_toll",
	"wardens.words.word_braced", "wardens.words.shield_bash", "wardens.words.shield_rush", "wardens.words.shield_pinned",
	"wardens.words.shield_pin_broken", "wardens.words.shield_flank", "wardens.words.shield_glance", "wardens.words.shield_line",
	"wardens.words.shield_pin", "wardens.words.ord_st", "wardens.words.ord_nd", "wardens.words.ord_rd", "wardens.words.ord_th",
	"wardens.words.pyre_fire", "wardens.words.pyre_step_off", "wardens.words.pyre_warded_word", "wardens.words.pyre_burned",
	"wardens.words.pyre_fires", "wardens.words.pyre_plural", "wardens.words.pyre_exposed", "wardens.words.pyre_warded",
	"wardens.words.pyre_at_relish", "wardens.words.break_line", "wardens.words.takes_head", "wardens.words.takes_stunned",
	"wardens.words.takes_shield", "wardens.words.takes_acolyte", "wardens.words.takes_pack", "wardens.words.counter_line",
	"wardens.words.counter_muffle", "wardens.words.counter_intercept", "wardens.words.counter_flank", "wardens.words.counter_snuff",
	"wardens.words.counter_none", "wardens.words.counter_none_party", "wardens.words.counter_make", "wardens.words.counter_have", "wardens.words.counter_helps", "death.missed_row",
	"death.missed_row_named", "death.attack_slam", "death.attack_toll", "death.attack_lunge", "death.attack_bash", "death.attack_rush", "death.attack_fire",
	"wardens.words.catch_label", "wardens.words.catch_ally", "wardens.words.join_and", "wardens.words.join_comma",
	"wardens.words.tally_muffled", "wardens.words.tally_intercepted", "wardens.words.tally_flanked", "wardens.words.tally_snuffed",
	"wardens.words.row_braced", "wardens.words.row_stunned", "wardens.words.row_phase", "wardens.words.row_caught",
	"wardens.words.row_phase_n", "wardens.words.row_hunting", "wardens.words.row_acolytes", "wardens.words.row_burned",
	"wardens.words.took_tag", "wardens.words.pack_more", "wardens.words.pack_horn_coming",
	"hud.legend.header", "hud.legend.hide", "hud.legend.chip", "hud.legend.click", "hud.legend.move", "hud.legend.space",
	"hud.legend.or", "hud.legend.mouse", "hud.legend.slow", "hud.legend.drag",
	"hud.retreat.title", "hud.retreat.btn_retreat", "hud.retreat.btn_stay", "hud.retreat.foot",
	"clear.foot", "held_door.label_unused_head", "held_door.label_unused_sub", "detour.cache_label",
	"hud.stats.label_essence", "hud.stats.label_raised", "hud.stats.label_phyl", "hud.stats.label_banked", "hud.stats.label_unbanked",
	"hud.stats.label_door", "hud.stats.rank_chaff", "hud.stats.rank_soldier", "hud.stats.rank_elite", "hud.stats.rank_big",
	"hud.stats.loose", "hud.stats.none", "hud.stats.at_risk", "hud.stats.on_floor",
	"hud.stats.key_relic", "hud.stats.key_remnant", "hud.stats.key_husk", "hud.stats.key_blueprint",
	"hud.text.title_tier", "hud.text.raised_big", "hud.text.raised_ranks", "hud.text.checkpoint", "hud.text.trance_ready",
	"hud.text.trance_focus", "hud.text.trance_cooldown", "hud.text.edge_exit", "hud.text.edge_warden", "hud.text.edge_loot",
	"hud.text.exit_off", "hud.text.exit_retreat", "hud.text.exit_banks",
	"ghost_ring.label",
	"vei_loss.keep_text", "relish.word_struck", "relish.word_soaked",
	"trace_notch.grade_head", "trace_notch.tier_tail", "trace_notch.not_circle", "trace_notch.word_perfect", "trace_notch.word_great",
	"trace_notch.word_good", "trace_notch.word_okay", "trace_notch.word_shaky", "trace_notch.word_poor", "trace_notch.word_awful",
	"vei_fight.name", "vei_fight.banner_court", "vei_fight.banner_front", "vei_fight.banner_break", "vei_fight.banner_crack",
	"vei_fight.banner_weave", "vei_fight.crack_phyl", "vei_fight.crack_clone", "vei_fight.plural", "vei_fight.hint_fronts", "vei_fight.hint_break",
	"vei_fight.lane_have", "vei_fight.lane_short", "vei_fight.lane_cleared", "vei_fight.lane_sends", "vei_fight.lane_met", "vei_fight.safe_cue",
	"vei_fight.hud_fronts", "vei_fight.hud_need", "vei_fight.hud_time", "vei_fight.hud_broken", "vei_fight.hud_broken_note",
	"vei_fight.hud_backlog", "vei_fight.hud_ferried", "vei_fight.hud_she_breaks", "vei_fight.hud_lost", "vei_fight.hud_winning",
	"vei_fight.hud_losing", "vei_fight.hud_break", "vei_fight.hud_backups", "vei_fight.hud_left", "vei_fight.hud_cracked",
	"vei_fight.eta", "vei_fight.lapse", "vei_fight.rule", "vei_fight.rule_cost", "vei_fight.rule_reset",
	"vei_fight.card_title_win", "vei_fight.card_title_lose", "vei_fight.card_sub_win", "vei_fight.card_time", "vei_fight.card_backups",
	"vei_fight.card_of", "vei_fight.card_none", "vei_fight.card_party", "vei_fight.card_backlog", "vei_fight.card_backlog_spent",
	"vei_fight.card_button", "vei_fight.card_button_auto",
	"revive.banner", "revive.left_none", "revive.left_one", "revive.left_fmt",
]

## The death card's numbers (raid.json death, read by RaidDeathCard and the clear card): each must be a number above zero.
const NUMBERS := [
	"death.card_w", "death.card_pad", "death.label_w", "death.value_px", "death.label_px", "death.foot_px", "death.sub_px",
	"death.sub_h", "death.backdrop_a", "death.plate_a", "hud.retreat.margin", "hud.retreat.gap", "revive.banner_s",
	"hud.stats.plate_w", "hud.stats.label_col", "hud.stats.value_pad", "hud.stats.row_px",
	"wardens.archetypes.bellringer.weak_point.counter_needed_from_tier", "wardens.archetypes.huntsman.weak_point.counter_needed_from_tier",
	"wardens.archetypes.shieldwall.weak_point.counter_needed_from_tier", "wardens.archetypes.pyre_priest.weak_point.counter_needed_from_tier",
	"wardens.archetypes.bellringer.weak_point.counter_helps_from_tier", "wardens.archetypes.huntsman.weak_point.counter_helps_from_tier",
	"wardens.archetypes.shieldwall.weak_point.counter_helps_from_tier", "wardens.archetypes.pyre_priest.weak_point.counter_helps_from_tier",
	"trace_notch.live_font_px", "trace_notch.live_ladder_px", "trace_notch.live_gap_px", "trace_notch.live_pad_px", "trace_notch.live_plate_alpha",
	"relish.hit_word_halo_px", "relish.hit_word_gap_px", "relish.hit_word_margin_px", "trace_notch.screen_margin_px", "trace_notch.result_gap_px", "trace_notch.result_stack_gap_px",
]

## The words the code formats, with the placeholders each must keep ("%d" words go through `%`, which throws without one).
const FORMATS := {
	"hud.stats.enemy": ["%d"], "hud.stats.enemies": ["%d"], "wardens.last_chance_loose": ["%d"],
	"vei_loss.break_text": ["{best}", "{need}"], "vei_loss.fronts_text": ["{fell}", "{total}", "{need}"],
	"vei_loss.held_clause": ["{held}"], "vei_loss.pressure_text": ["{mult}", "{pool}", "{reserve}"], "vei_loss.tag": ["{mult}"],
	"vei_loss.short_front": ["{name}", "{have}", "{need}"], "vei_loss.short_backups": ["{have}", "{need}"], "vei_loss.short_backups_one": ["{have}"],
	"vei_loss.fix_fronts": ["{fronts}"], "vei_loss.fix_front.giants": ["{gap}"], "vei_loss.fix_front.swarm": ["{gap}"],
	"vei_loss.fix_front.carvers": ["{gap}"], "vei_loss.fix_front.raw": ["{gap}"],
	"hud.goal.goal_break": ["%s", "%s"], "hud.goal.route_ahead_one": ["%d", "%s"], "hud.goal.route_ahead_many": ["%d", "%s"],
	"hud.goal.route_next_door": ["%s"], "hud.goal.route_room": ["%d", "%d", "%s"], "hud.goal.rooms_seen": ["%d", "%d"],
	"hud.goal.push_living": ["%d"], "hud.goal.push_exit": ["%s"], "hud.goal.push_exit_next": ["%s"], "hud.goal.push_exit_rooms": ["%s", "%d"],
	"hud.goal.risk_some": ["%s"], "hud.goal.risk_essence": ["%d"],
	"death.wait_s": ["%d"], "death.wait_min": ["%d"], "death.wait_min_s": ["%d", "%d"],
	"held.banner_holds": ["%s"], "held.payoff": ["%d", "%d", "%d"], "held.payoff_husk": ["%d"], "held.map_effect": ["%d"],
	"death.cause_slam": ["%s"], "death.cause_toll": ["%s"], "death.cause_lunge": ["%s"], "death.cause_bash": ["%s"], "death.cause_rush": ["%s"],
	"death.cause_fire": ["%s"], "death.cause_hound": ["%s"], "death.cause_pack": ["%s"],
	"death.missed_row": ["%s"], "death.missed_row_named": ["%s"], "death.killed_missed": ["%s", "%s"], "death.lost_bigs": ["%d"], "death.shut_text": ["%s"],
	"clear.title": ["%s"],
	"held_door.label_held": ["%s"], "held_door.label_sent": ["%s"], "held_door.label_shut": ["%s"], "held_door.label_freed": ["%s"],
	"held_door.row_held": ["%s"], "held_door.row_shut": ["%s"],
	"held_door.retreat_sent": ["%s"], "held_door.retreat_held": ["%s"], "held_door.retreat_shut": ["%s"],
	"wardens.words.wake_banner": ["%s", "%s"], "wardens.words.exposed_banner": ["%s"], "wardens.words.pack_horn": ["%d", "%s"],
	"wardens.words.pack_warded": ["%s"], "wardens.words.pack_down": ["%s"], "wardens.words.pack_teach": ["%s", "%d", "%s", "%s"],
	"wardens.words.pack_teach_weak": ["%s", "%s"], "wardens.words.pack_label": ["%s", "%d", "%d", "%s"],
	"wardens.words.shield_line": ["%d", "%s", "%s", "%d", "%s"], "wardens.words.shield_pin": ["%s"],
	"wardens.words.pyre_burned": ["%d"], "wardens.words.pyre_fires": ["%d", "%s", "%s"], "wardens.words.pyre_exposed": ["%s"],
	"wardens.words.pyre_warded": ["%s", "%s", "%s"], "wardens.words.pyre_at_relish": ["%d"], "wardens.words.break_line": ["%d"],
	"wardens.words.takes_stunned": ["%s"], "wardens.words.takes_shield": ["%s", "%s"], "wardens.words.takes_acolyte": ["%s"],
	"wardens.words.takes_pack": ["%s", "%s"], "wardens.words.counter_line": ["%s", "%d", "%s"], "wardens.words.counter_have": ["%d"],
	"wardens.words.catch_label": ["%d", "%s", "%s"],
	"wardens.words.tally_muffled": ["%d", "%d"], "wardens.words.tally_intercepted": ["%d"], "wardens.words.tally_flanked": ["%d", "%d"],
	"wardens.words.tally_snuffed": ["%d"], "wardens.words.row_phase_n": ["%d", "%d"], "wardens.words.row_acolytes": ["%d", "%d"],
	"wardens.words.row_burned": ["%d"], "wardens.words.took_tag": ["%d"], "wardens.words.pack_more": ["%d", "%s"],
	"wardens.words.pack_horn_coming": ["%d", "%s"],
	"hud.stats.loose": ["%d"], "hud.stats.on_floor": ["%d"],
	"hud.text.title_tier": ["%s", "%d"], "hud.text.raised_big": ["%d", "%d"], "hud.text.raised_ranks": ["%d", "%d", "%d"],
	"hud.text.checkpoint": ["%d", "%d", "%d", "%d", "%d"],
	"vei_loss.keep_text": ["%d"], "relish.word_struck": ["%d"], "trace_notch.grade_head": ["%d", "%s"], "trace_notch.tier_tail": ["%d", "%s", "%s"],
	"trace_notch.live_head": ["%d", "%s"], "trace_notch.live_head_keep": ["%d", "%s"], "trace_notch.live_tail": ["%d", "%s"], "trace_notch.live_ladder": ["%d", "%d"],
	"revive.banner": ["%s"], "revive.left_fmt": ["%d"],
	"vei_fight.banner_court": ["%d"], "vei_fight.banner_front": ["%s", "%d", "%d"], "vei_fight.banner_crack": ["%s", "%d", "%s"],
	"vei_fight.lane_have": ["%d", "%d"], "vei_fight.lane_short": ["%d"], "vei_fight.safe_cue": ["%d"], "vei_fight.hud_need": ["%d"],
	"vei_fight.hud_ferried": ["%.2f"], "vei_fight.hud_left": ["%d", "%s"], "vei_fight.hud_cracked": ["%d"], "vei_fight.eta": ["%d"],
	"vei_fight.lapse": ["%d", "%d", "%s"], "vei_fight.rule": ["%d"], "vei_fight.rule_cost": ["%d"], "vei_fight.card_of": ["%d", "%d"],
	"vei_fight.card_button_auto": ["%d"],
}


func run() -> int:
	var t := TestUtil.new()
	t.suite("raid_config")
	_parse_tests(t)
	_word_tests(t)
	_whole_beat_tests(t)
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


## The format specifiers of `w` in order, `%%` left out: what `%` will take an argument for.
static func _specs(w: String) -> Array:
	var re := RegEx.new()
	re.compile("%(%|[-+0-9.*]*[a-zA-Z])")
	var out := []
	for m in re.search_all(w):
		if m.get_string() != "%%":
			out.append(m.get_string())
	return out


## How many `%` in `w` are not half of a `%%` (RaidLogic.word_fmt's count): a lone `%` the regex does not match too.
static func _percents(w: String) -> int:
	return w.count("%") - 2 * w.count("%%")


## What is wrong with raid.json's words, one string per problem (empty when they are all there).
static func _word_problems(raid: Dictionary) -> Array:
	var out: Array = []
	for p in WORDS:
		var v: Variant = _dig(raid, p)
		if not (v is String) or (v as String) == "":
			out.append("%s is missing or blank" % p)
	for p in NUMBERS:
		var v: Variant = _dig(raid, p)
		if not (v is float or v is int) or float(v) <= 0.0:
			out.append("%s is missing or not above zero" % p)
	for p in FORMATS:
		var v: Variant = _dig(raid, p)
		for ph in FORMATS[p]:
			if v is String and not (v as String).contains(ph):
				out.append("%s lost its %s" % [p, ph])
		# the exact list: `contains` cannot see a lost duplicate ("%d %d" -> "%d"), an extra placeholder or a stray %
		var exp: Array = FORMATS[p]
		if v is String and not exp.is_empty() and (exp[0] as String).begins_with("%"):
			var got := _specs(v)
			if got != exp:
				out.append("%s has the placeholders %s, the code formats it with %s" % [p, got, exp])
			elif _percents(v) != exp.size():
				out.append("%s has a stray %% besides its placeholders %s" % [p, exp])
	# a word the code reads without arguments (not in FORMATS) holds no bare %: its `%` would throw, or word_fmt blank it
	# ("%%" alone is fine: word_fmt turns it into one "%", and the words read this way go through word_fmt with [])
	for p in WORDS:
		var v: Variant = _dig(raid, p)
		if not FORMATS.has(p) and v is String and _percents(v) != 0:
			out.append("%s has a bare %% but no FORMATS entry (the code reads it with no arguments)" % p)
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


## Every `tell_beats` and `pack_rest_beats` under wardens.archetypes that is not a whole number, as "path = value".
## Why they must be whole: WardenLogic.after_rest(beat, tell, rest) = ceil(ceil(beat) + tell + rest) is the same as the
## assist-off formula only while tell and rest are whole beats; a fractional one (0.5) would change the OFF path
## (the warned-attack assist, LONGER WARNINGS), which must stay byte-identical to before the assist.
func _whole_beat_problems(raid: Variant) -> Array:
	var out: Array = []
	var arches: Variant = _dig(raid, "wardens.archetypes")
	if not (arches is Dictionary):
		return ["wardens.archetypes is missing"]
	_collect_fractional_beats(arches, "wardens.archetypes", out)
	return out


func _collect_fractional_beats(node: Variant, path: String, out: Array) -> void:
	if node is Dictionary:
		for k in node:
			var v: Variant = node[k]
			if (str(k) == "tell_beats" or str(k) == "pack_rest_beats") and (v is float or v is int):
				if not is_equal_approx(float(v), roundf(float(v))):
					out.append("%s.%s = %s" % [path, k, str(v)])
			else:
				_collect_fractional_beats(v, "%s.%s" % [path, k], out)
	elif node is Array:
		for i in (node as Array).size():
			_collect_fractional_beats(node[i], "%s[%d]" % [path, i], out)


func _whole_beat_tests(t: TestUtil) -> void:
	var raid: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_DIR.path_join("raid.json")))
	if not (raid is Dictionary):
		t.ok(false, "raid.json parses, so the whole-beat check can run")
		return
	var seen := _count_beat_keys(_dig(raid, "wardens.archetypes"))
	t.ok(seen >= 8, "the whole-beat check sees every warden's tell_beats and pack_rest_beats (%d found)" % seen)
	var problems := _whole_beat_problems(raid)
	t.ok(problems.is_empty(), "every wardens.archetypes tell_beats and pack_rest_beats is a whole number: WardenLogic.after_rest equals the assist-off formula only for whole beats, so a fraction would change the off path: %s" % [problems])
	# the proof: an in-memory 0.5 is reported, for each key
	var half_tell: Dictionary = (raid as Dictionary).duplicate(true)
	half_tell["wardens"]["archetypes"]["huntsman"]["attack"]["tell_beats"] = 0.5
	t.ok(_whole_beat_problems(half_tell) == ["wardens.archetypes.huntsman.attack.tell_beats = 0.5"], "a tell_beats of 0.5 is reported: %s" % [_whole_beat_problems(half_tell)])
	var half_rest: Dictionary = (raid as Dictionary).duplicate(true)
	half_rest["wardens"]["archetypes"]["bellringer"]["attack"]["pack_rest_beats"] = 0.5
	t.ok(_whole_beat_problems(half_rest) == ["wardens.archetypes.bellringer.attack.pack_rest_beats = 0.5"], "a pack_rest_beats of 0.5 is reported: %s" % [_whole_beat_problems(half_rest)])
	t.ok(_whole_beat_problems({}) == ["wardens.archetypes is missing"], "no archetypes at all is reported")


func _count_beat_keys(node: Variant) -> int:
	var n := 0
	if node is Dictionary:
		for k in node:
			if str(k) == "tell_beats" or str(k) == "pack_rest_beats":
				n += 1
			else:
				n += _count_beat_keys(node[k])
	elif node is Array:
		for e in node:
			n += _count_beat_keys(e)
	return n


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
	var no_card_w: Dictionary = (real as Dictionary).duplicate(true)
	no_card_w["death"].erase("card_w")
	t.ok(_word_problems(no_card_w).has("death.card_w is missing or not above zero"), "a deleted death.card_w (the death card's width) is reported")
	var tell_less: Dictionary = (real as Dictionary).duplicate(true)
	tell_less["wardens"]["archetypes"]["huntsman"]["tells"] = []
	t.ok(_word_problems(tell_less).has("wardens.archetypes.huntsman.tells is missing or empty"), "a warden with no tells is reported")
	var stray: Dictionary = (real as Dictionary).duplicate(true)
	stray["demo"]["loot_hint"] = ""
	stray["held_door"]["_doc_geometry"] = ""
	var sp := _word_problems(stray)
	t.ok(sp.has("demo.loot_hint is blank") and sp.size() == 1, "a blank word outside WORDS is reported, and a blank _doc is not: %s" % [sp])

	# the format check is exact: each break below is caught (an in-memory raid.json, one edit each)
	t.ok(_word_problems(real).is_empty(), "the shipped words pass the exact format check")
	var edits := {
		"vei_fight.card_of": ["%d of total", "a placeholder lost (card_of: '%d of %d' became '%d of total', so rows_for would throw)"],
		"hud.text.raised_ranks": ["%d %d", "a placeholder lost (3 became 2)"],
		"hud.text.raised_big": ["%d, %d and %d", "a placeholder gained (2 became 3)"],
		"hud.text.checkpoint": ["%d %d %d %d", "a lost duplicate of one kind (five %d became four)"],
		"hud.goal.goal_break": ["%d and %s", "a placeholder's type changed (%s became %d)"],
		"hud.stats.enemies": ["%d enemies, 100% sure", "a stray % beside the placeholder"],
		"hud.text.exit_banks": ["banks 100% of your loot", "a bare % in a word the code reads with no arguments (every ExitButton redraw would throw)"],
	}
	for p: String in edits:
		var broken: Dictionary = (real as Dictionary).duplicate(true)
		var parts := p.split(".")
		var node: Dictionary = broken
		for i in parts.size() - 1:
			node = node[parts[i]]
		node[parts[parts.size() - 1]] = (edits[p] as Array)[0]
		var found := false
		for msg: String in _word_problems(broken):
			found = found or msg.begins_with(p + " ")
		t.ok(found, "%s is reported: %s" % [p, (edits[p] as Array)[1]])
	var pct: Dictionary = (real as Dictionary).duplicate(true)
	pct["hud"]["text"]["exit_banks"] = "banks 100%% of your loot"
	t.ok(_word_problems(pct).is_empty(), "a %% word outside FORMATS is fine (the code reads it through word_fmt, which makes it one %)")
	t.ok(_specs("%d%% of %s, %.2f") == ["%d", "%s", "%.2f"] and _percents("%d%% stays") == 1 and _percents("100% of") == 1, "_specs skips %% and keeps the flags; _percents counts a lone %")
