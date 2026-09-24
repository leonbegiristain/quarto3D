class_name PieceView
extends Node3D

## Visual for a single piece. Assign `traits` and every one of the six
## properties is applied: mesh (shape + hollow), material (colour + spots),
## node scale (size) and processing (spin).

const SPIN_SPEED := 0.96  # rad/s, ~55 deg/s
const BIG_SCALE := 1.0
const SMALL_SCALE := 0.62
## How much a piece swells while the pointer is over it.
const EMPHASIS_SCALE := 1.32
const EMPHASIS_TIME := 0.13

@export var traits: PieceTraits:
	set(value):
		traits = value
		_apply()

## How far a preview piece fades. It keeps its real material - colour and
## spots included - because a preview is meant to answer "what would this
## look like here".
const PREVIEW_TRANSPARENCY := 0.72

var _emphasised := false
var _ghosted := false
var _scale_tween: Tween

@onready var _mesh: MeshInstance3D = $Mesh

## Shared stand-in for a piece that has been spent. Deliberately an override
## rather than fading the piece's own material: the four piece materials are
## shared by all 64 instances, so fading one would fade every piece using it.
static var _ghost_material: StandardMaterial3D


static func scale_for(piece_traits: PieceTraits) -> float:
	return BIG_SCALE if piece_traits.is_big else SMALL_SCALE


static func ghost_material() -> StandardMaterial3D:
	if _ghost_material == null:
		_ghost_material = StandardMaterial3D.new()
		_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_material.albedo_color = Color(0.58, 0.64, 0.76, 0.17)
	return _ghost_material


## Temporary swell to signal that this piece is what a tap would hit.
func set_emphasised(on: bool) -> void:
	if _emphasised == on:
		return
	_emphasised = on
	if not is_node_ready():
		return
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_scale_tween.tween_property(self, "scale", _target_scale(), EMPHASIS_TIME)


## Spent pieces fade to a flat translucent stand-in and stop spinning. Shape,
## size, hollowness and - above all - grid position survive, and in a
## systematic grid the position is what identifies the piece.
func set_ghosted(on: bool) -> void:
	if _ghosted == on:
		return
	_ghosted = on
	if not is_node_ready():
		return
	_apply_material()
	_apply_processing()


## How far back a piece steps when it is not part of a finished line, so the
## four that won are the only ones left at full strength.
func set_fade(amount: float) -> void:
	if is_node_ready():
		_mesh.transparency = clampf(amount, 0.0, 1.0)


## A translucent stand-in for a placement that has not been committed.
## Goes through set_fade() rather than writing transparency directly: both
## effects claim the same property, and one setter keeps them from fighting.
func set_preview(on: bool) -> void:
	set_fade(PREVIEW_TRANSPARENCY if on else 0.0)


## Current spin phase. Handing this to a newly placed piece is what stops a
## spinning preview from snapping back to zero the moment it is committed.
func get_spin_angle() -> float:
	return _mesh.rotation.y if is_node_ready() else 0.0


func set_spin_angle(angle: float) -> void:
	if is_node_ready():
		_mesh.rotation.y = angle


func is_ghosted() -> bool:
	return _ghosted


func _target_scale() -> Vector3:
	if traits == null:
		return Vector3.ONE
	var factor := scale_for(traits)
	if _emphasised:
		factor *= EMPHASIS_SCALE
	return Vector3.ONE * factor


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	# Spin the mesh, not the root, so the root transform stays free for
	# placement tweens later on.
	_mesh.rotate_y(SPIN_SPEED * delta)


func _apply() -> void:
	if not is_node_ready():
		return
	_apply_processing()
	if traits == null:
		_mesh.mesh = null
		return
	_mesh.mesh = PieceAssets.mesh_for(traits.is_sphere, traits.is_hollow)
	_mesh.rotation = Vector3.ZERO
	_apply_material()
	scale = _target_scale()
	name = "Piece%02d" % traits.id


func _apply_material() -> void:
	if traits == null:
		return
	_mesh.material_override = ghost_material() if _ghosted \
		else PieceAssets.material_for(traits.is_black, traits.is_spotted)


func _apply_processing() -> void:
	set_process(not _ghosted and traits != null and traits.is_spinning)
