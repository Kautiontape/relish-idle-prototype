class_name GroundMoat
extends RefCounted
## The flow ground's lane moat (api-request #1): where the streaks thin out so the routes read
## over the ground. Pure (names no autoload, so headless tests compile it); flow_ground.gd feeds
## it the view_lanes rows and node positions and uploads the result to the particle shader.
##
## Geometry is map's own: MapLogic.lane_curve_for for a lane, MapLogic.gutter_curve for a dead
## row's shadow gutter, whole and untrimmed (the shader's moat_end keeps it off the nodes). The
## width is the drawn lane's outer edge, not the core's: the core times LaneStyle's width_mult
## (commit_width_mult from Covington, flood_hot_mult on the direct FLOOD), or its outermost halo,
## capped at halo_max_px, whichever LaneStyle.lit_layers draws widest.


## One quadratic bow per lane the routes draw, as {a, c, b, half_width, u, kind}: start, control
## and end in world px, the drawn half width in world px, Pulse's u, and the row's kind.
##   rows   view_lanes().lanes (or map's demo lanes), the STATE-API 5.3 row shape
##   pos    node id -> world position
##   u_of   rate -> Pulse u (Pulse.rate_to_u at map_view's rate_log_max); < 0 = off
##   cache  optional, kept by the caller between calls: a lane whose u (and, for a gutter, its
##          host's u) moved no more than map_view's u_epsilon since it was built is reused, the
##          same rule the routes use to skip a restyle. Positions must not change under a cache.
## Left out: off rows (map hides them), self-loops (WORK and REDIRECT rings sit inside moat_end
## of their node, where the moat is off anyway) and rows naming a node `pos` lacks.
static func lanes(rows: Array, pos: Dictionary, u_of: Callable, cache := {}) -> Array:
	var eps := float(MapLogic.cfg().get("u_epsilon", 0.0))
	var u_by_id := {}
	for r in rows:
		u_by_id[str(r["id"])] = float(u_of.call(float(r["rate"])))
	var out: Array = []
	for r in rows:
		var id := str(r["id"])
		var from := str(r["from"])
		var to := str(r["to"])
		var u: float = u_by_id[id]
		if u < 0.0 or from == to or not pos.has(from) or not pos.has(to):
			continue
		var dead := str(r["kind"]) == "dead"
		var u_host: float = u_by_id.get(LaneStyle.host_id(r), LaneStyle.OFF) if dead else 0.0
		var hit: Dictionary = cache.get(id, {})
		if not hit.is_empty() and absf(hit["u"] - u) <= eps and absf(hit["u_host"] - u_host) <= eps:
			out.append(hit["lane"])
			continue
		var curve: Dictionary
		var half: float
		if dead:
			curve = MapLogic.gutter_curve(pos[from], pos[to], u_host, u)
			half = gutter_half_width(u)
		else:
			curve = MapLogic.lane_curve_for(r, pos[from], pos[to], u)
			half = drawn_half_width(r, curve["half_width"])
		var lane := {"a": curve["a"], "c": curve["c"], "b": curve["b"], "half_width": half, "u": u,
			"kind": str(r["kind"])}
		cache[id] = {"u": u, "u_host": u_host, "lane": lane}
		out.append(lane)
	return out


## Half the widest stroke map draws for a lit lane whose core half width is `core_half`.
static func drawn_half_width(row: Dictionary, core_half: float) -> float:
	var style := LaneStyle.style_for(row)
	var ch := {"color": Palette.c(str(style["hue_key"])), "alpha": 1.0, "width": core_half * 2.0}
	var widest := 0.0
	for l in LaneStyle.lit_layers(ch, style):
		widest = maxf(widest, float(l["width"]))
	return widest * 0.5


## Half a shadow gutter's drawn width at dead intensity `u`: the cut plus its spill.
static func gutter_half_width(u: float) -> float:
	var spill := float(MapLogic.cfg().get("gutter", {}).get("spill_px", 0.0))
	return (MapLogic.gutter_width(u) + spill) * 0.5
