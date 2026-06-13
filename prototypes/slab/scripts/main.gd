extends Node
## Entry point: the crypt is the whole prototype.

func _ready() -> void:
	var crypt := Crypt.new()
	add_child(crypt)
