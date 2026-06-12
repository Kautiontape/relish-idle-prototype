extends Node
## Autoload "GameState". Per-run haul + the §12 telemetry (command touches vs
## trance summons, circle-score histogram), plus global debug toggles.
## Relish's death is ONE deletion path: total_wipe() (§8.3).

signal haul_changed
signal telemetry_changed

var remnants: Array = []        # rolled remnant dicts
var husks: Array = []           # husk id strings
var kills := 0
var essence_dropped := 0
var chaff_summoned := 0
var command_touches := 0
var trance_summons := 0
var circle_scores: Array = []
var current_chamber := 0

# Debug toggles (debug panel writes, everything else reads).
var debug := {
	"god": false,
	"pacifist": false,
	"freeze": false,
	"show_targets": false,
	"show_paths": false,
	"show_fields": true,
}

func reset_run() -> void:
	remnants = []
	husks = []
	kills = 0
	essence_dropped = 0
	chaff_summoned = 0
	command_touches = 0
	trance_summons = 0
	circle_scores = []
	current_chamber = 0
	haul_changed.emit()
	telemetry_changed.emit()

## §8.3 — Relish died. Everything is lost. Phase 1 has no persistence, so the
## wipe is the run state; when saves arrive (Phase 2) they die here too.
func total_wipe() -> void:
	reset_run()

func add_remnant(r: Dictionary) -> void:
	remnants.append(r)
	haul_changed.emit()

func add_husk(id: String) -> void:
	husks.append(id)
	haul_changed.emit()

func add_command_touch() -> void:
	command_touches += 1
	telemetry_changed.emit()

func add_summon(score: int, chaff_count: int) -> void:
	trance_summons += 1
	chaff_summoned += chaff_count
	circle_scores.append(score)
	telemetry_changed.emit()

func ratio_string() -> String:
	if trance_summons == 0:
		return "%d : 0" % command_touches
	return "%.1f : 1" % (float(command_touches) / float(trance_summons))

## True when command touches dominate ~8:1 — the RTS-drift kill criterion (§12).
func ratio_drifting() -> bool:
	return trance_summons > 0 and float(command_touches) / float(trance_summons) >= 8.0

func score_histogram() -> Array:
	var buckets := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for s in circle_scores:
		buckets[clampi(int(s) / 10, 0, 9)] += 1
	return buckets

func average_score() -> float:
	if circle_scores.is_empty():
		return 0.0
	var sum := 0.0
	for s in circle_scores:
		sum += s
	return sum / circle_scores.size()
