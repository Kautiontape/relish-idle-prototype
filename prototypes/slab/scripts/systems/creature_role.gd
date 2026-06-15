class_name CreatureRole
extends RefCounted
## The verdict stamp. So a stranger (and you) can tell what a build is FOR, every
## creature gets a role from its dominant stat plus a "good for X" use-case. If
## an echo is present it flavors the use-case (the echo is what it's good AT).
## Combat-only for now — town roles arrive when town does.

## {role, good_for, line}. line = "Brawler — good for deleting single targets".
static func of(stats: Dictionary, echoes: Dictionary) -> Dictionary:
	var roles: Dictionary = ConfigDb.data["roles"]
	var ranked := CreatureNamer._ranked_stats(stats)
	if ranked.is_empty():
		var h: Dictionary = roles["hollow"]
		return {"role": h["role"], "good_for": h["good_for"],
			"line": "%s — good for %s" % [h["role"], h["good_for"]]}
	var dom: String = ranked[0]["stat"]
	var sr: Dictionary = roles["stat_roles"][dom]
	var good_for: String = sr["good_for"]
	var echo := CreatureNamer._best_echo(echoes)
	if echo != "" and roles["echo_good_for"].has(echo):
		good_for = roles["echo_good_for"][echo]
	return {"role": sr["role"], "good_for": good_for,
		"line": "%s — good for %s" % [sr["role"], good_for]}
