class_name Billboard
extends Node2D
## A sponsor billboard on the street: two posts, a framed panel showing the
## sponsor's 640x460 ad, and a row of top-down gooseneck lamps washing it in
## warm light — the ad has to be readable at a walk-by. All procedural
## (posts/frame/lamps), same no-art recipe as BarStool; only the ad itself
## is a texture (delivered by the Sponsors autoload).
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
const POST_W := 8.0
const POST_COLOR := Color(0.16, 0.13, 0.22)
const FRAME_COLOR := Color(0.22, 0.18, 0.3)
const TRIM_COLOR := Color(0.55, 0.48, 0.68)
const LAMP_COLOR := Color(0.2, 0.18, 0.26)
const LIGHT_WARM := Color(1.0, 0.9, 0.55)

var sponsor_id := ""
## True once this instance has billed its impression (or was restored from a
## street snapshot that already had).
var counted := false

var _glows: Array = []
var _flicker_phase := randf() * TAU


func configure(sponsor: Dictionary, already_counted := false) -> void:
	sponsor_id = String(sponsor.get("id", ""))
	counted = already_counted
	z_index = -5  # background furniture, same layer as venue exteriors

	var panel_top := PANEL_BOTTOM - AD_H - FRAME * 2.0
	var half_w := AD_W / 2.0 + FRAME

	# Posts, panel bottom down to LEG_BOTTOM (slightly overlapped up top so
	# no seam shows against the frame).
	for px in [-AD_W * 0.32, AD_W * 0.32]:
		var post := ColorRect.new()
		post.color = POST_COLOR
		post.size = Vector2(POST_W, LEG_BOTTOM - PANEL_BOTTOM + 4.0)
		post.position = Vector2(px - POST_W / 2.0, PANEL_BOTTOM - 4.0)
		add_child(post)

	# Frame, then the ad inset into it.
	var frame := ColorRect.new()
	frame.color = FRAME_COLOR
	frame.size = Vector2(half_w * 2.0, AD_H + FRAME * 2.0)
	frame.position = Vector2(-half_w, panel_top)
	add_child(frame)
	var trim := ColorRect.new()
	trim.color = TRIM_COLOR
	trim.size = Vector2(half_w * 2.0 - 2.0, AD_H + FRAME * 2.0 - 2.0)
	trim.position = Vector2(-half_w + 1.0, panel_top + 1.0)
	add_child(trim)
	var backing := ColorRect.new()
	backing.color = Color(0.05, 0.04, 0.09)
	backing.size = Vector2(AD_W, AD_H)
	backing.position = Vector2(-AD_W / 2.0, panel_top + FRAME)
	add_child(backing)

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
		add_child(ad)

	# Honest-labelling tag, tucked on the frame's bottom-right.
	var tag := Label.new()
	tag.text = "AD"
	tag.add_theme_font_size_override("font_size", 6)
	tag.add_theme_color_override("font_color", Color(0.65, 0.6, 0.75))
	tag.position = Vector2(half_w - 16.0, PANEL_BOTTOM - 11.0)
	add_child(tag)

	_add_lamps(panel_top)

	# The impression fires when the PANEL actually scrolls into view, not
	# when the node spawns (spawns happen a screen ahead of the player).
	var seen := VisibleOnScreenNotifier2D.new()
	seen.rect = Rect2(-half_w, panel_top - 14.0, half_w * 2.0, AD_H + FRAME * 2.0 + 14.0)
	seen.screen_entered.connect(_on_seen)
	add_child(seen)


## Three gooseneck lamps along the top edge: stem up, head bent over the
## panel, and a translucent light cone washing down the ad.
func _add_lamps(panel_top: float) -> void:
	for i in 3:
		var lx := -AD_W * 0.33 + i * AD_W * 0.33
		var stem := ColorRect.new()
		stem.color = LAMP_COLOR
		stem.size = Vector2(3.0, 12.0)
		stem.position = Vector2(lx - 1.5, panel_top - 12.0)
		add_child(stem)
		var head := Polygon2D.new()
		head.polygon = PackedVector2Array([
			Vector2(lx - 7.0, panel_top - 13.0), Vector2(lx + 7.0, panel_top - 13.0),
			Vector2(lx + 4.0, panel_top - 6.0), Vector2(lx - 4.0, panel_top - 6.0)])
		head.color = LAMP_COLOR
		add_child(head)
		var bulb := ColorRect.new()
		bulb.color = LIGHT_WARM
		bulb.size = Vector2(6.0, 2.0)
		bulb.position = Vector2(lx - 3.0, panel_top - 7.0)
		add_child(bulb)
		var glow := Polygon2D.new()
		glow.polygon = PackedVector2Array([
			Vector2(lx - 5.0, panel_top - 6.0), Vector2(lx + 5.0, panel_top - 6.0),
			Vector2(lx + 26.0, panel_top + AD_H * 0.85),
			Vector2(lx - 26.0, panel_top + AD_H * 0.85)])
		glow.color = Color(LIGHT_WARM, 0.10)
		add_child(glow)
		_glows.append(glow)


## The faintest shimmer on the light cones — enough that the eye drifts to
## the billboard, nowhere near actual flicker.
func _process(_delta: float) -> void:
	var a := 0.10 + 0.025 * sin(Time.get_ticks_msec() / 320.0 + _flicker_phase)
	for g in _glows:
		g.color.a = a


func _on_seen() -> void:
	if counted or sponsor_id == "":
		return
	counted = true
	GameState.count_billboard_impression(sponsor_id)
