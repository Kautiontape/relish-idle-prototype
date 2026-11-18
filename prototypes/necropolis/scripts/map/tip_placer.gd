class_name TipPlacer
extends RefCounted
## The bar tooltip's placement state, split out of MapHud (which names the Game autoload and can't compile
## headless) so it can be tested. It remembers the inputs of its last placement (HudLogic.tip_key) and
## answers whether the shown plate must move: the card opening or closing, the HUD re-laying out, or the
## map's readouts moving re-place it; the same inputs again leave it where it is.

var _key: Array = []
var _has := false
var _rect := Rect2()


## `plates`: the HUD's text plates; `readouts`: the map's own text (Vei's readout and name, Covington's
## labels) in screen px, kept clear like the plates; `card`: the open card (Rect2() closed). Returns
## {moved: whether the plate must be put at `rect` now, rect: where it goes (the last one when not moved)}.
func place(word: Rect2, tip_size: Vector2, plates: Array, card: Rect2, viewport: Vector2, readouts := []) -> Dictionary:
	var key := HudLogic.tip_key(word, tip_size, plates + readouts, card, viewport)
	if _has and key == _key:
		return {"moved": false, "rect": _rect}
	_key = key
	_has = true
	_rect = HudLogic.tip_rect(word, tip_size, plates, viewport, card, readouts)
	return {"moved": true, "rect": _rect}


## The plate was hidden or is about to show: the next place() moves it.
func reset() -> void:
	_key = []
	_has = false
	_rect = Rect2()
