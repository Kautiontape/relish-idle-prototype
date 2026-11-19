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


## Where a card taller than `room` ends its visible area: the bottom of the last block (`bottoms`,
## each block's bottom edge in the card's frame) that fits, so no line is cut at the fold; `room`
## itself when no block fits.
static func snap_bottom(bottoms: Array, room: float) -> float:
	var best := -1.0
	for b in bottoms:
		if float(b) <= room and float(b) > best:
			best = float(b)
	return best if best > 0.0 else room


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
## uid with no name shows as itself). `siege_block` is realm.json tithe.siege_block, the share of a
## tithe wave a siege there blocks (0: not given, the siege chip makes no claim).
static func status_chips(fort: Dictionary, names: Dictionary, siege_block := 0.0) -> Array:
	var ch := _table("chips")
	var keys := _table("chip_keys")
	var out: Array = []
	out.append(fort_state(fort)["chip"])
	var tithe: Dictionary = fort.get("tithe", {})
	if bool(tithe.get("wave_active", false)):
		out.append({"text": str(ch.get("tithe_now", "")), "key": keys.get("tithe", "text")})
	elif bool(tithe.get("targeted", false)) and float(tithe.get("eta_s", -1.0)) >= 0.0:
		out.append({"text": str(ch.get("tithe_in_fmt", "%s")) % fmt_clock(float(tithe["eta_s"])), "key": keys.get("tithe", "text")})
	elif bool(tithe.get("next", false)) and float(tithe.get("next_s", -1.0)) >= 0.0:
		out.append({"text": str(ch.get("tithe_next_fmt", "%s")) % fmt_clock(float(tithe["next_s"])), "key": keys.get("tithe_next", "text_dim")})
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
		# what siege does: it blocks a share of a tithe wave and kills nothing; a second at the same fort adds nothing
		if siege_block > 0.0:
			out.append({"text": str(ch.get("siege_blocks_fmt", "%d")) % roundi(siege_block * 100.0), "key": keys.get("siege", "text")})
			if siege.size() > 1:
				out.append({"text": str(ch.get("siege_second", "")), "key": keys.get("siege", "text")})
	var charges := float(fort.get("simulacrum_charges", 0.0))
	if charges > 0.0:
		out.append({"text": str(ch.get("simulacrum_fmt", "%s")) % MapLogic.fmt_mass(charges), "key": keys.get("simulacrum", "text")})
	if bool(fort.get("first_dungeon", false)):
		out.append({"text": str(ch.get("first_dungeon", "")), "key": keys.get("first_dungeon", "text")})
	return out


## The fort's owner in the glossary's words: {state ("held" / "retaken" / "veis"), chip {text, key},
## line (how it got that way and what to do next)}. Retaken is a Vei's fort the player once held
## (flipped_count > 0); a Vei's fort with undead inside and no living (NodeLogic's overrun) says so, and once the
## game is won (the fort's `won`: MapModel's stamp) says it in words true after her death (veis_overrun_won).
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
		"line": str(words.get(("veis_overrun_won" if bool(fort.get("won", false)) else "veis_overrun") if overrun else "veis", ""))}


## The held chip. While the grace clock runs, "HELD · Vei contests in 6:14" (the hold's own colour);
## after it, with a margin, "HELD · 64 undead · SAFE" in the margin's colour; with none, "HELD".
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


## "also counts: Pale Ann (not assigned: its best front)": the uids VeiFronts counted on a front
## (`counted`) that the player did not assign, or "" when there are none (or no `counted`, an old-shape row).
static func also_counts_text(counted: Array, assigned: Array, names: Dictionary) -> String:
	var who: Array = []
	for u in counted:
		if not assigned.has(u):
			who.append(str(names.get(str(u), str(u))))
	if who.is_empty():
		return ""
	return str(_c().get("front_also_fmt", "%s")) % ", ".join(who)


## "+ her queue: 12" for a front whose `have` includes Vei's queue, else "". Which fronts count it is
## read from vei.json's fronts block (`vei_cfg`, ConfigDb's): per_backlog or per_q above 0 (VeiFronts:
## have = per_stat * sum(stat) + per_backlog * backlog + per_q * digest_q). The amount is `have` less
## per_stat * the counted units' stat on that front (`bigs`: uid -> view_big_undead entry); when a
## counted unit's stats are not in `bigs` it is only named ("+ her queue").
static func queue_text(f: Dictionary, vei_cfg: Dictionary, bigs: Dictionary) -> String:
	var fc: Dictionary = vei_cfg.get("fronts", {}).get(str(f.get("id", "")), {})
	if float(fc.get("per_backlog", 0.0)) <= 0.0 and float(fc.get("per_q", 0.0)) <= 0.0:
		return ""
	if not f.has("counted"):  # an old-shape row: nothing to take the units' part from, so the queue is only named (not all of `have`)
		return str(_c().get("front_queue", ""))
	var sum := 0.0
	for u in f.get("counted", []):
		var b: Dictionary = bigs.get(str(u), {})
		if not b.has("stats"):
			return str(_c().get("front_queue", ""))
		sum += float(b["stats"].get(str(fc.get("stat", "")), 0.0))
	var amount := float(f.get("have", 0.0)) - float(fc.get("per_stat", 1.0)) * sum
	return str(_c().get("front_queue_fmt", "%s")) % MapLogic.fmt_mass(maxf(amount, 0.0))


## One row per front: {id, name, have, need (formatted masses), cleared, mark ("✓ met" / "✗ open"),
## assigned (text), also (the "also counts" line or ""), queue (the "+ her queue" line or "")}.
## `vei_cfg` (configs/vei.json) and `bigs` (uid -> view_big_undead entry) give the queue part; without
## them a row has no queue line.
static func front_rows(fronts: Array, names: Dictionary, vei_cfg: Dictionary = {}, bigs: Dictionary = {}) -> Array:
	var out: Array = []
	for f in fronts:
		var cleared := bool(f.get("cleared", false))
		out.append({"id": str(f.get("id", "")), "name": front_name(str(f.get("id", ""))),
			"have": MapLogic.fmt_mass(float(f.get("have", 0.0))), "need": MapLogic.fmt_mass(float(f.get("need", 0.0))),
			"cleared": cleared, "mark": str(_c().get("front_met" if cleared else "front_open", "")),
			"assigned": assigned_text(f.get("assigned", []), names),
			"also": also_counts_text(f.get("counted", []), f.get("assigned", []), names),
			"queue": queue_text(f, vei_cfg, bigs)})
	return out


## "fronts met 1 · any 3 of the 4 are needed": the fight counts any `fronts_required` cleared fronts
## (VeiFronts.required, vei.json), so with more fronts than that the line says "any N of the M"; when
## every front is needed (or the view lists none) it reads "fronts met 1 of the 3 needed".
static func fronts_met_text(vei: Dictionary) -> String:
	return _fronts_fmt(vei, "fronts_met_fmt", "fronts_met_all_fmt")


static func _fronts_fmt(vei: Dictionary, any_key: String, all_key: String) -> String:
	var met := int(vei.get("fronts_met", 0))
	var need := int(vei.get("fronts_required", 0))
	var n := (vei.get("fronts", []) as Array).size()
	if n > need:
		return str(_c().get(any_key, "%d %d %d")) % [met, need, n]
	return str(_c().get(all_key, "%d %d")) % [met, need]


## The BEGIN dialog's text: repeats the odds, the sign and the drain time ("∞" when holding,
## "queue empty" with no backlog) from MapModel.readout(), as the top bar and Vei's node read them.
## With the fronts short (`vei.fronts_met` < `fronts_required`) the shortfall sentence follows on its own line.
static func confirm_text(readout: Dictionary, vei: Dictionary = {}) -> String:
	var st := HudLogic.status(readout)
	var sign := int(st["sign"])
	var text := str(_c().get("confirm_fmt", "%d %s %s")) % [roundi(clampf(float(readout.get("odds", 0.0)), 0.0, 1.0) * 100.0),
		"%s %s" % [st["sign_text"], sign_word(sign)] if sign != 0 else sign_word(0),
		st["drain_text"]]
	var short := fronts_short_text(vei)
	return text + "\n" + short if short != "" else text


## "Fronts met 1; any 3 of the 4 are needed, or Vei will likely win. Assign big undead to the open
## fronts." while the fronts met are fewer than required, else "" (the "of the N needed" form as
## fronts_met_text picks it).
static func fronts_short_text(vei: Dictionary) -> String:
	if int(vei.get("fronts_met", 0)) >= int(vei.get("fronts_required", 0)):
		return ""
	return _fronts_fmt(vei, "fronts_short_fmt", "fronts_short_all_fmt")


# --- who comes into a raid ---------------------------------------------------------------

## Who comes in with Relish at fort `fort`: {garrison, starter, bigs, total}. The garrison is the
## fort's undead over raid mass.garrison_mass_div (up to garrison_max; `undead`, not `garrison`, which
## is 0 unless held), the starter party is the first dungeon's only, the bigs are `party.party`
## (view_party()). The same formula as GameState._garrison and _starter_units.
static func comes_in(fort: Dictionary, party: Dictionary, raid_cfg: Dictionary, econ_cfg: Dictionary) -> Dictionary:
	var mass: Dictionary = raid_cfg.get("mass", {})
	var garrison := RaidLogic.garrison_count(float(fort.get("undead", 0.0)), raid_cfg)  # the raid's own count
	var first := bool(fort.get("first_dungeon", false))
	var starter := int(econ_cfg.get("opening", {}).get("starter_party", 0)) if first else 0
	var bigs := (party.get("party", []) as Array).size()
	# the counter's worth against THIS fort's warden: the raid's COUNTER-row rule (WardenLogic.counter_role)
	var counter := WardenLogic.counter_role_for_fort(str(fort.get("id", "")), int(fort.get("tier", 1)), first, raid_cfg)
	return {"garrison": garrison, "starter": starter, "bigs": bigs, "total": garrison + starter + bigs,
		"war_here": maxf(float(fort.get("undead", 0.0)), 0.0), "garrison_max": int(mass.get("garrison_max", 12)),
		"garrison_div": int(mass.get("garrison_mass_div", 10.0)), "counter": counter}


## The standard party of tier `tier` (clamped 1..4): {undead, bigs}, from raid autopilot.party_profiles.
## "Standard party" is raid.json autopilot.party_profiles: dungeon-owned (BALANCE 3's calibration
## party), the one source on purpose. If dungeon retunes it, the warning moves with it.
static func profile(tier: int, raid_cfg: Dictionary) -> Dictionary:
	var p: Dictionary = raid_cfg.get("autopilot", {}).get("party_profiles", {}).get(str(clampi(tier, 1, 4)), {})
	return {"undead": int(p.get("garrison_units", 0)) + int(p.get("starter_units", 0)), "bigs": (p.get("party", []) as Array).size()}


## The warning before a raid: {text, key}, or {}. Nobody coming in is "danger"; a party under the
## tier's standard is "select" (the big-undead part is dropped when the standard has none).
## With nobody coming in, corpse piles decide: a raid builds them when the fort's `dead` is over
## cards.comes_pile_min_dead (raid.gd's `dead > 0.05`), and Relish can raise undead from them
## ("select": a way forward); with none the raid can't be won ("danger").
static func comes_in_warning(ci: Dictionary, prof: Dictionary, tier: int, dead: float) -> Dictionary:
	if int(ci.get("total", 0)) == 0:
		if dead > float(_c().get("comes_pile_min_dead", 0.05)):
			return {"text": str(_c().get("comes_none_piles", "")), "key": "select"}
		return {"text": str(_c().get("comes_none", "")), "key": "danger"}
	var u := int(prof.get("undead", 0))
	var b := int(prof.get("bigs", 0))
	if int(ci.get("garrison", 0)) + int(ci.get("starter", 0)) < u or int(ci.get("bigs", 0)) < b:
		var t := clampi(tier, 1, 4)
		var text := (str(_c().get("comes_below_fmt", "%d %d %d")) % [t, u, b]) if b > 0 else (str(_c().get("comes_below_no_bigs_fmt", "%d %d")) % [t, u])
		return {"text": text, "key": "select"}
	return {}


## The plain first line of WHO COMES IN, from the same counts: "8 undead and 1 big undead come with
## you.", "No undead come with you."; while the party has no big undead, a second sentence says how
## to get one.
static func comes_plain_text(ci: Dictionary) -> String:
	var u := int(ci.get("garrison", 0)) + int(ci.get("starter", 0))
	var b := int(ci.get("bigs", 0))
	var s: String
	if u + b == 0:
		s = str(_c().get("comes_plain_none", ""))
	elif b > 0 and u > 0:  # both kinds: at least two come
		s = str(_c().get("comes_plain_bigs_fmt", "%d %d")) % [u, b]
	elif b > 0:  # only big undead: "comes" for exactly one
		s = str(_c().get("comes_plain_bigs_only_one_fmt" if b == 1 else "comes_plain_bigs_only_fmt", "%d")) % b
	else:
		s = str(_c().get("comes_plain_one_fmt" if u == 1 else "comes_plain_fmt", "%d")) % u
	if b == 0:  # a card without "counter" reads as "needed", as the sentence always did
		var key: String = {"needed": "comes_plain_warden", "helps": "comes_plain_warden_helps"}.get(str(ci.get("counter", WardenLogic.COUNTER_NEEDED)), "")
		if key != "":
			s += " " + str(_c().get(key, ""))
	return s


## Who they are, in one plain sentence (the glossary's "Who comes into a raid"; the plain line above
## has the count): each source that sends any, then what you raise inside. The fort's WAR undead come
## in one per 10 (at most garrison_max), the rule comes_in counts by, so the sentence names the fort's
## own number as its HELD chip shows it ("2 from the 22 WAR undead here (one per 10)"), and says when
## they are too few to send one. Day 1: "They're your 8 starter undead, plus any you raise inside; none
## come from your WAR stream yet."
static func comes_in_text(ci: Dictionary) -> String:
	var c := _c()
	var g := int(ci.get("garrison", 0))
	var s := int(ci.get("starter", 0))
	var b := int(ci.get("bigs", 0))
	# The count is the WHOLE undead, as the raid counts them (RaidLogic.garrison_count floors undead / div):
	# 9.6 reads "9", never a "10" that would send one. Under 1 reads as none.
	var here := floorf(float(ci.get("war_here", 0.0)))
	var here_s := MapLogic.fmt_mass(here)
	var div := int(ci.get("garrison_div", 10))
	var one := is_equal_approx(here, 1.0)  # "the 1 WAR undead here is", "the 4 ... are"
	var war_note := ""
	if g == 0:
		war_note = str(c.get("comes_who_few_one_fmt" if one else "comes_who_few_fmt", "%s %d")) % [here_s, div] if here > 0.0 else str(c.get("comes_who_no_war", ""))
	if g + s + b == 0:
		return (str(c.get("comes_who_none_few_one_fmt" if one else "comes_who_none_few_fmt", "%s %d")) % [here_s, div]) if here > 0.0 else str(c.get("comes_who_none", ""))
	var parts: Array = []
	if g > 0:
		var gmax := int(ci.get("garrison_max", 12))
		var capped := g >= gmax and here >= float(g + 1) * float(div)
		parts.append((str(c.get("comes_who_garrison_cap_fmt", "%d %s %d %d")) % [g, here_s, div, gmax]) if capped
			else (str(c.get("comes_who_garrison_fmt", "%d %s %d")) % [g, here_s, div]))
	if s > 0:
		parts.append(str(c.get("comes_who_starter_fmt", "%d")) % s)
	if b > 0:
		parts.append(str(c.get("comes_who_bigs_fmt", "%d")) % b)
	var who := str(parts[0])
	for i in range(1, parts.size()):
		who += str(c.get("comes_who_and" if i == parts.size() - 1 else "comes_who_sep", ", ")) + str(parts[i])
	return str(c.get("comes_who_fmt", "%s%s")) % [who, war_note]


## The tide bias as the card says it: 3.0 reads "3", 2.5 reads "2.5".
static func bring_more_text(tide_bias: float) -> String:
	var word := str(roundi(tide_bias)) if is_equal_approx(tide_bias, roundf(tide_bias)) else String.num(tide_bias)
	return str(_c().get("bring_more_fmt", "%s")) % word


## The descend dialog's text: the warning line, a blank line, then the ask.
static func descend_confirm_text(warn: Dictionary) -> String:
	return "%s\n\n%s" % [str(warn.get("text", "")), str(_c().get("descend_confirm_ask", ""))]


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
