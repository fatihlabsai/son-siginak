class_name Pickup
extends Node3D
## Yerden alınabilir eşya (her tür: yiyecek, mermi, silah, malzeme). Yakınına gelince [E] ile alınır.
## Silahların ve bazı eşyaların Tripo modeli varsa o gösterilir, yoksa basit bir şekil.

@export var item_type: String = "food"
@export var amount := 1
@export var durability := -1   # silahlar için (-1 = yeni)

var _visual: Node3D
var _t := 0.0

## Yerde gösterilen model boyu (m)
const MODEL_SIZES := {"knife": 0.35, "bat": 0.85, "axe": 0.8, "pistol": 0.25, "shotgun": 1.0,
	"crate": 0.4, "barrel": 0.4}


static func label_for(type: String) -> String:
	return Items.item_name(type)


func _ready() -> void:
	add_to_group("pickups")
	_t = randf() * TAU
	_visual = Node3D.new()
	add_child(_visual)
	var mid: String = Items.info(item_type).get("model", item_type)
	if MODEL_SIZES.has(mid) and PropLibrary.has(mid):
		var size: float = MODEL_SIZES[mid]
		var m := PropLibrary.instance(mid, size)
		var a := PropLibrary.aabb(mid)
		m.position = -a.get_center() * size
		var tilt := Node3D.new()
		tilt.rotation_degrees = Vector3(0, 0, 70)
		tilt.add_child(m)
		_visual.add_child(tilt)
	else:
		_build_placeholder()
	var light := OmniLight3D.new()
	light.light_color = _color()
	light.light_energy = 0.7
	light.omni_range = 2.2
	light.position.y = 0.6
	add_child(light)


func _process(delta: float) -> void:
	_t += delta
	_visual.position.y = 0.3 + sin(_t * 2.0) * 0.07
	_visual.rotate_y(delta * 0.8)


func display_name() -> String:
	var n := "%s al" % Items.item_name(item_type)
	if amount > 1:
		n += " (x%d)" % amount
	return n


func collect(player: Player) -> void:
	var got := player.add_item(item_type, amount, durability)
	amount -= got
	if amount <= 0:
		queue_free()


func _color() -> Color:
	var t: String = Items.info(item_type).get("type", "")
	match t:
		"food":
			return Color(0.85, 0.3, 0.2)
		"water":
			return Color(0.3, 0.6, 1.0)
		"medkit":
			return Color(0.95, 0.95, 0.95)
		"ammo":
			return Color(0.95, 0.8, 0.3)
		"melee", "gun":
			return Color(1.0, 0.55, 0.25)
		"material":
			return Color(0.75, 0.65, 0.5)
		"bandage":
			return Color(0.95, 0.95, 0.95)
		"throwable":
			return Color(1.0, 0.5, 0.15)
	return Color.WHITE


func _build_placeholder() -> void:
	var mesh: PrimitiveMesh
	match item_type:
		"food":
			var can := CylinderMesh.new()
			can.top_radius = 0.12
			can.bottom_radius = 0.12
			can.height = 0.22
			mesh = can
		"water":
			var bottle := CylinderMesh.new()
			bottle.top_radius = 0.06
			bottle.bottom_radius = 0.09
			bottle.height = 0.4
			mesh = bottle
		"medkit":
			var kit := BoxMesh.new()
			kit.size = Vector3(0.4, 0.22, 0.3)
			mesh = kit
		"wood":
			var plank := BoxMesh.new()
			plank.size = Vector3(0.7, 0.06, 0.16)
			mesh = plank
		"nails":
			var box := BoxMesh.new()
			box.size = Vector3(0.18, 0.1, 0.12)
			mesh = box
		"scrap":
			var sheet := BoxMesh.new()
			sheet.size = Vector3(0.45, 0.03, 0.35)
			mesh = sheet
		"bandage", "noisemaker":
			var roll := CylinderMesh.new()
			roll.top_radius = 0.08
			roll.bottom_radius = 0.08
			roll.height = 0.12
			mesh = roll
		"molotov", "alcohol":
			var bottle := CylinderMesh.new()
			bottle.top_radius = 0.04
			bottle.bottom_radius = 0.08
			bottle.height = 0.32
			mesh = bottle
		"cloth":
			var rag := BoxMesh.new()
			rag.size = Vector3(0.35, 0.04, 0.3)
			mesh = rag
		"shells":
			var sb := BoxMesh.new()
			sb.size = Vector3(0.22, 0.12, 0.14)
			mesh = sb
		_:
			var ammo := BoxMesh.new()
			ammo.size = Vector3(0.3, 0.16, 0.2)
			mesh = ammo
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color()
	mat.emission_enabled = true
	mat.emission = _color() * 0.35
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_visual.add_child(mi)
