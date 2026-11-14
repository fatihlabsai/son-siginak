class_name BuildMode
extends Node3D
## İnşa modu (B): fare noktasında yarı saydam önizleme; yeşil = kurulabilir, kırmızı = olmaz.
## Sol tık kurar, R döndürür, 1/2/3 yapıyı seçer, B / sağ tık çıkar.

signal changed

const OPTIONS := [
	{"id": "wood_barricade", "name": "Tahta barikat", "cost": {"wood": 3, "nails": 6}, "hp": 400.0,
		"desc": "Zombileri durdurur. Dayanıklılık 400."},
	{"id": "metal_barricade", "name": "Sac barikat", "cost": {"wood": 2, "scrap": 3, "nails": 8}, "hp": 900.0,
		"desc": "Çok daha sağlam. Dayanıklılık 900."},
	{"id": "spikes", "name": "Kazık tuzağı", "cost": {"wood": 2, "nails": 4}, "hp": 0.0,
		"desc": "Üstünden geçen zombileri yaralar ve yavaşlatır."},
]
const MAX_DIST := 4.5

var active := false
var index := 0
var yaw := 0.0
var valid := false
var affordable := false

var _player: Player
var _ghost: Node3D
var _ghost_mat: StandardMaterial3D
var _ghost_kind := ""


func setup(player: Player) -> void:
	_player = player


func _ready() -> void:
	top_level = true
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.no_depth_test = false
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.4)


func toggle() -> void:
	set_active(not active)


func set_active(on: bool) -> void:
	active = on
	if not on and _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_kind = ""
	changed.emit()


func select(i: int) -> void:
	index = clampi(i, 0, OPTIONS.size() - 1)
	changed.emit()


func rotate_ghost() -> void:
	yaw = fmod(yaw + PI / 4.0, TAU)


func current() -> Dictionary:
	return OPTIONS[index]


func can_afford(opt: Dictionary) -> bool:
	for id in opt.cost:
		if _player.inv.count(id) < int(opt.cost[id]):
			return false
	return true


func _physics_process(_delta: float) -> void:
	if not active or not is_instance_valid(_player):
		return
	var opt := current()
	if _ghost_kind != opt.id:
		_make_ghost(opt.id)
	# Fare noktasına (en fazla MAX_DIST uzağa), 0.5 m ızgaraya oturt
	var target := _player.aim_point
	var off := target - _player.global_position
	off.y = 0.0
	if off.length() > MAX_DIST:
		off = off.normalized() * MAX_DIST
	var p := _player.global_position + off
	p = Vector3(snappedf(p.x, 0.5), 0.0, snappedf(p.z, 0.5))
	_ghost.global_position = p
	_ghost.rotation.y = yaw
	affordable = can_afford(opt)
	valid = _space_free(p, opt.id)
	var ok := valid and affordable
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.4) if ok else Color(1.0, 0.25, 0.2, 0.4)


func try_place() -> void:
	if not active or _ghost == null:
		return
	var opt := current()
	if not affordable:
		_player.message.emit("Yetersiz malzeme: %s" % _cost_text(opt))
		Audio.play_2d("empty_click", -6.0)
		return
	if not valid:
		_player.message.emit("Buraya kurulamaz.")
		Audio.play_2d("empty_click", -6.0)
		return
	for id in opt.cost:
		_player.inv.remove(id, int(opt.cost[id]))
	var pos := _ghost.global_position
	var parent := get_tree().current_scene
	if opt.id == "spikes":
		var trap := SpikeTrap.new()
		parent.add_child(trap)
		trap.global_position = pos
		trap.rotation.y = yaw
	else:
		var b := Barricade.new()
		b.setup(opt.id, float(opt.hp), opt.name)
		parent.add_child(b)
		b.global_position = pos
		b.rotation.y = yaw
	Audio.play_3d("hit", pos + Vector3.UP * 0.5, -2.0, 6.0, 0.1)
	Game.make_noise(pos, 7.0)
	_player.message.emit("%s kuruldu." % opt.name)
	changed.emit()


func _cost_text(opt: Dictionary) -> String:
	var parts: Array[String] = []
	for id in opt.cost:
		parts.append("%s %d/%d" % [Items.item_name(id), _player.inv.count(id), int(opt.cost[id])])
	return ", ".join(parts)


func _make_ghost(kind: String) -> void:
	if _ghost:
		_ghost.queue_free()
	_ghost_kind = kind
	if kind == "spikes":
		_ghost = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(SpikeTrap.SIZE, 0.5, SpikeTrap.SIZE)
		(_ghost as MeshInstance3D).mesh = bm
		(_ghost as MeshInstance3D).position.y = 0.25
		var holder := Node3D.new()
		holder.add_child(_ghost)
		_ghost = holder
	else:
		_ghost = PropLibrary.instance("barricade", Barricade.LENGTH)
		if _ghost == null:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.4, 1.0, Barricade.LENGTH)
			mi.mesh = bm
			_ghost = Node3D.new()
			_ghost.add_child(mi)
	for n in _ghost.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.material_override = _ghost_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _ghost is MeshInstance3D:
		(_ghost as MeshInstance3D).material_override = _ghost_mat
	add_child(_ghost)


## Kurulacak yerde başka bir şey (bina, araba, zombi, oyuncu) var mı?
func _space_free(p: Vector3, kind: String) -> bool:
	var shape := BoxShape3D.new()
	if kind == "spikes":
		shape.size = Vector3(SpikeTrap.SIZE, 0.6, SpikeTrap.SIZE)
	else:
		shape.size = Vector3(0.45, 0.8, Barricade.LENGTH)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 0.5)
	q.collision_mask = 1 | 2 | 4
	q.collide_with_areas = kind == "spikes"
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 4)
	for h in hits:
		if h.collider is SpikeTrap or not (h.collider is Area3D):
			return false
	return true
