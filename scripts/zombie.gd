class_name Zombie
extends CharacterBody3D
## Zombi yapay zekası:
##  WANDER      -> evinin (spawn noktası) çevresinde yavaşça dolaşır
##  INVESTIGATE -> bir ses duydu, oraya gidiyor
##  CHASE       -> oyuncuyu gördü, peşinde
## Görüş: mesafe + bakış açısı + duvar kontrolü. Gece görüş kısalır, fener açıksa uzar.

enum State { WANDER, INVESTIGATE, CHASE, DEAD }

@export_group("Model (Tripo 3D)")
## Birden fazla Tripo zombi modeli ekleyebilirsin, her zombi rastgele birini seçer.
@export var model_variants: Array[PackedScene] = []
@export var model_scale := 1.0
@export var model_yaw_offset_deg := 0.0
@export var model_y_offset := 0.0

@export_group("İstatistik")
@export var max_health := 65.0
@export var wander_speed := 0.9
@export var chase_speed := 2.7
@export var attack_range := 1.35
@export var attack_damage := 12.0
@export var attack_cooldown := 1.4
@export var attack_windup := 0.45
@export_range(0.0, 1.0) var loot_drop_chance := 0.45

@export_group("Duyular")
@export var sight_range := 12.0
@export var sight_fov_deg := 140.0
@export var close_sense_range := 2.5
@export var lose_interest_time := 5.0
@export var wander_radius := 9.0

var state: State = State.WANDER
var health := 65.0
var is_dead := false

var _target_pos := Vector3.ZERO
var _last_nav_target := Vector3(99999, 0, 99999)
var _home := Vector3.ZERO
var _wander_wait := 0.0
var _wander_elapsed := 0.0
var _attack_timer := 0.0
var _windup := -1.0
var _lost_timer := 0.0
var _sense_timer := 0.0
var _can_see_player := false
var _move_vel := Vector3.ZERO
var _knockback := Vector3.ZERO
var _speed_mult := 1.0
var _animator := ModelAnimator.new()
var _blocker: Barricade = null
var _windup_target: Barricade = null
var slow_until := 0          # kazık tuzağı yavaşlatması (ms)
@export var barricade_damage := 15.0

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var model_pivot: Node3D = $ModelPivot
@onready var placeholder: Node3D = $ModelPivot/Placeholder


func _ready() -> void:
	add_to_group("zombies")
	health = max_health
	attack_damage *= Settings.diff("damage")
	loot_drop_chance *= Settings.diff("loot")
	_home = global_position
	_speed_mult = randf_range(0.8, 1.25)
	_sense_timer = randf() * 0.2
	model_pivot.rotation.y = randf() * TAU
	Game.noise_emitted.connect(_on_noise)
	_setup_model()
	_tint_placeholder()
	_pick_wander_target()


func _setup_model() -> void:
	if model_variants.is_empty():
		return
	var scene: PackedScene = model_variants.pick_random()
	if scene == null:
		return
	placeholder.queue_free()
	placeholder = null
	var model := scene.instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale * randf_range(0.93, 1.07)
	model.rotation_degrees.y = model_yaw_offset_deg
	model.position.y = model_y_offset
	model_pivot.add_child(model)
	_animator.setup(model)
	_animator.base_speed = randf_range(0.85, 1.15)


func _tint_placeholder() -> void:
	if placeholder == null:
		return
	var skin := Color(0.45, 0.52, 0.4).lerp(Color(0.55, 0.5, 0.45), randf())
	var clothes_options := [Color(0.3, 0.28, 0.25), Color(0.25, 0.3, 0.35), Color(0.4, 0.33, 0.25), Color(0.35, 0.2, 0.2), Color(0.28, 0.32, 0.26)]
	var clothes: Color = clothes_options.pick_random()
	for node in placeholder.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.95
		mat.albedo_color = skin if String(mi.name).begins_with("Skin") else clothes
		mi.material_override = mat
	placeholder.scale = Vector3.ONE * randf_range(0.92, 1.08)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	_knockback = _knockback.move_toward(Vector3.ZERO, 12.0 * delta)
	if is_dead:
		velocity.x = _knockback.x
		velocity.z = _knockback.z
		move_and_slide()
		return

	_attack_timer -= delta
	_update_burning(delta)
	if is_dead:
		return
	_sense_timer -= delta

	var player: Player = null
	if is_instance_valid(Game.player):
		player = Game.player
	var player_ok := player != null and not player.is_dead
	_update_groan(delta, player)
	if _sense_timer <= 0.0:
		_sense_timer = 0.2
		_can_see_player = player_ok and _can_see(player)
	if not player_ok:
		_can_see_player = false

	var desired := Vector3.ZERO
	var speed := 0.0
	var face_dir := Vector3.ZERO

	match state:
		State.WANDER:
			if _can_see_player:
				_start_chase(player)
			elif _wander_wait > 0.0:
				_wander_wait -= delta
			else:
				_wander_elapsed += delta
				if _flat_dist(_target_pos) < 1.0 or _wander_elapsed > 12.0:
					_wander_wait = randf_range(2.0, 6.0)
					_pick_wander_target()
				else:
					desired = _nav_dir(_target_pos)
					speed = wander_speed

		State.INVESTIGATE:
			if _can_see_player:
				_start_chase(player)
			elif _flat_dist(_target_pos) < 1.5:
				state = State.WANDER
				_home = global_position
				_wander_wait = randf_range(1.0, 3.0)
				_pick_wander_target()
			else:
				desired = _nav_dir(_target_pos)
				speed = chase_speed * 0.7

		State.CHASE:
			if not player_ok:
				state = State.WANDER
				_home = global_position
				_pick_wander_target()
			else:
				if _can_see_player:
					_lost_timer = 0.0
					_target_pos = player.global_position
				else:
					_lost_timer += delta
					if _lost_timer > lose_interest_time:
						state = State.INVESTIGATE
				var dist := _flat_dist(player.global_position)
				if dist <= attack_range:
					face_dir = player.global_position - global_position
					if _attack_timer <= 0.0 and _windup < 0.0:
						_windup = attack_windup
						_animator.play_once("attack")
						Audio.play_3d("zombie_attack", global_position + Vector3.UP * 1.6, 0.0, 6.0, 0.12)
				elif _windup < 0.0:
					desired = _nav_dir(_target_pos)
					speed = chase_speed

	# Yolunu bir barikat kesiyorsa (ve oyuncu vurulacak mesafede değilse) barikatı döv.
	var hitting_barricade := false
	if is_instance_valid(_blocker) and state != State.WANDER:
		var player_close := player_ok and _flat_dist(player.global_position) <= attack_range
		if not player_close and _blocker.hp > 0.0 and _flat_dist(_blocker.global_position) < Barricade.LENGTH * 0.5 + 1.4:
			hitting_barricade = true
			desired = Vector3.ZERO
			face_dir = _blocker.global_position - global_position
			if _attack_timer <= 0.0 and _windup < 0.0:
				_windup = attack_windup
				_windup_target = _blocker
				_animator.play_once("attack")
		else:
			_blocker = null

	# Saldırı hazırlığı: hasar animasyonun ortasında verilir, geri çekilerek kaçılabilir.
	if _windup >= 0.0:
		_windup -= delta
		desired = Vector3.ZERO
		if _windup < 0.0:
			_attack_timer = attack_cooldown
			if is_instance_valid(_windup_target):
				_windup_target.take_damage(barricade_damage * Settings.diff("damage"))
			elif player_ok and _flat_dist(player.global_position) <= attack_range + 0.5:
				player.take_damage(attack_damage)
			_windup_target = null

	if Time.get_ticks_msec() < slow_until:
		speed *= 0.4
	var target_vel := desired * speed * _speed_mult
	_move_vel = _move_vel.lerp(target_vel, 1.0 - exp(-8.0 * delta))
	velocity.x = _move_vel.x + _knockback.x
	velocity.z = _move_vel.z + _knockback.z
	move_and_slide()

	# Önüne barikat çıktı mı?
	if not hitting_barricade and state != State.WANDER:
		for i in get_slide_collision_count():
			var b := get_slide_collision(i).get_collider() as Barricade
			if b:
				_blocker = b
				break

	if face_dir == Vector3.ZERO:
		face_dir = desired
	_face_towards(face_dir, delta)
	_update_animation(target_vel.length())


var _groan_timer := randf_range(2.0, 10.0)

## Ara sıra inler; kovalarken daha sık ve yüksek. Uzaktakiler ses harcamaz.
func _update_groan(delta: float, player: Player) -> void:
	_groan_timer -= delta
	if _groan_timer > 0.0:
		return
	var chasing := state == State.CHASE
	_groan_timer = randf_range(2.5, 5.0) if chasing else randf_range(6.0, 14.0)
	if player and _flat_dist(player.global_position) < 32.0:
		Audio.play_3d("groan", global_position + Vector3.UP * 1.6, -2.0 if chasing else -7.0, 6.0, 0.15)


func _start_chase(player: Player) -> void:
	if state != State.CHASE:
		# Fark etti: hemen bir hırıltı
		_groan_timer = 0.0
	state = State.CHASE
	_lost_timer = 0.0
	_target_pos = player.global_position


## Dışarıdan (örn. sürü olayı) zombiyi bir noktaya yönlendirmek için.
func alert_to(pos: Vector3) -> void:
	if is_dead or state == State.CHASE:
		return
	state = State.INVESTIGATE
	_target_pos = pos


func _on_noise(pos: Vector3, radius: float) -> void:
	if is_dead or state == State.CHASE:
		return
	if _flat_dist(pos) <= radius:
		alert_to(pos + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5)))


func _can_see(player: Player) -> bool:
	var to := player.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d <= close_sense_range:
		return true
	var view := sight_range
	if Game.is_night():
		view *= 1.3 if player.flashlight_on else 0.55
	if d > view:
		return false
	var fwd := model_pivot.global_transform.basis.z
	fwd.y = 0.0
	if fwd.normalized().dot(to / d) < cos(deg_to_rad(sight_fov_deg * 0.5)):
		return false
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, player.global_position + Vector3.UP * 1.2, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _nav_dir(target: Vector3) -> Vector3:
	if target.distance_squared_to(_last_nav_target) > 0.25:
		agent.target_position = target
		_last_nav_target = target
	var d := Vector3.ZERO
	if not agent.is_navigation_finished():
		d = agent.get_next_path_position() - global_position
		d.y = 0.0
	if d.length() < 0.05:
		# Navigasyon hazır değilse ya da hedefe çok yakınsa doğrudan yürü.
		d = target - global_position
		d.y = 0.0
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


func _pick_wander_target() -> void:
	var off := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * randf_range(2.0, wander_radius)
	var p := _home + off
	if Game.nav_ready:
		p = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)
	_target_pos = p
	_wander_elapsed = 0.0


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _face_towards(v: Vector3, delta: float) -> void:
	v.y = 0.0
	if v.length_squared() < 0.0001:
		return
	model_pivot.rotation.y = lerp_angle(model_pivot.rotation.y, atan2(v.x, v.z), 1.0 - exp(-6.0 * delta))


func _update_animation(speed: float) -> void:
	if _animator.is_busy():
		return
	if speed < 0.2:
		_animator.play("idle")
		_animator.set_speed(1.0)
	elif speed < 2.0:
		_animator.play("walk")
		_animator.set_speed(clampf(speed / 1.4, 0.5, 1.6))
	else:
		_animator.play("run")
		_animator.set_speed(clampf(speed / 4.5, 0.6, 1.4))


func take_damage(amount: float, dir := Vector3.ZERO, knockback := 3.5) -> void:
	if is_dead:
		return
	health -= amount
	_knockback = dir * knockback
	_windup = -1.0
	_windup_target = null
	_attack_timer = maxf(_attack_timer, 0.4)
	Game.spawn_blood(global_position + Vector3.UP * 1.2)
	Audio.play_3d("hit", global_position + Vector3.UP * 1.2, -1.0, 6.0, 0.1)
	if health <= 0.0:
		_die()
		return
	if not _animator.play_once("hurt") and placeholder:
		var tw := create_tween()
		tw.tween_property(placeholder, "rotation:x", -0.3, 0.06)
		tw.tween_property(placeholder, "rotation:x", 0.0, 0.15)
	if state != State.CHASE and is_instance_valid(Game.player):
		_start_chase(Game.player)


## Ateş hasarı (molotof): geri itme, kan ve kovalamaya başlatma yok.
## Ateşe değen zombi 4 sn daha yanmaya devam eder (saniyede 14 hasar).
const AFTERBURN := 4.0
const AFTERBURN_DPS := 14.0
var _burning := 0.0
var _flames: CPUParticles3D

func burn(amount: float) -> void:
	if is_dead:
		return
	health -= amount
	_burning = AFTERBURN
	_set_flames(true)
	if health <= 0.0:
		_die()


func _update_burning(delta: float) -> void:
	if _burning <= 0.0:
		return
	_burning -= delta
	health -= AFTERBURN_DPS * delta
	if health <= 0.0:
		_die()
	if _burning <= 0.0 or is_dead:
		_burning = 0.0
		_set_flames(false)


func _set_flames(on: bool) -> void:
	if on and _flames == null:
		_flames = CPUParticles3D.new()
		_flames.amount = 24
		_flames.lifetime = 0.5
		_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_flames.emission_box_extents = Vector3(0.25, 0.7, 0.25)
		_flames.position.y = 0.9
		_flames.direction = Vector3.UP
		_flames.spread = 10.0
		_flames.gravity = Vector3(0, 2.5, 0)
		_flames.initial_velocity_min = 0.3
		_flames.initial_velocity_max = 0.9
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.8, 0.3, 0.95))
		grad.set_color(1, Color(0.15, 0.1, 0.1, 0.0))
		grad.add_point(0.4, Color(1.0, 0.38, 0.05, 0.85))
		_flames.color_ramp = grad
		var quad := QuadMesh.new()
		quad.size = Vector2(0.22, 0.42)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = Throwable.flame_tex()
		quad.material = mat
		_flames.mesh = quad
		add_child(_flames)
	if _flames:
		_flames.emitting = on


func _die() -> void:
	is_dead = true
	_burning = 0.0
	_set_flames(false)
	state = State.DEAD
	remove_from_group("zombies")
	collision_layer = 0
	collision_mask = 1
	Game.kills += 1
	Audio.play_3d("zombie_death", global_position + Vector3.UP * 1.2, -2.0, 6.0, 0.1)
	if not _animator.play_once("death") and placeholder:
		var tw := create_tween()
		tw.tween_property(placeholder, "rotation:x", -PI / 2.0, 0.4).set_trans(Tween.TRANS_QUAD)
	if randf() < loot_drop_chance and is_instance_valid(Game.level):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for entry in Items.roll("zombie", rng):
			Game.level.spawn_pickup(entry[0], global_position + Vector3(randf_range(0.3, 0.9), 0.0, randf_range(-0.4, 0.4)), false, entry[1])
	get_tree().create_timer(20.0).timeout.connect(queue_free)
