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
	{"action": "punch", "tex": "res://assets/gen/ui/btn_punch.png", "pos": Vector2(548, 296)},
	{"action": "kick", "tex": "res://assets/gen/ui/btn_kick.png", "pos": Vector2(596, 248)},
]


const DESIGN_W := 640.0
const DESIGN_H := 360.0

var _buttons: Array = []  # [{node, pos}]


func _ready() -> void:
	layer = 90
	for b in BUTTONS:
		var btn := TouchScreenButton.new()
		btn.texture_normal = load(b.tex)
		btn.action = b.action
		btn.scale = Vector2(SCALE, SCALE)
		btn.passby_press = true
		add_child(btn)
		_buttons.append({"node": btn, "pos": b.pos})
	_layout()
	# The OS/browser can report the real window size a frame (or a rotation)
	# after _ready, so re-anchor whenever the viewport changes.
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	for b in _buttons:
		var pos: Vector2 = b.pos
		# Scale each button's DESIGN-space offset from its corner, then hang
		# it off the corresponding LIVE screen corner — on wider-than-design
		# screens the right cluster must follow the real edge.
		var x := pos.x * SCALE if pos.x < DESIGN_W / 2.0 \
				else view.x - (DESIGN_W - pos.x) * SCALE
		var y := view.y - (DESIGN_H - pos.y) * SCALE
		b.node.position = Vector2(x, y)
