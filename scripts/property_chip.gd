class_name PropertyChip
extends Button

## One filter chip for one property bit. A tap cycles through three states:
## any, only the first side, only the second side (for bit 0: any, cube,
## sphere). The glyph is drawn in code, and the word underneath comes from
## PieceTraits.PROPERTY_NAMES, so the chip uses the same words as the rest of
## the game.

enum State { ANY, CLEAR, SET }

const INK := Color(0.92, 0.94, 0.98)
const DARK := Color(0.1, 0.11, 0.14)
const SPOT := Color(0.98, 0.84, 0.25)
const ACCENT := Color(0.72, 0.88, 1.0, 0.9)
const WORD_SIZE := 17
## Both sides share the glyph area while the chip is at "any", drawn smaller
## and dimmer so a set chip stands out from across the row.
const ANY_SCALE := 0.62
const ANY_ALPHA := 0.55

signal state_changed

var bit := 0
var state := State.ANY:
	set(value):
		state = value
		queue_redraw()


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(88, 72)
	pressed.connect(_on_pressed)


## The word under the glyph: "any", or the property word for the chosen side.
func word() -> String:
	if state == State.ANY:
		return "any"
	return PieceTraits.PROPERTY_NAMES[bit][int(state == State.SET)]


func _on_pressed() -> void:
	state = ((state + 1) % 3) as State
	state_changed.emit()


func _draw() -> void:
	var centre := Vector2(size.x * 0.5, size.y * 0.4)
	var radius := minf(size.x, size.y) * 0.2
	if state == State.ANY:
		var shift := Vector2(radius * 1.05, 0.0)
		_draw_glyph(0, centre - shift, radius * ANY_SCALE, ANY_ALPHA)
		_draw_glyph(1, centre + shift, radius * ANY_SCALE, ANY_ALPHA)
	else:
		_draw_glyph(int(state == State.SET), centre, radius, 1.0)
		draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), ACCENT, false, 2.0)

	var font := get_theme_font("font")
	var alpha := 1.0 if state != State.ANY else ANY_ALPHA
	draw_string(font, Vector2(0.0, size.y - 9.0), word(), HORIZONTAL_ALIGNMENT_CENTER,
		size.x, WORD_SIZE, Color(INK, alpha))


## One side of this chip's property. Side 0 is the bit clear, side 1 set, in
## the same order as PROPERTY_NAMES.
func _draw_glyph(side: int, c: Vector2, r: float, alpha: float) -> void:
	var ink := Color(INK, alpha)
	match bit:
		0:  # cube / sphere
			if side == 0:
				draw_rect(Rect2(c - Vector2.ONE * r * 0.85, Vector2.ONE * r * 1.7), ink)
			else:
				draw_circle(c, r, ink, true, -1.0, true)
		1:  # white / black
			draw_circle(c, r, ink if side == 0 else Color(DARK, alpha), true, -1.0, true)
			draw_arc(c, r, 0.0, TAU, 32, ink, 1.5, true)
		2:  # small / big
			draw_circle(c, r * (0.5 if side == 0 else 1.0), ink, true, -1.0, true)
		3:  # solid / hollow
			if side == 0:
				draw_circle(c, r, ink, true, -1.0, true)
			else:
				draw_arc(c, r * 0.85, 0.0, TAU, 32, ink, r * 0.3, true)
		4:  # plain / spotted
			draw_circle(c, r, ink, true, -1.0, true)
			if side == 1:
				var spot := Color(SPOT, alpha)
				for offset in [Vector2(-0.4, -0.35), Vector2(0.38, -0.2), Vector2(-0.15, 0.42), Vector2(0.3, 0.45)]:
					draw_circle(c + offset * r, r * 0.17, spot, true, -1.0, true)
		5:  # still / spinning
			if side == 0:
				draw_arc(c, r * 0.8, 0.0, TAU, 32, ink, r * 0.22, true)
			else:
				# Three quarters of a ring, plus an arrowhead at the open end.
				var ring := r * 0.8
				draw_arc(c, ring, 0.0, TAU * 0.75, 32, ink, r * 0.22, true)
				var tip := c + Vector2(cos(TAU * 0.75), sin(TAU * 0.75)) * ring
				draw_colored_polygon(PackedVector2Array([
					tip + Vector2(r * 0.45, 0.0),
					tip + Vector2(-r * 0.1, -r * 0.4),
					tip + Vector2(-r * 0.1, r * 0.4),
				]), ink)
