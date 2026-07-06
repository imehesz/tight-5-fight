class_name FloatingText
extends Label
## Small popup text used for insults, score awards and effects.


static func spawn(host: Node, pos: Vector2, text_value: String, color := Color.WHITE) -> void:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return
	var lbl := FloatingText.new()
	lbl.text = text_value
	lbl.modulate = color
	lbl.z_index = 50
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	host.add_child(lbl)
	lbl.global_position = pos + Vector2(-60, -8)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 26.0, 1.2)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.5)
	tw.tween_callback(lbl.queue_free)
