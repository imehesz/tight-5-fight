class_name FloatingText
extends Label
## Popup text. Two styles:
##  - plain: outlined colored text (score awards, effects)
##  - bubble: comic-book speech bubble — white fill, thick black border,
##    black text (NPC insults, boss taunts)

const FONT_SIZE := 8


static func spawn(host: Node, pos: Vector2, text_value: String,
		color := Color.WHITE, bubble := false) -> void:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return
	var lbl := FloatingText.new()
	lbl.text = text_value
	lbl.z_index = 50
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	# Press Start 2P is monospace: width == chars * size.
	var width := text_value.length() * FONT_SIZE
	if bubble:
		lbl.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.WHITE
		sb.border_color = Color.BLACK
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 7
		sb.content_margin_right = 7
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		lbl.add_theme_stylebox_override("normal", sb)
		width += 20
	else:
		lbl.modulate = color
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 4)
	host.add_child(lbl)
	lbl.global_position = pos + Vector2(-width / 2.0, -10)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 26.0, 1.4)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.7)
	tw.tween_callback(lbl.queue_free)
