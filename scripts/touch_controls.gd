class_name TouchControls
extends CanvasLayer
## Virtual on-screen controls for mobile landscape: D-pad on the left
## (up = enter doors, down = duck), punch/kick buttons on the right.
## Buttons emit the same input actions as the keyboard bindings.

const SCALE := 1.5
## Positions are the original 1x layout for 40px buttons on the 640x360
## viewport; _ready() scales each corner cluster outward from its screen
## corner so margins grow proportionally and nothing hangs off-screen.
const BUTTONS := [
	{"action": "move_left", "tex": "res://assets/gen/ui/btn_left.png", "pos": Vector2(12, 284)},
	{"action": "move_right", "tex": "res://assets/gen/ui/btn_right.png", "pos": Vector2(100, 284)},
	{"action": "interact", "tex": "res://assets/gen/ui/btn_up.png", "pos": Vector2(56, 240)},
	{"action": "duck", "tex": "res://assets/gen/ui/btn_down.png", "pos": Vector2(56, 316)},
	{"action": "punch", "tex": "res://assets/gen/ui/btn_punch.png", "pos": Vector2(536, 296)},
	{"action": "kick", "tex": "res://assets/gen/ui/btn_kick.png", "pos": Vector2(584, 248)},
]


func _ready() -> void:
	layer = 90
	var view := get_viewport().get_visible_rect().size
	for b in BUTTONS:
		var btn := TouchScreenButton.new()
		btn.texture_normal = load(b.tex)
		btn.action = b.action
		btn.scale = Vector2(SCALE, SCALE)
		var anchor := Vector2(0.0 if b.pos.x < view.x / 2.0 else view.x, view.y)
		btn.position = anchor + (b.pos - anchor) * SCALE
		btn.passby_press = true
		add_child(btn)
