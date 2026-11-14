extends Node3D
## Zombileri oyuncunun görüş alanı dışında doğurur, uzaktakileri temizler.
## Gece daha fazla zombi olur; her gece 22:00'de bir sürü (horde) kampa doğru gelir.

@export var zombie_scene: PackedScene
@export var initial_count := 14
@export var day_max := 14
@export var night_max := 34
@export var spawn_interval := 2.5
@export var min_spawn_distance := 24.0
@export var max_spawn_distance := 42.0
@export var despawn_distance := 75.0
@export var map_half_size := 55.0
@export var horde_base_size := 6
@export var horde_per_day := 2

var _timer := 0.0
var _active := false
var _last_horde_day := 0


func _ready() -> void:
	var m := Settings.diff("zombies")
	initial_count = int(initial_count * m)
	day_max = int(day_max * m)
	night_max = int(night_max * m)
	horde_base_size = int(horde_base_size * m)
	Game.level_ready.connect(_on_level_ready)
	if Game.nav_ready:
		_on_level_ready()


func _on_level_ready() -> void:
	if _active:
		return
	_active = true
	if Game.loaded_from_save:
		return   # zombiler kayıttan geldi
	for i in initial_count:
		_spawn(true)


func _physics_process(delta: float) -> void:
	if not _active or zombie_scene == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_despawn_far()
		var max_count := night_max if Game.is_night() else day_max
		if _alive_count() < max_count:
			_spawn(false)
	if Game.hour >= 22.0 and _last_horde_day != Game.day:
		_last_horde_day = Game.day
		_spawn_horde()


func _player_pos() -> Vector3:
	if is_instance_valid(Game.player):
		return Game.player.global_position
	return Vector3.ZERO


func _spawn(anywhere: bool) -> Zombie:
	var center := _player_pos()
	for attempt in 12:
		var pos: Vector3
		if anywhere:
			pos = Vector3(randf_range(-map_half_size, map_half_size), 0.0, randf_range(-map_half_size, map_half_size))
		else:
			var ang := randf() * TAU
			var d := randf_range(min_spawn_distance, max_spawn_distance)
			pos = center + Vector3(cos(ang) * d, 0.0, sin(ang) * d)
		if absf(pos.x) > map_half_size or absf(pos.z) > map_half_size:
			continue
		pos = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, pos)
		if Vector2(pos.x - center.x, pos.z - center.z).length() < min_spawn_distance * 0.8:
			continue
		return _spawn_at(pos)
	return null


func _spawn_at(pos: Vector3) -> Zombie:
	var z := zombie_scene.instantiate() as Zombie
	z.position = pos + Vector3.UP * 0.05  # spawner orijinde, local == global
	add_child(z)
	return z


func _spawn_horde() -> void:
	var size := horde_base_size + horde_per_day * (Game.day - 1)
	var center := _player_pos()
	var ang := randf() * TAU
	var origin := center + Vector3(cos(ang), 0.0, sin(ang)) * max_spawn_distance
	origin.x = clampf(origin.x, -map_half_size, map_half_size)
	origin.z = clampf(origin.z, -map_half_size, map_half_size)
	for i in size:
		var p := origin + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		p = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)
		var z := _spawn_at(p)
		z.alert_to(center)
	Audio.play_2d("horde", -1.0, 0.0)
	if is_instance_valid(Game.player):
		Game.player.message.emit("Uzaktan iniltiler yükseliyor... Bir sürü geliyor!")


func _alive_count() -> int:
	var n := 0
	for c in get_children():
		var z := c as Zombie
		if z and not z.is_dead:
			n += 1
	return n


func _despawn_far() -> void:
	var center := _player_pos()
	for c in get_children():
		var z := c as Zombie
		if z == null or z.is_dead or z.state == Zombie.State.CHASE:
			continue
		if Vector2(z.global_position.x - center.x, z.global_position.z - center.z).length() > despawn_distance:
			z.queue_free()
