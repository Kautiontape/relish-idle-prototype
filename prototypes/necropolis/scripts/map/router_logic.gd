class_name RouterLogic
extends RefCounted
## The scene router's decisions that need no autoload (main.gd names Game, so it can't compile under the
## headless runner; it calls these and the tests call them directly).


## Whether a finished raid's result is stale: the state already ended the run (a gap above idle.gap_s, or a
## load, ends any open run from its last checkpoint and emits run_ended), so `view_relish().run_id` is -1 and
## there is nothing to write back; applying it would be refused. A boss result is never stale by this rule.
static func result_stale(kind: String, relish_view: Dictionary) -> bool:
	return kind == "raid" and int(relish_view.get("run_id", -1)) == -1
