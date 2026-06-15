class_name CreatureNamer
extends RefCounted
## The name is identity-from-build rendered as language, live as you slot.
## Noun = the form (husk). An echo is the spice — if present, the strongest one
## names the creature. With no echo the name BLENDS the top two stats when the
## second is within blend_threshold of the first (e.g. "Brutal-Fleet Skeleton"),
## instead of a flat majority-wins single word. Nothing slotted -> "Hollow".

## [[stat, magnitude], ...] sorted by magnitude desc, Loot.STATS order breaking
## ties so naming is deterministic. Only stats with magnitude > 0.
static func _ranked_stats(stats: Dictionary) -> Array:
	var ranked: Array = []
	for i in Loot.STATS.size():
		var s: String = Loot.STATS[i]
		var m := float(stats.get(s, 0.0))
		if m > 0.0:
			ranked.append({"stat": s, "mag": m, "idx": i})
	ranked.sort_custom(func(a, b):
		if a["mag"] != b["mag"]:
			return a["mag"] > b["mag"]
		return a["idx"] < b["idx"])
	return ranked

static func _best_echo(echoes: Dictionary) -> String:
	var best := ""
	var best_pts := 0
	for id in echoes:
		if int(echoes[id]) > best_pts:
			best_pts = int(echoes[id])
			best = id
	return best

## The single defining adjective (echo wins, else top stat, else Hollow). Kept
## for any consumer that wants one word; the displayed name uses full_name().
static func adjective(stats: Dictionary, echoes: Dictionary) -> String:
	var names: Dictionary = ConfigDb.data["names"]
	var echo := _best_echo(echoes)
	if echo != "" and names["echo_adjectives"].has(echo):
		return names["echo_adjectives"][echo]
	var ranked := _ranked_stats(stats)
	if ranked.is_empty():
		return names["hollow_adjective"]
	return names["stat_adjectives"][ranked[0]["stat"]]

static func full_name(noun: String, stats: Dictionary, echoes: Dictionary) -> String:
	var names: Dictionary = ConfigDb.data["names"]
	# An echo is the spice — it names the creature on its own.
	var echo := _best_echo(echoes)
	if echo != "" and names["echo_adjectives"].has(echo):
		return "%s %s" % [names["echo_adjectives"][echo], noun]
	var ranked := _ranked_stats(stats)
	if ranked.is_empty():
		return "%s %s" % [names["hollow_adjective"], noun]
	var adj_a: String = names["stat_adjectives"][ranked[0]["stat"]]
	# Blend the second stat in when it's nearly as strong (proportions, not a
	# flat winner-takes-all) — but never more than two words before the noun.
	if ranked.size() >= 2:
		var share: float = ranked[1]["mag"] / ranked[0]["mag"]
		var adj_b: String = names["stat_adjectives"][ranked[1]["stat"]]
		if share >= float(names["blend_threshold"]) and adj_b != adj_a:
			return "%s%s%s %s" % [adj_a, String(names["blend_connector"]), adj_b, noun]
	return "%s %s" % [adj_a, noun]
