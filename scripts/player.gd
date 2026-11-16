class_name Player
extends CharacterBody3D
## Oyuncu: hareket, nişan, silahlar, yağma (arama), açlık/susuzluk/dayanıklılık, envanter.
## Model "+Z" yönüne bakar (glTF standardı). Tripo modeli ters bakıyorsa
## Inspector'da Model Yaw Offset = 180 yap.

signal message(text: String)
signal hurt(amount: float)
signal died

@export_group("Model (Tripo 3D)")
## Tripo'dan export ettiğin .glb dosyasını buraya sürükle. Boşsa kapsül yer tutucu kullanılır.
@export var model_scene: PackedScene
@export var model_scale := 1.0
@export var model_yaw_offset_deg := 0.0
@export var model_y_offset := 0.0

@export_group("Hareket")
@export var walk_speed := 4.0
@export var sprint_speed := 6.8
@export var aim_speed := 2.4
@export var acceleration := 30.0
@export var turn_speed := 14.0

@export_group("Hayatta Kalma")
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var hunger_per_minute := 10.0
@export var thirst_per_minute := 14.0
@export var starving_damage_per_sec := 1.5
@export var sprint_stamina_cost := 22.0
@export var stamina_regen := 16.0

@export_group("Envanter")
@export var max_weight := 25.0
@export var interact_range := 2.0

var health := 100.0
var stamina := 100.0
var hunger := 100.0
var thirst := 100.0
var inv := PlayerInventory.new()
var is_dead := false
var is_aiming := false
var is_sprinting := false
var flashlight_on := false
var aim_point := Vector3.ZERO

## Etkileşim: en yakın yerdeki eşya ya da aranabilir yer
var nearby_pickup: Pickup = null
var nearby_search: Searchable = null
var searching: Searchable = null
var search_progress := 0.0
var nearby_repair: Barricade = null
var repairing: Barricade = null
var repair_progress := 0.0
var build := BuildMode.new()
const REPAIR_TIME := 1.4
## Seçili fırlatılabilir (molotov / noisemaker)
var throw_id := "molotov"
const THROWABLES := ["molotov", "noisemaker"]
const THROW_RANGE := 12.0
var _throw_timer := 0.0

## Ara sahne oyuncuyu yönetirken true: girdi, hareket ve otomatik animasyon durur.
var scripted := false
var _attack_timer := 0.0
var _noise_timer := 0.0
var _search_noise := 0.0
var _exhausted := false
var _warned_hunger := false
var _warned_thirst := false
var _animator := ModelAnimator.new()
var _aim_marker: MeshInstance3D
var _hand: Node3D
var _held_id := ""
var _step_dist := 0.0

@onready var model_pivot: Node3D = $ModelPivot
@onready var placeholder: Node3D = $ModelPivot/Placeholder
@onready var flashlight: SpotLight3D = $ModelPivot/Flashlight
@onready var muzzle_light: OmniLight3D = $ModelPivot/MuzzleLight


func _ready() -> void:
	add_to_group("player")
	Game.player = self
	health = max_health
	stamina = max_stamina
	hunger_per_minute *= Settings.diff("hunger")
	thirst_per_minute *= Settings.diff("hunger")
	flashlight.position = Vector3(0, 1.4, 0.25)
	flashlight.rotation_degrees = Vector3(-12, 180, 0)
	flashlight.visible = false
	_setup_model()
	_create_aim_marker()

	# Başlangıç teçhizatı sığınaktaki çantada (Level kurar)
	inv.max_weight = max_weight
	inv.equip(-1)
	build.setup(self)
	add_child(build)
	inv.changed.connect(_update_held_weapon)
	_update_held_weapon()


func _setup_model() -> void:
	if model_scene == null:
		return
	placeholder.queue_free()
	placeholder = null
	var model := model_scene.instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale
	model.rotation_degrees.y = model_yaw_offset_deg
	model.position.y = model_y_offset
	model_pivot.add_child(model)
	_animator.setup(model)
	print("[Player] Animasyonlar: ", _animator.describe())
	# Silahı tutacak el kemiği
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var skel := skels[0] as Skeleton3D
		var bone_name := ""
		for candidate in ["mixamorig_RightHand", "mixamorig:RightHand", "RightHand"]:
			if skel.find_bone(candidate) >= 0:
				bone_name = candidate
				break
		if bone_name != "":
			var att := BoneAttachment3D.new()
			att.bone_name = bone_name
			skel.add_child(att)
			_hand = Node3D.new()
			_hand.name = "Hand"
			att.add_child(_hand)


# ------------------------------------------------------------------
# Her kare
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if is_dead or scripted:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	_attack_timer -= delta
	_throw_timer -= delta
	_update_aim_point()
	_update_survival(delta)
	var ui_open := Game.ui_open
	var busy := searching != null or repairing != null
	var stick_aim := Game.using_pad and Game.right_stick() != Vector2.ZERO
	is_aiming = (Input.is_action_pressed("aim") or stick_aim) and not ui_open and not busy and not build.active

	var input := Vector2.ZERO
	if not ui_open and not busy:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := _camera_relative(input)
	var moving := dir.length() > 0.1

	is_sprinting = moving and not is_aiming and Input.is_action_pressed("sprint") and not _exhausted
	var speed := walk_speed
	if is_aiming:
		speed = aim_speed
	elif is_sprinting:
		speed = sprint_speed
	if inv.total_weight() > inv.max_weight * 0.9:
		speed *= 0.8   # ağır yük

	if is_sprinting:
		stamina -= sprint_stamina_cost * delta
		if stamina <= 0.0:
			stamina = 0.0
			_exhausted = true
			message.emit("Nefesin kesildi!")
	else:
		var regen := stamina_regen * (0.5 if hunger < 25.0 or thirst < 25.0 else 1.0)
		stamina = minf(stamina + regen * delta, max_stamina)
	if _exhausted and stamina > 30.0:
		_exhausted = false

	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	move_and_slide()
	_update_footsteps(delta)
	_update_heartbeat()

	if searching:
		_face_towards(searching.global_position - global_position, delta)
	elif repairing:
		_face_towards(repairing.global_position - global_position, delta)
	elif is_aiming:
		_face_towards(aim_point - global_position, delta)
	elif moving:
		_face_towards(dir, delta)

	# Hareket gürültüsü: koşmak zombileri çeker, nişan alarak yürümek sessizdir.
	_noise_timer -= delta
	if moving and _noise_timer <= 0.0:
		_noise_timer = 0.5
		var r := 3.5
		if is_sprinting:
			r = 9.0
		elif is_aiming:
			r = 2.0
		Game.make_noise(global_position, r)

	if Input.is_action_just_pressed("attack") and not ui_open and not busy:
		if build.active:
			build.try_place()
		else:
			_attack()
	if Input.is_action_just_pressed("aim") and build.active and not ui_open:
		build.set_active(false)

	_update_nearby()
	_update_search(delta)
	_update_repair(delta)
	_update_animation()
	_aim_marker.visible = is_aiming
	if is_aiming:
		_aim_marker.global_position = aim_point + Vector3.UP * 0.03
	muzzle_light.light_energy = maxf(muzzle_light.light_energy - 60.0 * delta, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if is_dead or Game.ui_open:
		return
	if event.is_action_pressed("interact"):
		if is_instance_valid(nearby_pickup):
			nearby_pickup.collect(self)
			nearby_pickup = null
		elif is_instance_valid(nearby_search) and searching == null:
			searching = nearby_search
			search_progress = 0.0
			_search_noise = 0.0
		elif is_instance_valid(nearby_repair) and repairing == null:
			if inv.count("wood") <= 0:
				message.emit("Onarmak için tahta lazım.")
			else:
				repairing = nearby_repair
				repair_progress = 0.0
	elif event.is_action_pressed("build"):
		build.toggle()
		Audio.play_2d("flashlight", -10.0)
		if build.active:
			message.emit("İnşa modu: 1/2/3 seç, sol tık kur, R döndür, B çık")
	elif build.active and event.is_action_pressed("rotate_build"):
		build.rotate_ghost()
	elif build.active and event.is_action_pressed("use_food"):
		build.select(0)
	elif build.active and event.is_action_pressed("use_water"):
		build.select(1)
	elif build.active and event.is_action_pressed("use_medkit"):
		build.select(2)
	elif event.is_action_pressed("switch_weapon"):
		inv.cycle()
		Audio.play_2d("flashlight", -10.0)
		message.emit(Items.item_name(inv.current_id()))
	elif event.is_action_pressed("flashlight"):
		flashlight_on = not flashlight_on
		flashlight.visible = flashlight_on
		Audio.play_2d("flashlight", -8.0)
	elif event.is_action_pressed("use_food"):
		use_item("food")
	elif event.is_action_pressed("use_water"):
		use_item("water")
	elif event.is_action_pressed("use_medkit"):
		use_item("medkit")
	elif event.is_action_pressed("use_bandage"):
		use_item("bandage")
	elif event.is_action_pressed("switch_throwable"):
		cycle_throwable()
	elif event.is_action_pressed("throw") and searching == null and repairing == null and not build.active:
		throw_selected()


# ------------------------------------------------------------------
# Hareket / nişan
# ------------------------------------------------------------------

func _camera_relative(input: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(input.x, 0.0, input.y)
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var d := right * input.x - fwd * input.y
	return d.limit_length(1.0)


func _update_aim_point() -> void:
	# Oyun kolu: sağ çubuk yönünde 7 m ileri; çubuk boştaysa bakılan yön
	if Game.using_pad:
		var rs := Game.right_stick()
		if rs != Vector2.ZERO:
			aim_point = global_position + _camera_relative(rs.normalized()) * 7.0
		else:
			aim_point = global_position + get_facing() * 2.5
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var normal := cam.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, global_position.y)
	var hit = plane.intersects_ray(from, normal)
	if hit != null:
		aim_point = hit


func _face_towards(v: Vector3, delta: float, instant := false) -> void:
	v.y = 0.0
	if v.length_squared() < 0.0001:
		return
	var target_yaw := atan2(v.x, v.z)
	if instant:
		model_pivot.rotation.y = target_yaw
	else:
		model_pivot.rotation.y = lerp_angle(model_pivot.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))


func get_facing() -> Vector3:
	var f := model_pivot.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


# ------------------------------------------------------------------
# Dövüş
# ------------------------------------------------------------------

## Sol tık: kuşanılı silaha göre vur ya da ateş et.
## Ateşli silahla nişan almadan sol tık = dipçikle vurma (yumruk gibi).
func _attack() -> void:
	var info := inv.current_info()
	if info.type == "gun":
		if is_aiming:
			_try_shoot(info)
		else:
			_try_melee(Items.info("fists"), false)
	else:
		_try_melee(info, true)


func _try_melee(w: Dictionary, wears: bool) -> void:
	if _attack_timer > 0.0 or stamina < float(w.stamina) * 0.5:
		return
	_attack_timer = float(w.cooldown)
	stamina = maxf(stamina - float(w.stamina), 0.0)
	_face_towards(aim_point - global_position, 0.0, true)
	if not _animator.play_once("attack"):
		_placeholder_lunge()
	Audio.play_3d("swing", global_position + Vector3.UP, -6.0, 4.0)

	# Menzil + yay içindeki en yakın hedeflere vur
	var fwd := get_facing()
	var targets: Array = []
	for node in get_tree().get_nodes_in_group("zombies"):
		var z := node as Zombie
		if z == null or z.is_dead:
			continue
		var to := z.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist <= float(w.range) and (dist < 0.6 or fwd.dot(to / dist) > float(w.arc)):
			targets.append([dist, z, to / dist if dist > 0.01 else fwd])
	targets.sort_custom(func(a, b): return a[0] < b[0])
	var hits := mini(targets.size(), int(w.targets))
	for i in hits:
		var z: Zombie = targets[i][1]
		z.take_damage(float(w.damage), targets[i][2], float(w.knockback))
	Game.make_noise(global_position, float(w.noise) + (1.5 if hits > 0 else 0.0))

	if hits > 0 and wears:
		var broken := inv.wear_current(1)
		if broken != "":
			message.emit("%s kırıldı!" % broken)
			Audio.play_2d("hit", -2.0)


func _try_shoot(w: Dictionary) -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = float(w.cooldown)
	var ammo_id: String = w.ammo
	if not inv.remove(ammo_id, 1):
		message.emit("*klik* — %s yok!" % Items.item_name(ammo_id))
		Audio.play_2d("empty_click", -4.0)
		return
	Audio.play_3d("gunshot", global_position + Vector3.UP * 1.3, 2.0 if int(w.pellets) == 1 else 5.0, 30.0, 0.06)
	_face_towards(aim_point - global_position, 0.0, true)
	_animator.play_once("shoot")

	var base := aim_point - global_position
	base.y = 0.0
	if base.length() < 0.01:
		base = get_facing()
	base = base.normalized()
	var origin := global_position + Vector3.UP * 1.3 + base * 0.4
	var space := get_world_3d().direct_space_state
	for i in int(w.pellets):
		var dir := base.rotated(Vector3.UP, randf_range(-1.0, 1.0) * float(w.spread))
		var end := origin + dir * float(w.range)
		var query := PhysicsRayQueryParameters3D.create(origin, end, 1 | 4)  # dünya + zombiler
		query.exclude = [get_rid()]
		var result := space.intersect_ray(query)
		if not result.is_empty():
			end = result.position
			var z := result.collider as Zombie
			if z:
				z.take_damage(float(w.damage), dir, 2.0 if int(w.pellets) > 1 else 3.5)
		_spawn_tracer(origin, end)
	muzzle_light.light_energy = 6.0
	Game.make_noise(global_position, float(w.noise))


func _spawn_tracer(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.04, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = (a + b) * 0.5
	mi.look_at(b, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(mi.queue_free)


func take_damage(amount: float) -> void:
	_apply_damage(amount, true)


func _apply_damage(amount: float, show_hurt: bool) -> void:
	if is_dead:
		return
	health -= amount
	if show_hurt:
		hurt.emit(amount)
		Audio.play_2d("player_hurt", -3.0, 0.08)
		if searching:
			_cancel_search("Arama yarıda kaldı!")
		repairing = null
		if not _animator.play_once("hurt") and placeholder:
			var tw := create_tween()
			tw.tween_property(placeholder, "rotation:x", -0.25, 0.06)
			tw.tween_property(placeholder, "rotation:x", 0.0, 0.12)
	if health <= 0.0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	searching = null
	repairing = null
	build.set_active(false)
	Game.delete_save()   # kalıcı ölüm
	_aim_marker.visible = false
	collision_layer = 0
	Audio.set_ambience("heartbeat", -60.0)
	Audio.play_music("death", 0.3, -2.0)
	if not _animator.play_once("death") and placeholder:
		var tw := create_tween()
		tw.tween_property(placeholder, "rotation:x", -PI / 2.0, 0.5)
	died.emit()


func _placeholder_lunge() -> void:
	if placeholder == null:
		return
	var tw := create_tween()
	tw.tween_property(placeholder, "position:z", 0.35, 0.07)
	tw.tween_property(placeholder, "position:z", 0.0, 0.15)


# ------------------------------------------------------------------
# Elde tutulan silah modeli
# ------------------------------------------------------------------

## Elde tutma ayarları (Tripo modelleri XY düzleminde yatık gelir):
##  size: silahın gerçek uzunluğu (m), nlen: modeldeki uzunluğu (birim)
##  axis: modelde kabzadan uca doğru yön, grip: modelde elin kavradığı nokta
const HELD := {
	"knife": {"size": 0.3, "nlen": 1.3, "axis": Vector3(-0.72, -0.7, 0), "grip": Vector3(0.3, 0.78, 0)},
	"bat": {"size": 0.85, "nlen": 1.12, "axis": Vector3(0.83, -0.56, 0), "grip": Vector3(-0.36, 0.6, 0)},
	"axe": {"size": 0.8, "nlen": 1.0, "axis": Vector3(0, 1, 0), "grip": Vector3(0, 0.12, 0)},
	"pistol": {"size": 0.22, "nlen": 1.0, "axis": Vector3(-1, 0, 0), "grip": Vector3(0.22, 0.25, 0)},
	"shotgun": {"size": 1.0, "nlen": 1.0, "axis": Vector3(-1, 0, 0), "grip": Vector3(0.12, 0.12, 0)},
}
## El kemiği uzayında: parmaklar +Y, başparmak -Z, avuç normali X.
const HAND_GRIP_OFFSET := Vector3(0.0, 0.085, 0.0)   # bilekten avuç ortasına (m)


func _update_held_weapon() -> void:
	var id := inv.current_id()
	if id == _held_id or _hand == null:
		return
	_held_id = id
	for c in _hand.get_children():
		c.queue_free()
	var mid: String = Items.info(id).get("model", id)
	if not HELD.has(mid) or not PropLibrary.has(mid):
		return
	var h: Dictionary = HELD[mid]
	var parent_scale := model_scale if model_scale > 0.0 else 1.0
	var k := float(h.size) / float(h.nlen) / parent_scale

	# Model çerçevesi: uzun eksen, yan (düzlem normali Z), yukarı
	var axis: Vector3 = (h.axis as Vector3).normalized()
	var side := Vector3.BACK
	var up := side.cross(axis).normalized()
	side = axis.cross(up).normalized()
	var m := Basis(axis, up, side)
	# Hedef çerçeve (el kemiği): yakın dövüş silahı biraz aşağı eğik ileri, ateşli silah düz ileri
	var gun: bool = Items.info(id).get("type", "") == "gun"
	var tdir := Vector3(0, 0, -1) if gun else Vector3(0, 0.5, -1).normalized()
	var tside := Vector3(1, 0, 0)
	var tup := tside.cross(tdir).normalized()
	tside = tdir.cross(tup).normalized()
	var t := Basis(tdir, tup, tside)

	var model := PropLibrary.instance(mid, k)
	model.position = -(h.grip as Vector3) * k
	var pivot := Node3D.new()
	pivot.basis = t * m.inverse()
	pivot.position = HAND_GRIP_OFFSET / parent_scale
	pivot.add_child(model)
	_hand.add_child(pivot)


# ------------------------------------------------------------------
# Fırlatma (G at, Z değiştir)
# ------------------------------------------------------------------

## Seçili fırlatılabilir yoksa elde olan diğerine geçer. Hiçbiri yoksa "" döner.
func current_throwable() -> String:
	if inv.count(throw_id) > 0:
		return throw_id
	for t in THROWABLES:
		if inv.count(t) > 0:
			return t
	return ""


func cycle_throwable() -> void:
	var start := THROWABLES.find(throw_id)
	for i in range(1, THROWABLES.size() + 1):
		var t: String = THROWABLES[(start + i) % THROWABLES.size()]
		if inv.count(t) > 0:
			throw_id = t
			Audio.play_2d("flashlight", -10.0)
			message.emit("Fırlatılacak: %s (%d)" % [Items.item_name(t), inv.count(t)])
			inv.changed.emit()
			return
	message.emit("Fırlatacak bir şeyin yok. (C: üretim)")


func throw_selected() -> void:
	var id := current_throwable()
	if id == "":
		message.emit("Fırlatacak bir şeyin yok. (C: üretim)")
		return
	if _throw_timer > 0.0 or stamina < 6.0:
		return
	throw_id = id
	_throw_timer = 0.9
	stamina = maxf(stamina - 6.0, 0.0)
	var to := aim_point
	var flat := Vector3(to.x - global_position.x, 0.0, to.z - global_position.z)
	if flat.length() > THROW_RANGE:
		flat = flat.normalized() * THROW_RANGE
	if flat.length() < 1.0:
		flat = get_facing() * 3.0
	to = Vector3(global_position.x + flat.x, global_position.y, global_position.z + flat.z)
	_face_towards(flat, 0.0, true)
	if not _animator.play_once("attack"):
		_placeholder_lunge()
	Audio.play_3d("swing", global_position + Vector3.UP, -4.0, 4.0)
	inv.remove(id, 1)
	var from := global_position + Vector3.UP * 1.5 + flat.normalized() * 0.4
	Throwable.launch(get_tree().current_scene, id, from, to, self)
	Game.make_noise(global_position, 3.0)


# ------------------------------------------------------------------
# Etkileşim ve yağma
# ------------------------------------------------------------------

func _update_nearby() -> void:
	nearby_pickup = null
	nearby_search = null
	var best := interact_range
	for node in get_tree().get_nodes_in_group("pickups"):
		var pk := node as Pickup
		if pk == null:
			continue
		var d := _flat_dist(pk.global_position)
		if d < best:
			best = d
			nearby_pickup = pk
	if nearby_pickup:
		return
	nearby_repair = null
	var best_r := 99.0
	for node in get_tree().get_nodes_in_group("barricades"):
		var b := node as Barricade
		if b == null or b.hp >= b.max_hp:
			continue
		var d := _flat_dist(b.global_position)
		if d < Barricade.LENGTH * 0.5 + 1.0 and d < best_r:
			best_r = d
			nearby_repair = b
	var best_s := 99.0
	for node in get_tree().get_nodes_in_group("searchables"):
		var s := node as Searchable
		if s == null:
			continue
		var d := _flat_dist(s.global_position)
		if d <= s.reach and d < best_s:
			best_s = d
			nearby_search = s


func _update_search(delta: float) -> void:
	if searching == null:
		return
	if not is_instance_valid(searching) or searching.searched:
		searching = null
		return
	if not Input.is_action_pressed("interact"):
		_cancel_search("")
		return
	if _flat_dist(searching.global_position) > searching.reach + 0.6:
		_cancel_search("")
		return
	search_progress += delta / maxf(searching.search_time, 0.1)
	_search_noise -= delta
	if _search_noise <= 0.0:
		_search_noise = 0.7
		Game.make_noise(global_position, searching.noise_radius)
		Audio.play_3d("bandage", global_position + Vector3.UP, -12.0, 4.0, 0.2)
	if search_progress >= 1.0:
		var target := searching
		searching = null
		search_progress = 0.0
		var loot := target.open()
		if not target.silent:
			_receive_loot(loot, target.global_position)


## Barikat onarma: E basılı, her tamamlanışta 1 tahta harcar ve %40 onarır.
func _update_repair(delta: float) -> void:
	if repairing == null:
		return
	if not is_instance_valid(repairing) or repairing.hp <= 0.0 or not Input.is_action_pressed("interact") \
			or _flat_dist(repairing.global_position) > Barricade.LENGTH * 0.5 + 1.6:
		repairing = null
		repair_progress = 0.0
		return
	repair_progress += delta / REPAIR_TIME
	if repair_progress >= 1.0:
		repair_progress = 0.0
		if not inv.remove("wood", 1):
			message.emit("Tahta bitti.")
			repairing = null
			return
		repairing.repair(repairing.max_hp * 0.4)
		Audio.play_3d("hit", repairing.global_position + Vector3.UP * 0.6, -6.0, 5.0, 0.2)
		Game.make_noise(global_position, 5.0)
		if repairing.hp >= repairing.max_hp:
			message.emit("%s tamamen onarıldı." % repairing.display_name)
			repairing = null


func _cancel_search(reason: String) -> void:
	searching = null
	search_progress = 0.0
	if reason != "":
		message.emit(reason)


func _receive_loot(loot: Array, where: Vector3) -> void:
	if loot.is_empty():
		message.emit("Hiçbir şey bulamadın.")
		return
	var parts: Array[String] = []
	var dropped := false
	for entry in loot:
		var id: String = entry[0]
		var n: int = entry[1]
		var got := inv.add(id, n)
		if got > 0:
			parts.append("%s x%d" % [Items.item_name(id), got] if got > 1 else Items.item_name(id))
		if got < n and is_instance_valid(Game.level):
			dropped = true
			Game.level.spawn_pickup(id, global_position + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)), false, n - got)
	Audio.play_2d("pickup", -6.0)
	var text := "Buldun: " + ", ".join(parts) if not parts.is_empty() else ""
	if dropped:
		text += ("  —  " if text != "" else "") + "Çok ağır! Bir kısmını yere bıraktın."
	message.emit(text)


## Yerden alma (Pickup çağırır). Alınan adedi döndürür.
func add_item(type: String, amount: int, durability := -1) -> int:
	var got := inv.add(type, amount, durability)
	if got <= 0:
		message.emit("Çok ağır, taşıyamazsın! (Tab: envanter)")
		return 0
	Audio.play_2d("ammo_pickup" if Items.info(type).get("type", "") == "ammo" else "pickup", -6.0)
	message.emit("+%d %s" % [got, Items.item_name(type)] if got > 1 else "+ " + Items.item_name(type))
	return got


func use_item(type: String) -> void:
	if inv.count(type) <= 0:
		message.emit("%s yok." % Items.item_name(type))
		return
	match type:
		"food":
			if hunger >= 95.0:
				message.emit("Aç değilsin.")
				return
			hunger = minf(hunger + 45.0, 100.0)
		"water":
			if thirst >= 95.0:
				message.emit("Susamadın.")
				return
			thirst = minf(thirst + 50.0, 100.0)
		"medkit":
			if health >= max_health:
				message.emit("Yaran yok.")
				return
			health = minf(health + 50.0, max_health)
		"bandage":
			if health >= max_health:
				message.emit("Yaran yok.")
				return
			health = minf(health + 20.0, max_health)
		_:
			return
	inv.remove(type, 1)
	var use_sounds := {"food": "eat", "water": "drink", "medkit": "bandage", "bandage": "bandage"}
	Audio.play_2d(use_sounds[type], -4.0)
	message.emit("%s kullanıldı." % Items.item_name(type))


## Envanterden yere bırak (envanter ekranı çağırır).
func drop_item(id: String, amount: int) -> void:
	if not inv.remove(id, amount):
		return
	if is_instance_valid(Game.level):
		Game.level.spawn_pickup(id, global_position + get_facing() * 0.8, false, amount)


func drop_weapon(index: int) -> void:
	var wp := inv.take_weapon(index)
	if wp.is_empty():
		return
	if is_instance_valid(Game.level):
		Game.level.spawn_pickup(wp.id, global_position + get_facing() * 0.8, false, 1, int(wp.durability))


# ------------------------------------------------------------------
# Hayatta kalma
# ------------------------------------------------------------------

func _update_survival(delta: float) -> void:
	var mult := 1.6 if is_sprinting else 1.0
	hunger = maxf(hunger - hunger_per_minute / 60.0 * delta * mult, 0.0)
	thirst = maxf(thirst - thirst_per_minute / 60.0 * delta * mult, 0.0)
	if hunger <= 0.0 or thirst <= 0.0:
		_apply_damage(starving_damage_per_sec * delta, false)
	elif hunger > 50.0 and thirst > 50.0 and health < max_health:
		health = minf(health + 0.4 * delta, max_health)

	if hunger < 20.0 and not _warned_hunger:
		_warned_hunger = true
		message.emit("Çok açsın... [1] ile konserve ye.")
	elif hunger > 30.0:
		_warned_hunger = false
	if thirst < 20.0 and not _warned_thirst:
		_warned_thirst = true
		message.emit("Susuzluktan ağzın kurudu... [2] ile su iç.")
	elif thirst > 30.0:
		_warned_thirst = false


## Adım sesleri: kat edilen mesafeye göre (koşarken daha sık ve yüksek).
func _update_footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv < 0.5:
		_step_dist = 0.0
		return
	_step_dist += hv * delta
	var stride := 1.0 if is_sprinting else 0.75
	if _step_dist >= stride:
		_step_dist = 0.0
		var vol := -8.0 if is_sprinting else (-20.0 if is_aiming else -13.0)
		Audio.play_3d("footstep", global_position, vol, 4.0, 0.12)


## Can azaldıkça kalp atışı duyulur.
func _update_heartbeat() -> void:
	if health < 35.0:
		Audio.set_ambience("heartbeat", lerpf(-4.0, -20.0, health / 35.0))
	else:
		Audio.set_ambience("heartbeat", -60.0)


# ------------------------------------------------------------------
# Görsel
# ------------------------------------------------------------------

func _update_animation() -> void:
	if _animator.is_busy():
		return
	# Tripo'nun walk animasyonu ~1.5 m/s, run animasyonu ~4.5 m/s için yapılmış.
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv < 0.3:
		_animator.play("idle")
		_animator.set_speed(1.0)
	elif hv < 3.0:
		_animator.play("walk")
		_animator.set_speed(clampf(hv / 1.5, 0.6, 1.7))
	else:
		_animator.play("run")
		_animator.set_speed(clampf(hv / 4.5, 0.7, 1.6))


func _create_aim_marker() -> void:
	_aim_marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.18
	tm.outer_radius = 0.26
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.2, 0.15)
	tm.material = mat
	_aim_marker.mesh = tm
	_aim_marker.top_level = true
	_aim_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_marker.visible = false
	add_child(_aim_marker)
