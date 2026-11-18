class_name RouterLogic
extends RefCounted
## The scene router's decisions that need no autoload (main.gd names Game, so it can't compile under the
## headless runner; it calls these and the tests call them directly).


## Whether a finished raid's result is stale: the state already ended the run (a gap above idle.gap_s, or a
## load, ends any open run from its last checkpoint and emits run_ended), so `view_relish().run_id` is -1 and
## there is nothing to write back; applying it would be refused. A boss result is never stale by this rule.
static func result_stale(kind: String, relish_view: Dictionary) -> bool:
	return kind == "raid" and int(relish_view.get("run_id", -1)) == -1


## Whether apply_result's answer `out` leaves the run done with: applied now (ok), or applied already
## (duplicate_run: the Vei fight's win, recorded as she broke, was applied by a gap or a load before the card's
## press; P3b, api-request #22). Anything else is a refusal the router logs, forfeiting the run.
static func result_done(out: Dictionary) -> bool:
	return bool(out.get("ok", false)) or str(out.get("reason", "")) == "duplicate_run"


## The line the map shows when a raid's result is stale (controls.stale_raid): the win or loss is not lost
## to the player without a word; the away report has the story.
static func stale_toast() -> String:
	return str(MapLogic.cfg()["controls"]["stale_raid"])


# --- the catch-up progress screen (configs/map_view.json "catchup") ---------------------------

static func catchup_cfg() -> Dictionary:
	return MapLogic.cfg().get("catchup", {})


## done_s / total_s of a view_catchup() dict, clamped 0..1; a total of 0 reads 0.
static func catchup_fraction(view: Dictionary) -> float:
	var total := float(view.get("total_s", 0.0))
	if total <= 0.0:
		return 0.0
	return clampf(float(view.get("done_s", 0.0)) / total, 0.0, 1.0)


## "3h 20m of 9h 05m": done_s of total_s as durations (MapLogic.fmt_drain), done never past total.
static func catchup_line(view: Dictionary, c := {}) -> String:
	if c.is_empty():
		c = catchup_cfg()
	var total := maxf(float(view.get("total_s", 0.0)), 0.0)
	var done := clampf(float(view.get("done_s", 0.0)), 0.0, total)
	return str(c["line_fmt"]) % [MapLogic.fmt_drain(done), MapLogic.fmt_drain(total)]


## Input is swallowed exactly while the catch-up runs (not during the fade-out).
static func catchup_swallows(active: bool) -> bool:
	return active


## The overlay's alpha factor (0..1) after `dt`: full while active; then it fades over `fade_s`, or goes at
## once under reduced motion (or a fade of 0).
static func catchup_alpha(alpha: float, active: bool, dt: float, fade_s: float, reduced: bool) -> float:
	if active:
		return 1.0
	if reduced or fade_s <= 0.0:
		return 0.0
	return maxf(alpha - dt / fade_s, 0.0)


## Visible while any alpha is left.
static func catchup_shown(alpha: float) -> bool:
	return alpha > 0.0
