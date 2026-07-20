class_name BarStool
extends Node2D
## A classic four-leg bar stool, drawn rather than textured (no art needed).
##
## Geometry is anchored at the LEG TIPS (origin), with the seat up at
## -STOOL_LEN. That one orientation serves both users: standing on the floor
## next to the boss it just sits at rotation 0, and in his hands StoolSwing
## puts the origin at his shoulder and rotates it — he grips it by the legs
## and the seat is the striking end.

## Grip-to-seat length. A real bar stool is roughly two thirds of a person;
## the boss body is 48 local px tall.
const STOOL_LEN := 34.0
const SEAT_W := 20.0
const SEAT_H := 5.0
## Legs splay wider than the seat at the floor end, or it reads as a table.
const LEG_SPREAD := SEAT_W * 0.62
const WOOD := Color(0.58, 0.37, 0.19)
const WOOD_DARK := Color(0.30, 0.18, 0.08)


func _draw() -> void:
	var seat_y := -STOOL_LEN
	var ring_y := seat_y * 0.34   # footrest ring, low on the legs
	# Four legs as two outer pairs, so the splay reads from any angle.
	for sx in [-1.0, 1.0]:
		for inset in [1.0, 0.55]:
			var top := Vector2(sx * SEAT_W * 0.38 * inset, seat_y)
			var bottom := Vector2(sx * LEG_SPREAD * inset, 0.0)
			draw_line(top, bottom, WOOD_DARK, 3.0)
			draw_line(top, bottom, WOOD, 1.6)
	# Footrest ring.
	draw_line(Vector2(-LEG_SPREAD * 0.75, ring_y),
			Vector2(LEG_SPREAD * 0.75, ring_y), WOOD_DARK, 2.4)
	# Seat: dark rim under a lighter top, so it reads as a solid slab.
	draw_rect(Rect2(-SEAT_W / 2.0, seat_y - SEAT_H / 2.0, SEAT_W, SEAT_H),
			WOOD_DARK, true)
	draw_rect(Rect2(-SEAT_W / 2.0 + 1.5, seat_y - SEAT_H / 2.0 + 1.0,
			SEAT_W - 3.0, SEAT_H - 2.5), WOOD, true)
