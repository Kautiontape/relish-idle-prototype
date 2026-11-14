extends VBoxContainer
## Backups tab. Read-only skeleton: vats, phylactery, clones, death outcome (task 7).

signal command_issued


func bind(views: Dictionary) -> void:
	TownUI.clear(self)
	var bk: Dictionary = views.get("backups", {})
	var vats: Array = bk.get("vats", [])
	add_child(TownUI.label("vats %d" % vats.size()))
	for v in vats:
		add_child(TownUI.label("  vat %d    %s    grow %d%%%s" % [
			int(v.get("slot", 0)), "staffed" if v.get("staffed", false) else "unstaffed",
			int(round(float(v.get("grow", 0.0)) * 100.0)), "    ready" if v.get("ready", false) else ""]))
	add_child(TownUI.label("phylactery charges %d" % int(bk.get("phylactery_charges", 0))))
	add_child(TownUI.label("clones ready %d" % int(bk.get("clones_ready", 0))))
	add_child(TownUI.label("death: %s" % String(bk.get("death", {}).get("outcome", ""))))


func on_game_event(_ev: Dictionary) -> void:
	pass
