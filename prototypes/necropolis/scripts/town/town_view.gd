extends Control
## The town view (left). Placeholder: ground colour and a centred title. Task 2 replaces the body.

signal command_issued

var views := {}


func bind(v: Dictionary) -> void:
	views = v
	queue_redraw()


func on_game_event(_ev: Dictionary) -> void:
	pass


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.c("ground"))
	var font := ThemeDB.fallback_font
	var fs := 24
	var txt := "Covington"
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.c("text_dim"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
