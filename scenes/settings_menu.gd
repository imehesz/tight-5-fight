extends MenuBase
## Settings, in tabs down the left — SOUNDS (music/SFX volume), COLORS
## (outfit), WEAPONS (the melee weapon carried on the player's back) and DECOR
## (the decoration worn on the chest, when the edition ships any) — with the
## player's comedian previewed on the right, wearing the outfit, the decoration
## and the weapon exactly as they will in the run. Everything here is
## persisted per game the moment it is picked (see GameState.SETTINGS_PATH).
## The SFX slider plays a hurt sound at the new volume so changes are audible.
##
## Tabs borrow the scoreboard's look and its rule: all three panels live in one
## fixed-size box, so switching tabs never moves the screen around.

enum Tab { SOUNDS, COLORS, WEAPONS, DECOR }

## Matches the character select preview, so the comedian is framed and sized
## the same on both screens.
const PREVIEW_SIZE := Vector2(150, 170)
const PREVIEW_SCALE := Fighter.BODY_SCALE * 1.5
## Wide enough for a rack row at the current CARD_SIZE (3 * 74 + 2 * 12 = 246)
## plus the vertical scrollbar the rack always carries — sized flush to the row
## the weapons got clipped, since the rack has horizontal scrolling switched
## off. Also what the tab row above it measures, so the two line up. Tall
## enough for the roomiest panel (the 4x6 outfit grid); the rack now shows a
## row and a half and scrolls for the rest.
const PANEL_SIZE := Vector2(276, 190)
## Tabs match the scoreboard's: same 11pt text, same 28 tall, so the two tabbed
## screens read as one control. 3 * 88 + 2 * 6 = 276 — flush with PANEL_SIZE.x.
const TAB_SIZE := Vector2(88, 28)
const TAB_GAP := 6
const TAB_FONT := 11
## A fourth tab does not fit at that width, so the row shares itself out rather
## than each tab keeping 88px — the same move the scoreboard makes for its
## fifth tab. 4 * 64 + 3 * 6 = 274, still flush with PANEL_SIZE.x, and 8pt
## keeps the longest label ("WEAPONS", 7 monospace glyphs = 56px) inside it.
const TAB_SIZE_4 := Vector2(64, 28)
const TAB_FONT_4 := 8
const TAB_ON := Color(1.0, 0.85, 0.4)
const TAB_OFF := Color(0.6, 0.6, 0.68)
## Weapon rack: a 3x3 rack of cards like the roster's, padded with blanks so
## the grid keeps its shape, and scrolling once there are more than nine.
const RACK_COLUMNS := 3
const RACK_SLOTS := 9
## Cards (and so the sprites on them, which are laid out as a CARD_INSET-padded
## full-rect child) run ~15% over the 64x84 they started at: at rack size these
## weapons are small, dark and thin, and the point of the screen is being able
## to tell them apart. Gameplay art is untouched — this is menu-only.
const CARD_SIZE := Vector2(74, 97)
## Scaled with the card, so the art grows by the same 12% the frame does rather
## than eating the padding.
const CARD_INSET := 6
## Upgrade furniture on a weapon card: stars top-left, a "+" bottom-right, and
## the next star's price stacked directly above that "+".
## All three are overlays on the card button rather than a row beneath it — a
## 74x97 card has no spare vertical room, and the art is what the card is for.
const STAR_FONT := 7
## Smaller than the stars: the price is a running cost the player checks, not
## something to read at a glance. 4 is the floor here — below it the digits
## stop holding their shape and "JP1000" and "JP1800" blur together.
const PRICE_FONT := 4
const PLUS_SIZE := Vector2(20, 20)
const PLUS_MARGIN := 3.0
const PLUS_ON := Color(1.0, 0.85, 0.4)
const PLUS_OFF := Color(0.45, 0.45, 0.52)
const GOLD := Color(1.0, 0.85, 0.4)
## Weapon cards sit on near-black rather than the faint white wash the outfit
## swatches use: these are dark, thin, detailed sprites, and over the lit street
## backdrop a translucent card left half of them unreadable. The equipped one
## is a touch lighter so it reads as raised even before you spot its gold ring.
const CARD_BG := Color(0.02, 0.02, 0.035, 0.9)
const CARD_BG_ON := Color(0.06, 0.06, 0.1, 0.96)
const CARD_BORDER := Color(0.45, 0.45, 0.52, 0.35)
## DECOR cards. Square, because the art is (any canvas is fitted to the card,
## like the weapons), and three to a row on the rack's own column spacing so
## the two shelves line up: 3 * 74 + 2 * 12 = 246, inside PANEL_SIZE.x.
const DECOR_CARD_SIZE := Vector2(74, 74)
## Category headings. Small and gold, the same language as the JOKE POINTS
## readout — they group the shelf and are never read for anything else.
const DECOR_HEADING_FONT := 7
## An unowned decoration is dimmed to say so before you ever tap it; the price
## in its corner says what it would take.
const DECOR_LOCKED := Color(0.45, 0.45, 0.5, 1.0)

var _feedback_cooldown := 0.0
var _dancer: Dancer
var _weapon_label: Label
var _tab := Tab.SOUNDS
var _tab_buttons := {}
var _panels := {}
var _weapon_cards: Array[Button] = []
## Per-card upgrade overlays, keyed by weapon index, so a crafter reply can
## repaint stars and "+" states without rebuilding the rack (which would lose
## the scroll position).
var _weapon_stars := {}
var _weapon_plus := {}
var _weapon_prices := {}
## JOKE POINTS readout above the rack. Without it a rack of grey "+" signs
## gives no hint that the reason is affordability.
var _jp_label: Label
var _rack_scroll: ScrollContainer
## DECOR shelf, keyed by decorator index (Decorators.NONE for the bare-chest
## card) so a crafter reply can repaint prices and locks in place without
## rebuilding it — same reason the weapon overlays are kept.
var _decor_cards := {}
var _decor_prices := {}
var _decor_jp_label: Label
var _decor_scroll: ScrollContainer
## The decoration a purchase is in flight for. Buying one is how you pick it,
## so the reply equips it — without this the player would have to tap twice,
## and the second tap would look like it cost them again.
var _decor_pending := Decorators.NONE


func _ready() -> void:
	if Leaderboard.JOKE_BOOK_ENABLED:
		# Repaints the rack whenever the server answers — a purchase, or the
		# fetch the weapons panel fires when it is built.
		Leaderboard.crafter_loaded.connect(_on_crafter_loaded)
	var box := build_backdrop()
	add_title(box, "SETTINGS", 18)
	add_spacer(box, 6)

	# Controls on the left, comedian on the right — the character select layout.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	col.add_child(_build_tabs())
	col.add_child(_build_panels())
	row.add_child(_build_preview())

	_show_tab(Tab.SOUNDS)
	add_back_button(func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
	_add_version_label()


## Faint build stamp pinned to the screen bottom, so a deployed build can be
## eyeballed as up to date (see GameState.version_string).
func _add_version_label() -> void:
	var v := Label.new()
	v.text = GameState.version_string()
	v.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Lifted clear of the nav bar like everything else down there — otherwise
	# the one label you check to confirm a fresh deploy is the one the phone
	# hides.
	v.offset_top = -16 - GameState.SAFE_BOTTOM
	v.offset_bottom = -GameState.SAFE_BOTTOM
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 8)
	v.modulate = Color(1.0, 1.0, 1.0, 0.3)
	add_child(v)


func _process(delta: float) -> void:
	_feedback_cooldown = maxf(_feedback_cooldown - delta, 0.0)


# ---------------------------------------------------------------- tabs
func _build_tabs() -> HBoxContainer:
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", TAB_GAP)
	tabs.add_child(_tab_button(Tab.SOUNDS, "SOUNDS"))
	tabs.add_child(_tab_button(Tab.COLORS, "COLORS"))
	tabs.add_child(_tab_button(Tab.WEAPONS, "WEAPONS"))
	# Only an edition that ships decorators.json gets the tab — everywhere else
	# the row stays the three it has always been, at its original size.
	if Decorators.any():
		tabs.add_child(_tab_button(Tab.DECOR, "DECOR"))
		for b in _tab_buttons.values():
			b.custom_minimum_size = TAB_SIZE_4
			b.add_theme_font_size_override("font_size", TAB_FONT_4)
	return tabs


func _tab_button(tab: Tab, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = TAB_SIZE
	b.add_theme_font_size_override("font_size", TAB_FONT)
	b.pressed.connect(func():
		GameState.play_sfx("click")
		_show_tab(tab))
	_tab_buttons[tab] = b
	return b


## All three panels are built up front and stacked in one fixed-size box; only
## their visibility changes. Keeps the weapon rack's scroll position across a
## trip through the other tabs, and keeps the layout still.
func _build_panels() -> Control:
	var host := Control.new()
	host.custom_minimum_size = PANEL_SIZE
	_panels[Tab.SOUNDS] = _sounds_panel()
	_panels[Tab.COLORS] = _colors_panel()
	_panels[Tab.WEAPONS] = _weapons_panel()
	if Decorators.any():
		_panels[Tab.DECOR] = _decor_panel()
	for tab in _panels:
		var p: Control = _panels[tab]
		# Anchors AND offsets: anchors alone would leave the child sized zero.
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(p)
	return host


func _show_tab(tab: Tab) -> void:
	_tab = tab
	for t in _panels:
		_panels[t].visible = t == tab
	if tab == Tab.WEAPONS:
		# Open the rack on whatever is equipped: past nine weapons the pick can
		# be below the fold, and a rack that opens on a screenful of weapons you
		# are NOT carrying reads as having lost your choice. Deferred because
		# the panel is only just being shown — it has no size to scroll yet.
		_reveal_equipped_weapon.call_deferred()
	elif tab == Tab.DECOR:
		# Same reason as the rack: past one screenful the pick can be below the
		# fold, and a shelf that opens on decorations you are NOT wearing reads
		# as having lost your choice.
		_reveal_equipped_decor.call_deferred()
	# The active tab is gold and bright; the others are dimmed on every axis a
	# Button paints text with, so hovering an inactive one doesn't fake it.
	for t in _tab_buttons:
		var on: bool = t == tab
		var b: Button = _tab_buttons[t]
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(state, TAB_ON if on else TAB_OFF)
		b.modulate = Color(1, 1, 1) if on else Color(0.72, 0.72, 0.78)


## Shared skeleton for a tab's contents: a full-rect column that centers what
## it is given inside the panel box.
func _panel_column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	return v


# ---------------------------------------------------------------- sounds
func _sounds_panel() -> Control:
	var col := _panel_column()
	col.add_child(_volume_row("MUSIC", GameState.music_volume, GameState.set_music_volume))
	col.add_child(_volume_row("SFX", GameState.sfx_volume, GameState.set_sfx_volume, true))
	return col


func _volume_row(label_text: String, value: float, setter: Callable,
		feedback := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(44, 0)
	l.add_theme_font_size_override("font_size", 8)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	# Narrower than it was — it shares the panel width with the outfit grid
	# now — but taller, so it stays an easy drag on a phone.
	slider.custom_minimum_size = Vector2(150, 24)
	slider.value_changed.connect(func(v):
		setter.call(v)
		# Throttled so dragging doesn't machine-gun the sample.
		if feedback and _feedback_cooldown <= 0.0:
			_feedback_cooldown = 0.25
			GameState.play_sfx("hurt"))
	row.add_child(slider)
	return row


# ---------------------------------------------------------------- preview
## The player's comedian, wearing the current outfit and carrying the current
## weapon. Falls back to the first on the roster for someone who has never
## picked one.
func _build_preview() -> Control:
	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	var stage := Control.new()
	stage.custom_minimum_size = PREVIEW_SIZE
	panel.add_child(stage)
	if GameState.characters.is_empty():
		return panel
	_dancer = Dancer.new()
	# Set before set_character: it decides whether the weapon gets built at all.
	_dancer.show_weapon = true
	_dancer.position = Vector2(PREVIEW_SIZE.x / 2.0, PREVIEW_SIZE.y - 6.0)
	_dancer.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	stage.add_child(_dancer)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(PREVIEW_SIZE.x, 0)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", GOLD)
	name_label.text = String(GameState.selected_character_data().get("CharacterName", "?"))
	panel.add_child(name_label)
	# Names what they are carrying, so the weapon on the back — small, and
	# behind the body — is never something you have to squint at to identify.
	_weapon_label = add_text(panel, Weapons.weapon_name(GameState.weapon), 8,
			Color(0.75, 0.75, 0.82))

	_refresh_preview()
	return panel


## Dancer reads GameState.outfit as it builds its frames, so re-applying the
## character is what re-dyes it.
func _refresh_preview() -> void:
	if is_instance_valid(_dancer):
		_dancer.set_character(GameState.selected_character_data())


# ---------------------------------------------------------------- colors
## The player's outfit color: twenty-four swatches, 4 per row — three rows of
## flats, then three of gradients. No heading; the swatches speak for
## themselves, and the grid needs the whole panel. Picking one saves
## immediately, and is worn on whichever comedian is selected.
func _colors_panel() -> Control:
	var col := _panel_column()
	col.add_child(_outfit_picker())
	return col


func _outfit_picker() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 7)

	var buttons: Array[Button] = []
	for i in CharacterFactory.OUTFITS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 24)
		set_tip(b, String(CharacterFactory.OUTFITS[i]["name"]))
		_add_gradient_face(b, i)
		b.pressed.connect(func():
			GameState.play_sfx("click")
			GameState.set_outfit(i)
			_paint_swatches(buttons)
			_refresh_preview())
		grid.add_child(b)
		buttons.append(b)
	_paint_swatches(buttons)
	return grid


## Gradient outfits get their fade painted on the swatch, so the picker shows
## what the shirt will actually look like. Flat outfits are left to the
## stylebox below. Inset 3px so the selected ring still reads over it.
func _add_gradient_face(b: Button, outfit: int) -> void:
	var top := CharacterFactory.outfit_color(outfit)
	var bottom := CharacterFactory.outfit_color2(outfit)
	if top.is_equal_approx(bottom):
		return
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var face := TextureRect.new()
	face.texture = tex
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.offset_left = 3
	face.offset_top = 3
	face.offset_right = -3
	face.offset_bottom = -3
	b.add_child(face)


func _paint_swatches(buttons: Array[Button]) -> void:
	for i in buttons.size():
		var sb := StyleBoxFlat.new()
		sb.bg_color = CharacterFactory.outfit_color(i)
		sb.set_corner_radius_all(3)
		# The picked swatch gets the menu's gold ring; the rest a thin outline
		# so a dark outfit still reads as a button against the backdrop.
		sb.set_border_width_all(3 if i == GameState.outfit else 1)
		sb.border_color = GOLD if i == GameState.outfit \
				else Color(0.0, 0.0, 0.0, 0.5)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			buttons[i].add_theme_stylebox_override(state, sb)


# ---------------------------------------------------------------- weapons
## The weapon rack. Every weapon whose art imported gets a card, padded out to
## a rectangle, and the whole thing scrolls — so adding weapons to
## weapons.json never needs a layout change.
func _weapons_panel() -> Control:
	var col := _panel_column()
	if Leaderboard.JOKE_BOOK_ENABLED:
		_jp_label = Label.new()
		_jp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_jp_label.add_theme_font_size_override("font_size", 7)
		_jp_label.add_theme_color_override("font_color", GOLD)
		col.add_child(_jp_label)
		# The rack is built once and lives as long as the screen, so this is
		# the only place that needs to ask; the reply repaints in place.
		Leaderboard.fetch_crafter()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = PANEL_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_rack_scroll = scroll

	var grid := GridContainer.new()
	grid.columns = RACK_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	var slots := Weapons.available()
	for i in slots:
		grid.add_child(_weapon_card(i))
	# Pad with blank frames out to a full bottom row — and to at least the nine
	# the panel was sized for — exactly like a short last page on the roster
	# screen. Keeps the rack rectangular at any weapon count.
	var filled := maxi(RACK_SLOTS,
			ceili(slots.size() / float(RACK_COLUMNS)) * RACK_COLUMNS)
	for _i in range(slots.size(), filled):
		grid.add_child(_empty_card())
	_paint_weapon_cards()
	_paint_upgrades()
	return col


func _reveal_equipped_weapon() -> void:
	if _rack_scroll == null:
		return
	for b in _weapon_cards:
		if int(b.get_meta("weapon")) == GameState.weapon:
			# The card, not the button, so the name label under it comes along.
			_rack_scroll.ensure_control_visible(b.get_parent())
			return


func _weapon_card(index: int) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn := Button.new()
	btn.custom_minimum_size = CARD_SIZE
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	set_tip(btn, Weapons.weapon_name(index))
	btn.set_meta("weapon", index)

	# The weapon sits on the button as a child rather than as an icon: these
	# sprites are 1:3, and only KEEP_ASPECT_CENTERED inside a padded rect keeps
	# a chainsaw and a pool cue looking like the same rack of items.
	var art := TextureRect.new()
	art.texture = Weapons.texture(index)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Shown the way it will hang on your back, not the way the file is stored:
	# both flips together are a clean half turn, and unlike `rotation` they need
	# no pivot fixing up after the card is laid out.
	if Weapons.grip_up(index):
		art.flip_h = true
		art.flip_v = true
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_left = CARD_INSET
	art.offset_top = CARD_INSET
	art.offset_right = -CARD_INSET
	art.offset_bottom = -CARD_INSET
	btn.add_child(art)

	btn.pressed.connect(func():
		GameState.play_sfx("click")
		GameState.set_weapon(index)
		_paint_weapon_cards()
		if _weapon_label:
			_weapon_label.text = Weapons.weapon_name(index)
		if is_instance_valid(_dancer):
			# Swap the weapon only — no need to rebuild the comedian, and the
			# dance keeps its rhythm through the pick.
			_dancer.refresh_weapon())
	if Leaderboard.JOKE_BOOK_ENABLED:
		_add_upgrade_overlay(btn, index)
	card.add_child(btn)
	_weapon_cards.append(btn)

	var name_label := Label.new()
	name_label.text = Weapons.weapon_name(index)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(CARD_SIZE.x, 0)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 6)
	card.add_child(name_label)
	return card


## Stars top-left, "+" bottom-right, the next star's price stacked above it, all
## sitting on the card button itself.
##
## The "+" is a Button INSIDE a Button: Godot gives the child the click first,
## so buying an upgrade never also re-equips the weapon. A miss goes to the
## card underneath and merely equips it, which is the harmless way round.
func _add_upgrade_overlay(btn: Button, index: int) -> void:
	var stars := Label.new()
	stars.add_theme_font_size_override("font_size", STAR_FONT)
	stars.add_theme_color_override("font_color", PLUS_ON)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.position = Vector2(PLUS_MARGIN, PLUS_MARGIN)
	btn.add_child(stars)
	_weapon_stars[index] = stars

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = PLUS_SIZE
	plus.size = PLUS_SIZE
	plus.add_theme_font_size_override("font_size", 11)
	# Anchored to the card's bottom-right so it stays put whatever the card
	# does; offsets as well as anchors, or the preset leaves the old ones.
	plus.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	plus.offset_left = -PLUS_SIZE.x - PLUS_MARGIN
	plus.offset_top = -PLUS_SIZE.y - PLUS_MARGIN
	plus.offset_right = -PLUS_MARGIN
	plus.offset_bottom = -PLUS_MARGIN
	# Never `disabled`: a grey "+" still has to be tappable, because tapping it
	# is how the player finds out WHY it is grey.
	plus.pressed.connect(guard_tap(func(): _on_plus_pressed(index)))
	btn.add_child(plus)
	_weapon_plus[index] = plus

	# The price of the NEXT star, in its own band directly above the "+" and
	# sharing that button's right edge, so the two read as one control.
	# RIGHT-aligned rather than centred for exactly that reason: a wider price
	# ("JP2000") then grows leftward into the card's empty middle instead of
	# drifting off the "+" it belongs to.
	var price := Label.new()
	price.add_theme_font_size_override("font_size", PRICE_FONT)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Bottom-aligned so it hugs the "+" whatever the band rounds to.
	price.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# Same reason as `stars`: this must never swallow a tap meant for the card
	# or the "+" sitting under it.
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	price.offset_left = -CARD_SIZE.x + PLUS_MARGIN
	price.offset_top = -PLUS_SIZE.y - PLUS_MARGIN * 2.0 - PRICE_FONT - 3.0
	price.offset_right = -PLUS_MARGIN
	price.offset_bottom = -PLUS_SIZE.y - PLUS_MARGIN * 2.0
	btn.add_child(price)
	_weapon_prices[index] = price


## The one place that decides what a "+" tap means. Three outcomes, and the
## grey ones explain themselves rather than doing nothing.
func _on_plus_pressed(index: int) -> void:
	var weapon_id := Weapons.id_of(index)
	var level := Leaderboard.upgrade_level(weapon_id)
	# Priced per LEVEL, so the popup quotes what this particular star costs.
	var cost := Leaderboard.next_upgrade_cost(weapon_id)
	if level >= Leaderboard.max_upgrades():
		show_modal("WEAPON FULLY UPGRADED")
		return
	if Leaderboard.joke_points() < cost:
		show_modal("CRAFT JOKES IN THE JOKE BOOK FOR UPGRADES.")
		return
	show_modal("ARE YOU SURE YOU WANT TO SPEND JP%d ON THIS UPGRADE?" % cost,
			func(): Leaderboard.buy_upgrade(weapon_id))


## Repaint stars and "+" colour from the cached crafter state. Split out from
## _paint_weapon_cards so a crafter reply can refresh the rack without
## touching the equipped-card styling.
func _paint_upgrades() -> void:
	if not Leaderboard.JOKE_BOOK_ENABLED:
		return
	if _jp_label != null:
		_jp_label.text = "JOKE POINTS  JP%s" % String.num_int64(Leaderboard.joke_points()).pad_zeros(6)
	var cap := Leaderboard.max_upgrades()
	for index in _weapon_stars:
		var weapon_id := Weapons.id_of(index)
		var level := Leaderboard.upgrade_level(weapon_id)
		_weapon_stars[index].text = Weapons.stars(index)
		# Per weapon, not one shared price: a weapon on its third star costs
		# 2000 while an untouched one costs 500, so affordability differs
		# card by card even though the balance is the same.
		var cost := Leaderboard.next_upgrade_cost(weapon_id)
		# Gold only when a purchase is actually available right now: maxed out
		# and can't-afford both read as grey, and the popup says which.
		var buyable: bool = level < cap and Leaderboard.joke_points() >= cost
		var plus: Button = _weapon_plus[index]
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			plus.add_theme_color_override(state, PLUS_ON if buyable else PLUS_OFF)
		# A maxed weapon prints nothing rather than "JP0": next_upgrade_cost()
		# returns 0 for "not for sale", and a 0 price reads as free. The three
		# lit stars beside it are what say why the "+" went quiet.
		var price: Label = _weapon_prices[index]
		price.text = "" if level >= cap else "JP%d" % cost
		price.add_theme_color_override("font_color", PLUS_ON if buyable else PLUS_OFF)


func _on_crafter_loaded(_data: Dictionary) -> void:
	_paint_upgrades()
	if _decor_cards.is_empty():
		return
	# A purchase that just landed equips itself — the confirm popup WAS the
	# pick. Guarded on ownership rather than on "a reply arrived", so a reply
	# for something else (or a purchase the server refused) never silently
	# dresses the player in what they failed to buy.
	if _decor_pending != Decorators.NONE and _decor_unlocked(_decor_pending):
		GameState.set_decor(_decor_pending)
		_decor_pending = Decorators.NONE
		if is_instance_valid(_dancer):
			_dancer.refresh_decor()
	_paint_decor()


## A blank placeholder frame (not clickable) keeping a short rack on the same
## 3x3 grid as a full one.
func _empty_card() -> VBoxContainer:
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	var frame := Panel.new()
	frame.custom_minimum_size = CARD_SIZE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	# Same near-black as a real card, so the padded-out slots read as part of
	# the rack rather than as holes in it.
	sb.bg_color = CARD_BG
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(2)
	sb.border_color = CARD_BORDER
	frame.add_theme_stylebox_override("panel", sb)
	card.add_child(frame)
	var pad := Label.new()
	pad.text = " "  # same metrics as a name label, so rows stay aligned
	pad.add_theme_font_size_override("font_size", 6)
	card.add_child(pad)
	return card


## Same language as the outfit swatches: the equipped weapon wears the menu's
## gold ring, the rest a thin dim outline, and the unpicked art is dimmed so
## the choice reads at a glance.
func _paint_weapon_cards() -> void:
	for b in _weapon_cards:
		var on: bool = int(b.get_meta("weapon")) == GameState.weapon
		var sb := StyleBoxFlat.new()
		sb.bg_color = CARD_BG_ON if on else CARD_BG
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(3 if on else 2)
		sb.border_color = GOLD if on else CARD_BORDER
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, sb)
		# Barely dimmed now. The dark card and the gold ring already say which
		# one is equipped, and the old 0.68 wash was working against the whole
		# point of this change — the unpicked weapons are the ones you are
		# trying to see.
		b.modulate = Color(1, 1, 1) if on else Color(0.9, 0.9, 0.93)


# ---------------------------------------------------------------- decor
## The DECOR shelf: the chest decorations this edition ships (games/<id>/
## decorators.json), grouped under their `category`. The grouping is display
## only — nothing else in the game reads it — so a category is just a heading
## with a grid of cards under it, in file order.
##
## A free decoration equips on tap. A priced one has to be bought first, with
## JOKE POINTS, and the SERVER owns that transaction exactly like a weapon
## upgrade: this screen only asks, and repaints from whatever comes back.
func _decor_panel() -> Control:
	var col := _panel_column()
	if Leaderboard.JOKE_BOOK_ENABLED:
		_decor_jp_label = Label.new()
		_decor_jp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_decor_jp_label.add_theme_font_size_override("font_size", 7)
		_decor_jp_label.add_theme_color_override("font_color", GOLD)
		col.add_child(_decor_jp_label)
		# The weapons panel is built first and already asks; this is only the
		# fallback for a build where that panel is gone. _crafter_call drops a
		# second call while the first is in flight, so a duplicate is free.
		Leaderboard.fetch_crafter()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = PANEL_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_decor_scroll = scroll

	var shelf := VBoxContainer.new()
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.add_theme_constant_override("separation", 6)
	scroll.add_child(shelf)
	# "Wear nothing" leads the shelf, ungrouped: it belongs to no category, and
	# it is the one card every player needs to be able to find.
	shelf.add_child(_decor_grid([Decorators.NONE]))
	for c in Decorators.categories():
		shelf.add_child(_decor_heading(c))
		shelf.add_child(_decor_grid(Decorators.in_category(c)))
	_paint_decor()
	return col


func _decor_heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", DECOR_HEADING_FONT)
	l.add_theme_color_override("font_color", GOLD)
	return l


## One category's cards. Unlike the weapon rack this is NOT padded out to a
## rectangle: a category of two would grow a row of empty frames that read as
## decorations that failed to load.
func _decor_grid(indices: Array[int]) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = RACK_COLUMNS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	for i in indices:
		grid.add_child(_decor_card(i))
	return grid


## Decorators.NONE builds the bare-chest card — a labelled empty frame rather
## than art, since "nothing" has no sprite to show.
func _decor_card(index: int) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn := Button.new()
	btn.custom_minimum_size = DECOR_CARD_SIZE
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.set_meta("decor", index)

	if index == Decorators.NONE:
		btn.text = "NONE"
		btn.add_theme_font_size_override("font_size", 8)
		set_tip(btn, "NO DECORATION")
	else:
		set_tip(btn, Decorators.decor_name(index).to_upper())
		# The art as a padded full-rect child rather than an icon, for the
		# weapon rack's reason: KEEP_ASPECT_CENTERED inside a padded rect is
		# what makes decorations of any canvas size read as one shelf.
		var art := TextureRect.new()
		art.texture = Decorators.texture(index)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.offset_left = CARD_INSET
		art.offset_top = CARD_INSET
		art.offset_right = -CARD_INSET
		art.offset_bottom = -CARD_INSET
		btn.add_child(art)
		_add_decor_price(btn, index)

	btn.pressed.connect(guard_tap(func(): _on_decor_pressed(index)))
	card.add_child(btn)
	_decor_cards[index] = btn

	var name_label := Label.new()
	# Upper-cased here, not in the data: every label on these screens is, and
	# decorators.json is written in prose.
	name_label.text = "" if index == Decorators.NONE else Decorators.decor_name(index).to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Capped at the card width, or a long name would widen the whole COLUMN —
	# a GridContainer column is as wide as its widest child.
	name_label.custom_minimum_size = Vector2(DECOR_CARD_SIZE.x, 0)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 6)
	card.add_child(name_label)
	return card


## The price, bottom-right on the card itself — a 74x74 card has no spare row
## under it, and this disappears the moment the decoration is owned, so an
## unlocked shelf carries no clutter.
func _add_decor_price(btn: Button, index: int) -> void:
	var price := Label.new()
	price.add_theme_font_size_override("font_size", 6)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# Never swallows a tap meant for the card underneath it.
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.add_theme_color_override("font_color", GOLD)
	price.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	price.offset_left = -DECOR_CARD_SIZE.x + PLUS_MARGIN
	price.offset_top = -PLUS_MARGIN - 8.0
	price.offset_right = -PLUS_MARGIN
	price.offset_bottom = -PLUS_MARGIN
	btn.add_child(price)
	_decor_prices[index] = price


## Can the player wear this right now? Free decorations (and the bare chest)
## always; a priced one only once the SERVER says it was bought. Unknown is
## never guessed upward — see Leaderboard.owns_decor.
func _decor_unlocked(index: int) -> bool:
	if index == Decorators.NONE or Decorators.price(index) <= 0:
		return true
	return Leaderboard.owns_decor(Decorators.id_of(index))


## The one place that decides what tapping a decoration means. Like the weapon
## rack's "+", the locked outcomes explain themselves rather than doing nothing.
func _on_decor_pressed(index: int) -> void:
	GameState.play_sfx("click")
	if _decor_unlocked(index):
		GameState.set_decor(index)
		_paint_decor()
		if is_instance_valid(_dancer):
			# Swap the decoration only — the comedian keeps dancing through it.
			_dancer.refresh_decor()
		return
	var cost := Decorators.price(index)
	if not Leaderboard.JOKE_BOOK_ENABLED:
		show_modal("THIS DECOR IS NOT FOR SALE YET.")
		return
	if Leaderboard.joke_points() < cost:
		show_modal("CRAFT JOKES IN THE JOKE BOOK TO BUY DECOR.")
		return
	show_modal("ARE YOU SURE YOU WANT TO SPEND JP%d ON THIS DECOR?" % cost,
			func():
				# Remembered so the reply can equip it — buying one IS picking
				# it, and a second tap would look like a second charge.
				_decor_pending = index
				Leaderboard.buy_decor(Decorators.id_of(index)))


## Repaint the shelf from the cached crafter state: which card wears the gold
## ring, which are still locked, and what the locked ones cost.
func _paint_decor() -> void:
	if _decor_jp_label != null:
		_decor_jp_label.text = "JOKE POINTS  JP%s" \
				% String.num_int64(Leaderboard.joke_points()).pad_zeros(6)
	for index in _decor_cards:
		var btn: Button = _decor_cards[index]
		var on: bool = index == GameState.decor
		var locked := not _decor_unlocked(index)
		var sb := StyleBoxFlat.new()
		sb.bg_color = CARD_BG_ON if on else CARD_BG
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(3 if on else 2)
		sb.border_color = GOLD if on else CARD_BORDER
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(state, sb)
		# A locked decoration is dimmed hard, so the shelf says what is yours
		# before you tap anything; the rest follows the weapon rack's barely-
		# there wash, because seeing them is the point of the screen.
		btn.modulate = DECOR_LOCKED if locked \
				else (Color(1, 1, 1) if on else Color(0.9, 0.9, 0.93))
		if _decor_prices.has(index):
			# Owned means paid for: the price comes off the card entirely
			# rather than sitting there looking like a running cost.
			_decor_prices[index].text = ("JP%d" % Decorators.price(index)) if locked else ""


func _reveal_equipped_decor() -> void:
	if _decor_scroll == null or not _decor_cards.has(GameState.decor):
		return
	# The card, not the button, so the name label under it comes along.
	_decor_scroll.ensure_control_visible(_decor_cards[GameState.decor].get_parent())
