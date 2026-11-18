class_name CardBlocksLogic
extends RefCounted
## Pure assembly of the map's cards (no autoloads): each card is {title, sub, desc, blocks}, and a
## block is a plain dictionary MapCardView draws. Block kinds (all carry `id`):
##   head {text}                        a section heading
##   para {text, key, face}             wrapped text; face "text" or "mass"; key is a palette key
##   chips {chips: [{text, key}]}       status chips (word plus colour)
##   row {label, value, vkind, suffix}  a label and a value; vkind "rate", "mass" or "text"
##   massline {mass, text}              a mass in the mass face, then words
##   versus {text, a, b, known}         the strength line and its two comparison bars (0..1)
##   risk {label, chip}                 a label and one word chip
##   front {name, count, mark, cleared, assigned}   a Vei front row
##   assign {uid, name, sub, selected, options, labels}   a party member and its front selector
## A block's structure signature is `sig_of`; a card redraws from scratch only when the signatures
## change, otherwise the view updates texts in place.


static func _c() -> Dictionary:
	return MapLogic.cfg().get("cards", {})


static func _head(id: String, text: String) -> Dictionary:
	return {"kind": "head", "id": id, "text": text}


static func _para(id: String, text: String, key := "text", face := "text") -> Dictionary:
	return {"kind": "para", "id": id, "text": text, "key": key, "face": face}


static func _row(id: String, label: String, value: String, vkind: String, suffix := "") -> Dictionary:
	return {"kind": "row", "id": id, "label": label, "value": value, "vkind": vkind, "suffix": suffix}


## The structure signature of one block.
static func sig_of(b: Dictionary) -> String:
	var extra := ""
	match str(b["kind"]):
		"chips":
			extra = str((b["chips"] as Array).size())
		"assign":
			extra = "%s:%s" % [b["uid"], ",".join(b["options"])]
		"row":
			extra = str(b["suffix"] != "")
	return "%s:%s:%s" % [b["kind"], b["id"], extra]


## The structure signature of a whole card (its blocks plus whether it has a description).
static func card_sig(card: Dictionary) -> String:
	var parts: Array = [str(str(card.get("desc", "")) != "")]
	for b in card["blocks"]:
		parts.append(sig_of(b))
	return "|".join(parts)


## The fort card, top to bottom: chips, warden, loot, threat in advance, matter.
## `backups` is view_backups(), `names` maps big-undead uids to names, `loot_cfg` is configs/loot.json
## (for the dungeon's loot line).
static func fort_card(fort: Dictionary, desc: String, backups: Dictionary, names: Dictionary, loot_cfg: Dictionary) -> Dictionary:
	var c := _c()
	var blocks: Array = []
	var chips := CardLogic.status_chips(fort, names)
	if not chips.is_empty():
		blocks.append({"kind": "chips", "id": "chips", "chips": chips})
	var held := bool(fort.get("held", false))
	blocks.append(_para("state", str(CardLogic.fort_state(fort)["line"]), "text"))
	var hours := roundi(float(loot_cfg.get("recover_s", 0.0)) / 3600.0)
	blocks.append(_para("raid", str(c.get("raid_again_fmt", "%d")) % hours if held else str(c.get("raid_take", "")), "select"))
	blocks.append(_para("retreat", str(c.get("retreat_held" if held else "retreat_veis", "")), "text_dim"))
	var warden: Dictionary = fort.get("warden", {})
	var lines := CardLogic.warden_lines(warden)
	blocks.append(_para("warden", str(lines[0]), "text", "mass"))
	for i in range(1, lines.size()):
		var lead := (CardLogic.tell_label(warden) + ": ") if i == 1 else str(c.get("tell_more_prefix", ""))
		blocks.append(_para("tell%d" % i, lead + str(lines[i])))
	if str(fort.get("loot_hint", "")) != "":
		blocks.append(_para("hint", str(c.get("hint_fmt", "%s")) % str(fort["loot_hint"])))
	blocks.append(_para("loot", CardLogic.loot_card_line(fort, loot_cfg)))
	if CardLogic.first_clear_line(fort) != "":
		blocks.append(_para("first_clear", CardLogic.first_clear_line(fort), "select"))
	var threat: Dictionary = fort.get("threat", {})
	var fr := CardLogic.strength_fracs(threat)
	blocks.append(_head("threat_head", str(c.get("threat_head", ""))))
	blocks.append({"kind": "versus", "id": "versus", "text": CardLogic.strength_text(threat), "a": fr[0], "b": fr[1],
		"known": CardLogic.strength_known(threat)})
	blocks.append({"kind": "risk", "id": "risk", "label": str(c.get("risk_label", "")), "chip": CardLogic.risk_chip(threat)})
	var dl := CardLogic.death_lines(backups.get("death", {}))
	for i in dl.size():
		blocks.append(_para("death%d" % i, str(dl[i])))
	blocks.append(_head("matter_head", str(c.get("matter_head", ""))))
	blocks.append(_row("living", "LIVING", MapLogic.fmt_mass(float(fort.get("living", 0.0))), "mass"))
	blocks.append(_row("undead", "UNDEAD", MapLogic.fmt_mass(float(fort.get("undead", 0.0))), "mass"))
	blocks.append(_row("dead", "DEAD", MapLogic.fmt_mass(float(fort.get("dead", 0.0))), "mass"))
	blocks.append(_row("space", "EMPTY", MapLogic.fmt_mass(float(fort.get("space", 0.0))), "mass"))
	blocks.append(_row("war_in", "WAR IN", MapLogic.fmt_rate(float(fort.get("war_in", 0.0))), "rate"))
	blocks.append(_row("ship_in", "LIVING IN", MapLogic.fmt_rate(float(fort.get("ship_in", 0.0))), "rate"))
	return {"title": str(fort.get("name", "")),
		"sub": str(c.get("fort_sub_fmt", "%d %s")) % [int(fort.get("tier", 1)), MapLogic.fmt_mass(float(fort.get("cap", 0.0)))],
		"desc": desc, "blocks": blocks}


## Vei's card: the war at a glance, the fronts, the composition. `party` is view_party().party,
## `names` maps big-undead uids to names. `readout` is MapModel.readout(): the odds, sign and drain
## the top bar and Vei's node also draw (an empty backlog reads "queue empty", not "0s").
static func vei_card(vei: Dictionary, desc: String, party: Array, names: Dictionary, readout: Dictionary) -> Dictionary:
	var c := _c()
	var st := HudLogic.status(readout)
	var sign := int(st["sign"])
	var blocks: Array = []
	blocks.append({"kind": "massline", "id": "backlog", "mass": MapLogic.fmt_mass(float(vei.get("backlog", 0.0))),
		"text": str(c.get("vei_backlog_text", ""))})
	blocks.append(_row("odds", str(c.get("vei_odds_label", "")), str(st["odds_text"]), "mass"))
	blocks.append(_row("sign", str(c.get("vei_sign_label", "")), str(st["sign_text"]), "text"))
	blocks.append(_row("diff", str(c.get("vei_diff_label", "")), MapLogic.fmt_rate(float(vei.get("diff_ema", 0.0))), "rate"))
	blocks.append(_row("drain", str(c.get("vei_drain_label", "")), str(st["drain_text"]), "mass"))
	blocks.append(_head("fronts_head", str(c.get("fronts_head", ""))))
	for r in CardLogic.front_rows(vei.get("fronts", []), names):
		blocks.append({"kind": "front", "id": "front_%s" % r["id"], "name": r["name"], "count": "%s / %s" % [r["have"], r["need"]],
			"mark": r["mark"], "cleared": r["cleared"], "assigned": r["assigned"]})
	blocks.append(_para("fronts_met", CardLogic.fronts_met_text(vei), "text", "mass"))
	blocks.append(_head("composition_head", str(c.get("composition_head", ""))))
	if party.is_empty():
		blocks.append(_para("party_empty", str(c.get("party_empty", "")), "text_dim"))
	var options: Array = [""]
	var labels: Array = [str(c.get("assign_none", "—"))]
	for f in vei.get("fronts", []):
		options.append(str(f["id"]))
		labels.append(CardLogic.front_name(str(f["id"])))
	for m in party:
		blocks.append({"kind": "assign", "id": "assign_%s" % m["uid"], "uid": str(m["uid"]), "name": str(m["name"]),
			"sub": str(c.get("assign_sub_fmt", "%s %s")) % [m.get("kind", ""), m.get("role", "")],
			"selected": str(m.get("front", "")), "options": options, "labels": labels})
	return {"title": "Vei's Domain", "sub": str(c.get("vei_sub", "")), "desc": desc, "blocks": blocks}


## A village's card: its owner in words and the migrants it sends to Covington.
static func village_card(v: Dictionary, desc: String) -> Dictionary:
	var c := _c()
	var owner := str(v.get("owner", "none"))
	return {"title": str(v.get("name", "")), "sub": str(c.get("village_sub_fmt", "%s")) % CardLogic.village_owner_tag(owner),
		"desc": desc, "blocks": [
			_para("owner", CardLogic.village_owner_text(owner)),
			_row("migrants", str(c.get("village_migrants_label", "")), MapLogic.fmt_rate(float(v.get("migrants", 0.0))), "rate"),
		]}
