class_name MenuBase
extends Control
## Shared scaffolding for menu screens: dark backdrop, centered column,
## title/button helpers. Menus build their UI in code in _ready().


## Passing "" (the default) uses the active game's menu background from the
## manifest, so every menu screen shares one per-game backdrop.
func build_backdrop(bg_path := "") -> VBoxContainer:
	if bg_path == "":
		bg_path = GameState.menu_bg_path()
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if bg_path != "" and ResourceLoader.exists(bg_path):
		var art := TextureRect.new()
		art.texture = load(bg_path)
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(art)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.45)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	return box


func add_title(box: Container, text: String, size := 20, color := Color(1.0, 0.85, 0.4)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


func add_text(box: Container, text: String, size := 8, color := Color(0.8, 0.8, 0.85)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


func add_button(box: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 36)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(func(): GameState.play_sfx("click"))
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func add_spacer(box: Container, h := 8) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	box.add_child(s)


const EDGE_ARROW_MARGIN := 10.0

## A "<" / ">" pager pinned to the screen's left or right edge, vertically
## centred. Anchored to the menu root (not the content column), so the arrows
## stay put no matter how wide the names/rows between them get — muscle-memory
## tap targets. With aspect="expand" the anchors track the real screen edge.
## 1.5x the in-row arrows: edge targets are hit by feel, so they run big.
func add_edge_arrow(text: String, on_right: bool, cb: Callable, min_size := Vector2(45, 90)) -> Button:
	var b := make_arrow_button(text, cb, min_size)
	b.add_theme_font_size_override("font_size", 24)
	var ax := 1.0 if on_right else 0.0
	b.anchor_left = ax
	b.anchor_right = ax
	b.anchor_top = 0.5
	b.anchor_bottom = 0.5
	b.offset_top = -min_size.y / 2.0
	b.offset_bottom = min_size.y / 2.0
	if on_right:
		b.offset_right = -EDGE_ARROW_MARGIN
		b.offset_left = -EDGE_ARROW_MARGIN - min_size.x
		b.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	else:
		b.offset_left = EDGE_ARROW_MARGIN
		b.offset_right = EDGE_ARROW_MARGIN + min_size.x
		b.grow_horizontal = Control.GROW_DIRECTION_END
	add_child(b)
	return b


## A tall, narrow "<" / ">" pager button. Shared by character select and the
## scoreboard so both pagers click and look the same; the caller decides what
## turning a page means.
func make_arrow_button(text: String, cb: Callable, min_size := Vector2(30, 60)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func():
		GameState.play_sfx("click")
		cb.call())
	return b
