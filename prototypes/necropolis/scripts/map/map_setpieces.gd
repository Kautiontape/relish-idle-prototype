class_name MapSetpieces
extends Node
## The map's set pieces (VISUAL-LANGUAGE 2e), each a short treatment on the tempo, and the quiet
## tempo pulse on every beat at Covington (hop 0):
##   valve swing   a committed valve (MapValve.committed): Covington's stems tween to the new
##                 shares over one beat, brighter for that beat; Synth "whoosh".
##   flip          fort_flipped: the fort's ring re-inks orange to green segment by segment from
##                 12 o'clock over 1.5 beats, then its glyph and chip change; Synth "flip"; a
##                 callout "<Fort> taken by you". The game's first fort adds a green ripple on
##                 the fort's beat. note_return: after a raid whose fort is held (event missed)
##                 it plays too.
##   retreat       the map mounts after a raid that left the fort Vei's (Relish alive): a callout
##                 "<Fort> stays Vei's: you kept all you found". No re-ink, no sound.
##   tithe         tithe_warning: Synth "horn"; tithe_wave: an orange band sweeps from Vei along the
##                 living lane to the target fort over 2 beats.
##   garrison      counter_garrison_cleared: a green pulse along the fort's WAR lane from
##                 Covington, a green burst at the fort, the chip's counter-garrison draining to
##                 0 and flipping to the margin word, a callout.
##   victory       vei_result won (or won at map open): every lane runs green toward Vei for 2
##                 beats, then every dash stops and the victory line shows. It plays once per
##                 game (MapSeen VICTORY, per game_id); a later mount of a won game settles
##                 straight to its end state at mount (dashes stopped, the victory line up),
##                 without waiting for the camera ease.
##   build         building_done (or a lot whose level rose while the map was not up, found at mount):
##                 a plate above Covington, "Inn built · MINT +0.8/s", the sim's own projection for it
##                 (MapModel.proj_store) named by its biggest rate; several builds read as one plate.
##                 Not for a mount whose away panel opens: its report lists the builds.
## Garrison and victory play no sound of their own (VISUAL-LANGUAGE 2f names none).
## It hears events through Game.game_event (the router re-emits the ones it held while the map
## mounted). It drives the existing layers through small hooks: MapNodes' context
## (valve_shares / valve_bright, reink, chip_fx) and redraw_* calls, MapRoutes.set_victory,
## MapHud.show_victory and its own MapSetpieceLayer (bands, rings, callouts). Set pieces wait
## until go_live (world_map calls it once the camera's ease out of the scene just left is over),
## so they play where the player can see them. Every clock is beats on Pulse's wall clock, so
## reduced motion (each set piece straight to its end state) still times them; sounds still play.
## Debug: --setpiece=<kind> fires one at a demo fort debug_delay_s after going live;
## --setpiece-slow=k stretches every set piece k times. Always pair them with --fixture=:
## --setpiece=valve sends a real cmd_set_valve. --setpiece is not in BootRule.DEV_ARGS (those match engine
## args given without the `--` separator), but it never autosaves over auto.json either: as a user arg
## (after `--`) it is outside PLAYER_ARGS, so BootRule.is_harness_args makes the session a harness
## one. The fixture still pins the state it runs on. Timing: setpiece_logic.gd. Tuning:
## configs/map_view.json "setpieces"; sounds: configs/synth.json.

var model: MapModel
var nodes: MapNodes
var routes: MapRoutes
var hud: MapHud
var seen: MapSeen  # the game's shown-once flags: victory plays once per game
var valve: MapValve
var callouts: MapCallouts  # the lane callouts' drawn plates: soft obstacles to the set-piece line
var cam: MapCamera  # its position and the visible screen place the callouts in the frame
var _placed := {}  # "<fort>|<text>" -> {sig, lines, choice}: a callout's place, kept until its inputs change
var layer: MapSetpieceLayer

var _synth: Synth
var _live := false
var _queue: Array = []  # set pieces that arrived before go_live: {kind, fort_id, n}
var _active: Array = []  # running: {kind, fort_id, n, start_ms, track?}
var _beat := -1
var _slow := 1.0
var _debug_kind := ""
var _committed := {}  # the valve Covington's stems show at rest
var _swing := {}  # {from, to, start_ms} while the valve swing runs
var _valve_rev := -1  # the model.rev the idle valve target was last read at
var _taken_ids: Array = []  # forts whose fort_flipped this map heard (the router replays the ones it held): note_return's "taken"
var _won := false  # victory has played, is playing or was settled: once per map
var _chips_sig: Array = []  # the inputs _chips_key_cache was measured for
var _chips_key_cache: Array = []  # _chips_key's last result
var _won_at_mount := false  # the game was already won when the map mounted: its victory is seen, an away_report replays nothing
var _placed_used := {}  # the _placed keys drawn this frame: the rest are pruned at its end
var _builds: Array = []  # the finished builds the callout at Covington names: [{lot_id, building_id, level}]
var _build_runs: Array = []  # its line as runs (SetpieceLogic.build_spans)
var _build_start_ms := -1.0  # when it started; -1 until the set pieces are live
var _build_line := ""  # its text
var _build_hit := {}  # its place, kept until its inputs change: {sig, pos (world, the plate's bottom centre), choice}
var _fort_rects: Array = []  # the fort callouts placed this frame (zoomed frame): hard to the build line


func _ready() -> void:
	_synth = Synth.new()
	_synth.name = "Synth"
	add_child(_synth)
	_synth.warm(["pulse", "whoosh", "horn", "flip"])
	Game.game_event.connect(on_event)
	valve.committed.connect(_on_valve_committed)
	var dbg := SetpieceLogic.debug_args(OS.get_cmdline_user_args(), Game.state.debug_enabled)
	_slow = float(dbg["slow"])
	_debug_kind = str(dbg["kind"])
	_committed = _target()
	nodes.ctx.valve_shares = _committed


func _exit_tree() -> void:
	if Game.game_event.is_connected(on_event):
		Game.game_event.disconnect(on_event)


func on_event(ev: Dictionary) -> void:
	var type := str(ev.get("type", ""))
	var id := str(ev.get("fort_id", ""))
	match type:
		"fort_flipped":
			if not _taken_ids.has(id):
				_taken_ids.append(id)
			_add(SetpieceLogic.FIRST_FLIP if SetpieceLogic.first_flip(id, model.forts) else SetpieceLogic.FLIP, id)
		"tithe_warning":
			_synth.play("horn")
		"tithe_wave":
			# (a won game has no tithe since #21: it idles at the win, so no wave reaches a won map)
			_add(SetpieceLogic.TITHE, id)
		"counter_garrison_cleared":
			var g := SetpieceLogic.garrison_from_event(ev)
			_add(SetpieceLogic.GARRISON, str(g["fort_id"]), int(g["n"]))
		"vei_result":
			if bool(ev.get("won", false)):
				_add(SetpieceLogic.VICTORY, "")
		"away_report":
			_after_away()
		"building_done":
			_note_build({"lot_id": str(ev.get("lot_id", "")), "building_id": str(ev.get("building_id", "")), "level": int(ev.get("level", 1))})


## A catch-up ended (away_report): the events it ran went into the report, so nothing replays as a set
## piece. What this keeps from events is re-read from the views (SetpieceLogic.after_away): the taken
## forts that are still held, and a victory the swallowed vei_result would have played.
func _after_away() -> void:
	model.refresh(true)  # the event can land before the map's own refresh this frame
	var r := SetpieceLogic.after_away(_taken_ids, model.forts, SetpieceLogic.victory_seen(_won, _won_at_mount), bool(model.hud.get("won", false)))
	_taken_ids = r["taken_ids"]
	if bool(r["victory"]):
		_add(SetpieceLogic.VICTORY, "")


## The map mounted: the builds that finished while it was not up (model.mount_rises, found by its first
## refresh) get their callout, unless `away_opened` (the away panel opened for this return, and its report
## already lists them). They take the same path as the live event, so one that is both is named once.
## A won game whose victory was already seen settles to its end state here, not at go_live (which waits
## for the camera ease): the map never shows live lanes first. The first play still waits for go_live.
func note_mount(away_opened: bool) -> void:
	_won_at_mount = bool(model.hud.get("won", false))
	if SetpieceLogic.victory_settle_at_mount(_won_at_mount, seen.has(MapSeen.VICTORY)):
		_start({"kind": SetpieceLogic.VICTORY, "fort_id": "", "n": -1})
	for b in SetpieceLogic.mount_builds(model.mount_rises, away_opened):
		_note_build(b)


## The map mounted after a scene: `arrive_from` is the node just left. A raid that took the fort
## (its fort_flipped, replayed by the router before this call, or a fort held within its grace that
## was not already held when the map dove into it, SetpieceLogic.note_dive) says "<Fort> taken by you"
## through the flip set piece; one that left it Vei's says it stays hers and you kept what you found
## (SetpieceLogic.return_kind); a held fort raided again says nothing. `stale` (the raid ended while away)
## never says RETREAT. Returns the kind (TAKEN, RETREAT, "").
func note_return(arrive_from: String, stale := false) -> String:
	var kind := SetpieceLogic.return_kind(arrive_from, model.fort(arrive_from), _taken_ids.has(arrive_from), model.relish, SetpieceLogic._last_dive, stale)
	if kind == SetpieceLogic.TAKEN and not _taken_ids.has(arrive_from):
		_taken_ids.append(arrive_from)  # no event came: the flip set piece still plays, as for the event
		_add(SetpieceLogic.FIRST_FLIP if SetpieceLogic.first_flip(arrive_from, model.forts) else SetpieceLogic.FLIP, arrive_from)
	elif kind == SetpieceLogic.RETREAT:
		_add(SetpieceLogic.RETREAT, arrive_from)
	return kind


## The camera has settled on the map: queued set pieces start, a won realm plays victory, and the
## debug trigger is armed.
func go_live() -> void:
	if _live or not is_inside_tree():
		return
	_live = true
	if bool(model.hud.get("won", false)):
		_add(SetpieceLogic.VICTORY, "")
	for p in _queue:
		_start(p)
	_queue.clear()
	if not _builds.is_empty():
		_build_start_ms = Pulse.now_ms()
	if _debug_kind != "":
		get_tree().create_timer(float(SetpieceLogic.cfg()["debug_delay_s"])).timeout.connect(_fire_debug)


func _add(kind: String, fort_id: String, n := -1) -> void:
	var p := {"kind": kind, "fort_id": fort_id, "n": n}
	if _live:
		_start(p)
	else:
		_queue.append(p)


func _start(p: Dictionary) -> void:
	var kind := str(p["kind"])
	var id := str(p["fort_id"])
	if kind == SetpieceLogic.VICTORY:
		var how := SetpieceLogic.victory_start(_won, seen.has(MapSeen.VICTORY))
		if how == "":
			return
		_won = true
		p["settle"] = how == SetpieceLogic.VICTORY_SETTLE
		if how == SetpieceLogic.VICTORY_PLAY:
			seen.mark(MapSeen.VICTORY)
	elif not model.forts_by_id.has(id):
		return
	for q in _active.duplicate():  # the same set piece at the same fort restarts
		if str(q["fort_id"]) == id and (str(q["kind"]) == kind or (kind in [SetpieceLogic.FLIP, SetpieceLogic.FIRST_FLIP] and str(q["kind"]) in [SetpieceLogic.FLIP, SetpieceLogic.FIRST_FLIP])):
			_active.erase(q)
	p["start_ms"] = Pulse.now_ms()
	_active.append(p)
	if kind == SetpieceLogic.FLIP or kind == SetpieceLogic.FIRST_FLIP:
		_synth.play("flip")
		if not Pulse.reduced_motion:
			nodes.ctx.reink[id] = {"switched": 0, "total": int(SetpieceLogic.cfg()["reink_segments"]), "from": NodeLogic.HERS}
			_redraw_fort_all(id)


func _process(_delta: float) -> void:
	_tempo()
	_valve_tick()
	var items: Array = []
	_fort_rects = []  # refilled by this frame's fort callouts (_callout), before the build line reads it
	var now := Pulse.now_ms()
	var rm: bool = Pulse.reduced_motion
	for p in _active.duplicate():
		var t := SetpieceLogic.beats(float(p["start_ms"]), now, Pulse.tempo_ms, _slow)
		var done := true
		match str(p["kind"]):
			SetpieceLogic.FLIP, SetpieceLogic.FIRST_FLIP:
				done = _flip_tick(p, t, rm, items)
			SetpieceLogic.TITHE:
				done = _tithe_tick(p, t, rm, items)
			SetpieceLogic.GARRISON:
				done = _garrison_tick(p, t, rm, items)
			SetpieceLogic.VICTORY:
				done = _victory_tick(t, rm, bool(p.get("settle", false)))
			SetpieceLogic.RETREAT:
				done = _retreat_tick(p, t, rm, items)
		if done:
			_active.erase(p)
	_build_tick(items)
	_placed = SetpieceLogic.prune_placed(_placed, _placed_used)
	_placed_used = {}
	layer.set_items(items)


## The tempo pulse: a quiet thump on each beat at Covington. Counted from the clock, so reduced
## motion (a steady Pulse.phase) never silences it; muted, Synth plays nothing.
func _tempo() -> void:
	var b := SetpieceLogic.beat_index(Pulse.now_ms(), Pulse.tempo_ms)
	if b != _beat:
		if _beat >= 0:
			_synth.play("pulse")
		_beat = b


# --- the valve swing --------------------------------------------------------------------------

func _target() -> Dictionary:
	return ValveLogic.normalise(model.hud.get("valve_target", model.hud.get("valve", {})))


func _on_valve_committed(v: Dictionary) -> void:
	_swing_to(ValveLogic.normalise(v))


## Swings the stems from what they show now to `v` over one beat, with the whoosh. A commit that
## did not move the valve is no swing.
func _swing_to(v: Dictionary) -> void:
	var drawn: Dictionary = nodes.ctx.valve_shares if not nodes.ctx.valve_shares.is_empty() else _committed
	_committed = v
	if not SetpieceLogic.valve_moved(drawn, v):
		return
	_swing = {"from": drawn.duplicate(), "to": v, "start_ms": Pulse.now_ms()}
	_synth.play("whoosh")


## While a swing runs, tween the stems; otherwise follow a target changed from outside the panel
## (a load, a fixture) without one. Held while the handle is dragged.
func _valve_tick() -> void:
	var ctx := nodes.ctx
	if not _swing.is_empty():
		var t := SetpieceLogic.beats(float(_swing["start_ms"]), Pulse.now_ms(), Pulse.tempo_ms, _slow)
		var rm: bool = Pulse.reduced_motion
		ctx.valve_shares = SetpieceLogic.valve_shares(_swing["from"], _swing["to"], t, rm)
		ctx.valve_bright = SetpieceLogic.valve_bright(t, rm)
		if SetpieceLogic.valve_done(t):
			_swing = {}
			ctx.valve_shares = _committed
			ctx.valve_bright = 0.0
		nodes.redraw_covington()
		return
	if valve.is_dragging() or model.rev == _valve_rev:
		return  # idle: nothing to read until the model re-reads the game
	_valve_rev = model.rev
	var target := _target()
	if SetpieceLogic.valve_moved(target, _committed):
		_committed = target
		ctx.valve_shares = target
		nodes.redraw_covington()


# --- the flip ---------------------------------------------------------------------------------

func _flip_tick(p: Dictionary, t: float, rm: bool, items: Array) -> bool:
	var id := str(p["fort_id"])
	var ctx := nodes.ctx
	var done := SetpieceLogic.reink_done(t, rm)
	if not done:
		var cnt := SetpieceLogic.reink_count(t, rm)
		var rk: Dictionary = ctx.reink.get(id, {})
		if rk.is_empty() or int(rk["switched"]) != cnt:
			ctx.reink[id] = {"switched": cnt, "total": int(SetpieceLogic.cfg()["reink_segments"]), "from": NodeLogic.HERS}
			nodes.redraw_fort(id)
	elif ctx.reink.has(id):
		ctx.reink.erase(id)
		_redraw_fort_all(id)  # the ring is done: now the glyph and the chip change
	var c := SetpieceLogic.cfg()
	var f := model.fort(id)
	if f.is_empty():
		return done
	if str(p["kind"]) != SetpieceLogic.FIRST_FLIP:  # every fort taken says so: "<Fort> taken by you"
		var a0 := SetpieceLogic.callout_alpha(t, float(c["callout_beats"]), rm)
		if a0 > 0.0:
			items.append_array(_callout(id, SetpieceLogic.return_text(SetpieceLogic.TAKEN, str(model.names.get(id, id))), a0))
		return done and t >= float(c["callout_beats"])
	var rip := SetpieceLogic.ripple(Pulse.phase(model.hops_of(id)), t, rm)
	if not rip.is_empty():
		items.append({"kind": "ring", "pos": MapModel.to_vec(f["pos"]), "key": "undead", "alpha": float(rip["alpha"]),
			"r": MapLogic.fort_radius(int(f["tier"])) + float(c["ripple_reach_px"]) * float(rip["reach"]),
			"width": float(c["ripple_width_px"]), "cap": float(c["ripple_halo_max_px"])})
	var a := SetpieceLogic.callout_alpha(t, float(c["callout_beats"]), rm)
	if a > 0.0:
		items.append_array(_callout(id, SetpieceLogic.first_flip_text(str(model.names.get(id, id))), a))
	return done and t >= maxf(float(c["ripple_beats"]), float(c["callout_beats"]))


## A retreat: the fort stays Vei's, so no re-ink and no sound, just the line over the fort for
## callout_beats (a plain word colour: it is not a win).
func _retreat_tick(p: Dictionary, t: float, rm: bool, items: Array) -> bool:
	var id := str(p["fort_id"])
	var c := SetpieceLogic.cfg()
	if model.fort(id).is_empty():
		return true
	var a := SetpieceLogic.callout_alpha(t, float(c["callout_beats"]), rm)
	if a > 0.0:
		items.append_array(_callout(id, SetpieceLogic.return_text(SetpieceLogic.RETREAT, str(model.names.get(id, id))), a, "text"))
	return t >= float(c["callout_beats"])


func _redraw_fort_all(id: String) -> void:
	nodes.redraw_fort(id)
	nodes.redraw_glyphs()
	nodes.redraw_chips()


## A fort's callout: one label item per line, where SetpieceLogic.callout_place puts it. Today's place
## (centred above the fort's rings, callout_gap_px clear, and above Relish's token when she stands
## there: back from its dungeon, she does) when nothing is in the way; else slid, split at ": " into
## two lines (set in callout_font_two), under the fort's plates, or beside its ring, so it never covers
## another fort. Hard: every other fort's ring, every fort's name and tag plates, the held forts' chips,
## Relish's token, Covington's glyph and labels and Vei's (MapNodes.node_obstacles). Soft: the lane
## callouts as drawn (MapCallouts.drawn_rects); the open card is not read here.
func _callout(id: String, text: String, alpha: float, key := "undead") -> Array:
	var ctx := nodes.ctx
	var grid := float(MapLogic.cfg()["callouts"]["token_key_px"])
	var cp := cam.position if cam != null else Vector2.ZERO
	var tok := ctx.relish_pos * ctx.zoom
	# what the placement depends on (not the frame): the line, the zoom and camera, the viewport, her token on
	# the callouts' grid, and the model's rev (the held set, the chips)
	var sig := SetpieceLogic.callout_key(text, ctx.zoom, cp, get_viewport().get_visible_rect().size, ctx.tier, model.rev,
		Vector2(roundi(tok.x / grid), roundi(tok.y / grid)), HudLogic.rects_key(callouts.drawn_rects()) if callouts != null else [], _chips_key(ctx.zoom, ctx.tier), NodeLogic.panel_key(ctx.panel))
	var ck := "%s|%s" % [id, text]
	_placed_used[ck] = true
	var hit: Dictionary = _placed.get(ck, {})
	if hit.is_empty() or hit["sig"] != sig:
		var made := _place_callout(id, text, hit.get("choice", {}))  # the last choice stays while it is still free
		# no place near the fort is clear of the hard marks (a crowded corner, as the first dungeon by
		# Covington): the line goes to the HUD toast, once, rather than print over other labels (V-I1 item 6)
		var toast := bool(hit.get("toast", false)) or SetpieceLogic.callout_to_toast(float(made["hard"]))
		if toast and not bool(hit.get("toast", false)) and hud != null:
			hud.show_toast(text)
		hit = {"sig": sig, "lines": made["lines"], "rects": made["rects"], "choice": made["choice"], "toast": toast}
		_placed[ck] = hit
	if bool(hit["toast"]):
		return []
	_fort_rects.append_array(hit["rects"])  # the build line, placed after this frame's callouts, goes round them
	var out: Array = []
	for l in hit["lines"]:
		out.append({"kind": "label", "pos": l["pos"], "text": l["text"], "size": int(l["size"]), "key": key, "alpha": alpha})
	return out


## The held forts' chip rects as the placement reads them (zoomed frame), in whole px: part of the cache
## key, since a chip's width ticks with its text between revs. The rects cost a measure per held fort,
## so they are re-measured only when their inputs change (SetpieceLogic.chips_sig), not every frame.
func _chips_key(z: float, tier: String) -> Array:
	var ctx := nodes.ctx
	var grid := float(MapLogic.cfg()["callouts"]["token_key_px"])
	var tok := ctx.relish_pos * ctx.zoom
	var travelling := str(ctx.relish.get("state", "")) == "travelling"
	var shares: Dictionary = ctx.valve_shares if not ctx.valve_shares.is_empty() else model.hud.get("valve_target", model.hud.get("valve", {}))  # as MapFortIdle._layout
	var extra := [model.forts.size(), travelling, ctx.relish_pos if not travelling else Vector2.ZERO, roundi(model.drawn_backlog() * 1000.0),
		roundi(ctx.vei_radius * 10.0), ctx.cov_pos, ctx.vei_pos]
	var sig := SetpieceLogic.chips_sig(model.rev, z, tier, model.margin_sig, ctx.chip_fx, Vector2(roundi(tok.x / grid), roundi(tok.y / grid)), NodeLogic.panel_key(ctx.panel), shares, extra)
	if sig == _chips_sig:
		return _chips_key_cache
	_chips_sig = sig
	var rects: Array = []
	if IdleLogic.chip_shown(tier, z):
		for g in model.forts:
			if bool(g.get("held", false)):
				var r := nodes.chip_world_rect(g)
				rects.append(Rect2(r.position * z, r.size * z))
	_chips_key_cache = HudLogic.rects_key(rects)
	return _chips_key_cache


## Where `text` goes for the fort `id`: {lines: [{pos (world), text}], choice: {form, place, slide}}.
func _place_callout(id: String, text: String, prev: Dictionary) -> Dictionary:
	var f := model.fort(id)
	var c := SetpieceLogic.cfg()
	var ctx := nodes.ctx
	var z := ctx.zoom
	var size := int(c["callout_font"])
	var p := MapModel.to_vec(f["pos"]) * z
	var nc := NodeLogic.ncfg()  # the first dungeon's pulse reaches past its outer ring: the line keeps clear of it too
	var ring_r := SetpieceLogic.callout_own_r(NodeLogic.outer_radius("fort", int(f["tier"]), 0.0), MapLogic.fort_radius(int(f["tier"])),
		NodeLogic.first_dungeon_pulse(f), float(nc["first_reach_px"]), float(nc["first_halo_max_px"])) * z
	var gap := float(c["callout_gap_px"])
	var base_y := p.y - ring_r - gap
	var halo := float(NodeLogic.relish_radii(z)["halo"]) * z
	var token := ctx.relish_pos * z
	var node_hard := SetpieceLogic.node_hard(nodes.node_obstacles(), z)  # Covington's and Vei's discs and plates
	var forts := _fort_obstacles(id, z)
	var own: Array = forts["own"]
	var obs := {"rings": forts["rings"], "circles": [Vector3(token.x, token.y, halo)] + (node_hard["circles"] as Array),
		"rects": (node_hard["rects"] as Array) + (forts["rects"] as Array), "soft": callouts.drawn_rects() if callouts != null else []}
	if str(model.relish.get("at", "")) == id and str(model.relish.get("state", "")) != "travelling":
		base_y = minf(base_y, token.y - halo - gap)
		own.append(Rect2(token - Vector2(halo, halo), Vector2(halo, halo) * 2.0))
	var widths := {"one": MapNodeLayer.label_width(text, size)}
	var split := SetpieceLogic.split_text(text)
	var size_two := int(c.get("callout_font_two", size))
	if not split.is_empty():
		widths["a"] = MapNodeLayer.label_width(str(split[0]), size_two)
		widths["b"] = MapNodeLayer.label_width(str(split[1]), size_two)
		widths["size_two"] = size_two
	if hud != null:  # the visible screen between the top bar and the bottom bars
		var cp := cam.position if cam != null else Vector2.ZERO
		obs["bounds"] = SetpieceLogic.screen_bounds(get_viewport().get_visible_rect().size, cp, z, hud.bar_bottom(), hud.bottom_top())
	var at := SetpieceLogic.callout_place(p, ring_r, base_y, size, widths, own, obs, prev)
	var texts: Array = split if str(at["form"]) == "two" else [text]
	var lines: Array = []
	for i in texts.size():
		var pos := (at["pos"] as Vector2) + Vector2(0.0, float(i) * float(at["line"]))
		lines.append({"pos": pos / z, "text": str(texts[i]), "size": int(at["size"])})
	return {"lines": lines, "rects": at["rects"], "choice": {"form": at["form"], "place": at["place"], "slide": at["slide"]}, "hard": float(at.get("hard", 0.0))}


## The forts' hard obstacles in the zoomed frame, for a callout at the fort `own_id` ("" at Covington): {rings:
## [Vector3] every other fort's outermost ring, rects: every other fort's name and tag plates and held chip,
## own: the fort's own plates and chip}.
func _fort_obstacles(own_id: String, z: float) -> Dictionary:
	var ctx := nodes.ctx
	var rings: Array = []
	var rects: Array = []
	var own: Array = []
	var font := ThemeDB.fallback_font  # what the map's labels measure with
	var label_size := int(MapLogic.cfg()["font_label"])
	for g in model.forts:
		var gid := str(g["id"])
		var tier := int(g["tier"])
		var bucket: Array = own if gid == own_id else rects
		if gid != own_id:
			var gp := MapModel.to_vec(g["pos"]) * z
			rings.append(Vector3(gp.x, gp.y, NodeLogic.outer_radius("fort", tier, 0.0) * z))
		if NodeLogic.fort_label_shown(ctx.tier, tier):
			var tag := NodeLogic.name_tag(g)
			var tag_w := -1.0
			if not tag.is_empty() and ctx.tier != "far":
				tag_w = font.get_string_size(str(tag["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, NodeLogic.tag_size()).x
			var name_w := font.get_string_size(str(g["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
			bucket.append_array(SetpieceLogic.fort_plates(MapModel.to_vec(g["pos"]), tier, name_w, tag_w, z, ctx.panel))
		if bool(g.get("held", false)) and IdleLogic.chip_shown(ctx.tier, z):
			var r := nodes.chip_world_rect(g)
			bucket.append(Rect2(r.position * z, r.size * z))
	return {"rings": rings, "rects": rects, "own": own}


# --- a finished build -------------------------------------------------------------------------

## A build finished (the live event, or the mount's diff): it joins the callout at Covington, which
## restarts its clock with the new line. Several at once read as one plate.
func _note_build(b: Dictionary) -> void:
	var next := SetpieceLogic.add_build(_builds, b)
	if next.size() == _builds.size():
		return
	_builds = next
	_build_line = SetpieceLogic.build_text(_builds, MapModel.proj_store, _building_names())
	_build_runs = SetpieceLogic.build_spans(_build_line)
	_build_start_ms = Pulse.now_ms() if _live else -1.0


## building id -> its label (configs/buildings_view.json), as the HUD's bone line reads them.
func _building_names() -> Dictionary:
	var names := {}
	var view: Dictionary = ConfigDb.data.get("buildings_view", {})
	for id in view:
		names[id] = str(view[id].get("label", str(id).capitalize()))
	return names


func _build_tick(items: Array) -> void:
	if _builds.is_empty() or _build_start_ms < 0.0:
		return
	var t := SetpieceLogic.beats(_build_start_ms, Pulse.now_ms(), Pulse.tempo_ms, _slow)
	if SetpieceLogic.build_done(t):
		_builds = []
		_build_start_ms = -1.0
		return
	var a := SetpieceLogic.build_alpha(t, Pulse.reduced_motion)
	if a > 0.0:
		items.append(_build_plate(a))


## The build line's plate, where SetpieceLogic.build_place puts it: by default its bottom centre build_gap_px
## above Covington's rings, and above Relish's token when she stands there (home, she does); else slid or
## under, so it covers no fort's label. Placed AFTER the fort callouts (_process runs them first): theirs are
## hard to it (_fort_rects), while it is not hard to them. Kept until its inputs change (the line, zoom,
## camera, viewport, tier, model.rev, Relish's token on the callouts' grid, the lane callouts and the fort
## callouts' rects, the open card), never recomputed per frame.
func _build_plate(alpha: float) -> Dictionary:
	var c := SetpieceLogic.cfg()
	var ctx := nodes.ctx
	var z := ctx.zoom
	var grid := float(MapLogic.cfg()["callouts"]["token_key_px"])
	var cp := cam.position if cam != null else Vector2.ZERO
	var tok := ctx.relish_pos * z
	var soft: Array = callouts.drawn_rects() if callouts != null else []
	var sig := SetpieceLogic.callout_key(_build_line, z, cp, get_viewport().get_visible_rect().size, ctx.tier, model.rev,
		Vector2(roundi(tok.x / grid), roundi(tok.y / grid)), HudLogic.rects_key(soft + _fort_rects), _chips_key(z, ctx.tier), NodeLogic.panel_key(ctx.panel))
	if _build_hit.is_empty() or _build_hit["sig"] != sig:
		var made := _place_build(soft, _build_hit.get("choice", {}))
		_build_hit = {"sig": sig, "pos": made["pos"], "choice": made["choice"]}
	return {"kind": "runs", "pos": (_build_hit["pos"] as Vector2) / z, "runs": _build_runs, "size": int(c["build_font"]), "alpha": alpha}


## Where the build line goes now: {pos (the plate's bottom centre, zoomed frame), choice}. Obstacles as the fort
## callouts see them (hard: every fort's ring, name and tag plates and chip, Relish's halo, Vei, the fort callouts
## placed this frame; soft: the lane callouts), but Covington's own plates are its own.
func _place_build(soft: Array, prev: Dictionary) -> Dictionary:
	var c := SetpieceLogic.cfg()
	var ctx := nodes.ctx
	var z := ctx.zoom
	var p := model.node_pos(MapModel.COVINGTON) * z
	var ring_r := NodeLogic.outer_radius("covington", 0, 0.0) * z
	var gap := float(c["build_gap_px"])
	var bottom := p.y - ring_r - gap
	var halo := float(NodeLogic.relish_radii(z)["halo"]) * z
	var token := ctx.relish_pos * z
	var split := SetpieceLogic.build_obstacles(nodes.node_obstacles(), z)
	var forts := _fort_obstacles("", z)
	var own: Array = split["own"]
	if str(model.relish.get("at", "")) == MapModel.COVINGTON and str(model.relish.get("state", "")) != "travelling":
		bottom = minf(bottom, token.y - halo - gap)
		own.append(Rect2(token - Vector2(halo, halo), Vector2(halo, halo) * 2.0))
	var obs := {"rings": forts["rings"], "circles": [Vector3(token.x, token.y, halo)] + (split["circles"] as Array),
		"rects": (split["rects"] as Array) + (forts["rects"] as Array) + _fort_rects, "soft": soft}
	if hud != null:
		var cp := cam.position if cam != null else Vector2.ZERO
		obs["bounds"] = SetpieceLogic.screen_bounds(get_viewport().get_visible_rect().size, cp, z, hud.bar_bottom(), hud.bottom_top())
	var m := SetpieceLogic.build_metrics(_build_runs, int(c["build_font"]))
	var at := SetpieceLogic.build_place(p, ring_r, bottom, float(m["total"]), float(m["h"]) + float(c["build_pad_px"]) * 2.0, own, obs, prev)
	return {"pos": at["pos"], "choice": at["choice"]}


# --- bands along a lane -----------------------------------------------------------------------

## The track of the `kind` lane from `from` to `to` (the view's row when it has one, so the curve
## is the one the routes draw), trimmed off both nodes' rings.
func _track(kind: String, from: String, to: String) -> Dictionary:
	var row := {"id": "%s:%s:%s" % [kind, from, to], "kind": kind, "from": from, "to": to}
	for r in model.lanes:
		if str(r["id"]) == row["id"]:
			row = r
			break
	return SetpieceLogic.track(row, model.node_pos(from), model.node_pos(to), routes.node_trim_radius(from),
		routes.node_trim_radius(to), int(MapLogic.cfg()["ribbon_samples"]))


func _band(tr: Dictionary, b: Vector2, key: String, core: String, width: float, glow: float, cap: float) -> Dictionary:
	return {"kind": "band", "pts": SetpieceLogic.sub_polyline(tr["pts"], tr["cum"], b.x, b.y), "key": key, "core": core,
		"width": width, "glow": glow, "cap": cap}


func _tithe_tick(p: Dictionary, t: float, rm: bool, items: Array) -> bool:
	if not p.has("track"):
		p["track"] = _track("living", MapModel.VEI, str(p["fort_id"]))
	var tr: Dictionary = p["track"]
	var b := SetpieceLogic.tide(t, rm, float(tr["lo"]), float(tr["hi"]))
	if b == SetpieceLogic.NONE:
		return true
	var c := SetpieceLogic.cfg()
	items.append(_band(tr, b, "living", "living_core", float(c["tide_width_px"]), float(c["tide_glow"]), float(c["tide_halo_max_px"])))
	return false


# --- the garrison cleared ---------------------------------------------------------------------

func _garrison_tick(p: Dictionary, t: float, rm: bool, items: Array) -> bool:
	var id := str(p["fort_id"])
	var n := int(p["n"])
	var c := SetpieceLogic.cfg()
	var f := model.fort(id)
	var ctx := nodes.ctx
	if f.is_empty():
		if ctx.chip_fx.erase(id):
			nodes.redraw_chips()
		return true
	var g := SetpieceLogic.garrison(t, n, rm)
	var pos := MapModel.to_vec(f["pos"])
	var r := MapLogic.fort_radius(int(f["tier"]))
	if float(g["pulse"]) >= 0.0:
		if not p.has("track"):
			p["track"] = _track("war", MapModel.COVINGTON, id)
		var tr: Dictionary = p["track"]
		var b := SetpieceLogic.band_range(float(g["pulse"]), float(c["garrison_band_px"]), float(tr["lo"]), float(tr["hi"]))
		items.append(_band(tr, b, "undead", "undead_core", float(c["tide_width_px"]), float(c["tide_glow"]), float(c["tide_halo_max_px"])))
	var reach := float(c["garrison_burst_reach_px"])
	if float(g["burst"]) >= 0.0:
		var q := float(g["burst"])
		var rings := int(c["garrison_burst_rings"])
		for k in rings:
			items.append({"kind": "ring", "pos": pos, "r": r + reach * q * float(k + 1) / rings, "key": "undead",
				"alpha": pow(1.0 - q, 2.0), "width": float(c["garrison_burst_width_px"]), "cap": float(c["ripple_halo_max_px"])})
	elif bool(g["ring"]):  # reduced motion: the burst's still ring
		items.append({"kind": "ring", "pos": pos, "r": r + reach * 0.5, "key": "undead", "alpha": 1.0,
			"width": float(c["garrison_burst_width_px"]), "cap": float(c["ripple_halo_max_px"])})
	var chip: Dictionary = g["chip"]
	if chip != ctx.chip_fx.get(id, {}):
		if chip.is_empty():
			ctx.chip_fx.erase(id)
		else:
			ctx.chip_fx[id] = chip
		nodes.redraw_chips()
	if float(g["callout"]) > 0.0:
		items.append_array(_callout(id, SetpieceLogic.garrison_text(n), float(g["callout"])))
	if bool(g["done"]) and ctx.chip_fx.has(id):
		ctx.chip_fx.erase(id)
		nodes.redraw_chips()
	return bool(g["done"])


# --- victory ----------------------------------------------------------------------------------

## RUN, then STOP with the headline up, then END: the headline goes, the routes leave victory styling
## and drop every lane at Vei (MapRoutes.set_vei_hidden). A settle is END at once.
## END's lane hiding stays after #21 (MapRoutes.set_vei_hidden says why), as do the RUN / STOP / END beats.
func _victory_tick(t: float, rm: bool, settle := false) -> bool:
	var ph := SetpieceLogic.victory_phase(t, rm, settle)
	if ph == SetpieceLogic.END:
		hud.hide_victory()
		routes.set_victory("")
		routes.set_vei_hidden(true)
		if callouts != null:
			callouts.set_vei_hidden(true)  # their "why" plates go with the lanes
		return true
	routes.set_victory(ph)
	if ph == SetpieceLogic.STOP:
		hud.show_victory()
	return false


# --- debug ------------------------------------------------------------------------------------

## --setpiece=<kind>: the set piece at the demo fort, through the same path a real event takes.
func _fire_debug() -> void:
	if not is_inside_tree() or model.forts.is_empty():
		return
	var c := SetpieceLogic.cfg()
	var id := SetpieceLogic.demo_target(model.forts, str(c["debug_target"]))
	print("SETPIECE debug ", _debug_kind, " at ", id)
	match _debug_kind:
		SetpieceLogic.VALVE:
			var v := SetpieceLogic.demo_valve(_committed)
			if bool(model.state.cmd_set_valve(v["work"], v["war"], v["flood"])["ok"]):
				_swing_to(ValveLogic.normalise(v))
		SetpieceLogic.FLIP:
			_add(SetpieceLogic.FLIP, id)
		SetpieceLogic.FIRST_FLIP:
			_add(SetpieceLogic.FIRST_FLIP, id)
		SetpieceLogic.RETREAT:
			_add(SetpieceLogic.RETREAT, id)
		SetpieceLogic.TITHE:
			on_event({"type": "tithe_warning", "fort_id": id})
			on_event({"type": "tithe_wave", "fort_id": id})
		SetpieceLogic.GARRISON:
			on_event({"type": "counter_garrison_cleared", "fort_id": id, "killed_mass": float(c["debug_killed_mass"])})
		SetpieceLogic.VICTORY:
			on_event({"type": "vei_result", "won": true})
