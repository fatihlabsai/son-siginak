extends Node
## Oyun ayarları (autoload: "Settings"). user://settings.cfg dosyasına kaydedilir.

signal changed

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Düşük", "Orta", "Yüksek"]
const DIFFICULTY_NAMES := ["Kolay", "Normal", "Zor"]
## Zorluk çarpanları: [kolay, normal, zor]
const DIFF := {
	"damage": [0.6, 1.0, 1.5],   # zombi ısırık hasarı
	"zombies": [0.7, 1.0, 1.4],  # aynı anda kaç zombi / sürü büyüklüğü
	"hunger": [0.7, 1.0, 1.3],   # açlık / susuzluk hızı
	"loot": [1.3, 1.0, 0.7],     # erzak bolluğu
}

var fullscreen := false
var vsync := true
var quality := 2
var master_volume := 0.8
var music_volume := 0.7
var sfx_volume := 0.9
var blood := true
var show_help := true
var camera_zoom := 20.0
var difficulty := 1


func _ready() -> void:
	load_settings()
	apply()


func diff(key: String) -> float:
	return DIFF[key][clampi(difficulty, 0, 2)]


func reset_defaults() -> void:
	fullscreen = false
	vsync = true
	quality = 2
	master_volume = 0.8
	music_volume = 0.7
	sfx_volume = 0.9
	blood = true
	show_help = true
	camera_zoom = 20.0
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
	vsync = cfg.get_value("display", "vsync", vsync)
	quality = cfg.get_value("display", "quality", quality)
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	blood = cfg.get_value("gameplay", "blood", blood)
	show_help = cfg.get_value("gameplay", "show_help", show_help)
	camera_zoom = cfg.get_value("gameplay", "camera_zoom", camera_zoom)
	difficulty = cfg.get_value("gameplay", "difficulty", difficulty)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "quality", quality)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("gameplay", "blood", blood)
	cfg.set_value("gameplay", "show_help", show_help)
	cfg.set_value("gameplay", "camera_zoom", camera_zoom)
	cfg.set_value("gameplay", "difficulty", difficulty)
	cfg.save(PATH)


func apply() -> void:
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("Ambience", sfx_volume)
	var msaa := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
	get_viewport().msaa_3d = msaa[clampi(quality, 0, 2)]
	changed.emit()


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


## Sahnedeki ışık / ortamı grafik kalitesine göre ayarlar.
func apply_to_world(sun: Light3D, env: Environment) -> void:
	if sun:
		sun.shadow_enabled = quality >= 1
	if env:
		env.ssao_enabled = quality >= 2
		env.glow_enabled = quality >= 1
