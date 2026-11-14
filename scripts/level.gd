class_name Level
extends NavigationRegion3D
## Seviye: yer tutucu kasabayı üretir, navigasyon ağını (navmesh) pişirir, erzak dağıtır.
##
## Tripo modellerinle kendi haritanı kurduğunda:
##  1) Modelleri "Level/Props" altına koy (çarpışma için StaticBody3D + CollisionShape3D olmalı)
##  2) generate_placeholder_town = false yap
## Navmesh her açılışta bu düğümün altındaki statik çarpıştırıcılardan yeniden pişirilir.

@export var generate_placeholder_town := true
@export var town_seed := 1337
@export var map_half_size := 58.0
@export var bake_at_runtime := true
@export var pickup_scene: PackedScene
@export var pickup_count := 35

@onready var props: Node3D = $Props

var _rng := RandomNumberGenerator.new()
var _occupied: Array[Rect2] = []
var _mat_cache := {}
var _campfire_light: OmniLight3D
var _t := 0.0


var _fader: OcclusionFader


func _ready() -> void:
	Game.level = self
	_fader = OcclusionFader.new()
	_fader.name = "OcclusionFader"
	add_child(_fader)
	_rng.seed = town_seed
	if generate_placeholder_town:
		_build_town()
	var map := get_navigation_map()
	if bake_at_runtime:
		bake_navigation_mesh(false)
	# NavigationServer haritayı sonraki karelerde senkronlar. Pişirilen navmesh haritaya
	# gerçekten girene kadar bekle (öncesinde sorgular hep (0,0,0) döndürür).
	var probe := Vector3(map_half_size * 0.5, 0.0, -map_half_size * 0.5)
	for i in 300:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 \
				and NavigationServer3D.map_get_closest_point(map, probe).length() > 1.0:
			break
	if Game.pending_load.is_empty():
		_scatter_pickups()
		Game.nav_ready = true
	else:
		Game.nav_ready = true
		_apply_save(Game.pending_load)
		Game.pending_load = {}
	Game.level_ready.emit()


# ------------------------------------------------------------------
# Kayıt
# ------------------------------------------------------------------

var _searchables: Array[Searchable] = []


func searched_ids() -> Array:
	var out := []
	for i in _searchables.size():
		var s := _searchables[i]
		if is_instance_valid(s) and s.searched:
			out.append(i)
	return out


## Kayıttan dünyayı geri kurar (harita aynı tohumla zaten kurulmuş olur).
func _apply_save(d: Dictionary) -> void:
	Game.loaded_from_save = true
	var scene := get_tree().current_scene
	# Aranmış yerler
	for id in d.get("searched", []):
		var i := int(id)
		if i >= 0 and i < _searchables.size():
			_searchables[i].searched = true
			_searchables[i].remove_from_group("searchables")
	# Yerdeki eşyalar
	for e in d.get("pickups", []):
		spawn_pickup(String(e.type), Game.to_vec(e.pos), false, int(e.amount), int(e.durability))
	# Barikatlar ve tuzaklar
	for e in d.get("barricades", []):
		var b := Barricade.new()
		b.setup(String(e.kind), float(e.max_hp), String(e.name))
		scene.add_child(b)
		b.global_position = Game.to_vec(e.pos)
		b.rotation.y = float(e.rot)
		b.hp = float(e.hp)
		b.call_deferred("repair", 0.0)   # hasar rengini güncelle
	for e in d.get("traps", []):
		var t := SpikeTrap.new()
		scene.add_child(t)
		t.global_position = Game.to_vec(e.pos)
		t.rotation.y = float(e.rot)
		t.uses = int(e.uses)
	# Zombiler
	var spawner := scene.get_node_or_null("ZombieSpawner")
	if spawner:
		spawner.set("_last_horde_day", int(d.get("last_horde_day", 0)))
		for e in d.get("zombies", []):
			var z: Zombie = spawner.call("_spawn_at", Game.to_vec(e.pos))
			if z:
				z.health = float(e.health)
	# Oyuncu
	var p := Game.player
	var pd: Dictionary = d.get("player", {})
	if is_instance_valid(p) and not pd.is_empty():
		p.global_position = Game.to_vec(pd.pos) + Vector3.UP * 0.1
		p.model_pivot.rotation.y = float(pd.get("yaw", 0.0))
		p.health = float(pd.health)
		p.stamina = float(pd.stamina)
		p.hunger = float(pd.hunger)
		p.thirst = float(pd.thirst)
		p.inv.items.clear()
		for k in pd.get("items", {}):
			p.inv.items[String(k)] = int(pd.items[k])
		p.inv.weapons.clear()
		for w in pd.get("weapons", []):
			p.inv.weapons.append({"id": String(w.id), "durability": int(w.durability)})
		p.inv.equip(int(pd.get("equipped", -1)))
		if bool(pd.get("flashlight", false)):
			p.flashlight_on = true
			p.flashlight.visible = true
		var rig := scene.get_node_or_null("CameraRig") as Node3D
		if rig:
			rig.global_position = p.global_position


func _process(delta: float) -> void:
	_t += delta
	if _campfire_light:
		_campfire_light.light_energy = 2.4 + sin(_t * 13.0) * 0.25 + sin(_t * 7.3) * 0.2 + randf() * 0.3


## amount -1 = türe göre otomatik (mermi için birkaç tane, diğerleri 1)
func spawn_pickup(type: String, pos: Vector3, snap := false, amount := -1, durability := -1) -> void:
	if pickup_scene == null:
		return
	if snap and NavigationServer3D.map_get_iteration_id(get_navigation_map()) > 0:
		var snapped := NavigationServer3D.map_get_closest_point(get_navigation_map(), pos)
		if snapped.length() > 0.01:
			pos = snapped
	if type == "ammo":
		type = "pistol_ammo"
	var pk := pickup_scene.instantiate() as Pickup
	pk.item_type = type
	if amount < 0:
		match type:
			"pistol_ammo":
				amount = _rng.randi_range(3, 8)
			"shells":
				amount = _rng.randi_range(2, 4)
			"nails":
				amount = _rng.randi_range(3, 8)
			_:
				amount = 1
	pk.amount = amount
	pk.durability = durability
	pk.position = Vector3(pos.x, 0.0, pos.z)
	var holder := get_node_or_null("../Pickups")
	if holder:
		holder.add_child(pk)
	else:
		add_child(pk)


func _scatter_pickups() -> void:
	spawn_pickup("food", Vector3(-3, 0, 2))
	spawn_pickup("water", Vector3(-2, 0, 3))
	# Asıl erzak artık aranabilir yerlerde; yerde daha az eşya var.
	var types := ["food", "water", "water", "pistol_ammo", "wood", "scrap", "bat"]
	for i in int(pickup_count * 0.5 * Settings.diff("loot")):
		var p := Vector3(_rng.randf_range(-map_half_size + 3.0, map_half_size - 3.0), 0.0, _rng.randf_range(-map_half_size + 3.0, map_half_size - 3.0))
		if p.length() < 12.0:
			continue
		spawn_pickup(types[_rng.randi() % types.size()], p, true)


# ------------------------------------------------------------------
# Yer tutucu kasaba (Tripo modelleri gelene kadar)
# ------------------------------------------------------------------

func _build_town() -> void:
	var ground := get_node_or_null("Ground/Mesh") as MeshInstance3D
	if ground:
		ground.material_override = GroundBuilder.ground_material(Vector2.ZERO, 10.0)
	var road_z := _add_visual(Vector3(0, 0.01, 0), _box_mesh(Vector3(8, 0.02, map_half_size * 2.0)), Color.BLACK)
	road_z.material_override = GroundBuilder.road_material(0, 4.0)
	var road_x := _add_visual(Vector3(0, 0.012, 0), _box_mesh(Vector3(map_half_size * 2.0, 0.02, 8)), Color.BLACK)
	road_x.material_override = GroundBuilder.road_material(1, 4.0)
	# Solmuş, yer yer kopuk şerit çizgileri
	var stripe := Color(0.5, 0.46, 0.32)
	for i in range(-int(map_half_size), int(map_half_size), 6):
		if abs(i) < 10:
			continue
		if _rng.randf() > 0.15:
			_add_visual(Vector3(0, 0.025, i), _box_mesh(Vector3(0.18, 0.01, _rng.randf_range(1.2, 2.5))), stripe.darkened(_rng.randf() * 0.3))
		if _rng.randf() > 0.15:
			_add_visual(Vector3(i, 0.025, 0), _box_mesh(Vector3(_rng.randf_range(1.2, 2.5), 0.01, 0.18)), stripe.darkened(_rng.randf() * 0.3))

	_reserve(Rect2(-5, -map_half_size, 10, map_half_size * 2.0))
	_reserve(Rect2(-map_half_size, -5, map_half_size * 2.0, 10))
	_reserve(Rect2(-11, -11, 22, 22))

	_build_border()
	_build_camp()
	_build_buildings(24)
	_build_cars(16)
	_build_trees(50)
	_build_clutter(35)
	_build_grass()


func _build_grass() -> void:
	var counts := [0, 4500, 10000]
	var count: int = counts[clampi(Settings.quality, 0, 2)]
	var area := Rect2(-map_half_size + 1.0, -map_half_size + 1.0, map_half_size * 2.0 - 2.0, map_half_size * 2.0 - 2.0)
	GroundBuilder.add_grass(props, count, area, _grass_ok, _rng)


func _grass_ok(p: Vector2) -> bool:
	if absf(p.x) < 4.6 or absf(p.y) < 4.6:
		return false
	return not _overlaps(Rect2(p - Vector2(0.3, 0.3), Vector2(0.6, 0.6)))


func _build_border() -> void:
	var col := Color(0.3, 0.27, 0.23)
	var s := map_half_size
	_add_box(Vector3(0, 1.25, -s), Vector3(s * 2.0, 2.5, 0.4), col)
	_add_box(Vector3(0, 1.25, s), Vector3(s * 2.0, 2.5, 0.4), col)
	_add_box(Vector3(-s, 1.25, 0), Vector3(0.4, 2.5, s * 2.0), col)
	_add_box(Vector3(s, 1.25, 0), Vector3(0.4, 2.5, s * 2.0), col)


func _build_camp() -> void:
	# Ortadaki sığınak: barikat duvarı (4 kapılı), çadırlar, kamp ateşi, sandıklar
	var s := 9.0
	var seg := 3.5   # bir barikat parçasının uzunluğu
	for side in 4:
		for sgn in [-1.0, 1.0]:
			for k in 2:
				var along: float = sgn * (2.0 + seg * 0.5 + seg * k)
				var pos: Vector3
				var yaw := 0.0
				match side:
					0:
						pos = Vector3(along, 0, -s)
						yaw = PI / 2.0
					1:
						pos = Vector3(along, 0, s)
						yaw = -PI / 2.0
					2:
						pos = Vector3(-s, 0, along)
					_:
						pos = Vector3(s, 0, along)
						yaw = PI
				yaw += _rng.randf_range(-0.04, 0.04)
				if not PropLibrary.spawn(props, "barricade", pos, seg, yaw):
					var size := Vector3(seg, 2.0, 0.3) if side < 2 else Vector3(0.3, 2.0, seg)
					_add_box(pos + Vector3.UP, size, Color(0.36, 0.26, 0.17))

	for t in [[Vector3(-5.5, 0, -5.5), 0.3], [Vector3(5.5, 0, -5.5), -0.4 + PI]]:
		if not PropLibrary.spawn(props, "tent", t[0], 3.6, t[1]):
			var tent := PrismMesh.new()
			tent.size = Vector3(3.0, 2.0, 3.5)
			var tent_shape := BoxShape3D.new()
			tent_shape.size = Vector3(2.6, 2.0, 3.2)
			_add_static(t[0] + Vector3.UP, tent, tent_shape, Color(0.3, 0.36, 0.25), t[1])

	# Kamp ateşi
	var fire_body: Node3D = PropLibrary.spawn(props, "campfire", Vector3(3, 0, 3), 1.5, 0.0, "box", Vector3(0.8, 1.0, 0.8))
	if fire_body == null:
		var ring := CylinderMesh.new()
		ring.top_radius = 0.7
		ring.bottom_radius = 0.75
		ring.height = 0.2
		var ring_shape := CylinderShape3D.new()
		ring_shape.radius = 0.7
		ring_shape.height = 0.4
		fire_body = _add_static(Vector3(3, 0.1, 3), ring, ring_shape, Color(0.3, 0.3, 0.3))
	_add_embers(fire_body)
	_campfire_light = OmniLight3D.new()
	_campfire_light.light_color = Color(1.0, 0.6, 0.25)
	_campfire_light.omni_range = 9.0
	_campfire_light.light_energy = 2.5
	_campfire_light.shadow_enabled = true
	_campfire_light.position.y = 1.0
	fire_body.add_child(_campfire_light)
	Audio.attach_loop("fire", fire_body, Vector3(0, 0.4, 0), -2.0, 4.0)

	var crates := [[Vector3(-6.5, 0, 4.0), 0.0], [Vector3(-5.5, 0, 4.4), 0.0], [Vector3(-6.0, 0.65, 4.2), 0.0], [Vector3(6.5, 0, 5.5), 0.0]]
	for i in crates.size():
		var c: Array = crates[i]
		var crate := PropLibrary.spawn(props, "crate", c[0], 0.9, _rng.randf_range(-0.4, 0.4))
		if crate == null:
			_add_box(c[0] + Vector3.UP * 0.4, Vector3(0.8, 0.8, 0.8), Color(0.45, 0.35, 0.22))
		elif i == 0 or i == 3:
			_add_searchable(crate, Vector3.ZERO, "crate", "Sandığı aç", 1.4)
	PropLibrary.spawn(props, "barrel", Vector3(-3.5, 0, 6.8), 0.95)
	PropLibrary.spawn(props, "barrel", Vector3(-2.7, 0, 7.2), 0.95)


func _add_searchable(parent: Node3D, local_pos: Vector3, table: String, label: String, reach: float) -> void:
	var s := Searchable.new()
	s.table = table
	s.label = label
	s.reach = reach
	s.position = local_pos
	parent.add_child(s)
	_searchables.append(s)


## Kamp ateşinden yükselen kıvılcımlar
func _add_embers(parent: Node3D) -> void:
	var spark := SphereMesh.new()
	spark.radius = 0.025
	spark.height = 0.05
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.2)
	spark.material = mat
	var embers := CPUParticles3D.new()
	embers.mesh = spark
	embers.amount = 24
	embers.lifetime = 2.2
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.3
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.initial_velocity_min = 0.6
	embers.initial_velocity_max = 1.4
	embers.gravity = Vector3(0.1, 0.1, 0)
	embers.position.y = 0.5
	parent.add_child(embers)


## Binalar: çiftlik evi, ev, ahır, market. Ön yüzleri (+Z) en yakın yola bakar.
func _build_buildings(count: int) -> void:
	var kinds := ["farmhouse", "farmhouse", "house", "house", "house", "barn", "store"]
	var placed := 0
	var tries := 0
	while placed < count and tries < 800:
		tries += 1
		var kind: String = kinds[_rng.randi() % kinds.size()]
		var s := _rng.randf_range(10.0, 14.0)
		if kind == "store":
			s = _rng.randf_range(11.0, 15.0)
		var c := Vector2(_rng.randf_range(-map_half_size + 9.0, map_half_size - 9.0), _rng.randf_range(-map_half_size + 9.0, map_half_size - 9.0))
		var yaw: float
		if absf(c.x) < absf(c.y):
			yaw = -signf(c.x) * PI / 2.0
		else:
			yaw = 0.0 if c.y < 0.0 else PI
		var fp := PropLibrary.footprint(kind, s, yaw) if PropLibrary.has(kind) else Vector2(s * 0.7, s * 0.7)
		var rect := Rect2(c - fp / 2.0, fp)
		if _overlaps(rect.grow(3.0)):
			continue
		_reserve(rect)
		var building := PropLibrary.spawn(props, kind, Vector3(c.x, 0, c.y), s, yaw)
		if building:
			_fader.add(building, PropLibrary.aabb(kind), s)
			# Ön kapı (modelin +Z yüzü) önünde aranabilir nokta
			var a := PropLibrary.aabb(kind)
			var labels := {"farmhouse": "Evi ara", "house": "Evi ara", "barn": "Ahırı ara", "store": "Marketi ara"}
			_add_searchable(building, Vector3(a.get_center().x * s, 0, a.end.z * s + 0.9), "house", labels.get(kind, "Ara"), 2.2)
		else:
			var h := _rng.randf_range(3.0, 5.5)
			_add_box(Vector3(c.x, h / 2.0, c.y), Vector3(fp.x, h, fp.y), Color(0.42, 0.4, 0.37))
		placed += 1


func _build_cars(count: int) -> void:
	for i in count:
		var along := _rng.randf_range(-map_half_size + 6.0, map_half_size - 6.0)
		if absf(along) < 13.0:
			continue
		var lateral := _rng.randf_range(-2.4, 2.4)
		var on_z_road := _rng.randf() < 0.5
		var pos := Vector3(lateral, 0.0, along) if on_z_road else Vector3(along, 0.0, lateral)
		var yaw := (0.0 if on_z_road else PI / 2.0) + _rng.randf_range(-0.5, 0.5)
		if _rng.randf() < 0.5:
			yaw += PI
		var kind := "pickup_truck" if _rng.randf() < 0.45 else "sedan_car"
		var length := 5.3 if kind == "pickup_truck" else 4.6
		var car := PropLibrary.spawn(props, kind, pos, length, yaw, "box", Vector3(0.95, 0.9, 0.95))
		if car:
			# Arka taraf (bagaj): modelin -Z ucu
			var a := PropLibrary.aabb(kind)
			_add_searchable(car, Vector3(0, 0, a.position.z * length - 0.8), "car", "Arabayı ara", 1.9)
		else:
			_add_box(pos + Vector3.UP * 0.65, Vector3(1.9, 1.0, 4.3), Color(0.45, 0.2, 0.15), yaw)


func _build_trees(count: int) -> void:
	for i in count:
		var p := Vector2(_rng.randf_range(-map_half_size + 2.0, map_half_size - 2.0), _rng.randf_range(-map_half_size + 2.0, map_half_size - 2.0))
		var r := Rect2(p - Vector2(1, 1), Vector2(2, 2))
		if _overlaps(r):
			continue
		_reserve(r)
		var dead := _rng.randf() < 0.35
		var kind := "dead_tree" if dead else "pine_tree"
		var s := _rng.randf_range(5.0, 8.0) if dead else _rng.randf_range(7.0, 11.0)
		var tree := PropLibrary.spawn(props, kind, Vector3(p.x, 0, p.y), s, _rng.randf() * TAU, "trunk")
		if tree:
			_fader.add(tree, PropLibrary.aabb(kind), s, 0.75)
			continue
		var trunk_h := _rng.randf_range(2.5, 4.0)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.28
		cyl.height = trunk_h
		var shape := CylinderShape3D.new()
		shape.radius = 0.3
		shape.height = trunk_h
		var body := _add_static(Vector3(p.x, trunk_h / 2.0, p.y), cyl, shape, Color(0.25, 0.18, 0.12))
		if _rng.randf() < 0.3:
			continue  # kuru ağaç
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = _rng.randf_range(1.2, 2.0)
		cone.height = _rng.randf_range(2.5, 4.0)
		var foliage := MeshInstance3D.new()
		foliage.mesh = cone
		foliage.material_override = _mat(Color(0.16, 0.24, 0.15).lerp(Color(0.28, 0.3, 0.18), _rng.randf()))
		foliage.position.y = trunk_h / 2.0 + cone.height / 2.0 - 0.6
		body.add_child(foliage)


func _build_clutter(count: int) -> void:
	for i in count:
		var p := Vector2(_rng.randf_range(-map_half_size + 2.0, map_half_size - 2.0), _rng.randf_range(-map_half_size + 2.0, map_half_size - 2.0))
		var r := Rect2(p - Vector2(1.2, 1.2), Vector2(2.4, 2.4))
		if _overlaps(r) or p.length() < 12.0:
			continue
		_reserve(r)
		var kind := _rng.randi() % 3
		var model_keys := ["barrel", "crate", "dumpster"]
		var model_scales := [0.95, 0.9, 1.2]
		var prop := PropLibrary.spawn(props, model_keys[kind], Vector3(p.x, 0, p.y), model_scales[kind], _rng.randf() * TAU)
		if prop:
			if kind == 1:
				_add_searchable(prop, Vector3.ZERO, "crate", "Sandığı aç", 1.4)
			elif kind == 2:
				_add_searchable(prop, Vector3.ZERO, "dumpster", "Çöpü karıştır", 1.5)
			# Bazen yanına ikinci bir varil/sandık
			if kind < 2 and _rng.randf() < 0.4:
				PropLibrary.spawn(props, model_keys[kind], Vector3(p.x + 0.8, 0, p.y + 0.3), model_scales[kind], _rng.randf() * TAU)
			continue
		match kind:
			0:  # varil
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.35
				cyl.bottom_radius = 0.35
				cyl.height = 1.0
				var shape := CylinderShape3D.new()
				shape.radius = 0.35
				shape.height = 1.0
				_add_static(Vector3(p.x, 0.5, p.y), cyl, shape, Color(0.4, 0.22, 0.12))
			1:  # sandık
				_add_box(Vector3(p.x, 0.45, p.y), Vector3(0.9, 0.9, 0.9), Color(0.45, 0.35, 0.22), _rng.randf() * TAU)
			_:  # çöp konteyneri
				_add_box(Vector3(p.x, 0.65, p.y), Vector3(1.9, 1.3, 1.1), Color(0.2, 0.3, 0.22), _rng.randf() * TAU)


# --- Yardımcılar ---

func _reserve(r: Rect2) -> void:
	_occupied.append(r)


func _overlaps(r: Rect2) -> bool:
	for o in _occupied:
		if o.intersects(r):
			return true
	return false


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		_mat_cache[key] = m
	return _mat_cache[key]


func _box_mesh(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


func _add_static(pos: Vector3, mesh: Mesh, shape: Shape3D, color: Color, rot_y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	props.add_child(body)
	return body


func _add_box(center: Vector3, size: Vector3, color: Color, rot_y := 0.0) -> StaticBody3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return _add_static(center, _box_mesh(size), shape, color, rot_y)


func _add_visual(pos: Vector3, mesh: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	props.add_child(mi)
	return mi
