class_name PiecePanel
extends PanelContainer

## All 64 pieces as a fixed HUD grid pinned to the right edge of the screen.
##
## The pieces live in a SubViewport with its own World3D and its own
## orthographic camera. That is what makes the panel immune to the orbit rig:
## the main camera is not in this world at all, so there is nothing to
## compensate for.
##
## Columns are shape x colour - white cube, black cube, white sphere, black
## sphere - and rows run through the remaining four bits: small above big,
## solid above hollow, plain above spotted, still above spinning.
##
## This is also where a piece is picked up. Clicking an available piece selects
## it, clicking it again puts it back. A piece already on the board is ghosted
## in place and cannot be picked.

const COLUMNS := 4
const ROWS := 16
const SPACING := 1.25
## Three-quarter tilt, so a cube reads as a cube rather than a flat square
## against a head-on orthographic camera. Positive X brings the top face
## toward the viewer, matching how the board is framed from above.
const PIECE_TILT := Vector3(0.42, 0.62, 0.0)
## Click radius around a piece, in SubViewport pixels. The grid pitch is about
## 41px, so this stays just under half of it and targets cannot overlap.
const PICK_RADIUS := 20.0
const NO_PIECE := -1
const PIECE_SCENE: PackedScene = preload("res://scenes/piece.tscn")

## Carries the held piece, or null when nothing is held.
signal selection_changed(traits: PieceTraits)

var _piece_by_id: Dictionary = {}  # int -> PieceView
var _available: Dictionary = {}  # int -> bool
var _selected_id := NO_PIECE
var _hovered_id := NO_PIECE
var _locked := false

@onready var _viewport_container: SubViewportContainer = $Viewport
@onready var _camera: Camera3D = $Viewport/SubViewport/Camera3D
@onready var _piece_root: Node3D = $Viewport/SubViewport/Pieces
@onready var _highlight: MeshInstance3D = $Viewport/SubViewport/Highlight


## Grid slot for a piece: column from bits 0-1, row from bits 2-5.
static func slot_for(traits: PieceTraits) -> Vector2i:
	var column := int(traits.is_sphere) * 2 + int(traits.is_black)
	var row := int(traits.is_big) * 8 + int(traits.is_hollow) * 4 \
		+ int(traits.is_spotted) * 2 + int(traits.is_spinning)
	return Vector2i(column, row)


func _ready() -> void:
	# The camera frames the grid by height; the panel aspect then decides how
	# much horizontal slack there is. Driven from the constants so the layout
	# has a single source of truth.
	_camera.size = ROWS * SPACING + SPACING * 0.5
	_highlight.visible = false
	mouse_exited.connect(_on_mouse_exited)
	_build_pieces()


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
	selection_changed.emit(get_selected_traits())


func clear_selection() -> void:
	if _selected_id == NO_PIECE:
		return
	_selected_id = NO_PIECE
	_refresh_highlight()
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
	var best_distance := PICK_RADIUS
	for id in _piece_by_id:
		var piece: PieceView = _piece_by_id[id]
		var distance := _camera.unproject_position(piece.position).distance_to(viewport_position)
		if distance >= best_distance:
			continue
		best_distance = distance
		best = id
	return best


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
	var next := id if is_available(id) else NO_PIECE
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
		piece.position = Vector3(
			(slot.x - (COLUMNS - 1) * 0.5) * SPACING,
			-(slot.y - (ROWS - 1) * 0.5) * SPACING,  # negated: row 0 at the top
			0.0)
		# Safe to set on the root: PieceView spins its mesh child and only ever
		# writes scale here, so a spinning piece spins inside the tilt.
		piece.rotation = PIECE_TILT

		_piece_by_id[traits.id] = piece
		_available[traits.id] = true
	assert(seen.size() == PieceTraits.COUNT, "Panel must hold all 64 distinct pieces")
