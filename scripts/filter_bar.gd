class_name FilterBar
extends HBoxContainer

## The row of six property chips above the tray. It only reads the chips and
## reports the combined filter as two bitmasks, in the same form as
## PieceTraits.shared_property_names(): bits every shown piece must have, and
## bits no shown piece may have. The chips combine with AND.

signal filter_changed(must_set: int, must_clear: int)

var _chips: Array[PropertyChip] = []


func _ready() -> void:
	for bit in PieceTraits.PROPERTY_NAMES.size():
		var chip := PropertyChip.new()
		chip.bit = bit
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(chip)
		chip.state_changed.connect(_on_chip_changed)
		_chips.append(chip)


func get_chips() -> Array[PropertyChip]:
	return _chips


func get_must_set() -> int:
	var mask := 0
	for chip in _chips:
		if chip.state == PropertyChip.State.SET:
			mask |= 1 << chip.bit
	return mask


func get_must_clear() -> int:
	var mask := 0
	for chip in _chips:
		if chip.state == PropertyChip.State.CLEAR:
			mask |= 1 << chip.bit
	return mask


func _on_chip_changed() -> void:
	filter_changed.emit(get_must_set(), get_must_clear())
