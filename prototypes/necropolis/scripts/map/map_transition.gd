class_name MapTransition
extends CanvasLayer
## The router's `Transition` layer: a full-rect input blocker (so a double click cannot start a
## second swap) and the snapshot of the outgoing scene that fades out over the incoming one.
## Durations come from TransitionLogic.timeline; tuning in configs/map_view.json "transition".


var _block: Control
var _shot: TextureRect
var _tween: Tween


func _init() -> void:
	name = "Transition"
	layer = int(TransitionLogic.cfg()["layer"])
	_block = Control.new()
	_block.mouse_filter = Control.MOUSE_FILTER_STOP
	_block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_block)


## The --transition-slow factor (debug only), shared by the router and the map's arrival.
static func slow() -> float:
	return TransitionLogic.slow_factor(OS.get_cmdline_user_args(), Game.state.debug_enabled)


## True when a real framebuffer exists to snapshot: not a headless boot, and not a minimised
## window (frame_post_draw does not fire while minimised, so a swap would wait and pile up events).
static func can_snapshot() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED


## Snapshots the viewport as drawn this frame onto the layer. False (nothing shown) when there is
## no framebuffer or the image is empty.
func snapshot() -> bool:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return false
	_shot = TextureRect.new()
	_shot.texture = ImageTexture.create_from_image(img)
	_shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shot.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_shot)
	return true


## Fades the snapshot out over `seconds`, then frees the layer (the blocker with it).
func fade_out(seconds: float) -> void:
	if _shot != null and seconds > 0.0:
		_tween = create_tween()
		_tween.tween_property(_shot, "modulate:a", 0.0, seconds)
		await _tween.finished
	queue_free()
