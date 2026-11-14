class_name SpikeTrap
extends Area3D
## Kazık tuzağı: üstünden geçen zombilere hasar verir ve onları yavaşlatır.
## Her hasar verişte yıpranır, sonunda kırılır.

const SIZE := 1.8
const TICK := 0.5
const DAMAGE := 9.0

var uses := 24
var _timer := 0.0


func _ready() -> void:
	add_to_group("traps")
	collision_layer = 0
	collision_mask = 4   # zombiler
	monitoring = true
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE, 1.0, SIZE)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.5
	add_child(cs)
	_build_visual()


func _build_visual() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.18)
	wood.roughness = 1.0
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SIZE, 0.08, SIZE)
	bm.material = wood
	base.mesh = bm
	base.position.y = 0.04
	add_child(base)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 4:
		for j in 4:
			var stake := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.06
			cm.height = rng.randf_range(0.45, 0.65)
			cm.material = wood
			stake.mesh = cm
			var x := -SIZE * 0.4 + i * SIZE * 0.8 / 3.0 + rng.randf_range(-0.08, 0.08)
			var z := -SIZE * 0.4 + j * SIZE * 0.8 / 3.0 + rng.randf_range(-0.08, 0.08)
			stake.position = Vector3(x, 0.08 + cm.height * 0.5, z)
			stake.rotation = Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
			add_child(stake)


func _physics_process(delta: float) -> void:
	_timer -= delta
	var hit := false
	for body in get_overlapping_bodies():
		var z := body as Zombie
		if z == null or z.is_dead:
			continue
		z.slow_until = Time.get_ticks_msec() + 600
		if _timer <= 0.0:
			z.take_damage(DAMAGE, Vector3.ZERO, 0.0)
			hit = true
	if _timer <= 0.0:
		_timer = TICK
		if hit:
			uses -= 1
			if uses <= 0:
				if is_instance_valid(Game.player):
					Game.player.message.emit("Kazık tuzağı kırıldı.")
				queue_free()
