extends RefCounted
## The flow ground's lane moat (GroundMoat, api-request #1): it sits on map's own lane curves at
## the drawn lane's width, for every lane the routes draw and only those.

const PULSE := preload("res://autoload/pulse.gd")


func _row(kind: String, from: String, to: String, rate: float) -> Dictionary:
	return {"id": "%s:%s:%s" % [kind, from, to], "from": from, "to": to, "kind": kind,
		"rate": rate, "bias": 1.0, "why": ""}


func _same(a: Dictionary, b: Dictionary) -> bool:
	return a["a"].is_equal_approx(b["a"]) and a["c"].is_equal_approx(b["c"]) and a["b"].is_equal_approx(b["b"])


func run() -> int:
	var t := TestUtil.new()
	t.suite("ground_moat")
	Palette.configure(TestUtil.load_json("res://configs/palette.json"))
	LineGlow.configure(TestUtil.load_json("res://configs/line_glow.json"))
	var view := TestUtil.load_json("res://configs/map_view.json")
	MapLogic.configure(view)
	var pulse: Node = PULSE.new()
	pulse.configure(TestUtil.load_json("res://configs/pulse.json"))
	var log_max := float(view["rate_log_max"])
	var u_of := func(rate: float) -> float: return pulse.rate_to_u(rate, log_max)

	var pos := {"covington": Vector2(1780, 1270), "vei": Vector2(1024, 130),
		"fa": Vector2(400, 400), "fb": Vector2(1600, 300)}
	var war := _row("war", "covington", "fa", 5.0)
	var direct := _row("flood", "covington", "vei", 3.0)
	var drain := _row("flood", "fa", "vei", 2.0)
	var dead := _row("dead", "fa", "vei", 1.0)
	var rows := [war, direct, drain, dead,
		_row("living", "vei", "fb", 0.0),          # off
		_row("work", "covington", "covington", 4.0),  # self-loop ring
		_row("redirect", "fb", "fb", 2.0),         # self-loop ring
		_row("war", "covington", "ghost", 3.0)]    # a node the positions lack
	var ls := GroundMoat.lanes(rows, pos, u_of)
	t.ok(ls.size() == 4, "moats the 4 drawn lanes; drops off rows, self-loops and unknown nodes (%d)" % ls.size())
	if ls.size() != 4:
		pulse.free()
		return t.failures
	var by := {"war": ls[0], "direct": ls[1], "drain": ls[2], "dead": ls[3]}

	# geometry: map's own curves, whole
	var u_war: float = u_of.call(5.0)
	t.ok(_same(by["war"], MapLogic.lane_curve_for(war, pos["covington"], pos["fa"], u_war)),
		"a WAR lane's moat is MapLogic.lane_curve_for's curve")
	t.ok(not _same(by["war"], MapLogic.lane_curve(pos["covington"], pos["fa"], u_war, 0.07)),
		"not the ground's old private bow (0.07)")
	var u_direct: float = u_of.call(3.0)
	t.ok(_same(by["direct"], MapLogic.lane_curve(pos["covington"], pos["vei"], u_direct, float(view["flood_direct_bow"]))),
		"the direct Covington -> Vei FLOOD bows by flood_direct_bow")
	t.ok(not _same(by["direct"], MapLogic.lane_curve(pos["covington"], pos["vei"], u_direct)),
		"... not by lane_bow")
	var u_drain: float = u_of.call(2.0)
	var u_dead: float = u_of.call(1.0)
	t.ok(_same(by["dead"], MapLogic.gutter_curve(pos["fa"], pos["vei"], u_drain, u_dead)),
		"a DEAD row's moat is its shadow gutter, beside the host FLOOD lane (gutter_curve)")
	t.ok(is_equal_approx(by["war"]["u"], u_war) and is_equal_approx(by["dead"]["u"], u_dead), "u passes through")

	# width: the drawn lane's outer edge, not the core's
	var halo_half := float(view["halo_max_px"]) * 0.5
	var core_war := MapLogic.lane_half_width(u_war)
	var hw_war: float = by["war"]["half_width"]
	t.ok(hw_war >= core_war * float(view["commit_width_mult"]) - 1e-4,
		"a committed lane's moat clears its core x commit_width_mult (%.2f >= %.2f)" % [hw_war, core_war * float(view["commit_width_mult"])])
	t.ok(hw_war > core_war * float(view["commit_width_mult"]) + 0.5 and hw_war <= halo_half + 1e-4,
		"... and its halo, capped at halo_max_px / 2 (%.2f <= %.2f)" % [hw_war, halo_half])
	var core_direct := MapLogic.lane_half_width(u_direct)
	t.ok(float(by["direct"]["half_width"]) >= core_direct * float(view["commit_width_mult"]) * float(view["flood_hot_mult"]) - 1e-4,
		"the direct FLOOD's moat clears its hot core (commit x flood_hot_mult)")
	t.ok(is_equal_approx(by["dead"]["half_width"], (MapLogic.gutter_width(u_dead) + float(view["gutter"]["spill_px"])) * 0.5),
		"a gutter's moat is the cut plus its spill")
	# a wide core: the cap never cuts into the core
	var fat := GroundMoat.drawn_half_width(war, halo_half * 2.0)
	t.ok(fat >= halo_half * 2.0 * float(view["commit_width_mult"]) - 1e-4, "a core wider than the halo cap keeps its own width")

	# nothing left of the old stand-in
	var src := FileAccess.get_file_as_string("res://scripts/map/flow_ground.gd")
	t.ok(not src.contains("directShare") and not src.contains("RealmSim"), "flow_ground.gd reads no realm internals")
	t.ok(not TestUtil.load_json("res://configs/ground.json").has("lane_bow"), "ground.json has no private lane bow")

	# the cache: a lane is rebuilt only when its u moves past map's u_epsilon (the routes' rule)
	var eps := float(view["u_epsilon"])
	var raw_u := func(rate: float) -> float: return rate
	var cache := {}
	var l0: Dictionary = GroundMoat.lanes([_row("war", "covington", "fa", 0.5)], pos, raw_u, cache)[0]
	var l1: Dictionary = GroundMoat.lanes([_row("war", "covington", "fa", 0.5 + eps * 0.5)], pos, raw_u, cache)[0]
	var l2: Dictionary = GroundMoat.lanes([_row("war", "covington", "fa", 0.5 + eps * 3.0)], pos, raw_u, cache)[0]
	t.ok(is_same(l0, l1), "a u change within u_epsilon reuses the cached lane")
	t.ok(not is_same(l1, l2) and is_equal_approx(l2["u"], 0.5 + eps * 3.0), "a change past it rebuilds the lane")
	var uncached: Dictionary = GroundMoat.lanes([_row("war", "covington", "fa", 0.5 + eps * 3.0)], pos, raw_u)[0]
	t.ok(_same(l2, uncached) and is_equal_approx(l2["half_width"], uncached["half_width"]), "a rebuilt lane equals an uncached one")
	pulse.free()
	return t.failures
