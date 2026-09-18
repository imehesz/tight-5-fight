class_name WantedPoster
extends Node2D
## Today's bounty, nailed to a post on the street: an aged old-west WANTED bill
## with the comedian's face printed on it.
##
## Deliberately NOT a Billboard. Billboards are sponsor inventory — spots that
## are sold, counted and reported — so this must never occupy one of those
## slots or bill an impression. It borrows the weathered post texture and the
## lean, and nothing else: no lamps, no ad panel, no impression counter.
##
## The bill itself is ART, not drawn code: the paper, the torn edges, the
## stains and the WANTED lettering are all baked into one texture, which is why
## nothing here needs a display font. Only the portrait is composited, into the
## empty panel the art leaves for it.
##
## Origin is the ground point under the post, exactly like Billboard, so the
## street places it the same way: position = (x, GROUND_Y).

## The baked bill. Its own pixel size IS the size it draws at — the project
## filters textures NEAREST, so the street shows it 1:1 and the run-start
## popup doubles it on a whole number, which keeps every edge crisp.
const BILL_TEX_PATH := "res://shared/assets/parts/t5f-wanted-bill.png"
## The same bill cut larger, straight from the full-resolution original, for
## the main menu. A SECOND texture rather than scaling the first: the project
## filters NEAREST, so a 1.25x scale would double some pixel rows and not
## others and shred the baked lettering. FACE_RECT is stored as fractions, so
## both sizes share it untouched.
const BILL_TEX_MENU_PATH := "res://shared/assets/parts/t5f-wanted-bill_menu.png"
## The empty panel the art leaves for the portrait, as FRACTIONS of the bill —
## measured off the texture rather than guessed, and fractions rather than
## pixels so redrawing the art at another size cannot silently shift the face.
const FACE_RECT := Rect2(0.2206, 0.2701, 0.5574, 0.4007)
## Aged photo stock behind the portrait. The baked panel is nearly black, and a
## sepia head on near-black just reads as mud; on this it reads as a print.
const FACE_BACKING := Color(0.769, 0.659, 0.471)
## The vintage wash over the face. Heads are full-colour pngs, and multiplying
## one down to warm sepia is what sells "printed a century ago".
const FACE_TINT := Color(0.910, 0.745, 0.471)
## The reward line printed in the blank band under the portrait, and the ink it
## is printed in. The name is deliberately NOT here — the face is the whole
## point, and a name at this size costs two lines of the bill to say something
## the portrait already said.
const REWARD_TEXT := "+10% KO"
const INK := Color(0.18, 0.12, 0.07)
## The printed panel is drawn this much larger than the one baked into the
## art. It is the only thing on the bill that has to read at a walk-by, and
## the baked panel is a touch small for it. Growing it also COVERS the baked
## panel completely, which is why the frame below is drawn here — otherwise
## two borders would fight, the baked one and ours.
const FACE_SCALE := 1.15
## Bottom of the bill above the ground line. Same furniture height billboards
## hang at, so the street keeps one consistent skyline.
const PANEL_BOTTOM := -132.0
## Where the post stops, matching Billboard's legs: planted on the far sidewalk
## instead of in the lane the fighters walk down.
const POST_BOTTOM := -50.0
const THICK_POST_W := 22.0
## Every board on this street leans a degree or two; this one is no different.
const MIN_TILT_DEG := 0.7
const MAX_TILT_DEG := 2.2
## Shared with Billboard — the weathered post that already has bills baked into
## its art, which is the look this prop is extending.
const WOOD_TEX_PATH := "res://shared/assets/parts/t5f-wood-post.png"
const WOOD_TINT := Color(0.78, 0.75, 0.92)

## Who this bill is for — the permanent CharacterId, so a rename never orphans
## a poster mid-run.
var char_id := ""
## Signed lean in degrees; persisted so a restored street leans the same way.
var tilt_deg := 0.0


## Build the bill for one roster entry. `saved_tilt` of 0.0 means "roll a new
## lean"; a restored street passes the one it stored.
func configure(cfg: Dictionary, saved_tilt := 0.0) -> void:
	char_id = String(cfg.get("CharacterId", ""))
	tilt_deg = saved_tilt if not is_zero_approx(saved_tilt) \
			else randf_range(MIN_TILT_DEG, MAX_TILT_DEG) * (1.0 if randf() < 0.5 else -1.0)
	# Same layer as Billboard: above the street tiles (-10), below the banner
	# plane (-7) so the plane still flies in front of it.
	z_index = -8

	var tex: Texture2D = load(BILL_TEX_PATH)
	if tex == null:
		return
	var tilt := deg_to_rad(tilt_deg)
	var panel_top := PANEL_BOTTOM - tex.get_height()

	# Post first, so the bill draws over its top and leaves no seam.
	_add_post(tilt)

	# Everything bill-mounted hangs off one rotated node, which keeps the
	# layout below in plain untilted coordinates.
	var panel := Node2D.new()
	panel.rotation = tilt
	add_child(panel)
	_draw_bill(panel, cfg, panel_top)


## The bill drawn into any Node2D, top edge at `panel_top`, centred on x = 0.
##
## Static and shared on purpose: the street prop and the run-start
## introduction both call this, so what the player is shown at the top of the
## run is literally the same artwork they will spot nailed to a post later.
static func _draw_bill(panel: Node2D, cfg: Dictionary, panel_top: float,
		tex_path := BILL_TEX_PATH) -> void:
	var tex: Texture2D = load(tex_path)
	if tex == null:
		return
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var left := -w / 2.0

	var paper := Sprite2D.new()
	paper.texture = tex
	paper.centered = false
	paper.position = Vector2(left, panel_top)
	panel.add_child(paper)

	# The portrait panel, in bill pixels, grown about its centre.
	var box := Rect2(
			left + FACE_RECT.position.x * w, panel_top + FACE_RECT.position.y * h,
			FACE_RECT.size.x * w, FACE_RECT.size.y * h)
	var gx := box.size.x * (FACE_SCALE - 1.0) / 2.0
	var gy := box.size.y * (FACE_SCALE - 1.0) / 2.0
	box = box.grow_individual(gx, gy, gx, gy)

	# Ink border, then the photo stock inside it: together they replace the
	# baked panel this now sits on top of.
	var frame := ColorRect.new()
	frame.color = INK
	frame.position = box.position - Vector2.ONE
	frame.size = box.size + Vector2.ONE * 2.0
	panel.add_child(frame)

	var backing := ColorRect.new()
	backing.color = FACE_BACKING
	backing.position = box.position
	backing.size = box.size
	panel.add_child(backing)

	_add_face(panel, String(cfg.get("HeadSpritePath", "")), box)

	# The reward line, centred in the band the art leaves blank below the
	# portrait. Project font, so it reads as part of the game rather than as a
	# second display face fighting the baked lettering above it.
	var reward := Label.new()
	reward.text = REWARD_TEXT
	reward.add_theme_font_size_override("font_size", 6)
	reward.add_theme_color_override("font_color", INK)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var band_top := box.position.y + box.size.y
	reward.position = Vector2(left, band_top)
	reward.size = Vector2(w, panel_top + h - band_top)
	panel.add_child(reward)


## The comedian's head, fit INSIDE the portrait panel and washed to sepia.
##
## Fit inside rather than filling it: the heads are tall ovals on a square
## canvas, and scaling one to cover a square panel crops the hair off — which
## is the one thing that makes a comedian recognisable at this size. A head
## that fails to load leaves the photo stock blank rather than breaking the
## prop; the bill still says somebody is wanted.
static func _add_face(panel: Node2D, head_path: String, box: Rect2) -> void:
	if head_path == "":
		return
	var tex: Texture2D = load(head_path)
	if tex == null:
		return
	var s := minf(box.size.x / tex.get_width(), box.size.y / tex.get_height())
	var face := Sprite2D.new()
	face.texture = tex
	face.centered = false
	face.scale = Vector2(s, s)
	face.modulate = FACE_TINT
	face.position = box.position + (box.size - Vector2(
			tex.get_width() * s, tex.get_height() * s)) / 2.0
	panel.add_child(face)


## The bill wrapped in a Control, for dropping into a UI panel. `zoom` is a
## whole number on purpose — this is pixel art under NEAREST filtering, and a
## fractional scale would put the paper edges between pixels.
static func make_bill(cfg: Dictionary, zoom := 2.0,
		tex_path := BILL_TEX_PATH) -> Control:
	var tex: Texture2D = load(tex_path)
	var w := float(tex.get_width()) if tex else 84.0
	var h := float(tex.get_height()) if tex else 117.0
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, h) * zoom
	var art := Node2D.new()
	art.scale = Vector2(zoom, zoom)
	# _draw_bill centres on x = 0, so shift it into the holder's own box.
	art.position = Vector2(w / 2.0 * zoom, 0.0)
	holder.add_child(art)
	_draw_bill(art, cfg, 0.0, tex_path)
	return holder


## The thick weathered trunk, cropped onto the cluster of baked-in bills so the
## post itself reads as a place things get nailed to.
func _add_post(tilt: float) -> void:
	var wood: Texture2D = load(WOOD_TEX_PATH)
	if wood == null:
		return
	var attach := Vector2(0.0, PANEL_BOTTOM - 6.0).rotated(tilt)
	var span := POST_BOTTOM - attach.y
	var s := THICK_POST_W / wood.get_width()
	var src_h := span / s
	var y0 := clampf(wood.get_height() * 0.62 - src_h / 2.0,
			0.0, wood.get_height() - src_h)
	var post := Sprite2D.new()
	post.texture = wood
	post.centered = false
	post.region_enabled = true
	post.region_rect = Rect2(0.0, y0, wood.get_width(), src_h)
	post.scale = Vector2(s, s)
	post.position = Vector2(attach.x - THICK_POST_W / 2.0, attach.y)
	post.modulate = WOOD_TINT
	add_child(post)
