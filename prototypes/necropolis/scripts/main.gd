extends Node
## Scene router (STATE-API 2.3): one active scene at a time. Every scene gets setup(args)
## with ids only and emits finished(result); every exit routes through here.
## Every scene gets ids only (STATE-API 2.3) and reads its seed from views. A v1 raid or boss
## result is still converted with Results.from_v1 before it is applied.

const MAP := "res://scenes/map/WorldMap.tscn"
const RAID := "res://scenes/raid/Raid.tscn"
const TOWN := "res://scenes/town/Covington.tscn"
const BOSS := "res://scenes/boss/VeiBoss.tscn"

var current: Node = null
var _gen := 0  # one per swap: a transition from an older swap stops when it sees a newer one
var _closing := false  # the window is closing: swaps mount directly, with no transition
var _held_events: Array = []  # game events drained while the swapped-in scene was not mounted yet
var _holding_sounds := false  # this router took a hold on Synth's render cache in _ready
var _catchup: MapCatchup  # the catch-up progress screen; the last child, so its _input hears events first
var _catchup_demo := false  # --catchup=demo: the screen is held at the demo progress


func _ready() -> void:
	AudioPrefs.apply()  # the saved mute and volume hold even in a scene with no Synth
	Synth.retain()  # hold the shared sound cache across scene swaps; released when the router goes
	_holding_sounds = true
	Game.game_event.connect(_on_game_event)
	_catchup = MapCatchup.new()
	_catchup_demo = Game.state.debug_enabled and OS.get_cmdline_user_args().has("--catchup=demo")
	add_child(_catchup)
	_update_catchup(0.0)  # a load's catch-up is already active: input is swallowed from the first frame
	_open_map()


## The catch-up screen follows view_catchup() (a small dict) once a frame.
func _process(delta: float) -> void:
	_update_catchup(delta)


## --catchup=demo (debug only) holds the screen at the configured demo progress.
func _update_catchup(dt: float) -> void:
	var view: Dictionary
	if _catchup_demo:
		var c := RouterLogic.catchup_cfg()
		view = {"active": true, "done_s": float(c["demo_done_s"]), "total_s": float(c["demo_total_s"])}
	else:
		view = Game.state.view_catchup()
	_catchup.update(view, dt, Pulse.reduced_motion)


## main is notified before its children: a close request mid-transition must not start another
## animation (the quit would wait on a snapshot).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_closing = true
	elif what == NOTIFICATION_PREDELETE and _holding_sounds:
		# At quit. The router's PREDELETE fires before its children are freed, so the scene's Synth
		# is usually the last holder; whichever lets go last clears the cache (no ObjectDB leak).
		_holding_sounds = false
		Synth.release()


## A result's events (loot_banked, fort_flipped) drain a frame or two after apply_result, often
## while the new scene waits for the dive's snapshot and is not in the tree to hear them: hold
## them for it (_mount re-emits them through Game.game_event).
func _on_game_event(ev: Dictionary) -> void:
	if current != null and not current.is_inside_tree():
		_held_events.append(ev)


## `arrive_from` is the node whose scene was just left: the map starts zoomed in on it.
## `toast` is a one-off line the map shows on arrival (a refused teleport's reason).
func _open_map(arrive_from := "", toast := "") -> void:
	var args := {"mode": "map"}
	if arrive_from != "":
		args["arrive_from"] = arrive_from
	if toast != "":
		args["toast"] = toast
	_swap(MAP, args)


## Map or town must never be open with a run open: forfeit one if it is.
func _forfeit_open_run() -> void:
	if Game.state.view_relish().get("run_id", -1) != -1:
		push_warning("necropolis: router forfeited an open run before opening the map or town")
		Game.state.cmd_abort_dungeon()


## Frees the old scene and opens `path`. On a missing or unloadable scene: forfeits any open
## run and falls back to the map (unless the map itself is what failed). `dive_to` is the map
## node the old map dives into before the swap; an `arrive_from` in `args` makes the new map
## ease out from that node. Either one runs a transition over the swap (_run_transition).
func _swap(path: String, args: Dictionary, dive_to := "") -> void:
	Engine.time_scale = 1.0
	_gen += 1
	_held_events = []  # events an abandoned swap held are not this scene's
	var old := current
	current = null
	if old != null and not (dive_to != "" or args.has("arrive_from")):
		old.queue_free()
		old = null
	var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed == null:
		push_warning("necropolis: scene unavailable " + path)
		Game.state.cmd_abort_dungeon()
		if old != null:
			old.queue_free()
		if path != MAP:
			_open_map()
		return
	if path == MAP or path == TOWN:
		_forfeit_open_run()
	var node: Node = packed.instantiate()
	current = node
	if node.has_signal("finished"):
		node.finished.connect(_on_finished.bind(node, path))
	# The scene is added deferred: a swap can run inside a notification (a window close
	# mid-raid routes the retreat result from NOTIFICATION_WM_CLOSE_REQUEST), where
	# add_child fails with "Parent node is busy setting up children". The result apply
	# above and the autosave below stay synchronous, so quitting still saves.
	Game.autosave()
	if old != null and not _closing and MapTransition.can_snapshot():
		_run_transition(old, node, args, dive_to, _gen)  # a coroutine: this call returns at its first suspension
	else:
		if old != null:
			old.queue_free()
		_mount.call_deferred(node, args)


## The dive: the map zooms into `dive_to` (if it can), the viewport is snapshotted onto the
## Transition layer over everything, the old scene is freed and the new one mounted, and the
## snapshot fades out. A return (no dive_to) snapshots the old scene first and the new map eases
## out on its own. The layer blocks input; reduced motion is a crossfade with no zoom. The old
## scene lives only until the snapshot, so two scenes never run at once. A newer swap (`gen`
## moved on) abandons this one.
func _run_transition(old: Node, node: Node, args: Dictionary, dive_to: String, gen: int) -> void:
	var tr := MapTransition.new()
	add_child(tr)
	var reduced: bool = Pulse.reduced_motion
	var kind := TransitionLogic.IN if dive_to != "" else TransitionLogic.OUT
	var tl := TransitionLogic.timeline(TransitionLogic.cfg(), kind, reduced, MapTransition.slow())
	if dive_to != "" and not reduced and old.has_method("dive_to"):
		await old.dive_to(dive_to, tl["zoom_s"])
	elif old.has_method("hide_hud"):
		old.hide_hud()  # no dive: the map still takes its HUD out of the snapshot
	var shot: bool = await tr.snapshot() if gen == _gen else false
	if is_instance_valid(old):
		old.queue_free()
	if gen != _gen:
		tr.queue_free()
		if is_instance_valid(node) and node != current and not node.is_inside_tree():
			node.queue_free()  # the abandoned swap's scene was never mounted
		return
	_mount.call_deferred(node, args)
	if not shot:
		tr.queue_free()
		return
	for i in int(TransitionLogic.cfg()["settle_frames"]):  # the new scene's first frames are the heavy ones
		await get_tree().process_frame
	tr.fade_out(tl["fade_s"])


## Adds a swapped-in scene and runs its setup. A scene replaced again before it mounted
## (two swaps in one frame) is dropped instead of added.
func _mount(node: Node, args: Dictionary) -> void:
	if not is_instance_valid(node):
		return
	if node != current:
		node.queue_free()
		return
	add_child(node)
	move_child(_catchup, -1)  # last in the tree: its _input runs before the new scene's
	if node.has_method("setup"):
		node.setup(args)
	var held := _held_events
	_held_events = []
	# Re-emit through Game.game_event so every listener the scene connected in _ready hears them
	# (HUD toasts, the away report, the ground's ink sweeps, set pieces, the tithe explanation).
	# The router does not act on game_event, and the legacy relish_respawned / victory signals
	# fire from Game._process's drain, not from game_event, so nothing fires twice.
	for ev in held:
		Game.game_event.emit(ev)


func _on_finished(result: Dictionary, emitter: Node, path: String) -> void:
	if emitter != current or emitter.has_meta("router_done"):
		return  # a late or duplicate emit from a scene that is no longer current
	emitter.set_meta("router_done", true)  # one handled emit per scene
	match path:
		MAP, TOWN:
			# map and town results are v2: they never move Relish
			_teleport(str(result.get("teleport_to", "")), "covington" if path == TOWN else "", path == MAP)
		RAID:
			# in_dungeon: Relish's `at` is the fort whose run is open (and the map arrives from it)
			var fort := str(Game.state.view_relish().get("at", ""))
			_apply("raid", result, Game.state.view_dungeon_seed(fort), fort)
		BOSS:
			_apply("boss", result, Game.state.view_boss_seed(), "vei")


## Opens the scene for `id`. `arrive_from` names the scene just left (a town's result opens the
## map arriving from Covington); `from_map` lets the map dive into `id` first.
func _teleport(id: String, arrive_from := "", from_map := false) -> void:
	var s := Game.state
	if id == "covington":
		_swap(TOWN, {"mode": "town"}, id if from_map else "")
	elif id == "vei":
		var r := s.cmd_begin_boss()
		if not r["ok"]:
			_open_map("", RelishLogic.reason_text(str(r["reason"])))
			return
		var args := {"mode": "boss", "run_id": r["run_id"], "seed_rev": r["seed_rev"]}
		_swap(BOSS, args, id if from_map else "")
	elif id != "" and not s.view_fort(id).is_empty():
		var r := s.cmd_begin_dungeon(id)
		if not r["ok"]:
			_open_map("", RelishLogic.reason_text(str(r["reason"])))
			return
		var args := {"mode": "dungeon", "fort_id": id, "run_id": r["run_id"], "seed_rev": r["seed_rev"]}
		_swap(RAID, args, id if from_map else "")
	else:
		_open_map(arrive_from)


## Writes a dungeon or boss result back (converting a v1 one with the open run's seed), then
## goes to the map, arriving from `arrive_from`. A refusal is logged and the run forfeited, so
## none stays open.
func _apply(kind: String, result: Dictionary, seed: Dictionary, arrive_from: String) -> void:
	var s := Game.state
	if RouterLogic.result_stale(kind, s.view_relish()):
		_open_map(arrive_from, RouterLogic.stale_toast())  # the state already ended this run (a gap: run_ended); nothing to write back
		return
	var v2 := result if result.has("v") else Results.from_v1(kind, result, seed)
	var out := s.apply_result(kind, v2)
	if not out["ok"]:
		push_warning("necropolis: %s result refused: %s" % [kind, out["reason"]])
		s.cmd_abort_dungeon()
	_open_map(arrive_from)
