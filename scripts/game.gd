extends Node
## Global oyun durumu (autoload: "Game").
## Zaman / gün döngüsü, gürültü sistemi, skor ve tuş atamaları burada.

signal noise_emitted(pos: Vector3, radius: float)
signal level_ready

const DAY_LENGTH_SEC := 720.0   # 1 oyun günü = 12 gerçek dakika
const START_HOUR := 9.0

var day := 1
var hour := START_HOUR
var kills := 0
var player: Player
var level: Level
var nav_ready := false
var ui_open := false   # envanter gibi bir pencere açıkken oyuncu saldırmaz/yürümez

var _blood_mesh: SphereMesh
var _decal_mat: StandardMaterial3D
var _decals: Array[Node3D] = []
const MAX_DECALS := 60


func _ready() -> void:
	_setup_input()


func _exit_tree() -> void:
	PropLibrary.clear()
	UITheme.clear()
	Throwable.clear()
	GroundBuilder.clear()


func _process(delta: float) -> void:
	var prev := hour
	hour += delta * 24.0 / DAY_LENGTH_SEC
	if hour >= 24.0:
		hour -= 24.0
		day += 1
	# Her şafakta otomatik kayıt
	if prev < 6.0 and hour >= 6.0 and can_save():
		if save_game():
			player.message.emit("Gün doğdu. Oyun kaydedildi.")


# ------------------------------------------------------------------
# Kayıt sistemi (user://savegame.json)
# Ölünce kayıt silinir (kalıcı ölüm). Harita aynı tohumla kurulduğu için
# sadece değişen şeyler saklanır: oyuncu, envanter, barikatlar, yerdeki eşyalar,
# aranmış yerler, zombiler, zaman.
# ------------------------------------------------------------------

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

var pending_load: Dictionary = {}     # ana menüden "Devam Et" ile gelen kayıt
var loaded_from_save := false


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func can_save() -> bool:
	return nav_ready and is_instance_valid(player) and not player.is_dead and is_instance_valid(level)


func read_save() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


## Kayıt özeti (ana menüde göstermek için): "Gün 3 · 14:20 · Normal"
func save_summary() -> String:
	var d := read_save()
	if d.is_empty():
		return ""
	var h := int(d.get("hour", 0.0))
	var m := int((float(d.get("hour", 0.0)) - h) * 60.0)
	var diff: int = clampi(int(d.get("difficulty", 1)), 0, 2)
	return "Gün %d  ·  %02d:%02d  ·  %s" % [int(d.get("day", 1)), h, m, Settings.DIFFICULTY_NAMES[diff]]


func save_game() -> bool:
	if not can_save():
		return false
	var p := player
	var d := {
		"version": SAVE_VERSION,
		"day": day, "hour": hour, "kills": kills,
		"difficulty": Settings.difficulty,
		"player": {
			"pos": _v(p.global_position), "yaw": p.model_pivot.rotation.y,
			"health": p.health, "stamina": p.stamina, "hunger": p.hunger, "thirst": p.thirst,
			"items": p.inv.items, "weapons": p.inv.weapons, "equipped": p.inv.equipped,
			"flashlight": p.flashlight_on,
		},
		"searched": level.searched_ids(),
		"barricades": [], "traps": [], "pickups": [], "zombies": [],
	}
	for n in get_tree().get_nodes_in_group("barricades"):
		var b := n as Barricade
		d.barricades.append({"kind": b.kind, "name": b.display_name, "pos": _v(b.global_position),
			"rot": b.rotation.y, "hp": b.hp, "max_hp": b.max_hp})
	for n in get_tree().get_nodes_in_group("traps"):
		var t := n as SpikeTrap
		d.traps.append({"pos": _v(t.global_position), "rot": t.rotation.y, "uses": t.uses})
	for n in get_tree().get_nodes_in_group("pickups"):
		var pk := n as Pickup
		d.pickups.append({"type": pk.item_type, "amount": pk.amount, "durability": pk.durability, "pos": _v(pk.global_position)})
	for n in get_tree().get_nodes_in_group("zombies"):
		var z := n as Zombie
		d.zombies.append({"pos": _v(z.global_position), "health": z.health})
	var spawner := get_tree().current_scene.get_node_or_null("ZombieSpawner")
	if spawner:
		d["last_horde_day"] = spawner.get("_last_horde_day")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "  "))
	return true


## Ana menüden "Devam Et": kaydı okuyup oyun sahnesine hazırlar.
func prepare_continue() -> bool:
	var d := read_save()
	if d.is_empty():
		return false
	reset_run()
	day = int(d.get("day", 1))
	hour = float(d.get("hour", START_HOUR))
	kills = int(d.get("kills", 0))
	Settings.difficulty = int(d.get("difficulty", 1))
	pending_load = d
	return true


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


static func to_vec(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


func is_night() -> bool:
	return hour < 6.0 or hour >= 20.0


func reset_run() -> void:
	day = 1
	hour = START_HOUR
	kills = 0
	nav_ready = false
	ui_open = false
	pending_load = {}
	loaded_from_save = false
	player = null
	level = null
	_decals.clear()


## Silah sesi, koşma, dövüş... Yarıçap içindeki zombiler sesi araştırmaya gelir.
func make_noise(pos: Vector3, radius: float) -> void:
	noise_emitted.emit(pos, radius)


func spawn_blood(pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null or not Settings.blood:
		return
	if _blood_mesh == null:
		_blood_mesh = SphereMesh.new()
		_blood_mesh.radius = 0.05
		_blood_mesh.height = 0.1
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.02, 0.02)
		_blood_mesh.material = m
		_decal_mat = StandardMaterial3D.new()
		_decal_mat.albedo_color = Color(0.22, 0.02, 0.02)
		_decal_mat.roughness = 0.4

	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.mesh = _blood_mesh
	scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

	# Yerde kalan kan lekesi
	var decal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var r := randf_range(0.25, 0.6)
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = 0.01
	cyl.material = _decal_mat
	decal.mesh = cyl
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(decal)
	decal.global_position = Vector3(pos.x + randf_range(-0.4, 0.4), 0.015, pos.z + randf_range(-0.4, 0.4))
	_decals.append(decal)
	while _decals.size() > MAX_DECALS:
		var old: Node3D = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# --- Tuş atamaları (project.godot'u şişirmemek için kodla tanımlanıyor) ---

func _setup_input() -> void:
	_bind_keys("move_up", [KEY_W, KEY_UP])
	_bind_keys("move_down", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("interact", [KEY_E])
	_bind_keys("flashlight", [KEY_F])
	_bind_keys("switch_weapon", [KEY_Q])
	_bind_keys("inventory", [KEY_TAB, KEY_I])
	_bind_keys("build", [KEY_B])
	_bind_keys("rotate_build", [KEY_R])
	_bind_keys("use_food", [KEY_1])
	_bind_keys("use_water", [KEY_2])
	_bind_keys("use_medkit", [KEY_3])
	_bind_keys("use_bandage", [KEY_4])
	_bind_keys("craft", [KEY_C])
	_bind_keys("throw", [KEY_G])
	_bind_keys("switch_throwable", [KEY_Z])
	_bind_keys("pause", [KEY_ESCAPE])
	_bind_keys("restart", [KEY_R, KEY_ENTER])
	_bind_keys("toggle_help", [KEY_H])
	_bind_keys("attack", [KEY_SPACE])
	_bind_mouse("attack", MOUSE_BUTTON_LEFT)
	_bind_mouse("aim", MOUSE_BUTTON_RIGHT)


func _bind_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _bind_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
