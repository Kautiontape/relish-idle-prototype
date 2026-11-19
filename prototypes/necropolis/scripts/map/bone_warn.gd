class_name BoneWarn
extends RefCounted
## BONE's stall warning beside the top bar's BONE cell (HudLogic.show_bone_warn), kept out of MapHud so headless tests
## can build it (MapHud names Game). The model's line comes in on each new rev (set_line); the hold runs on this HUD's
## own real clock (tick), every frame, so a line held after its stall has gone runs out bone_line.hold_s after the stall
## was last seen even while the model stands still (a paused game has no new rev). One per MapHud: a map reload builds a
## new one, with no line held and no room kept.

var label: Label
var clock := 0.0  # real seconds since the bar was built
var _line := ""  # the model's line at its last rev ("": no stall)
var _held := {}  # show_bone_warn's last return: the line it holds and when the stall was last seen


func _init(warn: Label) -> void:
	label = warn


## A new rev: the model's line now (HudLogic.bone_line; "" when nothing stalls).
func set_line(line: String) -> void:
	_line = line
	_held = HudLogic.show_bone_warn(label, _line, _held, clock)


## Every frame, real seconds: a stall still in the model is seen again, and a held line runs out on time.
func tick(delta: float) -> void:
	clock += delta
	if _line != "" or label.text != "":  # no stall and nothing held: nothing to do
		_held = HudLogic.show_bone_warn(label, _line, _held, clock)
