class_name BountyBanner
extends CanvasLayer
## "BOUNTY COLLECTED!" — the payoff for KOing today's WANTED comedian.
##
## Born tiny at the KO spot, it bursts out in a confetti pop and a screen
## flash, sails up to the top third of the screen at full size behind a
## spinning sunburst, holds there shimmering, then flies off the top. The
## gold "+N" floater enemy.gd already spawns keeps doing the counting; this
## is purely the celebration.
##
## Screen-space on purpose (its own CanvasLayer): a world-space label would
## drift with the camera and shrink under the venue zoom, and "grand" means
## the same size everywhere.
##
## Usage: BountyBanner.spawn(enemy.global_position + Vector2(0, -60))

## Over the HUD (80) so the banner is never behind the score, under the hint
## popup (90) and modals so it never covers a question the player must answer.
const LAYER := 85
const LINE1 := "BOUNTY"
const LINE2 := "COLLECTED!"
const LINE1_SIZE := 20
const LINE2_SIZE := 24
const GOLD := Color(1.0, 0.84, 0.3)
const SHINE := Color(1.0, 1.0, 0.85)
## Where the banner parks, as fractions of the visible screen.
const PARK := Vector2(0.5, 0.3)
## Birth scale at the KO spot, overshoot peak, and timings (seconds).
const START_SCALE := 0.2
const PEAK_SCALE := 1.15
const RISE_S := 0.5
const HOLD_S := 1.3
const EXIT_S := 0.45
## The sunburst behind the words.
const RAYS := 14
const RAY_LEN := 120.0
const RAY_SPIN_S := 5.0


## Fire the celebration from a WORLD position (the KO'd enemy). Projected
## into screen space through the viewport's canvas transform, which already
## includes any camera — the same trick the HUD gain fliers use.
static func spawn(world_pos: Vector2) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var banner := BountyBanner.new()
	# Parented to the scene, not the root: a scene change (game over, venue
	# exit) takes the banner with it instead of leaving it over the menu.
	tree.current_scene.add_child(banner)
	var vp := banner.get_viewport()
	banner._play(vp.get_canvas_transform() * world_pos, vp.get_visible_rect().size)


func _play(origin: Vector2, view: Vector2) -> void:
	layer = LAYER
	origin = origin.clamp(Vector2(40, 40), view - Vector2(40, 40))
	GameState.play_crowd("cheer")

	# Quick warm flash over the whole screen — the "something big happened".
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.95, 0.7, 0.35)
	flash.size = view
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	flash.create_tween().tween_property(flash, "color:a", 0.0, 0.3)

	_add_confetti(origin)

	var root := Node2D.new()
	root.position = origin
	root.scale = Vector2.ONE * START_SCALE
	add_child(root)

	var rays := _make_rays()
	root.add_child(rays)
	var spin := rays.create_tween().set_loops()
	spin.tween_property(rays, "rotation", TAU, RAY_SPIN_S).from(0.0)

	var l1 := _make_line(LINE1, LINE1_SIZE)
	var l2 := _make_line(LINE2, LINE2_SIZE)
	root.add_child(l1)
	root.add_child(l2)
	# Stack the two lines around the root's origin, so scaling the root
	# grows the whole banner about its own centre.
	var gap := 4.0
	var total := l1.size.y + gap + l2.size.y
	l1.position = Vector2(-l1.size.x / 2.0, -total / 2.0)
	l2.position = Vector2(-l2.size.x / 2.0, -total / 2.0 + l1.size.y + gap)

	# Shimmer: the words pulse gold -> near-white while they hold.
	for l in [l1, l2]:
		var sh := (l as Label).create_tween().set_loops()
		sh.tween_property(l, "modulate", SHINE, 0.15)
		sh.tween_property(l, "modulate", GOLD, 0.15)

	var park := view * PARK
	var tw := create_tween()
	tw.tween_property(root, "position", park, RISE_S) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(root, "scale", Vector2.ONE * PEAK_SCALE, RISE_S * 0.7) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(HOLD_S)
	# Exit: whip up off the top, fading as it goes.
	tw.tween_property(root, "position:y", -80.0, EXIT_S) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(root, "modulate:a", 0.0, EXIT_S)
	tw.tween_callback(queue_free)


func _make_line(text: String, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = GOLD
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.add_theme_color_override("font_shadow_color", Color(0.45, 0.1, 0.0))
	lbl.add_theme_constant_override("shadow_offset_x", 3)
	lbl.add_theme_constant_override("shadow_offset_y", 3)
	lbl.add_theme_constant_override("shadow_outline_size", 8)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.reset_size()
	return lbl


## Alternating translucent gold wedges — the old-west "reward" sunburst.
func _make_rays() -> Node2D:
	var rays := Node2D.new()
	var half := PI / RAYS / 2.0
	for i in RAYS:
		var a := TAU * i / RAYS
		var wedge := Polygon2D.new()
		wedge.polygon = PackedVector2Array([
			Vector2.ZERO,
			Vector2.from_angle(a - half) * RAY_LEN,
			Vector2.from_angle(a + half) * RAY_LEN,
		])
		wedge.color = Color(1.0, 0.8, 0.25, 0.4 if i % 2 == 0 else 0.22)
		rays.add_child(wedge)
	return rays


## One-shot confetti burst left behind at the KO spot while the banner rises.
func _add_confetti(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 48
	p.lifetime = 1.3
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 240.0
	p.gravity = Vector2(0, 320)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	ramp.colors = PackedColorArray([GOLD, Color(1.0, 0.3, 0.3),
			Color(0.3, 0.85, 1.0), Color.WHITE])
	p.color_initial_ramp = ramp
	add_child(p)
	p.emitting = true
