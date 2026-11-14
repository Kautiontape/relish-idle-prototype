extends PanelContainer
## Top strip: tier, bodies, gold and bone against their store caps (a thin fill bar, or "no cap"
## while cap is -1), and the Return button. Caps come from view_hud().rates[].cap (IDLE 6).

signal command_issued
signal return_pressed


## A thin fill bar: `frac` 0..1 of the track in matter ink (gold = living, bone = dead matte).
class CapBar:
	extends Control
	var frac := 0.0
	var ink := "living"

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ring_track"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(frac, 0.0, 1.0), size.y)), Palette.c(ink))


var _tier: Label
var _bodies: Label
var _caps := {}  # "gold"/"bone" -> {label: Label, bar: CapBar}
var _return: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", TownUI.panel_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	_tier = TownUI.label("", 18)
	row.add_child(_tier)
	_bodies = TownUI.label("", 16)
	_bodies.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_bodies)
	var bar_cfg: Dictionary = ConfigDb.v("town", "view", {}).get("cap_bar", {})
	for store in ["gold", "bone"]:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 3)
		var l := TownUI.label("", 16)
		col.add_child(l)
		var bar := CapBar.new()
		bar.ink = String(bar_cfg.get("ink", {}).get(store, "living"))
		bar.custom_minimum_size = Vector2(float(bar_cfg.get("w_px", 120.0)), float(bar_cfg.get("h_px", 6.0)))
		col.add_child(bar)
		row.add_child(col)
		_caps[store] = {"label": l, "bar": bar}
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_return = TownUI.button("Return to the realm")
	_return.custom_minimum_size = Vector2(200, TownUI.MIN_TARGET)
	_return.pressed.connect(func(): return_pressed.emit())
	row.add_child(_return)


func set_return_enabled(on: bool) -> void:
	_return.disabled = not on


func bind(views: Dictionary) -> void:
	var town: Dictionary = views.get("town", {})
	_tier.text = String(town.get("tier", "")).capitalize()
	_bodies.text = "bodies %d" % int(town.get("bodies", 0.0))
	for store in _caps:
		var stock := float(town.get(store, 0.0))
		var f := BuildSort.fill(stock, float(BuildSort.hud_rate(views.get("hud", {}), store).get("cap", -1.0)))
		var cap: Dictionary = _caps[store]
		var cap_v := float(BuildSort.hud_rate(views.get("hud", {}), store).get("cap", -1.0))
		if f < 0.0:
			cap["label"].text = "%s %d  no cap" % [store, int(stock)]
		else:
			cap["label"].text = "%s %d / %d%s" % [store, int(stock), int(cap_v), "  full" if f >= 1.0 else ""]
		cap["bar"].visible = f >= 0.0
		if f >= 0.0 and not is_equal_approx(cap["bar"].frac, f):
			cap["bar"].frac = f
			cap["bar"].queue_redraw()


func on_game_event(_ev: Dictionary) -> void:
	pass
