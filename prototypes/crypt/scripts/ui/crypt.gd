class_name Crypt
extends Control
## Mobile-first command center, designed at phone-logical 400x866. Bottom tabs
## (Horde / Build / Maw / Vei) so each screen breathes. The horde is a grid of
## self-describing tokens (tier ring + counter badge + tag stripe — no hover, so
## it reads on a thumb). Tap a token to select; a contextual bar shows one unit's
## detail or bulk actions for many. An always-on strip reads Vei coverage at a
## glance. Tools get the care; raid/Vei crude; town/loadouts faked.

const W := 400
const H := 866
const PAGE_TOP := 44
const TABBAR_H := 76
const TABS := ["missions", "horde", "build", "maw"]
const TAB_LABEL := {"missions": "Missions", "horde": "Horde", "build": "Build", "maw": "Maw"}
const SORT_ORDER := ["mission", "power", "role", "aspect", "tag", "newest"]
const TAG_PALETTE := ["#cf6f6f", "#6f9fcf", "#cfb86f", "#9f6fcf", "#6fcf9f", "#cf9f6f"]
const ABBR := {"power": "PW", "beef": "BF", "speed": "SP", "wits": "WT", "charm": "CH", "dread": "DR", "magic": "MG", "persistence": "PS"}
const COMP_STATS := ["wits", "dread", "beef", "power"]
const COMP_DISPLAY_MAX := 50.0
const ROLE_ABBR := {"Brawler": "BRA", "Bulwark": "BUL", "Skirmisher": "SKR", "Stalker": "STK", "Charmer": "CHM", "Terror": "TER", "Hexer": "HEX", "Undying": "UND", "Hollow": "HOL"}

var active_tab := "horde"
var sort_key := "power"
var filter_kind := ""
var filter_value := ""
var selected := {}
var build := BuildState.new()
var _picking := -1
var _reveal := false

var status_label: Label
var pages := {}
var tab_btns := {}
var missions_body: VBoxContainer
var muster_banner: Panel
var muster_label: Label
var auto_fill_btn: Button
var leave_btn: Button
var comp_strip: HBoxContainer
var sort_btn: Button
var filter_flow: HBoxContainer
var grid_flow: HFlowContainer
var send_btn: Button
var ctx_bar: Panel
var ctx_label: Label
var ctx_tag_btn: Button
var ctx_shred_btn: Button
var _token_of := {}
var bld_forms: HFlowContainer
var bld_slots: HFlowContainer
var bld_preview: Label
var bld_raise: Button
var rem_picker: Panel
var rem_list: VBoxContainer
var maw_fill: ColorRect
var maw_stock: Label
var maw_result: Label
var vei_body: VBoxContainer
var raid_panel: Panel
var raid_body: VBoxContainer
var tag_panel: Panel
var tag_chips: HFlowContainer
var tag_new_edit: LineEdit
var end_panel: Panel
var end_body: VBoxContainer
var dbg_panel: Panel

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.065, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_topbar()
	for id in TABS:
		var p := Control.new()
		p.position = Vector2(0, PAGE_TOP)
		p.size = Vector2(W, H - PAGE_TOP - TABBAR_H)
		add_child(p)
		pages[id] = p
	# Vei has her own page, reached from the Missions board as a capstone card —
	# not a peer tab. Keeps the tab bar a clean Missions / Horde / Build / Maw.
	var vp := Control.new()
	vp.position = Vector2(0, PAGE_TOP)
	vp.size = Vector2(W, H - PAGE_TOP - TABBAR_H)
	add_child(vp)
	pages["vei"] = vp
	_build_missions_page()
	_build_horde_page()
	_build_build_page()
	_build_maw_page()
	_build_vei_page()
	_build_tabbar()
	_build_rem_picker()
	_build_raid_panel()
	_build_tag_panel()
	_build_end_panel()
	_build_debug()

	GameState.horde_changed.connect(func(): _refresh())
	GameState.materials_changed.connect(func(): _refresh())
	ConfigDb.value_changed.connect(func(_f, _k, _v): _refresh())
	_set_tab("missions")

# ---------- top bar + tab bar ----------

func _build_topbar() -> void:
	status_label = Label.new()
	status_label.position = Vector2(56, 10)
	status_label.size = Vector2(W - 64, 28)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.88))
	add_child(status_label)
	var dbg := _btn("dbg", Vector2(46, 30), func(): dbg_panel.visible = not dbg_panel.visible)
	dbg.position = Vector2(6, 8)
	dbg.add_theme_font_size_override("font_size", 12)
	add_child(dbg)

func _build_tabbar() -> void:
	var y := H - TABBAR_H
	var bar := ColorRect.new()
	bar.color = Color(0.1, 0.1, 0.14)
	bar.position = Vector2(0, y)
	bar.size = Vector2(W, TABBAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var bw := W / float(TABS.size())
	for i in TABS.size():
		var id: String = TABS[i]
		var b := _btn(TAB_LABEL[id], Vector2(bw - 6, TABBAR_H - 12), _set_tab.bind(id))
		b.position = Vector2(i * bw + 3, y + 6)
		b.add_theme_font_size_override("font_size", 18)
		tab_btns[id] = b
		add_child(b)

func _set_tab(id: String) -> void:
	active_tab = id
	for k in pages:
		pages[k].visible = (k == id)
	for k in tab_btns:
		var b: Button = tab_btns[k]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.27, 0.31, 0.42) if k == id else Color(0.14, 0.14, 0.18)
		sb.set_corner_radius_all(8)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
	_refresh()

# ---------- missions page (home) ----------

func _build_missions_page() -> void:
	var p: Control = pages["missions"]
	# Always-on Vei readiness glance — the meter you're climbing — lives on the
	# home screen, right above the capstone card.
	comp_strip = HBoxContainer.new()
	comp_strip.position = Vector2(10, 4)
	comp_strip.add_theme_constant_override("separation", 6)
	p.add_child(comp_strip)
	p.add_child(_section_label("CHOOSE A MISSION — bring the right dead, claim the spoils", Vector2(12, 52)))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 76)
	scroll.size = Vector2(W - 16, H - PAGE_TOP - TABBAR_H - 84)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	missions_body = VBoxContainer.new()
	missions_body.custom_minimum_size = Vector2(W - 24, 0)
	missions_body.add_theme_constant_override("separation", 10)
	scroll.add_child(missions_body)

func _refresh_missions() -> void:
	for c in missions_body.get_children():
		c.queue_free()
	var comp := GameState.composition()
	for m in GameState.mission_board:
		missions_body.add_child(_mission_card(m, comp))
	missions_body.add_child(_vei_card())

func _mission_card(m: Dictionary, _comp: Dictionary) -> Button:
	var th: Dictionary = m["threat"]
	var diff: Dictionary = m["difficulty"]
	var reward: Dictionary = m["reward"]
	var cs := String(th["counter_stat"])
	var card := _btn("", Vector2(W - 24, 116), _choose_mission.bind(m))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.16)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = _diff_color(String(diff["id"]))
	for st in ["normal", "hover", "pressed"]:
		card.add_theme_stylebox_override(st, sb)
	_card_label(card, "%s — %s" % [String(diff["label"]), String(th["desc"])], Vector2(12, 8), 17, Color(0.92, 0.86, 0.72))
	_card_label(card, "Demands: %s" % _counter_word(th), Vector2(12, 36), 13, Color(0.66, 0.78, 0.9))
	# Readiness = the strength of the BEST party you could field (top jar units by
	# this counter), not the whole horde — that's the number you actually deploy.
	var have := _best_party_strength(cs)
	var tgt := float(ConfigDb.v("missions", "readiness_soft_target"))
	var rcol := Color(0.55, 0.85, 0.55) if have >= tgt else (Color(0.9, 0.8, 0.45) if have >= tgt * 0.5 else Color(0.9, 0.5, 0.45))
	_card_label(card, "Best party %s: %d" % [cs, int(have)], Vector2(12, 58), 13, rcol)
	_card_label(card, "Spoils: %s    ·    danger %s" % [String(reward["hint"]), _danger_pips(diff)], Vector2(12, 82), 13, Color(0.78, 0.74, 0.6))
	return card

func _vei_card() -> Button:
	var res := CombatSim.resolve_vei(GameState.horde)
	var card := _btn("", Vector2(W - 24, 80), func(): _set_tab("vei"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.13, 0.22)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.62, 0.5, 0.74)
	for st in ["normal", "hover", "pressed"]:
		card.add_theme_stylebox_override(st, sb)
	_card_label(card, "⚑ CHALLENGE VEI — the crypt is yours if she falls", Vector2(12, 10), 15, Color(0.9, 0.84, 0.95))
	_card_label(card, "Your horde covers %d of her %d needed fronts." % [int(res["met"]), int(res["need"])], Vector2(12, 40), 13, Color(0.78, 0.74, 0.85))
	return card

func _choose_mission(m: Dictionary) -> void:
	GameState.active_mission = m
	sort_key = "mission"
	selected.clear()
	_set_tab("horde")

func _diff_color(id: String) -> Color:
	match id:
		"scout": return Color(0.5, 0.75, 0.55)
		"siege": return Color(0.85, 0.5, 0.45)
		_: return Color(0.62, 0.64, 0.72)

func _danger_pips(diff: Dictionary) -> String:
	var lm := float(diff["loss_mult"])
	if lm <= 0.7:
		return "low"
	if lm >= 1.4:
		return "HIGH"
	return "med"

## Strength of the best legal party (top jar_size units) for a counter-stat.
func _best_party_strength(counter_stat: String) -> float:
	var vals: Array = []
	for u in GameState.horde:
		vals.append(float(u["power"]) if counter_stat == "power" else float(u["stats"].get(counter_stat, 0.0)))
	vals.sort()
	vals.reverse()
	var s := 0.0
	for i in mini(GameState.jar_size(), vals.size()):
		s += float(vals[i])
	return s

func _card_label(card: Control, text: String, pos: Vector2, sz: int, col: Color) -> void:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(card.custom_minimum_size.x - pos.x - 8, sz + 10)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.text = text
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(l)

# ---------- muster (horde tab, scoped to the chosen mission) ----------

func _refresh_muster() -> void:
	var m: Dictionary = GameState.active_mission
	if m.is_empty():
		muster_label.text = "No mission chosen. Tap a unit to inspect it, or pick a mission on the Missions tab to deploy."
		auto_fill_btn.disabled = true
		leave_btn.disabled = true
		return
	var th: Dictionary = m["threat"]
	muster_label.text = "MUSTER: %s — bring %s · jar %d · spoils %s" % [String(th["desc"]), String(th["counter_stat"]), GameState.jar_size(), String(m["reward"]["hint"])]
	auto_fill_btn.disabled = false
	leave_btn.disabled = false

## Select the best party for the active mission's counter-stat (power as tiebreak).
func _auto_fill() -> void:
	if GameState.active_mission.is_empty():
		return
	var cs := String(GameState.active_mission["threat"]["counter_stat"])
	var units: Array = GameState.horde.duplicate()
	units.sort_custom(func(a, b):
		var av: float = float(a["power"]) if cs == "power" else float(a["stats"].get(cs, 0.0))
		var bv: float = float(b["power"]) if cs == "power" else float(b["stats"].get(cs, 0.0))
		if av == bv:
			return float(a["power"]) > float(b["power"])
		return av > bv)
	selected.clear()
	for i in mini(GameState.jar_size(), units.size()):
		selected[int(units[i]["id"])] = true
	_refresh()

func _leave_muster() -> void:
	GameState.active_mission = {}
	sort_key = "power"
	selected.clear()
	_set_tab("missions")

# ---------- horde page ----------

func _build_horde_page() -> void:
	var p: Control = pages["horde"]
	# Muster banner — the mission you're fielding (chosen on the Missions tab),
	# with AUTO-FILL (best party for its counter-stat) and a way to back out.
	muster_banner = Panel.new()
	muster_banner.position = Vector2(8, 2)
	muster_banner.size = Vector2(W - 16, 46)
	var mbsb := StyleBoxFlat.new()
	mbsb.bg_color = Color(0.17, 0.12, 0.12)
	mbsb.set_corner_radius_all(8)
	mbsb.border_color = Color(0.62, 0.42, 0.36)
	mbsb.set_border_width_all(2)
	muster_banner.add_theme_stylebox_override("panel", mbsb)
	p.add_child(muster_banner)
	muster_label = Label.new()
	muster_label.position = Vector2(8, 3)
	muster_label.size = Vector2(W - 16 - 148, 42)
	muster_label.add_theme_font_size_override("font_size", 12)
	muster_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.74))
	muster_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	muster_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	muster_banner.add_child(muster_label)
	auto_fill_btn = _btn("AUTO-FILL", Vector2(92, 36), _auto_fill)
	auto_fill_btn.position = Vector2(W - 16 - 140, 5)
	auto_fill_btn.add_theme_font_size_override("font_size", 13)
	muster_banner.add_child(auto_fill_btn)
	leave_btn = _btn("✕", Vector2(38, 36), _leave_muster)
	leave_btn.position = Vector2(W - 16 - 44, 5)
	muster_banner.add_child(leave_btn)

	sort_btn = _btn("Sort: power", Vector2(106, 32), _cycle_sort)
	sort_btn.position = Vector2(10, 52)
	sort_btn.add_theme_font_size_override("font_size", 13)
	p.add_child(sort_btn)
	var selall := _btn("Sel all", Vector2(64, 32), _select_shown)
	selall.position = Vector2(120, 52)
	selall.add_theme_font_size_override("font_size", 12)
	p.add_child(selall)
	var fscroll := ScrollContainer.new()
	fscroll.position = Vector2(190, 52)
	fscroll.size = Vector2(W - 200, 34)
	fscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(fscroll)
	filter_flow = HBoxContainer.new()
	filter_flow.add_theme_constant_override("separation", 5)
	fscroll.add_child(filter_flow)

	var gscroll := ScrollContainer.new()
	gscroll.position = Vector2(8, 92)
	gscroll.size = Vector2(W - 16, 538)
	gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(gscroll)
	grid_flow = HFlowContainer.new()
	grid_flow.custom_minimum_size = Vector2(W - 24, 0)
	grid_flow.add_theme_constant_override("h_separation", 6)
	grid_flow.add_theme_constant_override("v_separation", 6)
	gscroll.add_child(grid_flow)

	ctx_bar = Panel.new()
	ctx_bar.position = Vector2(10, 636)
	ctx_bar.size = Vector2(W - 20, 110)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.12, 0.13, 0.17)
	csb.set_corner_radius_all(10)
	csb.border_color = Color(0.3, 0.5, 0.72)
	csb.set_border_width_all(2)
	ctx_bar.add_theme_stylebox_override("panel", csb)
	p.add_child(ctx_bar)
	ctx_label = Label.new()
	ctx_label.position = Vector2(12, 6)
	ctx_label.size = Vector2(W - 32, 52)
	ctx_label.add_theme_font_size_override("font_size", 12)
	ctx_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.92))
	ctx_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	ctx_bar.add_child(ctx_label)
	var crow := HBoxContainer.new()
	crow.position = Vector2(12, 60)
	crow.add_theme_constant_override("separation", 6)
	ctx_bar.add_child(crow)
	send_btn = _btn("SEND", Vector2(116, 40), _send_party)
	send_btn.add_theme_font_size_override("font_size", 17)
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.5, 0.22, 0.2)
	ssb.set_corner_radius_all(8)
	for st in ["normal", "hover", "pressed"]:
		send_btn.add_theme_stylebox_override(st, ssb)
	crow.add_child(send_btn)
	ctx_tag_btn = _btn("Tag", Vector2(66, 40), _open_tag_picker)
	crow.add_child(ctx_tag_btn)
	ctx_shred_btn = _btn("Shred", Vector2(78, 40), _shred_selected)
	ctx_shred_btn.add_theme_color_override("font_color", Color(0.95, 0.6, 0.5))
	crow.add_child(ctx_shred_btn)
	crow.add_child(_btn("Clear", Vector2(62, 40), _clear_select))

func _refresh_comp() -> void:
	for c in comp_strip.get_children():
		c.queue_free()
	var comp := GameState.composition()
	for s in COMP_STATS:
		var v: float = float(comp["total_power"]) if s == "power" else float(comp["counter"][s])
		comp_strip.add_child(_comp_gauge(s, v))

func _comp_gauge(stat: String, value: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(89, 42)
	var l := Label.new()
	l.size = Vector2(89, 18)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.72, 0.74, 0.82))
	l.text = "%s %d" % [ABBR[stat], int(value)]
	c.add_child(l)
	var bgr := ColorRect.new()
	bgr.color = Color(0.16, 0.16, 0.2)
	bgr.position = Vector2(0, 22)
	bgr.size = Vector2(89, 10)
	c.add_child(bgr)
	var fill := ColorRect.new()
	fill.color = _aspect_color(Loot.ASPECT_OF_STAT[stat])
	fill.position = Vector2(0, 22)
	fill.size = Vector2(89.0 * clampf(value / COMP_DISPLAY_MAX, 0.0, 1.0), 10)
	c.add_child(fill)
	return c

func _refresh_filters() -> void:
	for c in filter_flow.get_children():
		c.queue_free()
	filter_flow.add_child(_chip("All", filter_kind == "", _set_filter.bind("", "")))
	var comp := GameState.composition()
	var roles: Array = (comp["by_role"] as Dictionary).keys()
	roles.sort()
	for r in roles:
		var active: bool = filter_kind == "role" and filter_value == String(r)
		filter_flow.add_child(_chip("%s %d" % [r, int(comp["by_role"][r])], active, _set_filter.bind("role", String(r))))
	var present := {}
	for u in GameState.horde:
		for t in u["tags"]:
			present[t] = true
	for t in present.keys():
		var td := GameState.tag_def(String(t))
		var active2: bool = filter_kind == "tag" and filter_value == String(t)
		var chip := _chip("#" + String(td["label"]), active2, _set_filter.bind("tag", String(t)))
		chip.add_theme_color_override("font_color", Color(String(td["color"])))
		filter_flow.add_child(chip)

func _cycle_sort() -> void:
	var i := SORT_ORDER.find(sort_key)
	sort_key = SORT_ORDER[(i + 1) % SORT_ORDER.size()]
	sort_btn.text = "Sort: " + sort_key
	_refresh_grid()

func _set_filter(kind: String, value: String) -> void:
	if filter_kind == kind and filter_value == value:
		filter_kind = ""
		filter_value = ""
	else:
		filter_kind = kind
		filter_value = value
	_refresh_filters()
	_refresh_grid()

func _visible_units() -> Array:
	var out: Array = []
	for u in GameState.horde:
		if _passes_filter(u):
			out.append(u)
	out.sort_custom(_sorter)
	return out

func _passes_filter(u: Dictionary) -> bool:
	match filter_kind:
		"role": return String(u["role"]) == filter_value
		"tag": return filter_value in u["tags"]
		_: return true

func _sorter(a: Dictionary, b: Dictionary) -> bool:
	match sort_key:
		"mission":
			var cs := ""
			if not GameState.active_mission.is_empty():
				cs = String(GameState.active_mission["threat"]["counter_stat"])
			if cs == "":
				return float(a["power"]) > float(b["power"])
			var av: float = float(a["power"]) if cs == "power" else float(a["stats"].get(cs, 0.0))
			var bv: float = float(b["power"]) if cs == "power" else float(b["stats"].get(cs, 0.0))
			if av == bv:
				return float(a["power"]) > float(b["power"])
			return av > bv
		"role":
			if String(a["role"]) == String(b["role"]):
				return float(a["power"]) > float(b["power"])
			return String(a["role"]) < String(b["role"])
		"power": return float(a["power"]) > float(b["power"])
		"aspect":
			if String(a["aspect"]) == String(b["aspect"]):
				return float(a["power"]) > float(b["power"])
			return String(a["aspect"]) < String(b["aspect"])
		"tag":
			var at: String = String(a["tags"][0]) if not (a["tags"] as Array).is_empty() else "~"
			var bt: String = String(b["tags"][0]) if not (b["tags"] as Array).is_empty() else "~"
			return at < bt
		_: return int(a["id"]) > int(b["id"])

func _refresh_grid() -> void:
	_prune_selected()
	sort_btn.text = "Sort: " + sort_key
	for c in grid_flow.get_children():
		c.queue_free()
	_token_of.clear()
	for u in _visible_units():
		grid_flow.add_child(_make_token(u))

func _make_token(u: Dictionary) -> Button:
	var id := int(u["id"])
	var btn := _btn("", Vector2(84, 92), _toggle_select.bind(id))
	var hollow := String(u["tier"]) == "Hollow"
	# role hat (non-Hollow only): a colored bar + 3-letter role. This is the
	# combat/town surface — every role is combat for now; town roles land here.
	if not hollow:
		var hat := ColorRect.new()
		hat.color = _aspect_color(String(u["aspect"]))
		hat.position = Vector2(2, 2)
		hat.size = Vector2(80, 14)
		hat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(hat)
		var rl := Label.new()
		rl.position = Vector2(2, 0)
		rl.size = Vector2(80, 16)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rl.add_theme_font_size_override("font_size", 11)
		rl.add_theme_color_override("font_color", Color(0.08, 0.07, 0.1))
		rl.text = ROLE_ABBR.get(String(u["role"]), String(u["role"]).substr(0, 3).to_upper())
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(rl)
	var icon := _icon("res://assets/icons/%s.svg" % String(u["form_id"]), Vector2(23, 18), Vector2(38, 38), _aspect_color(String(u["aspect"])))
	btn.add_child(icon)
	var bd := _badge_for(u)
	if String(bd["text"]) != "":
		var bl := Label.new()
		bl.position = Vector2(5, 60)
		bl.add_theme_font_size_override("font_size", 13)
		bl.add_theme_color_override("font_color", bd["color"])
		bl.text = String(bd["text"])
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(bl)
	var pl := Label.new()
	pl.position = Vector2(48, 60)
	pl.size = Vector2(32, 16)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pl.add_theme_font_size_override("font_size", 12)
	pl.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
	pl.text = "p%d" % int(u["power"])
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(pl)
	var tags: Array = u["tags"]
	for i in mini(tags.size(), 5):
		var seg := ColorRect.new()
		seg.color = Color(String(GameState.tag_def(String(tags[i]))["color"]))
		seg.position = Vector2(5 + i * 15, 80)
		seg.size = Vector2(13, 6)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(seg)
	_token_of[id] = btn
	_restyle_token(btn, u)
	return btn

func _token_badge(u: Dictionary) -> String:
	var best := ""
	var bv := 0.0
	for s in Loot.STATS:
		if float(u["stats"][s]) > bv:
			bv = float(u["stats"][s])
			best = s
	return "%s%d" % [ABBR[best], int(bv)] if best != "" else ""

## The token's stat badge. In muster it shows the MISSION's counter-stat (gold),
## so the value you're shopping for is on every token; otherwise the dominant stat.
func _badge_for(u: Dictionary) -> Dictionary:
	if not GameState.active_mission.is_empty():
		var cs := String(GameState.active_mission["threat"]["counter_stat"])
		if cs != "power":
			return {"text": "%s%d" % [ABBR[cs], int(u["stats"].get(cs, 0))], "color": Color(1.0, 0.85, 0.4)}
	return {"text": _token_badge(u), "color": Color(0.92, 0.88, 0.7)}

func _restyle_token(btn: Button, u: Dictionary) -> void:
	var sel := selected.has(int(u["id"]))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.15, 0.2) if sel else Color(0.1, 0.1, 0.13)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3 if sel else 2)
	sb.border_color = Color(0.3, 0.9, 1.0) if sel else _tier_color(String(u["tier"]))
	for st in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(st, sb)

func _toggle_select(id: int) -> void:
	if selected.has(id):
		selected.erase(id)
	else:
		selected[id] = true
	var u := _unit_by_id(id)
	if _token_of.has(id) and not u.is_empty():
		_restyle_token(_token_of[id], u)
	_refresh_ctx()

func _refresh_ctx() -> void:
	var n := selected.size()
	var jar := GameState.jar_size()
	var has_m := not GameState.active_mission.is_empty()
	send_btn.disabled = not (has_m and n >= 1 and n <= jar)
	ctx_tag_btn.disabled = n == 0
	ctx_shred_btn.disabled = n == 0
	send_btn.text = "SEND %d" % n if (has_m and n >= 1 and n <= jar) else "SEND"
	if n == 0:
		if has_m:
			ctx_label.text = "Muster a party for %s.\nTap up to %d undead, or AUTO-FILL." % [String(GameState.active_mission["threat"]["desc"]), jar]
		else:
			ctx_label.text = "Tap one unit to inspect its full stats.\nChoose a mission (Missions tab) to deploy a party."
		return
	# One selected → inspect: the full stat line you couldn't read before.
	if n == 1:
		var u := _unit_by_id(int(selected.keys()[0]))
		if not u.is_empty():
			ctx_label.text = "%s · %s\n%s%s" % [String(u["name"]), String(u["role"]), _stat_line(u), _echoes_line(u)]
			return
	var units: Array = []
	for id in selected.keys():
		var u2 := _unit_by_id(int(id))
		if not u2.is_empty():
			units.append(u2)
	var cm := Horde.composition(units)
	var co: Dictionary = cm["counter"]
	var head := "Party %d/%d" % [n, jar] if n <= jar else "Party %d/%d — too many" % [n, jar]
	ctx_label.text = "%s · %s\npower %d · WT %d · DR %d · BF %d" % [head, _role_summary(cm["by_role"]), int(cm["total_power"]), int(co["wits"]), int(co["dread"]), int(co["beef"])]

## The full stat readout for one unit — every nonzero stat, not just the badge.
func _stat_line(u: Dictionary) -> String:
	var parts: Array = []
	for s in Loot.STATS:
		var v := int(u["stats"][s])
		if v > 0:
			parts.append("%s %d" % [ABBR[s], v])
	var body := " · ".join(parts) if not parts.is_empty() else "no stats (Hollow)"
	return "p%d %s · %s" % [int(u["power"]), String(u["tier"]), body]

func _echoes_line(u: Dictionary) -> String:
	var ech: Dictionary = u.get("echoes", {})
	if ech.is_empty():
		return ""
	var parts: Array = []
	for k in ech:
		parts.append("%s %d" % [_echo_name(String(k)), int(ech[k])])
	return "\n+ " + ", ".join(parts)

func _echo_name(id: String) -> String:
	for side in ["combat", "town"]:
		var d: Dictionary = ConfigDb.data["echoes"][side]
		if d.has(id):
			return String(d[id]["name"])
	return id

func _role_summary(by_role: Dictionary) -> String:
	var arr: Array = by_role.keys()
	arr.sort_custom(func(a, b): return int(by_role[a]) > int(by_role[b]))
	var parts: Array = []
	for i in mini(arr.size(), 3):
		parts.append("%d %s" % [int(by_role[arr[i]]), arr[i]])
	return ", ".join(parts)

func _select_clear_on_act() -> void:
	selected.clear()
	_refresh()

func _clear_select() -> void:
	selected.clear()
	_refresh()

func _shred_selected() -> void:
	var ids := selected.keys()
	if ids.is_empty():
		return
	var fill := GameState.shred_units(ids)
	selected.clear()
	maw_result.text = "Fed %d to the Maw  (+%d fullness)." % [ids.size(), fill]

# ---------- build page ----------

func _build_build_page() -> void:
	var p: Control = pages["build"]
	p.add_child(_section_label("KIT A CHAMPION — 1 · pick a form", Vector2(12, 12)))
	bld_forms = HFlowContainer.new()
	bld_forms.position = Vector2(10, 36)
	bld_forms.custom_minimum_size = Vector2(W - 20, 36)
	bld_forms.add_theme_constant_override("h_separation", 6)
	bld_forms.add_theme_constant_override("v_separation", 6)
	p.add_child(bld_forms)
	p.add_child(_section_label("2 · tap a slot, fill it (aspect-gated)", Vector2(12, 120)))
	bld_slots = HFlowContainer.new()
	bld_slots.position = Vector2(12, 144)
	bld_slots.custom_minimum_size = Vector2(W - 24, 70)
	bld_slots.add_theme_constant_override("h_separation", 12)
	bld_slots.add_theme_constant_override("v_separation", 12)
	p.add_child(bld_slots)
	bld_preview = Label.new()
	bld_preview.position = Vector2(12, 556)
	bld_preview.size = Vector2(W - 24, 62)
	bld_preview.autowrap_mode = TextServer.AUTOWRAP_WORD
	bld_preview.add_theme_font_size_override("font_size", 16)
	bld_preview.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
	p.add_child(bld_preview)
	bld_raise = _btn("Raise this champion", Vector2(W - 20, 66), _do_kit)
	bld_raise.position = Vector2(10, 628)
	bld_raise.add_theme_font_size_override("font_size", 18)
	p.add_child(bld_raise)

func _refresh_build() -> void:
	for c in bld_forms.get_children():
		c.queue_free()
	var counts := {}
	for id in GameState.forms:
		counts[id] = int(counts.get(id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort()
	for id in ids:
		var active: bool = build.form_id == String(id)
		bld_forms.add_child(_chip("%s x%d" % [String(ConfigDb.husk(id)["name"]), int(counts[id])], active, _pick_form.bind(String(id))))
	for c in bld_slots.get_children():
		c.queue_free()
	if not build.has_form():
		bld_preview.text = "pick a form to begin"
		bld_raise.disabled = true
	else:
		for i in build.slots.size():
			bld_slots.add_child(_slot_circle(i))
		var d := build.derived()
		bld_preview.text = "-> %s  ·  %s  ·  power %d" % [String(d["name"]), String(d["role"]), int(Horde.power_of(d["stats"], d["echoes"]))]
		bld_raise.disabled = false

func _slot_circle(i: int) -> Button:
	var slot: Dictionary = build.slots[i]
	var aspect: String = slot["aspect"]
	var filled: bool = not (slot["remnant"] as Dictionary).is_empty()
	var b := _btn("", Vector2(64, 64), _slot_tap.bind(i))
	var col := _aspect_color(aspect)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(32)
	sb.set_border_width_all(3)
	sb.border_color = col
	sb.bg_color = Loot.rarity_color(slot["remnant"]["rarity"]).darkened(0.25) if filled else col.darkened(0.7)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_font_size_override("font_size", 14)
	if filled:
		b.text = "%s%d" % [ABBR[slot["remnant"]["stat"]], int(slot["remnant"]["magnitude"])]
	else:
		b.text = aspect.substr(0, 2).to_upper()
	return b

func _slot_tap(i: int) -> void:
	var slot: Dictionary = build.slots[i]
	if not (slot["remnant"] as Dictionary).is_empty():
		build.unslot(i)
		_refresh_build()
	else:
		_open_rem_picker(i)

func _pick_form(id: String) -> void:
	build.place_form(id)
	_refresh_build()

func _do_kit() -> void:
	if not build.has_form():
		return
	GameState.raise_kitted(build.form_id, build.slotted())
	build.clear()
	maw_result.text = "A champion rises."
	_refresh()

func _build_rem_picker() -> void:
	rem_picker = _overlay_panel(Vector2(16, 110), Vector2(W - 32, 620))
	rem_picker.add_child(_section_label("SLOT A REMNANT", Vector2(16, 12)))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 44)
	scroll.size = Vector2(W - 56, 510)
	rem_picker.add_child(scroll)
	rem_list = VBoxContainer.new()
	rem_list.custom_minimum_size = Vector2(W - 68, 0)
	rem_list.add_theme_constant_override("separation", 4)
	scroll.add_child(rem_list)
	var cancel := _btn("cancel", Vector2(W - 56, 44), func(): rem_picker.visible = false)
	cancel.position = Vector2(12, 562)
	rem_picker.add_child(cancel)

func _open_rem_picker(i: int) -> void:
	_picking = i
	var aspect: String = build.slots[i]["aspect"]
	for c in rem_list.get_children():
		c.queue_free()
	var matches: Array = []
	for r in GameState.remnants:
		if Loot.ASPECT_OF_STAT[r["stat"]] != aspect:
			continue
		if build.slotted().has(r):
			continue
		matches.append(r)
	matches.sort_custom(func(a, b):
		var ra := _rarity_rank(String(a["rarity"]))
		var rb := _rarity_rank(String(b["rarity"]))
		if ra != rb:
			return ra > rb
		return int(a["magnitude"]) > int(b["magnitude"]))
	for r in matches:
		var b := _btn("%s %d [%s]%s" % [String(r["stat"]).capitalize(), int(r["magnitude"]), r["rarity"], _echo_suffix(r)], Vector2(W - 72, 42), _pick_rem.bind(r))
		b.add_theme_color_override("font_color", Loot.rarity_color(r["rarity"]))
		rem_list.add_child(b)
	if matches.is_empty():
		var l := Label.new()
		l.text = "No %s remnants. Raid or PULL the Maw for more." % aspect
		l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		rem_list.add_child(l)
	rem_picker.visible = true

func _pick_rem(r: Dictionary) -> void:
	build.slot_remnant(_picking, r)
	rem_picker.visible = false
	_refresh_build()

# ---------- maw page ----------

func _build_maw_page() -> void:
	var p: Control = pages["maw"]
	p.add_child(_section_label("THE MAW — fullness is the quality dial", Vector2(12, 12)))
	var bgm := ColorRect.new()
	bgm.color = Color(0.05, 0.04, 0.04)
	bgm.position = Vector2(12, 42)
	bgm.size = Vector2(W - 24, 28)
	p.add_child(bgm)
	maw_fill = ColorRect.new()
	maw_fill.color = Color(0.9, 0.55, 0.2)
	maw_fill.position = Vector2(12, 42)
	maw_fill.size = Vector2(0, 28)
	p.add_child(maw_fill)
	maw_stock = Label.new()
	maw_stock.position = Vector2(12, 78)
	maw_stock.size = Vector2(W - 24, 22)
	maw_stock.add_theme_font_size_override("font_size", 14)
	maw_stock.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
	p.add_child(maw_stock)
	var half := (W - 30) / 2.0
	var feed := _btn("FEED scraps", Vector2(half, 58), func(): GameState.feed_scraps())
	feed.position = Vector2(12, 110)
	p.add_child(feed)
	var pull := _btn("PULL", Vector2(half, 58), _do_pull)
	pull.position = Vector2(18 + half, 110)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.42, 0.3, 0.18)
	psb.set_corner_radius_all(8)
	for st in ["normal", "hover", "pressed"]:
		pull.add_theme_stylebox_override(st, psb)
	p.add_child(pull)
	maw_result = Label.new()
	maw_result.position = Vector2(12, 182)
	maw_result.size = Vector2(W - 24, 90)
	maw_result.autowrap_mode = TextServer.AUTOWRAP_WORD
	maw_result.add_theme_font_size_override("font_size", 15)
	maw_result.add_theme_color_override("font_color", Color(0.82, 0.78, 0.62))
	p.add_child(maw_result)
	p.add_child(_section_label("shred surplus undead on the Horde tab:\nselect them, tap Shred.", Vector2(12, 286)))

func _update_maw() -> void:
	var f: float = GameState.ossuary.fullness
	maw_fill.size = Vector2((W - 24) * f, 28)
	maw_fill.color = Color(0.55, 0.5, 0.5).lerp(Color(1.0, 0.65, 0.2), f)
	maw_stock.text = "fullness %d%%   ·   scraps %d   ·   forms %d   ·   remnants %d" % [int(f * 100.0), GameState.scraps, GameState.forms.size(), GameState.remnants.size()]

func _do_pull() -> void:
	var out := GameState.pull_ossuary()
	var noun: String = String(ConfigDb.husk(out["form_id"])["name"])
	var r: Dictionary = out["remnant"]
	maw_result.text = "PULLED: a %s husk + %s %d [%s]" % [noun, String(r["stat"]).capitalize(), int(r["magnitude"]), r["rarity"]]

# ---------- vei page ----------

func _build_vei_page() -> void:
	var p: Control = pages["vei"]
	p.add_child(_section_label("VEI, WHO KEEPS THE DEAD", Vector2(12, 12)))
	var back := _btn("← Missions", Vector2(108, 30), func(): _set_tab("missions"))
	back.position = Vector2(W - 120, 8)
	back.add_theme_font_size_override("font_size", 13)
	p.add_child(back)
	var intro := Label.new()
	intro.position = Vector2(12, 36)
	intro.size = Vector2(W - 24, 76)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 14)
	intro.add_theme_color_override("font_color", Color(0.75, 0.75, 0.82))
	intro.text = "End her and the crypt is yours. She fields more than one kind of doom — read your horde and judge whether it answers them all. Lose, and the whole horde is unmade."
	p.add_child(intro)
	vei_body = VBoxContainer.new()
	vei_body.position = Vector2(12, 120)
	vei_body.custom_minimum_size = Vector2(W - 24, 0)
	vei_body.add_theme_constant_override("separation", 9)
	p.add_child(vei_body)
	var fight := _btn("CHALLENGE VEI", Vector2(W - 20, 70), _do_vei)
	fight.position = Vector2(10, 656)
	fight.add_theme_font_size_override("font_size", 20)
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.3, 0.24, 0.36)
	fsb.set_corner_radius_all(10)
	fsb.border_color = Color(0.6, 0.55, 0.72)
	fsb.set_border_width_all(2)
	for st in ["normal", "hover", "pressed"]:
		fight.add_theme_stylebox_override(st, fsb)
	p.add_child(fight)

func _refresh_vei() -> void:
	for c in vei_body.get_children():
		c.queue_free()
	for f in GameState.vei_fronts():
		_panel_line(vei_body, "• " + String(f["hint"]), 14, Color(0.83, 0.79, 0.72))
		var t := "      your %s: %d" % [String(f["counter_stat"]), int(f["strength"])]
		if _reveal:
			t += "   / need %d  %s" % [int(f["threshold"]), "OK" if f["met"] else "X"]
		_panel_line(vei_body, t, 13, Color(0.62, 0.78, 0.72))

func _do_vei() -> void:
	var res := GameState.fight_vei()
	_show_end(res)

# ---------- raid + end overlays ----------

func _send_party() -> void:
	var n := selected.size()
	if GameState.active_mission.is_empty() or n < 1 or n > GameState.jar_size():
		return
	var delta := GameState.raid(selected.keys())
	selected.clear()
	sort_key = "power"
	_set_tab("missions")
	_show_raid(delta)

func _select_shown() -> void:
	for u in _visible_units():
		selected[int(u["id"])] = true
	_refresh_grid()
	_refresh_ctx()

func _counter_word(th: Dictionary) -> String:
	match String(th.get("counter_stat", "")):
		"wits": return "wits (fells giants)"
		"dread": return "dread or charm (crowd control)"
		"beef": return "beef (a wall)"
		"power": return "raw force"
		_: return "a balanced party"

func _rarity_rank(rarity: String) -> int:
	match rarity:
		"legendary": return 3
		"rare": return 2
		"uncommon": return 1
		_: return 0

func _build_raid_panel() -> void:
	raid_panel = _overlay_panel(Vector2(16, 220), Vector2(W - 32, 440))
	raid_panel.add_child(_section_label("RAID REPORT", Vector2(16, 12)))
	raid_body = VBoxContainer.new()
	raid_body.position = Vector2(16, 44)
	raid_body.custom_minimum_size = Vector2(W - 64, 0)
	raid_body.add_theme_constant_override("separation", 10)
	raid_panel.add_child(raid_body)
	var ok := _btn("got it", Vector2(W - 64, 46), func(): raid_panel.visible = false)
	ok.position = Vector2(16, 380)
	raid_panel.add_child(ok)

func _show_raid(delta: Dictionary) -> void:
	for c in raid_body.get_children():
		c.queue_free()
	var threat: Dictionary = delta["threat"]
	_panel_line(raid_body, "Your party of %d marched on %s." % [int(delta.get("party_size", 0)), String(threat["desc"])], 17, Color(0.9, 0.82, 0.7))
	_panel_line(raid_body, "Coverage %d%% — composition, not luck." % int(float(delta["coverage"]) * 100.0), 14, Color(0.6, 0.8, 0.9))
	var lost: Array = delta["lost"]
	if lost.is_empty():
		_panel_line(raid_body, "Lost: none. The screen held.", 15, Color(0.6, 0.85, 0.6))
	else:
		var names: Array = []
		for i in mini(lost.size(), 6):
			names.append("%s (%s)" % [String(lost[i]["name"]), String(lost[i]["role"])])
		var more := "" if lost.size() <= 6 else " +%d more" % (lost.size() - 6)
		_panel_line(raid_body, "Lost %d: %s%s" % [lost.size(), ", ".join(names), more], 14, Color(0.9, 0.58, 0.52))
	_panel_line(raid_body, "Haul: %d forms · %d remnants · %d hollows · %d scrap" % [int(delta["gained_forms"]), int(delta["gained_remnants"]), int(delta["gained_hollows"]), int(delta["scraps"])], 14, Color(0.7, 0.85, 0.7))
	if delta.has("reward"):
		_panel_line(raid_body, "Spoils skewed toward: %s." % String((delta["reward"] as Dictionary)["hint"]), 13, Color(0.8, 0.78, 0.6))
	raid_panel.visible = true

func _build_end_panel() -> void:
	end_panel = _overlay_panel(Vector2(16, 200), Vector2(W - 32, 480))
	end_body = VBoxContainer.new()
	end_body.position = Vector2(18, 24)
	end_body.custom_minimum_size = Vector2(W - 68, 0)
	end_body.add_theme_constant_override("separation", 11)
	end_panel.add_child(end_body)
	var cont := _btn("continue", Vector2(W - 64, 48), func():
		end_panel.visible = false
		_set_tab("missions"))
	cont.position = Vector2(16, 420)
	end_panel.add_child(cont)

func _show_end(res: Dictionary) -> void:
	for c in end_body.get_children():
		c.queue_free()
	if res["won"]:
		_panel_line(end_body, "VEI FALLS.", 28, Color(0.95, 0.9, 0.6))
		_panel_line(end_body, "The Raven Queen is unmade. You managed your dead well — %d of her %d fronts covered. The crypt is yours." % [int(res["met"]), int(res["need"])], 15, Color(0.85, 0.85, 0.9))
	else:
		_panel_line(end_body, "VEI UNMAKES YOU.", 26, Color(0.9, 0.45, 0.45))
		_panel_line(end_body, "You felt ready. You were not. Only %d of %d fronts held." % [int(res["met"]), int(res["need"])], 15, Color(0.85, 0.7, 0.7))
		for f in res["fronts"]:
			var mark := "held" if f["met"] else "FELL"
			var col := Color(0.6, 0.8, 0.6) if f["met"] else Color(0.9, 0.55, 0.5)
			_panel_line(end_body, "%s — %s (your %s %d)" % [mark, String(f["hint"]), String(f["counter_stat"]), int(f["strength"])], 12, col)
		_panel_line(end_body, "The dead scatter. Begin again.", 14, Color(0.6, 0.6, 0.7))
	end_panel.visible = true

# ---------- tag picker overlay ----------

func _build_tag_panel() -> void:
	tag_panel = _overlay_panel(Vector2(16, 220), Vector2(W - 32, 400))
	tag_panel.add_child(_section_label("TAG THE SELECTED", Vector2(16, 12)))
	tag_chips = HFlowContainer.new()
	tag_chips.position = Vector2(16, 44)
	tag_chips.custom_minimum_size = Vector2(W - 64, 120)
	tag_chips.add_theme_constant_override("h_separation", 8)
	tag_chips.add_theme_constant_override("v_separation", 8)
	tag_panel.add_child(tag_chips)
	tag_panel.add_child(_section_label("coin a new one:", Vector2(16, 244)))
	tag_new_edit = LineEdit.new()
	tag_new_edit.position = Vector2(16, 268)
	tag_new_edit.size = Vector2(W - 116, 46)
	tag_new_edit.placeholder_text = "the wall, fodder..."
	tag_new_edit.add_theme_font_size_override("font_size", 16)
	tag_panel.add_child(tag_new_edit)
	var add := _btn("+ add", Vector2(76, 46), _coin_tag)
	add.position = Vector2(W - 92, 268)
	tag_panel.add_child(add)
	var cancel := _btn("cancel", Vector2(W - 64, 42), func(): tag_panel.visible = false)
	cancel.position = Vector2(16, 332)
	tag_panel.add_child(cancel)

func _open_tag_picker() -> void:
	if selected.is_empty():
		return
	for c in tag_chips.get_children():
		c.queue_free()
	for t in GameState.all_tags():
		var chip := _btn(String(t["label"]), Vector2(0, 38), _apply_tag.bind(String(t["id"])))
		chip.add_theme_color_override("font_color", Color(String(t["color"])))
		tag_chips.add_child(chip)
	tag_panel.visible = true

func _apply_tag(tag_id: String) -> void:
	GameState.tag_units(selected.keys(), tag_id)
	tag_panel.visible = false

func _coin_tag() -> void:
	var label := tag_new_edit.text.strip_edges()
	if label == "":
		return
	var color: String = TAG_PALETTE[GameState.custom_tags.size() % TAG_PALETTE.size()]
	var id := GameState.add_custom_tag(label, color)
	tag_new_edit.text = ""
	GameState.tag_units(selected.keys(), id)
	tag_panel.visible = false

# ---------- debug ----------

func _build_debug() -> void:
	dbg_panel = _overlay_panel(Vector2(8, 44), Vector2(W - 16, 560))
	dbg_panel.visible = false
	var box := VBoxContainer.new()
	box.position = Vector2(12, 12)
	box.size = Vector2(W - 40, 536)
	box.add_theme_constant_override("separation", 6)
	dbg_panel.add_child(box)
	_dbg_button(box, "Grant a big haul (x3 raids)", func():
		for i in 3:
			GameState.raid([]))
	_dbg_button(box, "Reset the crypt", func(): GameState.reset())
	_dbg_button(box, "+ 4 test champions", func():
		for i in 4:
			if GameState.forms.is_empty():
				break
			var fid: String = GameState.forms[0]
			var rems: Array = []
			for r in GameState.remnants:
				if rems.size() >= 3:
					break
				rems.append(r)
			GameState.raise_kitted(fid, rems))
	_dbg_button(box, "Raise all spare forms as Hollows", func(): GameState.raise_all_hollows())
	_dbg_button(box, "Re-roll mission board", func(): GameState.roll_mission_board())
	var reveal := CheckButton.new()
	reveal.text = "reveal Vei thresholds"
	reveal.focus_mode = Control.FOCUS_NONE
	reveal.toggled.connect(func(on): _reveal = on; _refresh())
	box.add_child(reveal)
	_dbg_slider(box, "Vei fronts required", "vei", "fronts_required", 1, 4, 1)
	_dbg_slider(box, "raid coverage / pt", "raid", "coverage_per_counter_point", 0.005, 0.06, 0.005)
	_dbg_slider(box, "champion power threshold", "horde", "champion_power_threshold", 6.0, 30.0, 1.0)
	var close := _btn("close", Vector2(W - 40, 40), func(): dbg_panel.visible = false)
	box.add_child(close)

# ---------- refresh ----------

func _refresh() -> void:
	_update_status()
	match active_tab:
		"missions":
			_refresh_comp()
			_refresh_missions()
		"horde":
			_refresh_muster()
			_refresh_filters()
			_refresh_grid()
			_refresh_ctx()
		"build":
			_refresh_build()
		"maw":
			_update_maw()
		"vei":
			_refresh_vei()

func _update_status() -> void:
	var comp := GameState.composition()
	status_label.text = "%d undead   ·   power %d" % [int(comp["count"]), int(comp["total_power"])]

func _prune_selected() -> void:
	var live := {}
	for u in GameState.horde:
		live[int(u["id"])] = true
	for id in selected.keys():
		if not live.has(id):
			selected.erase(id)

func _unit_by_id(id: int) -> Dictionary:
	for u in GameState.horde:
		if int(u["id"]) == id:
			return u
	return {}

func _tags_text(u: Dictionary) -> String:
	if (u["tags"] as Array).is_empty():
		return ""
	var s := "  "
	for t in u["tags"]:
		s += "#" + String(GameState.tag_def(String(t))["label"]) + " "
	return s

func _echo_suffix(r: Dictionary) -> String:
	var s := ""
	for e in r.get("echoes", []):
		var side: Dictionary = ConfigDb.data["echoes"][e["side"]]
		if side.has(e["id"]):
			s += " +" + String(side[e["id"]]["name"])
	return s

# ---------- tiny helpers ----------

func _btn(text: String, sz: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = sz
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

func _chip(text: String, active: bool, cb: Callable) -> Button:
	var b := _btn(text, Vector2(0, 30), cb)
	b.add_theme_font_size_override("font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.27, 0.33, 0.42) if active else Color(0.13, 0.13, 0.17)
	sb.set_corner_radius_all(15)
	sb.border_color = Color(0.5, 0.7, 0.9) if active else Color(0.3, 0.3, 0.38)
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, sb)
	return b

func _section_label(text: String, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	l.text = text
	return l

func _panel_line(box: VBoxContainer, text: String, sz: int, col: Color) -> void:
	var l := Label.new()
	l.custom_minimum_size = Vector2(W - 72, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.text = text
	box.add_child(l)

func _dbg_button(box: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	box.add_child(b)

func _dbg_slider(box: VBoxContainer, label: String, file: String, key: String, lo: float, hi: float, step: float) -> void:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 12)
	l.text = "%s: %s" % [label, str(ConfigDb.v(file, key))]
	box.add_child(l)
	var s := HSlider.new()
	s.focus_mode = Control.FOCUS_NONE
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(ConfigDb.v(file, key))
	s.custom_minimum_size = Vector2(0, 24)
	s.value_changed.connect(func(v):
		l.text = "%s: %s" % [label, str(v)]
		ConfigDb.set_v(file, key, v))
	box.add_child(s)

func _aspect_color(aspect: String) -> Color:
	if aspect == "hollow":
		return Color(0.5, 0.5, 0.55)
	return Color(String(ConfigDb.data["slab"]["aspect_colors"].get(aspect, "#cccccc")))

func _tier_color(tier: String) -> Color:
	match tier:
		"Champion": return Color(0.95, 0.78, 0.35)
		"Risen": return Color(0.8, 0.82, 0.9)
		_: return Color(0.4, 0.4, 0.47)

func _icon(path: String, pos: Vector2, sz: Vector2, tint: Color) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = load(path)
	tr.position = pos
	tr.custom_minimum_size = sz
	tr.size = sz
	tr.modulate = tint
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _overlay_panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.13, 0.995)
	sb.border_color = Color(0.4, 0.4, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p
