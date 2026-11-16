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
## Haritada gösterilecek bina alanları
var map_buildings: Array[Rect2] = []
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
		_setup_new_run()
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
		if i >= 0 and i < _searchables.size() and is_instance_valid(_searchables[i]):
			_searchables[i].restore_searched()
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
		# Sığınaktan önceki sürümlerin kayıtları: oyuncu dışarıdaysa çanta ve kapı açılmış sayılır
		if not shelter_bag_searched() and p.global_position.distance_to(shelter_center) > 8.0:
			shelter_bag.restore_searched()
			shelter_door.restore_searched()


func _process(delta: float) -> void:
	_process_story()
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
	_build_yard()
	_build_story_sites()
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


const CAMPFIRE_POS := Vector3(3, 0, 3)

func campfire_position() -> Vector3:
	return CAMPFIRE_POS


func _add_searchable(parent: Node3D, local_pos: Vector3, table: String, label: String, reach: float) -> Searchable:
	var s := Searchable.new()
	s.table = table
	s.label = label
	s.reach = reach
	s.position = local_pos
	parent.add_child(s)
	_searchables.append(s)
	return s


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
		map_buildings.append(rect)
		var building := PropLibrary.spawn(props, kind, Vector3(c.x, 0, c.y), s, yaw)
		if building:
			_fader.add(building, PropLibrary.aabb(kind), s)
			# Ön kapı (modelin +Z yüzü) önünde aranabilir nokta
			var a := PropLibrary.aabb(kind)
			var labels := {"farmhouse": "Evi ara", "house": "Evi ara", "barn": "Ahırı ara", "store": "Marketi ara"}
			var srch := _add_searchable(building, Vector3(a.get_center().x * s, 0, a.end.z * s + 0.9), "house", labels.get(kind, "Ara"), 2.2)
			_buildings_info.append({"kind": kind, "node": building, "center": Vector3(c.x, 0, c.y), "yaw": yaw, "search": srch})
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
			_tree_items.append([r, tree])
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
		_tree_items.append([r, body])
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


# ------------------------------------------------------------------
# İlçe bakım sahası ve fırtına sığınağı (oyunun başladığı yer)
# ------------------------------------------------------------------

var shelter_center := Vector3(-30, 0, 30)
var shelter_bag: Searchable
var shelter_door: Searchable
var _door_pivot: Node3D
var _door_light: SpotLight3D
var _shelter_node: Node3D
var _yard_rect := Rect2()

const SHELTER_HALF := Vector2(2.5, 2.05)   # iç yarı boyut (x, z)


func _build_yard() -> void:
	# Haritada boş bir köşe bul (tohum sabit olduğu için hep aynı yer çıkar)
	var size := Vector2(17, 13)
	var candidates := [Vector2(-30, 30), Vector2(30, 30), Vector2(-30, -30), Vector2(30, -30),
		Vector2(-40, 20), Vector2(40, 20), Vector2(-20, 40), Vector2(20, 40), Vector2(-40, -20), Vector2(40, -20)]
	var chosen := Vector2.INF
	for cand in candidates:
		if not _overlaps(Rect2(cand - size / 2.0, size)):
			chosen = cand
			break
	if chosen == Vector2.INF:
		for i in 300:
			var c2 := Vector2(_rng.randf_range(-45, 45), _rng.randf_range(-45, 45))
			if absf(c2.x) < 14 or absf(c2.y) < 14:
				continue
			if not _overlaps(Rect2(c2 - size / 2.0, size)):
				chosen = c2
				break
	if chosen == Vector2.INF:
		chosen = Vector2(-30, 30)
	_yard_rect = Rect2(chosen - size / 2.0, size)
	_reserve(_yard_rect)
	shelter_center = Vector3(chosen.x - 3.0, 0, chosen.y)
	var c := shelter_center

	# Sahanın zemini: çatlak beton
	var pad := _add_visual(Vector3(chosen.x, 0.008, chosen.y), _box_mesh(Vector3(size.x, 0.016, size.y)), Color(0.36, 0.36, 0.34))
	pad.material_override = GroundBuilder.road_material(0, 3.0)
	_build_shelter(c)

	# Belediye kamyoneti, bariyer yığını, koniler, kum yığını, tabela
	var truck := PropLibrary.spawn(props, "pickup_truck", c + Vector3(6.5, 0, -3.3), 5.0, 0.25, "box", Vector3(0.95, 0.9, 0.95))
	if truck:
		var ta := PropLibrary.aabb("pickup_truck")
		_add_searchable(truck, Vector3(0, 0, ta.position.z * 5.0 - 0.8), "car", "Kamyoneti ara", 1.9)
	for i in 4:
		var bp := c + Vector3(6.2 + (i % 2) * 0.25, 0.0, 2.6 + i * 0.32)
		CutsceneActor.spawn_prop(props, "res://assets/models/intro/barrier.glb", 1.5, bp, PI / 2.0 + _rng.randf_range(-0.1, 0.1))
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(1.0, 1.0, 1.6)
	var bbody := StaticBody3D.new()
	bbody.position = c + Vector3(6.3, 0.5, 3.1)
	var bcs := CollisionShape3D.new()
	bcs.shape = bshape
	bbody.add_child(bcs)
	props.add_child(bbody)
	for i in 5:
		_add_cone(c + Vector3(3.6 + i * 0.55, 0, 5.0 - (i % 2) * 0.4))
	var pile := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.6
	sp.height = 1.4
	pile.mesh = sp
	pile.material_override = _mat(Color(0.55, 0.5, 0.42))
	pile.position = c + Vector3(-1.0, -0.2, -5.0)
	props.add_child(pile)
	var sign := Label3D.new()
	sign.text = "İLÇE BAKIM SAHASI"
	sign.font_size = 72
	sign.outline_size = 10
	sign.modulate = Color(0.95, 0.92, 0.85)
	sign.position = c + Vector3(9.5, 2.3, 5.6)
	sign.rotation.y = PI / 4.0
	sign.pixel_size = 0.006
	props.add_child(sign)
	_add_box(c + Vector3(9.5, 1.0, 5.6), Vector3(0.12, 2.0, 0.12), Color(0.3, 0.3, 0.3))
	# Çit (yer yer kopuk)
	var fence := Color(0.45, 0.46, 0.45)
	var x0 := _yard_rect.position.x
	var x1 := _yard_rect.end.x
	var z0 := _yard_rect.position.y
	var z1 := _yard_rect.end.y
	for seg in [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x0, z0), Vector2(x0, z1)], [Vector2(x0, z1), Vector2(x0 + 6, z1)]]:
		var a: Vector2 = seg[0]
		var b2: Vector2 = seg[1]
		var n := int(a.distance_to(b2) / 2.5)
		for i in n:
			if _rng.randf() < 0.18:
				continue
			var p := a.lerp(b2, (i + 0.5) / n)
			var horiz := absf(b2.x - a.x) > absf(b2.y - a.y)
			_add_box(Vector3(p.x, 0.75, p.y), Vector3(2.3, 1.5, 0.06) if horiz else Vector3(0.06, 1.5, 2.3), fence)


func _add_cone(p: Vector3) -> void:
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.16
	cm.height = 0.5
	cone.mesh = cm
	cone.material_override = _mat(Color(0.95, 0.42, 0.1))
	cone.position = p + Vector3(0, 0.25, 0)
	props.add_child(cone)


func _build_shelter(c: Vector3) -> void:
	var hx := SHELTER_HALF.x
	var hz := SHELTER_HALF.y
	var h := 2.6
	var t := 0.3
	var concrete := Color(0.5, 0.5, 0.48)
	_shelter_node = Node3D.new()
	_shelter_node.name = "Shelter"
	props.add_child(_shelter_node)
	_shelter_node.position = c
	# Duvar, çatı ve kapı ayrı grupta: oyuncu içerideyken sadece bunlar saydamlaşır
	var shell := Node3D.new()
	shell.name = "Shell"
	_shelter_node.add_child(shell)
	var walls: Array = [
		[Vector3(-hx - t / 2, h / 2, 0), Vector3(t, h, hz * 2 + t * 2)],
		[Vector3(0, h / 2, -hz - t / 2), Vector3(hx * 2 + t * 2, h, t)],
		[Vector3(0, h / 2, hz + t / 2), Vector3(hx * 2 + t * 2, h, t)],
		# Ön duvar (+X), kapı boşluğu z = 0..1.2
		[Vector3(hx + t / 2, h / 2, (-hz - t) / 2.0), Vector3(t, h, hz + t)],
		[Vector3(hx + t / 2, h / 2, (1.2 + hz + t) / 2.0), Vector3(t, h, hz + t - 1.2)],
		[Vector3(hx + t / 2, 2.35, 0.6), Vector3(t, 0.5, 1.2)],
	]
	for w in walls:
		var body := _add_box(c + w[0], w[1], concrete)
		body.get_parent().remove_child(body)
		shell.add_child(body)
		body.position = w[0]
	# Zemin ve tavan (görsel)
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = _box_mesh(Vector3(hx * 2, 0.04, hz * 2))
	floor_mi.material_override = _mat(Color(0.32, 0.32, 0.31))
	floor_mi.position = Vector3(0, 0.02, 0)
	_shelter_node.add_child(floor_mi)
	var roof := MeshInstance3D.new()
	roof.mesh = _box_mesh(Vector3(hx * 2 + 0.9, 0.28, hz * 2 + 0.9))
	roof.material_override = _mat(Color(0.42, 0.42, 0.4))
	roof.position = Vector3(0, h + 0.14, 0)
	shell.add_child(roof)
	# İçeride raf, sandıklar, eski bir sedye
	var shelf := Color(0.3, 0.32, 0.3)
	for k in 3:
		var sb := MeshInstance3D.new()
		sb.mesh = _box_mesh(Vector3(1.6, 0.04, 0.45))
		sb.material_override = _mat(shelf)
		sb.position = Vector3(-0.3, 0.45 + k * 0.6, -hz + 0.25)
		_shelter_node.add_child(sb)
	for k in 2:
		var leg := MeshInstance3D.new()
		leg.mesh = _box_mesh(Vector3(0.04, 1.75, 0.04))
		leg.material_override = _mat(shelf)
		leg.position = Vector3(-1.1 + k * 1.6, 0.875, -hz + 0.25)
		_shelter_node.add_child(leg)
	for k in 4:
		var bx := MeshInstance3D.new()
		bx.mesh = _box_mesh(Vector3(0.35, 0.28, 0.32))
		bx.material_override = _mat(Color(0.5, 0.42, 0.3).darkened(k * 0.08))
		bx.position = Vector3(-0.8 + k * 0.38, 0.62 + (k % 2) * 0.6, -hz + 0.25)
		_shelter_node.add_child(bx)
	var cot := MeshInstance3D.new()
	cot.mesh = _box_mesh(Vector3(1.9, 0.35, 0.75))
	cot.material_override = _mat(Color(0.3, 0.34, 0.27))
	cot.position = Vector3(0.1, 0.18, hz - 0.45)
	_shelter_node.add_child(cot)
	# Çanta (kapının yanında) ve su şişesi (Caleb'in yanında)
	var bag := CutsceneActor.spawn_prop(_shelter_node, "res://assets/models/intro/duffel.glb", 0.75, Vector3(hx - 0.45, 0, -0.65), 0.4)
	shelter_bag = Searchable.new()
	shelter_bag.table = "start_bag"
	shelter_bag.label = "Çantanı kontrol et"
	shelter_bag.reach = 1.5
	bag.add_child(shelter_bag)
	_searchables.append(shelter_bag)
	var bottle := MeshInstance3D.new()
	bottle.name = "WaterBottle"
	var bc := CylinderMesh.new()
	bc.top_radius = 0.025
	bc.bottom_radius = 0.035
	bc.height = 0.24
	bottle.mesh = bc
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.75, 0.88, 0.95, 0.55)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.roughness = 0.1
	bottle.material_override = bm
	bottle.position = Vector3(-hx + 0.75, 0.12, 0.25)
	_shelter_node.add_child(bottle)
	# Çelik kapı (menteşe z = 0, kapı z = 0..1.2)
	_door_pivot = Node3D.new()
	_door_pivot.position = Vector3(hx + t / 2, 0, 0.0)
	shell.add_child(_door_pivot)
	var dshape := BoxShape3D.new()
	dshape.size = Vector3(0.06, 2.1, 1.18)
	var door := StaticBody3D.new()
	door.position = Vector3(0, 1.05, 0.6)
	var dmi := MeshInstance3D.new()
	dmi.mesh = _box_mesh(Vector3(0.06, 2.1, 1.18))
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.38, 0.4, 0.38)
	steel.metallic = 0.6
	steel.roughness = 0.55
	dmi.material_override = steel
	door.add_child(dmi)
	var dcs := CollisionShape3D.new()
	dcs.shape = dshape
	door.add_child(dcs)
	_door_pivot.add_child(door)
	# Kapının altından sızan gün ışığı
	var strip := MeshInstance3D.new()
	strip.mesh = _box_mesh(Vector3(0.03, 0.035, 1.14))
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.93, 0.8)
	strip.material_override = sm
	strip.position = Vector3(hx + 0.06, 0.018, 0.6)
	strip.name = "DoorStrip"
	_shelter_node.add_child(strip)
	# Zeminde, kapıdan içeri uzanan soluk ışık lekesi
	var glow := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(0.9, 1.3)
	glow.mesh = gq
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.7, 0.35))
	g.set_color(1, Color(1.0, 0.9, 0.7, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(1.0, 0.5)
	gt.fill_to = Vector2(0.0, 0.5)
	gm.albedo_texture = gt
	glow.material_override = gm
	glow.rotation.x = -PI / 2.0
	glow.position = Vector3(hx - 0.45, 0.045, 0.6)
	glow.name = "DoorGlow"
	_shelter_node.add_child(glow)
	_door_light = SpotLight3D.new()
	_door_light.light_color = Color(1.0, 0.9, 0.75)
	_door_light.light_energy = 3.0
	_door_light.spot_range = 3.2
	_door_light.spot_angle = 75.0
	_door_light.position = Vector3(hx + 0.05, 0.04, 0.6)
	_shelter_node.add_child(_door_light)
	_door_light.rotation = Vector3(-0.08, PI / 2.0, 0)
	shelter_door = Searchable.new()
	shelter_door.table = "door"
	shelter_door.label = "Kapıyı aç"
	shelter_door.reach = 1.4
	shelter_door.silent = true
	shelter_door.position = Vector3(hx - 0.35, 0, 0.6)
	_shelter_node.add_child(shelter_door)
	_searchables.append(shelter_door)
	shelter_door.opened.connect(func(_r: bool): _open_shelter_door())
	_fader.add(shell, AABB(Vector3(-hx - 0.5, 0, -hz - 0.5), Vector3(hx * 2 + 1.0, h + 0.3, hz * 2 + 1.0)), 1.0)


func _open_shelter_door() -> void:
	if not is_instance_valid(_door_pivot):
		return
	var tw := create_tween()
	tw.tween_property(_door_pivot, "rotation:y", deg_to_rad(105.0), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_instance_valid(_door_light):
		_door_light.visible = false
	for nm in ["DoorStrip", "DoorGlow"]:
		var n := _shelter_node.get_node_or_null(nm)
		if n:
			n.visible = false
	Audio.play_3d("hit", _door_pivot.global_position + Vector3.UP, -6.0, 6.0, 0.3)


func shelter_door_open() -> bool:
	return is_instance_valid(shelter_door) and shelter_door.searched


func shelter_bag_searched() -> bool:
	return is_instance_valid(shelter_bag) and shelter_bag.searched


func yard_rect() -> Rect2:
	return _yard_rect


func shelter_node() -> Node3D:
	return _shelter_node


## Oyuncunun sığınakta oturduğu nokta (kapıya doğru, +X bakar)
func shelter_start() -> Vector3:
	return shelter_center + Vector3(-SHELTER_HALF.x + 0.55, 0.05, -0.1)


## Yeni oyun: oyuncu sığınakta, elinde hiçbir şey yok, yorgun ve susuz.
func _setup_new_run() -> void:
	var p := Game.player
	if not is_instance_valid(p):
		return
	p.global_position = shelter_start()
	p.model_pivot.rotation.y = PI / 2.0
	p.inv.items.clear()
	p.inv.weapons.clear()
	p.inv.equip(-1)
	p.inv.changed.emit()
	p.health = 72.0
	p.thirst = 26.0
	p.hunger = 58.0
	var rig := get_tree().current_scene.get_node_or_null("CameraRig") as Node3D
	if rig:
		rig.global_position = p.global_position
	# Sahada birkaç işe yarar şey
	spawn_pickup("wood", shelter_center + Vector3(4.0, 0, -4.4), false, 2)
	spawn_pickup("water", shelter_center + Vector3(7.8, 0, -1.2), false, 1)
	for e in _story_pickups:
		spawn_pickup(e[0], e[1], false, e[2])
	if Game.play_shelter_intro:
		var intro := ShelterIntro.new()
		get_tree().current_scene.add_child(intro)


# ------------------------------------------------------------------
# Hikâye: Bölüm 1 — Mercer evi ve Kuzey Lisesi (tahliye noktası)
# ------------------------------------------------------------------

signal story_event(id: String)

var house_center := Vector3.INF
var school_center := Vector3.INF
var story_house: Searchable
var story_school: Searchable
var _school_horde_done := false
var _story_pickups: Array = []
var _tree_items: Array = []   # [Rect2, Node3D]


## Ağaçlar dışındaki ayrılmış alanlarla çakışıyor mu? (yol, bina, kamp, saha, eşyalar)
func _overlaps_hard(r: Rect2) -> bool:
	for o in _occupied:
		if not o.intersects(r):
			continue
		var is_tree := false
		for t in _tree_items:
			if t[0] == o:
				is_tree = true
				break
		if not is_tree:
			return true
	return false


## Alanın içindeki ağaçları kaldır.
func _clear_trees(r: Rect2) -> void:
	for t in _tree_items:
		if (t[0] as Rect2).intersects(r) and is_instance_valid(t[1]):
			var n := t[1] as Node
			n.get_parent().remove_child(n)
			n.free()   # navmesh pişirilmeden önce gitsin


var _buildings_info: Array = []


## Kasabadaki binalardan biri Mercer evi, biri Kuzey Lisesi (tahliye noktası) olur.
## Harita ve kayıtlardaki sıra değişmesin diye yeni bina eklenmez.
func _build_story_sites() -> void:
	var homes: Array = []
	var others: Array = []
	for b in _buildings_info:
		if not is_instance_valid(b.node):
			continue
		if b.kind == "house" or b.kind == "farmhouse":
			homes.append(b)
		else:
			others.append(b)
	if homes.is_empty():
		return
	# Ev: sığınaktan en uzaktaki evlerden biri (yol boyunca bir yolculuk olsun)
	homes.sort_custom(func(x, y): return (x.center as Vector3).distance_to(shelter_center) > (y.center as Vector3).distance_to(shelter_center))
	var home: Dictionary = homes[0]
	_make_mercer_house(home)
	# Okul: tercihen bir market/ahır, evden uzak olan
	var pool: Array = others if not others.is_empty() else homes.slice(1)
	if pool.is_empty():
		return
	# Hem sığınaktan hem evden uzak olan (en kısa mesafesi en büyük) bina
	var score := func(b: Dictionary) -> float:
		var c: Vector3 = b.center
		return minf(c.distance_to(shelter_center), c.distance_to(home.center))
	pool.sort_custom(func(x, y): return score.call(x) > score.call(y))
	_make_school(pool[0])


func _make_mercer_house(b: Dictionary) -> void:
	house_center = b.center
	story_house = b.search
	story_house.table = "mercer_house"
	story_house.label = "Evine gir"
	story_house.opened.connect(func(restored: bool): if not restored: story_event.emit("house"))
	var door := story_house.global_position
	var yaw: float = b.yaw
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var front := Vector3(sin(yaw), 0, cos(yaw))
	# Posta kutusu ve isim
	var mb := door + front * 2.2 + side * 2.2
	_add_box(mb + Vector3.UP * 0.55, Vector3(0.1, 1.1, 0.1), Color(0.3, 0.28, 0.25))
	_add_box(mb + Vector3.UP * 1.15, Vector3(0.3, 0.26, 0.3), Color(0.15, 0.25, 0.45))
	var name_l := Label3D.new()
	name_l.text = "MERCER"
	name_l.font_size = 64
	name_l.outline_size = 8
	name_l.pixel_size = 0.005
	name_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_l.position = mb + Vector3.UP * 1.7
	props.add_child(name_l)
	# Kapının önüne düşmüş bir çocuk çantası, ışığı açık kalmış bir lamba
	_add_box(door + front * 1.0 - side * 0.8 + Vector3.UP * 0.12, Vector3(0.35, 0.24, 0.2), Color(0.85, 0.6, 0.15))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 1.2
	lamp.omni_range = 4.0
	lamp.position = door + Vector3.UP * 2.2
	props.add_child(lamp)
	_story_pickups.append(["food", door + front * 2.0 - side * 2.5, 1])


func _make_school(b: Dictionary) -> void:
	school_center = b.center
	var srch: Searchable = b.search
	srch.label = "Okulu ara"
	var door := srch.global_position
	var yaw: float = b.yaw
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var front := Vector3(sin(yaw), 0, cos(yaw))
	var sign := Label3D.new()
	sign.text = "KUZEY LİSESİ\nTAHLİYE NOKTASI"
	sign.font_size = 80
	sign.outline_size = 12
	sign.pixel_size = 0.007
	sign.modulate = Color(1.0, 0.95, 0.85)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = door + Vector3.UP * 4.2
	props.add_child(sign)
	# Kum torbaları ve bariyerler (giriş açık)
	var sand := Color(0.5, 0.46, 0.34)
	var horiz := absf(front.x) < 0.5
	for k in [-1.0, 1.0]:
		_add_box(door + front * 1.8 + side * k * 2.6 + Vector3.UP * 0.4, Vector3(2.0, 0.8, 0.6) if horiz else Vector3(0.6, 0.8, 2.0), sand)
		CutsceneActor.spawn_prop(props, "res://assets/models/intro/barrier.glb", 1.4, door + front * 2.6 + side * k * 1.2, yaw + k * 0.35)
	# Kayıt masası ve tahtalı kâğıt
	var table := door + side * 2.4 + front * 0.2
	_add_box(table + Vector3.UP * 0.38, Vector3(1.4, 0.06, 0.6) if horiz else Vector3(0.6, 0.06, 1.4), Color(0.45, 0.42, 0.38))
	var paper := MeshInstance3D.new()
	paper.mesh = _box_mesh(Vector3(0.22, 0.01, 0.3))
	paper.material_override = _mat(Color(0.95, 0.94, 0.9))
	paper.position = table + Vector3.UP * 0.42
	paper.rotation.y = yaw + 0.3
	props.add_child(paper)
	story_school = Searchable.new()
	story_school.table = "evac_list"
	story_school.label = "Tahliye kaydını oku"
	story_school.reach = 1.8
	story_school.silent = true
	props.add_child(story_school)
	story_school.global_position = table + front * 0.9
	_searchables.append(story_school)
	story_school.opened.connect(func(restored: bool): if not restored: story_event.emit("school"))
	_story_pickups.append(["medkit", door + front * 3.5 + side * 3.5, 1])
	_story_pickups.append(["pistol_ammo", door + front * 3.5 - side * 3.5, 10])


func story_house_searched() -> bool:
	return is_instance_valid(story_house) and story_house.searched


func story_school_searched() -> bool:
	return is_instance_valid(story_school) and story_school.searched


## Okula ilk yaklaşmada bir sürü belirir (sadece bir kez; kayıtla ilgilenmez).
func _process_story() -> void:
	if _school_horde_done or school_center == Vector3.INF or story_school_searched() or not story_house_searched():
		return
	var p := Game.player
	if not is_instance_valid(p) or Game.cutscene_active:
		return
	if Vector2(p.global_position.x - school_center.x, p.global_position.z - school_center.z).length() > 30.0:
		return
	_school_horde_done = true
	var spawner := get_tree().current_scene.get_node_or_null("ZombieSpawner")
	if spawner == null:
		return
	var n := int(round(6 * Settings.diff("zombies")))
	for i in n:
		var ang := TAU * i / n
		var pos := school_center + Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(5.0, 9.0)
		var z = spawner.call("_spawn_at", pos)
		if z and z.has_method("alert_to"):
			z.alert_to(p.global_position)
	Audio.play_2d("horde", -6.0)
	if is_instance_valid(p):
		p.message.emit("Okulun çevresi zombi kaynıyor!")
