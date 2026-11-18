class_name MapCardView
extends VBoxContainer
## Draws one card ({title, sub, desc, blocks} from CardBlocksLogic) in the type law's faces. The
## controls are built once per card structure (CardBlocksLogic.card_sig) and only their texts are
## updated on a refresh, so a press or an open dropdown is never swallowed. Everything is static:
## nothing here moves, so reduced motion changes nothing.

signal assign_front(uid: String, front_id: String)

var _sig := ""
var _title: Label
var _sub: Label
var _about: Button
var _desc: Label
var _body: VBoxContainer
var _refs: Array = []
var _desc_open := true


## The comparison bars of a "versus" block: two thin tracks with a fill each (party above, garrison below).
class Bars extends Control:
	var a := 0.0
	var b := 0.0

	func _draw() -> void:
		var cards: Dictionary = MapLogic.cfg()["cards"]
		var h := float(cards["bar_h_px"])
		var gap := float(cards["bar_gap_px"])
		var track := Palette.c("contour", float(cards["bar_track_alpha"]))
		for i in 2:
			var y := float(i) * (h + gap)
			draw_rect(Rect2(0.0, y, size.x, h), track)
			draw_rect(Rect2(0.0, y, size.x * (a if i == 0 else b), h), Palette.c("undead" if i == 0 else "living"))


func _ready() -> void:
	var cfg := MapLogic.cfg()
	add_theme_constant_override("separation", int(cfg["sidebar_row_gap_px"]))
	_desc_open = not bool(cfg["cards"]["desc_collapsed_default"])
	_title = Label.new()
	MapType.style_title(_title)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	_sub = Label.new()
	MapType.style_label(_sub)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_sub)
	_about = Button.new()
	MapUi.style_button(_about, int(cfg["font_body"]))
	_about.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_about.pressed.connect(func():
		_desc_open = not _desc_open
		_apply_desc())
	add_child(_about)
	_desc = Label.new()
	MapType.style_label(_desc, "text_dim", int(cfg["font_body"]))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_desc)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", int(cfg["sidebar_row_gap_px"]))
	add_child(_body)


func _apply_desc() -> void:
	var cards: Dictionary = MapLogic.cfg()["cards"]
	var has := _desc.text != ""
	_about.visible = has
	_desc.visible = has and _desc_open
	_about.text = str(cards["about_open" if _desc_open else "about_closed"])


## Shows `card`; rebuilds the controls only when its structure changed.
func show_card(card: Dictionary) -> void:
	var sig := CardBlocksLogic.card_sig(card)
	if sig != _sig:
		_sig = sig
		for c in _body.get_children():
			_body.remove_child(c)
			c.queue_free()
		_refs.clear()
		for blk in card["blocks"]:
			_refs.append(_build(blk))
	_put(_title, str(card["title"]))
	_put(_sub, str(card["sub"]))
	_put(_desc, str(card.get("desc", "")))
	_apply_desc()
	for i in _refs.size():
		_update(_refs[i], card["blocks"][i])


## The bottom edge of every block, in this card's frame, from the controls' minimum sizes (a layout
## pass behind a text change would give stale positions): the sidebar ends a scrolled card's visible
## area on one of these (CardLogic.snap_bottom), so no line is cut at the fold.
func block_bottoms() -> Array:
	var out: Array = []
	var gap := float(get_theme_constant("separation"))
	var y := 0.0
	for c in get_children():
		var ctl := c as Control
		if not ctl.visible:
			continue
		if ctl == _body:
			var bgap := float(_body.get_theme_constant("separation"))
			var by := y
			for b in _body.get_children():
				if (b as Control).visible:
					by += (b as Control).get_combined_minimum_size().y
					out.append(by)
					by += bgap
			y = by - bgap
		else:
			y += ctl.get_combined_minimum_size().y
			out.append(y)
		y += gap
	return out


static func _put(l: Label, text: String) -> void:
	if l.text != text:
		l.text = text


static func _body_size() -> int:
	return int(MapLogic.cfg()["font_body"])


static func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## What a para's style depends on: its face and colour key (the structure signature ignores both).
static func _para_style(blk: Dictionary) -> String:
	return "%s:%s" % [blk["face"], blk["key"]]


static func _face(l: Label, face: String, key: String) -> void:
	match face:
		"mass":
			MapType.style_mass(l, key)
		"rate":
			MapType.style_rate(l, key)
		_:
			MapType.style_label(l, key, _body_size())


# --- building ---------------------------------------------------------------------------

func _build(blk: Dictionary) -> Dictionary:
	var cfg := MapLogic.cfg()
	var cards: Dictionary = cfg["cards"]
	var refs := {"kind": blk["kind"]}
	match str(blk["kind"]):
		"head":
			var m := MarginContainer.new()
			m.add_theme_constant_override("margin_top", int(cards["section_gap_px"]))
			var l := Label.new()
			MapType.style_label(l, "text_dim")
			m.add_child(l)
			_body.add_child(m)
			refs["label"] = l
		"para":
			var l := _wrap(Label.new())
			_face(l, str(blk["face"]), str(blk["key"]))
			_body.add_child(l)
			refs["label"] = l
			refs["para_style"] = _para_style(blk)
		"chips":
			var f := HFlowContainer.new()
			f.add_theme_constant_override("h_separation", int(cards["chip_gap_px"]))
			f.add_theme_constant_override("v_separation", int(cards["chip_gap_px"]))
			_body.add_child(f)
			refs["flow"] = f
			refs["chips"] = []
			for i in (blk["chips"] as Array).size():
				var chip := _make_chip()
				f.add_child(chip["box"])
				refs["chips"].append(chip)
		"row":
			var h := HBoxContainer.new()
			var name_l := Label.new()
			MapType.style_label(name_l, "text_dim", _body_size())
			name_l.custom_minimum_size.x = float(cfg["sidebar_row_label_px"])
			h.add_child(name_l)
			var val := _wrap(Label.new())
			_face(val, str(blk["vkind"]), "text")
			h.add_child(val)
			var suf := Label.new()
			MapType.style_label(suf, "text", _body_size())
			h.add_child(suf)
			_body.add_child(h)
			refs.merge({"name": name_l, "value": val, "suffix": suf})
		"massline":
			var h := HBoxContainer.new()
			var m := Label.new()
			MapType.style_mass(m)
			h.add_child(m)
			var t := _wrap(Label.new())
			MapType.style_label(t, "text_dim", _body_size())
			h.add_child(t)
			_body.add_child(h)
			refs.merge({"mass": m, "text": t})
		"versus":
			var v := VBoxContainer.new()
			var t := _wrap(Label.new())
			MapType.style_mass(t)
			v.add_child(t)
			var bars := Bars.new()
			bars.custom_minimum_size.y = 2.0 * float(cards["bar_h_px"]) + float(cards["bar_gap_px"])
			v.add_child(bars)
			_body.add_child(v)
			refs.merge({"text": t, "bars": bars})
		"risk":
			var h := HBoxContainer.new()
			var name_l := Label.new()
			MapType.style_label(name_l, "text_dim", _body_size())
			name_l.custom_minimum_size.x = float(cfg["sidebar_row_label_px"])
			h.add_child(name_l)
			var chip := _make_chip()
			h.add_child(chip["box"])
			_body.add_child(h)
			refs.merge({"name": name_l, "chip": chip})
		"front":
			var v := VBoxContainer.new()
			var h := HBoxContainer.new()
			var name_l := Label.new()
			MapType.style_label(name_l, "text", _body_size())
			name_l.custom_minimum_size.x = float(cards["bar_label_w_px"])
			h.add_child(name_l)
			var count := Label.new()
			MapType.style_mass(count)
			count.custom_minimum_size.x = float(cards["front_count_w_px"])
			h.add_child(count)
			var mark := _wrap(Label.new())
			MapType.style_label(mark, "text", _body_size())
			h.add_child(mark)
			v.add_child(h)
			var who := _wrap(Label.new())
			MapType.style_label(who, "text_dim", _body_size())
			v.add_child(who)
			_body.add_child(v)
			refs.merge({"name": name_l, "count": count, "mark": mark, "who": who})
		"assign":
			var h := HBoxContainer.new()
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var name_l := _wrap(Label.new())
			MapType.style_label(name_l, "text", _body_size())
			v.add_child(name_l)
			var sub := _wrap(Label.new())
			MapType.style_label(sub, "text_dim", _body_size())
			v.add_child(sub)
			h.add_child(v)
			var ob := OptionButton.new()
			MapUi.style_option(ob)
			ob.custom_minimum_size.x = float(cards["assign_option_w_px"])
			for i in (blk["options"] as Array).size():
				ob.add_item(str(blk["labels"][i]), i)
			var uid := str(blk["uid"])
			var options: Array = blk["options"]
			ob.item_selected.connect(func(idx: int): assign_front.emit(uid, str(options[idx])))
			h.add_child(ob)
			_body.add_child(h)
			refs.merge({"name": name_l, "sub": sub, "option": ob})
	return refs


## A status or risk chip: a word in a palette key on a faint tint of that key, outlined.
func _make_chip() -> Dictionary:
	var box := PanelContainer.new()
	var l := Label.new()
	box.add_child(l)
	return {"box": box, "label": l, "key": ""}


func _style_chip(chip: Dictionary, key: String) -> void:
	if chip["key"] == key:
		return
	chip["key"] = key
	var cards: Dictionary = MapLogic.cfg()["cards"]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.c(key, float(cards["chip_bg_alpha"]))
	sb.border_color = Palette.c(key, float(cards["chip_border_alpha"]))
	sb.set_border_width_all(1)
	sb.set_content_margin_all(int(cards["chip_pad_px"]))
	(chip["box"] as PanelContainer).add_theme_stylebox_override("panel", sb)
	MapType.style_label(chip["label"], key, _body_size())


# --- updating -----------------------------------------------------------------------------

func _update(refs: Dictionary, blk: Dictionary) -> void:
	match str(refs["kind"]):
		"head":
			_put(refs["label"], str(blk["text"]))
		"para":
			_put(refs["label"], str(blk["text"]))
			var style := _para_style(blk)  # a para's colour can change under the same id
			if refs.get("para_style", "") != style:
				refs["para_style"] = style
				_face(refs["label"], str(blk["face"]), str(blk["key"]))
		"chips":
			for i in (blk["chips"] as Array).size():
				var chip: Dictionary = refs["chips"][i]
				_style_chip(chip, str(blk["chips"][i]["key"]))
				_put(chip["label"], str(blk["chips"][i]["text"]))
		"row":
			_put(refs["name"], str(blk["label"]))
			_put(refs["value"], str(blk["value"]))
			_put(refs["suffix"], (" " + str(blk["suffix"])) if str(blk["suffix"]) != "" else "")
		"massline":
			_put(refs["mass"], str(blk["mass"]))
			_put(refs["text"], str(blk["text"]))
		"versus":
			_put(refs["text"], str(blk["text"]))
			var bars: Bars = refs["bars"]
			bars.visible = bool(blk["known"])
			if bars.a != float(blk["a"]) or bars.b != float(blk["b"]):
				bars.a = float(blk["a"])
				bars.b = float(blk["b"])
				bars.queue_redraw()
		"risk":
			_put(refs["name"], str(blk["label"]))
			_style_chip(refs["chip"], str(blk["chip"]["key"]))
			_put(refs["chip"]["label"], str(blk["chip"]["text"]))
		"front":
			_put(refs["name"], str(blk["name"]))
			_put(refs["count"], str(blk["count"]))
			_put(refs["mark"], str(blk["mark"]))
			var mark_key := "undead" if bool(blk["cleared"]) else "text"
			if refs.get("mark_key", "") != mark_key:
				refs["mark_key"] = mark_key
				MapType.style_label(refs["mark"], mark_key, _body_size())
			var lines: Array = [str(blk["assigned"])]
			for k in ["also", "queue"]:
				if str(blk.get(k, "")) != "":
					lines.append(str(blk[k]))
			_put(refs["who"], "\n".join(lines))
		"assign":
			_put(refs["name"], str(blk["name"]))
			_put(refs["sub"], str(blk["sub"]))
			var ob: OptionButton = refs["option"]
			if not ob.get_popup().visible:
				ob.select(maxi((blk["options"] as Array).find(str(blk["selected"])), 0))
