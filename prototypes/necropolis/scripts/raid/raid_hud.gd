class_name RaidHud
extends CanvasLayer
## Raid HUD: fort name/tier, a compact glanceable stat block (the WARD chain and the carried
## essence as pips with their integers beside them), trance meter, hint line, the
## always-visible retreat button (top-right) + its confirmation dialog. The boss (Vei's final test)
## has no retreat: no button and no dialog; its BossBlock (top centre) shows the fronts, the horde,
## the break's beat pips and the backups left. A dungeon's awake warden gets the WardenBlock (top
## centre): its break meter and whether the counterplay is working.

var raid: Node = null

var trace_overlay: RaidTraceOverlay = null   # the loop's screen-space readouts (the trance and the feedback feed it)

var _title: Label
var _stats: StatBlock
var _hint: Label
var _hint2: Label      # the idle hint's second line (dungeon only)
var _hint_plate: ColorRect = null   # the hint's ground plate, bottom-centre, inside the danger frame
var _hp_fitted := false   # the hint plate's cached fit: what it was fitted to (show flag, hint text, sub-line text)
var _hp_show := false
var _hp_text := ""
var _hp_sub := ""
var _meter: Control
var _exit_btn: Control = null       # dungeon only
var _retreat: RaidRetreatPanel = null   # dungeon only: the retreat choice (mouse only; Space never confirms)
var _retreat_t := 0.0               # the open retreat panel's lines refresh clock
var _legend: RaidLegend = null     # dungeon only: the control legend (open until a fort is taken, then a chip)
var _flash: ColorRect
var _flash_t := -1.0
var _banner: Label
var _banner_t := -1.0
var _banner_plate: ColorRect = null   # a dark plate fitted to the banner's lines (walls run under it)
var _banner_live := Callable()        # recomputes the banner's text while it shows (the last chance)
var _banner_live_t := 0.0
var _scene_s := 0.0                  # scene seconds since the HUD was built (slows with the trance)
var _undead_cue_shown := false       # T2: the undead cue shows once per run
var _first_mote_cue_shown := false   # T2: the first-mote cue shows once per run
var _cue_queue: Array = []           # T2: cues waiting behind a banner: [text, secs, color_key, waited_real_s]
var _warden_block: Control = null   # dungeon only: the awake warden's break meter
var _pointers: Node2D = null        # dungeon only: the pointer to the nearest floor loot
var _push: PushLine = null          # dungeon only: the push-or-retreat line under the RETREAT button
var _push_t := 1.0
var _goal_block: RaidGoalBlock = null   # T4, dungeon only: the goal / route / how-to-break rows while no warden block shows
var _goal_t := 1.0
var _route_len := -1                # hops from the spawn's room to the warden's room, plus one (-1: not measured yet)
var _hops_left := -1                # hops from Relish's room to the warden's (kept through a doorway band)
var _risk := {}                     # the UNBANKED counts, for the push line
var exit_pos := Vector2.INF         # the nearest exit's inner point (the Pointers' EXIT chevron)
var _banner_top := 70.0
var _clearing := false              # the clear card is up: BANKED is the win, nothing is unbanked (on_clear)
var _clear_counts := {}             # the win's loot counts, for BANKED while _clearing
var _loot_key := []            # [banked, found_loot, carried, on the floor] the BANKED/UNBANKED lines show
var _door_prompt: Label = null    # D-e task 6: the held door's plate prompt, while she can send a big (its row is the StatBlock's DOOR)
var _door_text := ""             # the DOOR row's text as last wrapped
# boss extras
var _boss_block: Control = null
var boss_info: Dictionary = {}   # the boss's hud_info(), built once a frame in refresh() (BossBlock reads it)
# refresh() runs every frame: the config word blocks are read once in build, each string is rebuilt only when its inputs change
var _hint_words: Dictionary = {}   # raid.json hud.hint
var _title_key := ""               # the fort name and tier the title was last built from
var _title_tier := -1
var _raised_key := [-1, -1, -1]    # the RAISED row's inputs as last built


## raid.json hud.text: the HUD's own words (title, RAISED rows, checkpoint banner, trance meter, edge chevrons, exit plate).
static func hud_text() -> Dictionary:
	return ConfigDb.data.get("raid", {}).get("hud", {}).get("text", {})


## One of them, formatted with `args` (blank when raid.json has no such word).
static func hud_fmt(key: String, args: Array) -> String:
	return RaidLogic.word_fmt(hud_text(), key, args)


func build(p_raid: Node, boss_mode: bool) -> void:
	raid = p_raid
	_hint_words = raid.rcfg().get("hud", {}).get("hint", {})
	layer = 10

	var box := VBoxContainer.new()
	box.position = Vector2(18, 14)
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_title = _mk_label(box, 24, Palette.c("vei"))
	_stats = StatBlock.new()
	_stats.setup(boss_mode)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_stats)
	if not boss_mode and raid.held_door != null:
		# the held door (D-e task 6): the plate's prompt over the hint line, wide enough for the whole trade
		# (the big it holds is on the StatBlock's DOOR row, not in the WARD's big row)
		_door_prompt = _mk_label(self, 17, Palette.c("text"))
		_door_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_door_prompt.anchor_top = 1.0
		# its top and bottom come from the hint's fitted plate (_fit_hint_plate), which refits it with the plate
		_door_prompt.offset_left = 0.0
		_door_prompt.offset_right = 0.0
		_door_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH   # sized to its text, centred
		_door_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# its own dark plate, as the banner has: the map's walls never run through the trade it names
		var pplate := StyleBoxFlat.new()
		pplate.bg_color = Palette.c("ground", float(raid.rcfg().get("hud", {}).get("door_plate_alpha", 0.86)))
		pplate.content_margin_left = 10.0
		pplate.content_margin_right = 10.0
		pplate.content_margin_top = 3.0
		pplate.content_margin_bottom = 3.0
		_door_prompt.add_theme_stylebox_override("normal", pplate)
		_door_prompt.visible = false

	if not boss_mode:
		# the control legend (T1): open until a fort has been taken, then a chip; bottom-left, 8 px over the trance meter
		var open_legend := RaidLogic.legend_open_at_start(int(Game.state.view_hud().get("highest_tier_flipped", 0)))
		_legend = RaidLegend.new()
		_legend.setup(ConfigDb.data.get("raid", {}).get("hud", {}).get("legend", {}), open_legend)
		add_child(_legend)
		_legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_legend.anchor_top = 1.0
		var lsz := _legend.size
		_legend.offset_left = 18.0
		_legend.offset_right = 18.0 + lsz.x
		_legend.offset_bottom = -54.0
		_legend.offset_top = -54.0 - lsz.y

	_banner_plate = ColorRect.new()
	_banner_plate.color = Palette.c("ground", float(raid.rcfg().get("hud", {}).get("banner_plate_alpha", 0.94)))
	_banner_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_plate.visible = false
	add_child(_banner_plate)
	_banner_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_plate.anchor_left = 0.5
	_banner_plate.anchor_right = 0.5
	_banner = _mk_label(self, 20, Palette.c("relish"))
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_left = -RaidLogic.BANNER_W * 0.5
	_banner.offset_right = RaidLogic.BANNER_W * 0.5
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH   # an over-wide line stays centred, and so does its plate
	_banner.offset_top = 70.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false

	_hint_plate = ColorRect.new()   # fitted to the hint's visible lines by _fit_hint_plate
	_hint_plate.color = Palette.c("ground", float(raid.rcfg().get("hud", {}).get("hint", {}).get("plate_alpha", 0.96)))
	_hint_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_plate.visible = false
	add_child(_hint_plate)
	_hint_plate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_plate.anchor_top = 1.0
	var hint_cfg: Dictionary = raid.rcfg().get("hud", {}).get("hint", {})
	_hint = _mk_label(self, int(hint_cfg.get("font_px", 19)), Palette.c("text"))
	_hint.text = str(hint_cfg.get("idle_text", ""))
	_cue_undead_lines = str(raid.rcfg().get("hud", {}).get("cues", {}).get("undead_text", "")).replace(" · ", "\n")
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.anchor_top = 1.0
	_hint.offset_top = -52.0
	_hint.offset_bottom = -24.0
	_hint.offset_left = -380.0
	_hint.offset_right = 380.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# the idle hint's second line (RaidLogic.hint_sub_text): under the first, dim, until the first raise
	_hint2 = _mk_label(self, int(hint_cfg.get("sub_font_px", 15)), Palette.c("text_dim"))
	_hint2.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint2.anchor_top = 1.0
	_hint2.offset_top = -24.0
	_hint2.offset_bottom = -4.0
	_hint2.offset_left = -380.0
	_hint2.offset_right = 380.0
	_hint2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint2.visible = false

	_meter = TranceMeter.new()
	_meter.raid = p_raid
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_meter)
	_meter.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_meter.anchor_top = 1.0
	_meter.offset_left = 18.0
	_meter.offset_top = -46.0
	_meter.offset_right = 208.0
	_meter.offset_bottom = -16.0

	if not boss_mode:
		_warden_block = WardenBlock.new()
		_warden_block.raid = p_raid
		_warden_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_warden_block.visible = false
		add_child(_warden_block)
		_warden_block.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_warden_block.anchor_left = 0.5
		_warden_block.anchor_right = 0.5
		var half_w := float(raid.rcfg().get("hud", {}).get("warden_block_w", 680.0)) * 0.5   # hud.warden_block_w: both top blocks' width
		_warden_block.offset_left = -half_w
		_warden_block.offset_right = half_w
		_warden_block.offset_top = 10.0
		_warden_block.offset_bottom = 72.0
		# T4: the goal block, in the same spot while no warden block shows (before the wake, after it falls, a held raid)
		_goal_block = RaidGoalBlock.new()
		_goal_block.visible = false
		_goal_block.plate_alpha = float(_goal_cfg(p_raid).get("plate_alpha", 0.96))
		add_child(_goal_block)
		_goal_block.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_goal_block.anchor_left = 0.5
		_goal_block.anchor_right = 0.5
		_goal_block.offset_left = -half_w
		_goal_block.offset_right = half_w
		_goal_block.offset_top = 10.0
		_goal_block.offset_bottom = 10.0

	if not boss_mode:   # there is no retreat from the Vei fight
		_exit_btn = ExitButton.new()
		_exit_btn.hud = self
		add_child(_exit_btn)
		_exit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_exit_btn.anchor_left = 1.0
		_exit_btn.offset_left = -196.0
		_exit_btn.offset_top = 14.0
		_exit_btn.offset_right = -18.0
		_exit_btn.offset_bottom = 60.0

		_push = PushLine.new()
		_push.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_push)
		_push.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_push.anchor_left = 1.0
		_push.offset_left = -760.0
		_push.offset_right = -18.0
		_push.offset_top = 64.0
		_push.offset_bottom = 88.0

		_retreat = RaidRetreatPanel.new()
		_retreat.configure(raid.rcfg().get("hud", {}).get("retreat", {}))
		_retreat.chosen.connect(func(go: bool) -> void:
			if go:
				raid.endings.try_retreat("click"))
		add_child(_retreat)

	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	add_child(_flash)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)

	if not boss_mode:
		_pointers = Pointers.new()
		_pointers.hud = self
		add_child(_pointers)
		move_child(_pointers, 0)   # under the stat block and its plate: the loot pointer never crosses HUD text

	if boss_mode:
		_boss_block = BossBlock.new()
		_boss_block.raid = p_raid
		_boss_block.hud = self
		_boss_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_boss_block)
		_boss_block.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_boss_block.anchor_left = 0.5
		_boss_block.anchor_right = 0.5
		_boss_block.offset_left = -BossLogic.BLOCK_W * 0.5   # the BACKLOG row's width test reads BossLogic.BLOCK_W
		_boss_block.offset_right = BossLogic.BLOCK_W * 0.5
		_boss_block.offset_top = 10.0
		_boss_block.offset_bottom = 10.0 + BossBlock.H_BREAK
		_banner.offset_top = 10.0 + BossBlock.H_BREAK + 8.0
	if not boss_mode:
		_banner.offset_top = 116.0   # its own row under the push line (up to two lines), so neither can run into the other
	_banner_top = _banner.offset_top
	# the loop's readouts (RaidTraceOverlay): drawn over every HUD control above, under the retreat panel and under
	# the death, clear and Vei cards (added to this layer later, so after it)
	trace_overlay = RaidTraceOverlay.new()
	trace_overlay.raid = raid
	trace_overlay.hud = self
	add_child(trace_overlay)
	if _retreat != null:
		move_child(trace_overlay, _retreat.get_index())


## The hint plate's screen rect (empty while it is hidden): the loop's readouts keep off it when they can.
func hint_plate_rect() -> Rect2:
	if _hint_plate == null or not _hint_plate.visible:
		return Rect2()
	return Rect2(_hint_plate.global_position, _hint_plate.size)


func _mk_label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Palette.c("ground", 0.85))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _process(_delta: float) -> void:
	if raid == null:
		return
	_scene_s += _delta
	refresh()
	_fit_hint_plate()
	_tick_cues()
	if _warden_block != null:
		if _goal_block != null:
			_tick_goal(_delta_real())
		# the banner steps down under whichever top-centre block shows (the goal block's height, or the warden's)
		var blk := top_block_rect()
		var top := RaidLogic.banner_top(_banner_top, blk.size.y > 0.0, blk.size.y)
		if _banner.visible:   # and off the sleeping warden's ring: below it, or above when below won't fit
			var vr := get_viewport().get_visible_rect()
			var pw := _banner_plate.offset_right - _banner_plate.offset_left
			var plate := Rect2(vr.size.x * 0.5 + _banner_plate.offset_left, top - 3.0, pw, _banner_plate.offset_bottom - _banner_plate.offset_top)
			var wd = raid.warden_run.warden if raid.warden_run != null else null
			var pres := (wd as RaidWarden).presence_screen_rect() if _sleeping_ring_rect(wd).has_area() else Rect2()   # the ring and its name plates
			top = RaidLogic.banner_clear_top(top, plate, pres, Rect2(Vector2.ZERO, vr.size))
		if _banner.offset_top != top:
			_banner.offset_top = top
			_fit_banner_plate()
		if _push != null:
			_push.max_w = _push_room()
	if _banner_t >= 0.0:
		_banner_t -= _delta
		if _banner_live.is_valid():
			_banner_live_t += _delta_real()
			if _banner_live_t >= 0.25:
				_banner_live_t = 0.0
				var lt: String = _banner_live.call()
				if lt != _banner.text:
					_banner.text = lt
					_fit_banner_plate()
		if _banner_t < 0.0:
			_banner.visible = false
			_banner_plate.visible = false
			_banner_live = Callable()
	if _flash_t >= 0.0:
		_flash_t += _delta / maxf(0.05, Engine.time_scale)
		var f := _flash_t / 0.9
		if f >= 1.0:
			_flash.visible = false
			_flash_t = -1.0
		else:
			var c: Color = _flash.color
			c.a = (1.0 - f) * 0.85
			_flash.color = c


func refresh() -> void:
	var fort: String = raid.fort_name()
	var tier: int = 0 if raid.is_boss() else raid.fort_tier()
	if fort != _title_key or tier != _title_tier:
		_title_key = fort
		_title_tier = tier
		_title.text = fort.to_upper() if raid.is_boss() else hud_fmt("title_tier", [fort.to_upper(), tier])
	var st := _stats
	st.living = raid.enemies.size()
	var motes: int = raid.get_tree().get_node_count_in_group("raid_essence")   # a count, no array
	if raid.is_boss():
		# the boss keeps no ledger: the WARD (her sacrifice chain) and the raised that stand
		st.loose = motes
		var raised := 0
		var party := 0
		for a in raid.allies:
			if is_instance_valid(a) and a.alive:
				if a.role == "party":
					party += 1
				else:
					raised += 1
		if raised != _raised_key[0] or party != _raised_key[1]:
			_raised_key = [raised, party, 0]
			st.raised_text = hud_fmt("raised_big", [raised, party])
		boss_info = raid.hud_info()   # once a frame; the boss block reads this copy
		var info: Dictionary = boss_info
		_hint.text = str(info["hint"])
		_hint.visible = _hint.text != ""
		st.queue_redraw()
		return
	if raid.ledger_v2 != null:
		var cc: int = raid.carried_count()
		st.carried = cc
		st.carry_max = int(raid.rcfg().get("essence", {}).get("carry_max", 12))
		st.loose = maxi(0, motes - cc)
		var w: Dictionary = raid.ward_counts()
		st.ward[0] = int(w["chaff"])
		st.ward[1] = int(w["soldier"])
		st.ward[2] = int(w["elite"])
		st.ward[3] = int(w["big"])
		var rc: Dictionary = raid.ledger_v2.raised_counts()
		if rc["chaff"] != _raised_key[0] or rc["soldier"] != _raised_key[1] or rc["elite"] != _raised_key[2]:
			_raised_key = [rc["chaff"], rc["soldier"], rc["elite"]]
			st.raised_text = hud_fmt("raised_ranks", [rc["chaff"], rc["soldier"], rc["elite"]])
	_hint.visible = not raid.first_raise_done and not raid._ended
	if _legend != null:
		_legend.visible = not raid._ended
	if retreat_open() and (raid._ended or not exit_enabled()):
		_retreat.close()   # she walked off the exit (or the run ended): the choice is gone
		_retreat_t = 0.0
	elif retreat_open():
		# not modal: a pickup while it shows changes what a retreat pays, so its lines follow, 4 times a second
		_retreat_t += _delta_real()
		if _retreat_t >= 0.25:
			_retreat_t = 0.0
			_retreat.avoid_right_x = _stat_plate_right()
			_retreat.refresh_lines(_retreat_lines())
	if _door_prompt != null:
		var dr: String = raid.held_door.row_text()
		if dr != _door_text:
			_door_text = dr
			st.set_door(RaidHud.wrap_chunks(dr, ThemeDB.fallback_font, st._val, st.value_w()),
				Palette.c("danger" if raid.held_door.state == "shut" else "text"))
		var dp: String = raid.held_door.prompt_text() if not raid._ended else ""
		if dp != _door_prompt.text:
			_door_prompt.text = dp
		_door_prompt.visible = dp != ""
	if not raid.is_boss():
		st.set_phyl(raid.phylactery_left())
		st.phyl_word = RaidLogic.phylactery_word(st.words, st.phyl)
		if st.phyl_word != "":
			# no revive is a state, not a mood: `danger` whatever her hp (the halo's dashes say it in the world)
			st.phyl_tone = Palette.c("danger")
		# the checkpoint risk: BANKED is the last snapshot, UNBANKED is what a death loses now. Rebuilt only
		# when what they show changes (banked and found_loot are replaced, never edited, when they change)
		var carried: int = raid.carried_count()
		var floor_n: int = raid.pickups_left()
		if _loot_key.is_empty() or not is_same(_loot_key[0], raid.endings.banked) or not is_same(_loot_key[1], raid.found_loot) \
				or int(_loot_key[2]) != carried or int(_loot_key[3]) != floor_n:
			_loot_key = [raid.endings.banked, raid.found_loot, carried, floor_n]
			var bk: Dictionary = RaidLogic.loot_counts(raid.endings.banked)
			var ub: Dictionary = RaidLogic.unbanked(raid.found_loot, carried, raid.endings.banked)
			if _clearing:   # the win is banked: what the clear card shows, and nothing at stake
				bk = _clear_counts
				ub = RaidLogic.loot_counts(RaidLogic.empty_loot())
			st.set_loot(RaidLogic.loot_line(bk), RaidLogic.loot_line(ub))
			_risk = ub
			st.unbanked_n = int(ub["total"])
			st.floor_n = floor_n
			st.set_key(floor_n > 0)
			_push_t = 1.0   # the push line's "at risk" follows UNBANKED on the same frame
		_push_t += _delta_real()
		if _push != null and _push_t >= 0.25:
			_push_t = 0.0
			_update_push()
		var at_exit: bool = raid.exit_hint_ready()
		var hint_words: Dictionary = _hint_words   # cached in build
		_hint.text = RaidLogic.hint_text(hint_words, raid.trance_active, at_exit)
		if at_exit:
			_hint.visible = true
		_hint2.text = RaidLogic.hint_sub_text(hint_words, raid.trance_active, at_exit, raid.first_raise_done)
		_hint2.visible = _hint.visible and _hint2.text != "" and not _undead_cue_up()
		# the "your undead fight on their own" cue (once per run)
		if not _undead_cue_shown:
			var alive := 0
			for a in raid.allies:
				if is_instance_valid(a) and a.alive:
					alive += 1
			var cues: Dictionary = raid.rcfg().get("hud", {}).get("cues", {})
			if RaidLogic.undead_cue_due(_undead_cue_shown, raid.kills, _scene_s, float(cues.get("undead_delay_s", 5.0)), alive):
				_undead_cue_shown = true
				show_cue(str(cues.get("undead_text", "")), float(cues.get("undead_s", 3.5)), "undead")
	st.queue_redraw()


func _delta_real() -> float:
	return get_process_delta_time() / maxf(0.05, Engine.time_scale)


static func _goal_cfg(r: Node) -> Dictionary:
	return r.rcfg().get("hud", {}).get("goal", {})


## T4: the awake warden the WardenBlock shows (null while dormant, dead or absent).
func _awake_warden() -> RaidWarden:
	if raid.warden_run == null:
		return null
	var w = raid.warden_run.warden
	if w == null or not is_instance_valid(w) or not w.alive or not w.awake:
		return null
	return w


## T4: the goal block shows while no WardenBlock does and the run lives; its rows are rebuilt four times a
## second (and set only when they change). While it is hidden (the warden awake, the run ended) nothing is
## rebuilt, and the first frame it may show again rebuilds at once.
func _tick_goal(dt: float) -> void:
	if raid._ended or _awake_warden() != null:
		_goal_block.visible = false
		_goal_t = 1.0
		return
	_goal_t += dt
	if _goal_t >= 0.25:
		_goal_t = 0.0
		_update_goal()
	_goal_block.visible = _goal_block.height > 0.0


## The HUD's screen rects that cover the world's top: the fort's title and StatBlock (top-left) and the
## top-centre block. A sleeping warden's name plate under one of them moves below its ring.
func occluder_rects() -> Array:
	var out: Array = []
	if _stats != null and _stats.is_visible_in_tree():
		out.append((_stats.get_parent() as Control).get_global_rect())
	var tb := top_block_rect()
	if tb.has_area():
		out.append(tb)
	return out


## The screen rect of the top-centre block that shows (the goal block, else the warden's): empty when neither
## does. The banner steps down under it and the edge chevrons stay clear of it (RaidLogic.edge_clear_of).
func top_block_rect() -> Rect2:
	if _goal_block != null and _goal_block.visible:
		return Rect2(_goal_block.global_position, Vector2(_goal_block.size.x, _goal_block.height))
	if _warden_block != null and _warden_block.visible:
		return Rect2(_warden_block.global_position, Vector2(_warden_block.size.x, RaidLogic.TOP_BLOCK_BASE_H + (_warden_block as WardenBlock).extra_h))
	return Rect2()


## The rows: the goal line, then (warden alive) the route and how to break it, or (warden down) the chest;
## a held raid keeps only its goal. Plus the no-army row when nothing can be raised.
func _update_goal() -> void:
	var g := _goal_cfg(raid)
	var wr: RaidWardenRun = raid.warden_run
	var held: bool = raid.held
	var w = wr.warden if wr != null else null
	var alive: bool = w != null and is_instance_valid(w) and w.alive
	var s := {"held": held, "fort_name": raid.fort_name(), "warden_alive": alive, "warden_name": "",
		"route_text": "", "break_rows": [], "chest": wr != null and wr.chest != null, "no_army": false,
		"goal_px": int(g.get("goal_px", 17)), "route_px": int(g.get("route_px", 14)), "row_px": int(g.get("row_px", 15)),
		"break_px": int(raid.rcfg().get("hud", {}).get("break_row_px", 15))}
	if not held and alive:
		var sp: Dictionary = w.spec
		s["warden_name"] = str(sp.get("name", ""))
		s["route_text"] = _route_text()
		s["break_rows"] = break_rows(raid, sp, int(w.meter_n))
		s["break_rows_compact"] = break_rows(raid, sp, int(w.meter_n), true)
	elif not held and wr != null:
		s["warden_name"] = wr.warden_name
	s["no_army"] = (held or alive or s["chest"]) and _no_army()   # the row follows a goal row only
	# the sleeping warden's ring must stay clear: compact rows while the block's FULL rect (measured with the full
	# rows even when compact shows, so it cannot flicker) meets the ring's screen rect
	var full_rows := RaidLogic.goal_rows(g, s)
	var vw := get_viewport().get_visible_rect().size.x
	var full := Rect2(Vector2(vw * 0.5 + _goal_block.offset_left, _goal_block.offset_top),
		Vector2(_goal_block.offset_right - _goal_block.offset_left, _goal_block.height_for(full_rows)))
	s["compact"] = alive and not held and RaidLogic.goal_compact(full, _sleeping_ring_rect(w))
	_goal_block.set_rows(RaidLogic.goal_rows(g, s) if s["compact"] else full_rows)


## The screen rect of the sleeping warden's ring and glyph (RaidLogic.warden_ring_rect, through the canvas
## transform so it follows the camera); empty while it is awake, down or absent.
func _sleeping_ring_rect(w: Variant) -> Rect2:
	if w == null or not is_instance_valid(w) or not w.alive or w.awake:
		return Rect2()
	var xf: Transform2D = (w as Node2D).get_global_transform_with_canvas()
	return RaidLogic.warden_ring_rect(xf.origin, xf.get_scale().x, float(w.radius), w.wcfg().get("presence", {}))


## The break line, the takes line (when something multiplies a blow) and the counter line for a warden's spec.
## `compact` builds the COUNTER row without its "make one at the Crypt slab" advice (the goal block over a sleeping ring).
static func break_rows(raid: Node, sp: Dictionary, meter_n := -1, compact := false) -> Array:
	# the pips the player sees are the warden node's meter_n (its bands; the Pyre-priest adds acolyte pips);
	# the config's meter_pips only when there is no node
	var wcfg: Dictionary = raid.rcfg().get("wardens", {})
	var words: Dictionary = wcfg.get("words", {})
	var pips := meter_n if meter_n > 0 else int(wcfg.get("meter_pips", 12))
	var rows: Array = [WardenLogic.break_line(words, sp, pips)]
	var tk := WardenLogic.takes_line(words, sp)
	if tk != "":
		rows.append(tk)
	var stat := str((sp.get("weak_point", {}) as Dictionary).get("stat", ""))
	# the bigs the warden's own counter checks count (RaidLogic.counter_party_values): not the one spent on the door's plate
	var hd = raid.held_door
	var vals: Array = RaidLogic.counter_party_values(raid.allies, stat, hd.holder if hd != null and hd.committed() else null)
	var cl := WardenLogic.counter_line(words, sp, vals, compact)
	if cl != "":   # "" when the counter changes nothing in this fight (WardenLogic.counter_role)
		rows.append(cl)
	return rows


## "room 2 of 4 · the warden is 2 rooms on · next door NE": the route's length from the spawn's room, the hops left
## from Relish's room (kept through a doorway band) and the compass word of the next step of the walk to the warden.
func _route_text() -> String:
	var lay: Dictionary = raid.layout
	var rel: RaidRelish = raid.relish
	var wroom := int(lay.get("warden_room", -1))
	if rel == null or lay.is_empty() or wroom < 0 or not lay.has("room_hops"):
		return ""
	var hops: Array = lay["room_hops"]
	if _route_len < 0:
		var sr := RaidLogic.room_of(lay, lay.get("spawn", rel.global_position))
		if sr >= 0:
			_route_len = maxi(0, int((hops[sr] as Array)[wroom]) + 1)   # 0: no walk from the spawn's room (the line drops "room n of m")
	var rf := RaidLogic.room_of(lay, rel.global_position)
	if rf >= 0:
		_hops_left = int((hops[rf] as Array)[wroom])
	if _route_len < 0 or _hops_left < 0:
		return ""
	var goal: Vector2 = ((lay["rooms"] as Array)[wroom] as Rect2).get_center()
	var step := LayoutLogic.waypoint(lay, rel.global_position, goal, rel.radius)
	return RaidLogic.route_line(_goal_cfg(raid), _route_len, _hops_left, RaidLogic.compass(step - rel.global_position))


## Nothing to raise with: no undead alive, no loose or carried essence, no unstirred corpse pile.
func _no_army() -> bool:
	var alive := 0
	for a in raid.allies:
		if is_instance_valid(a) and a.alive:
			alive += 1
	var carried: int = raid.carried_count()
	var loose := maxi(0, raid.get_tree().get_node_count_in_group("raid_essence") - carried)
	var piles := 0
	for o in raid.get_tree().get_nodes_in_group("raid_piles"):
		if is_instance_valid(o) and not o._stirred and o._shrink < 0.0:
			piles += 1
	return RaidLogic.no_army(alive, loose, carried, piles)


## The push-or-retreat line, 4 times a second and on the frame UNBANKED changes: the living left,
## the nearest exit by walking distance (the compass word of the first step of the route to it,
## LayoutLogic.waypoint: the doorway to take, so it never points through a wall; and how many rooms
## away), and what a death would lose now. No exit found drops the exit clause. Its text is set only
## when it changes.
func _update_push() -> void:
	var lay: Dictionary = raid.layout
	var rel: RaidRelish = raid.relish
	if rel == null or lay.is_empty():
		return
	var doors: Array = lay.get("doors", [])
	var best := -1
	var bd := INF
	for i in doors.size():
		if not bool(doors[i].get("exit", false)):
			continue
		var d := LayoutLogic.route_dist(lay, rel.global_position, doors[i]["inner"], rel.radius)
		if d < bd:
			bd = d
			best = i
	exit_pos = Vector2.INF if best < 0 else (doors[best]["inner"] as Vector2)
	var word := ""
	var hops := -1
	var at_exit: bool = raid.endings.exit_idx >= 0
	if best >= 0 and not at_exit:
		var step := LayoutLogic.waypoint(lay, rel.global_position, exit_pos, rel.radius)
		word = RaidLogic.compass(step - rel.global_position)
		var rf := RaidLogic.room_of(lay, rel.global_position)
		var rt := int(doors[best].get("room", -1))
		if rf >= 0 and rt >= 0 and lay.has("room_hops"):
			hops = int(((lay["room_hops"] as Array)[rf] as Array)[rt])
	_push.set_text(RaidLogic.push_line(_goal_cfg(raid), raid.enemies.size(), word, hops, _risk, at_exit,
		raid.endings.rooms_seen(), (lay.get("rooms", []) as Array).size(), not _clearing))


## Width the push line may use without running under the warden's block (narrow windows wrap it).
func _push_room() -> float:
	var room := _push.size.x
	if _warden_block != null and _warden_block.visible:
		var block_right := _warden_block.global_position.x + _warden_block.size.x
		room = minf(room, _push.global_position.x + _push.size.x - block_right - 12.0)
	if _goal_block != null and _goal_block.visible:
		var goal_right := _goal_block.global_position.x + _goal_block.size.x
		room = minf(room, _push.global_position.x + _push.size.x - goal_right - 12.0)
	return maxf(160.0, room)


## The hint's plate: the visible hint lines stacked up from `hint.bottom_px` above the screen bottom (clear of the
## danger frame's inner edge, 10 px in), a ground plate fitted to them. Refit only when what shows changes.
func _fit_hint_plate() -> void:
	if _hint_plate == null:
		return
	var show := _hint.visible and _hint.text != ""
	var sub := show and _hint2.visible and _hint2.text != ""
	var sub_text := _hint2.text if sub else ""
	if _hp_fitted and show == _hp_show and _hint.text == _hp_text and sub_text == _hp_sub:
		return
	_hp_fitted = true
	_hp_show = show
	_hp_text = _hint.text
	_hp_sub = sub_text
	_hint_plate.visible = show
	var hc: Dictionary = raid.rcfg().get("hud", {}).get("hint", {})
	var bottom_px := float(hc.get("bottom_px", 24))
	var top := -bottom_px   # the plate's top (its bottom while the hint is hidden): the held door's prompt sits over it
	if show:
		var f := ThemeDB.fallback_font
		var hpx := int(hc.get("font_px", 19))
		var spx := int(hc.get("sub_font_px", 15))
		var L := RaidLogic.hint_plate_layout(bottom_px, float(hc.get("pad_px", 14)), float(hc.get("gap_px", 4)),
			f.get_string_size(_hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hpx).x, _hint.get_line_height(),
			f.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, spx).x if sub else 0.0, _hint2.get_line_height() if sub else 0.0)
		if sub:
			_hint2.offset_bottom = L["sub_bottom"]
			_hint2.offset_top = L["sub_top"]
		_hint.offset_bottom = L["hint_bottom"]
		_hint.offset_top = L["hint_top"]
		_hint_plate.offset_left = L["plate_left"]
		_hint_plate.offset_right = L["plate_right"]
		_hint_plate.offset_top = L["plate_top"]
		_hint_plate.offset_bottom = L["plate_bottom"]
		top = L["plate_top"]
	if _door_prompt != null:
		# over the plate (not a hand-computed offset): refitted whenever the plate is
		_door_prompt.offset_bottom = top - float(hc.get("door_gap_px", 8))
		_door_prompt.offset_top = _door_prompt.offset_bottom - float(hc.get("door_prompt_h", 28))


## The banner's plate: the widest line plus a margin, as tall as its lines, centred under it.
func _fit_banner_plate() -> void:
	if _banner_plate == null:
		return
	var f := ThemeDB.fallback_font
	var w := 0.0
	var lines := _banner.text.split("\n")
	for l in lines:
		w = maxf(w, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x)
	var h := float(lines.size()) * _banner.get_line_height() + 8.0
	_banner_plate.offset_left = -w * 0.5 - 14.0
	_banner_plate.offset_right = w * 0.5 + 14.0
	_banner_plate.offset_top = _banner.offset_top - 3.0
	_banner_plate.offset_bottom = _banner.offset_top - 3.0 + h
	_banner_plate.visible = _banner.visible


## Screen point at the end of the "N on the floor" note (the loot pointer starts there), or INF
## when nothing lies on the floor.
func floor_anchor() -> Vector2:
	if _stats == null or _stats.floor_n <= 0 or _stats.floor_end == Vector2.INF:
		return Vector2.INF
	return _stats.global_position + _stats.floor_end


func flash(color: Color) -> void:
	var c := color
	c.a = 0.85
	_flash.color = c
	_flash.visible = true
	_flash_t = 0.0


## The warden is beaten and the clear card is up (RaidWardenRun.on_chest_opened, not the measuring bot): the HUD
## must not contradict the win. The banner under the card is hidden (and none shows after), BANKED reads the win's
## loot counts, UNBANKED reads none with no stakes row, and the push line drops its "at risk" clause.
func on_clear(win_counts: Dictionary) -> void:
	_clearing = true
	_clear_counts = win_counts
	_banner_t = -1.0
	_banner_live = Callable()
	_cue_queue.clear()
	_banner.visible = false
	if _banner_plate != null:
		_banner_plate.visible = false
	_loot_key = []   # refresh() rebuilds BANKED/UNBANKED from the win on its next pass
	_push_t = 1.0


## A plain banner line for `secs` seconds (warden wake, last chance, victory).
func show_banner(text: String, secs: float, color_key := "relish") -> void:
	if _clearing:
		return
	_banner_live = Callable()
	_banner.text = text
	_banner.add_theme_color_override("font_color", Palette.c(color_key))
	_banner.visible = true
	_banner_t = secs
	_fit_banner_plate()


## An onboarding cue (T2): shown at once when no banner is up; otherwise it waits in a small queue and
## shows when the banner hides, and is dropped after hud.cues.max_wait_s real seconds. A cue never
## replaces a visible banner. Long cues break at their " · " so they fit the banner's width.
func show_cue(text: String, secs: float, color_key: String) -> void:
	if _banner_t < 0.0:
		show_banner(text.replace(" · ", "\n"), secs, color_key)
		return
	_cue_queue.append([text, secs, color_key, 0.0])


## The one-shot "your undead fight on their own" toast is on screen: the idle sub-line says the same words, so it
## waits (the banner's text is the cue's, broken at its " · ").
## The undead cue as the banner shows it (its " · " parts on their own lines), made once: compared every frame.
var _cue_undead_lines := ""   # set in setup from hud.cues undead_text


func _undead_cue_up() -> bool:
	return _banner != null and _banner.visible and _banner.text == _cue_undead_lines


func _tick_cues() -> void:
	if _cue_queue.is_empty():
		return
	if _banner_t < 0.0:
		var c: Array = _cue_queue.pop_front()
		show_banner(str(c[0]).replace(" · ", "\n"), float(c[1]), str(c[2]))
		return
	var max_wait := float(raid.rcfg().get("hud", {}).get("cues", {}).get("max_wait_s", 6.0))
	var dt := _delta_real()
	for i in range(_cue_queue.size() - 1, -1, -1):
		_cue_queue[i][3] = float(_cue_queue[i][3]) + dt
		if float(_cue_queue[i][3]) >= max_wait:
			_cue_queue.remove_at(i)


## The first essence mote to join Relish's slots (the raid calls this from carry_add): the cue, once.
func on_first_carry() -> void:
	if _first_mote_cue_shown:
		return
	_first_mote_cue_shown = true
	var cues: Dictionary = raid.rcfg().get("hud", {}).get("cues", {})
	show_cue(str(cues.get("first_mote_text", "")), float(cues.get("first_mote_s", 4.0)), "essence")


## A banner whose text `provider` recomputes 4 times a second while it shows (the last chance's
## "N essence to bank" falls as Relish gathers).
func show_banner_live(provider: Callable, secs: float, color_key := "relish") -> void:
	show_banner(str(provider.call()), secs, color_key)
	_banner_live = provider
	_banner_live_t = 0.0


## The banner when a checkpoint room banks new loot.
func show_checkpoint(loot: Dictionary) -> void:
	_banner.add_theme_color_override("font_color", Palette.c("relish"))
	_banner.text = hud_fmt("checkpoint", [
		int(loot["relics"]), (loot["blueprints"] as Array).size(), (loot["husks"] as Array).size(),
		(loot["remnants"] as Array).size(), int(loot["essence"])])
	_banner_live = Callable()
	_banner.visible = true
	_banner_t = float(raid.rcfg().get("checkpoint", {}).get("banner_s", 2.5))
	_fit_banner_plate()


## Retreat is live only at an exit (never in the boss: there is no retreat from Vei).
func exit_enabled() -> bool:
	return raid != null and raid.can_retreat()


## `text` in lines no wider than `max_w` at `font_px`: whole " · " chunks where they fit, a long chunk
## broken at spaces (draw only: the StatBlock's DOOR row wraps on its plate).
static func wrap_chunks(text: String, font: Font, font_px: int, max_w: float) -> PackedStringArray:
	return RaidLogic.wrap_chunks(text, font, font_px, max_w)   # the one wrap, headless-testable in RaidLogic


func open_exit_dialog() -> void:
	if _retreat == null or raid._ended or not exit_enabled():
		return
	_retreat.avoid_right_x = _stat_plate_right()
	_retreat.open(_retreat_lines())


## The stat block plate's real right edge on screen (the retreat panel sits clear of it, RaidLogic.retreat_panel_rect).
func _stat_plate_right() -> float:
	return _stats.get_global_rect().end.x if _stats != null else 0.0


## The retreat panel's lines now: what a retreat pays (found loot and carried essence) and what stays. A big
## spent on the held door is lost, said by its state (on the plate, or shut in at the cache).
func _retreat_lines() -> Array:
	var hd = raid.held_door
	var keep := RaidLogic.loot_counts(RaidLogic.loot_snapshot(raid.found_loot, raid.carried_count()))
	# the right column reads what the death card reads (RaidEndings.death_inputs, death_next_row, the revive rule)
	var di: Dictionary = raid.endings.death_inputs()
	var rw: Dictionary = raid.rcfg().get("hud", {}).get("retreat", {})
	var dw: Dictionary = raid.rcfg().get("death", {})
	return [RaidLogic.retreat_keep_lines(rw, raid.rcfg().get("loot_uses", {}), raid.held, keep,
			RaidLogic.held_door_retreat_line(raid.rcfg().get("held_door", {}), hd.state, hd.holder_name) if hd != null else ""),
		RaidLogic.retreat_fall_lines(rw, dw, raid.endings.phylactery_left(), di["unbanked"], int(di["party_n"]),
			RaidLogic.death_next_row(raid.seed_data, dw), str(di["shut"]))]


## The retreat panel shows (the raid closes it on a stay key: Space, right mouse, Esc).
func retreat_open() -> bool:
	return _retreat != null and _retreat.is_open()


func close_retreat() -> void:
	if _retreat != null:
		_retreat.close()


## Standalone runs: show the emitted result so the scene is testable by itself.
func show_result(result: Dictionary, telemetry := "") -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300.0
	panel.offset_top = -190.0
	panel.offset_right = 300.0
	panel.offset_bottom = 190.0
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.text = "finished(result) emitted — standalone run\n" + telemetry + "\n\n" + JSON.stringify(result, "  ")
	panel.add_child(lbl)


# ------------------------------------------------------------- sub-controls --
## The compact stat block. One neutral label tone (`text_dim`) and one value tone (`text`); the
## pips carry the colour (WARD undead, essence, phylactery relish), so meaning is by shape and
## position, not hue. Everything is drawn from cached ints; nothing is allocated per frame.
class StatBlock:
	extends Control
	const RANK_KEYS := ["rank_chaff", "rank_soldier", "rank_elite", "rank_big"]   # the hud.stats keys of the four rank labels
	var boss := false
	var living := 0
	var carried := 0
	var carry_max := 12
	var loose := 0
	var ward := [0, 0, 0, 0]
	var raised_text := ""
	var phyl := 0
	var phyl_meaning := PackedStringArray()   # its dim meaning rows (RaidLogic.phylactery_meaning), kept by set_phyl
	var phyl_extra := 0      # rows its meaning takes beyond one
	var phyl_word := ""      # "NO REVIVE · a death ends the raid" at 0 charges (RaidLogic.phylactery_word)
	var phyl_tone: Color = Palette.c("danger")   # the NO REVIVE words: `danger` whenever no charge is left
	var banked_text := ""
	var unbanked_text := ""
	var banked_lines := PackedStringArray()     # banked_text wrapped to value_w() (set_loot); empty: "none"
	var unbanked_lines := PackedStringArray()
	var unbanked_n := 0     # items + essence a death would lose now
	var floor_n := 0         # pickups still on the floor
	var floor_end := Vector2.INF   # local end of the "N on the floor" note (the loot pointer's start)
	var _row := 20.0
	var _lab := 13
	var _val := 15
	var _pip := 7.0
	var _row_max := 24
	var _col := 92.0                        # the label column's width (hud.stats label_col)
	var _plate_w := 420.0                   # the plate's width (hud.stats plate_w)
	var _val_pad := 8.0                     # the space kept right of the value column (hud.stats value_pad)
	var words: Dictionary = {}              # raid.json hud.stats
	var detail_px := 14                     # the detail lines' size, drawn in full `text`
	var label_alpha := 0.85                 # the row labels' brightness (text at this alpha)
	var essence_lines := PackedStringArray()   # hud.stats essence_meaning wrapped to value_w() at detail_px (setup)
	var key_pile_lines := PackedStringArray()   # hud.stats key_pile wrapped to the plate's inner width at detail_px (setup)
	var plate_alpha := 0.96
	var show_key := false
	var door_lines := PackedStringArray()   # D-e task 6: the held door's DOOR row, wrapped (empty: no row)
	var door_tone: Color = Palette.c("text")

	func setup(p_boss: bool) -> void:
		boss = p_boss
		var c: Dictionary = ConfigDb.data.get("raid", {}).get("hud", {})
		_pip = float(c.get("pip_px", 7.0))
		_lab = int(c.get("label_px", 13))
		_val = int(c.get("value_px", 15))
		_row_max = int(c.get("pip_row_max", 24))
		plate_alpha = float(c.get("plate_alpha", 0.96))
		words = c.get("stats", {})
		_plate_w = float(words.get("plate_w", _plate_w))
		_col = float(words.get("label_col", _col))
		_val_pad = float(words.get("value_pad", _val_pad))
		_row = float(words.get("row_px", _row))
		detail_px = int(words.get("detail_px", 14))
		label_alpha = float(words.get("label_alpha", 0.85))
		essence_lines = RaidLogic.wrap_each(PackedStringArray([str(words.get("essence_meaning", ""))]), ThemeDB.fallback_font, detail_px, value_w())
		key_pile_lines = RaidLogic.wrap_each(PackedStringArray([str(words.get("key_pile", ""))]), ThemeDB.fallback_font, detail_px, _plate_w - 12.0)
		var rows := 3.0 if boss else 14.0   # living, essence, raised | + 4 ward rows, essence meaning, phylactery, its meaning, banked, unbanked, stakes
		custom_minimum_size = Vector2(_plate_w, rows * _row + 8.0)
		if not boss:
			_fit()

	## The floor-loot key (two rows under the stakes) shows while something lies on the floor.
	func set_key(on: bool) -> void:
		if on == show_key:
			return
		show_key = on
		_fit()

	## The held door's DOOR row (D-e task 6): its wrapped lines (none: no row) and their tone.
	func set_door(lines: PackedStringArray, tone: Color) -> void:
		door_lines = lines
		door_tone = tone
		_fit()

	## The value column's width on the plate.
	func value_w() -> float:
		return _plate_w - _col - _val_pad

	## BANKED / UNBANKED (RaidLogic.loot_line), wrapped to the value column with each kind whole; the plate
	## grows a row per extra line. Called only when what they show changes.
	func set_loot(banked: String, unbanked: String) -> void:
		banked_text = banked
		unbanked_text = unbanked
		banked_lines = RaidLogic.wrap_loot_line(banked, ThemeDB.fallback_font, _val, value_w())
		unbanked_lines = RaidLogic.wrap_loot_line(unbanked, ThemeDB.fallback_font, _val, value_w())
		_fit()

	## The PHYLACT. count: its meaning is one row, or two with none left (RaidLogic.phylactery_meaning).
	func set_phyl(n: int) -> void:
		if n == phyl and not phyl_meaning.is_empty():
			return   # called every frame: nothing to rebuild while the count holds
		phyl = n
		phyl_meaning = RaidLogic.wrap_each(RaidLogic.phylactery_meaning(words, n), ThemeDB.fallback_font, detail_px, value_w())
		var extra := phyl_meaning.size() - 1
		if extra != phyl_extra:
			phyl_extra = extra
			_fit()

	func _fit() -> void:
		var loot_extra := maxi(0, banked_lines.size() - 1) + maxi(0, unbanked_lines.size() - 1)
		var ess_extra := maxi(0, essence_lines.size() - 1)
		custom_minimum_size = Vector2(_plate_w, RaidLogic.stat_block_height(_row, ess_extra, phyl_extra, loot_extra, 1 + key_pile_lines.size() if show_key else 0, door_lines.size()))

	## A floor glyph as the pickups draw it (RaidLoot.floor_glyph shapes), small, at `p`.
	func _key_glyph(p: Vector2, shape: String, col: Color) -> void:
		var s := 5.0
		match shape:
			"gem":
				draw_polyline(PackedVector2Array([p + Vector2(0, -s * 1.2), p + Vector2(s, -s * 0.25), p + Vector2(0, s * 1.2), p + Vector2(-s, -s * 0.25), p + Vector2(0, -s * 1.2)]), col, 1.5)
			"scroll":
				draw_polyline(PackedVector2Array([p + Vector2(-s, -s * 0.8), p + Vector2(s * 0.55, -s * 0.8), p + Vector2(s, -s * 0.35), p + Vector2(s, s * 0.8), p + Vector2(-s, s * 0.8), p + Vector2(-s, -s * 0.8)]), col, 1.3)
			"husk":
				draw_polyline(PackedVector2Array([p + Vector2(0, -s * 1.2), p + Vector2(s * 0.75, -s * 0.6), p + Vector2(s * 0.75, s * 0.6), p + Vector2(0, s * 1.2), p + Vector2(-s * 0.75, s * 0.6), p + Vector2(-s * 0.75, -s * 0.6), p + Vector2(0, -s * 1.2)]), col, 1.5)
			_:
				draw_polyline(PackedVector2Array([p + Vector2(-s * 0.55, s), p + Vector2(-s * 0.1, -s * 1.25), p + Vector2(s * 0.55, s * 0.2), p + Vector2(-s * 0.55, s)]), col, 1.5)

	func _draw_key(y: float) -> void:
		var f := ThemeDB.fallback_font
		var x := 6.0
		for k in [["relic", "key_relic"], ["remnant", "key_remnant"], ["husk", "key_husk"], ["blueprint", "key_blueprint"]]:
			var g := RaidLoot.floor_glyph(str(k[0]), false)
			var kw := _word(str(k[1]))
			_key_glyph(Vector2(x + 6.0, y - 4.0), str(g["shape"]), Palette.c(str(g["key"])))
			draw_string(f, Vector2(x + 16.0, y), kw, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_px, Palette.c("text"))
			x += 22.0 + f.get_string_size(kw, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_px).x
		for i in key_pile_lines.size():
			draw_string(f, Vector2(6.0, y + _row * float(i + 1)), key_pile_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, detail_px, Palette.c("text"))

	## The stat block's word `key` (raid.json hud.stats; blank when it has none).
	func _word(key: String) -> String:
		return str(words.get(key, ""))

	## A row label; `wide` lets it run past the label column (a header whose row has no value).
	func _label(y: float, text: String, wide := false) -> void:
		draw_string(ThemeDB.fallback_font, Vector2(6, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0 if wide else _col, _lab, Palette.c("text", label_alpha))

	func _value(x: float, y: float, text: String, col: Variant = null) -> float:
		var f := ThemeDB.fallback_font
		var tone: Color = Palette.c("text") if col == null else col
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _val, tone)
		return x + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _val).x

	## `n` pips left to right from x, `filled` of them solid; returns the x after the row.
	func _pips(x: float, y: float, n: int, filled: int, col: Color, r: float, diamond := false) -> float:
		var step := r * 2.0 + 3.0
		var dim := col
		dim.a = 0.8   # a hollow pip's outline: a line, held at 3:1 over the plate by the contrast test
		for i in n:
			var p := Vector2(x + r + step * i, y)
			if diamond:
				var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)])
				if i < filled:
					draw_colored_polygon(pts, col)
				else:
					draw_polyline(pts, dim, 1.3)
			elif i < filled:
				draw_circle(p, r, col)
			else:
				draw_arc(p, r - 0.6, 0.0, TAU, 12, dim, 1.3)
		return x + step * n

	func _draw() -> void:
		# the plate sits near-opaque so a world glyph under the block never crosses its text
		draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ground", plate_alpha))
		var y := _row - 5.0
		var und := Palette.c("undead")
		_label(y, str(words.get("living_label", "")))
		var lx := _pips(_col, y - 5.0, 1, 0, Palette.c("living"), _pip * 0.6)   # hollow ring = the living
		_value(lx + 4.0, y, RaidLogic.enemies_text(living, words))
		y += _row
		if boss:
			_label(y, _word("label_essence"))
			_value(_col, y, str(loose))
			y += _row
		else:
			_label(y, str(words.get("ward_head", "")), true)
			y += _row
			for i in 4:
				var n := int(ward[i])
				_label(y, _word(RANK_KEYS[i]))
				var r := _pip * (0.5 + 0.12 * i)
				var shown := mini(n, _row_max)
				var x := _pips(_col, y - 5.0, shown, shown, und, r, i == 3)
				if n > 0:   # a zero rank is an empty row (the label stays: it teaches the chain's order)
					_value(x + 4.0, y, ("+" if n > _row_max else "") + str(n))
				y += _row
			_label(y, _word("label_essence"))
			var ex := _pips(_col, y - 5.0, carry_max, carried, Palette.c("essence"), _pip * 0.5)
			_value(ex + 6.0, y, "%d/%d" % [carried, carry_max])
			if loose > 0:
				_value(ex + 6.0 + 60.0, y, RaidLogic.word_fmt(words, "loose", [loose]))
			y += _row
			for el in essence_lines:
				draw_string(ThemeDB.fallback_font, Vector2(_col, y), el, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_px, Palette.c("text"))
				y += _row
		_label(y, _word("label_raised"))
		_value(_col, y, raised_text)
		y += _row
		if not boss:
			_label(y, _word("label_phyl"))
			var px := _pips(_col, y - 5.0, phyl, phyl, Palette.c("relish"), _pip * 0.6, true)
			var vx := _value(px + 4.0, y, str(phyl), phyl_tone if phyl_word != "" else null)
			if phyl_word != "":
				# no revive left: the state in words (the halo says it in the world)
				var cut := phyl_word.find(" · ")
				var head := phyl_word if cut < 0 else phyl_word.substr(0, cut)
				var hx := _value(vx + 10.0, y, head, phyl_tone)
				if cut >= 0:
					draw_string(ThemeDB.fallback_font, Vector2(hx, y), phyl_word.substr(cut), HORIZONTAL_ALIGNMENT_LEFT, -1, detail_px, Palette.c("text"))
			y += _row
			# what a phylactery charge is (RaidLogic.phylactery_meaning, wrapped), in full text, as the ESSENCE row's meaning line
			for ml in phyl_meaning:
				draw_string(ThemeDB.fallback_font, Vector2(_col, y), ml, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_px, Palette.c("text"))
				y += _row
			# zero kinds are hidden; nothing at all is one dim word; a long line wraps under itself (set_loot)
			_label(y, _word("label_banked"))
			if banked_lines.is_empty():
				_value(_col, y, _word("none"), Palette.c("text_dim"))
				y += _row
			for ln in banked_lines:
				_value(_col, y, ln)
				y += _row
			var risk := unbanked_n > 0
			var tone := Palette.c("danger") if risk else Palette.c("text_dim")
			_label(y, _word("label_unbanked"))
			if unbanked_lines.is_empty():
				_value(_col, y, _word("none"), tone)
				y += _row
			for ln in unbanked_lines:
				_value(_col, y, ln, tone)
				y += _row
			# the stakes: one pip per unbanked thing (capped), then what it means
			floor_end = Vector2.INF
			if risk or floor_n > 0:
				var px2 := _pips(_col, y - 5.0, mini(unbanked_n, _row_max), mini(unbanked_n, _row_max), tone, _pip * 0.6, true)
				var note := (_word("at_risk") if risk else "") + ("" if floor_n <= 0 else (" · " if risk else "") + RaidLogic.word_fmt(words, "on_floor", [floor_n]))
				var nx := _value(px2 + 6.0, y, note, tone if risk else Palette.c("vei"))
				if floor_n > 0:
					floor_end = Vector2(nx + 4.0, y - 5.0)
			if show_key:
				_draw_key(y + _row)
			if not door_lines.is_empty():
				# the held door's big, on the plate: out of the WARD's big row while it is spent on the door
				var dy := y + _row * (2.0 + float(key_pile_lines.size()) if show_key else 1.0)
				_label(dy, _word("label_door"))
				for ln in door_lines:
					draw_string(ThemeDB.fallback_font, Vector2(_col, dy), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, _val, door_tone)
					dy += _row


class TranceMeter:
	extends Control
	var raid: Node = null
	var _w_ready := ""        # the three state words, formatted once on the first draw (raid.json hud.text)
	var _w_focus := ""
	var _w_cool := ""
	var _words_set := false

	func _process(_d: float) -> void:
		queue_redraw()

	## Cooldown reads by shape: one segment per second of cooldown, draining away.
	func _segmented(r: Rect2, remaining_frac: float, total_s: float, col: Color) -> void:
		var n := maxi(1, roundi(total_s))
		var w := r.size.x / n
		var left := remaining_frac * n
		for i in n:
			var fill := clampf(left - i, 0.0, 1.0)
			if fill > 0.0:
				draw_rect(Rect2(r.position.x + w * i, r.position.y, (w - 2.0) * fill, r.size.y), col)

	func _draw() -> void:
		if raid == null or raid.trance == null or raid._ended:
			return
		var tr = raid.trance
		if not _words_set:
			_words_set = true
			_w_ready = RaidHud.hud_fmt("trance_ready", [])
			_w_focus = RaidHud.hud_fmt("trance_focus", [])
			_w_cool = RaidHud.hud_fmt("trance_cooldown", [])
		var r := Rect2(0, 12, 150, 12)
		var violet := Palette.c("relish")
		draw_rect(r.grow(2.0), Palette.c("ground", 0.8))
		var word := ""
		var col := violet
		if tr.state == RaidTrance.State.READY:
			word = _w_ready
			draw_rect(r, Palette.c("relish", 0.85))
		elif tr.state == RaidTrance.State.ACTIVE:
			word = _w_focus
			draw_rect(Rect2(r.position, Vector2(r.size.x * tr.focus_frac(), r.size.y)), violet)
		elif tr.state == RaidTrance.State.COOLDOWN:
			word = _w_cool
			col = Palette.c("cooldown")
			_segmented(r, tr.cooldown_frac(), tr.cooldown_total, Palette.c("cooldown", 0.9))
		elif tr.state == RaidTrance.State.LOCKOUT:
			word = "…"
			col = Palette.c("danger")
			_segmented(r, tr.cooldown_frac(), tr.cooldown_total, Palette.c("danger", 0.5))
		draw_string(ThemeDB.fallback_font, Vector2(0, 8), word,
			HORIZONTAL_ALIGNMENT_LEFT, 190, 14, col)


## The awake warden's break meter (top centre; hidden while it sleeps and once it falls). Row 1:
## its name, the strength left as pips (`vei`, VISUAL-LANGUAGE law 9) with the phase notches where
## its phases are hp gates, "n/N", and the counterplay's running count: the Bellringer's
## "MUFFLED x n of m" (lit `undead` once it has worked, "braced" while a brace is up), the Huntsman's
## "INTERCEPTED x n · took k" (k pips taken inside stun windows). Pips a stun window took stay as
## `undead` rings with a slash; the open window's pips flash (steady under reduced motion).
## The Shieldwall's "FLANKED x n of m · took k" (hits from off its shield, of all the hits it took; k
## pips taken by them), the weak point's words until the first flank. The Pyre-priest's "SNUFFED x n ·
## took k" (acolytes a power big killed in one blow; k their pips), the weak point's words until the
## first snuff; its meter's right-hand pips are its acolytes.
## Row 2: the Bellringer's phase and its weak point; the Huntsman's CAUGHT track (danger diamonds,
## notched where catches change its phase) and whether it is hunting your dead; the Shieldwall's
## phase and its shield (WardenLogic.shield_label: arc, multipliers, turn rate, bash period); the
## Pyre-priest's phase, its acolytes left, its fire (WardenLogic.pyre_label: the ward, fires per beat
## and how many at Relish) and the essence it has burned (hidden at 0). Redrawn
## only when what it shows changes (or every frame while a stun window flashes).
class WardenBlock:
	extends Control
	var raid: Node = null
	var _key := -1
	var _key2 := -1
	var _t := 0.0
	var extra_h := 0.0   # the Huntsman's third row (what a catch costs) and a pack's row make the block taller
	var _key3 := -1
	var _rows_t := 1.0
	var break_rows: Array = []   # T4: the break / takes / counter lines (RaidHud.break_rows), drawn under the existing rows
	var break_lines := PackedStringArray()   # those rows wrapped to the plate (RaidLogic.wrap_break_rows): what is drawn and counted in extra_h
	var _wrap_w := -1.0
	var _row_step := -1.0   # hud.break_row_step, read once on first use (the _process and the draw both use it)
	var note_lines := PackedStringArray()   # the note under row 2, wrapped to the plate (break_row_px, WARDEN_NOTE_KEY): counted in extra_h
	var note_key := RaidLogic.WARDEN_NOTE_KEY

	func _step() -> float:
		if _row_step < 0.0:
			_row_step = float(raid.rcfg().get("hud", {}).get("break_row_step", 22.0))
		return _row_step

	func _warden() -> RaidWarden:
		if raid == null or raid.warden_run == null:
			return null
		var w = raid.warden_run.warden
		if w == null or not is_instance_valid(w) or not w.alive or not w.awake:
			return null
		return w

	func _process(d: float) -> void:
		var w := _warden()
		var show: bool = w != null and not raid._ended
		if show != visible:
			visible = show
			_key = -1
			_rows_t = 1.0
		if not show:
			return
		_t += d / maxf(0.05, Engine.time_scale)
		# T4: how it breaks, as rows at the bottom (4 times a second: the counter row follows the party)
		_rows_t += d / maxf(0.05, Engine.time_scale)
		if _rows_t >= 0.25:
			_rows_t = 0.0
			var nl := RaidLogic.wrap_chunks(_note_text(w), ThemeDB.fallback_font, int(raid.rcfg().get("hud", {}).get("break_row_px", 15)),
				RaidLogic.break_wrap_width(size.x, RaidLogic.WARDEN_BLOCK_INSET, float(raid.rcfg().get("hud", {}).get("break_wrap_min_px", 120.0))))
			var nk: String = "danger" if w is RaidPyrePriest and (w as RaidPyrePriest).living() <= 0 else RaidLogic.WARDEN_NOTE_KEY
			if nl != note_lines or nk != note_key:
				note_lines = nl
				note_key = nk
				_key = -1
			var nr := RaidHud.break_rows(raid, w.spec, int(w.meter_n))
			if nr != break_rows or size.x != _wrap_w:
				# the rows wrap to the plate's inner width, once per change (not per frame)
				break_rows = nr
				_wrap_w = size.x
				break_lines = RaidLogic.wrap_break_rows(nr, ThemeDB.fallback_font, int(raid.rcfg().get("hud", {}).get("break_row_px", 15)),
					RaidLogic.break_wrap_width(size.x, RaidLogic.WARDEN_BLOCK_INSET, float(raid.rcfg().get("hud", {}).get("break_wrap_min_px", 120.0))))
				_key = -1
		var eh: float = RaidLogic.warden_rows_layout(note_lines.size(), w.spec.has("pack"), break_lines.size(), _step())["extra_h"]
		if eh != extra_h:
			extra_h = eh
			offset_bottom = offset_top + RaidLogic.TOP_BLOCK_BASE_H + eh
			_key = -1
		var k := w.meter_lit() | (w.phase << 6) | (w.weak_taken << 9)
		var k2 := 0
		var flashing := false
		if w is RaidBellringer:
			var bw := w as RaidBellringer
			k2 = mini(bw.slams_muffled, 1023) | (mini(bw.slams, 1023) << 10) | (int(bw.muffled) << 20)
		elif w is RaidHuntsman:
			var hw := w as RaidHuntsman
			flashing = hw.is_stunned()
			k2 = mini(hw.intercepts, 1023) | (mini(hw.catches, 1023) << 10) | (int(flashing) << 20) | (int(hw.hunting_undead) << 21)
		elif w is RaidShieldwall:
			var sw := w as RaidShieldwall
			k2 = (sw.flanks & 0xFFFFF) | ((sw.hits & 0xFFFFF) << 20)
		elif w is RaidPyrePriest:
			var pp := w as RaidPyrePriest
			k2 = mini(pp.snuffs, 63) | (mini(pp.living(), 63) << 6) | (mini(pp.essence_burned, 0xFFFF) << 12)
		var k3 := mini(w.pack_alive(), 255) | (int(w.horn_beat >= 0.0) << 8) | (mini(w.horns, 63) << 9) | (mini(w.pack_broken, 1023) << 15)
		if k != _key or k2 != _key2 or k3 != _key3 or (flashing and not Pulse.reduced_motion):
			_key = k
			_key2 = k2
			_key3 = k3
			queue_redraw()

	## The note under row 2 (WardenLogic words, read from the spec so it follows the config): what a Huntsman catch
	## costs and where its hunt speeds up, the Shieldwall's shield, the Pyre-priest's fires, the Bellringer's muffle.
	func _note_text(w: RaidWarden) -> String:
		if w is RaidHuntsman:
			return WardenLogic.catch_label(w.wwords(), w.spec, raid.warden_run.tell_bypass)
		if w is RaidShieldwall:
			return WardenLogic.shield_label(w.wwords(), w.spec, w.phase, WardenLogic.lever_on(int(w.spec.get("tier", 1)), bool(w.spec.get("first_dungeon", false)), w.wcfg()))
		if w is RaidPyrePriest:
			return WardenLogic.pyre_label(w.wwords(), w.spec, w.phase, (w as RaidPyrePriest).living())
		return str((w.spec.get("weak_point", {}) as Dictionary).get("label", ""))

	func _text(x: float, y: float, text: String, px: int, key := "text") -> float:
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Palette.c(key))
		return x + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x

	func _notch(x: float, y: float) -> void:
		draw_line(Vector2(x, y - 11.0), Vector2(x, y + 1.0), Palette.c("vei", 0.9), 2.0)

	func _text_w(text: String, px: int) -> float:
		return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x

	## Row 1's dim 13 px teach label, drawn only where it fits the plate (RaidLogic.row1_fits, `reserve` px left after
	## it); the COUNTER row below says the same in full. Returns the x after it (`x` when dropped).
	func _teach(x: float, y: float, text: String, reserve := 0.0) -> float:
		if not RaidLogic.row1_fits(x, _text_w(text, 13), reserve, size.x):
			return x
		return _text(x, y, text, 13, "text_dim")

	## Row 1's counter tally (15 px): its parts in order (RaidLogic.fit_parts drops the last ones that would run
	## off the plate, `reserve` px kept for a status word after it). Returns the x after it.
	func _tally(x: float, y: float, parts: Array, key: String, reserve := 0.0) -> float:
		return _text(x, y, RaidLogic.fit_parts(parts, ThemeDB.fallback_font, 15, x, reserve, size.x), 15, key)

	## " · took n": the pips its weak-point windows took (the pips show them too, so it is the first part dropped).
	func _took_tag(w: RaidWarden) -> String:
		return "" if w.weak_taken <= 0 else RaidLogic.word_fmt(w.wwords(), "took_tag", [w.weak_taken])

	## The counter row's pack count:" · +n hounds" once its counter has killed any of its pack in one blow.
	func _pack_tag(w: RaidWarden) -> String:
		if w.pack_broken <= 0:
			return ""
		return RaidLogic.word_fmt(w.wwords(), "pack_more", [w.pack_broken, str((w.spec.get("pack", {}) as Dictionary).get("name", "pack"))])

	## A warden with a pack: HORN while it sounds, "HOUNDS n of m · it takes ×0.25" while they run, else
	## what the pack is (WardenLogic.pack_teach).
	func _pack_row(w: RaidWarden, x0: float, y: float) -> void:
		var pk: Dictionary = w.spec.get("pack", {})
		if pk.is_empty():
			return
		if w.horn_beat >= 0.0:
			_text(x0, y, RaidLogic.word_fmt(w.wwords(), "pack_horn_coming", [w.horn_pts.size(), str(pk.get("name", "pack"))]), 13, "danger")
		elif w.pack_alive() > 0:
			_text(x0, y, WardenLogic.pack_label(w.wwords(), pk, w.pack_alive(), int(pk.get("size", 0))), 13, "vei")
		else:
			_text(x0, y, WardenLogic.pack_teach(w.wwords(), pk), 13, "text_dim")

	func _draw() -> void:
		var w := _warden()
		if w == null:
			return
		var ww := w.wwords()   # raid.json wardens.words
		draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ground", float(raid.rcfg().get("hud", {}).get("warden_plate_alpha", 0.96))))
		var x0 := 12.0
		var px0 := 150.0
		var y := 26.0
		_text(x0, y, str(w.spec.get("name", "")).to_upper(), 13, "text_dim")
		# row 1: the strength left, notched at the phase boundaries
		var lit := w.meter_lit()
		var hw: RaidHuntsman = w as RaidHuntsman
		var win_lo := lit
		var win_hi := -1
		if hw != null and hw.is_stunned() and hw.stun_lit0 > lit:
			win_hi = hw.stun_lit0
		var blink := 1.0 if Pulse.reduced_motion else 0.55 + 0.45 * sin(_t * 14.0)
		var x := px0 + 6.0
		var r := 6.0
		for i in w.meter_n:
			if w.meter_notch.has(i):
				_notch(x - 3.5, y + 1.0)
				x += 9.0
			var p := Vector2(x, y - 5.0)
			if w.pip_lit(i):
				draw_circle(p, r, Palette.c("vei"))
			elif i >= win_lo and i < win_hi:
				# the open stun window took this pip: it flashes, slashed (shape as well as colour)
				draw_circle(p, r, Palette.c("undead", blink))
				draw_line(p + Vector2(-r * 0.7, r * 0.7), p + Vector2(r * 0.7, -r * 0.7), Palette.c("ground", 0.9), 1.8)
			elif w.weak_marks[i] != 0:
				draw_arc(p, r - 0.6, 0.0, TAU, 14, Palette.c("undead"), 1.6)
				draw_line(p + Vector2(-r * 0.7, r * 0.7), p + Vector2(r * 0.7, -r * 0.7), Palette.c("undead"), 1.6)
			else:
				draw_arc(p, r - 0.6, 0.0, TAU, 14, Palette.c("text_dim", 0.8), 1.3)
			x += 16.0
		x = _text(x + 2.0, y, "%d/%d" % [lit, w.meter_n], 15)   # (the words "break pips" label the row in the world, warden.gd: row 1 has no room for them)
		y += 26.0
		if w is RaidBellringer:
			var bw := w as RaidBellringer
			var n := bw.slams_muffled
			var x2 := x + 14.0
			if bw.slams > 0:   # no slam yet: no "×0 of 0" (the PHASE row below already says what muffles it)
				x2 = _tally(x2, y - 26.0, [RaidLogic.word_fmt(ww, "tally_muffled", [n, bw.slams]), _pack_tag(w)], "undead" if n > 0 or w.pack_broken > 0 else "text_dim", 8.0 + _text_w(str(ww.get("row_braced", "")), 13) if bw.muffled else 0.0)
			if bw.muffled:
				_text(x2 + 8.0, y - 26.0, str(ww.get("row_braced", "")), 13, "undead")
			_text(x0, y, str(ww.get("row_phase", "")), 13, "text_dim")
			_text(px0 + 6.0, y, "%d/%d" % [w.phase + 1, (w.spec.get("phases", []) as Array).size()], 15)   # (its note, the weak point's words, is the note row under this one)
		elif hw != null:
			var n2 := hw.intercepts
			var x4 := x + 14.0
			if n2 > 0 or w.pack_broken > 0:
				x4 = _tally(x4, y - 26.0, [RaidLogic.word_fmt(ww, "tally_intercepted", [n2]), _pack_tag(w), _took_tag(w)], "undead", 8.0 + _text_w(str(ww.get("row_stunned", "")), 13) if win_hi > 0 else 0.0)
			else:   # no intercept yet: teach the counter in words instead of a zero (if it fits, with STUNNED after it)
				x4 = _teach(x4, y - 26.0, str((w.spec.get("weak_point", {}) as Dictionary).get("label", "")), 8.0 + _text_w(str(ww.get("row_stunned", "")), 13) if win_hi > 0 else 0.0)
			if win_hi > 0:
				_text(x4 + 8.0, y - 26.0, str(ww.get("row_stunned", "")), 13, "undead")
			# row 2: the hunt, notched where catches change its phase
			_text(x0, y, str(ww.get("row_caught", "")), 13, "text_dim")
			var notches := WardenLogic.catch_notches(w.spec)
			var slots := maxi(WardenLogic.catch_slots(w.spec), hw.catches)
			var cx := px0 + 6.0
			for i in slots:
				if notches.has(i):
					_notch(cx - 3.5, y + 1.0)
					cx += 9.0
				var q := Vector2(cx, y - 5.0)
				var pts := PackedVector2Array([q + Vector2(0, -6), q + Vector2(6, 0), q + Vector2(0, 6), q + Vector2(-6, 0), q + Vector2(0, -6)])
				if i < hw.catches:
					draw_colored_polygon(pts, Palette.c("danger"))
				else:
					draw_polyline(pts, Palette.c("text_dim", 0.8), 1.3)
				cx += 16.0
			var x5 := cx + 2.0
			if hw.catches > 0:
				x5 = _text(x5, y, str(hw.catches), 15, "danger")
			x5 = _text(x5 + 12.0, y, RaidLogic.word_fmt(ww, "row_phase_n", [w.phase + 1, (w.spec.get("phases", []) as Array).size()]), 13, "text_dim")
			if hw.hunting_undead:
				_text(x5 + 12.0, y, str(ww.get("row_hunting", "")), 13, "danger")
		elif w is RaidShieldwall:
			var sw := w as RaidShieldwall
			var x6 := x + 14.0
			if sw.flanks > 0 or w.pack_broken > 0:
				_tally(x6, y - 26.0, [RaidLogic.word_fmt(ww, "tally_flanked", [sw.flanks, sw.hits]), _pack_tag(w), _took_tag(w)], "undead")
			else:   # no flank yet: teach the counter in words instead of a zero (if it fits)
				_teach(x6, y - 26.0, str((w.spec.get("weak_point", {}) as Dictionary).get("label", "")))
			_text(x0, y, str(ww.get("row_phase", "")), 13, "text_dim")
			_text(px0 + 6.0, y, "%d/%d" % [w.phase + 1, (w.spec.get("phases", []) as Array).size()], 15)
		elif w is RaidPyrePriest:
			var pp := w as RaidPyrePriest
			var x8 := x + 14.0
			if pp.snuffs > 0 or w.pack_broken > 0:
				_tally(x8, y - 26.0, [RaidLogic.word_fmt(ww, "tally_snuffed", [pp.snuffs]), _pack_tag(w), _took_tag(w)], "undead")
			else:   # no snuff yet: teach the counter in words instead of a zero (if it fits)
				_teach(x8, y - 26.0, str((w.spec.get("weak_point", {}) as Dictionary).get("label", "")))
			_text(x0, y, str(ww.get("row_phase", "")), 13, "text_dim")
			var x9 := _text(px0 + 6.0, y, "%d/%d" % [w.phase + 1, (w.spec.get("phases", []) as Array).size()], 15)
			var lv := pp.living()
			if lv > 0:
				x9 = _text(x9 + 12.0, y, RaidLogic.word_fmt(ww, "row_acolytes", [lv, pp.acolytes.size()]), 13, "vei")
			if pp.essence_burned > 0:
				_text(x9 + 12.0, y, RaidLogic.word_fmt(ww, "row_burned", [pp.essence_burned]), 13, "danger")
		# the note under row 2 (what a catch costs, what the shield does...): the break rows' size and tone, wrapped to the plate
		var lay := RaidLogic.warden_rows_layout(note_lines.size(), w.spec.has("pack"), break_lines.size(), _step())
		var npx := int(raid.rcfg().get("hud", {}).get("break_row_px", 15))
		for i in note_lines.size():
			_text(x0, y + 22.0 + _step() * float(i), note_lines[i], npx, note_key)
		_pack_row(w, x0, y + float(lay["pack_dy"]))
		# the new rows sit under the last of the existing ones (the note, a pack's row)
		var ry := y + float(lay["break_dy"])
		for line in break_lines:
			ry += _step()
			_text(x0, ry, str(line), int(raid.rcfg().get("hud", {}).get("break_row_px", 15)), RaidLogic.BREAK_ROW_KEY)


## Screen-space pointers over the world (a Node2D: it takes no input). The loot pointer: a faint
## dashed `vei` line from the HUD's "N on the floor" to the nearest pickup, ringed, while it is on
## screen; an edge chevron marked LOOT pointing at it while it is off screen. The exit pointer: an
## edge chevron marked EXIT (`relish`, the exits' lip colour) toward the nearest exit while it is off
## screen. The nearest pickup and exit are re-picked 4 times a second; each frame only projects them,
## and it redraws only when what it would draw moves (nothing to point at: no redraw at all).
class Pointers:
	extends Node2D
	var hud: RaidHud = null
	var _t := 1.0
	var _loot: Node2D = null
	var _chev := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var _ep := Vector2.INF      # the off-screen exit's screen point (INF: no EXIT chevron)
	var _wp := Vector2.INF      # the off-screen warden's screen point (INF: no WARDEN chevron)
	var _sp := Vector2.INF      # the nearest pickup's screen point (INF: none)
	var _from := Vector2.INF    # the HUD's "N on the floor" anchor
	var _block := Rect2()       # the top-centre block (goal or warden) a chevron must stay clear of

	func _process(d: float) -> void:
		var raid = hud.raid if hud != null else null
		var on: bool = raid != null and not raid._ended and raid.relish != null
		if on != visible:
			visible = on
		if not on:
			return
		_t += d / maxf(0.05, Engine.time_scale)
		if _t >= 0.25:
			_t = 0.0
			_loot = _nearest(raid, "raid_pickups")
		var view := get_viewport_rect().size
		var inner := Rect2(Vector2.ZERO, view).grow(-30.0)
		var xf: Transform2D = raid.get_viewport().get_canvas_transform()
		var ep := Vector2.INF
		if hud.exit_pos != Vector2.INF:
			ep = xf * hud.exit_pos
			if inner.has_point(ep):
				ep = Vector2.INF   # on screen: its lips and sigil already say where it is
		var wp := Vector2.INF   # T4: the warden (dormant or awake) while it is off screen
		var wd = raid.warden_run.warden if raid.warden_run != null else null
		if wd != null and is_instance_valid(wd) and wd.alive:
			wp = xf * (wd as Node2D).global_position
			if inner.has_point(wp):
				wp = Vector2.INF
		var sp := Vector2.INF
		if _loot != null and is_instance_valid(_loot) and _loot.is_in_group("raid_pickups"):
			sp = xf * _loot.global_position
		var from := hud.floor_anchor() if sp != Vector2.INF else Vector2.INF
		var blk := hud.top_block_rect()
		if ep != _ep or sp != _sp or from != _from or wp != _wp or blk != _block:
			_block = blk
			_wp = wp
			_ep = ep
			_sp = sp
			_from = from
			queue_redraw()

	func _nearest(raid: Node, group: String) -> Node2D:
		var best: Node2D = null
		var bd := INF
		var rp: Vector2 = raid.relish.global_position
		for o in raid.get_tree().get_nodes_in_group(group):
			var d: float = (o as Node2D).global_position.distance_to(rp)
			if d < bd:
				bd = d
				best = o
		return best

	## A chevron on the screen's inset edge where the line from its centre to `sp` leaves it.
	func _edge(sp: Vector2, view: Vector2, col: Color, word: String) -> void:
		var c := view * 0.5
		var dir := (sp - c).normalized()
		var m := 34.0
		var tx := INF if absf(dir.x) < 0.0001 else ((view.x - m) - c.x) / absf(dir.x)
		var ty := INF if absf(dir.y) < 0.0001 else ((view.y - m) - c.y) / absf(dir.y)
		var p := c + dir * minf(tx, ty)
		var f := ThemeDB.fallback_font
		var tw := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var lp := p - dir * 26.0 - Vector2(tw * 0.5, -5.0)
		# a chevron or label under the top-centre block moves to just below it, so it stays visible
		var q := RaidLogic.edge_clear_of(p, Rect2(lp + Vector2(0.0, -13.0), Vector2(tw, 16.0)), _block, view)
		if q != p:
			p = q
			lp = p - dir * 26.0 - Vector2(tw * 0.5, -5.0)
		_chev[0] = p + dir * 12.0
		_chev[1] = p - dir * 6.0 + dir.orthogonal() * 10.0
		_chev[2] = p - dir * 6.0 - dir.orthogonal() * 10.0
		draw_colored_polygon(_chev, Palette.c("ground", 0.8))
		draw_polyline(_chev, col, 2.0)
		draw_line(_chev[2], _chev[0], col, 2.0)
		draw_string(f, lp, word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

	func _draw() -> void:
		var view := get_viewport_rect().size
		if _ep != Vector2.INF:
			_edge(_ep, view, Palette.c("relish"), RaidHud.hud_fmt("edge_exit", []))
		if _wp != Vector2.INF:
			_edge(_wp, view, Palette.c("vei"), RaidHud.hud_fmt("edge_warden", []))
		if _sp == Vector2.INF:
			return
		if Rect2(Vector2.ZERO, view).grow(-30.0).has_point(_sp):
			if _from != Vector2.INF:
				draw_dashed_line(_from, _sp, Palette.c("vei", 0.45), 1.5, 7.0)
			draw_arc(_sp, 26.0, 0.0, TAU, 28, Palette.c("vei", 0.7), 1.5)
		else:
			_edge(_sp, view, Palette.c("vei"), RaidHud.hud_fmt("edge_loot", []))


## The push-or-retreat line, right-aligned on a dark backing (walls run under the HUD). When it is
## wider than `max_w` (a narrow window, where it would run under the warden's block) it wraps at its
## " · " clauses onto more lines, still right-aligned. Redrawn only when its text or room changes.
class PushLine:
	extends Control
	var text := ""
	var max_w := 4096.0:
		set(v):
			if absf(v - max_w) >= 1.0:
				max_w = v
				queue_redraw()

	func set_text(t: String) -> void:
		if t != text:
			text = t
			queue_redraw()

	func _line(f: Font, y: float, s: String) -> void:
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var x := size.x - w
		draw_rect(Rect2(Vector2(x - 10.0, y - 3.0), Vector2(w + 12.0, 28.0)), Palette.c("ground", float(ConfigDb.data.get("raid", {}).get("hud", {}).get("plate_alpha", 0.96))))
		draw_string(f, Vector2(x - 2.0, y + 17.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Palette.c("text"))

	func _draw() -> void:
		if text == "":
			return
		var f := ThemeDB.fallback_font
		if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 8.0 <= max_w:
			_line(f, 0.0, text)
			return
		var y := 0.0
		var cur := ""
		for part in text.split(" · "):
			var next := part if cur == "" else cur + " · " + part
			if cur != "" and f.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 8.0 > max_w:
				_line(f, y, cur)
				y += 22.0
				cur = part
			else:
				cur = next
		if cur != "":
			_line(f, y, cur)


class ExitButton:
	extends Control
	var hud: RaidHud = null
	var _hover := false

	func _init() -> void:
		# PASS: only its own left press is accepted below; a right press (the trance) or a dragged loop reaches the raid
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hover = false; queue_redraw())

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			accept_event()
			hud.open_exit_dialog()

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var on := hud.exit_enabled()
		var border := Palette.c("relish", (1.0 if _hover else 0.55) if on else 0.2)
		var vei := Palette.c("vei")
		draw_rect(r, Palette.c("ground", 0.92))
		draw_rect(r, border, false, 2.0)
		# door glyph: frame, leaf ajar, knob + escape arrow
		var d0 := Vector2(14, 9)
		draw_rect(Rect2(d0, Vector2(18, 28)), Palette.c("text_dim"), false, 2.0)
		var leaf := PackedVector2Array([d0 + Vector2(2, 2), d0 + Vector2(13, 5),
			d0 + Vector2(13, 24), d0 + Vector2(2, 26)])
		draw_colored_polygon(leaf, Palette.c("relish", 0.75))
		draw_circle(d0 + Vector2(10.5, 14.5), 1.6, Palette.c("text", 0.9))
		draw_line(d0 + Vector2(22, 14), d0 + Vector2(32, 14), vei, 2.0)
		draw_line(d0 + Vector2(28, 10), d0 + Vector2(32, 14), vei, 2.0)
		draw_line(d0 + Vector2(28, 18), d0 + Vector2(32, 14), vei, 2.0)
		if not on:
			draw_rect(r, Palette.c("ground", 0.55))   # visibly disabled
			draw_string(ThemeDB.fallback_font, Vector2(52, size.y * 0.5 + 5), RaidHud.hud_fmt("exit_off", []),
				HORIZONTAL_ALIGNMENT_LEFT, 96, 13, Palette.c("text_dim", 0.8))
			return
		draw_string(ThemeDB.fallback_font, Vector2(56, 21), RaidHud.hud_fmt("exit_retreat", []),
			HORIZONTAL_ALIGNMENT_LEFT, 120, 15, Palette.c("vei", 1.0 if _hover else 0.8))
		# what it does, always beside the button at an exit (the hint line may be teaching the circle)
		draw_string(ThemeDB.fallback_font, Vector2(56, 38), RaidHud.hud_fmt("exit_banks", []),
			HORIZONTAL_ALIGNMENT_LEFT, 130, 13, Palette.c("text", 0.85))


## Vei's final test (top centre). Fronts phase: FRONTS n/4 · need k, a front pip per front (filled
## once it breaks through), and the phase-1 clock. The break: BACKLOG (the seed's horde) as an upright
## integer with the ferry's rate in plain words (the real clock is deaths, so no minus, no slant) and
## which side is winning, then the BREAK meter drawn as the wardens' meter (WardenBlock): break_beats
## pips lit from the left by the streak, a notch every `notch` pips, a lapse's pips slashed in `danger`
## while it shows (flashing, steady under reduced motion), the beat count and, while the pace gains,
## "~30 s at this pace". Under it one line: the phase-2 rule for the break's first hint_s seconds, and
## once a lapse has happened "LAPSES ×n · −k beats" (no row before the first). Always: BACKUPS left as
## pips (a phylactery diamond, a clone dot) and one cracked violet ring per backup spent. Reads the HUD's once-a-frame boss_info and
## redraws only when what it shows changes (or while a lapse flashes).
class BossBlock:
	extends Control
	var raid: Node = null
	var hud: Node = null
	const H_FRONTS := 94.0   # the plate's height before the break (three rows)
	const H_BREAK := 122.0  # and from the break on (four: the rule / lapse line sits under the meter)
	var _key := PackedInt32Array()
	var _next := PackedInt32Array()
	var _eta_key := ""
	var _t := 0.0
	static var _oblique: FontVariation = null

	static func oblique() -> FontVariation:
		if _oblique == null:
			_oblique = FontVariation.new()
			_oblique.base_font = ThemeDB.fallback_font
			_oblique.variation_transform = Transform2D(Vector2(1, 0), Vector2(tan(deg_to_rad(9.0)), 1), Vector2.ZERO)
		return _oblique

	static func thousands(n: int) -> String:
		var t := str(absi(n))
		var out := ""
		while t.length() > 3:
			out = "," + t.substr(t.length() - 3) + out
			t = t.substr(0, t.length() - 3)
		return ("-" if n < 0 else "") + t + out

	func _info() -> Dictionary:
		return hud.boss_info if hud != null else {}

	## Redraw when a shown number changes, or every frame while a lapse flashes (not under reduced motion).
	func _process(d: float) -> void:
		_t += d / maxf(0.05, Engine.time_scale)
		var info := _info()
		if info.is_empty():
			return
		_next.resize(18)
		_next[0] = int(info["break_began"]) | (int(info["over"]) << 1) | (int(info["won"]) << 2) | (int(info["winning"]) << 3) | (int(info["lapse_on"]) << 4)
		_next[1] = int(info["met"])
		_next[2] = floori(float(info["t"]))
		_next[3] = roundi(float(info["horde"]))
		_next[4] = int(info["streak"])
		_next[5] = int(info["break_beats"])
		_next[6] = int(info["lapses"])
		_next[7] = int(info["lapse_lost"])
		_next[8] = int(info["lapse_lo"])
		_next[9] = int(info["lapse_hi"])
		_next[10] = int(info["phyl_left"])
		_next[11] = int(info["clones_left"])
		_next[12] = int(info["spent_phyl"]) + int(info["spent_clones"])
		_next[13] = roundi(float(info["ferry"]) * 100.0)
		_next[14] = int(info["required"])
		_next[15] = int(info["notch"])
		_next[16] = int(info["rule_on"])
		_next[17] = roundi(float(info["pressure"]) * 100.0) if str(info["pressure_tag"]) != "" else 0   # the guards tag shows only above the threshold
		var eta_key := str(info["eta"])
		if _next != _key or eta_key != _eta_key or (bool(info["lapse_on"]) and not Pulse.reduced_motion):
			_key = _next.duplicate()
			_eta_key = eta_key
			queue_redraw()

	func _label(x: float, y: float, text: String) -> float:
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.c("text_dim"))
		return x + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x

	func _text(x: float, y: float, text: String, px: int, key := "text", font: Font = null) -> float:
		var f: Font = font if font != null else ThemeDB.fallback_font
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Palette.c(key))
		return x + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x

	func _pip(p: Vector2, r: float, col: Color, filled: bool, diamond: bool) -> void:
		if diamond:
			var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)])
			if filled:
				draw_colored_polygon(pts, col)
			else:
				draw_polyline(pts, Palette.c("text_dim", 0.6), 1.3)
		elif filled:
			draw_circle(p, r, col)
		else:
			draw_arc(p, r - 0.6, 0.0, TAU, 12, Palette.c("text_dim", 0.6), 1.3)

	func _cracked(p: Vector2, r: float, i: int) -> void:
		for j in 3:
			var a0: float = TAU * j / 3.0 + 0.7 * i + 0.2
			draw_arc(p, r, a0, a0 + TAU / 3.0 - 0.55, 8, Palette.c("relish", 0.9), 1.6)

	func _notch(x: float, y: float) -> void:
		draw_line(Vector2(x, y - 11.0), Vector2(x, y + 1.0), Palette.c("vei", 0.9), 2.0)

	func _draw() -> void:
		var info := _info()
		if info.is_empty():
			return
		draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(size.x, H_BREAK if bool(info["break_began"]) else H_FRONTS)), Palette.c("ground", 0.62))
		var vw: Dictionary = raid.vwords()   # raid.json vei_fight: the block's words
		var x0 := 12.0
		var col2 := 108.0
		var y := 26.0
		if not bool(info["break_began"]):
			var x := _label(x0, y, str(vw.get("hud_fronts", "")))
			x = _text(col2, y, "%d/4" % int(info["met"]), 20)
			x = _text(x + 8.0, y, RaidLogic.word_fmt(vw, "hud_need", [int(info["required"])]), 15)
			var tx := size.x - 150.0
			_label(tx, y, str(vw.get("hud_time", "")))
			_text(tx + 44.0, y, "%d / %d s" % [floori(float(info["t"])), roundi(float(info["max_t"]))], 15)
			y += 28.0
			_label(x0, y, str(vw.get("hud_broken", "")))
			for i in 4:
				_pip(Vector2(col2 + 8.0 + 20.0 * i, y - 5.0), 6.0, Palette.c("undead"), i < int(info["met"]), true)
			_text(col2 + 96.0, y, str(vw.get("hud_broken_note", "")), 13, "text_dim")
		else:
			# the backlog (the seed's horde), the ferry's rate in words, and which side the beat is going to.
			# The backlog drains by deaths, not by this clock (it would take ~90 min): no minus, no slant.
			_label(x0, y, str(vw.get("hud_backlog", "")))
			var x2 := _text(col2, y, thousands(roundi(float(info["horde"]))), 20)
			x2 = _text(x2 + BossLogic.GAP_FERRY, y, RaidLogic.word_fmt(vw, "hud_ferried", [float(info["ferry"])]), 13, "text_dim")
			var tag := str(info["pressure_tag"])   # "· guards ×2.3" only when her pool presses the break (BossLogic.pressure_tag)
			if tag != "":
				x2 = _text(x2 + BossLogic.GAP_TAG, y, tag, 13, "text_dim")   # dim like "ferried": it qualifies the ferry, and the orange status after it stays its own phrase
			x2 += BossLogic.GAP_STATUS
			if bool(info["won"]):
				_text(x2, y, str(vw.get("hud_she_breaks", "")), 15, "vei")
			elif bool(info["over"]):
				_text(x2, y, str(vw.get("hud_lost", "")), 13, "danger")
			elif bool(info["winning"]):
				_text(x2, y, str(vw.get("hud_winning", "")), 13, "undead")
			else:
				_text(x2, y, str(vw.get("hud_losing", "")), 13, "living")
			y += 28.0
			# the break meter, as the wardens': lit from the left, notched, a lapse's pips slashed
			_label(x0, y, str(vw.get("hud_break", "")))
			var n := int(info["break_beats"])
			var st := int(info["streak"])
			var notch := maxi(1, int(info["notch"]))
			var lo := int(info["lapse_lo"])
			var hi := int(info["lapse_hi"]) if bool(info["lapse_on"]) else -1
			var blink := 1.0 if Pulse.reduced_motion else 0.55 + 0.45 * sin(_t * 14.0)
			var r := 5.0
			var x := col2 + 8.0
			for i in n:
				if i > 0 and i % notch == 0:
					_notch(x - 3.5, y + 1.0)
					x += 7.0
				var p := Vector2(x, y - 5.0)
				if i < st:
					draw_circle(p, r, Palette.c("vei"))
				elif i >= lo and i < hi:
					# the lapse took this pip: it flashes, slashed (shape as well as colour)
					draw_circle(p, r, Palette.c("danger", blink))
					draw_line(p + Vector2(-r * 0.7, r * 0.7), p + Vector2(r * 0.7, -r * 0.7), Palette.c("ground", 0.9), 1.8)
				else:
					draw_arc(p, r - 0.6, 0.0, TAU, 12, Palette.c("text_dim", 0.6), 1.3)
				x += 13.0
			x = _text(x + 2.0, y, "%d/%d" % [st, n], 15)
			var eta := str(info["eta"])
			if eta != "" and not bool(info["over"]):
				_text(x + 10.0, y, eta, 13, "text_dim")
			# under the meter: the rule for the break's first seconds, and the lapse count once there is one
			y += 22.0
			var nl := int(info["lapses"])
			var tx := x0
			if bool(info["rule_on"]):
				tx = _text(x0, y, str(info["rule"]), 13, "text") + 18.0
			if nl > 0:
				_text(tx, y, BossLogic.lapse_text(nl, int(info["lapse_lost"]), vw), 13, "danger" if hi > 0 else "text_dim")
		y += 28.0
		_label(x0, y, str(vw.get("hud_backups", "")))
		var px := col2 + 8.0
		for i in int(info["phyl_left"]):
			_pip(Vector2(px, y - 5.0), 6.5, Palette.c("relish"), true, true)
			px += 18.0
		for i in int(info["clones_left"]):
			_pip(Vector2(px, y - 5.0), 6.0, Palette.c("relish"), true, false)
			px += 18.0
		var spent := int(info["spent_phyl"]) + int(info["spent_clones"])
		for i in spent:
			_cracked(Vector2(px, y - 5.0), 6.5, i)
			px += 18.0
		var left := int(info["phyl_left"]) + int(info["clones_left"])
		_text(px + 4.0, y, RaidLogic.word_fmt(vw, "hud_left", [left, "" if spent == 0 else RaidLogic.word_fmt(vw, "hud_cracked", [spent])]), 15,
			"text" if left > 0 else "danger")
