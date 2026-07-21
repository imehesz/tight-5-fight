extends MenuBase
## SPONSORS: the businesses currently backing this city's fights. One
## tappable row per active sponsor (their street-billboard ad as the icon,
## tap opens their site), fed by the same hosted roster the billboards use —
## so this screen and the street can never disagree about who's live.

const ADVERTISE_MAILTO := "mailto:imehesz@gmail.com?subject=TIGHT%205%20FIGHT%20sponsorship"
## Row height doubles as the tap target (phone-first: comfortably over 45px).
const ROW_H := 48.0
## Every ad renders in this same box regardless of name length — uniform
## images were the whole point of ditching Button.expand_icon.
const AD_SIZE := Vector2(72, 40)
## Fixed viewport for the list (~3 rows); extra sponsors scroll instead of
## pushing ADVERTISE HERE / BACK off screen.
const LIST_H := 160.0
## Past MAX_SHOWN we show a random 6 here (the street still runs everyone —
## this screen is a sampler, not the roster of record).
const MAX_SHOWN := 6

var _list: VBoxContainer


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, "SPONSORS", 18)
	add_spacer(box, 2)
	add_text(box, "They keep the mics on. Give them a tap.", 8)
	add_spacer(box, 6)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, LIST_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	add_spacer(box, 8)
	add_button(box, "ADVERTISE HERE", func(): OS.shell_open(ADVERTISE_MAILTO))
	add_button(box, "BACK", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))

	Sponsors.ensure_loaded()
	if Sponsors.is_ready():
		_populate()
	else:
		add_text(_list, "Loading…", 8)
		Sponsors.sponsors_ready.connect(_populate, CONNECT_ONE_SHOT)


func _populate() -> void:
	for c in _list.get_children():
		c.queue_free()
	if Sponsors.active.is_empty():
		add_text(_list, "This space is for sale.", 9, Color(1.0, 0.85, 0.4))
		return
	var shown: Array = Sponsors.active.duplicate()
	if shown.size() > MAX_SHOWN:
		shown.shuffle()
		shown = shown.slice(0, MAX_SHOWN)
	for s in shown:
		_list.add_child(_sponsor_row(s))


## One tappable sponsor row: the billboard ad in a fixed AD_SIZE box (not
## Button.icon — expand_icon sizes the icon from leftover text space, so
## long names shrank the art), name beside it. The whole row is the tap
## target — nobody should have to hit a tiny link on a phone.
func _sponsor_row(s: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 8)
	b.add_child(h)
	var ad := TextureRect.new()
	ad.texture = s.texture
	ad.custom_minimum_size = AD_SIZE
	ad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ad.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ad.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ad)
	var name_l := Label.new()
	name_l.text = String(s.name)
	name_l.add_theme_font_size_override("font_size", 10)
	name_l.size_flags_vertical = Control.SIZE_FILL
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(name_l)
	var link := String(s.link)
	b.pressed.connect(func():
		GameState.play_sfx("click")
		if link != "":
			OS.shell_open(link))
	return b
