extends MenuBase
## Game Over: the mic drop. A microphone falls from above, thuds onto the
## stage (smash SFX + screen shake), tips over flat, and a big GAME OVER
## slams in — then the results column and the dancer fade up. The whole
## overture runs ~1.2s so PLAY AGAIN regulars aren't held hostage.

## Twice the in-game fighter size.
const DANCE_SCALE := Fighter.BODY_SCALE * 2.0
const DANCE_FEET_POS := Vector2(110, 330)

const MIC_TEXTURE := "res://shared/assets/ui/mic.png"
## Where the mic lands: the very bottom of the viewport (360 is fixed —
## aspect="expand" widens on phones, never heightens), so it drops past the
## button column instead of hovering beside it. The dancer keeps the stage
## line at 330.
const FLOOR_Y := 360.0
## Sprite is 48x96, center-anchored, drawn MIC_SCALE bigger: upright the
## floor is half the scaled height below center, lying flat half the WIDTH.
const MIC_SCALE := 1.2
const MIC_HALF_H := 48.0 * MIC_SCALE
const MIC_HALF_W := 24.0 * MIC_SCALE
const SHAKE_PX := 5.0

var _box: VBoxContainer
var _title: Label
var _dancer: Dancer
var _back_btn: Button
var _mic: Sprite2D


func _ready() -> void:
	_box = build_backdrop()
	_title = add_title(_box, "GAME OVER", 32, Color(0.95, 0.3, 0.25))
	add_text(_box, "%s bombed after %d venue%s." % [
		String(GameState.selected_character_data().get("CharacterName", "You")),
		GameState.venues_entered,
		"" if GameState.venues_entered == 1 else "s",
	])
	add_spacer(_box, 8)
	add_title(_box, "FINAL SCORE: %d" % GameState.score, 14, Color(0.9, 0.9, 0.95))
	if GameState.last_run_rank >= 0 and GameState.last_run_rank < GameState.CELEBRATED_HIGH_SCORES:
		add_title(_box, "NEW HIGH SCORE — #%d!" % (GameState.last_run_rank + 1), 10)
	add_spacer(_box, 14)
	# One-tap retry: straight back to the street as the same comedian (or a
	# fresh roll if the "?" card is the active pick). Roster detours are the
	# CHANGE COMEDIAN button's job now.
	add_button(_box, "PLAY AGAIN", func(): GameState.start_new_game(GameState.fight_character_index()))
	add_button(_box, "CHANGE COMEDIAN", func(): GameState.change_scene(GameState.SCENE_CHARACTER_SELECT))
	add_button(_box, "SCOREBOARD", func(): GameState.change_scene(GameState.SCENE_SCOREBOARD))
	# Leaving to the main menu is the corner BACK now, like every other
	# screen. It hangs off the root rather than _box, so it has to be hidden
	# and revealed by hand with the rest (see _reveal) — a tap during the mic
	# drop must not jump the player out mid-animation.
	_back_btn = add_back_button(func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
	_dancer = Dancer.new()
	_dancer.position = DANCE_FEET_POS
	_dancer.scale = Vector2(DANCE_SCALE, DANCE_SCALE)
	_dancer.set_character(GameState.selected_character_data())
	add_child(_dancer)

	# Everything above is laid out but hidden until the mic has landed.
	# visible=false, not modulate.a=0: an invisible-by-alpha Button still
	# takes clicks, and a mid-drop tap must not restart the game.
	_box.visible = false
	_dancer.visible = false
	_back_btn.visible = false
	_drop_the_mic()


## Fall → thud (smash + shake) → bounce, tipping over → land flat → reveal.
func _drop_the_mic() -> void:
	_mic = Sprite2D.new()
	_mic.texture = load(MIC_TEXTURE)
	_mic.scale = Vector2(MIC_SCALE, MIC_SCALE)
	# Center of the LIVE viewport, not design 320: aspect="expand" widens the
	# screen on phones and the mic should split it down the middle.
	var cx := get_viewport_rect().size.x / 2.0
	_mic.position = Vector2(cx, -MIC_HALF_H)
	add_child(_mic)

	var tw := create_tween()
	# Gravity: ease IN, so it accelerates into the floor.
	tw.tween_property(_mic, "position:y", FLOOR_Y - MIC_HALF_H, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		GameState.play_sfx("smash")
		_shake()
		_blast_text())
	# One bounce, tipping over on the way up...
	tw.tween_property(_mic, "position:y", FLOOR_Y - MIC_HALF_H - 34.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_mic, "rotation_degrees", 55.0, 0.16)
	# ...and coming down flat on its side.
	tw.tween_property(_mic, "position:y", FLOOR_Y - MIC_HALF_W, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_mic, "rotation_degrees", 90.0, 0.14)
	tw.tween_callback(_reveal)


## "MIC DROP" detonates on impact: born small at dead center, blown up until
## it spans the whole screen while fading out. Freed once invisible.
func _blast_text() -> void:
	var l := Label.new()
	l.text = "MIC DROP"
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	add_child(l)
	l.reset_size()
	var view := get_viewport_rect().size
	l.position = (view - l.size) / 2.0
	l.pivot_offset = l.size / 2.0
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE * (view.x / maxf(l.size.x, 1.0)), 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Alpha eases IN: legible while small, gone as it fills the screen.
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


func _shake() -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(self, "position",
			Vector2(randf_range(-SHAKE_PX, SHAKE_PX), randf_range(-SHAKE_PX, SHAKE_PX)), 0.04)
	tw.tween_property(self, "position", Vector2.ZERO, 0.04)


## GAME OVER slams in oversized while the rest of the screen fades up.
## No SFX here — "defeat" already rang when the player hit the floor.
func _reveal() -> void:
	_box.visible = true
	_dancer.visible = true
	_back_btn.visible = true
	_box.modulate.a = 0.0
	_dancer.modulate.a = 0.0
	_back_btn.modulate.a = 0.0
	# Scaling a Control inside a VBox only transforms its paint, not the
	# layout, so the slam doesn't shove the column around — but it needs the
	# pivot centered or it grows from the top-left corner.
	_title.pivot_offset = _title.size / 2.0
	_title.scale = Vector2(2.6, 2.6)
	var tw := create_tween()
	tw.tween_property(_box, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(_dancer, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(_back_btn, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(_title, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
