class_name OcclusionFader
extends Node
## Oyuncu ile kamera arasına giren binaları ve ağaçları saydamlaştırır.
## Her karede oyuncunun ayak, gövde ve baş noktasından kameraya doğru ışın gönderilir;
## ışın bir engelin sınır kutusundan geçiyorsa o engel yumuşakça soluklaşır.
## Derinlik ön geçişli saydamlık: sadece en öndeki yüzey yarı saydam görünür, iç içe
## yüzeyler karışmaz; bina "hayalet" gibi görünür ama şekli belli olur.

const FADED_ALPHA := 0.12
const FADE_SPEED := 4.0
const CHECK_RADIUS := 32.0

var _items: Array[Dictionary] = []


## node: sahnedeki model kökü, local_aabb: modelin ölçeksiz sınır kutusu, s: ölçek.
## shrink: yatayda sınır kutusunu daralt (ağaç gibi seyrek modeller için).
func add(node: Node3D, local_aabb: AABB, s: float, shrink := 1.0) -> void:
	var a := AABB(local_aabb.position * s, local_aabb.size * s)
	if shrink != 1.0:
		var c := a.get_center()
		a.size.x *= shrink
		a.size.z *= shrink
		a.position.x = c.x - a.size.x * 0.5
		a.position.z = c.z - a.size.z * 0.5
	var world := node.global_transform * a
	_items.append({"node": node, "aabb": world, "alpha": 1.0, "mats": []})


func _process(delta: float) -> void:
	var player := Game.player
	var cam := get_viewport().get_camera_3d()
	if not is_instance_valid(player) or cam == null:
		return
	var to_cam := cam.global_transform.basis.z.normalized()
	var p := player.global_position
	var samples := [p + Vector3.UP * 0.4, p + Vector3.UP * 1.2, p + Vector3.UP * 1.9]
	for item in _items:
		var node: Node3D = item.node
		if not is_instance_valid(node):
			continue
		var box: AABB = item.aabb
		var target := 1.0
		var c := box.get_center()
		if Vector2(c.x - p.x, c.z - p.z).length() < CHECK_RADIUS + box.size.length() * 0.5:
			for sp in samples:
				if box.has_point(sp) or box.intersects_ray(sp, to_cam) != null:
					target = FADED_ALPHA
					break
		var alpha: float = item.alpha
		if is_equal_approx(alpha, target):
			continue
		alpha = move_toward(alpha, target, delta * FADE_SPEED)
		item.alpha = alpha
		_apply(item, alpha)


func _apply(item: Dictionary, alpha: float) -> void:
	var mats: Array = item.mats
	if mats.is_empty():
		var node: Node3D = item.node
		for n in node.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var base := mi.get_active_material(i) as BaseMaterial3D
				if base == null:
					continue
				var m := base.duplicate() as BaseMaterial3D
				mi.set_surface_override_material(i, m)
				mats.append(m)
	var faded := alpha < 0.995
	for m in mats:
		var bm := m as BaseMaterial3D
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if faded else BaseMaterial3D.TRANSPARENCY_DISABLED
		bm.albedo_color.a = alpha if faded else 1.0
