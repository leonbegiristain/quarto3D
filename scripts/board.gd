class_name Board
extends Node3D

## The 4x4x4 lattice. Each of the 64 vertices can hold one piece, and any one
## of them can be selected to isolate the lines running through it.
##
## Nothing here knows the rules - it is storage plus visuals. The seams
## gameplay will plug into are place_piece() / remove_piece(); the line
## geometry itself lives in BoardLines.

const GRID := BoardLines.GRID
const SPACING := 1.45
## Radius of the tap target around a cell centre. Stays below SPACING * 0.5 so
## the targets of neighbouring cells cannot overlap.
const PICK_RADIUS := 0.55
## Empty slot dots are tiny, so they need a big multiplier to read as
## hovered at all - unlike a piece, which only needs a nudge.
const MARKER_EMPHASIS_SCALE := 3.6
## Borrowed from PieceView so a dot and a piece swell at the same rate.
const MARKER_EMPHASIS_TIME := PieceView.EMPHASIS_TIME
## Lattice opacity at rest, and while connections are on screen. The grid
## stays for context but steps back so the highlight reads over it.
const LATTICE_ALPHA := 0.26
const LATTICE_ALPHA_ISOLATED := 0.08
const LATTICE_FADE_TIME := 0.2
## The finished line, gold rather than the isolation cyan so that a win can
## never be mistaken for a selection.
const WIN_COLOR := Color(1.0, 0.82, 0.30, 1.0)
## How far a piece off the finished line steps back.
const WIN_DIM_FADE := 0.78
const NO_CELL := Vector3i(-1, -1, -1)
const PIECE_SCENE: PackedScene = preload("res://scenes/piece.tscn")

signal selection_changed(cell: Vector3i)
signal hover_changed(cell: Vector3i)

## A real game starts empty. The scatter stays one inspector click away, for
## looking at a full board without playing one.
@export var demo_fill := false
@export_range(0, 64) var demo_count := 12
@export var demo_seed := 20260920

var _pieces: Dictionary = {}  # Vector3i -> PieceView
var _selected := NO_CELL
var _hovered := NO_CELL
var _lattice: MeshInstance3D
var _lattice_material: StandardMaterial3D
var _lattice_tween: Tween
## Current scale of each slot dot, indexed like the MultiMesh instances.
## The dots have no node of their own, so this is what gets tweened.
var _marker_scales := PackedFloat32Array()
var _marker_tweens: Dictionary = {}  # Vector3i -> Tween
var _preview: PieceView
var _preview_cell := NO_CELL
var _highlight: MeshInstance3D
var _highlight_material: StandardMaterial3D
var _win_highlight: MeshInstance3D
var _win_material: StandardMaterial3D
## Cells on a finished line, as a set. Empty until the game is won, and what
## _apply_isolation() reads to decide which pieces step back.
var _win_cells: Dictionary = {}
var _markers: MultiMeshInstance3D
var _piece_root: Node3D


## Local position of a lattice vertex. The grid is centred on the board origin.
static func cell_to_local(cell: Vector3i) -> Vector3:
	return (Vector3(cell) - Vector3.ONE * (GRID - 1) * 0.5) * SPACING


static func is_valid_cell(cell: Vector3i) -> bool:
	return BoardLines.is_valid_cell(cell)


## Half the width of the lattice, for framing the camera.
static func extent() -> float:
	return (GRID - 1) * SPACING * 0.5


func _ready() -> void:
	_build_lattice()
	_build_markers()
	_build_highlight_nodes()
	_piece_root = Node3D.new()
	_piece_root.name = "Pieces"
	add_child(_piece_root)
	if demo_fill:
		_place_demo_pieces()
	_apply_isolation()


# --- pieces ------------------------------------------------------------------

func place_piece(cell: Vector3i, traits: PieceTraits) -> PieceView:
	if not is_valid_cell(cell):
		push_error("Board.place_piece: cell out of range: %s" % cell)
		return null
	remove_piece(cell)
	var piece: PieceView = PIECE_SCENE.instantiate()
	_piece_root.add_child(piece)
	piece.traits = traits
	piece.position = cell_to_local(cell)
	# Carry on from the orientation the preview was showing, so committing a
	# placement never snaps the piece round.
	if _preview_shows(cell, traits):
		piece.set_spin_angle(_preview.get_spin_angle())
	_pieces[cell] = piece
	_apply_isolation()
	return piece


func remove_piece(cell: Vector3i) -> void:
	if not _pieces.has(cell):
		return
	var piece: PieceView = _pieces[cell]
	_pieces.erase(cell)
	piece.queue_free()
	_apply_isolation()


func get_piece(cell: Vector3i) -> PieceView:
	return _pieces.get(cell) as PieceView


## Trait ids currently on the board, as a set keyed by id. The board is the
## single source of truth for which pieces are spent; the panel reads this
## rather than keeping a second tally of its own.
func placed_ids() -> Dictionary:
	var ids: Dictionary = {}
	for cell in _pieces:
		var piece: PieceView = _pieces[cell]
		if piece.traits != null:
			ids[piece.traits.id] = true
	return ids


## Trait id at each filled cell. The rules read the board through this rather
## than reaching into the piece nodes, which is what lets WinCheck run without
## a scene at all.
func occupancy() -> Dictionary:
	var filled: Dictionary = {}
	for cell in _pieces:
		var piece: PieceView = _pieces[cell]
		if piece.traits != null:
			filled[cell] = piece.traits.id
	return filled


func clear() -> void:
	for cell in _pieces.keys():
		remove_piece(cell)


## A translucent stand-in for a piece being considered for a cell. It lives
## outside _pieces on purpose, so it counts for nothing: not placed_ids(),
## not occupancy, not picking, not isolation.
func set_preview(traits: PieceTraits, cell: Vector3i) -> void:
	if traits == null or not is_valid_cell(cell) or _pieces.has(cell):
		clear_preview()
		return
	if _preview == null:
		_preview = PIECE_SCENE.instantiate()
		_piece_root.add_child(_preview)
	_preview.traits = traits
	_preview.set_preview(true)
	_preview.name = "Preview"
	_preview.position = cell_to_local(cell)
	_preview.visible = true
	_preview_cell = cell


## True when the preview is currently showing exactly this piece in this
## cell, and its orientation is therefore worth carrying over.
func _preview_shows(cell: Vector3i, traits: PieceTraits) -> bool:
	if _preview == null or not _preview.visible or _preview_cell != cell:
		return false
	return _preview.traits != null and _preview.traits.id == traits.id


func clear_preview() -> void:
	if _preview != null:
		_preview.visible = false
	_preview_cell = NO_CELL


# --- selection ---------------------------------------------------------------

func get_selected() -> Vector3i:
	return _selected


func select_cell(cell: Vector3i) -> void:
	if not is_valid_cell(cell) or cell == _selected:
		return
	_selected = cell
	_apply_isolation()
	selection_changed.emit(_selected)


func clear_selection() -> void:
	if _selected == NO_CELL:
		return
	_selected = NO_CELL
	_apply_isolation()
	selection_changed.emit(_selected)


## Tapping the selected cell again clears it; tapping another moves the focus.
func toggle_cell(cell: Vector3i) -> void:
	if cell == _selected:
		clear_selection()
	else:
		select_cell(cell)


func get_hovered() -> Vector3i:
	return _hovered


## Marks the cell under the pointer, which swells to signal what a tap
## would hit: the piece if the cell holds one, otherwise the slot dot.
func set_hovered(cell: Vector3i) -> void:
	var next := cell if is_valid_cell(cell) else NO_CELL
	if next == _hovered:
		return
	var previous := _hovered
	_hovered = next
	_set_piece_emphasis(previous, false)
	_set_piece_emphasis(_hovered, true)
	_animate_marker(previous, 1.0)
	_animate_marker(_hovered, MARKER_EMPHASIS_SCALE)
	hover_changed.emit(_hovered)


func _set_piece_emphasis(cell: Vector3i, on: bool) -> void:
	var piece := get_piece(cell)
	if piece != null:
		piece.set_emphasised(on)


## A dot lives inside a MultiMesh, so there is no node to tween. Its scale
## is animated as a plain number and written back into the instance
## transform on each step, which is what lets it ease like a piece does.
func _animate_marker(cell: Vector3i, target: float) -> void:
	if not is_valid_cell(cell):
		return
	var running: Tween = _marker_tweens.get(cell)
	if running != null and running.is_valid():
		running.kill()
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_method(_set_marker_scale.bind(cell),
		_marker_scales[_cell_to_index(cell)], target, MARKER_EMPHASIS_TIME)
	_marker_tweens[cell] = tween


func _set_marker_scale(value: float, cell: Vector3i) -> void:
	_marker_scales[_cell_to_index(cell)] = value
	_update_marker(cell)


## Nearest cell whose tap target the ray passes through, or NO_CELL on a miss.
##
## Pure maths over the 64 centres rather than collision shapes, so an empty
## vertex is exactly as clickable as an occupied one and there is nothing to
## keep in sync as pieces come and go.
func pick_cell(ray_origin: Vector3, ray_direction: Vector3) -> Vector3i:
	var to_local := global_transform.affine_inverse()
	var origin := to_local * ray_origin
	var direction := (to_local.basis * ray_direction).normalized()

	var best := NO_CELL
	var best_distance := INF
	for index in GRID * GRID * GRID:
		var cell := _index_to_cell(index)
		var offset := cell_to_local(cell) - origin
		var along := offset.dot(direction)
		if along < 0.0:
			continue  # behind the camera
		if offset.distance_to(direction * along) > PICK_RADIUS:
			continue
		# Nearest along the ray wins: that is the one in front, which is the
		# one the user is looking at.
		if along < best_distance:
			best_distance = along
			best = cell
	return best


## Single source of truth for what is on screen. Isolating hides only the
## pieces that are off the line - the lattice stays put, so the highlighted
## connections read against the grid they belong to rather than floating in
## empty space.
func _apply_isolation() -> void:
	var isolating := _selected != NO_CELL
	var visible_cells: Dictionary = {}
	if isolating:
		visible_cells = BoardLines.cells_in_line_with(_selected)

	# A finished game dims everything off the winning line, so the four that
	# made it are the only pieces left at full strength.
	var celebrating := not _win_cells.is_empty()

	for cell in _pieces:
		var piece: PieceView = _pieces[cell]
		piece.visible = not isolating or visible_cells.has(cell)
		piece.set_fade(WIN_DIM_FADE if celebrating and not _win_cells.has(cell) else 0.0)

	# After the pieces, because a marker stands in for whatever is not there.
	_refresh_markers()
	_fade_lattice(LATTICE_ALPHA_ISOLATED if isolating or celebrating else LATTICE_ALPHA)

	if _highlight != null:
		_highlight.visible = isolating
		if isolating:
			_build_highlight()


# --- visuals -----------------------------------------------------------------

## The lattice, the isolation highlight and the win highlight are all the same
## thing: flat translucent lines that ignore the scene lighting. One builder,
## so they cannot drift apart in how they are set up.
static func _line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	return material


func _build_line_node(node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = ImmediateMesh.new()
	node.visible = false
	add_child(node)
	return node


## The 48 lattice lines: 16 per axis, drawn as a single line mesh.
func _build_lattice() -> void:
	_lattice_material = _line_material(Color(0.64, 0.72, 0.86, LATTICE_ALPHA))

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _lattice_material)
	var last := GRID - 1
	for a in GRID:
		for b in GRID:
			mesh.surface_add_vertex(cell_to_local(Vector3i(0, a, b)))
			mesh.surface_add_vertex(cell_to_local(Vector3i(last, a, b)))
			mesh.surface_add_vertex(cell_to_local(Vector3i(a, 0, b)))
			mesh.surface_add_vertex(cell_to_local(Vector3i(a, last, b)))
			mesh.surface_add_vertex(cell_to_local(Vector3i(a, b, 0)))
			mesh.surface_add_vertex(cell_to_local(Vector3i(a, b, last)))
	mesh.surface_end()

	_lattice = MeshInstance3D.new()
	_lattice.name = "Lattice"
	_lattice.mesh = mesh
	add_child(_lattice)


## Faded rather than switched, so the grid recedes instead of popping.
func _fade_lattice(target_alpha: float) -> void:
	if _lattice_material == null:
		return
	if is_equal_approx(_lattice_material.albedo_color.a, target_alpha):
		return
	if _lattice_tween != null and _lattice_tween.is_valid():
		_lattice_tween.kill()
	_lattice_tween = create_tween()
	_lattice_tween.tween_property(
		_lattice_material, "albedo_color:a", target_alpha, LATTICE_FADE_TIME)


## One faint dot per empty vertex, all 64 in a single MultiMesh draw.
func _build_markers() -> void:
	var material := _line_material(Color(0.82, 0.88, 1.0, 0.42))

	var dot := SphereMesh.new()
	dot.radius = 0.045
	dot.height = 0.09
	dot.radial_segments = 8
	dot.rings = 4
	dot.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = dot
	multimesh.instance_count = GRID * GRID * GRID

	_marker_scales.resize(multimesh.instance_count)
	_marker_scales.fill(1.0)

	_markers = MultiMeshInstance3D.new()
	_markers.name = "SlotMarkers"
	_markers.multimesh = multimesh
	add_child(_markers)


## A marker stands in for any vertex without a visible piece on it. During an
## isolation that includes cells whose pieces are hidden, so the grid keeps
## all 64 vertices instead of developing holes.
func _refresh_markers() -> void:
	if _markers == null:
		return
	for index in _markers.multimesh.instance_count:
		_update_marker(_index_to_cell(index))


## The one place an instance transform is written. Size comes from the
## animated scale, so a refresh mid-tween never stamps on the animation.
## Hidden dots are scaled to zero rather than removed, keeping the instance
## count fixed and the indices stable.
func _update_marker(cell: Vector3i) -> void:
	if _markers == null:
		return
	var index := _cell_to_index(cell)
	var piece := get_piece(cell)
	var size := 0.0
	if piece == null or not piece.visible:
		size = _marker_scales[index]
	_markers.multimesh.set_instance_transform(index,
		Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), cell_to_local(cell)))


func _build_highlight_nodes() -> void:
	_highlight_material = _line_material(Color(0.30, 0.80, 1.0, 1.0))
	_highlight = _build_line_node("Highlight")
	_win_material = _line_material(WIN_COLOR)
	_win_highlight = _build_line_node("WinHighlight")


## The lines through the selected cell - diagonals included, which is where
## they become visible. The cell itself needs no mark of its own: it is
## where every highlighted line meets.
func _build_highlight() -> void:
	var mesh: ImmediateMesh = _highlight.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _highlight_material)
	for line in BoardLines.lines_through(_selected):
		mesh.surface_add_vertex(cell_to_local(line[0]))
		mesh.surface_add_vertex(cell_to_local(line[line.size() - 1]))
	mesh.surface_end()


# --- win highlight -----------------------------------------------------------

## Marks the finished line or lines in gold. Everything else about the look of
## a won board - the dimmed pieces, the receding lattice - is left to
## _apply_isolation(), which stays the one place that decides what is on
## screen; this only records which cells won and asks it to run again.
func set_win_highlight(lines: Array[Array]) -> void:
	_win_cells.clear()
	var mesh: ImmediateMesh = _win_highlight.mesh
	mesh.clear_surfaces()
	if not lines.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, _win_material)
		for line in lines:
			for cell in line:
				_win_cells[cell] = true
			mesh.surface_add_vertex(cell_to_local(line[0]))
			mesh.surface_add_vertex(cell_to_local(line[line.size() - 1]))
		mesh.surface_end()
	_win_highlight.visible = not _win_cells.is_empty()
	_apply_isolation()


func clear_win_highlight() -> void:
	var none: Array[Array] = []
	set_win_highlight(none)


## Cells on a finished line. Empty while the game is still running.
func win_cells() -> Dictionary:
	return _win_cells.duplicate()


# --- indexing and demo content -----------------------------------------------

static func _cell_to_index(cell: Vector3i) -> int:
	return (cell.x * GRID + cell.y) * GRID + cell.z


static func _index_to_cell(index: int) -> Vector3i:
	return Vector3i(index / (GRID * GRID), (index / GRID) % GRID, index % GRID)


## A deterministic scatter of distinct pieces, so the lattice reads as a board
## straight away. Turn demo_fill off for a clean empty grid.
func _place_demo_pieces() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = demo_seed

	var cells: Array[Vector3i] = []
	for i in GRID * GRID * GRID:
		cells.append(_index_to_cell(i))
	var ids: Array[int] = []
	for i in PieceTraits.COUNT:
		ids.append(i)
	_shuffle(cells, rng)
	_shuffle(ids, rng)

	var count := mini(demo_count, mini(cells.size(), ids.size()))
	for i in count:
		place_piece(cells[i], PieceTraits.from_id(ids[i]))


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = items[i]
		items[i] = items[j]
		items[j] = swap
