class_name LoadingBanner
extends RefCounted
## "LOADING ..." pinned top-centre, over everything, while slow work runs —
## people wait far more patiently when they can see SOMETHING is happening.
##
## Usage, from any script:
##     await LoadingBanner.run(_build_the_slow_thing)
##
## Why run() and not just show()/hide() around the work: a plain load() blocks
## the main thread, and a label shown in the same frame as the work never gets
## drawn — the freeze arrives first. run() shows the banner, waits until a
## frame WITH the banner has actually been drawn, and only then does the work.
##
## Static and self-contained: no autoload, no scene. The banner lives on its
## own CanvasLayer under the tree root, so it sits above every scene (and
## modals) and survives a scene change mid-load. Calls nest — overlapping
## run()s keep it up until the last one finishes.

## Above the modal layer (128), so a confirm popup never hides it.
const LAYER := 129
const TEXT := "LOADING ..."
## One colour per letter of LOADING — an arcade rainbow, so the eye goes
## straight to it. The dots (and anything past the palette) stay gold.
const LETTER_COLORS: Array[Color] = [
	Color(1.0, 0.25, 0.25),   # L red
	Color(1.0, 0.6, 0.15),    # O orange
	Color(1.0, 0.9, 0.2),     # A yellow
	Color(0.3, 0.9, 0.3),     # D green
	Color(0.25, 0.85, 1.0),   # I cyan
	Color(0.4, 0.5, 1.0),     # N blue
	Color(0.9, 0.4, 1.0),     # G violet
]
const DOTS_COLOR := Color(1.0, 0.85, 0.4)
const FONT_SIZE := 12
## Solid black plate behind the text, so the colours pop over any screen.
const PAD_X := 8
const PAD_Y := 5

static var _layer: CanvasLayer
static var _depth := 0


## Show the banner, let it draw, run `work`, hide it. `work` may itself be a
## coroutine; it is awaited either way.
static func run(work: Callable) -> void:
	show()
	# Wait until the NEXT frame's process step: by then the frame the banner
	# went up in has been drawn. Two ticks for margin (e.g. called mid scene
	# change). NOT RenderingServer.frame_post_draw — that never fires with no
	# renderer (headless), and a signal that never comes leaves the banner up
	# and the work never run.
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await tree.process_frame
	# The screen that asked may be gone by now (BACK tapped during the wait).
	if work.is_valid():
		await work.call()
	hide()


static func show() -> void:
	_depth += 1
	if _depth == 1:
		_ensure_layer()
		_layer.visible = true


static func hide() -> void:
	_depth = maxi(_depth - 1, 0)
	if _depth == 0 and is_instance_valid(_layer):
		_layer.visible = false


static func _ensure_layer() -> void:
	if is_instance_valid(_layer):
		return
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	# One Label per character: a Label can only be one colour. The font is
	# monospace, so a row of one-glyph labels with no gap spaces exactly like
	# a single label would.
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	sb.set_corner_radius_all(3)
	sb.content_margin_left = PAD_X
	sb.content_margin_right = PAD_X
	sb.content_margin_top = PAD_Y
	sb.content_margin_bottom = PAD_Y
	plate.add_theme_stylebox_override("panel", sb)
	plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	plate.offset_top = 10
	plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Never swallows a tap meant for the screen underneath.
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	for i in TEXT.length():
		var ch := Label.new()
		ch.text = TEXT[i]
		ch.add_theme_font_size_override("font_size", FONT_SIZE)
		ch.add_theme_color_override("font_color",
				LETTER_COLORS[i] if i < LETTER_COLORS.size() else DOTS_COLOR)
		ch.add_theme_color_override("font_outline_color", Color.BLACK)
		ch.add_theme_constant_override("outline_size", 4)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ch)
	_layer.add_child(plate)
	# Deferred: run() may be called while a scene is still being set up, when
	# the root refuses new children. Deferred calls still land before the frame
	# is drawn, so the banner shows on the very frame run() waits for.
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_layer)
