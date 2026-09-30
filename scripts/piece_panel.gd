class_name PiecePanel
extends PanelContainer

## All 64 pieces as a fixed 8x8 HUD grid on the right of the screen.
##
## The pieces live in a SubViewport with its own World3D and its own
## orthographic camera. That is what makes the panel immune to the orbit rig:
## the main camera is not in this world at all, so there is nothing to
## compensate for.
##
## The grid is four 4x4 blocks with a gap between them: cubes on the left,
## spheres on the right, small on top, big below. Inside a block, columns run
## white solid, white hollow, black solid, black hollow, and rows run plain
## still, plain spinning, spotted still, spotted spinning. So every piece has
## one fixed home that can be found by reading its properties off the axes.
##
## This is also where a piece is picked up. Clicking an available piece selects
## it, clicking it again puts it back. A piece already on the board is ghosted
## in place and cannot be picked.
##
## A property filter can hide pieces in place. The grid never reflows, so a
## piece is always in its home slot whether or not its neighbours are shown.

const COLUMNS := 8
const ROWS := 8
## Slots per block along each axis. The gap after every block is what makes
## the grid read as four groups rather than one field of 64.
const BLOCK := 4
const SPACING := 1.25
const BLOCK_GAP := 0.5
## Border around the grid inside the panel, in world units.
const FRAME_MARGIN := 0.25
## Three-quarter tilt, so a cube reads as a cube rather than a flat square
## against a head-on orthographic camera. Positive X brings the top face
## toward the viewer, matching how the board is framed from above.
const PIECE_TILT := Vector3(0.42, 0.62, 0.0)
const NO_PIECE := -1
const PIECE_SCENE: PackedScene = preload("res://scenes/piece.tscn")

## Carries the held piece, or null when nothing is held.
signal selection_changed(traits: PieceTraits)

var _piece_by_id: Dictionary = {}  # int -> PieceView
var _available: Dictionary = {}  # int -> bool
var _selected_id := NO_PIECE
var _hovered_id := NO_PIECE
var _locked := false
## A piece passes the filter when it has every bit in _must_set and none in
## _must_clear. Both zero means no filter.
var _must_set := 0
var _must_clear := 0

@onready var _viewport_container: SubViewportContainer = $Viewport
@onready var _camera: Camera3D = $Viewport/SubViewport/Camera3D
@onready var _piece_root: Node3D = $Viewport/SubViewport/Pieces
@onready var _highlight: MeshInstance3D = $Viewport/SubViewport/Highlight


## Grid slot for a piece. Shape picks the left or right half and size the top
## or bottom half; the other four bits place it inside that block.
static func slot_for(traits: PieceTraits) -> Vector2i:
	var column := int(traits.is_sphere) * 4 + int(traits.is_black) * 2 + int(traits.is_hollow)
	var row := int(traits.is_big) * 4 + int(traits.is_spotted) * 2 + int(traits.is_spinning)
	return Vector2i(column, row)


## Centre of a slot in the panel world. Row 0 is at the top.
static func slot_position(slot: Vector2i) -> Vector3:
	return Vector3(_axis_offset(slot.x, COLUMNS), -_axis_offset(slot.y, ROWS), 0.0)


@warning_ignore("integer_division")
static func _axis_offset(index: int, count: int) -> float:
	var gaps := (count - 1) / BLOCK
	var span := (count - 1) * SPACING + gaps * BLOCK_GAP
	return index * SPACING + (index / BLOCK) * BLOCK_GAP - span * 0.5


func _ready() -> void:
	_highlight.visible = false
	mouse_exited.connect(_on_mouse_exited)
	_viewport_container.resized.connect(_frame_camera)
	_build_pieces()
	_frame_camera()


# --- selection ---------------------------------------------------------------

func get_selected_id() -> int:
	return _selected_id


func get_selected_traits() -> PieceTraits:
	if _selected_id == NO_PIECE:
		return null
	return PieceTraits.from_id(_selected_id)


func select(id: int) -> void:
	if not is_available(id) or id == _selected_id:
		return
	_selected_id = id
	_refresh_highlight()
	_refresh_visibility()
	selection_changed.emit(get_selected_traits())


func clear_selection() -> void:
	if _selected_id == NO_PIECE:
		return
	_selected_id = NO_PIECE
	_refresh_highlight()
	_refresh_visibility()
	selection_changed.emit(null)


## Clicking the held piece again puts it back.
func toggle(id: int) -> void:
	if id == _selected_id:
		clear_selection()
	else:
		select(id)


# --- availability ------------------------------------------------------------

func is_available(id: int) -> bool:
	return bool(_available.get(id, false))


## Driven from the board by main, never maintained here - see
## Main._sync_panel_availability().
func set_available(id: int, available: bool) -> void:
	if not _piece_by_id.has(id) or _available.get(id) == available:
		return
	_available[id] = available
	var piece: PieceView = _piece_by_id[id]
	piece.set_ghosted(not available)
	if available:
		return
	piece.set_emphasised(false)
	if _hovered_id == id:
		_hovered_id = NO_PIECE
	if _selected_id == id:
		clear_selection()


# --- filter ------------------------------------------------------------------

## Show only the pieces that have every bit in `must_set` and none of the bits
## in `must_clear`. This only changes what is drawn: availability and the
## selection are untouched.
func set_filter(must_set: int, must_clear: int) -> void:
	_must_set = must_set
	_must_clear = must_clear
	_refresh_visibility()


func passes_filter(id: int) -> bool:
	return (id & _must_set) == _must_set and (id & _must_clear) == 0


## The selected piece is always shown, whatever the filter says. Otherwise a
## filter could hide the piece you are about to give or place.
func is_shown(id: int) -> bool:
	return id == _selected_id or passes_filter(id)


# --- locking -----------------------------------------------------------------

func is_locked() -> bool:
	return _locked


## A locked panel is a display only. Once a piece has been handed over it is
## not negotiable, so clicks and hover do nothing until the phase comes round
## again. Programmatic select() still works: this gates input, not state.
func set_locked(locked: bool) -> void:
	if _locked == locked:
		return
	_locked = locked
	if locked:
		_set_hovered(NO_PIECE)


## Cyan while a piece is only being considered, the active player's colour
## once it has been handed over, so the panel itself says which half of the
## turn the game is in without a second label to read.
func set_highlight_color(color: Color) -> void:
	var material := _highlight.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color


# --- picking and input -------------------------------------------------------

## Nearest piece to a point inside the panel, or NO_PIECE on a miss.
##
## Unprojecting through the panel camera rather than re-deriving the
## orthographic mapping by hand keeps the hit test welded to what is actually
## drawn. 64 unprojections per click costs nothing.
func pick_id_at(local_position: Vector2) -> int:
	# _gui_input reports positions local to this PanelContainer, and the
	# viewport sits inset by the style box content margin.
	var viewport_position := local_position - _viewport_container.position
	var best := NO_PIECE
	var best_distance := pick_radius()
	for id in _piece_by_id:
		if not is_shown(id):
			continue
		var piece: PieceView = _piece_by_id[id]
		var distance := _camera.unproject_position(piece.position).distance_to(viewport_position)
		if distance >= best_distance:
			continue
		best_distance = distance
		best = id
	return best


## Click radius around a piece, in SubViewport pixels: half the on-screen
## distance between two neighbouring slots, so targets can never overlap.
## Measured through the camera rather than stored, so it follows the panel
## size.
func pick_radius() -> float:
	var a := _camera.unproject_position(Vector3.ZERO)
	var b := _camera.unproject_position(Vector3(SPACING, 0.0, 0.0))
	return a.distance_to(b) * 0.5


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if not _locked:
				var id := pick_id_at(event.position)
				if id != NO_PIECE and is_available(id):
					toggle(id)
			# Swallowed even while locked, or the click falls through to the orbit
			# rig and lands as a tap on the board behind the panel.
			accept_event()
	elif event is InputEventMouseMotion and not _locked:
		_set_hovered(pick_id_at(event.position))


func _set_hovered(id: int) -> void:
	var next := id if is_available(id) and is_shown(id) else NO_PIECE
	if next == _hovered_id:
		return
	if _piece_by_id.has(_hovered_id):
		(_piece_by_id[_hovered_id] as PieceView).set_emphasised(false)
	_hovered_id = next
	if _piece_by_id.has(_hovered_id):
		(_piece_by_id[_hovered_id] as PieceView).set_emphasised(true)


func _on_mouse_exited() -> void:
	_set_hovered(NO_PIECE)


# --- build -------------------------------------------------------------------

## Fit the whole grid inside the panel, whichever way round the panel is. An
## orthographic camera's size is its height, so a panel narrower than the grid
## needs a taller view to fit the width.
func _frame_camera() -> void:
	var view := _viewport_container.size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	# Outermost slot centres, plus a full slot so the edge pieces fit too.
	var width := -2.0 * _axis_offset(0, COLUMNS) + SPACING + FRAME_MARGIN * 2.0
	var height := -2.0 * _axis_offset(0, ROWS) + SPACING + FRAME_MARGIN * 2.0
	_camera.size = maxf(height, width * view.y / view.x)


func _refresh_visibility() -> void:
	for id in _piece_by_id:
		(_piece_by_id[id] as PieceView).visible = is_shown(id)
	if _hovered_id != NO_PIECE and not is_shown(_hovered_id):
		_set_hovered(NO_PIECE)


func _refresh_highlight() -> void:
	_highlight.visible = _selected_id != NO_PIECE
	if not _highlight.visible:
		return
	var piece: PieceView = _piece_by_id[_selected_id]
	# Behind the piece, so the tile reads as the slot rather than a veil.
	_highlight.position = Vector3(piece.position.x, piece.position.y, -0.9)


func _build_pieces() -> void:
	var all_traits := PieceTraits.all()
	assert(all_traits.size() == PieceTraits.COUNT, "PieceTraits.all() must produce 64 pieces")

	var seen: Dictionary = {}
	for traits in all_traits:
		var slot := slot_for(traits)
		assert(not seen.has(slot), "Two pieces claim panel slot %s" % slot)
		seen[slot] = traits.id

		var piece: PieceView = PIECE_SCENE.instantiate()
		_piece_root.add_child(piece)
		piece.traits = traits
		piece.position = slot_position(slot)
		# Safe to set on the root: PieceView spins its mesh child and only ever
		# writes scale here, so a spinning piece spins inside the tilt.
		piece.rotation = PIECE_TILT

		_piece_by_id[traits.id] = piece
		_available[traits.id] = true
	assert(seen.size() == PieceTraits.COUNT, "Panel must hold all 64 distinct pieces")
