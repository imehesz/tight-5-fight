class_name Billboard
extends Node2D
## A sponsor billboard on the street: a framed panel showing the sponsor's
## 640x460 ad and a row of top-down gooseneck lamps washing it in warm light
## — the ad has to be readable at a walk-by. Two support variants, rolled per
## spawn: two slim wooden legs, or one thick old wooden post with decorative
## WANTED posters baked into its texture. Every board leans a degree or two
## (left or right, so the legs come out uneven) instead of standing surveyor-
## straight. Frame/lamps stay procedural; the ad texture comes from the
## Sponsors autoload, the wood from shared/assets/parts/t5f-wood-post.png.
##
## Origin is the ground point between the posts, so the street places it
## like it places doors: position = (x, GROUND_Y).
##
## One billboard = at most ONE impression (VisibleOnScreenNotifier2D →
## GameState.count_billboard_impression), and `counted` round-trips through
## street_state so re-walking a restored street never double-bills a sponsor.

## Ad panel: the 640x460 ad scaled to 170px wide, plus frame around it.
const AD_W := 170.0
const AD_H := AD_W * 460.0 / 640.0  # ≈ 122
const FRAME := 6.0
## Panel bottom sits this far above the ground — high street furniture,
## fully above the fighters' heads but inside the 360px design view.
const PANEL_BOTTOM := -132.0
## Posts stop this far above the ground line, so the billboard reads as
## planted on the far sidewalk instead of in the lane the fighters walk.
const LEG_BOTTOM := -50.0
const LEG_W := 9.0
## Width of the single-post variant's thick trunk on screen.
const THICK_POST_W := 26.0
## Every board leans a touch — enough that they stop looking machine-placed,
## not enough to read as falling over.
const MIN_TILT_DEG := 0.7
const MAX_TILT_DEG := 2.2
## Weathered wooden post (Higgsfield, decorative WANTED posters baked in).
## The slim legs sample poster-free wood from the top of this same texture.
## Path string + runtime load(), same as PlaneDrop's textures.
const WOOD_TEX_PATH := "res://shared/assets/parts/t5f-wood-post.png"
## Cool night-street cast over the daylight-neutral wood.
const WOOD_TINT := Color(0.78, 0.75, 0.92)
## Odds that this board gets a pigeon visit (1-3 birds) when it scrolls in.
const BIRD_CHANCE := 0.7
const FRAME_COLOR := Color(0.22, 0.18, 0.3)
const TRIM_COLOR := Color(0.55, 0.48, 0.68)
const LAMP_COLOR := Color(0.2, 0.18, 0.26)
const LIGHT_WARM := Color(1.0, 0.9, 0.55)

var sponsor_id := ""
## True once this instance has billed its impression (or was restored from a
## street snapshot that already had).
var counted := false
## "legs" (two slim posts) or "post" (one thick old wooden post). Rolled at
## spawn, round-tripped through street_state like `counted`.
var variant := "legs"
## Signed lean in degrees; also persisted so a restored street leans the same.
var tilt_deg := 0.0

var _panel: Node2D
var _wood: Texture2D
var _glows: Array = []
var _flicker_phase := randf() * TAU
## One bird roll per board, even if the panel re-enters the screen.
var _birds_rolled := false


func configure(sponsor: Dictionary, already_counted := false,
		saved_variant := "", saved_tilt := 0.0) -> void:
	sponsor_id = String(sponsor.get("id", ""))
	counted = already_counted
	if saved_variant == "":
		variant = "post" if randf() < 0.5 else "legs"
		tilt_deg = randf_range(MIN_TILT_DEG, MAX_TILT_DEG) * (1.0 if randf() < 0.5 else -1.0)
	else:
		variant = saved_variant
		tilt_deg = saved_tilt
	z_index = -8  # background furniture: above street tiles (-10) but below
	# the banner plane (-7) — the plane must fly IN FRONT of billboards while
	# still passing behind venue exteriors/signs (-5/-4)

	var tilt := deg_to_rad(tilt_deg)
	var panel_top := PANEL_BOTTOM - AD_H - FRAME * 2.0
	var half_w := AD_W / 2.0 + FRAME
	_wood = load(WOOD_TEX_PATH)

	# Supports go in first so the panel frame draws over their tops (no seam).
	# The panel leans by `tilt` around the ground origin; supports stay
	# vertical and each runs from the panel's (rotated, so uneven) bottom
	# edge down to LEG_BOTTOM — that's what makes one leg longer.
	if variant == "post":
		_add_thick_post(tilt)
	else:
		for px in [-AD_W * 0.32, AD_W * 0.32]:
			_add_leg(px, tilt)

	# Everything panel-mounted lives under one rotated node, keeping the
	# child layout identical to the old untilted math.
	_panel = Node2D.new()
	_panel.rotation = tilt
	add_child(_panel)

	# Frame, then the ad inset into it.
	var frame := ColorRect.new()
	frame.color = FRAME_COLOR
	frame.size = Vector2(half_w * 2.0, AD_H + FRAME * 2.0)
	frame.position = Vector2(-half_w, panel_top)
	_panel.add_child(frame)
	var trim := ColorRect.new()
	trim.color = TRIM_COLOR
	trim.size = Vector2(half_w * 2.0 - 2.0, AD_H + FRAME * 2.0 - 2.0)
	trim.position = Vector2(-half_w + 1.0, panel_top + 1.0)
	_panel.add_child(trim)
	var backing := ColorRect.new()
	backing.color = Color(0.05, 0.04, 0.09)
	backing.size = Vector2(AD_W, AD_H)
	backing.position = Vector2(-AD_W / 2.0, panel_top + FRAME)
	_panel.add_child(backing)

	var tex: Texture2D = sponsor.get("texture")
	if tex:
		var ad := Sprite2D.new()
		ad.texture = tex
		ad.centered = false
		# 640x460 by contract, but scale from the real size so an off-spec
		# image still fits the panel (fit-inside, centered).
		var s := minf(AD_W / tex.get_width(), AD_H / tex.get_height())
		ad.scale = Vector2(s, s)
		ad.position = Vector2(-tex.get_width() * s / 2.0,
				panel_top + FRAME + (AD_H - tex.get_height() * s) / 2.0)
		_panel.add_child(ad)

	# Honest-labelling tag, tucked on the frame's bottom-right.
	var tag := Label.new()
	tag.text = "AD"
	tag.add_theme_font_size_override("font_size", 6)
	tag.add_theme_color_override("font_color", Color(0.65, 0.6, 0.75))
	tag.position = Vector2(half_w - 16.0, PANEL_BOTTOM - 11.0)
	_panel.add_child(tag)

	_add_lamps(panel_top)

	# The impression fires when the PANEL actually scrolls into view, not
	# when the node spawns (spawns happen a screen ahead of the player).
	var seen := VisibleOnScreenNotifier2D.new()
	seen.rect = Rect2(-half_w, panel_top - 14.0, half_w * 2.0, AD_H + FRAME * 2.0 + 14.0)
	seen.screen_entered.connect(_on_seen)
	_panel.add_child(seen)


## One slim wooden leg under the tilted panel's bottom edge at panel-local x
## `px` — sampled from a poster-free patch of the wood texture, each leg its
## own patch so the pair doesn't read as copy-pasted.
func _add_leg(px: float, tilt: float) -> void:
	# Where the panel's bottom edge actually ends up once it leans (tucked
	# 4px up behind the frame so no seam shows).
	var attach := Vector2(px, PANEL_BOTTOM - 4.0).rotated(tilt)
	var leg_h := LEG_BOTTOM - attach.y
	var src_w := 22.0
	var src_h := 150.0
	var leg := Sprite2D.new()
	leg.texture = _wood
	leg.centered = false
	leg.region_enabled = true
	leg.region_rect = Rect2(
			randf_range(6.0, _wood.get_width() - src_w - 6.0),
			randf_range(0.0, _wood.get_height() * 0.49 - src_h), src_w, src_h)
	leg.scale = Vector2(LEG_W / src_w, leg_h / src_h)
	leg.position = Vector2(attach.x - LEG_W / 2.0, attach.y)
	leg.modulate = WOOD_TINT
	add_child(leg)


## The one-post variant: a thick old wooden trunk under the panel's center,
## cropped so the baked-in nailed posters land in the visible span.
func _add_thick_post(tilt: float) -> void:
	var attach := Vector2(0.0, PANEL_BOTTOM - 6.0).rotated(tilt)
	var span := LEG_BOTTOM - attach.y
	var s := THICK_POST_W / _wood.get_width()
	var src_h := span / s
	# Center the crop on the poster cluster (~62% down the texture).
	var y0 := clampf(_wood.get_height() * 0.62 - src_h / 2.0,
			0.0, _wood.get_height() - src_h)
	var post := Sprite2D.new()
	post.texture = _wood
	post.centered = false
	post.region_enabled = true
	post.region_rect = Rect2(0.0, y0, _wood.get_width(), src_h)
	post.scale = Vector2(s, s)
	post.position = Vector2(attach.x - THICK_POST_W / 2.0, attach.y)
	post.modulate = WOOD_TINT
	add_child(post)


## Three gooseneck lamps along the top edge: stem up, head bent over the
## panel, and a translucent light cone washing down the ad.
func _add_lamps(panel_top: float) -> void:
	for i in 3:
		var lx := -AD_W * 0.33 + i * AD_W * 0.33
		var stem := ColorRect.new()
		stem.color = LAMP_COLOR
		stem.size = Vector2(3.0, 12.0)
		stem.position = Vector2(lx - 1.5, panel_top - 12.0)
		_panel.add_child(stem)
		var head := Polygon2D.new()
		head.polygon = PackedVector2Array([
			Vector2(lx - 7.0, panel_top - 13.0), Vector2(lx + 7.0, panel_top - 13.0),
			Vector2(lx + 4.0, panel_top - 6.0), Vector2(lx - 4.0, panel_top - 6.0)])
		head.color = LAMP_COLOR
		_panel.add_child(head)
		var bulb := ColorRect.new()
		bulb.color = LIGHT_WARM
		bulb.size = Vector2(6.0, 2.0)
		bulb.position = Vector2(lx - 3.0, panel_top - 7.0)
		_panel.add_child(bulb)
		var glow := Polygon2D.new()
		glow.polygon = PackedVector2Array([
			Vector2(lx - 5.0, panel_top - 6.0), Vector2(lx + 5.0, panel_top - 6.0),
			Vector2(lx + 26.0, panel_top + AD_H * 0.85),
			Vector2(lx - 26.0, panel_top + AD_H * 0.85)])
		glow.color = Color(LIGHT_WARM, 0.10)
		_panel.add_child(glow)
		_glows.append(glow)


## The faintest shimmer on the light cones — enough that the eye drifts to
## the billboard, nowhere near actual flicker.
func _process(_delta: float) -> void:
	var a := 0.10 + 0.025 * sin(Time.get_ticks_msec() / 320.0 + _flicker_phase)
	for g in _glows:
		g.color.a = a


func _on_seen() -> void:
	_maybe_spawn_birds()
	if counted or sponsor_id == "":
		return
	counted = true
	GameState.count_billboard_impression(sponsor_id)


## Pure decoration: most boards get 1-3 pigeons that swoop in shortly after
## the board scrolls into view, perch on the frame's top edge between the
## lamps, glance around, and leave. One visit per board per street — but a
## re-walk can roll a fresh visit (birds aren't part of street_state).
func _maybe_spawn_birds() -> void:
	if _birds_rolled:
		return
	_birds_rolled = true
	if randf() > BIRD_CHANCE:
		return
	var panel_top := PANEL_BOTTOM - AD_H - FRAME * 2.0
	# Landing slots along the top edge, clear of the three lamp stems.
	var slots := [-72.0, -30.0, 28.0, 70.0]
	slots.shuffle()
	for i in randi_range(1, 3):
		var bird := BillboardBird.new()
		_panel.add_child(bird)
		bird.setup(Vector2(slots[i], panel_top - 1.0),
				randf_range(0.2, 1.4) + i * randf_range(0.5, 0.9))
