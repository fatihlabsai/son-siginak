class_name Throwable
extends Node3D
## Fırlatılan eşya (molotof / gürültücü). Hedefe kavisli uçar; yola duvar çıkarsa orada düşer.
## Düşünce: molotof -> yangın alanı, gürültücü -> 12 sn ses çıkaran cihaz.

const FIRE_TIME := 7.0
const FIRE_RADIUS := 2.3
const FIRE_DPS_ZOMBIE := 20.0
const FIRE_DPS_PLAYER := 10.0
const NOISE_TIME := 12.0
const NOISE_RADIUS := 28.0

var kind := "molotov"
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _flight := 0.6
var _t := 0.0
var _height := 2.5
var _landed := false
var _life := 0.0
var _tick := 0.0
var _mesh: Node3D
var _light: OmniLight3D
var _exclude: Array[RID] = []


static func launch(parent: Node, item: String, from: Vector3, to: Vector3, thrower: CollisionObject3D) -> Throwable:
	var t := Throwable.new()
	t.kind = item
	t._from = from
	t._to = to
	var d := Vector2(to.x - from.x, to.z - from.z).length()
	t._flight = clampf(0.35 + d * 0.05, 0.35, 1.0)
	t._height = clampf(1.0 + d * 0.22, 1.0, 3.5)
	if thrower:
		t._exclude.append(thrower.get_rid())
	parent.add_child(t)
	t.global_position = from
	return t


func _ready() -> void:
	_mesh = _make_projectile_mesh()
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	if not _landed:
		_fly(delta)
		return
	_life += delta
	if kind == "molotov":
		_update_fire(delta)
	else:
		_update_noisemaker(delta)


# ------------------------------------------------------------------
# Uçuş
# ------------------------------------------------------------------

func _fly(delta: float) -> void:
	var prev := global_position
	_t = minf(_t + delta / _flight, 1.0)
	var p := _from.lerp(_to, _t)
	p.y += 4.0 * _height * _t * (1.0 - _t)
	# Duvar / araba vb. çarpması
	var q := PhysicsRayQueryParameters3D.create(prev, p)
	q.exclude = _exclude
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var n: Vector3 = hit.normal
		p = hit.position + n * 0.15
		p.y = _to.y
		_land(p)
		return
	global_position = p
	_mesh.rotate_x(delta * 14.0)
	if _t >= 1.0:
		_land(_to)


func _land(p: Vector3) -> void:
	_landed = true
	global_position = Vector3(p.x, _to.y, p.z)
	_mesh.rotation = Vector3.ZERO
	if kind == "molotov":
		_mesh.queue_free()
		Audio.play_3d("hit", global_position, 0.0, 8.0, 0.2)
		_start_fire()
	else:
		_mesh.rotation = Vector3(0, randf() * TAU, PI / 2.0)
		_mesh.position.y = 0.06
		_start_noisemaker()


# ------------------------------------------------------------------
# Molotof yangını
# ------------------------------------------------------------------

func _start_fire() -> void:
	Game.make_noise(global_position, 20.0)
	var fire := CPUParticles3D.new()
	fire.amount = 200
	fire.lifetime = 0.6
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fire.emission_box_extents = Vector3(FIRE_RADIUS * 0.7, 0.05, FIRE_RADIUS * 0.7)
	fire.direction = Vector3.UP
	fire.spread = 12.0
	fire.gravity = Vector3(0, 2.0, 0)
	fire.initial_velocity_min = 0.6
	fire.initial_velocity_max = 1.6
	fire.scale_amount_min = 0.5
	fire.scale_amount_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	fire.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.7, 0.15, 1.0))
	grad.set_color(1, Color(0.12, 0.1, 0.1, 0.0))
	grad.add_point(0.35, Color(0.95, 0.3, 0.02, 0.95))
	grad.add_point(0.7, Color(0.45, 0.06, 0.01, 0.55))
	fire.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.58)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = flame_tex()
	quad.material = mat
	fire.mesh = quad
	fire.position.y = 0.15
	add_child(fire)

	# Yanmış zemin lekesi
	var scorch := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * FIRE_RADIUS * 2.2
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.03, 0.02, 0.02, 0.75)
	smat.albedo_texture = soft_dot()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plane.material = smat
	scorch.mesh = plane
	scorch.position.y = 0.03
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(scorch)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 9.0
	_light.light_energy = 4.0
	_light.shadow_enabled = false
	_light.position.y = 1.0
	add_child(_light)
	Audio.attach_loop("fire", self, Vector3.UP * 0.5, 2.0, 7.0)


func _update_fire(delta: float) -> void:
	var fade := clampf((FIRE_TIME - _life) / 1.5, 0.0, 1.0)
	_light.light_energy = (3.2 + sin(_life * 23.0) * 0.6 + sin(_life * 37.0) * 0.5) * fade
	_tick -= delta
	if _tick <= 0.0 and _life < FIRE_TIME:
		_tick = 0.25
		for node in get_tree().get_nodes_in_group("zombies"):
			var z := node as Zombie
			if z and not z.is_dead and _flat(z.global_position) <= FIRE_RADIUS:
				z.burn(FIRE_DPS_ZOMBIE * 0.25)
		var p := Game.player
		if is_instance_valid(p) and not p.is_dead and _flat(p.global_position) <= FIRE_RADIUS:
			p.take_damage(FIRE_DPS_PLAYER * 0.25)
	if _life >= FIRE_TIME:
		for c in get_children():
			if c is CPUParticles3D:
				c.emitting = false
	if _life >= FIRE_TIME + 1.5:
		queue_free()


# ------------------------------------------------------------------
# Gürültücü
# ------------------------------------------------------------------

func _start_noisemaker() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.15, 0.1)
	_light.omni_range = 4.0
	_light.light_energy = 0.0
	_light.position.y = 0.4
	add_child(_light)
	_tick = 0.0


func _update_noisemaker(delta: float) -> void:
	_tick -= delta
	_light.light_energy = maxf(_light.light_energy - delta * 12.0, 0.0)
	if _tick <= 0.0 and _life < NOISE_TIME:
		_tick = 1.0
		Game.make_noise(global_position, NOISE_RADIUS)
		Audio.play_3d("empty_click", global_position, 6.0, 14.0, 0.15)
		Audio.play_3d("flashlight", global_position, 2.0, 12.0, 0.3)
		_light.light_energy = 3.0
	if _life >= NOISE_TIME + 4.0:
		queue_free()


# ------------------------------------------------------------------

func _flat(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _make_projectile_mesh() -> Node3D:
	var root := Node3D.new()
	var m := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	if kind == "molotov":
		var c := CylinderMesh.new()
		c.top_radius = 0.035
		c.bottom_radius = 0.06
		c.height = 0.26
		m.mesh = c
		mat.albedo_color = Color(0.35, 0.5, 0.25, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.15
		var rag := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.05, 0.1, 0.05)
		rag.mesh = b
		rag.position.y = 0.17
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(1.0, 0.6, 0.2)
		rmat.emission_enabled = true
		rmat.emission = Color(1.0, 0.45, 0.1)
		rmat.emission_energy_multiplier = 3.0
		b.material = rmat
		root.add_child(rag)
	else:
		var c := CylinderMesh.new()
		c.top_radius = 0.06
		c.bottom_radius = 0.06
		c.height = 0.14
		m.mesh = c
		mat.albedo_color = Color(0.55, 0.55, 0.52)
		mat.metallic = 0.7
		mat.roughness = 0.4
	(m.mesh as PrimitiveMesh).material = mat
	root.add_child(m)
	return root


static var _dot_tex: Texture2D
static var _flame_tex: Texture2D

## Damla biçimli alev dokusu (altı yuvarlak, üstü sivri).
static func flame_tex() -> Texture2D:
	if _flame_tex:
		return _flame_tex
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 32:
			var u := (x - 15.5) / 15.5
			var v := y / 63.0          # 0 üst, 1 alt
			var w := clampf(sqrt(clampf(v, 0.0, 1.0)) * 1.15, 0.0, 1.0)   # üste doğru daralır
			var a := 1.0 - clampf(absf(u) / maxf(w, 0.01), 0.0, 1.0)
			a *= clampf((1.0 - v) * 5.0, 0.0, 1.0) * clampf(v * 1.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_flame_tex = ImageTexture.create_from_image(img)
	return _flame_tex

static func soft_dot() -> Texture2D:
	if _dot_tex:
		return _dot_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	_dot_tex = t
	return t


static func clear() -> void:
	_dot_tex = null
	_flame_tex = null
