extends MenuBase
## Main Menu: Play, Settings, Scoreboard, About.
##
## The SPONSORS entry is temporarily commented out (2026-07-23) so players meet
## the in-game billboard ads with no menu explaining them — we want to see the
## unprimed reaction first. The sponsors_menu scene, the Sponsors autoload and
## the in-game billboards are all untouched; uncomment the marked blocks below
## to bring the button back.

#var _sponsors_btn: Button

## Clear space between the screen edge and the bill, on both sides.
##
## The bills hang at 1:1 off their own larger texture, never scaled: the menu
## column measures 336px and sits centred, so the 640px design width leaves
## exactly 152px of margin on each side. At 105 wide a bill leaves 29px of
## clear space before the buttons start. The viewport only ever gets WIDER
## than the design (stretch aspect is "expand"), so that 29px is the worst
## case rather than a typical one.
const MENU_BILL_MARGIN := 18.0

## The Tight 5 Games socials, plus the tip jar. Publisher-level, not
## per-edition — every city build points at the same pages, so these stay
## constants here rather than in the per-game manifest.
const SOCIALS := [
	{
		"icon": "res://shared/assets/ui/social_facebook.png",
		"url": "https://www.facebook.com/profile.php?id=61593096446732",
		"tip": "Tight 5 Games on Facebook",
	},
	{
		"icon": "res://shared/assets/ui/social_instagram.png",
		"url": "https://www.instagram.com/tight5games/",
		"tip": "@tight5games on Instagram",
	},
	{
		"icon": "res://shared/assets/ui/social_coffee.png",
		"url": "https://buymeacoffee.com/tight5games",
		"tip": "Buy us a coffee",
	},
]


func _ready() -> void:
	var box := build_backdrop()
	add_title(box, GameState.menu_title(), 24)
	add_text(box, "beat the streets. bomb gracefully.", 8, Color(0.7, 0.7, 0.8))
	add_spacer(box, 12)
	add_button(box, "PLAY", func(): GameState.change_scene(GameState.SCENE_CHARACTER_SELECT))
	add_button(box, "SETTINGS", func(): GameState.change_scene(GameState.SCENE_SETTINGS))
	add_button(box, "LEADERBOARD", func(): GameState.change_scene(GameState.SCENE_SCOREBOARD))
	add_button(box, "ABOUT", func(): GameState.change_scene(GameState.SCENE_ABOUT))
	add_spacer(box, 6)
	add_link_row(box, SOCIALS)
	_add_wanted_bill()
	# --- SPONSORS button: temporarily hidden, restore this block ------------
	#_sponsors_btn = add_button(box, "SPONSORS", func(): GameState.change_scene(GameState.SCENE_SPONSORS))
	#_sponsors_btn.visible = not Sponsors.active.is_empty()
	#if not Sponsors.is_ready():
		#Sponsors.ensure_loaded()
		#Sponsors.sponsors_ready.connect(_show_sponsors_if_any)
	# -----------------------------------------------------------------------


## Today's bounty, pinned to BOTH margins of the menu, so a player knows who
## they are hunting before they ever press PLAY — whichever side they look.
##
## Nothing is drawn at all when there is no bounty, which is the empty-roster
## case.
func _add_wanted_bill() -> void:
	var cfg: Dictionary = GameState.wanted_data()
	if cfg.is_empty():
		return
	_pin_bill(cfg, true)
	_pin_bill(cfg, false)


## One bill against the left or right edge, vertically centred.
##
## Anchored to the LIVE viewport rather than placed at a design-width offset —
## the same wide-phone rule every other menu follows, and what keeps the pair
## hugging the edges as the screen gets wider instead of drifting inward. Both
## are lifted by the Android nav-bar inset, like the centred column between
## them.
func _pin_bill(cfg: Dictionary, left_side: bool) -> void:
	var bill := WantedPoster.make_bill(cfg, 1.0, WantedPoster.BILL_TEX_MENU_PATH)
	var bw: float = bill.custom_minimum_size.x
	var bh: float = bill.custom_minimum_size.y
	var edge := 0.0 if left_side else 1.0
	bill.anchor_left = edge
	bill.anchor_right = edge
	bill.anchor_top = 0.5
	bill.anchor_bottom = 0.5
	bill.offset_left = MENU_BILL_MARGIN if left_side else -(MENU_BILL_MARGIN + bw)
	bill.offset_right = bill.offset_left + bw
	bill.offset_top = -bh / 2.0 - GameState.SAFE_BOTTOM
	bill.offset_bottom = bh / 2.0 - GameState.SAFE_BOTTOM
	# Added after build_backdrop's shade, so the bills sit on top of the
	# darkened art rather than under it.
	add_child(bill)


# --- SPONSORS button: temporarily hidden, restore with the block above ------
#func _show_sponsors_if_any() -> void:
	#_sponsors_btn.visible = not Sponsors.active.is_empty()
