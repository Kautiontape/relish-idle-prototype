extends PanelContainer
## Top strip. Streams, not stockpiles (law 10): one cell per stream (workers, living, gold, bone,
## bodies), each led by its signed oblique net rate with a sign glyph, then the in/out split, then
## the upright stock with its cap bar and "full in" readout; morale with its factors; the tier and
## what the next one needs; the Return button. A bottleneck line under it names what is stuck. The
## workers cell also names the unspent hands and their best use ("10 idle: build a Forge (+2 jobs)
## or let them muster") next to "→ WAR", and why the town keeps fewer than its steady state.
## All logic is HudModel's; this only lays out labels and reuses them on every bind.

signal command_issued
signal return_pressed
## The relic wall's To the realm: the shell leaves through its one exit (the HUD never finishes the scene itself).
signal realm_pressed


## A thin fill bar: `frac` 0..1 of the track in matter ink; a negative frac (no cap) draws nothing.
## `tick` >= 0 marks a target on the track (morale).
class CapBar:
	extends Control
	var frac := 0.0
	var tick := -1.0
	var ink := "living"

	func _draw() -> void:
		if frac < 0.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ring_track"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(frac, 0.0, 1.0), size.y)), Palette.c(ink))
		if tick >= 0.0:
			var x := size.x * clampf(tick, 0.0, 1.0)
			draw_line(Vector2(x, -2.0), Vector2(x, size.y + 2.0), Palette.c("text"), 2.0)


var _hcfg: Dictionary = {}
var _vcfg: Dictionary = {}
var _bview: Dictionary = {}
var _bcfg: Dictionary = {}
var _idle_cap := 0.0
var _tab := {}  # this bind's BuildSort.tab_suggestion: the idle line and the bottleneck read the same needs and sort
var _cells := {}  # stream id -> {net, name, split, stock, bar}
var _tier: Label
var _next: Label
var _morale_val: Label
var _morale_bar: CapBar
var _morale_line: Label
var _stuck: Label
var _return: Button
var _next_lit := false
var _realm: Button  # the relic wall's route, visible only while the wall is the next-tier line


func _ready() -> void:
	_vcfg = ConfigDb.v("town", "view", {})
	_hcfg = _vcfg.get("hud", {})
	_bview = ConfigDb.data.get("buildings_view", {})
	_bcfg = ConfigDb.data.get("buildings", {})
	_idle_cap = float(ConfigDb.data.get("economy", {}).get("worker", {}).get("idle_cap", 0.0))
	var sb := TownUI.panel_box()
	sb.set_content_margin_all(4)
	add_theme_stylebox_override("panel", sb)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	add_child(rows)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(row)
	for id in _hcfg.get("streams", []):
		row.add_child(_make_cell(String(id)))
	row.add_child(_make_morale())
	row.add_child(_make_tier())
	_return = TownUI.button("Return to the realm")
	_return.custom_minimum_size = Vector2(float(_hcfg.get("return_w_px", 170.0)), TownUI.MIN_TARGET)
	_return.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_return.pressed.connect(func(): return_pressed.emit())
	row.add_child(_return)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	rows.add_child(foot)
	_stuck = _clip(TownUI.label("", 13, "text"))
	_stuck.mouse_filter = Control.MOUSE_FILTER_STOP  # Labels ignore the mouse by default: the tooltip needs it
	foot.add_child(_stuck)
	_next = TownUI.label("", maxi(int(_hcfg.get("next_px", 13)), TownUI.MIN_TEXT), "text_dim")
	_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_child(_next)


func _clip(l: Label) -> Label:
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _make_cell(id: String) -> Control:
	var ink := String((_hcfg.get("ink", {}) as Dictionary).get(id, "text"))
	var text_key := TownModel.float_text_key(ink)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(float(_hcfg.get("cell_w_px", 150.0)), 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = float((_hcfg.get("cell_stretch", {}) as Dictionary).get(id, 1.0))
	col.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var net := TownUI.rate_label("", int(_hcfg.get("net_px", 24)), text_key)
	head.add_child(net)
	var nm := TownUI.label(id, int(_hcfg.get("name_px", 13)), "text_dim")
	nm.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(nm)
	col.add_child(head)
	var split := _clip(TownUI.rate_label("", int(_hcfg.get("split_px", 12)), "text_dim"))
	col.add_child(split)
	var war_row: HBoxContainer = null
	var war_rate: Label = null
	var war_word: Label = null
	var idle_line: RichTextLabel = null
	if id == "workers":  # the surplus past what the town keeps, "+0.07/s → WAR", and the idle hands' best use
		war_row = HBoxContainer.new()
		war_row.add_theme_constant_override("separation", 4)
		war_row.mouse_filter = Control.MOUSE_FILTER_STOP  # the idle line is clipped: its tooltip carries it whole
		war_rate = TownUI.rate_label("", int(_hcfg.get("split_px", 12)), "text_dim")
		war_row.add_child(war_rate)
		war_word = TownUI.label(String((_hcfg.get("text", {}) as Dictionary).get("war", "")), int(_hcfg.get("split_px", 12)), "text_dim")
		war_row.add_child(war_word)
		idle_line = TownUI.parts_label(int(_hcfg.get("split_px", 12)), "text")
		war_row.add_child(idle_line)
		war_row.visible = false
		col.add_child(war_row)
	var stock := _clip(TownUI.label("", int(_hcfg.get("stock_px", 13)), "text"))
	if id == "workers":
		stock.mouse_filter = Control.MOUSE_FILTER_STOP  # clipped with the kept reason: the tooltip carries it whole
	col.add_child(stock)
	var bar := CapBar.new()
	bar.ink = ink
	bar.frac = -1.0
	var bc: Dictionary = _vcfg.get("cap_bar", {})
	bar.custom_minimum_size = Vector2(float(bc.get("w_px", 120.0)), float(bc.get("h_px", 6.0)))
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bar)
	_cells[id] = {"net": net, "split": split, "stock": stock, "bar": bar, "war_row": war_row, "war_rate": war_rate,
		"war_word": war_word, "idle": idle_line}
	return col


func _make_morale() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(float(_hcfg.get("morale_w_px", 340.0)), 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = float(_hcfg.get("morale_stretch", 2.0))
	col.add_theme_constant_override("separation", 0)
	_morale_val = _clip(TownUI.label("", 18, "text"))
	col.add_child(_morale_val)
	_morale_bar = CapBar.new()
	_morale_bar.ink = "living"
	var mb: Dictionary = _hcfg.get("morale_bar", {})
	_morale_bar.custom_minimum_size = Vector2(float(mb.get("w_px", 120.0)), float(mb.get("h_px", 8.0)))
	_morale_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_morale_bar)
	_morale_line = _clip(TownUI.label("", int(_hcfg.get("split_px", 12)), "text_dim"))
	col.add_child(_morale_line)
	return col


func _make_tier() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(float(_hcfg.get("tier_w_px", 100.0)), 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	_tier = TownUI.label("", 20, "text")
	col.add_child(_tier)
	# the relic wall's route sits under the tier name, in the top row's spare height: the strip never grows
	_realm = TownUI.button(String((_hcfg.get("text", {}) as Dictionary).get("next_relics_btn", "")))
	_realm.custom_minimum_size = Vector2(float(_hcfg.get("relic_btn_w_px", 112.0)), maxf(float(_hcfg.get("relic_btn_h_px", 44.0)), TownUI.MIN_TARGET))
	_realm.pressed.connect(func(): realm_pressed.emit())
	_realm.visible = false
	col.add_child(_realm)
	return col


func set_return_enabled(on: bool) -> void:
	_return.disabled = not on


func bind(views: Dictionary) -> void:
	_tab = views.get("tab", {})  # the shell's BuildSort.tab_suggestion, computed once per fetch for every panel
	if _tab.is_empty():
		_tab = BuildSort.tab_suggestion(views, _bview, _bcfg, _vcfg)
	var town: Dictionary = views.get("town", {})
	var hud: Dictionary = views.get("hud", {})
	var rates: Dictionary = views.get("rates", {}).get("rates", {})
	for id in _cells:
		_bind_cell(String(id), _cells[id], town, hud, rates.get(id, {}), views)
	_bind_morale(town)
	_tier.text = String(town.get("tier", "")).capitalize()
	var nl := HudModel.next_line(views, _hcfg, _bview)
	_next.text = String(nl["text"])
	var lit: bool = nl["relics"]  # the relic wall: a lit colour, words not colour alone, and a way out
	if lit != _next_lit:  # a theme override is a relayout: only when the line flips
		_next_lit = lit
		_next.add_theme_color_override("font_color", Palette.c(String(_hcfg.get("relic_ink", "danger")) if lit else "text_dim"))
		_realm.visible = lit
	var stuck := HudModel.bottleneck(views, _vcfg, _bview, _bcfg, _tab)
	_stuck.text = String(_hcfg.get("text", {}).get("stuck_sep", " · ")).join(stuck)
	_stuck.tooltip_text = "\n".join(stuck)  # the line is clipped; the tooltip carries every stuck stream


func _bind_cell(id: String, c: Dictionary, town: Dictionary, hud: Dictionary, flow: Dictionary, views: Dictionary) -> void:
	var hr := BuildSort.hud_rate(hud, id)
	var net := float(hr.get("rate", 0.0))
	c["net"].text = "%s %s" % [HudModel.glyph(net, _hcfg), HudModel.net_text(net, _hcfg)]
	c["net"].modulate.a = 0.6 if HudModel.is_flat(net, _hcfg) else 1.0
	var inn := float(flow.get("in", 0.0))
	var out := float(flow.get("out", 0.0))
	var split := ""
	if id == "workers":
		var w: Dictionary = town.get("workers", {})
		var parts := [["in", inn], ["rot", -float(w.get("rot", out))]]
		if float(w.get("muster", 0.0)) > 0.0:
			parts.append(["muster", -float(w["muster"])])
		split = HudModel.split_text(parts, _hcfg)
		var total := float(w.get("total", 0.0))
		var steady := float(w.get("steady", 0.0))
		var kept := HudModel.kept(town, hud)
		var why := HudModel.kept_reason(town, hud, steady, kept, _idle_cap, _hcfg)  # TODO(api-request #12)
		c["stock"].text = "%d  %s %s%s" % [roundi(total), HudModel.steady_text(kept, _hcfg), HudModel.steady_arrow(total, kept, _hcfg),
			"  (%s)" % why if why != "" else ""]
		c["stock"].tooltip_text = c["stock"].text
		var war := HudModel.surplus_rate(town, steady, kept, _hcfg)
		var idle := HudModel.idle_parts(views, _vcfg, _bview, _bcfg, _tab)
		(c["war_row"] as Control).visible = war > 0.0 or not idle.is_empty()
		(c["war_rate"] as Label).visible = war > 0.0
		(c["war_word"] as Label).visible = war > 0.0
		(c["war_rate"] as Label).text = HudModel.war_text(war, _hcfg)
		TownUI.set_parts(c["idle"], idle)
		(c["idle"] as Control).visible = not idle.is_empty()
		(c["war_row"] as Control).tooltip_text = HudModel.parts_text(idle)
		(c["idle"] as Control).tooltip_text = HudModel.parts_text(idle)
	elif id == "living":
		split = HudModel.split_text([["in", float(town.get("migrants", inn))], ["out", -float(town.get("departures", out))]], _hcfg)
		c["stock"].text = "%d / %d" % [roundi(float(town.get("living", 0.0))), roundi(float(town.get("living_cap", 0.0)))]
	else:
		split = HudModel.split_text([["in", inn], ["out", -out]], _hcfg)
		var stock := float(town.get(id, hr.get("stock", 0.0)))
		var cap := float(hr.get("cap", -1.0))
		if id == "bodies" and cap < 0.0:
			cap = float(town.get("bodies_cap", -1.0))
		var note := HudModel.store_text(stock, cap, net, _hcfg)
		c["stock"].text = "%d%s%s" % [roundi(stock), "" if cap < 0.0 else " / %d" % roundi(cap), "  " + note if note != "" else ""]
		_set_bar(c["bar"], BuildSort.fill(stock, cap), -1.0)
	c["split"].text = split


func _set_bar(bar: CapBar, frac: float, tick: float) -> void:
	if not is_equal_approx(bar.frac, frac) or not is_equal_approx(bar.tick, tick):
		bar.frac = frac
		bar.tick = tick
		bar.queue_redraw()


func _bind_morale(town: Dictionary) -> void:
	var m: Dictionary = town.get("morale", {})
	var tx: Dictionary = _hcfg.get("text", {})
	_morale_val.text = "%s %.2f" % [tx.get("morale", "morale"), float(m.get("value", 0.0))]
	_set_bar(_morale_bar, float(m.get("value", 0.0)), float(m.get("target", 0.0)))
	var line := HudModel.factor_line(m, _hcfg, _bview)
	_morale_line.text = line
	_morale_line.tooltip_text = "%s\n%s" % [BuildSort.fmt(String(tx.get("morale_target", "")), {"v": "%.2f" % float(m.get("target", 0.0))}), line]
	_morale_line.mouse_filter = Control.MOUSE_FILTER_STOP


func on_game_event(_ev: Dictionary) -> void:
	pass
