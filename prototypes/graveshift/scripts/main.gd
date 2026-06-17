extends Node
## Entry point: the yard is the whole prototype.

func _ready() -> void:
	var yard := Yard.new()
	add_child(yard)
