class_name PiecePreview
extends SubViewportContainer

## One piece, large, in its own little world: what is about to be given or
## placed. Small tray icons are hardest to read for exactly the properties that
## matter most at a glance - spotted, hollow - so this shows the piece at a
## size where they are obvious.
##
## Lit like the tray (the environment is shared) and tilted like it, so the
## piece reads as the same object at a bigger scale. The camera is framed for
## a big piece, which leaves a small one visibly small.

@onready var _piece: PieceView = $SubViewport/Piece


func _ready() -> void:
	_piece.rotation = PiecePanel.PIECE_TILT


## Show a piece, or nothing when passed null.
func show_traits(traits: PieceTraits) -> void:
	if traits == null:
		_piece.visible = false
		return
	# Reassigning the same piece would restart its spin on every UI refresh.
	if _piece.traits == null or _piece.traits.id != traits.id:
		_piece.traits = traits
	_piece.visible = true


func get_shown_id() -> int:
	if not _piece.visible or _piece.traits == null:
		return PiecePanel.NO_PIECE
	return _piece.traits.id
