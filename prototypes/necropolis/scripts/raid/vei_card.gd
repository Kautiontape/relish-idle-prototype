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

var _info := {}
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


func _plate() -> Rect2:
	var w := float(_cfg.get("w_px", 620.0))
	var h := float(_cfg.get("loss_h_px", 520.0)) if bool(_info.get("lost", false)) else float(_cfg.get("h_px", 470.0))
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

	var lx := pl.position.x + 44.0
	var rx := pl.end.x - 44.0
	var y := pl.position.y + 226.0
	var step := 36.0
	draw_line(Vector2(lx, y - 24.0), Vector2(rx, y - 24.0), Palette.c("text_dim", 0.35), 1.0)

	# the fight time
	_txt(lx, y, "FIGHT TIME", 15, "text_dim")
	_txt(lx, y, str(_info["time_text"]), 24, "text", HORIZONTAL_ALIGNMENT_RIGHT, rx - lx)
	y += step

	# the backups: a cracked ring per one spent, a violet diamond (phylactery) or dot (clone) per one left
	_txt(lx, y, "BACKUPS SPENT", 15, "text_dim")
	var spent := int(_info["spent"])
	var total := int(_info["backups_total"])
	var words := "%d of %d" % [spent, total] if total > 0 else "none to spend"
	var font := ThemeDB.fallback_font
	var ww := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	_txt(lx, y, words, 24, "text", HORIZONTAL_ALIGNMENT_RIGHT, rx - lx)
	var px := rx - ww - 22.0
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
	y += step

	# the big undead lost
	_txt(lx, y, "BIG UNDEAD LOST", 15, "text_dim")
	_txt(lx, y, "%d of %d" % [int(_info["party_lost"]), int(_info["party"])], 24, "text", HORIZONTAL_ALIGNMENT_RIGHT, rx - lx)
	y += step

	if lost:
		# a loss keeps a share of the backlog (economy's rule; the card prints the share, never a made-up number)
		_txt(lx, y, "BACKLOG", 15, "text_dim")
		_txt(lx, y, str(_info["keep_text"]), 24, "text", HORIZONTAL_ALIGNMENT_RIGHT, rx - lx)
		var af: Dictionary = _info.get("after", {})
		if not af.is_empty():
			y += step
			_txt(lx, y, str(af["label"]), 15, "text_dim")
			_txt(lx, y, str(af["text"]), 24, str(af["key"]), HORIZONTAL_ALIGNMENT_RIGHT, rx - lx)
	else:
		# what the fight spent of the backlog
		_txt(lx, y, "BACKLOG SPENT", 15, "text_dim")
		_txt(lx, y, RaidHud.BossBlock.thousands(roundi(float(_info["backlog_spent"]))), 24, "text", HORIZONTAL_ALIGNMENT_RIGHT, rx - lx)

	# the button
	var b := _button_rect()
	var live := can_skip()
	draw_rect(b, Palette.c("vei", 0.38 if (_hover and live) else 0.16))
	draw_rect(b, vei if live else Palette.c("vei", 0.5), false, 3.0 if (_hover and live) else 2.0)
	if has_focus() and live:
		draw_rect(b.grow(5.0), Palette.c("text", 0.8), false, 1.5)
	_txt(b.position.x, b.position.y + b.size.y * 0.5 + 7.0, "BACK TO THE REALM", 20, "text" if live else "text_dim", HORIZONTAL_ALIGNMENT_CENTER, b.size.x)
