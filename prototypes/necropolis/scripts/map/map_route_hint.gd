class_name MapRouteHint
extends MapNodeLayer
## Relish's routes, drawn under the nodes. While a fort or Vei card is open and she is neither
## there nor on her way: her would-be route, a dashed violet line from where she is drawn to the
## node, with the ETA (distance / travel_speed) at its midpoint. While she travels: the remaining
## route to her target, a solid violet hairline that shrinks as she walks, with her ETA at the
## target. Both are static (no phase), so reduced motion needs nothing. Rules: relish_logic.gd.
## It shares MapNodes' context (her drawn position, the zoom, the selection) and its text helper.

var _speed := -1.0  # realm.relish.travel_speed, px/s
var _last_pos := Vector2.INF
var _last_sel := "?"
var _last_zoom := -1.0
var _last_rev := -2


func _process(_delta: float) -> void:
	if ctx == null or ctx.model == null or ctx.model.realm.is_empty():
		return
	var rev := ctx.model.rev
	if ctx.relish_pos != _last_pos or ctx.selected_id != _last_sel or ctx.zoom != _last_zoom or rev != _last_rev:
		_last_pos = ctx.relish_pos
		_last_sel = ctx.selected_id
		_last_zoom = ctx.zoom
		_last_rev = rev
		queue_redraw()


func _travel_speed() -> float:
	if _speed < 0.0:
		_speed = float(ConfigDb.data.get("realm", {}).get("relish", {}).get("travel_speed", 0.0))
	return _speed


func _is_dest(id: String) -> bool:
	return id == MapModel.VEI or ctx.model.forts_by_id.has(id)


func _draw_static() -> void:
	var rel := ctx.model.relish
	if rel.is_empty():
		return
	var sel := ctx.selected_id
	var st := RelishLogic.route_state(rel, sel, _is_dest(sel))
	if st["travel"]:
		_travel_route(rel)
	if st["preview"]:
		_preview_route(rel, sel)


func _preview_route(rel: Dictionary, id: String) -> void:
	var c: Dictionary = MapLogic.cfg()["controls"]
	var to := ctx.model.node_pos(id)
	var from := ctx.relish_pos
	var col := Palette.c("relish")
	var w := maxf(ctx.px(float(c["route_width_px"])), ctx.hair_w())
	for seg in RelishLogic.dash_segments(from, to, ctx.px(float(c["route_dash_px"])), ctx.px(float(c["route_gap_px"]))):
		for l in NodeLogic.capped_layers(col, w, float(c["route_glow"]), ctx.px(float(c["route_halo_max_px"]))):
			draw_polyline(PackedVector2Array([seg[0], seg[1]]), l[1], l[0])
	var eta := RelishLogic.eta_s(MapModel.to_vec(rel["pos"]).distance_to(to), _travel_speed())
	text((from + to) * 0.5, RelishLogic.fmt_eta(eta), int(c["route_label_px"]), col, ALIGN_CENTER, float(c["route_label_px"]) * 0.5)


func _travel_route(rel: Dictionary) -> void:
	var c: Dictionary = MapLogic.cfg()["controls"]
	var tid := str(rel.get("target", ""))
	if not ctx.model.has_node(tid):
		return
	var to := ctx.model.node_pos(tid)
	var col := Palette.c("relish")
	LineGlow.polyline(self, PackedVector2Array([ctx.relish_pos, to]), col, maxf(ctx.px(float(c["route_travel_width_px"])), ctx.hair_w()), 0.0)
	text(to - Vector2(0.0, ctx.px(float(c["route_label_up_px"]))), RelishLogic.fmt_eta(float(rel.get("eta_s", 0.0))),
		int(c["route_label_px"]), col, ALIGN_CENTER, 0.0)
