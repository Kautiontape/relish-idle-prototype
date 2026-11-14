extends VBoxContainer
## Stances tab. Read-only skeleton: slots used and one row per stance (task 5 adds toggles).

signal command_issued


func bind(views: Dictionary) -> void:
	TownUI.clear(self)
	var st: Dictionary = views.get("stances", {})
	add_child(TownUI.label("slots %d / %d" % [int(st.get("used", 0)), int(st.get("slots", 0))]))
	var rows: Array = st.get("stances", [])
	if rows.is_empty():
		add_child(TownUI.label("No stances.", 14, "text_dim"))
		return
	for s in rows:
		var on: bool = s.get("on", false)
		var line := "%s    %s    %s" % [String(s.get("id", "")).capitalize(),
			"on" if on else "off", "active" if s.get("active", false) else "idle"]
		add_child(TownUI.label(line, 14, "text" if on else "text_dim"))


func on_game_event(_ev: Dictionary) -> void:
	pass
