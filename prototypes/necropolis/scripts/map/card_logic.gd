class_name CardLogic
extends RefCounted
## Pure text builders for the map's cards (no autoloads, so headless tests compile it): the
## warden's name and tells, the loot line, the strength comparison, the risk chip, the cost of a
## death, the status chips, Vei's front rows and confirm text, the village owner words. They take
## view-shaped dictionaries and return Strings (or {text, key} chips); the words live in
## configs/map_view.json "cards". MapCardBlocks assembles them into a card; MapCardView draws it.


static func _c() -> Dictionary:
	return MapLogic.cfg().get("cards", {})


static func _table(name: String) -> Dictionary:
	return _c().get(name, {})


## "m:ss" from seconds, ceiling so "0:00 left" never shows while time remains.
static func fmt_clock(s: float) -> String:
	var n := maxi(ceili(s), 0)
	return "%d:%02d" % [n / 60, n % 60]


# --- the warden --------------------------------------------------------------------

## The warden's name: the view's `name` (raid.json's, the dungeon owns it) when it has one, else the
## id title-cased ("pyre_priest" -> "The Pyre Priest").
static func warden_name(archetype: String, name: String = "") -> String:
	if name != "":
		return name
	return str(_c().get("warden_fallback_fmt", "%s")) % archetype.replace("_", " ").capitalize()


## The warden block's lines: [name, tell, ...]: one tell, or every tell (the Watchtower case),
## or the "no tell known" line.
static func warden_lines(warden: Dictionary) -> Array:
	var out: Array = [warden_name(str(warden.get("archetype", "")), str(warden.get("name", "")))]
	var tells: Array = warden.get("tells", [])
	if tells.is_empty():
		out.append(str(_c().get("tell_none", "")))
	else:
		for t in tells:
			out.append(str(t))
	return out


## The label in front of the tells: TELL for one, TELLS for several.
static func tell_label(warden: Dictionary) -> String:
	return str(_c().get("tells_label" if (warden.get("tells", []) as Array).size() > 1 else "tell_label", ""))


# --- loot --------------------------------------------------------------------------

## The fort card's loot line: the dungeon unit's RaidLoot.card_line, so the card and the dungeon read
## from one source. `loot_cfg` is configs/loot.json (this file names no autoload, so the caller passes it).
static func loot_card_line(fort: Dictionary, loot_cfg: Dictionary) -> String:
	return RaidLoot.card_line(fort, loot_cfg)


## "FIRST CLEAR · guaranteed blueprint" while the fort's first clear is unspent, else "".
static func first_clear_line(fort: Dictionary) -> String:
	return str(_table("loot").get("first_clear_text", "")) if bool(fort.get("first_clear", false)) else ""


# --- threat in advance ---------------------------------------------------------------

## Whether the comparison is known: any strength above 0 (a 0-vs-0 reads as "not measured").
static func strength_known(threat: Dictionary) -> bool:
	return float(threat.get("party_strength", 0.0)) > 0.0 or float(threat.get("garrison_strength", 0.0)) > 0.0


## "PARTY 8.0 vs GARRISON 6.1", or the unknown line.
static func strength_text(threat: Dictionary) -> String:
	if not strength_known(threat):
		return str(_c().get("strength_unknown", ""))
	var dec := int(_c().get("strength_decimals", 1))
	return str(_c().get("strength_fmt", "%s %s")) % ["%.*f" % [dec, float(threat.get("party_strength", 0.0))],
		"%.*f" % [dec, float(threat.get("garrison_strength", 0.0))]]


## The comparison bars' fill, 0..1 each, both scaled to the larger strength; [0, 0] when unknown.
static func strength_fracs(threat: Dictionary) -> Array:
	if not strength_known(threat):
		return [0.0, 0.0]
	var a := maxf(float(threat.get("party_strength", 0.0)), 0.0)
	var b := maxf(float(threat.get("garrison_strength", 0.0)), 0.0)
	var top := maxf(a, b)
	return [a / top, b / top]


## The risk word chip: {text: "LOW" or "RISKY · 34%", key: palette key}. `risk_pct` >= 0 (the
## Watchtower) adds the exact percentage (it is a percent, 0..100).
# TODO(api): confirm risk_pct is 0..100, not a fraction
static func risk_chip(threat: Dictionary) -> Dictionary:
	var risk := str(threat.get("risk", "low"))
	var word := str(_table("risk_words").get(risk, risk.to_upper()))
	var pct := float(threat.get("risk_pct", -1.0))
	var text := (str(_c().get("risk_pct_fmt", "%s %d")) % [word, roundi(pct)]) if pct >= 0.0 else word
	return {"text": text, "key": str(_table("risk_keys").get(risk, "text"))}


## What a death costs right now, from view_backups().death, as lines: the outcome, the respawn
## time when > 0, then "loses: the party, unbanked loot, morale" (or "loses nothing").
static func death_lines(death: Dictionary) -> Array:
	var outcome := str(death.get("outcome", ""))
	var words := _table("death_outcomes")
	var said: String = str(words[outcome]) if words.has(outcome) else str(_c().get("death_fallback_fmt", "%s")) % outcome
	var out: Array = [str(_c().get("death_fmt", "%s")) % said]
	var respawn := float(death.get("respawn_s", 0.0))
	if respawn > 0.0:
		out.append(str(_c().get("death_respawn_fmt", "%s")) % fmt_clock(respawn))
	var lose_words := _table("loses_words")
	var lost: Array = []
	for k in death.get("loses", []):
		lost.append(str(lose_words.get(str(k), str(k).replace("_", " "))))
	out.append((str(_c().get("death_loses_fmt", "%s")) % ", ".join(lost)) if not lost.is_empty() else str(_c().get("death_loses_none", "")))
	return out


# --- status chips ------------------------------------------------------------------------

## The fort's status chips, each {text, key}. `names` maps big-undead uids to names (a siege
## uid with no name shows as itself).
static func status_chips(fort: Dictionary, names: Dictionary) -> Array:
	var ch := _table("chips")
	var keys := _table("chip_keys")
	var out: Array = []
	out.append(fort_state(fort)["chip"])
	var tithe: Dictionary = fort.get("tithe", {})
	if bool(tithe.get("wave_active", false)):
		out.append({"text": str(ch.get("tithe_now", "")), "key": keys.get("tithe", "text")})
	elif bool(tithe.get("targeted", false)) and float(tithe.get("eta_s", -1.0)) >= 0.0:
		out.append({"text": str(ch.get("tithe_in_fmt", "%s")) % fmt_clock(float(tithe["eta_s"])), "key": keys.get("tithe", "text")})
	if bool(fort.get("relish_here", false)):
		var parts: Array = [str(ch.get("relish_here", ""))]
		if bool(fort.get("tide", false)):
			parts.append(str(ch.get("tide", "")))
		if bool(fort.get("redirect", false)):
			parts.append(str(ch.get("redirect", "")))
		out.append({"text": " · ".join(parts), "key": keys.get("relish", "text")})
	var siege: Array = fort.get("siege", [])
	if not siege.is_empty():
		var who: Array = []
		for u in siege:
			who.append(str(names.get(str(u), str(u))))
		out.append({"text": str(ch.get("siege_fmt", "%s")) % ", ".join(who), "key": keys.get("siege", "text")})
	var charges := float(fort.get("simulacrum_charges", 0.0))
	if charges > 0.0:
		out.append({"text": str(ch.get("simulacrum_fmt", "%s")) % MapLogic.fmt_mass(charges), "key": keys.get("simulacrum", "text")})
	if bool(fort.get("first_dungeon", false)):
		out.append({"text": str(ch.get("first_dungeon", "")), "key": keys.get("first_dungeon", "text")})
	return out


## The fort's owner in the glossary's words: {state ("held" / "retaken" / "veis"), chip {text, key},
## line (how it got that way and what to do next)}. Retaken is a Vei's fort the player once held
## (flipped_count > 0); a Vei's fort with undead inside and no living (NodeLogic's overrun) says so.
static func fort_state(fort: Dictionary) -> Dictionary:
	var ch := _table("chips")
	var keys := _table("chip_keys")
	var words := _table("state")
	if bool(fort.get("held", false)):
		return {"state": "held", "chip": held_chip(fort),
			"line": str(words.get("held_grace" if float(fort.get("grace_s_left", 0.0)) > 0.0 else "held_contested", ""))}
	if int(fort.get("flipped_count", 0)) > 0:
		return {"state": "retaken", "chip": {"text": str(ch.get("retaken", "")), "key": keys.get("retaken", "text")},
			"line": str(words.get("retaken", ""))}
	var overrun := NodeLogic.fort_state(fort, "") == NodeLogic.OVERRUN
	return {"state": "veis", "chip": {"text": str(ch.get("veis", "")), "key": keys.get("veis", "text")},
		"line": str(words.get("veis_overrun" if overrun else "veis", ""))}


## The held chip. While the grace clock runs, "HELD · Vei contests in 6:14" (the hold's own colour);
## after it, with a margin, "HELD · garrison 64 · SAFE" in the margin's colour; with none, "HELD".
static func held_chip(fort: Dictionary) -> Dictionary:
	if float(fort.get("grace_s_left", 0.0)) > 0.0:
		return {"text": str(_table("chips").get("held_fmt", "%s")) % fmt_clock(float(fort["grace_s_left"])),
			"key": _table("chip_keys").get("held", "text")}
	var m := str(fort.get("margin", ""))
	if m != "":
		return {"text": str(_c().get("held_margin_fmt", "%s %s")) % [MapLogic.fmt_mass(IdleLogic.garrison_units(fort)), IdleLogic.word(m)],
			"key": IdleLogic.color_key(m)}
	return {"text": str(_table("chips").get("held_bare", "HELD")), "key": _table("chip_keys").get("held", "text")}


# --- Vei -----------------------------------------------------------------------------------

static func front_name(id: String) -> String:
	return str(_table("front_names").get(id, id.capitalize()))


## "gaining" / "holding" / "losing" for a sign.
static func sign_word(sign: int) -> String:
	return str(_table("sign_words").get(str(signi(sign)), ""))


## The names of the big undead assigned to a front, in order ("assigned: Old Gristle, Pale Ann",
## or "no one assigned"). `names` maps uids to names.
static func assigned_text(assigned: Array, names: Dictionary) -> String:
	if assigned.is_empty():
		return str(_c().get("front_unassigned", ""))
	var who: Array = []
	for u in assigned:
		who.append(str(names.get(str(u), str(u))))
	return str(_c().get("front_assigned_fmt", "%s")) % ", ".join(who)


## One row per front: {id, name, have, need (formatted masses), cleared, mark ("✓ met" / "✗ open"),
## assigned (text)}.
static func front_rows(fronts: Array, names: Dictionary) -> Array:
	var out: Array = []
	for f in fronts:
		var cleared := bool(f.get("cleared", false))
		out.append({"id": str(f.get("id", "")), "name": front_name(str(f.get("id", ""))),
			"have": MapLogic.fmt_mass(float(f.get("have", 0.0))), "need": MapLogic.fmt_mass(float(f.get("need", 0.0))),
			"cleared": cleared, "mark": str(_c().get("front_met" if cleared else "front_open", "")),
			"assigned": assigned_text(f.get("assigned", []), names)})
	return out


## "fronts met 3 of 3 required".
static func fronts_met_text(vei: Dictionary) -> String:
	return str(_c().get("fronts_met_fmt", "%d %d")) % [int(vei.get("fronts_met", 0)), int(vei.get("fronts_required", 0))]


## The BEGIN dialog's text: repeats the odds, the sign and the drain time ("∞" when holding,
## "queue empty" with no backlog) from MapModel.readout(), as the top bar and Vei's node read them.
static func confirm_text(readout: Dictionary) -> String:
	var st := HudLogic.status(readout)
	var sign := int(st["sign"])
	return str(_c().get("confirm_fmt", "%d %s %s")) % [roundi(clampf(float(readout.get("odds", 0.0)), 0.0, 1.0) * 100.0),
		"%s %s" % [st["sign_text"], sign_word(sign)] if sign != 0 else sign_word(0),
		st["drain_text"]]


## The odds summary pinned beside BEGIN (out of the card's scroll): "Your odds 61% ▲ gaining ·
## drains in ∞", from MapModel.readout() as the top bar reads it.
static func pinned_odds(readout: Dictionary) -> String:
	var st := HudLogic.status(readout)
	var sign := int(st["sign"])
	return str(_c().get("vei_pinned_fmt", "%d %s %s")) % [roundi(clampf(float(readout.get("odds", 0.0)), 0.0, 1.0) * 100.0),
		"%s %s" % [st["sign_text"], sign_word(sign)] if sign != 0 else sign_word(0), st["drain_text"]]


# --- villages ------------------------------------------------------------------------------

## The village owner in words ("held by the necrosis: its people drift to Covington").
static func village_owner_text(owner: String) -> String:
	var words := _table("village_owner_words")
	return str(words.get(owner, words.get("none", "")))


static func village_owner_tag(owner: String) -> String:
	var tags := _table("village_owner_tags")
	return str(tags.get(owner, tags.get("none", owner.to_upper())))
