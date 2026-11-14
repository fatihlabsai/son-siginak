class_name Barricade
extends StaticBody3D
## Oyuncunun kurduğu barikat. Zombileri durdurur; zombiler onu döverek kırar.
## Oyuncu tahta harcayarak onarabilir (E basılı).

const LENGTH := 3.0

var kind := "wood_barricade"
var max_hp := 250.0
var hp := 250.0
var display_name := "Tahta barikat"
var _model: Node3D
var _mats: Array[BaseMaterial3D] = []


func setup(p_kind: String, p_hp: float, p_name: String) -> void:
	kind = p_kind
	max_hp = p_hp
	hp = p_hp
	display_name = p_name


func _ready() -> void:
	add_to_group("barricades")
	collision_layer = 1
	collision_mask = 0
	_model = PropLibrary.instance("barricade", LENGTH)
	var a := PropLibrary.aabb("barricade")
	var size := a.size * LENGTH
	var center := (a.position + a.size * 0.5) * LENGTH
	if _model == null:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 1.0, LENGTH)
		mi.mesh = bm
		_model = mi
		size = bm.size
		center = Vector3(0, 0.5, 0)
	add_child(_model)
	# Biraz kalınlaştırılmış çarpışma kutusu (zombiler aradan sızmasın)
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 0.5), maxf(size.y, 1.0), size.z)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(center.x, maxf(size.y, 1.0) * 0.5, center.z)
	add_child(cs)
	# Sac barikat: daha gri ve metalik görünsün
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var base := mi.get_active_material(i) as BaseMaterial3D
			if base == null:
				continue
			var m := base.duplicate() as BaseMaterial3D
			if kind == "metal_barricade":
				m.albedo_color = Color(0.62, 0.66, 0.72)
				m.metallic = 0.6
			mi.set_surface_override_material(i, m)
			_mats.append(m)
	# Kurulma animasyonu
	_model.scale *= Vector3(1, 0.05, 1)
	create_tween().tween_property(_model, "scale:y", LENGTH, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	Audio.play_3d("hit", global_position + Vector3.UP * 0.7, -2.0, 7.0, 0.15)
	Game.make_noise(global_position, 6.0)
	# Sarsıntı ve hasar rengi
	var tw := create_tween()
	tw.tween_property(_model, "position:x", 0.06, 0.04)
	tw.tween_property(_model, "position:x", -0.04, 0.05)
	tw.tween_property(_model, "position:x", 0.0, 0.05)
	_update_tint()
	if hp <= 0.0:
		_break()


func repair(amount: float) -> void:
	hp = minf(hp + amount, max_hp)
	_update_tint()


func hp_ratio() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func _update_tint() -> void:
	var dmg := 1.0 - hp_ratio()
	var base := Color(0.62, 0.66, 0.72) if kind == "metal_barricade" else Color.WHITE
	for m in _mats:
		m.albedo_color = base.lerp(Color(0.35, 0.25, 0.2), dmg * 0.7)


func _break() -> void:
	remove_from_group("barricades")
	collision_layer = 0
	Audio.play_3d("hit", global_position + Vector3.UP * 0.7, 4.0, 10.0, 0.1)
	if is_instance_valid(Game.player):
		Game.player.message.emit("%s yıkıldı!" % display_name)
	# Kalıntılardan biraz malzeme düşer
	if is_instance_valid(Game.level) and randf() < 0.6:
		Game.level.spawn_pickup("wood", global_position, false, 1)
	var tw := create_tween()
	tw.tween_property(_model, "scale:y", 0.05, 0.3)
	tw.tween_callback(queue_free)
