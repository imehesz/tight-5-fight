extends MenuBase
## Game Over: final score, high-score callout, replay / menu options,
## plus the just-played character dancing it off on the left.

## Dance poses: walk cycle and "hit" (arms flung up in the air).
const DANCE_ANIMS := ["walk", "hit"]
## 1.5x the in-game fighter size.
const DANCE_SCALE := Fighter.BODY_SCALE * 1.5
const DANCE_FEET_POS := Vector2(110, 330)

var _body: AnimatedSprite2D
var _head: Sprite2D
var _head_offset := Vector2.ZERO
var _dance_timer: Timer


func _ready() -> void:
	var box := build_backdrop(MENU_BG)
	add_title(box, "GAME OVER", 24, Color(0.95, 0.3, 0.25))
	add_text(box, "%s bombed after %d venue%s." % [
		String(GameState.selected_character_data().get("CharacterName", "You")),
		GameState.venues_entered,
		"" if GameState.venues_entered == 1 else "s",
	])
	add_spacer(box, 8)
	add_title(box, "FINAL SCORE: %d" % GameState.score, 14, Color(0.9, 0.9, 0.95))
	if GameState.last_run_rank >= 0:
		add_title(box, "NEW HIGH SCORE — #%d!" % (GameState.last_run_rank + 1), 10)
	add_spacer(box, 14)
	add_button(box, "PLAY AGAIN", func(): GameState.change_scene(GameState.SCENE_CHARACTER_SELECT))
	add_button(box, "SCOREBOARD", func(): GameState.change_scene(GameState.SCENE_SCOREBOARD))
	add_button(box, "MAIN MENU", func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
	_build_dancer()


## Rebuild the played character (body + socketed head, like Fighter does)
## and let them dance: random walk / arms-up poses, head glancing left/right.
func _build_dancer() -> void:
	var cfg := GameState.selected_character_data()
	var dancer := Node2D.new()
	dancer.position = DANCE_FEET_POS
	dancer.scale = Vector2(DANCE_SCALE, DANCE_SCALE)
	add_child(dancer)

	_body = AnimatedSprite2D.new()
	_body.sprite_frames = CharacterFactory.body_frames(
			String(cfg.get("BodyType", "M")),
			Color.from_string(String(cfg.get("SkinColor", "")),
					CharacterFactory.DEFAULT_SKIN))
	_body.offset = Vector2(0, -CharacterFactory.FRAME_H / 2.0)
	dancer.add_child(_body)

	_head = Sprite2D.new()
	_head.texture = CharacterFactory.head_texture(String(cfg.get("HeadSpritePath", "")))
	var s := Fighter.HEAD_SCALE * maxf(float(cfg.get("HeadScale", 1.0)), 0.1) \
			* (Fighter.HEAD_BASE_PX / maxf(_head.texture.get_width(), 1.0))
	_head.scale = Vector2(s, s)
	_head_offset = Vector2(float(cfg.get("HeadOffsetX", 0)), float(cfg.get("HeadOffsetY", 0)))
	dancer.add_child(_head)

	_dance_timer = Timer.new()
	_dance_timer.one_shot = true
	_dance_timer.timeout.connect(_dance_step)
	add_child(_dance_timer)
	_dance_step()


func _dance_step() -> void:
	var anim: String = DANCE_ANIMS.pick_random()
	_body.play(anim)
	_head.flip_h = randi() % 2 == 0
	var neck := CharacterFactory.head_offset(anim)
	var lift := _head.texture.get_height() * _head.scale.y / 2.0 - 4.0
	_head.position = Vector2(neck.x + _head_offset.x, neck.y - lift + _head_offset.y)
	_dance_timer.start(randf_range(0.4, 0.9))
