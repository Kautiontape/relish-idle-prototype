class_name TransitionLogic
extends RefCounted
## Pure logic for the router's dive (VISUAL-LANGUAGE 3; no autoloads, so headless tests compile
## it): the phase timeline, the easing, the dive camera's target and the arrival's start state.
## Pulse-derived values (reduced motion) and the --transition-slow factor come in as arguments.
## Tuning: configs/map_view.json "transition".

const IN := "in"    # map -> scene: the camera zooms, then the snapshot fades
const OUT := "out"  # scene -> map: the camera eases out while the snapshot fades


static func cfg() -> Dictionary:
	return MapLogic.cfg().get("transition", {})


## {zoom_s, fade_s, total_s}, all multiplied by `slow` (the debug factor, 1 normally). IN runs the
## zoom, then the fade (a sum); OUT runs both at once (the longer). Reduced motion has no zoom:
## only the reduced_fade_ms crossfade.
static func timeline(c: Dictionary, kind: String, reduced: bool, slow := 1.0) -> Dictionary:
	var k := maxf(slow, 0.0)
	if reduced:
		var f := float(c["reduced_fade_ms"]) * 0.001 * k
		return {"zoom_s": 0.0, "fade_s": f, "total_s": f}
	var fade := float(c["dive_fade_ms"]) * 0.001 * k
	if kind == IN:
		var z := float(c["dive_zoom_ms"]) * 0.001 * k
		return {"zoom_s": z, "fade_s": fade, "total_s": z + fade}
	var az := float(c["arrive_zoom_ms"]) * 0.001 * k
	return {"zoom_s": az, "fade_s": fade, "total_s": maxf(az, fade)}


## The factor for --transition-slow=<k>; 1.0 unless `debug` and a positive number is given.
static func slow_factor(args: Array, debug: bool) -> float:
	if not debug:
		return 1.0
	for a in args:
		var s := str(a)
		if s.begins_with("--transition-slow=") and s.trim_prefix("--transition-slow=").is_valid_float():
			var k := s.trim_prefix("--transition-slow=").to_float()
			if k > 0.0:
				return k
	return 1.0


## In-out ease of t in [0, 1] with the config's power (3 = cubic).
static func ease_t(t: float, power: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	if x < 0.5:
		return 0.5 * pow(2.0 * x, power)
	return 1.0 - 0.5 * pow(2.0 * (1.0 - x), power)


## The progress of a phase `elapsed` s in, of `dur` s (1 for a zero-length phase).
static func progress(elapsed: float, dur: float) -> float:
	return 1.0 if dur <= 0.0 else clampf(elapsed / dur, 0.0, 1.0)


## The dive camera's end state: zoom x dive_zoom_mult, clamped to the map's zoom range, centred
## on the node. {zoom, centre}.
static func dive_target(zoom: float, node_pos: Vector2, c: Dictionary, zoom_min: float, zoom_max: float) -> Dictionary:
	return {"zoom": clampf(zoom * float(c["dive_zoom_mult"]), zoom_min, zoom_max), "centre": node_pos}


## The arrival's start state: the dive's end state, from the default fit.
static func arrive_start(fit_zoom: float, node_pos: Vector2, c: Dictionary, zoom_min: float, zoom_max: float) -> Dictionary:
	return dive_target(fit_zoom, node_pos, c, zoom_min, zoom_max)


## Zoom between two zooms at eased progress `e`, geometric so each frame scales by the same factor.
static func mix_zoom(a: float, b: float, e: float) -> float:
	return a * pow(b / a, e)


## The map HUD's alpha `t` seconds into its fade (the HUD means the top bar, strip, chip, sidebar,
## valve, callouts, toasts, away panel and tithe card). IN (the dive): 1 to 0 over hud_fade_s (x
## `slow`), from the moment the dive starts; reduced motion hides it at once (t = 0). OUT (the
## return): `t` counts from the end of the router's snapshot fade; 0 before it (t < 0), then 0 to 1
## over hud_fade_s; reduced motion shows it at once when the crossfade ends.
static func hud_alpha(c: Dictionary, kind: String, reduced: bool, slow: float, t: float) -> float:
	var dur := float(c["hud_fade_s"]) * maxf(slow, 0.0)
	if kind == IN:
		return 0.0 if reduced else 1.0 - progress(t, dur)
	if t < 0.0:
		return 0.0
	return 1.0 if reduced else progress(t, dur)


## The dive's HUD fade length: hud_fade_s (x `slow`), never longer than the zoom it sits inside.
static func hud_fade_len(c: Dictionary, slow: float, zoom_s: float) -> float:
	return minf(float(c["hud_fade_s"]) * maxf(slow, 0.0), zoom_s)
