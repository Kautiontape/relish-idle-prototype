class_name VeiCard
extends Control
## Vei's end card (D-d): beating her beats the game, so after the unravel the board holds, dimmed,
## under one plate: VEI BREAKS, the fight time, the backups spent (as the HUD's BACKUPS row draws
## them: a cracked violet ring per spent one, a violet diamond or dot per one unspent), the big undead
## lost, the backlog spent, and one button, "BACK TO THE REALM". Lines and plates only, colours from
## Palette, every label 14 px or more, static (nothing moves, so reduced motion has nothing to cut).
## The scene (vei_boss.gd `_win_card`) builds it from BossLogic.end_card plus `phyl_total` and
## `clones_total`, and hands it the callable the button runs. Enter, Space and Escape press it too,
## and so does a click, all only after `card.skip_after_s` (as the death card's gate): the boss
## trance key is Space, so a player still holding it as the set piece ends must not dismiss the
## card unseen. Until then the button is dim. vei.json `card` holds the sizes, the dim and the gate.
## The loss card (D-e close-out) is the same plate with `info.lost` set (BossLogic.loss_card, built by
## vei_boss.gd `_lose_card`): VEI HOLDS over what ended the fight, the same FIGHT TIME, BACKUPS SPENT and
## BIG UNDEAD LOST rows, BACKLOG as the share that stays (a share, not a number: BossLogic.loss_card says
## why) and, after a final death, an AFTER row; the same button, gate and keys. Static, like the win card.

## The rows' layout (all px): the plate's side padding, the first row's baseline under the plate's top, a one-line
## row's pitch, the space from the last row's pitch end to the plate's bottom (the button and its margins), the
## label and value sizes, and the least gap between a label and a value drawn beside it.
const SIDE_PAD := 44.0
const ROWS_TOP := 226.0
const ROW_STEP := 36.0
const TAIL := 114.0
const LABEL_PX := 15
const VALUE_PX := 24
const LABEL_GAP := 16.0
const STACK_DROP := 28.0   # a stacked row: the value's first baseline under its label's
const STACK_AFTER := 30.0  # and the pitch from the value's last baseline to the next row's label

var _info := {}
var _rows: Array = []   # layout_rows of rows_for(_info), made once in setup
var _cfg := {}
var _on_back := Callable()
var _hover := false
var _pressed := false
var _t := 0.0
var _skip_after := 0.8


func setup(info: Dictionary, cfg: Dictionary, on_back: Callable) -> void:
	_info = info
	_cfg = cfg
	_on_back = on_back
	_skip_after = float(cfg.get("skip_after_s", 0.8))
	_rows = [] if info.is_empty() else layout_rows(rows_for(info), value_w(cfg), ThemeDB.fallback_font)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size   # a CanvasLayer parent gives the anchors nothing to resolve against
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	resized.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	grab_focus.call_deferred()
	queue_redraw()


func can_skip() -> bool:
	return BossLogic.card_unlocked(_t, _skip_after)


func _process(delta: float) -> void:
	var was := can_skip()
	_t += delta / maxf(0.05, Engine.time_scale)
	if can_skip() != was:
		queue_redraw()


## The width a row's value has: the plate less its side padding (a label sits in the same span).
static func value_w(cfg: Dictionary) -> float:
	return float(cfg.get("w_px", 620.0)) - 2.0 * SIDE_PAD


## The card's rows as [{label, text, key, id}], in order. `id` marks a row with an extra drawing ("backups").
## Add a row here (the loss card's pressure and cause rows go in this list) and layout_rows sizes it.
static func rows_for(info: Dictionary) -> Array:
	var rows: Array = [{"label": "FIGHT TIME", "text": str(info["time_text"]), "key": "text", "id": "time"}]
	var total := int(info["backups_total"])
	rows.append({"label": "BACKUPS SPENT", "text": ("%d of %d" % [int(info["spent"]), total]) if total > 0 else "none to spend", "key": "text", "id": "backups"})
	rows.append({"label": "BIG UNDEAD LOST", "text": "%d of %d" % [int(info["party_lost"]), int(info["party"])], "key": "text", "id": "party"})
	if bool(info.get("lost", false)):
		# a loss keeps a share of the backlog (economy's rule; the card prints the share, never a made-up number)
		rows.append({"label": "BACKLOG", "text": str(info["keep_text"]), "key": "text", "id": "backlog"})
		var af: Dictionary = info.get("after", {})
		if not af.is_empty():
			rows.append({"label": str(af["label"]), "text": str(af["text"]), "key": str(af["key"]), "id": "after"})
	else:
		rows.append({"label": "BACKLOG SPENT", "text": _thousands(roundi(float(info["backlog_spent"]))), "key": "text", "id": "backlog"})
	return rows


## 12345 -> "12,345" (RaidHud.BossBlock.thousands, copied: that script needs the Game autoload, which a headless test cannot load).
static func _thousands(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if n < 0 else "") + t + out


## Measure each row for a value span of `vw` px. A value that fits beside its label stays one line on the label's
## baseline (h = ROW_STEP). A longer one is `stacked`: the label on its line and the value wrapped to `vw` under
## it (wrap_words), each line right-aligned, and the row grows to hold them.
## Returns each row plus `lines` (PackedStringArray), `stacked` and `h`.
static func layout_rows(rows: Array, vw: float, font: Font) -> Array:
	var out: Array = []
	var lh := font.get_height(VALUE_PX)
	for r in rows:
		var row: Dictionary = (r as Dictionary).duplicate()
		var text := str(row["text"])
		var side := vw - font.get_string_size(str(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX).x - LABEL_GAP
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_PX).x <= side:
			row["lines"] = PackedStringArray([text])
			row["stacked"] = false
			row["h"] = ROW_STEP
		else:
			var lines := wrap_words(text, font, VALUE_PX, vw)
			row["lines"] = lines
			row["stacked"] = true
			row["h"] = STACK_DROP + lh * float(maxi(0, lines.size() - 1)) + STACK_AFTER
		out.append(row)
	return out


## `text` broken at spaces into lines no wider than `max_w` at `px` (greedy: a line takes words while they fit; a
## single word wider than `max_w` stays whole on its own line).
static func wrap_words(text: String, font: Font, px: int, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var trial: String = word if line == "" else line + " " + word
		if line != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > max_w:
			out.append(line)
			line = word
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


## The plate's height for laid-out rows: `min_h` (vei.json card.loss_h_px) or what the rows need, if more.
static func plate_h_for(laid: Array, min_h: float) -> float:
	var total := 0.0
	for r in laid:
		total += float(r["h"])
	return maxf(min_h, ROWS_TOP + total + TAIL)


func _plate() -> Rect2:
	var w := float(_cfg.get("w_px", 620.0))
	var h := plate_h_for(_rows, float(_cfg.get("loss_h_px", 520.0))) if bool(_info.get("lost", false)) else float(_cfg.get("h_px", 470.0))
	return Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))


func _button_rect() -> Rect2:
	var pl := _plate()
	var bw := float(_cfg.get("button_w_px", 300.0))
	var bh := maxf(44.0, float(_cfg.get("button_h_px", 54.0)))
	return Rect2(Vector2(pl.position.x + (pl.size.x - bw) * 0.5, pl.end.y - bh - 28.0), Vector2(bw, bh))


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := _button_rect().has_point(ev.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		if can_skip() and _button_rect().has_point(ev.position):
			_press()
		accept_event()


## The keys, whoever has focus: once the fight is over the scene ignores input (raid.gd), so the card
## listens itself. Enter, Space and Escape press the button once `can_skip()`.
func _input(ev: InputEvent) -> void:
	if not visible or _info.is_empty() or not can_skip():
		return
	if ev is InputEventKey and ev.pressed and not ev.echo \
			and (ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER or ev.keycode == KEY_SPACE or ev.keycode == KEY_ESCAPE):
		_press()
		get_viewport().set_input_as_handled()


func _press() -> void:
	if _pressed:
		return
	_pressed = true
	if _on_back.is_valid():
		_on_back.call()


func _txt(x: float, y: float, text: String, px: int, key := "text", align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(x, y), text, align, w, px, Palette.c(key))


func _draw() -> void:
	if _info.is_empty():
		return
	var vei := Palette.c("vei")
	draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ground", float(_cfg.get("dim", 0.74))))
	var pl := _plate()
	draw_rect(pl, Palette.c("ground", 0.97))
	draw_rect(pl, vei, false, 3.0)
	draw_rect(pl.grow(-9.0), Palette.c("vei", 0.35), false, 1.0)

	# her rings: unravelled (four concentric arcs, each with a gap) when she breaks, whole when she holds
	var lost := bool(_info.get("lost", false))
	var cx := pl.position.x + pl.size.x * 0.5
	var cy := pl.position.y + 62.0
	for i in 4:
		var r := 14.0 + 11.0 * i
		var a0 := 0.6 + 0.9 * i
		draw_arc(Vector2(cx, cy), r, a0, a0 + (TAU if lost else TAU * 0.78), 48 if lost else 28, Palette.c("vei", 0.95 - 0.15 * i), 2.5)
	draw_circle(Vector2(cx, cy), 4.0, Palette.c("text"))

	_txt(pl.position.x, pl.position.y + 150.0, "VEI HOLDS" if lost else "VEI BREAKS", 46, "danger" if lost else "vei", HORIZONTAL_ALIGNMENT_CENTER, pl.size.x)
	_txt(pl.position.x, pl.position.y + 178.0, str(_info.get("ended", "the fight is lost")) if lost else "the game is beaten", 18, "text_dim", HORIZONTAL_ALIGNMENT_CENTER, pl.size.x)

	var lx := pl.position.x + SIDE_PAD
	var rx := pl.end.x - SIDE_PAD
	var y := pl.position.y + ROWS_TOP
	draw_line(Vector2(lx, y - 24.0), Vector2(rx, y - 24.0), Palette.c("text_dim", 0.35), 1.0)

	# the rows (rows_for, laid out once in setup): a label and its value beside it, or, for a value too long
	# for that, the label alone and the value wrapped under it
	for row in _rows:
		_txt(lx, y, str(row["label"]), LABEL_PX, "text_dim")
		var lines: PackedStringArray = row["lines"]
		if bool(row["stacked"]):
			var lh := ThemeDB.fallback_font.get_height(VALUE_PX)
			for k in lines.size():
				_txt(lx, y + STACK_DROP + lh * k, lines[k], VALUE_PX, str(row["key"]), HORIZONTAL_ALIGNMENT_RIGHT, rx - lx)
		else:
			_txt(lx, y, lines[0], VALUE_PX, str(row["key"]), HORIZONTAL_ALIGNMENT_RIGHT, rx - lx)
		if str(row["id"]) == "backups":
			_draw_backup_pips(rx - ThemeDB.fallback_font.get_string_size(lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_PX).x - 22.0, y)
		y += float(row["h"])

	# the button
	var b := _button_rect()
	var live := can_skip()
	draw_rect(b, Palette.c("vei", 0.38 if (_hover and live) else 0.16))
	draw_rect(b, vei if live else Palette.c("vei", 0.5), false, 3.0 if (_hover and live) else 2.0)
	if has_focus() and live:
		draw_rect(b.grow(5.0), Palette.c("text", 0.8), false, 1.5)
	_txt(b.position.x, b.position.y + b.size.y * 0.5 + 7.0, "BACK TO THE REALM", 20, "text" if live else "text_dim", HORIZONTAL_ALIGNMENT_CENTER, b.size.x)


## The backups: a cracked ring per one spent, a violet diamond (phylactery) or dot (clone) per one left,
## right to left from `px` on the row's baseline `y`.
func _draw_backup_pips(px: float, y: float) -> void:
	var sp := int(_info["spent_phyl"])
	var sc := int(_info["spent_clones"])
	var pt := int(_info.get("phyl_total", 0))
	var ct := int(_info.get("clones_total", 0))
	var kinds: Array = []
	for i in pt:
		kinds.append([true, i < sp])
	for i in ct:
		kinds.append([false, i < sc])
	for k in range(kinds.size() - 1, -1, -1):
		var c := Vector2(px, y - 7.0)
		if bool(kinds[k][1]):
			for j in 3:
				var a0 := TAU * j / 3.0 + 0.7 * k + 0.2
				draw_arc(c, 7.5, a0, a0 + TAU / 3.0 - 0.55, 8, Palette.c("relish", 0.95), 2.0)
		elif bool(kinds[k][0]):
			var r := 7.5
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), Palette.c("relish"))
		else:
			draw_circle(c, 6.5, Palette.c("relish"))
		px -= 22.0
