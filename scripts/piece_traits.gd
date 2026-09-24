class_name PieceTraits
extends Resource

## One of the 64 Quarto pieces, encoded as a 6-bit id.
##
## The bit layout is fixed: the tray layout, the demo fill and every debug
## line depend on it, and it makes the eventual line-win check a bitmask test.
##
##   bit 0  is_sphere    cube   / sphere
##   bit 1  is_black     white  / black
##   bit 2  is_big       small  / big
##   bit 3  is_hollow    solid  / hollow
##   bit 4  is_spotted   plain  / spotted
##   bit 5  is_spinning  still  / rotating

const BIT_SPHERE := 1 << 0
const BIT_BLACK := 1 << 1
const BIT_BIG := 1 << 2
const BIT_HOLLOW := 1 << 3
const BIT_SPOTTED := 1 << 4
const BIT_SPINNING := 1 << 5

const ID_MASK := 0x3F
const COUNT := 64

## The two words for each bit, low bit first: [when clear, when set].
## describe() and shared_property_names() both read this, so the vocabulary
## used by the tray, the held label and the win banner cannot drift apart.
const PROPERTY_NAMES := [
	["cube", "sphere"],
	["white", "black"],
	["small", "big"],
	["solid", "hollow"],
	["plain", "spotted"],
	["still", "spinning"],
]

## The packed trait id. Every other property is a view onto these bits.
@export_range(0, 63) var id: int = 0:
	set(value):
		id = value & ID_MASK
		emit_changed()

var is_sphere: bool:
	get:
		return (id & BIT_SPHERE) != 0
	set(value):
		_set_bit(BIT_SPHERE, value)

var is_black: bool:
	get:
		return (id & BIT_BLACK) != 0
	set(value):
		_set_bit(BIT_BLACK, value)

var is_big: bool:
	get:
		return (id & BIT_BIG) != 0
	set(value):
		_set_bit(BIT_BIG, value)

var is_hollow: bool:
	get:
		return (id & BIT_HOLLOW) != 0
	set(value):
		_set_bit(BIT_HOLLOW, value)

var is_spotted: bool:
	get:
		return (id & BIT_SPOTTED) != 0
	set(value):
		_set_bit(BIT_SPOTTED, value)

var is_spinning: bool:
	get:
		return (id & BIT_SPINNING) != 0
	set(value):
		_set_bit(BIT_SPINNING, value)


static func from_id(value: int) -> PieceTraits:
	var traits := PieceTraits.new()
	traits.id = value
	return traits


## Every distinct piece, in id order.
static func all() -> Array[PieceTraits]:
	var result: Array[PieceTraits] = []
	for i in COUNT:
		result.append(from_id(i))
	return result


## True when the given piece ids all agree on at least one property.
## This is the whole Quarto win condition; WinCheck applies it to a line.
static func share_property(ids: Array[int]) -> bool:
	return not shared_property_names(ids).is_empty()


## Which properties the given ids agree on, named - "black", "big" and so on.
## Empty when they agree on nothing. A line can agree on more than one, which
## is why this returns all of them rather than the first.
static func shared_property_names(ids: Array[int]) -> PackedStringArray:
	var names := PackedStringArray()
	if ids.is_empty():
		return names
	# One pass over the ids leaves two masks: bits set in every piece, and bits
	# clear in every piece. Either kind of agreement wins.
	var all_set := ID_MASK
	var all_clear := ID_MASK
	for value in ids:
		all_set &= value
		all_clear &= ~value & ID_MASK
	for bit in PROPERTY_NAMES.size():
		var mask := 1 << bit
		if all_set & mask:
			names.append(PROPERTY_NAMES[bit][1])
		elif all_clear & mask:
			names.append(PROPERTY_NAMES[bit][0])
	return names


func describe() -> String:
	var words := PackedStringArray()
	for bit in PROPERTY_NAMES.size():
		words.append(PROPERTY_NAMES[bit][(id >> bit) & 1])
	return "%02d %s" % [id, "/".join(words)]


func _set_bit(bit: int, value: bool) -> void:
	if value:
		id = id | bit
	else:
		id = id & ~bit
