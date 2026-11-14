class_name PropLibrary
extends RefCounted
## Tripo'dan gelen eşya / bina modellerini yükler, boyutlarını ölçer ve sahneye yerleştirir.
## Tripo modelleri en uzun kenarı 1 birim olacak şekilde gelir; burada gerçek boyuta ölçeklenir.
## Yeni model eklemek: assets/models/props/<isim>.glb koy, aşağıdaki listeye ekle.

const DIR := "res://assets/models/props/"
const NAMES := [
	"pickup_truck", "sedan_car", "farmhouse", "house", "barn", "store",
	"barrel", "crate", "dumpster", "barricade", "tent", "dead_tree", "pine_tree", "campfire",
	"knife", "bat", "axe", "pistol", "shotgun",
]

static var _scenes := {}
static var _aabbs := {}


static func has(key: String) -> bool:
	_load()
	return _scenes.has(key)


## Modelin kendi biriminde sınır kutusu (ölçeksiz).
static func aabb(key: String) -> AABB:
	_load()
	if _aabbs.has(key):
		return _aabbs[key]
	var box := AABB()
	if not _scenes.has(key):
		return box
	var inst := (_scenes[key] as PackedScene).instantiate() as Node3D
	var first := true
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n and n != inst:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		var a := t * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	inst.free()
	_aabbs[key] = box
	return box


## Modeli ölçekleyip bir düğüm olarak döndürür (çarpışmasız).
static func instance(key: String, s: float) -> Node3D:
	_load()
	if not _scenes.has(key):
		return null
	var inst := (_scenes[key] as PackedScene).instantiate() as Node3D
	inst.scale = Vector3.ONE * s
	return inst


## Statik çarpışmalı model. collider: "box" (sınır kutusu), "trunk" (ağaç gövdesi), "none".
## box_scale ile çarpışma kutusu küçültülebilir (örn. araba lastik çıkıntıları).
static func spawn(parent: Node, key: String, pos: Vector3, s: float, rot_y := 0.0, collider := "box", box_scale := Vector3.ONE) -> Node3D:
	var model := instance(key, s)
	if model == null:
		return null
	var root: Node3D = StaticBody3D.new() if collider != "none" else Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	root.add_child(model)
	if collider == "box":
		var a := aabb(key)
		var shape := BoxShape3D.new()
		shape.size = a.size * s * box_scale
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = (a.position + a.size * 0.5) * s
		root.add_child(cs)
	elif collider == "trunk":
		var shape := CylinderShape3D.new()
		shape.radius = clampf(s * 0.04, 0.25, 0.5)
		shape.height = 3.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 1.5
		root.add_child(cs)
	parent.add_child(root)
	return root


## Modelin yerde kapladığı alan (x, z), verilen ölçek ve dik açılı dönüşle.
static func footprint(key: String, s: float, rot_y: float) -> Vector2:
	var a := aabb(key)
	var fp := Vector2(a.size.x, a.size.z) * s
	if absf(sin(rot_y)) > 0.7:
		fp = Vector2(fp.y, fp.x)
	return fp


## Çıkışta önbelleği boşalt (aksi halde Godot "kaynak sızıntısı" uyarısı verir).
static func clear() -> void:
	_scenes.clear()
	_aabbs.clear()


static func _load() -> void:
	if not _scenes.is_empty():
		return
	for key in NAMES:
		var path: String = DIR + key + ".glb"
		if ResourceLoader.exists(path):
			_scenes[key] = load(path)
