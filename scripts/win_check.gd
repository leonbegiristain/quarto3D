class_name WinCheck
extends RefCounted

## Quarto's win condition on a 4x4x4 board: a line whose four cells are all
## filled and whose four pieces agree on at least one of the six properties.
##
## A pure query. It is handed an occupancy map and knows nothing about nodes,
## so the rules can be exercised headlessly without a scene. It sits on top of
## BoardLines (which lines exist) and PieceTraits (what agreeing means), and
## neither of those knows this file exists - no cycle.

## Every winning line. `occupancy` maps Vector3i -> trait id.
##
## All 76 lines are scanned rather than only the ones through the last move.
## That is 304 lookups, which costs nothing, and it buys two things: every
## simultaneous win is found, so the highlight can show all of them, and the
## answer stays correct if a piece is ever taken back off the board.
static func winning_lines(occupancy: Dictionary) -> Array[Array]:
	var found: Array[Array] = []
	for line in BoardLines.all_lines():
		var ids := line_ids(occupancy, line)
		if ids.is_empty():
			continue
		if PieceTraits.share_property(ids):
			found.append(line)
	return found


## The properties the pieces on `cells` agree on, for the result banner.
## Empty when the line is unfinished or agrees on nothing.
static func line_properties(occupancy: Dictionary, cells: Array) -> PackedStringArray:
	return PieceTraits.shared_property_names(line_ids(occupancy, cells))


## Trait ids along `cells`, or empty if any of them is still open. A part
## filled line can never win, so "not yet" and "nothing there" collapse into
## one return value on purpose.
static func line_ids(occupancy: Dictionary, cells: Array) -> Array[int]:
	var ids: Array[int] = []
	for cell in cells:
		if not occupancy.has(cell):
			ids.clear()
			return ids
		ids.append(int(occupancy[cell]))
	return ids
