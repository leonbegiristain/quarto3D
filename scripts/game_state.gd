class_name GameState
extends RefCounted

## Whose turn it is and what they owe. Knows the rules of the turn and nothing
## about the scene; it keeps no copy of the board, and is handed an occupancy
## map on the one occasion it has to judge a position.
##
## Quarto's turn is the unusual part, and the whole shape follows from it: you
## never choose your own piece. You place whatever your opponent handed you,
## and then you choose what they must place. So the active player changes in
## the middle of a turn rather than at the end of it, and the opening move is
## a choice with nothing to place - which falls out of the starting phase for
## free rather than needing a special case.

enum Phase {
	CHOOSING,  ## the active player picks a piece for the opponent
	PLACING,  ## the active player must place what they were handed
	OVER,
}
enum Outcome { NONE, WIN, DRAW }

const NO_PIECE := -1
const PLAYER_COUNT := 2
const CELL_COUNT := BoardLines.GRID * BoardLines.GRID * BoardLines.GRID

## Presentation, kept here so "who the two players are" is answered in exactly
## one place: the banner, the panel highlight and the button labels all read
## these rather than each deciding for themselves.
const PLAYER_NAMES := ["Player 1", "Player 2"]
const PLAYER_COLORS := [Color(1.0, 0.76, 0.36), Color(0.42, 0.78, 1.0)]
const DRAW_COLOR := Color(0.82, 0.86, 0.94)

signal changed

var phase: Phase = Phase.CHOOSING
var active_player := 0
## The piece the active player must place, or NO_PIECE. This is the single
## source of truth for what is in hand; the panel selection mirrors it.
var held_id := NO_PIECE
var outcome: Outcome = Outcome.NONE
var winner := -1
var winning_lines: Array[Array] = []
var winning_properties := PackedStringArray()


static func player_name(index: int) -> String:
	if index < 0 or index >= PLAYER_COUNT:
		return "Nobody"
	return PLAYER_NAMES[index]


static func player_color(index: int) -> Color:
	if index < 0 or index >= PLAYER_COUNT:
		return DRAW_COLOR
	return PLAYER_COLORS[index]


func opponent() -> int:
	return (active_player + 1) % PLAYER_COUNT


func is_over() -> bool:
	return phase == Phase.OVER


func reset() -> void:
	phase = Phase.CHOOSING
	active_player = 0
	held_id = NO_PIECE
	outcome = Outcome.NONE
	winner = -1
	winning_lines = []
	winning_properties = PackedStringArray()
	changed.emit()


## The active player hands `id` to the opponent, who becomes active and now
## owes a placement. The flip belongs here because the piece was chosen *for*
## them: choosing is the end of one player's turn, not the start of it.
func hand_piece(id: int) -> void:
	if phase != Phase.CHOOSING or id == NO_PIECE:
		return
	held_id = id
	active_player = opponent()
	phase = Phase.PLACING
	changed.emit()


## Called once the board has taken the held piece. Judges the new position: a
## completed line ends the game in favour of whoever just placed, a full board
## with no line is a draw, and otherwise the same player stays active and now
## chooses for the opponent.
func record_placement(occupancy: Dictionary) -> void:
	if phase != Phase.PLACING:
		return
	held_id = NO_PIECE
	winning_lines = WinCheck.winning_lines(occupancy)
	if not winning_lines.is_empty():
		outcome = Outcome.WIN
		winner = active_player
		winning_properties = WinCheck.line_properties(occupancy, winning_lines[0])
		phase = Phase.OVER
	elif occupancy.size() >= CELL_COUNT:
		outcome = Outcome.DRAW
		phase = Phase.OVER
	else:
		phase = Phase.CHOOSING
	changed.emit()


## One line for the banner: who is up and what they owe, or how it ended.
func headline() -> String:
	if phase == Phase.CHOOSING:
		return "%s - choose a piece for %s" % [
			player_name(active_player), player_name(opponent())]
	if phase == Phase.PLACING:
		return "%s - place the piece" % player_name(active_player)
	if outcome == Outcome.DRAW:
		return "Draw - the board is full"
	return "%s wins - all %s" % [player_name(winner), " and ".join(winning_properties)]


func headline_color() -> Color:
	if phase == Phase.OVER:
		return DRAW_COLOR if outcome == Outcome.DRAW else player_color(winner)
	return player_color(active_player)
