class_name CreatureNamer
extends RefCounted
## Adjective Noun. Noun = the form (husk). Adjective = the build's defining
## trait: an echo wins if any is present (highest points), else the dominant
## stat, else "Hollow" (nothing slotted). This is identity-emerges-from-build
## rendered as language — it updates live as remnants slot.

static func adjective(stats: Dictionary, echoes: Dictionary) -> String:
	var names: Dictionary = ConfigDb.data["names"]
	# An echo is the spice — if present, the strongest one names the creature.
	var best_echo := ""
	var best_pts := 0
	for id in echoes:
		if int(echoes[id]) > best_pts:
			best_pts = int(echoes[id])
			best_echo = id
	if best_echo != "" and names["echo_adjectives"].has(best_echo):
		return names["echo_adjectives"][best_echo]
	# else the dominant stat (Loot.STATS order breaks ties deterministically)
	var best_stat := ""
	var best_mag := 0.0
	for s in Loot.STATS:
		var m := float(stats.get(s, 0.0))
		if m > best_mag:
			best_mag = m
			best_stat = s
	if best_stat != "" and names["stat_adjectives"].has(best_stat):
		return names["stat_adjectives"][best_stat]
	return names["hollow_adjective"]

static func full_name(noun: String, stats: Dictionary, echoes: Dictionary) -> String:
	return "%s %s" % [adjective(stats, echoes), noun]
