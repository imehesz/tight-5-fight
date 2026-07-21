extends MenuBase
## SPONSORS: the businesses currently backing this city's fights. One
## tappable row per active sponsor (their street-billboard ad as the icon,
## tap opens their site), fed by the same hosted roster the billboards use —
## so this screen and the street can never disagree about who's live.

const ADVERTISE_MAILTO := "mailto:imehesz@gmail.com?subject=TIGHT%205%20FIGHT%20sponsorship"
## Row height doubles as the tap target (phone-first: comfortably over 45px).
const ROW_H := 48.0

var _list: VBoxContainer


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, "SPONSORS", 18)
	add_spacer(box, 2)
	add_text(box, "They keep the mics on. Give them a tap.", 8)
	add_spacer(box, 6)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_list)
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
	for s in Sponsors.active:
		_list.add_child(_sponsor_row(s))


## One tappable sponsor row: the billboard ad as the icon, name beside it.
## The whole row is the tap target, mirroring how the landing page's cards
## work — nobody should have to hit a tiny link on a phone.
func _sponsor_row(s: Dictionary) -> Button:
	var b := Button.new()
	b.text = " " + String(s.name)
	b.icon = s.texture
	b.expand_icon = true
	b.custom_minimum_size = Vector2(240, ROW_H)
	b.add_theme_font_size_override("font_size", 10)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var link := String(s.link)
	b.pressed.connect(func():
		GameState.play_sfx("click")
		if link != "":
			OS.shell_open(link))
	return b
