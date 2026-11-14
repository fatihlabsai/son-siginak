extends Node
## Ses yöneticisi (autoload: "Audio").
##  - assets/audio/sfx/ içindeki "isim_0.wav, isim_1.wav..." dosyalarını "isim" grubunda toplar,
##    her çalışta rastgele birini ve hafif farklı perdeyi seçer (tekrar hissi azalır).
##  - Müzik (iki kanal arası yumuşak geçiş), sürekli ambiyans döngüleri ve 3D efekt havuzu.
##  - Ses kanalları (bus): Master > Music / SFX / Ambience

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const LOOPS := ["wind", "crickets", "fire", "heartbeat", "theme"]
const POOL_3D := 28
const POOL_2D := 10

var _lib := {}
var _music := {}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _ui: AudioStreamPlayer
var _i3 := 0
var _i2 := 0

var _music_players: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_name := ""
var _music_targets := [-80.0, -80.0]
var _music_fade := 2.0

var _amb := {}   # isim -> {player, target}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Ambience"]:
		_ensure_bus(bus)
	_load_dir(SFX_DIR, _lib)
	_load_dir(MUSIC_DIR, _music)

	# 3D efektler oyun duraklayınca durur; arayüz/müzik/ambiyans devam eder.
	var world_root := Node.new()
	world_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world_root)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_distance = 60.0
		p.panning_strength = 0.8
		world_root.add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		world_root.add_child(p)
		_pool2d.append(p)
	_ui = AudioStreamPlayer.new()
	_ui.bus = "SFX"
	_ui.max_polyphony = 4
	add_child(_ui)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music_players.append(m)


func _exit_tree() -> void:
	# Kapanışta çalan döngüleri durdur (aksi halde Godot sızıntı uyarısı verir)
	for p in find_children("*", "AudioStreamPlayer", true, false):
		(p as AudioStreamPlayer).stop()
	for p in find_children("*", "AudioStreamPlayer3D", true, false):
		(p as AudioStreamPlayer3D).stop()


func _process(delta: float) -> void:
	# Müzik geçişleri
	for i in 2:
		var p := _music_players[i]
		p.volume_db = move_toward(p.volume_db, _music_targets[i], delta * 60.0 / _music_fade)
		if p.playing and p.volume_db <= -79.0 and _music_targets[i] <= -79.0:
			p.stop()
	# Ambiyans seviyeleri
	for key in _amb:
		var e: Dictionary = _amb[key]
		var p: AudioStreamPlayer = e.player
		p.volume_db = move_toward(p.volume_db, e.target, delta * 25.0)
		if p.volume_db <= -59.0 and e.target <= -59.0:
			if p.playing:
				p.stop()
		elif not p.playing:
			p.play()


# ------------------------------------------------------------------
# Efektler
# ------------------------------------------------------------------

func has_sound(sound: String) -> bool:
	return _lib.has(sound)


## Dünyada bir noktada çalar. unit_size büyüdükçe ses daha uzaktan duyulur.
func play_3d(sound: String, pos: Vector3, volume_db := 0.0, unit_size := 6.0, pitch_var := 0.08) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var p := _next_3d()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.global_position = pos
	p.play()


## Konumsuz efekt (oyuncunun kendi sesleri, olay uyarıları).
func play_2d(sound: String, volume_db := 0.0, pitch_var := 0.05) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var p := _pool2d[_i2]
	_i2 = (_i2 + 1) % _pool2d.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## Menü sesleri (oyun duraklatılmışken de çalar).
func ui(sound: String, volume_db := -4.0) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	_ui.stream = stream
	_ui.volume_db = volume_db
	_ui.pitch_scale = 1.0 + randf_range(-0.03, 0.03)
	_ui.play()


func stop_world_sounds() -> void:
	for p in _pool3d:
		p.stop()
	for p in _pool2d:
		p.stop()


## Bir sahneye bağlı sürekli 3D döngü (örn. kamp ateşi). Sahneyle birlikte silinir.
func attach_loop(sound: String, parent: Node3D, offset := Vector3.ZERO, volume_db := 0.0, unit_size := 5.0) -> AudioStreamPlayer3D:
	var stream := _pick(sound)
	if stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "Ambience"
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = 40.0
	p.position = offset
	p.autoplay = true
	parent.add_child(p)
	return p


# ------------------------------------------------------------------
# Müzik ve ambiyans
# ------------------------------------------------------------------

## Müziği yumuşakça değiştirir. Boş isim = müziği sustur.
func play_music(track: String, fade := 2.0, volume_db := -6.0) -> void:
	_music_fade = maxf(fade, 0.05)
	if track == _music_name:
		_music_targets[_music_active] = volume_db if track != "" else -80.0
		return
	_music_name = track
	_music_targets[_music_active] = -80.0
	if track == "" or not _music.has(track):
		return
	_music_active = 1 - _music_active
	var p := _music_players[_music_active]
	p.stream = _music[track][0]
	p.volume_db = -80.0 if fade > 0.05 else volume_db
	p.play()
	_music_targets[_music_active] = volume_db


## Sürekli ambiyans katmanının hedef ses seviyesi (-60 = kapalı). Her kare çağrılabilir.
func set_ambience(sound: String, volume_db: float) -> void:
	if not _amb.has(sound):
		var stream := _pick(sound)
		if stream == null:
			return
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Ambience"
		p.volume_db = -60.0
		add_child(p)
		_amb[sound] = {"player": p, "target": -60.0}
	_amb[sound].target = volume_db


func stop_all_ambience() -> void:
	for key in _amb:
		_amb[key].target = -60.0


# ------------------------------------------------------------------
# İç işler
# ------------------------------------------------------------------

func _next_3d() -> AudioStreamPlayer3D:
	for k in _pool3d.size():
		var p := _pool3d[(_i3 + k) % _pool3d.size()]
		if not p.playing:
			_i3 = (_i3 + k + 1) % _pool3d.size()
			return p
	var q := _pool3d[_i3]
	_i3 = (_i3 + 1) % _pool3d.size()
	return q


func _pick(sound: String) -> AudioStream:
	if not _lib.has(sound):
		if not _music.has(sound):
			return null
		return _music[sound][0]
	var arr: Array = _lib[sound]
	return arr[randi() % arr.size()]


func _load_dir(dir: String, into: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if not file.ends_with(".wav") and not file.ends_with(".ogg"):
			continue
		var stream := load(dir + file) as AudioStream
		if stream == null:
			continue
		var base := file.get_basename()
		var key := base
		var us := base.rfind("_")
		if us > 0 and base.substr(us + 1).is_valid_int():
			key = base.substr(0, us)
		if key in LOOPS:
			_make_loop(stream)
		if not into.has(key):
			into[key] = []
		if not stream in into[key]:
			into[key].append(stream)


func _make_loop(stream: AudioStream) -> void:
	var w := stream as AudioStreamWAV
	if w:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(round(w.get_length() * w.mix_rate))
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
