extends VBoxContainer
## Build tab. Read-only skeleton: one row per catalog building (task 4 adds the interactions).

signal command_issued


func bind(views: Dictionary) -> void:
	TownUI.clear(self)
	var rows: Array = views.get("catalog", {}).get("buildings", [])
	if rows.is_empty():
		add_child(TownUI.label("No buildings.", 14, "text_dim"))
		return
	for b in rows:
		var cost: Dictionary = b.get("cost", {})
		var ok: bool = b.get("can_build", false)
		var tail := "can build" if ok else String(b.get("reason", ""))
		var line := "%s    %d gold / %d bone / %d relics    %s" % [
			String(b.get("building_id", "")).capitalize(), int(cost.get("gold", 0.0)),
			int(cost.get("bone", 0.0)), int(cost.get("relics", 0)), tail]
		add_child(TownUI.label(line, 14, "text" if ok else "text_dim"))


func on_game_event(_ev: Dictionary) -> void:
	pass
