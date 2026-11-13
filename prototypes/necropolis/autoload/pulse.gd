extends Node
## Pulse (autoload): the game's one tempo and BRIEF §6's motion language.
## Every scene takes its beat, its wave and the reduced-motion flag from here;
## no scene script carries its own tempo. Tuning: configs/pulse.json.
## Debug: F9 (pulse.json `reduced_motion_key`) or `-- --reduced-motion` on the CLI.
##
## Headless tests run before autoloads exist, so they build one directly:
##   var p = load("res://autoload/pulse.gd").new(); p.configure(json); ...; p.free()

## rate_to_u() for a route that is switched off. Zero rate means dark, never slow.
const OFF := -1.0

## Every scene reads this one flag. Under it phase(), wave() and dash_offset() hold still.
var reduced_motion := false
## Tests pin the clock here (milliseconds). Negative = real time.
var clock_ms := -1.0

# Read-only after configure(): see configs/pulse.json for meaning.
var tempo_ms := 0.0
var map_max_hops := 0.0
var wave_spread := 0.0
var wave_decay := 0.0
var reduced_phase := 0.0
var reduced_wave := 0.0
var rate_off := 0.0
var rate_ref := 0.0

var _cfg := {}
var _toggle_key: Key = KEY_NONE
# channel constants, cached so channels() does no dictionary work per call
var _p0 := 0.0
var _p1 := 0.0
var _v0 := 0.0
var _v1 := 0.0
var _w0 := 0.0
var _w1 := 0.0
var _a0 := 0.0
var _a1 := 0.0
var _hue0 := 0.0
var _hue_ease := 0.0
var _sat := 0.0
var _l0 := 0.0
var _l1 := 0.0
var _hz_min := 0.0
var _hz_max := 0.0
var _duty := 0.0


func _ready() -> void:
	# By path, not the ConfigDb identifier: autoload names don't resolve when the
	# headless test runner compiles this script.
	var db := get_node_or_null("/root/ConfigDb")
	configure((db.get("data") as Dictionary).get("pulse", {}) if db != null else {})
	if "--reduced-motion" in OS.get_cmdline_user_args():
		reduced_motion = true


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == _toggle_key:
		reduced_motion = not reduced_motion
		print("Pulse: reduced motion ", "ON" if reduced_motion else "OFF")


func configure(cfg: Dictionary) -> void:
	_cfg = cfg
	tempo_ms = _num("tempo_ms")
	map_max_hops = _num("map_max_hops")
	wave_spread = _num("wave_spread")
	wave_decay = _num("wave_decay")
	reduced_phase = _num("reduced_phase")
	reduced_wave = _num("reduced_wave")
	rate_off = _num("rate_off")
	rate_ref = _num("rate_ref")
	_p0 = _num("period_base")
	_p1 = _num("period_per_u")
	_v0 = _num("speed_base")
	_v1 = _num("speed_per_u")
	_w0 = _num("width_base")
	_w1 = _num("width_per_u")
	_a0 = _num("alpha_base")
	_a1 = _num("alpha_per_u")
	_hue0 = _num("hue_dormant")
	_hue_ease = _num("hue_ease")
	_sat = _num("hue_saturation")
	_l0 = _num("lightness_base")
	_l1 = _num("lightness_per_u")
	_hz_min = _num("mark_hz_min")
	_hz_max = _num("mark_hz_max")
	_duty = _num("dash_duty")
	reduced_motion = bool(cfg.get("reduced_motion", false))
	_toggle_key = OS.find_keycode_from_string(str(cfg.get("reduced_motion_key", "")))


func now_ms() -> float:
	return clock_ms if clock_ms >= 0.0 else float(Time.get_ticks_msec())


# --- the tempo ---------------------------------------------------------------

## Beat lag, in beats, for something `hops` route-graph steps from the source.
## Angiogram's phase = dCov / maxd (01-angiogram-perfusion:464), with the spread
## normalised to `wave_spread` so the farthest node never lands back in phase.
## `max_hops` <= 0 uses the map's depth (Covington 0, fort 1, Vei 2).
func hop_phase(hops: float, max_hops := -1.0) -> float:
	var depth := max_hops if max_hops > 0.0 else map_max_hops
	if depth <= 0.0:
		return 0.0
	return wave_spread * clampf(hops / depth, 0.0, 1.0)


## 0..1 position in the current beat, lagged by hop distance.
## Reduced motion: a steady `reduced_phase` for every hop.
func phase(hops := 0.0, max_hops := -1.0) -> float:
	if reduced_motion:
		return reduced_phase
	return fposmod(now_ms() / tempo_ms - hop_phase(hops, max_hops), 1.0)


## Pulse intensity: 1 on the beat, decaying to exp(-wave_decay) (angiogram's
## exp(-b·3.2)). Read per node with its hop count, it is a wave crossing the realm.
## Reduced motion: a steady `reduced_wave` (> 0, so pulsed things stay visible).
func wave(hops := 0.0, max_hops := -1.0) -> float:
	if reduced_motion:
		return reduced_wave
	return exp(-phase(hops, max_hops) * wave_decay)


## Dash offset in px for a lane moving at `speed` px/s with dash `period`.
## Walk dashes from -period + offset. Reduced motion: 0 (dashes hold still).
func dash_offset(speed: float, period: float) -> float:
	if reduced_motion or period <= 0.0:
		return 0.0
	return fposmod(now_ms() * 0.001 * speed, period)


# --- the five channels -------------------------------------------------------

## BRIEF §6 log normalisation: u = log(1+rate) / log(1+ref), clamped 0..1.
## Below `rate_off` (and at zero) the route is OFF: returns Pulse.OFF.
## `ref` <= 0 uses the config's `rate_ref`.
func rate_to_u(rate: float, ref := -1.0) -> float:
	if rate <= 0.0 or rate < rate_off:
		return OFF
	var r := ref if ref > 0.0 else rate_ref
	return clampf(log(1.0 + rate) / log(1.0 + r), 0.0, 1.0)


## All five §6 channels from one u, for a flow whose own hue is `flow_hue` degrees
## (use Palette.hue("undead") / Palette.hue("living")). Keys:
##   off, u, period, dash, speed, hz, width, alpha, hue, color (alpha applied)
## u < 0 (Pulse.OFF) returns off = true with zero width and alpha: draw nothing.
## Deviations from BRIEF's literal text, decided by the manager (audit Q7, Q8):
##  - hue eases from dormant violet 272 to the flow's own hue along the shorter
##    arc (06-three-flow-geometry:507, :532-537), so green and orange survive;
##  - speed is clamped so marks pass at mark_hz_min..max (0.80-7.00 Hz,
##    06:402-410, :520-528). Below u ~ 0.35 the floor lifts speed above 14+140u.
## Dead flows use the motion channels and ignore `color` (Palette "dead", matte).
func channels(u: float, flow_hue: float) -> Dictionary:
	if u < 0.0:
		return {
			"off": true, "u": OFF, "period": _p0, "dash": 0.0, "speed": 0.0, "hz": 0.0,
			"width": 0.0, "alpha": 0.0, "hue": _hue0, "color": Color(0, 0, 0, 0),
		}
	u = minf(u, 1.0)
	var period := _p0 + _p1 * u
	var speed := _v0 + _v1 * u
	var hz := speed / period
	if hz < _hz_min or hz > _hz_max:
		hz = clampf(hz, _hz_min, _hz_max)
		speed = hz * period
	var alpha := _a0 + _a1 * u
	var ease := 1.0 - pow(1.0 - u, _hue_ease)
	var hue := fposmod(_hue0 + wrapf(flow_hue - _hue0, -180.0, 180.0) * ease, 360.0)
	var col := _hsl(hue, _sat, _l0 + _l1 * u)
	col.a = alpha
	return {
		"off": false, "u": u, "period": period, "dash": period * _duty, "speed": speed,
		"hz": hz, "width": _w0 + _w1 * u, "alpha": alpha, "hue": hue, "color": col,
	}


# --- helpers -----------------------------------------------------------------

func _num(key: String) -> float:
	if not _cfg.has(key):
		push_error("Pulse: configs/pulse.json is missing '%s'" % key)
		return 0.0
	return float(_cfg[key])


## HSL -> RGB, ported from 06-three-flow-geometry's hsl2rgb (Godot has HSV and
## OKHSL built in, not plain HSL).
static func _hsl(h_deg: float, s: float, l: float) -> Color:
	var h := fposmod(h_deg, 360.0) / 360.0
	if s <= 0.0:
		return Color(l, l, l)
	var q := l * (1.0 + s) if l < 0.5 else l + s - l * s
	var p := 2.0 * l - q
	return Color(_hue2(p, q, h + 1.0 / 3.0), _hue2(p, q, h), _hue2(p, q, h - 1.0 / 3.0))


static func _hue2(p: float, q: float, t: float) -> float:
	if t < 0.0:
		t += 1.0
	if t > 1.0:
		t -= 1.0
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * (2.0 / 3.0 - t) * 6.0
	return p
