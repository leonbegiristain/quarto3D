class_name OrbitCamera
extends Node3D

## Orbit rig: this node is the pivot, the Camera3D child is pushed back along
## its local +Z. Drag with the mouse or one finger to orbit, wheel / pinch to
## zoom. Everything eases toward a target so view switches glide.

## Emitted on a press that was released without really moving - the
## gesture that means "select", as opposed to an orbit drag.
signal tapped(screen_position: Vector2)

## Emitted as the mouse moves, so the board can show what sits under the
## cursor. Touch never hovers - there is no cursor to hover with.
signal hovered(screen_position: Vector2)

## A press counts as a tap only if the pointer travels less than this many
## pixels in total and is released inside the time limit.
const TAP_TRAVEL_LIMIT := 12.0
const TAP_TIME_LIMIT_MS := 400
const DRAG_SENSITIVITY := 0.0065
const PITCH_LIMIT := 1.35
const MIN_DISTANCE := 3.0
const MAX_DISTANCE := 40.0
const ZOOM_STEP := 1.12
const SMOOTHING := 12.0

@export var camera_path: NodePath = ^"Camera3D"
@export var start_yaw := 0.7
@export var start_pitch := 0.42
@export var start_distance := 10.0

var _yaw := 0.0
var _pitch := 0.0
var _distance := 10.0
var _pivot := Vector3.ZERO
## Where the pivot sits on screen, as a horizontal NDC coordinate: 0 is the
## centre, -1 the left edge. Lets the HUD claim one side without the orbit
## swinging around anything but the board.
var _screen_x := 0.0

var _target_yaw := 0.0
var _target_pitch := 0.0
var _target_distance := 10.0
var _target_pivot := Vector3.ZERO
var _target_screen_x := 0.0

var _dragging := false
var _touches: Dictionary = {}
var _pinch_span := 0.0

var _tap_candidate := false
var _tap_position := Vector2.ZERO
var _tap_travel := 0.0
var _tap_start_ms := 0

@onready var _camera: Camera3D = get_node(camera_path)


func _ready() -> void:
	_target_yaw = start_yaw
	_target_pitch = start_pitch
	_target_distance = start_distance
	_yaw = _target_yaw
	_pitch = _target_pitch
	_distance = _target_distance
	_pivot = _target_pivot
	_apply_transform()


## Glide to look at `center` from `distance` away. Pass `pitch` / `yaw` to
## also swing to a given angle; leave them out to keep the current one.
func focus(center: Vector3, distance: float, pitch := INF, yaw := INF) -> void:
	_target_pivot = center
	_target_distance = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)
	if is_finite(pitch):
		_target_pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	if is_finite(yaw):
		# Take the short way round, however far the user has orbited.
		_target_yaw = _yaw + wrapf(yaw - _yaw, -PI, PI)


## Glide the pivot to a horizontal spot on screen, in NDC (-1 left, 1 right).
func set_screen_center(ndc_x: float) -> void:
	_target_screen_x = clampf(ndc_x, -1.0, 1.0)


func _process(delta: float) -> void:
	var weight := 1.0 - exp(-SMOOTHING * delta)
	_yaw = lerpf(_yaw, _target_yaw, weight)
	_pitch = lerpf(_pitch, _target_pitch, weight)
	_distance = lerpf(_distance, _target_distance, weight)
	_pivot = _pivot.lerp(_target_pivot, weight)
	_screen_x = lerpf(_screen_x, _target_screen_x, weight)
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		hovered.emit(event.position)
		if _dragging:
			_orbit_by(event.relative)
	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMagnifyGesture:
		_zoom_by(1.0 / maxf(event.factor, 0.01))


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				_begin_tap(event.position)
			else:
				_end_tap()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_by(1.0 / ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_by(ZOOM_STEP)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_begin_tap(event.position)
		else:
			_tap_candidate = false  # a second finger means pinch, never a tap
	else:
		_touches.erase(event.index)
		_end_tap()
	_pinch_span = _touch_span()


func _handle_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _touches.size() == 1:
		_orbit_by(event.relative)
	elif _touches.size() >= 2:
		var span := _touch_span()
		if _pinch_span > 0.0 and span > 0.0:
			_zoom_by(_pinch_span / span)
		_pinch_span = span


func _touch_span() -> float:
	if _touches.size() < 2:
		return 0.0
	var points := _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


func _begin_tap(position: Vector2) -> void:
	_tap_candidate = true
	_tap_position = position
	_tap_travel = 0.0
	_tap_start_ms = Time.get_ticks_msec()


func _end_tap() -> void:
	if not _tap_candidate:
		return
	_tap_candidate = false
	if _tap_travel > TAP_TRAVEL_LIMIT:
		return
	if Time.get_ticks_msec() - _tap_start_ms > TAP_TIME_LIMIT_MS:
		return
	# The press position, not the release position: that is where the user
	# actually aimed.
	tapped.emit(_tap_position)


func _orbit_by(motion: Vector2) -> void:
	# Total travel, not displacement from the press point - a small circle
	# that ends where it started is still a drag, not a tap.
	_tap_travel += motion.length()
	_target_yaw -= motion.x * DRAG_SENSITIVITY
	_target_pitch = clampf(_target_pitch + motion.y * DRAG_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)


func _zoom_by(factor: float) -> void:
	_target_distance = clampf(_target_distance * factor, MIN_DISTANCE, MAX_DISTANCE)


func is_dragging() -> bool:
	return _dragging


func get_camera() -> Camera3D:
	return _camera


## Start of the pick ray through a screen point. Use this and screen_ray_normal()
## rather than the Camera3D project_ray_* calls, which ignore the frustum
## offset and so miss by the whole lens shift.
func screen_ray_origin(_screen_position: Vector2) -> Vector3:
	return _camera.global_position


## Direction of the pick ray through a screen point, taken from the real
## projection matrix, lens shift included.
func screen_ray_normal(screen_position: Vector2) -> Vector3:
	var view := _camera.get_viewport().get_visible_rect().size
	var ndc := Vector2(screen_position.x / view.x * 2.0 - 1.0, 1.0 - screen_position.y / view.y * 2.0)
	# Any depth inside the frustum lies on the ray; 0 is valid for both depth
	# conventions.
	var eye := _camera.get_camera_projection().inverse() * Vector4(ndc.x, ndc.y, 0.0, 1.0)
	var local := Vector3(eye.x, eye.y, eye.z) / eye.w
	return (_camera.global_transform.basis * local).normalized()


func _apply_transform() -> void:
	position = _pivot
	# Negated pitch so a positive value means "camera above the pivot".
	basis = Basis.from_euler(Vector3(-_pitch, _yaw, 0.0))
	if _camera != null:
		_camera.position = Vector3(0.0, 0.0, _distance)
		_apply_lens_shift()


## Puts the pivot at `_screen_x` on screen with an off-axis frustum: a lens
## shift. The camera still looks straight at the pivot, so the board is drawn
## exactly as it would be centred, only moved over. Sliding the camera
## sideways instead (h_offset) views the board off-axis and visibly skews it.
##
## The frustum is rebuilt from `fov`, which stays the one lens setting: the
## near-plane height that `fov` implies, with the window slid across.
func _apply_lens_shift() -> void:
	var view := _camera.get_viewport().get_visible_rect().size
	if view.y <= 0.0:
		return
	# Height, because the camera keeps height by default.
	var height := 2.0 * _camera.near * tan(deg_to_rad(_camera.fov) * 0.5)
	var half_width := height * 0.5 * view.x / view.y
	_camera.set_frustum(height, Vector2(-_screen_x * half_width, 0.0), _camera.near, _camera.far)
