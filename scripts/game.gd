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
var cutscene_active := false   # ara sahne sırasında zaman durur, arayüz gizlenir
var play_shelter_intro := false   # açılış ara sahnesinden sonra sığınak sahnesi oynasın
var ambient_scale := 1.0   # ara sahnede ortam ışığını kısmak için

var _blood_mesh: SphereMesh
var _decal_mat: StandardMaterial3D
var _decals: Array[Node3D] = []
const MAX_DECALS := 60


func _ready() -> void:
	_migrate_legacy_save()
	_setup_input()


## Son girdi oyun kolundan mı geldi? (nişan ve ipuçları buna göre)
var using_pad := false

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.35):
		using_pad = true
	elif event is InputEventMouseMotion or event is InputEventKey or event is InputEventMouseButton:
		using_pad = false


func _exit_tree() -> void:
	PropLibrary.clear()
	UITheme.clear()
	Throwable.clear()
	GroundBuilder.clear()


func _process(delta: float) -> void:
	if cutscene_active:
		return
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

const LEGACY_SAVE_PATH := "user://savegame.json"
const SLOT_COUNT := 3
const SAVE_VERSION := 1

## Etkin kayıt yuvası (0..2). Yeni oyun ve Devam Et bunu ayarlar.
var slot := 0


func slot_path(i: int) -> String:
	return "user://save_%d.json" % (i + 1)


func has_save_slot(i: int) -> bool:
	return FileAccess.file_exists(slot_path(i))


func any_save() -> bool:
	for i in SLOT_COUNT:
		if has_save_slot(i):
			return true
	return false


## En son değişen kaydın yuvası; kayıt yoksa -1.
func latest_slot() -> int:
	var best := -1
	var best_t := -1
	for i in SLOT_COUNT:
		if has_save_slot(i):
			var t := FileAccess.get_modified_time(slot_path(i))
			if t > best_t:
				best_t = t
				best = i
	return best


## Yeni oyun için yuva: önce boş olan, hepsi doluysa en eski.
func free_or_oldest_slot() -> int:
	var oldest := 0
	var oldest_t := 1 << 62
	for i in SLOT_COUNT:
		if not has_save_slot(i):
			return i
		var t := FileAccess.get_modified_time(slot_path(i))
		if t < oldest_t:
			oldest_t = t
			oldest = i
	return oldest


func read_save_slot(i: int) -> Dictionary:
	if not has_save_slot(i):
		return {}
	var f := FileAccess.open(slot_path(i), FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


func summary_of(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	var h := int(d.get("hour", 0.0))
	var m := int((float(d.get("hour", 0.0)) - h) * 60.0)
	var diff: int = clampi(int(d.get("difficulty", 1)), 0, 2)
	return "Gün %d  ·  %02d:%02d  ·  %s" % [int(d.get("day", 1)), h, m, Settings.DIFFICULTY_NAMES[diff]]


func delete_slot(i: int) -> void:
	if has_save_slot(i):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(i)))


## Eski tek dosyalık kaydı 1. yuvaya taşı.
func _migrate_legacy_save() -> void:
	if FileAccess.file_exists(LEGACY_SAVE_PATH) and not has_save_slot(0):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(LEGACY_SAVE_PATH), ProjectSettings.globalize_path(slot_path(0)))

var pending_load: Dictionary = {}     # ana menüden "Devam Et" ile gelen kayıt
var loaded_from_save := false


func has_save() -> bool:
	return has_save_slot(slot)


func delete_save() -> void:
	delete_slot(slot)


func can_save() -> bool:
	return nav_ready and is_instance_valid(player) and not player.is_dead and is_instance_valid(level)


func read_save() -> Dictionary:
	return read_save_slot(slot)


## Kayıt özeti (ana menüde göstermek için): "Gün 3 · 14:20 · Normal"
func save_summary() -> String:
	return summary_of(read_save())


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
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
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
	cutscene_active = false
	play_shelter_intro = false
	ambient_scale = 1.0
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
	_bind_keys("map", [KEY_M])
	_bind_keys("throw", [KEY_G])
	_bind_keys("switch_throwable", [KEY_Z])
	_bind_keys("pause", [KEY_ESCAPE])
	_bind_keys("restart", [KEY_R, KEY_ENTER])
	_bind_keys("toggle_help", [KEY_H])
	_bind_keys("attack", [KEY_SPACE])
	_bind_mouse("attack", MOUSE_BUTTON_LEFT)
	_bind_mouse("aim", MOUSE_BUTTON_RIGHT)
	_setup_pad()


## Oyun kolu (Xbox düzeni; PlayStation'da aynı yerdeki tuşlar):
##  Sol çubuk yürü · Sağ çubuk nişan yönü · RT vur/ateş · LT nişan al
##  A etkileşim · B fener · X inşa · Y silah değiştir (inşada döndür)
##  LB koş · RB fırlat · L3 fırlatılacağı değiştir · R3 harita
##  Back/View: dokun envanter, basılı tut üretim · Start duraklat · Yön tuşları 1-2-3-4
func _setup_pad() -> void:
	_bind_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_bind_axis("attack", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_bind_axis("aim", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_bind_pad("interact", JOY_BUTTON_A)
	_bind_pad("flashlight", JOY_BUTTON_B)
	_bind_pad("build", JOY_BUTTON_X)
	_bind_pad("switch_weapon", JOY_BUTTON_Y)
	_bind_pad("rotate_build", JOY_BUTTON_Y)
	_bind_pad("sprint", JOY_BUTTON_LEFT_SHOULDER)
	_bind_pad("throw", JOY_BUTTON_RIGHT_SHOULDER)
	_bind_pad("switch_throwable", JOY_BUTTON_LEFT_STICK)
	_bind_pad("map", JOY_BUTTON_RIGHT_STICK)
	_bind_pad("pad_menu", JOY_BUTTON_BACK)
	_bind_pad("pause", JOY_BUTTON_START)
	_bind_pad("restart", JOY_BUTTON_START)
	_bind_pad("use_food", JOY_BUTTON_DPAD_UP)
	_bind_pad("use_water", JOY_BUTTON_DPAD_RIGHT)
	_bind_pad("use_medkit", JOY_BUTTON_DPAD_DOWN)
	_bind_pad("use_bandage", JOY_BUTTON_DPAD_LEFT)


func _bind_pad(action: String, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _bind_axis(action: String, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


## Sağ çubuğun yönü (ölü bölge dışında), yoksa sıfır.
func right_stick() -> Vector2:
	var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	return v if v.length() > 0.3 else Vector2.ZERO


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
