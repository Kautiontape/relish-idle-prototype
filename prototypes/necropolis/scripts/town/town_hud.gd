extends PanelContainer
## Top strip. Placeholder (task 8 fills it): tier, gold/bone/bodies stocks, Return button.

signal command_issued
signal return_pressed

var _tier: Label
var _stocks: Label
var _return: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", TownUI.panel_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	_tier = TownUI.label("", 18)
	row.add_child(_tier)
	_stocks = TownUI.label("", 16)
	_stocks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stocks.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_stocks)
	_return = TownUI.button("Return to the realm")
	_return.custom_minimum_size = Vector2(200, TownUI.MIN_TARGET)
	_return.pressed.connect(func(): return_pressed.emit())
	row.add_child(_return)


func set_return_enabled(on: bool) -> void:
	_return.disabled = not on


func bind(views: Dictionary) -> void:
	var town: Dictionary = views.get("town", {})
	_tier.text = String(town.get("tier", "")).capitalize()
	_stocks.text = "gold %d    bone %d    bodies %d" % [
		int(town.get("gold", 0.0)), int(town.get("bone", 0.0)), int(town.get("bodies", 0.0))]


func on_game_event(_ev: Dictionary) -> void:
	pass
