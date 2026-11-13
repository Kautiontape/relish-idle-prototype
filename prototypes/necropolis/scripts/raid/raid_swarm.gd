class_name RaidSwarm
extends Node2D
## The swarm badge: when `swarm.min_count` or more allied undead cluster together, a small
## integer count in `undead_core` text sits at the cluster's centroid with a faint loose
## ring round the formation. Allies are bucketed on a coarse grid (`cell_px`), adjacent
## buckets merge, and the clusters refresh a few times a second (`refresh_s`), never per
## frame; `_draw` only walks the cached clusters.

var raid: Node = null
var _min := 12
var _cell := 160.0
var _refresh := 0.25
var _font := 16
var _pad := 36.0
var _ring_a := 0.2
var _ring_w := 1.5
var _max := 8
var _t := 0.0
# cached clusters, parallel arrays: centroid, ring radius, count
var _cent: Array[Vector2] = []
var _rad: Array[float] = []
var _cnt: Array[int] = []
var _txt: Array[String] = []      # cached badge strings and sizes (set at refresh, not in _draw)
var _box: Array[Rect2] = []       # badge backing rect, local to the centroid
var _tpos: Array[Vector2] = []    # text baseline origin, local to the centroid
var _fs := 16                     # badge font size in world px (font_px / camera zoom)
var _buckets := {}   # Vector2i -> [count, sum_x, sum_y, min_x, min_y, max_x, max_y, label]


func configure(p_raid: Node) -> void:
	raid = p_raid
	var c: Dictionary = ConfigDb.data.get("raid", {}).get("swarm", {})
	_min = int(c.get("min_count", 12))
	_cell = float(c.get("cell_px", 160.0))
	_refresh = float(c.get("refresh_s", 0.25))
	_font = int(c.get("font_px", 16))
	_pad = float(c.get("ring_pad_px", 36.0))
	_ring_a = float(c.get("ring_alpha", 0.2))
	_ring_w = float(c.get("ring_width", 1.5))
	_max = int(c.get("max_clusters", 8))
	z_index = 33   # over the units, under the trance dim


func _process(delta: float) -> void:
	_t += delta / maxf(0.05, Engine.time_scale)
	if _t < _refresh:
		return
	_t = 0.0
	_recluster()
	queue_redraw()


## Cluster the live allies: grid buckets, then an 8-neighbour flood merge of every occupied
## bucket, so a thin or cell-straddling swarm is one cluster and its count is its true size.
func _recluster() -> void:
	_cent.clear()
	_rad.clear()
	_cnt.clear()
	_txt.clear()
	_box.clear()
	_tpos.clear()
	if raid == null:
		return
	_buckets.clear()
	for a in raid.allies:
		if not is_instance_valid(a) or not a.alive:
			continue
		var p: Vector2 = a.position
		var k := Vector2i(int(floorf(p.x / _cell)), int(floorf(p.y / _cell)))
		var b = _buckets.get(k)
		if b == null:
			_buckets[k] = [1, p.x, p.y]
		else:
			b[0] += 1
			b[1] += p.x
			b[2] += p.y
	if _buckets.is_empty():
		return
	var zoom := maxf(0.05, get_viewport().get_canvas_transform().get_scale().x)
	_fs = maxi(8, roundi(float(_font) / zoom))   # about font_px on screen at any zoom
	var pad := 5.0 / zoom
	var font := ThemeDB.fallback_font
	var seen := {}
	for k in _buckets:
		if seen.has(k):
			continue
		var stack: Array = [k]
		seen[k] = true
		var n := 0
		var sx := 0.0
		var sy := 0.0
		var minx := INF
		var miny := INF
		var maxx := -INF
		var maxy := -INF
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			var b: Array = _buckets[c]
			n += int(b[0])
			sx += float(b[1])
			sy += float(b[2])
			minx = minf(minx, float(b[1]) / b[0])
			maxx = maxf(maxx, float(b[1]) / b[0])
			miny = minf(miny, float(b[2]) / b[0])
			maxy = maxf(maxy, float(b[2]) / b[0])
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nk := Vector2i(c.x + dx, c.y + dy)
					if not seen.has(nk) and _buckets.has(nk):
						seen[nk] = true
						stack.append(nk)
		if n >= _min and _cnt.size() < _max:
			_cent.append(Vector2(sx / n, sy / n))
			_rad.append(maxf(_cell * 0.5, 0.5 * Vector2(maxx - minx, maxy - miny).length()) + _pad)
			_cnt.append(n)
			var txt := str(n)
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, _fs).x
			_txt.append(txt)
			_tpos.append(Vector2(-tw * 0.5, 0.0))
			_box.append(Rect2(Vector2(-tw * 0.5 - pad, -_fs), Vector2(tw + pad * 2.0, _fs + pad)))


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var ring := Palette.c("undead", _ring_a)
	var back := Palette.c("ground", 0.8)
	var ink := Palette.c("undead_core")
	for i in _cnt.size():
		var c := _cent[i]
		draw_arc(c, _rad[i], 0.0, TAU, 48, ring, _ring_w)
		draw_rect(Rect2(c + _box[i].position, _box[i].size), back)
		draw_string(font, c + _tpos[i], _txt[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, ink)
