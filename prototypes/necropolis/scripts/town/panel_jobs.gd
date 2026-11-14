extends VBoxContainer
## Jobs tab. Read-only skeleton: the ladder order with staffed/slots (task 5 adds the interactions).

signal command_issued


func bind(views: Dictionary) -> void:
	TownUI.clear(self)
	var town: Dictionary = views.get("town", {})
	var ladder: Array = town.get("ladder", [])
	var by_id := {}
	for j in town.get("jobs", []):
		by_id[String(j.get("id", ""))] = j
	if ladder.is_empty():
		add_child(TownUI.label("No jobs.", 14, "text_dim"))
		return
	var n := 0
	for id in ladder:
		n += 1
		var j: Dictionary = by_id.get(String(id), {})
		add_child(TownUI.label("%d. %s    %.1f / %d" % [
			n, String(id).capitalize(), float(j.get("staffed", 0.0)), int(j.get("slots", 0))]))


func on_game_event(_ev: Dictionary) -> void:
	pass
