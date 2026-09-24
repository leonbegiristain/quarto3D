class_name BoardLines
extends RefCounted

## The 76 straight lines of a 4x4x4 grid: 48 along the axes, 24 in-plane
## diagonals and 4 space diagonals.
##
## This is also the Quarto-3D win set, so the same data will serve win
## detection later. Knows nothing about the scene: Board depends on this, never
## the other way round - two class_name scripts referencing each other form a
## cycle.

const GRID := 4
const LINE_LENGTH := GRID
const LINE_COUNT := 76

static var _all_lines: Array[Array] = []
static var _by_cell: Dictionary = {}  # Vector3i -> Array[Array]


static func is_valid_cell(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.x < GRID \
		and cell.y >= 0 and cell.y < GRID \
		and cell.z >= 0 and cell.z < GRID


## Every line, each LINE_LENGTH cells long. Built once, then cached.
static func all_lines() -> Array[Array]:
	if _all_lines.is_empty():
		_all_lines = _build_lines()
	return _all_lines


## The lines that pass through `cell` - between 3 and 7 of them.
static func lines_through(cell: Vector3i) -> Array[Array]:
	if not _by_cell.has(cell):
		var found: Array[Array] = []
		for line in all_lines():
			if line.has(cell):
				found.append(line)
		_by_cell[cell] = found
	var cached: Array[Array] = _by_cell[cell]
	return cached


## The union of every line through `cell`, as a set keyed by Vector3i.
## `cell` itself is included.
static func cells_in_line_with(cell: Vector3i) -> Dictionary:
	var cells: Dictionary = {}
	for line in lines_through(cell):
		for member in line:
			cells[member] = true
	return cells


## One generator for all three families. A direction and its opposite describe
## the same line, so only directions whose first non-zero component is +1 are
## kept, and each line is emitted from the end that has no predecessor in the
## grid. That yields 3x16 axis + 6x4 in-plane + 4x1 space = 76.
static func _build_lines() -> Array[Array]:
	var lines: Array[Array] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var direction := Vector3i(dx, dy, dz)
				if not _is_canonical(direction):
					continue
				for x in GRID:
					for y in GRID:
						for z in GRID:
							var start := Vector3i(x, y, z)
							if is_valid_cell(start - direction):
								continue  # not the head of its line
							if not is_valid_cell(start + direction * (LINE_LENGTH - 1)):
								continue  # runs off the grid
							var line: Array[Vector3i] = []
							for step in LINE_LENGTH:
								line.append(start + direction * step)
							lines.append(line)
	return lines


static func _is_canonical(direction: Vector3i) -> bool:
	for component in [direction.x, direction.y, direction.z]:
		if component != 0:
			return component > 0
	return false  # the zero vector is not a direction


## Runs at script load, so a broken generator fails immediately rather than
## silently drawing the wrong lines.
static func _static_init() -> void:
	var lines := all_lines()
	assert(lines.size() == LINE_COUNT,
		"expected %d lines, built %d" % [LINE_COUNT, lines.size()])

	var per_cell: Dictionary = {}
	for line in lines:
		assert(line.size() == LINE_LENGTH, "line of the wrong length: %s" % [line])
		var seen: Dictionary = {}
		for cell in line:
			assert(is_valid_cell(cell), "line leaves the grid: %s" % [line])
			assert(not seen.has(cell), "line repeats a cell: %s" % [line])
			seen[cell] = true
			per_cell[cell] = int(per_cell.get(cell, 0)) + 1

	assert(per_cell.size() == GRID * GRID * GRID, "some cell lies on no line at all")
	for count in per_cell.values():
		# 3 axis lines always, plus at most 3 in-plane and 1 space diagonal.
		assert(count >= 3 and count <= 7, "unexpected line count through a cell: %d" % count)
