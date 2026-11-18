extends Control
## COVINGTON shell: layout, view fetch on rev change, bind() to the HUD, the town view and the
## dock panels, event routing, and the one-click return to the realm.
## Contract (STATE-API 2.3): setup(args) with ids only; finished({"v": 2, "teleport_to": ""}) once.

signal finished(result: Dictionary)

const HudScript := preload("res://scripts/town/town_hud.gd")
const ViewScript := preload("res://scripts/town/town_view.gd")
const StripScript := preload("res://scripts/town/town_away_strip.gd")
const PANELS := [
	["Build", preload("res://scripts/town/panel_build.gd")],
	["Jobs", preload("res://scripts/town/panel_jobs.gd")],
	["Stances", preload("res://scripts/town/panel_stances.gd")],
	["Backups", preload("res://scripts/town/panel_backups.gd")],
	["Crypt", preload("res://scripts/town/panel_crypt.gd")],
]

var _setup_done := false
var _finished := false
var _hud: Control
var _view: Control
var _panels: Array = []
var _tabs: Array = []
var _bound: Array = []  # everything that gets on_game_event()
var _later: Array = []  # the nodes a refresh has still to bind, one per frame (see _fetch)
var _tab := 0  # the tab on show: its panel binds on every fetch, the others once, when shown (see _select_tab)
var _last_rev := -1
var _since_fetch := 0.0
var _dirty := false
var _pending: Dictionary = {}  # a spread refresh's phase-A views, waiting for phase B next frame ({} = none)
var _pending_cmd := false  # the pending refresh is a command's: its binds start with the tab on show
var _refresh_s := 0.25
## Debug-only harness (`--town-demo=full|tierup`, ignored unless Game.state.debug_enabled):
## "full" binds the synthetic demo city instead of the fetched views; "tierup" fires a synthetic
## tier_up event shortly after setup. Both say so on screen.
var _demo := ""
var _tier := ""  # the last fetched town tier (the synthetic tier_up's `from`)
var _fort_names := {}  # fort id -> name, read once from view_realm (the Build tab's chips)
## Debug-only (`--town-grow=<sim_seconds>`, needs debug_enabled, no autosave and `--fixture=`/`--shot=`):
## before the first bind an autoplayer builds what the Build tab suggests, on the real TownSim, and
## skips sim time in view.grow_chunk_s steps until the target passes. `--town-grow-log` prints a line
## per chunk. `--town-zoom=<cx>,<cy>,<scale>` scales the town view's content about a point.
## Sound: one shared Synth child (scripts/fx/synth.gd), which owns mute and volume (AudioPrefs; M;
## harness sessions start muted). town.json `sound.kinds` maps each town event to a Synth kind. Fed by
## the town view's sfx signal, the crypt tab's raise signals and Pulse's beat.
var _synth: Synth
var _beat_i := -1
var _last_trade := -1.0  # seconds of the last trade blip that sounded (the limiter)
## The staffing projections the Jobs, Stances and Backups tabs show, made once per rev (project_staffing),
## and the lot hops (once per town rev); `_last_views` is what the panels were last bound to.
var _staff_cache := RevCache.new()
var _hops_cache := RevCache.new()
var _last_views := {}
## Debug-only set-piece drivers (debug builds only): `--town-raise[=<lot>]` auto-holds and keeps the
## raise on the crypt tab (needs `--town-tab=crypt --town-slab=...`); once the rings have landed it
## stands in for the E3 raise (which mints nothing yet) by granting one big undead and placing it at
## <lot> with the real cmd_place_big_undead, so the walk-out is driven by the real view change.
## `--town-place=<uid>:<lot>` places an existing big undead the same way, after demo_raise.place_delay_s.
## `--town-staff-vat=<slot>[,<slot>]` staffs those clone vats (the real cmd_staff_vat) right after setup's
## first fetch; the rev change shows it on the next one (a debug driver for the Backups tab's screenshot).
## `--town-show=<building_id>` opens the Build tab with that building's row focused and scrolled into view
## (the backups' "Show the Chapel of Vats" route), for a screenshot of a row below the fold.
## `--town-hold` holds the raise like `--town-raise` but stops at the name prompt, its field focused (the crypt's
## name-focus check). `--town-grant=<stock>:<n>[,…]` grants stocks (cmd_debug_grant) after setup's first fetch.
var _raise_lot := ""
var _log_set := false  # prints frame numbers of the set-piece beats
var _frame := 0
var _walkers_n := 0
var _grow_label: Label
var _cue: ScrollCue  # the dock's "more below" fade over the shown tab's scroll edge
var _goal: PanelContainer  # the first goal in town (TownGuide.goal), top-left of the town view; hidden once met
var _goal_head: Label  # the game's goal, over
var _goal_step: Label  # the step due now
## The welcome-back replay (TownReplay): the away strip sits in the dock over the tabs. `_replayed` is the
## last away report replayed this session (a static, so a second visit doesn't replay it; never saved);
## `_away_check` asks the next fetch to look (setup's first, and each away_report). `_replay_lots` are the lots
## still to flash, `_replay_left` the seconds to the next one (-1 = none due).
## `--town-away=<seconds>` (debug builds) runs a real reporting catch-up of that gap right after setup.
static var _replayed := 0
var _away_check := true
var _plates: VBoxContainer
var _strip: PanelContainer
var _replay_lots: Array = []
var _replay_left := -1.0
var _grow_log: Array = []  # [{t, building_id, lot_id}] of what the autoplayer built
var _grown_s := 0.0


func _ready() -> void:
	_build_ui()
	Game.game_event.connect(_on_game_event)
	if not _setup_done and get_tree().current_scene == self:
		setup({"mode": "town"})
	_standalone_check.call_deferred()


func _exit_tree() -> void:
	if Game.game_event.is_connected(_on_game_event):
		Game.game_event.disconnect(_on_game_event)


func _standalone_check() -> void:
	# change_scene_to_file can assign current_scene around _ready; re-check once settled.
	if not _setup_done and get_tree().current_scene == self:
		setup({"mode": "town"})


## args: {mode: "town"}; unknown keys (including legacy ones the router merges in) are ignored.
func setup(_args: Dictionary) -> void:
	_setup_done = true
	for f in Game.state.view_realm().get("forts", []):
		_fort_names[String(f.get("id", ""))] = String(f.get("name", ""))
	_grow()
	_zoom()
	_debug_slab()
	_fetch()
	_debug_set_pieces()
	var show := _debug_arg("town-show")  # debug `--town-show=<building_id>`: the Build tab, that row focused
	if show != "":
		_on_show_building(show, _panels[0])
	if _demo == "tierup":
		var spec: Dictionary = ConfigDb.v("town", "view", {}).get("demo_tierup", {})
		get_tree().create_timer(float(spec.get("delay_s", 0.0))).timeout.connect(
			_fire_demo_tierup.bind(String(spec.get("tier", ""))))


func _fire_demo_tierup(tier: String) -> void:
	if not is_inside_tree():
		return
	_on_game_event({"type": "tier_up", "t": 0.0, "tier": tier, "from": _tier})


## Reads `--town-demo=<mode>`; only a debug build honours it.
func _read_demo_flag() -> void:
	if not Game.state.debug_enabled:
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--town-demo="):
			var mode := arg.trim_prefix("--town-demo=")
			if mode in ["full", "tierup"]:
				_demo = mode
			else:
				printerr("Covington: unknown --town-demo=%s (expected full or tierup)" % mode)


## The value of a debug arg `--name=value` ("" absent); only a debug build reads it.
func _debug_arg(name: String) -> String:
	if not Game.state.debug_enabled:
		return ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.trim_prefix("--%s=" % name)
	return ""


## Whether a debug arg is given, with or without a value (`--name` or `--name=value`); debug builds only.
func _debug_has(name: String) -> bool:
	if not Game.state.debug_enabled:
		return false
	for arg in OS.get_cmdline_user_args():
		if arg == "--" + name or arg.begins_with("--%s=" % name):
			return true
	return false


## `--town-grow=<sim_seconds>`: plays the town the way the suggestion tells a new player to (the top
## buildable row on its nearest lot), skipping view.grow_chunk_s of sim between moves.
func _grow() -> void:
	var raw := _debug_arg("town-grow")
	if raw == "" or not raw.is_valid_float():
		return
	var args := OS.get_cmdline_user_args()
	var harness := false
	for a in args:
		if a.begins_with("--fixture=") or a.begins_with("--shot="):
			harness = true
	if Game.autosave_enabled or not harness:
		printerr("Covington: --town-grow refused (needs --fixture= or --shot= alongside, and no autosave)")
		return
	var cfg: Dictionary = ConfigDb.v("town", "view", {})
	var chunk := maxf(float(cfg.get("grow_chunk_s", 60.0)), 1.0)
	var chunk_arg := _debug_arg("town-grow-chunk")  # a longer step for a long run
	if chunk_arg.is_valid_float():
		chunk = maxf(float(chunk_arg), 1.0)
	var target := float(raw)
	var cfgs := {"town": ConfigDb.data.get("town", {}), "buildings_view": ConfigDb.data.get("buildings_view", {}),
		"buildings": ConfigDb.data.get("buildings", {}), "economy": ConfigDb.data.get("economy", {})}
	var log_chunks := "--town-grow-log" in args
	var paid := {"build": {"gold": 0.0, "bone": 0.0, "relics": 0.0, "n": 0}, "upgrade": {"gold": 0.0, "bone": 0.0, "relics": 0.0, "n": 0}}
	while _grown_s < target:
		var vws := _fetch_views()
		var why := BuildSort.autoplay_why(vws, cfgs) if log_chunks else ""
		var pick := BuildSort.autoplay_pick(vws, cfgs)
		var kind := "-"
		if not pick.is_empty():
			var is_up := bool(pick.get("upgrade", false))
			kind = "upgrade" if is_up else "build"
			var r: Dictionary = Game.state.cmd_upgrade(pick["lot_id"]) if is_up else Game.state.cmd_build(pick["building_id"], pick["lot_id"])
			if bool(r.get("ok", false)):
				_grow_log.append({"t": _grown_s, "building_id": pick["building_id"], "lot_id": pick["lot_id"], "upgrade": is_up})
				for k in ["gold", "bone", "relics"]:
					paid[kind][k] += float((r.get("cost", {}) as Dictionary).get(k, 0.0))
				paid[kind]["n"] += 1
			else:
				kind += "-refused:" + String(r.get("reason", ""))
		Game.state.cmd_debug_skip_time(chunk)
		_grown_s += chunk
		if log_chunks:
			var town: Dictionary = Game.state.view_town()
			var counts := {}
			var lv := []
			for b in town["buildings"]:
				counts[b["building_id"]] = int(counts.get(b["building_id"], 0)) + 1
				lv.append("%s:%s@L%d" % [b["building_id"], b["lot_id"], int(b["level"])])
			var rr := []
			for r in Game.state.view_hud().get("rates", []):
				rr.append("%s=%+.3f" % [r["id"], float(r["rate"])])
			var slots := 0
			for j in town.get("jobs", []):
				slots += int(j.get("slots", 0))
			var bone_in := float(Game.state.view_rates().get("rates", {}).get("bone", {}).get("in", 0.0))
			print("GROW2 t=%d pick=%s | %s | bld=%s | rates %s | gold=%.0f bone=%.0f bodies=%.0f" % [_grown_s,
				str(pick.get("building_id", "-")), why, JSON.stringify(counts), " ".join(rr), town["gold"], town["bone"], town["bodies"]])
			print("GROW3 t=%d kind=%s levels=%s slots=%d bone_in=%.4f paid_build=%.0fg/%.0fb/%.0fr/%d paid_upgrade=%.0fg/%.0fb/%.0fr/%d" % [_grown_s, kind,
				",".join(lv), slots, bone_in, paid["build"]["gold"], paid["build"]["bone"], paid["build"]["relics"], paid["build"]["n"],
				paid["upgrade"]["gold"], paid["upgrade"]["bone"], paid["upgrade"]["relics"], paid["upgrade"]["n"]])
			print("GROW t=%d tier=%s buildings=%d built=%d workers=%.1f/%.1f idle=%.1f muster=%.3f living=%.1f/%.0f" % [_grown_s, town["tier"],
				(town["buildings"] as Array).size(), _grow_log.size(), town["workers"]["total"], town["workers"]["steady"],
				town["workers"]["idle"], town["workers"]["muster"], town["living"], town["living_cap"]])
	if log_chunks:
		var tw: Dictionary = Game.state.view_town()
		var rates := []
		for r in Game.state.view_hud().get("rates", []):
			if r["id"] in ["gold", "bone", "bodies"]:
				rates.append("%s %+.3f/s" % [r["id"], float(r["rate"])])
		print("GROWSTATE t=%d tier=%s buildings=%s workers=%.1f steady=%.1f living=%.1f/%.0f %s gold=%.1f bone=%.1f bodies=%.1f next=%s" % [_grown_s,
			tw["tier"], ",".join((tw["buildings"] as Array).map(func(b): return "%s@%s(%s)" % [b["building_id"], b["lot_id"], b["state"]])),
			tw["workers"]["total"], tw["workers"]["steady"], tw["living"], tw["living_cap"], ", ".join(rates), tw["gold"], tw["bone"], tw["bodies"], str(tw["next_tier"])])
	var h := int(_grown_s) / 3600
	var m := (int(_grown_s) % 3600) / 60
	_grow_label = TownUI.label(BuildSort.fmt(String(cfg.get("grow_text", "")),
		{"h": h, "mm": "%02d" % m, "n": _grow_log.size()}), 14, "select")
	_grow_label.position = Vector2(12, 8)
	_grow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grow_label.add_theme_stylebox_override("normal", TownUI.panel_box())
	_view.add_child(_grow_label)


## `--town-slab=<husk_uid>:<remnant_uid>,<remnant_uid>` (debug, e.g. h1:r2,r3): puts Relish home
## (cmd_debug_set_state relish_at covington) and that husk with those remnants on the crypt slab
## (the crypt tab applies it on the first bind whose inventory has them).
func _debug_slab() -> void:
	var raw := _debug_arg("town-slab")
	if raw == "":
		return
	var parts := raw.split(":")
	var rems: Array = []
	if parts.size() > 1:
		for r in parts[1].split(",", false):
			rems.append(r)
	var r: Dictionary = Game.state.cmd_debug_set_state({"relish_at": "covington"})
	if not bool(r.get("ok", false)):
		printerr("Covington: --town-slab could not bring Relish home (%s)" % r.get("reason", ""))
	for p in _panels:
		if p.has_method("debug_preset"):
			p.debug_preset(parts[0], rems)


## `--town-zoom=<cx>,<cy>,<scale>` (debug): the town view's content scaled about a point.
func _zoom() -> void:
	var p := _debug_arg("town-zoom").split(",")
	if p.size() != 3 or not p[2].is_valid_float() or float(p[2]) <= 0.0:
		return
	_view.set_zoom(Vector2(float(p[0]), float(p[1])), float(p[2]))
	var cfg: Dictionary = ConfigDb.v("town", "view", {})
	var tag := TownUI.label(BuildSort.fmt(String(cfg.get("zoom_text", "")), {"scale": p[2]}), 14, "select")
	tag.position = Vector2(12, 8 if _grow_label == null and _demo == "" else 40)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_stylebox_override("normal", TownUI.panel_box())
	_view.add_child(tag)


func _build_ui() -> void:
	var cfg: Dictionary = ConfigDb.v("town", "view", {})
	_refresh_s = float(cfg.get("refresh_s", 0.25))
	_read_demo_flag()
	_synth = Synth.new()
	_synth.name = "Synth"
	add_child(_synth)
	var kinds: Array = []
	for k in (ConfigDb.v("town", "sound", {}).get("kinds", {}) as Dictionary).values():
		if not kinds.has(k):
			kinds.append(k)
	_synth.warm(kinds)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_hud = HudScript.new()
	_hud.custom_minimum_size = Vector2(0, float(cfg.get("hud_h", 72)))
	root.add_child(_hud)
	_hud.return_pressed.connect(_on_return)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	_view = ViewScript.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_view)

	var dock := PanelContainer.new()
	dock.custom_minimum_size = Vector2(float(cfg.get("dock_w", 560)), 0)
	dock.add_theme_stylebox_override("panel", TownUI.panel_box())
	body.add_child(dock)
	var col := VBoxContainer.new()
	dock.add_child(col)
	var tab_row := HBoxContainer.new()
	col.add_child(tab_row)
	# the welcome-back strip: in the dock over every tab, so it never covers a lot the replay flashes
	_strip = StripScript.new()
	_strip.setup(cfg.get("replay", {}))
	col.add_child(_strip)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stack)

	for i in PANELS.size():
		var p: Control = PANELS[i][1].new()
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)
		_panels.append(p)
		var b := TownUI.button(PANELS[i][0])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, maxf(TownUI.MIN_TARGET, float(cfg.get("tab_h", 44))))
		b.pressed.connect(_select_tab.bind(i))
		tab_row.add_child(b)
		_tabs.append(b)
	_cue = ScrollCue.new()  # over the shown tab's scroll edge while there's more below (_select_tab points it)
	_cue.setup(cfg.get("scroll_cue", {}))
	stack.add_child(_cue)
	_bound = [_hud, _view] + _panels
	for n in _bound:
		n.command_issued.connect(_on_command_issued)
	var build: Control = _panels[0]
	build.placement_changed.connect(_view.set_placement)
	build.lot_selected.connect(_view.set_selected_lot)
	_view.lot_clicked.connect(build.on_lot_clicked)
	_view.right_clicked.connect(build.dismiss)
	# In-scene building: the lot card, the hover outline, the day-1 suggestion, queue ghosts, the build flash.
	build.attach_card(_view.card)
	build.card_opened.connect(_view.open_card)
	build.card_closed.connect(_view.close_card)
	build.hover_lots.connect(_view.set_hover_lots)
	build.suggestion_changed.connect(_view.set_suggestion)
	build.queue_changed.connect(_view.set_queue)
	build.build_started.connect(_view.flash_lot)
	_panels[3].show_building.connect(_on_show_building.bind(build))  # backups' No vats yet: the Build tab, that building selected
	build.to_realm.connect(_on_return)  # the relic pin's To the realm: the same one exit as the HUD's Return
	_view.suggestion_dismissed.connect(build.on_suggestion_dismissed)
	_view.sfx.connect(_on_sfx)
	_build_goal()
	_strip.acted.connect(_on_strip_acted)
	var crypt: Control = _panels[4]
	crypt.hold_started.connect(_play.bind("raise_hold"))
	crypt.raise_started.connect(_on_raise_started)
	crypt.raise_landed.connect(_on_raise_landed)
	for p in _panels:  # the one staffing-projection helper, handed in (a panel never asks GameState for it)
		if "project" in p:
			p.project = project_staffing
	_select_tab(_debug_tab())
	if _demo != "":
		var tag := TownUI.label("SYNTHETIC DEMO TOWN (debug)" if _demo == "full" else "SYNTHETIC TIER-UP EVENT (debug)",
			14, "select")
		tag.position = Vector2(12, 8)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_theme_stylebox_override("normal", TownUI.panel_box())
		_view.add_child(tag)


## Reads `--town-tab=<build|jobs|stances|backups|crypt>`; only a debug build honours it. Tab 0 otherwise.
func _debug_tab() -> int:
	if not Game.state.debug_enabled:
		return 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--town-tab="):
			var i := ["build", "jobs", "stances", "backups", "crypt"].find(arg.trim_prefix("--town-tab="))
			if i >= 0:
				return i
			printerr("Covington: unknown --town-tab=%s (expected build, jobs, stances, backups or crypt)" % arg.trim_prefix("--town-tab="))
	return 0


func _select_tab(i: int) -> void:
	var was := _tab
	_tab = i
	for k in _panels.size():
		_panels[k].visible = (k == i)
		_tabs[k].set_pressed_no_signal(k == i)
		_tabs[k].add_theme_stylebox_override("normal", TownUI.button_box("active" if k == i else "normal"))
	var p: Control = _panels[i]  # the Build tab is its own scroll; every other tab holds one
	var scrolls := p.find_children("*", "ScrollContainer", true, false)
	_cue.scroll = p if p is ScrollContainer else (scrolls[0] if not scrolls.is_empty() else null)
	# a hidden panel is current the moment it shows, unless a refresh is due: then `_last_views` may predate a
	# command (between its phase A and B) and would clear the Build tab's sent lots; phase B binds the tab on show
	if not _last_views.is_empty() and (i != was or i == 0) and not _dirty and _pending.is_empty():
		_panels[i].bind(_last_views)


func _on_show_building(bid: String, build: Control) -> void:
	_select_tab(0)
	build.select_building(bid)


func _on_command_issued() -> void:
	_dirty = true


func _process(delta: float) -> void:
	if not _setup_done:
		return
	_frame += 1
	if _log_set and _view.agents != null and _view.agents.walkers.size() != _walkers_n:
		_walkers_n = _view.agents.walkers.size()
		print("TOWNSET walkers=%d frame=%d" % [_walkers_n, _frame])
	# a muted synth computes no beat; by clock otherwise, so it steps under reduced motion too
	var beat := TownSound.beat_step(_synth.is_muted(), _beat_i, Pulse.now_ms(), Pulse.tempo_ms)
	_beat_i = int(beat["i"])
	if bool(beat["fire"]):
		_play("beat")
	if _replay_left >= 0.0:
		_replay_step(delta)
	_since_fetch += delta
	# One piece of the refresh per frame, so no frame carries a whole one (a cold fetch is ~5 ms, the binds ~3 ms):
	# a command's phase A (it drops what was pending), else a fetch's phase B, else one bind, else a due refresh.
	if _dirty:
		_refresh_a(true)
	elif not _pending.is_empty():
		_refresh_b()
	elif not _later.is_empty():
		(_later.pop_front() as Node).bind(_last_views)
	elif Game.state.rev != _last_rev and _since_fetch >= _refresh_s:
		_refresh_a(false)


## Fetches the views and binds what is on screen, all in this frame: the setup and the debug drivers. Every other
## refresh is spread over frames (_refresh_a, _refresh_b, then one bind a frame).
func _fetch() -> void:
	_last_rev = Game.state.rev
	_since_fetch = 0.0
	_dirty = false
	_pending = {}
	var views := _fetch_views()
	_take(views)
	_later = []
	for n in _bound.filter(_binds_now):
		n.bind(views)


## A spread refresh's first frame: the views that must agree with each other (phase A, _fetch_views_a). A command's
## (`cmd`) drops the binds still pending, which would show the views from before it, and binds the tab on show
## first once phase B lands, so the panel clicked answers first.
func _refresh_a(cmd: bool) -> void:
	_last_rev = Game.state.rev
	_since_fetch = 0.0
	_dirty = false
	_pending = _fetch_views_a()
	_pending_cmd = cmd or _pending_cmd
	if cmd:
		_later = []


## A spread refresh's second frame: the rest of the views (_fetch_views_b), the goal and the replay check, and the
## binds queued one a frame after this one.
func _refresh_b() -> void:
	var views := _fetch_views_b(_pending)
	_pending = {}
	_take(views)
	var now := _bound.filter(_binds_now)
	if _pending_cmd:
		_pending_cmd = false
		var tab: Node = _panels[_tab]
		now.erase(tab)
		now.push_front(tab)
		_later = now
	else:
		_later = TownModel.merge_pending(_later, now)  # merged: a fetch before the queue drains drops nothing


## What every fetch does with its views before the binds: the tier, the last views, the goal, the replay check.
func _take(views: Dictionary) -> void:
	_tier = String(views["town"].get("tier", ""))
	_last_views = views
	_update_goal(views)
	if _away_check:
		_away_check = false
		_check_replay(views)


## Whether `n` binds on this fetch: the HUD and the town view always; the tab on show; and the Build tab even
## hidden, because it owns what the town view shows whatever tab is open (the suggestion tag, the queue ghosts,
## the placement check) and measures the build throughput between binds. A hidden Build tab skips its rows
## itself. The other tabs own nothing outside their own nodes: a hidden one keeps `_last_views` and binds once
## when shown.
func _binds_now(n: Node) -> bool:
	var i := _panels.find(n)
	return i < 0 or i == _tab or i == 0


## The jobs TownSim would staff for job `order`, with `extra` ({vat slot: on}) applied: GameState's
## view_staffing_projection (STATE-API v5, TownSim's own rule; the #16 stand-in is retired). Made once per
## (rev, order, extra); the tabs get this as a Callable and never call GameState for it.
func project_staffing(order: Array, extra := {}) -> Array:
	var s: GameState = Game.state
	return _staff_cache.fetch(int(s.rev), [order, extra], func() -> Variant:
		return s.view_staffing_projection(order, extra).get("jobs", [])) as Array


func _fetch_views() -> Dictionary:
	return _fetch_views_b(_fetch_views_a())


## Phase A of a fetch: the views the Build tab and the HUD read together (the queue, can_build, the stocks and
## rates, from one rev), and the cheap ones. ~3 ms cold at midgame.
func _fetch_views_a() -> Dictionary:
	var s = Game.state
	return {
		"town": s.view_town(), "hud": s.view_hud(), "rates": s.view_rates(), "catalog": s.view_catalog(),
		"backups": s.view_backups(), "inventory": s.view_inventory(), "big_undead": s.view_big_undead(),
		"party": s.view_party(), "relish": s.view_relish(), "vei": s.view_vei(), "fort_names": _fort_names,
	}


## Phase B: the stances, the fort digest (view_realm), and what is computed from all of the views (the demo city,
## the lot hops, the shared suggestion). A spread refresh runs it a frame after phase A; the views may then be a rev
## apart, and the next refresh (rev moved) closes the gap.
func _fetch_views_b(views: Dictionary) -> Dictionary:
	var s = Game.state
	views["stances"] = s.view_stances()
	views["forts"] = _forts(s.view_realm())
	if _demo == "full":
		views = TownStandins.demo_views(views, ConfigDb.data.get("buildings", {}), ConfigDb.data.get("town", {}))
	# the same lot hops the autoplayer breaks ties with, and the one suggestion the Build tab and the HUD show,
	# computed once per fetch for every panel (the town view's own model binds after the HUD, so it can't lend them)
	var cfgs := {"town": ConfigDb.data.get("town", {}), "buildings_view": ConfigDb.data.get("buildings_view", {}),
		"buildings": ConfigDb.data.get("buildings", {}), "economy": ConfigDb.data.get("economy", {})}
	# (TownModel._layout reads only config and ref_px, so the hops never change: one compute, kept)
	views["lot_hops"] = _hops_cache.fetch(0, "hops", func() -> Variant:
		return BuildSort.lot_maps(views, cfgs)["hops"])
	views["tab"] = BuildSort.tab_suggestion(views, cfgs["buildings_view"], cfgs["buildings"], cfgs["town"].get("view", {}))
	return views


## The first-goal plate: the game's goal in bold (goal.head_px) over the step due now (goal.px), both in `text` on a
## ground plate edged in `select`, at guide.goal's x/y in the town view, under the lot card (so an open card is never
## covered). Hidden until a goal is due.
func _build_goal() -> void:
	var vcfg: Dictionary = ConfigDb.v("town", "view", {})
	var g: Dictionary = vcfg.get("guide", {}).get("goal", {})
	_plates = VBoxContainer.new()
	_plates.add_theme_constant_override("separation", int(vcfg.get("replay", {}).get("gap_px", 6.0)))
	_plates.position = Vector2(float(g.get("x_px", 12.0)), float(g.get("y_px", 8.0)))
	_plates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_plates)
	_view.move_child(_plates, _view.card.get_index())
	_goal = PanelContainer.new()
	var sb := TownUI.panel_box()
	sb.border_color = Palette.c("select")
	_goal.add_theme_stylebox_override("panel", sb)
	_goal.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal.add_child(col)
	_goal_head = TownUI.label("", int(g.get("head_px", 18)), "text")
	_goal_head.add_theme_font_override("font", TownUI.bold_font())
	_goal_step = TownUI.label("", int(g.get("px", 16)), "text")
	for l in [_goal_head, _goal_step]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
	_plates.add_child(_goal)


## The welcome-back replay, when the away report is due one (TownReplay.due): the strip, then each finished build's
## lot flashing in the report's order, replay.first_beats then flash_beats apart. Marks the report replayed.
func _check_replay(views: Dictionary) -> void:
	if _demo != "":
		return
	var rep: Dictionary = Game.state.view_away()
	var gid := String(views.get("hud", {}).get("game_id", ""))
	if not TownReplay.due(rep, _replayed, gid):
		return
	_replayed = TownReplay.key(rep, gid)
	var rcfg: Dictionary = ConfigDb.v("town", "view", {}).get("replay", {})
	_strip.show_report(TownReplay.title(rep, rcfg), TownReplay.lines(rep, rcfg))
	_replay_lots = TownReplay.finished_lots(rep, views.get("town", {}), ConfigDb.data.get("buildings_view", {}),
		ConfigDb.v("economy", "idle", {}).get("report", {}))
	_replay_left = _beats_s(float(rcfg.get("first_beats", 1.0)))
	if _log_set:
		print("TOWNSET replay lots=%s frame=%d" % [str(_replay_lots), _frame])


## `beats` of Pulse's tempo, in seconds.
func _beats_s(beats: float) -> float:
	return maxf(beats * Pulse.tempo_ms * 0.001, 0.0)


func _replay_step(delta: float) -> void:
	_replay_left -= delta
	if _replay_left > 0.0:
		return
	if _replay_lots.is_empty():
		_replay_left = -1.0
		_strip.flashes_done()
		return
	_view.flash_lot(String(_replay_lots.pop_front()))
	_replay_left = _beats_s(float(ConfigDb.v("town", "view", {}).get("replay", {}).get("flash_beats", 1.0)))


## A strip line's button: the Crypt tab (the slab), the Build tab (the queue), or back to the realm (a raid line).
func _on_strip_acted(act: String) -> void:
	match act:
		"crypt":
			_select_tab(4)
		"build":
			_select_tab(0)
		"realm":
			_on_return()


## Sets the goal plate from the fetched views; the labels are touched only when the step changes.
func _update_goal(views: Dictionary) -> void:
	if _goal == null:
		return
	var g := TownGuide.goal(views, ConfigDb.v("town", "view", {}).get("guide", {}))
	var text := String(g.get("text", ""))
	if text != _goal_step.text:
		_goal_step.text = text
		_goal_head.text = String(g.get("head", ""))
		_goal_head.visible = _goal_head.text != ""
		_goal.visible = text != ""
		_goal.reset_size()
		_plates.reset_size()


## The forts as the crypt's Siege… chooser and the first goal (TownGuide) need them:
## [{id, name, held, flipped_count, first_dungeon}] in world order.
func _forts(realm: Dictionary) -> Array:
	var out: Array = []
	for f in realm.get("forts", []):
		out.append({"id": String(f.get("id", "")), "name": String(f.get("name", "")), "held": bool(f.get("held", false)),
			"flipped_count": int(f.get("flipped_count", 0)), "first_dungeon": bool(f.get("first_dungeon", false)),
			"margin": String(f.get("margin", ""))})  # the forecast's will_fall (TownForecast)
	return out


func _on_game_event(ev: Dictionary) -> void:
	if String(ev.get("type", "")) == "away_report":
		# a catch-up's events went to the away report, not to the scenes: away_report is the cue to re-read every
		# view (the catch-up ruling, STATE-API §6), so the next frame fetches and binds everything at once; that fetch
		# also looks for the welcome-back replay
		_dirty = true
		_away_check = true
	for n in _bound:
		if n.has_method("on_game_event"):
			n.on_game_event(ev)


## Plays the Synth kind town.json `sound.kinds` gives `event` (nothing when it has none).
func _play(event: String) -> void:
	var kind := TownSound.kind_for(ConfigDb.v("town", "sound", {}), event)
	if kind != "":
		_synth.play(kind)


func _on_sfx(id: String) -> void:
	match id:
		"tier_up":
			_play("tier_up")
		"trade":
			var now := float(Time.get_ticks_msec()) * 0.001
			if TownSound.allow(now, _last_trade, float(ConfigDb.v("town", "sound", {}).get("trade_min_gap_s", 0.0))):
				_last_trade = now
				_play("trade_blip")


func _on_raise_started() -> void:
	_view.echo_raise()
	_play("raise_grow")
	if _log_set:
		print("TOWNSET raise_started frame=%d" % _frame)


func _on_raise_landed() -> void:
	_play("raise_done")
	if _log_set:
		print("TOWNSET raise_landed frame=%d" % _frame)
	if _raise_lot != "":
		var lot := _raise_lot
		_raise_lot = ""
		var delay := float(ConfigDb.v("town", "view", {}).get("demo_raise", {}).get("place_delay_s", 0.0))
		get_tree().create_timer(delay).timeout.connect(_debug_raise_walk.bind(lot))


## The debug set-piece drivers (see _raise_lot). All of them need a debug build.
func _debug_set_pieces() -> void:
	if not Game.state.debug_enabled:
		return
	var spec: Dictionary = ConfigDb.v("town", "view", {}).get("demo_raise", {})
	for slot in _debug_arg("town-staff-vat").split(",", false):
		if slot.is_valid_int():
			Game.state.cmd_staff_vat(int(slot), true)
	if _debug_has("town-raise"):
		_log_set = true
		var lot := _debug_arg("town-raise")
		_raise_lot = lot if lot != "" else _free_lot()
		for p in _panels:
			if p.has_method("debug_autoraise"):
				p.debug_autoraise(float(spec.get("delay_s", 0.0)))
	elif _debug_has("town-hold"):  # `--town-hold`: the same mouse hold, stopped at the name prompt (its field focused)
		for p in _panels:
			if p.has_method("debug_autoraise"):
				p.debug_autoraise(float(spec.get("delay_s", 0.0)), true)
	# `--town-grant=gold:20000,bone:5000`: cmd_debug_grant before the first refresh (a store over its cap, for a shot)
	var grant := {}
	for pair in _debug_arg("town-grant").split(",", false):
		var kv := pair.split(":")
		if kv.size() == 2 and kv[1].is_valid_float():
			grant[kv[0]] = float(kv[1])
	if not grant.is_empty():
		print("TOWNSET grant %s -> %s" % [str(grant), str(Game.state.cmd_debug_grant(grant).get("ok", false))])
		_dirty = true
	var place := _debug_arg("town-place").split(":")
	if place.size() == 2:
		_log_set = true
		get_tree().create_timer(float(spec.get("place_delay_s", 0.0))).timeout.connect(_debug_place.bind(place[0], place[1]))
	# `--town-enqueue=inn:lot-13,bakery:lot-08`: the real cmd_queue_build (where --town-queue seeds only the stand-in)
	for pair in _debug_arg("town-enqueue").split(",", false):
		var bl := pair.split(":")
		if bl.size() == 2:
			var r: Dictionary = Game.state.cmd_queue_build(bl[0], bl[1])
			print("TOWNSET enqueue %s -> %s ok=%s %s" % [bl[0], bl[1], str(r.get("ok", false)), str(r.get("reason", ""))])
			_dirty = true
			_panels[0].debug_show_queue(6.0)
	# `--town-away=<seconds>`: a real open-game gap of that length (GameState.tick's reporting catch-up), so its
	# away_report reaches this scene as it would after a sleep: the welcome-back replay's driver
	var away := _debug_arg("town-away")
	if away.is_valid_float() and float(away) > 0.0:
		_log_set = true
		var s: GameState = Game.state
		s.tick(float(away) * s.time_scale, s.max_substeps_per_frame())
		print("TOWNSET away %s s, catching up=%s frame=%d" % [away, str(s.view_catchup().get("active", false)), _frame])


## A building with no foreman, other than the crypt, for the demo raise's walk-out.
func _free_lot() -> String:
	for b in Game.state.view_town().get("buildings", []):
		if String(b.get("foreman", "")) == "" and String(b.get("building_id", "")) != "crypt" and String(b.get("state", "")) != "constructing":
			return String(b.get("lot_id", ""))
	return ""


## Stands in for the raise while it is a stub that mints nothing: one big undead is granted, named as the slab
## named it (CryptLogic.raise_name), and placed at `lot` with the real place command.
func _debug_raise_walk(lot: String) -> void:
	var before := {}
	for e in Game.state.view_big_undead().get("big_undead", []):
		before[String(e["uid"])] = true
	Game.state.cmd_debug_grant({"big_undead": 1})
	for e in Game.state.view_big_undead().get("big_undead", []):
		var uid := String(e["uid"])
		if not before.has(uid):
			# the slab's name for the husk and remnants on it (what the raise was kept under), not a made-up one
			var crypt: Control = _panels[4]
			Game.state.cmd_rename_big_undead(uid, CryptLogic.raise_name(String(crypt.last_raise_name), e,
				ConfigDb.data.get("town", {}).get("slab", {})))
			_debug_place(uid, lot)
			return
	printerr("Covington: --town-raise could not mint a big undead (at the cap?)")


func _debug_place(uid: String, lot: String) -> void:
	var r: Dictionary = Game.state.cmd_place_big_undead(uid, "town:" + lot)
	_dirty = true
	if _log_set:
		print("TOWNSET place %s -> %s ok=%s %s frame=%d" % [uid, lot, str(r.get("ok", false)), str(r.get("reason", "")), _frame])


func _on_return() -> void:
	if _finished:
		return
	_finished = true
	_hud.set_return_enabled(false)
	finished.emit({"v": 2, "teleport_to": ""})
