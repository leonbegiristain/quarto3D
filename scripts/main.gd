extends Node3D

## Game root. Owns the turn machine and wires it to the two views: the 4x4x4
## board, shifted left, and the 8x8 piece tray on the right.
##
## Board and panel share one set of pieces: every trait id is either available
## in the panel or sitting on the board, never both and never neither.
##
## A turn has two halves. You place the piece your opponent handed you, then
## you choose the piece they must place, so the active player changes in the
## middle of a turn rather than at the end. Both halves are confirmed with a
## button, so no single stray click can spend a piece or hand one away.
##
## Tapping a board vertex always means "isolate its lines" and never places
## anything, which is why placement needs the confirm button at all.

const CUBE_PADDING := 7.2
const CUBE_PITCH := 0.38
const CUBE_YAW := 0.7
const MENU_SCENE := "res://scenes/menu.tscn"
## Panel slot highlight while a piece is only being considered. Neutral on
## purpose: a tentative pick belongs to nobody yet, and it has to stay legibly
## different from both player colours once the piece is handed over - which a
## cyan does not, player 2 being blue.
const CHOOSING_COLOR := Color(0.82, 0.87, 0.96, 0.24)
const HELD_ALPHA := 0.34
const TRAY_SLIDE_TIME := 0.25

var _game := GameState.new()
var _tray_open := true
## 0 with the tray in place, 1 with it slid off the right edge.
var _tray_slide := 0.0
var _tray_tween: Tween
## The tray's and toggle's offsets as laid out in the scene, i.e. open. The
## slide is applied on top of these rather than stored as a second layout.
var _tray_home := Vector2.ZERO
var _toggle_home := Vector2.ZERO

@onready var _rig: OrbitCamera = $CameraRig
@onready var _board: Board = $Board
@onready var _tray: Control = $UI/Tray
@onready var _tray_toggle: Button = $UI/TrayToggle
@onready var _panel: PiecePanel = $UI/Tray/PiecePanel
@onready var _filter_bar: FilterBar = $UI/Tray/FilterBar
@onready var _turn_banner: Label = $UI/Header/TurnBanner
@onready var _held_card: Control = $UI/HeldCard
@onready var _preview: PiecePreview = $UI/HeldCard/VBox/Preview
@onready var _held_label: Label = $UI/HeldCard/VBox/HeldLabel
@onready var _place_button: Button = $UI/HeldCard/VBox/PlaceButton
@onready var _give_button: Button = $UI/HeldCard/VBox/GiveButton
@onready var _restart_button: Button = $UI/Header/Actions/RestartButton
@onready var _menu_button: Button = $UI/Header/Actions/MenuButton


func _ready() -> void:
	_place_button.pressed.connect(_on_place_pressed)
	_give_button.pressed.connect(_on_give_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_rig.tapped.connect(_on_tapped)
	_rig.hovered.connect(_on_hovered)
	# The panel swallows mouse motion before the rig sees it, so without this
	# the last hovered cell would stay swollen once the cursor crosses onto it.
	_panel.mouse_entered.connect(_clear_board_hover)
	_filter_bar.filter_changed.connect(_panel.set_filter)
	_panel.selection_changed.connect(_on_panel_selection_changed)
	_board.selection_changed.connect(_on_board_selection_changed)
	_game.changed.connect(_refresh_ui)
	get_viewport().size_changed.connect(_update_view_center)
	_tray_toggle.pressed.connect(toggle_panel)
	_tray_home = Vector2(_tray.offset_left, _tray.offset_right)
	_toggle_home = Vector2(_tray_toggle.offset_left, _tray_toggle.offset_right)

	set_panel_open(true, false)
	# Accounts for anything the board placed during its own _ready(), which is
	# nothing in a real game and the demo scatter when that export is on.
	_sync_panel_availability()
	_refresh_ui()
	_rig.focus(_board.global_position, _framing_distance(), CUBE_PITCH, CUBE_YAW)


# --- shared piece set --------------------------------------------------------

## Availability is derived from the board, never maintained alongside it: walk
## what is on the board, and everything else is still in the panel. A second
## tally kept in step by hand is exactly the thing that drifts.
func _sync_panel_availability() -> void:
	var placed := _board.placed_ids()
	for id in PieceTraits.COUNT:
		_panel.set_available(id, not placed.has(id))
	_assert_unique_set(placed)


## The invariant, checked rather than assumed: the panel and the board
## partition the 64 ids exactly.
func _assert_unique_set(placed: Dictionary) -> void:
	var available := 0
	for id in PieceTraits.COUNT:
		var in_panel := _panel.is_available(id)
		assert(in_panel != placed.has(id),
			"piece %d is in %s" % [id, "both places" if in_panel else "neither place"])
		if in_panel:
			available += 1
	assert(available + placed.size() == PieceTraits.COUNT,
		"shared set lost a piece: %d available + %d placed" % [available, placed.size()])


## While a piece is in hand the panel must be showing exactly that piece - the
## same derived-not-maintained rule as availability, checked rather than
## trusted, because a silent refusal inside select() would otherwise leave one
## player looking at the wrong piece to place.
func _assert_held_piece() -> void:
	if _game.phase != GameState.Phase.PLACING:
		return
	assert(_panel.get_selected_id() == _game.held_id,
		"panel shows %d but %s was handed %d" % [
			_panel.get_selected_id(),
			GameState.player_name(_game.active_player),
			_game.held_id])


# --- the turn ----------------------------------------------------------------

func _on_panel_selection_changed(_traits: PieceTraits) -> void:
	_refresh_ui()


func _on_board_selection_changed(_cell: Vector3i) -> void:
	_refresh_ui()


## Everything the HUD shows, derived in one pass from the game state and the
## two views. Anything that can change what is on screen routes through here
## rather than poking at a label from whichever handler caused it.
func _refresh_ui() -> void:
	var choosing := _game.phase == GameState.Phase.CHOOSING
	var placing := _game.phase == GameState.Phase.PLACING

	_turn_banner.text = _game.headline()
	_turn_banner.add_theme_color_override("font_color", _game.headline_color())

	# During PLACING the panel selection is a view of the held piece rather
	# than a choice: driven from the game state, then locked so it stays put.
	if placing:
		_panel.select(_game.held_id)
		_panel.set_highlight_color(
			Color(GameState.player_color(_game.active_player), HELD_ALPHA))
	else:
		_panel.set_highlight_color(CHOOSING_COLOR)
	_panel.set_locked(not choosing)
	_assert_held_piece()

	var traits := _panel.get_selected_traits()
	_held_card.visible = traits != null and not _game.is_over()
	_preview.show_traits(traits if _held_card.visible else null)
	if _held_card.visible:
		var words := traits.words()
		_held_label.text = "%s\n%s\n%s\n%s" % [
			"giving" if choosing else "to place",
			" · ".join(words.slice(0, 2)),
			" · ".join(words.slice(2, 4)),
			" · ".join(words.slice(4))]

	_give_button.visible = choosing and traits != null
	if _give_button.visible:
		_give_button.text = "Give to %s" % GameState.player_name(_game.opponent())

	var cell := _board.get_selected()
	var empty_cell := cell != Board.NO_CELL and _board.get_piece(cell) == null
	var can_place := placing and traits != null and empty_cell
	_place_button.visible = can_place
	if can_place:
		_place_button.text = "Place at (%d, %d, %d)" % [cell.x, cell.y, cell.z]
		_board.set_preview(traits, cell)
	else:
		_board.clear_preview()


func _on_give_pressed() -> void:
	# Whatever was isolated belonged to the player who was choosing. The piece
	# now passes to the other one, so the board starts clean for them rather
	# than opening on a cell they did not pick with the place button already up.
	_board.clear_selection()
	_game.hand_piece(_panel.get_selected_id())
	# Placing happens on the board, and the held card already shows the piece,
	# so the tray steps aside and gives the board the room.
	set_panel_open(false)


func _on_place_pressed() -> void:
	var traits := _panel.get_selected_traits()
	var cell := _board.get_selected()
	if _game.phase != GameState.Phase.PLACING or traits == null:
		return
	if cell == Board.NO_CELL or _board.get_piece(cell) != null:
		return

	_board.place_piece(cell, traits)
	# Drop the isolation too, so a completed placement leaves a clean board
	# rather than holding the view on the cell you just filled.
	_board.clear_selection()
	# Judged before the panel is touched. record_placement() moves the phase
	# out of PLACING, and only then is it correct for the spent piece to stop
	# being the held one - otherwise _assert_held_piece() would fire on the
	# refresh that _sync_panel_availability() sets off.
	_game.record_placement(_board.occupancy())
	_sync_panel_availability()
	if _game.is_over():
		_board.set_win_highlight(_game.winning_lines)
	else:
		# Back for the choosing half. Left closed on a finished game, where
		# there is nothing to choose and the winning line wants the room.
		set_panel_open(true)
	_refresh_ui()


func _on_restart_pressed() -> void:
	# Reloading rather than unpicking the state by hand: one call, and
	# provably back to the opening position, camera framing included.
	get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


# --- panel and camera --------------------------------------------------------

func toggle_panel() -> void:
	set_panel_open(not _tray_open)


func is_panel_open() -> bool:
	return _tray_open


## Slides the tray off the right edge, or back. The toggle rides along on the
## tray's left side, so it ends up at the screen edge as "<" and comes back as
## ">". The board starts easing to its new centre at the same moment.
func set_panel_open(open: bool, animate := true) -> void:
	_tray_open = open
	_tray_toggle.text = ">" if open else "<"
	if _tray_tween != null and _tray_tween.is_valid():
		_tray_tween.kill()
	if open:
		_set_tray_active(true)
		_clear_board_hover()
	var target := 0.0 if open else 1.0
	if animate:
		_tray_tween = create_tween()
		_tray_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tray_tween.tween_method(_set_tray_slide, _tray_slide, target, TRAY_SLIDE_TIME)
		if not open:
			_tray_tween.tween_callback(_set_tray_active.bind(false))
	else:
		_set_tray_slide(target)
		_set_tray_active(open)
	_update_view_center()


func _set_tray_slide(amount: float) -> void:
	_tray_slide = amount
	# The tray's left offset is its distance in from the right edge, so
	# shifting by exactly that much puts it just off screen.
	var shift := -_tray_home.x * amount
	_tray.offset_left = _tray_home.x + shift
	_tray.offset_right = _tray_home.y + shift
	_tray_toggle.offset_left = _toggle_home.x + shift
	_tray_toggle.offset_right = _toggle_home.y + shift


## Hidden once it is off screen, not just moved: that stops its SubViewport
## rendering, and disabling the branch stops the spin _process calls.
func _set_tray_active(active: bool) -> void:
	_tray.visible = active
	_panel.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


## Centre the board in the strip between the held card and the tray, or up
## to the right edge while the tray is closed. Worked out from the actual
## rects rather than widths copied from the scene. Re-framing resets the zoom,
## which only happens on a resize or a tray toggle.
func _update_view_center() -> void:
	var view := get_viewport().get_visible_rect().size
	if view.x <= 0.0:
		return
	var strip := _free_strip()
	_rig.set_screen_center((strip.x + strip.y) / view.x - 1.0)
	_rig.focus(_board.global_position, _framing_distance())


## Left and right edges of the space the board gets. The card's column counts
## even while the card is hidden, so the board does not jump sideways every
## time a piece is picked up or put down. The tray counts by where it is
## going, not where it is mid-slide, so the camera eases in step with it.
func _free_strip() -> Vector2:
	var left := _held_card.get_global_rect().end.x
	var right := get_viewport().get_visible_rect().size.x
	if _tray_open:
		right += _tray_home.x
	return Vector2(left, right)


## CUBE_PADDING frames the board by height. A free strip narrower than it is
## tall needs the camera further back, by however much more distance the
## board's bounding sphere needs to fit the width than the height, so both
## axes keep the same margin.
func _framing_distance() -> float:
	var base := Board.extent() + CUBE_PADDING
	var view := get_viewport().get_visible_rect().size
	if view.y <= 0.0:
		return base
	var half_fov := deg_to_rad(_rig.get_camera().fov) * 0.5
	var strip := _free_strip()
	var half_width := atan(tan(half_fov) * (strip.y - strip.x) / view.y)
	return base * maxf(1.0, sin(half_fov) / sin(half_width))


## Mouse-over feedback: the cell under the cursor swells. Suppressed while
## orbiting, since a drag never ends in a selection and the swell would be
## promising something that will not happen.
func _on_hovered(screen_position: Vector2) -> void:
	if _game.is_over() or _rig.is_dragging() or _rig.get_camera() == null:
		_clear_board_hover()
		return
	_board.set_hovered(_board.pick_cell(
		_rig.screen_ray_origin(screen_position),
		_rig.screen_ray_normal(screen_position)))


## A tap picks a lattice cell to isolate. Tapping the selected cell again
## clears it, and tapping the background - hitting no cell at all - is the
## other way out of an isolated view. Once the game is over the board stops
## listening, so nothing can disturb the winning line.
func _on_tapped(screen_position: Vector2) -> void:
	if _game.is_over() or _rig.get_camera() == null:
		return
	var cell := _board.pick_cell(
		_rig.screen_ray_origin(screen_position),
		_rig.screen_ray_normal(screen_position))
	if cell == Board.NO_CELL:
		_board.clear_selection()
	else:
		_board.toggle_cell(cell)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		toggle_panel()
		get_viewport().set_input_as_handled()


func _clear_board_hover() -> void:
	_board.set_hovered(Board.NO_CELL)
