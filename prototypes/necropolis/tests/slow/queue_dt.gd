extends RefCounted
## The build queue's start delay at long steps (MECHANICS §4.4; E2b-2 T3.2; tests/run.sh --slow
## --only=queue_dt): 12 h of midgame_2flips with a full queue of 8 (the house's, the well's, the pit's,
## the market's and the mill's next level, an inn, a graveyard and stables), core steps with the field
## frozen (tests/slow/convergence.gd's harness), at 0.5 s and at 10 s. The queue starts entries at step
## boundaries, so a start is up to one step late at a long step, and an entry that waited on funds starts
## later still when the long step's gold runs behind. Prints every start at both steps, the max and mean
## delay, and the end-of-run gold, bone and levels; gates only that both runs start the same entries in
## the same order and end with the same levels. T3.3b re-measures with a build-start clip.
##
## Measured at T3.2 (load about 8 on 12 cores, no time asserted): the five entries affordable at once start
## 9.5 s late (one step); the pit's and the market's level 2, which waited on gold, 223.5 s late each (mean
## 70.6 s over the 7 starts): the 10 s run's gold runs 2.2 behind from the first constructions on (they end
## on step boundaries, so the builders keep the stalls short a little longer) and the town saves about
## 0.01 gold/s, so 2.2 gold takes about 220 s. End: gold 9 261 against 9 330 (−0.74%), bone 29.2 against
## 28.5, the same levels; the mill's level 2 waits on bone in both. With no queue the gold paths match.

const HOURS := 12.0
const QUEUE := [["", "lot-05"], ["", "lot-06"], ["inn", "lot-13"], ["graveyard", "lot-14"], ["stables", "lot-15"],
	["", "lot-02"], ["", "lot-04"], ["", "lot-07"]]

var t := TestUtil.new()


func run() -> int:
	t.suite("queue_dt")
	var c = load("res://tests/slow/convergence.gd").new()
	c.t = t
	var js: String = c.start_json("midgame_2flips")
	var res := {}
	for dt in [0.5, 10.0]:
		res[dt] = _run(c, js, dt)
	var a: Array = res[0.5]["starts"]
	var b: Array = res[10.0]["starts"]
	var same := a.size() == b.size()
	var mx := 0.0
	var sum := 0.0
	for i in mini(a.size(), b.size()):
		same = same and a[i][0] == b[i][0] and a[i][1] == b[i][1] and a[i][2] == b[i][2]
		var d := float(b[i][3]) - float(a[i][3])
		print("  [queue_dt] %s@%s level %d: %.1f s at 0.5 s, %.1f s at 10 s, %+.1f s" % [a[i][0], a[i][1], a[i][2], a[i][3], b[i][3], d])
		mx = maxf(mx, absf(d))
		sum += d
	var n := maxi(1, mini(a.size(), b.size()))
	print("  [queue_dt] %d starts; delay at 10 s: max %.2f s, mean %.2f s" % [a.size(), mx, sum / n])
	print("  [queue_dt] end gold %.3f at 0.5 s, %.3f at 10 s (%+.3f%%); bone %.3f, %.3f" % [res[0.5]["gold"], res[10.0]["gold"],
		100.0 * (float(res[10.0]["gold"]) - float(res[0.5]["gold"])) / maxf(1.0, float(res[0.5]["gold"])), res[0.5]["bone"], res[10.0]["bone"]])
	t.ok(same and a.size() >= 5, "both steps start the same %d entries in the same order" % a.size())
	t.ok(res[0.5]["levels"] == res[10.0]["levels"], "and end with the same levels: %s" % str(res[10.0]["levels"]))
	return t.failures


## One run at core steps of `dt`: {starts: [[building_id, lot_id, level, s from the start]], gold, bone,
## levels: {lot_id: "building level"}}.
func _run(c, js: String, dt: float) -> Dictionary:
	var s: GameState = c.load_state(js)
	for q in QUEUE:
		t.ok(s.cmd_queue_build(q[0], q[1])["ok"], "dt %.1f: %s on %s queued" % [dt, q[0] if q[0] != "" else "upgrade", q[1]])
	s.drain_events()
	var starts: Array = []
	var t0 := s.t
	for i in int(HOURS * 3600.0 / dt):
		s._core_step(dt)
		for e in s.drain_events():
			if e["type"] == "queue_started":
				starts.append([e["building_id"], e["lot_id"], int(e["level"]), float(e["t"]) - t0])
	var levels := {}
	for lot in s.town_sim.buildings:
		var bl: Dictionary = s.town_sim.buildings[lot]
		levels[lot] = "%s %d" % [bl["building_id"], int(bl["level"])]
	return {"starts": starts, "gold": s.town_sim.gold, "bone": s.town_sim.bone, "levels": levels}
