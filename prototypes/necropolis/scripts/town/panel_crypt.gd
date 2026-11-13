extends VBoxContainer
## Crypt tab. Read-only skeleton: Relish home, husks, remnants, big undead (task 6).

signal command_issued


func bind(views: Dictionary) -> void:
	TownUI.clear(self)
	var home: bool = views.get("town", {}).get("relish_home", false)
	add_child(TownUI.label("Relish is %s" % ("home" if home else "away"), 14, "text" if home else "text_dim"))
	var inv: Dictionary = views.get("inventory", {})
	add_child(TownUI.label("husks %d    remnants %d" % [inv.get("husks", []).size(), inv.get("remnants", []).size()]))
	var bu: Array = views.get("big_undead", {}).get("big_undead", [])
	if bu.is_empty():
		add_child(TownUI.label("No big undead.", 14, "text_dim"))
		return
	for u in bu:
		add_child(TownUI.label("%s    %s" % [String(u.get("name", "")), String(u.get("place", ""))]))


func on_game_event(_ev: Dictionary) -> void:
	pass
