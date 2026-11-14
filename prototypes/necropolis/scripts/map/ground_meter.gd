extends CanvasLayer
## Frame-time readout in milliseconds (not FPS) plus a CLI bench for the
## ground spike. Owned by map_field_view.gd.
##
## Readout: wall-clock frame time (mean / p95 / max over the last 240 frames),
## main and trail viewport CPU/GPU render time from
## RenderingServer.viewport_get_measured_render_time_*, and the GDScript time
## the ground spent this frame. With vsync on or an fps cap, frame time pins
## to the refresh interval; press F5 (or pass --vsync=off, which also lifts any
## --max-fps cap) to see the real cost. The GPU
## particle pass is not attributed to either viewport's GPU timer, so the
## vsync-off wall-clock frame time is the honest total.
##
## Bench (CLI, args after `--`):
##   --bench-seconds=S     measure each mode for S wall seconds
##   --bench-modes=a,b,c   modes to measure back to back (default flow,old,off);
##                         a mode may add +reduced, +grey and/or +bare (routes and
##                         nodes hidden, for contrast captures), e.g. flow+reduced
##   --bench-warm=N        frames to wait first (e.g. at --speed=60 to reach late game)
##   --bench-speed=X       sim speed to switch to after warm-up (default 1; 0 < X <= 100)
##   --bench-shot=/abs/prefix  save <prefix>-<mode>.png at the end of each mode
## Prints one "BENCH ..." line per mode, then quits.

var view: Node            # map_field_view.gd
var label: Label
var _hist := PackedFloat32Array()
var _hi := 0
var _last_us := 0
var _acc := 0.0

var _bench := {}
var _bstate := "off"
var _bmodes: Array = []
var _bframes := 0
var _bt0 := 0
var _bsamples := {}
var _warm_t0 := -1.0  # sim clock (view_hud t) when the warm-up began
var _bare := false


func _ready() -> void:
	layer = 5
	_hist.resize(240)
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.c("ground", 0.86)
	sb.border_color = Palette.c("ring_track")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	plate.add_theme_stylebox_override("panel", sb)
	plate.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	plate.offset_right = -12.0
	plate.offset_top = 8.0
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Palette.c("text"))
	plate.add_child(label)
	add_child(plate)
	var root_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(root_rid, true)
	_parse_bench()


func _parse_bench() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2 and kv[0].begins_with("--bench"):
			_bench[kv[0].trim_prefix("--")] = kv[1]
	if _bench.has("bench-seconds"):
		_bmodes = str(_bench.get("bench-modes", "flow,old,off")).split(",")
		_bstate = "warm"
		_bframes = int(_bench.get("bench-warm", "120"))


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := 0.0 if _last_us == 0 else (now - _last_us) / 1000.0
	_last_us = now
	if ms > 0.0:
		_hist[_hi] = ms
		_hi = (_hi + 1) % _hist.size()
	_run_bench(ms)
	_acc += delta
	if _acc < 0.25 or not visible:
		return
	_acc = 0.0
	var s := _stats(_hist)
	var main_rid := get_viewport().get_viewport_rid()
	var lines := PackedStringArray()
	lines.append("GROUND %s%s · %s" % [view.mode, "  [reduced motion]" if Pulse.reduced_motion else "", view.detail()])
	var cap := ""
	if Engine.max_fps > 0:
		cap = "  fps cap %d" % Engine.max_fps
	lines.append("frame %.2f ms  p95 %.2f  max %.2f   vsync %s%s" % [s["mean"], s["p95"], s["max"],
		"ON" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "OFF", cap])
	lines.append("main  cpu %.2f  gpu %.2f ms" % [
		RenderingServer.viewport_get_measured_render_time_cpu(main_rid),
		RenderingServer.viewport_get_measured_render_time_gpu(main_rid)])
	var trid: RID = view.trail_rid()
	if trid.is_valid():
		var hrid: RID = view.history_rid()
		lines.append("trail cpu %.2f  gpu %.2f ms · history gpu %.2f ms" % [
			RenderingServer.viewport_get_measured_render_time_cpu(trid),
			RenderingServer.viewport_get_measured_render_time_gpu(trid),
			RenderingServer.viewport_get_measured_render_time_gpu(hrid)])
	lines.append("ground cpu %.2f ms this frame" % view.cpu_ms())
	lines.append("F5 vsync · F6 reload cfg · F7 ground · F8 reduced (Pulse) · F9 grey")
	label.text = "\n".join(lines)


func _stats(arr: PackedFloat32Array) -> Dictionary:
	var v := Array(arr).filter(func(x): return x > 0.0)
	if v.is_empty():
		return {"mean": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "p999": 0.0, "max": 0.0, "over4": 0, "n": 0}
	v.sort()
	var sum := 0.0
	for x in v:
		sum += x
	var n := v.size()
	return {"mean": sum / n, "p50": v[int(0.5 * (n - 1))], "p95": v[int(0.95 * (n - 1))],
		"p99": v[int(0.99 * (n - 1))], "p999": v[int(0.999 * (n - 1))], "max": v[n - 1],
		"over4": v.filter(func(x): return x > 4.0).size(), "n": n}


func _run_bench(ms: float) -> void:
	match _bstate:
		"warm":
			_bframes -= 1
			var t_now := float(Game.state.view_hud()["t"])
			if _warm_t0 < 0.0:
				_warm_t0 = t_now
			if _bframes <= 0:
				var sim_s := t_now - _warm_t0
				var vei := Game.state.view_vei()
				print("BENCH_WARM frames=%s sim_s=%.0f (%.2f sim-hours) odds=%.2f backlog=%.0f" % [
					_bench.get("bench-warm", "120"), sim_s, sim_s / 3600.0, vei["odds"], vei["backlog"]])
				var sent := Game.state.cmd_debug_set_state({"time_scale": float(_bench.get("bench-speed", "1"))})
				if not sent["ok"]:
					push_warning("bench-speed refused: %s" % sent["reason"])
				_next_mode()
		"settle":
			_bframes -= 1
			if _bframes <= 0:
				_bstate = "measure"
				_bt0 = Time.get_ticks_msec()
				_bsamples = {"frame": [], "mcpu": [], "mgpu": [], "tcpu": [], "tgpu": [], "gcpu": []}
		"measure":
			var main_rid := get_viewport().get_viewport_rid()
			_bsamples["frame"].append(ms)
			_bsamples["mcpu"].append(RenderingServer.viewport_get_measured_render_time_cpu(main_rid))
			_bsamples["mgpu"].append(RenderingServer.viewport_get_measured_render_time_gpu(main_rid))
			_bsamples["gcpu"].append(view.cpu_ms())
			var trid: RID = view.trail_rid()
			if trid.is_valid():
				_bsamples["tcpu"].append(RenderingServer.viewport_get_measured_render_time_cpu(trid))
				_bsamples["tgpu"].append(RenderingServer.viewport_get_measured_render_time_gpu(trid)
					+ RenderingServer.viewport_get_measured_render_time_gpu(view.history_rid()))
			if Time.get_ticks_msec() - _bt0 >= int(float(_bench["bench-seconds"]) * 1000.0):
				_report()
				if _bench.has("bench-shot"):
					var p := "%s-%s%s%s%s.png" % [_bench["bench-shot"], view.mode, "-reduced" if Pulse.reduced_motion else "",
					"-grey" if view.is_grey() else "", "-bare" if _bare else ""]
					get_viewport().get_texture().get_image().save_png(p)
					print("BENCH_SHOT ", p)
				_next_mode()


func _next_mode() -> void:
	if _bmodes.is_empty():
		_bstate = "done"
		print("BENCH_DONE")
		get_tree().quit()
		return
	# a mode token is "<flow|old|off>[+reduced][+grey][+bare]" (bare: no routes or nodes)
	var parts := str(_bmodes.pop_front()).split("+")
	Pulse.reduced_motion = parts.has("reduced")   # the game-wide flag; the view follows
	view.set_grey(parts.has("grey"))
	view.set_bare(parts.has("bare"))
	_bare = parts.has("bare")
	view.set_mode(parts[0])
	_bstate = "settle"
	_bframes = 90


func _report() -> void:
	var f := _stats(PackedFloat32Array(_bsamples["frame"]))
	var mean := func(key: String) -> float:
		var a: Array = _bsamples[key]
		if a.is_empty():
			return 0.0
		var s := 0.0
		for x in a:
			s += x
		return s / a.size()
	var vs := get_viewport().get_visible_rect().size
	var gc: Array = _bsamples["gcpu"]
	print("BENCH mode=%s%s%s%s n=%d frame_ms mean=%.3f p50=%.3f p95=%.3f p99=%.3f p99.9=%.3f max=%.3f over4ms=%d | main cpu=%.3f gpu=%.3f | trail cpu=%.3f gpu(+history)=%.3f | ground_cpu_ms mean=%.3f max=%.3f | %s | viewport=%dx%d window=%s vsync=%s sim_speed=%s" % [
		view.mode, "+reduced" if Pulse.reduced_motion else "", "+grey" if view.is_grey() else "",
		"+bare" if _bare else "", f["n"],
		f["mean"], f["p50"], f["p95"], f["p99"], f["p999"], f["max"], f["over4"],
		mean.call("mcpu"), mean.call("mgpu"), mean.call("tcpu"), mean.call("tgpu"),
		mean.call("gcpu"), gc.max() if not gc.is_empty() else 0.0, view.detail(), int(vs.x), int(vs.y), str(DisplayServer.window_get_size()),
		"off" if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED else "on",
		str(Game.state.view_hud()["time_scale"])])
