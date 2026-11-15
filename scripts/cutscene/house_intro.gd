extends Node3D
## Açılış ara sahnesi: Mercer evi, salon, öğleden sonra.
## June okul projesi için fotoğrafları sehpaya dizer, Nora koltuğun ucunda kahvesini içer.
## Caleb arar: kuzey köprüsü kapatılacak. Sonra kararır: "Altı gün sonra" -> sığınak.
##
## Her şey kodla kurulur; modeller assets/models/intro ve characters altından gelir.
## Diyaloglar İngilizce (ElevenLabs), alt yazılar Türkçe.

const GAME_SCENE := "res://scenes/main.tscn"
const A := "res://assets/audio/intro/"
const M := "res://assets/models/intro/"
const C := "res://assets/models/characters/"

## Sahnedeki ana noktalar (metre)
const TABLE_POS := Vector3(0.0, 0.0, -1.22)
const NORA_POS := Vector3(0.55, 0.0, -1.95)
const JUNE_POS := Vector3(-0.35, 0.0, -0.55)
const TV_POS := Vector3(0.0, 0.0, 2.45)
const PHONE_POS := Vector3(0.06, 0.0, -1.4)
const KEY_PHOTO_POS := Vector3(0.42, 0.0, -1.4)

## Çekim sonrası ayarlanan değerler (ilk önizlemelerden)
var table_top := 0.36

var ui: CutsceneUI
var cam: Camera3D
var nora: CutsceneActor
var june: CutsceneActor
var phone: Node3D
var phone_screen: PhoneScreen
var key_photo: Node3D
var key_photo_corner: Node3D
var photos: Array[Node3D] = []
var tv_screen: TvScreen
var _players: Array[AudioStreamPlayer] = []
var _skipped := false
var _done := false
var _photo_textures: Array[Texture2D] = []


func _ready() -> void:
	Game.cutscene_active = true
	Audio.stop_world_sounds()
	Audio.stop_all_ambience()
	Audio.play_music("", 1.0)
	ui = CutsceneUI.new()
	add_child(ui)
	ui.skip_requested.connect(_skip)
	_build_environment()
	_build_room()
	_build_furniture()
	_build_people()
	await _render_photos()
	_build_table_items()
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.near = 0.05
	cam.cull_mask = 1
	add_child(cam)
	cam.make_current()
	_run()


# ------------------------------------------------------------------
# Zaman çizelgesi
# ------------------------------------------------------------------

func _run() -> void:
	var amb := _sound("amb_living_room", -16.0, true)
	var tv := _sound("tv_weather", -21.0)
	tv.bus = _tv_bus()
	ui.bars(true, 0.01)
	ui.set_black(1.0)
	ui.fade_to(0.0, 2.2)

	# S1 — Kuruluş planı: köşeden salona yavaş kayma
	_shot(Vector3(2.7, 1.55, 2.0), Vector3(0.0, 0.7, -1.3), 40.0, 6.0, Vector3(2.2, 1.45, 1.6), Vector3(-0.1, 0.65, -1.3))
	if await _wait(6.0): return

	# S2 — Sehpadaki fotoğraflar, Caleb'in fotoğrafına itiş
	var kp := key_photo.global_position
	_shot(kp + Vector3(0.1, 0.62, 0.2), kp, 38.0, 4.0, kp + Vector3(0.02, 0.36, 0.1), kp + Vector3(0, 0, -0.01))
	if await _wait(3.7): return

	# S3 — Nora: "Bunu mu koyacaksın?"
	var nh := nora.bone_global("mixamorig_Head")
	_shot(nh + Vector3(-0.55, -0.05, 1.25), nh + Vector3(0, -0.12, 0), 34.0, 3.8, nh + Vector3(-0.5, -0.05, 1.05), nh + Vector3(0, -0.12, 0))
	if await _wait(0.3): return
	_line("nora_1", "NORA", "Bunu mu koyacaksın?")
	if await _wait(3.5): return

	# S4 — June: "Evet. Babamın gülümsemeye çalışmadığı tek fotoğraf."
	var jt := JUNE_POS + Vector3(0.0, 0.62, -0.15)
	_shot(JUNE_POS + Vector3(1.6, 1.0, -0.5), jt, 38.0, 5.0, JUNE_POS + Vector3(1.45, 0.97, -0.45), jt)
	if await _wait(0.3): return
	_line("june_1", "JUNE", "Evet. Babamın gülümsemeye çalışmadığı tek fotoğraf.")
	if await _wait(4.7): return

	# S5 — Nora fotoğrafı eline alır, telefon çalar
	_shot(Vector3(1.55, 1.05, -0.35), nh + Vector3(-0.15, -0.35, 0.2), 38.0, 4.0, Vector3(1.4, 1.0, -0.45), nh + Vector3(-0.15, -0.4, 0.2))
	_put_mug_down()
	var pick_len := nora.play("pick up", false, 0.4)
	_sfx_at(1.5, "sfx_photo", -10.0)
	_grab_photo_later(pick_len * 0.36)
	if await _wait(2.9): return
	var ring := _sound("sfx_phone_ring", -7.0)
	_vibrate_phone(true)
	phone_screen.set_state("incoming")
	if await _wait(0.9): return

	# S6 — Telefon yakın plan: ekranda "Caleb"
	var pp := phone.global_position
	_shot(pp + Vector3(0.05, 0.42, 0.28), pp, 36.0, 2.6, pp + Vector3(0.03, 0.34, 0.2), pp)
	if await _wait(1.8): return
	ring.stop()
	_vibrate_phone(false)
	phone_screen.set_state("speaker")
	_sfx("sfx_call_end", -20.0)
	if await _wait(0.3): return
	_line("nora_2", "NORA", "Efendim?")
	if await _wait(0.6): return

	# S7 — İkili plan (TV tarafından): Caleb hoparlörde
	_shot(Vector3(0.7, 1.45, 1.1), Vector3(0.15, 0.55, -1.5), 40.0, 10.5, Vector3(0.6, 1.4, 0.85), Vector3(0.15, 0.55, -1.5))
	_sfx("sfx_truck_door_phone", -12.0)
	if await _wait(0.9): return
	_line("caleb_1", "CALEB (TELEFONDA)", "İlçeden aradılar. Kuzey köprüsünü kapatmamızı istiyorlar.")
	if await _wait(3.6): return
	_line("nora_3", "NORA", "Ne olmuş?")
	if await _wait(1.4): return
	_line("caleb_2", "CALEB (TELEFONDA)", "Söylemediler. Bariyerleri bırakıp dönerim. Akşam evdeyim.")
	if await _wait(4.3): return

	# S8 — June telefona eğilir: "Gelirken süt alır mısın?"
	_shot(JUNE_POS + Vector3(-0.85, 0.95, -1.4), jt + Vector3(0, -0.08, -0.1), 36.0, 3.4, JUNE_POS + Vector3(-0.75, 0.9, -1.25), jt + Vector3(0, -0.1, -0.15))
	june.play("phone", false, 0.4)
	if await _wait(0.7): return
	_line("june_2", "JUNE", "Gelirken süt alır mısın?")
	if await _wait(2.6): return

	# S9 — Nora: Caleb "Olur."
	_shot(nh + Vector3(-0.75, -0.1, 1.4), nh + Vector3(0, -0.2, 0), 36.0, 3.2, nh + Vector3(-0.68, -0.1, 1.25), nh + Vector3(0, -0.2, 0))
	june.play("next to a low", true, 0.8)
	_line("caleb_3", "CALEB (TELEFONDA)", "Olur.")
	if await _wait(2.4): return
	_sfx("sfx_call_end", -10.0)
	phone_screen.set_state("ended")
	if await _wait(0.8): return

	# S10 — Fotoğraf yerine, June kıvrılan köşeyi düzeltir
	_shot(kp + Vector3(0.14, 0.55, 0.16), kp, 36.0, 5.5, kp + Vector3(0.06, 0.4, 0.1), kp)
	nora.play("pick up", false, 0.3, 1.0, true)
	_return_photo_later(pick_len * 0.6)
	_sfx_at(pick_len * 0.6, "sfx_photo", -12.0)
	if await _wait(pick_len * 0.6 + 1.2): return
	var tw := create_tween()
	tw.tween_property(key_photo_corner, "rotation:x", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	_sfx("sfx_photo", -18.0)
	if await _wait(2.0): return

	# KARARIR
	ui.clear_subtitle()
	ui.fade_to(1.0, 2.0)
	_fade_audio(amb, 2.0)
	_fade_audio(tv, 2.0)
	if await _wait(2.6): return
	await ui.caption("Altı gün sonra", 3.2)
	_finish()


func _skip() -> void:
	if _skipped or _done:
		return
	_skipped = true
	ui.clear_subtitle()
	for p in _players:
		if is_instance_valid(p):
			p.stop()
	await ui.fade_to(1.0, 0.5).finished
	_finish()


## Bekler; atlandıysa true döner (çağıran return etsin).
func _wait(t: float) -> bool:
	if _skipped:
		return true
	await get_tree().create_timer(t).timeout
	return _skipped


func _finish() -> void:
	if _done:
		return
	_done = true
	Game.cutscene_active = false
	Game.hour = Game.START_HOUR
	Game.play_shelter_intro = true
	get_tree().change_scene_to_file(GAME_SCENE)


# ------------------------------------------------------------------
# Kamera, ses, alt yazı
# ------------------------------------------------------------------

func _shot(from: Vector3, look: Vector3, fov: float, dur: float, to := Vector3.INF, look_to := Vector3.INF) -> void:
	var tw0: Tween = cam.get_meta("tween") if cam.has_meta("tween") else null
	if tw0 and tw0.is_valid():
		tw0.kill()
	cam.fov = fov
	cam.global_position = from
	cam.look_at(look)
	if to == Vector3.INF:
		return
	if look_to == Vector3.INF:
		look_to = look
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(k: float):
		cam.global_position = from.lerp(to, k)
		cam.look_at(look.lerp(look_to, k)), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cam.set_meta("tween", tw)


func _sound(name: String, db: float, loop := false) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s := load(A + name + ".ogg") as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	p.stream = s
	p.volume_db = db
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(p)
	p.play()
	_players.append(p)
	return p


func _sfx(name: String, db: float) -> void:
	var p := _sound(name, db)
	p.finished.connect(p.queue_free)


func _sfx_at(t: float, name: String, db: float) -> void:
	await get_tree().create_timer(t).timeout
	if not _skipped:
		_sfx(name, db)


func _line(name: String, speaker: String, text: String) -> void:
	var p := _sound(name, -1.0)
	p.bus = "Master"
	var len := p.stream.get_length() if p.stream else 2.0
	ui.subtitle(speaker, text, len + 0.4)


func _fade_audio(p: AudioStreamPlayer, dur: float) -> void:
	if is_instance_valid(p):
		create_tween().tween_property(p, "volume_db", -60.0, dur)


## TV sesi için boğuk (alçak geçiren) bir bus.
func _tv_bus() -> String:
	var name := "IntroTV"
	if AudioServer.get_bus_index(name) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 2600.0
		AudioServer.add_bus_effect(i, lp)
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.25
		rv.wet = 0.12
		AudioServer.add_bus_effect(i, rv)
	return name


# ------------------------------------------------------------------
# Fotoğraf ve telefon hareketleri
# ------------------------------------------------------------------

var _photo_home: Transform3D
var _mug: MeshInstance3D

func _put_mug_down() -> void:
	if not is_instance_valid(_mug):
		return
	_mug.get_parent().remove_child(_mug)
	add_child(_mug)
	_mug.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.5, table_top + 0.05, -1.02))

func _grab_photo_later(t: float) -> void:
	await get_tree().create_timer(t).timeout
	if _skipped:
		return
	_photo_home = key_photo.global_transform
	var gt := key_photo.global_transform
	var att := nora.attach("mixamorig_RightHand", Node3D.new())
	if att == null:
		return
	var holder := att.get_child(0).get_child(0) as Node3D
	key_photo.get_parent().remove_child(key_photo)
	holder.add_child(key_photo)
	key_photo.global_transform = gt
	# Elde tutulurken fotoğraf avuç içine doğru otursun
	create_tween().tween_property(key_photo, "position", Vector3(0.0, 0.09, 0.03), 0.4)


func _return_photo_later(t: float) -> void:
	await get_tree().create_timer(t).timeout
	if _skipped:
		return
	var gt := key_photo.global_transform
	key_photo.get_parent().remove_child(key_photo)
	add_child(key_photo)
	key_photo.global_transform = gt
	var tw := create_tween()
	tw.tween_property(key_photo, "global_transform", _photo_home, 0.35).set_trans(Tween.TRANS_SINE)
	key_photo_corner.rotation.x = -0.55   # köşe kıvrık kalır


var _vib: Tween

func _vibrate_phone(on: bool) -> void:
	if _vib and _vib.is_valid():
		_vib.kill()
	var base := Vector3(PHONE_POS.x, table_top + 0.005, PHONE_POS.z)
	phone.position = base
	if not on:
		return
	_vib = create_tween().set_loops()
	for i in 6:
		_vib.tween_property(phone, "position", base + Vector3(randf_range(-0.004, 0.004), 0, randf_range(-0.004, 0.004)), 0.04)
	_vib.tween_property(phone, "position", base, 0.04)
	_vib.tween_interval(0.7)


# ------------------------------------------------------------------
# Dünya kurulumu
# ------------------------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.8, 0.72)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.06
	we.environment = env
	add_child(we)

	# Pencereden giren öğleden sonra ışığı
	var sun := SpotLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 6.0
	sun.spot_range = 9.0
	sun.spot_angle = 50.0
	sun.spot_attenuation = 0.6
	sun.shadow_enabled = true
	sun.position = Vector3(3.6, 2.4, -0.4)
	add_child(sun)
	sun.look_at(Vector3(0.0, 0.0, -1.0))
	# Odayı yumuşak dolduran ışık
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.9, 0.78)
	fill.light_energy = 0.9
	fill.omni_range = 7.0
	fill.position = Vector3(0.3, 2.3, 0.3)
	add_child(fill)


func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_room() -> void:
	var w := 6.6
	var d := 5.6
	var h := 2.7
	var wall := _mat(Color(0.62, 0.6, 0.5))
	var wall2 := _mat(Color(0.55, 0.57, 0.5))
	# Zemin: tahta
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.42, 0.29, 0.18)
	floor_m.roughness = 0.55
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.width = 512
	nt.height = 64
	nt.seamless = true
	floor_m.albedo_texture = nt
	floor_m.uv1_scale = Vector3(1.0, 8.0, 1.0)
	_box(Vector3(w, 0.05, d), Vector3(0, -0.025, 0), floor_m)
	_box(Vector3(w, 0.05, d), Vector3(0, h + 0.025, 0), _mat(Color(0.82, 0.8, 0.76)))
	_box(Vector3(w, h, 0.1), Vector3(0, h / 2, -d / 2), wall)
	_box(Vector3(w, h, 0.1), Vector3(0, h / 2, d / 2), wall)
	_box(Vector3(0.1, h, d), Vector3(-w / 2, h / 2, 0), wall2)
	# Sağ duvar: pencereli
	var wx := w / 2
	_box(Vector3(0.1, h, 1.9), Vector3(wx, h / 2, -d / 2 + 0.95), wall2)
	_box(Vector3(0.1, h, 2.3), Vector3(wx, h / 2, d / 2 - 1.15), wall2)
	_box(Vector3(0.1, 0.9, 1.4), Vector3(wx, 0.45, -0.15), wall2)
	_box(Vector3(0.1, 0.5, 1.4), Vector3(wx, h - 0.25, -0.15), wall2)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.9, 0.95, 1.0)
	glass.emission_enabled = true
	glass.emission = Color(0.95, 0.9, 0.8)
	glass.emission_energy_multiplier = 2.2
	_box(Vector3(0.02, 1.3, 1.4), Vector3(wx + 0.06, 1.55, -0.15), glass)
	# Perde
	var curtain := _mat(Color(0.7, 0.62, 0.48))
	_box(Vector3(0.05, 1.7, 0.35), Vector3(wx - 0.08, 1.45, -1.0), curtain)
	_box(Vector3(0.05, 1.7, 0.35), Vector3(wx - 0.08, 1.45, 0.7), curtain)
	# Süpürgelik
	var trim := _mat(Color(0.9, 0.88, 0.82))
	_box(Vector3(w, 0.1, 0.02), Vector3(0, 0.05, -d / 2 + 0.06), trim)
	_box(Vector3(w, 0.1, 0.02), Vector3(0, 0.05, d / 2 - 0.06), trim)
	# Halı
	var rug := _mat(Color(0.45, 0.22, 0.18))
	_box(Vector3(2.8, 0.012, 2.0), Vector3(0, 0.006, -1.1), rug)
	_box(Vector3(2.6, 0.014, 1.8), Vector3(0, 0.007, -1.1), _mat(Color(0.55, 0.32, 0.24)))
	# Duvarda çerçeveler
	for f in [[Vector3(-0.7, 1.75, -d / 2 + 0.07), Vector2(0.5, 0.38)], [Vector3(0.1, 1.85, -d / 2 + 0.07), Vector2(0.35, 0.45)], [Vector3(0.8, 1.7, -d / 2 + 0.07), Vector2(0.42, 0.32)]]:
		_box(Vector3(f[1].x, f[1].y, 0.03), f[0], _mat(Color(0.15, 0.12, 0.1)))
		_box(Vector3(f[1].x - 0.06, f[1].y - 0.06, 0.01), f[0] + Vector3(0, 0, 0.016), _mat(Color(0.75, 0.7, 0.6)))
	# Ayaklı lamba
	var lamp := Node3D.new()
	lamp.position = Vector3(-1.75, 0, -2.3)
	add_child(lamp)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = 1.5
	pole.mesh = cyl
	pole.material_override = _mat(Color(0.2, 0.18, 0.16), 0.4)
	pole.position.y = 0.75
	lamp.add_child(pole)
	var shade := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.15
	cone.bottom_radius = 0.24
	cone.height = 0.28
	shade.mesh = cone
	var sm := _mat(Color(0.95, 0.88, 0.72))
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.8, 0.55)
	sm.emission_energy_multiplier = 0.8
	shade.material_override = sm
	shade.position.y = 1.55
	lamp.add_child(shade)
	var ll := OmniLight3D.new()
	ll.light_color = Color(1.0, 0.72, 0.45)
	ll.light_energy = 1.2
	ll.omni_range = 3.5
	ll.position.y = 1.45
	lamp.add_child(ll)
	# Saksı
	var pot := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.18
	pc.bottom_radius = 0.13
	pc.height = 0.32
	pot.mesh = pc
	pot.material_override = _mat(Color(0.55, 0.3, 0.2))
	pot.position = Vector3(2.75, 0.16, -2.35)
	add_child(pot)
	var leaves := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.38
	sp.height = 0.85
	leaves.mesh = sp
	leaves.material_override = _mat(Color(0.2, 0.36, 0.18))
	leaves.position = Vector3(2.75, 0.75, -2.35)
	add_child(leaves)


func _build_furniture() -> void:
	CutsceneActor.spawn_prop(self, M + "sofa.glb", 2.15, Vector3(0.0, 0, -2.25), 0.0)
	var table := CutsceneActor.spawn_prop(self, M + "coffee_table.glb", 1.15, TABLE_POS, PI / 2.0)
	table_top = (table.get_meta("size") as Vector3).y
	CutsceneActor.spawn_prop(self, M + "tv.glb", 1.55, TV_POS, PI)
	CutsceneActor.spawn_prop(self, M + "armchair.glb", 0.95, Vector3(2.15, 0, -0.55), -PI / 2.0 + 0.45)
	CutsceneActor.spawn_prop(self, M + "bookshelf.glb", 1.2, Vector3(-3.0, 0, -0.9), PI / 2.0)
	# TV ekranı (canlı yayın)
	tv_screen = TvScreen.new()
	add_child(tv_screen)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.1, 0.62)
	q.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = tv_screen.get_texture()
	q.material_override = sm
	q.position = TV_POS + Vector3(0.0, 1.0, -0.13)
	q.rotation.y = PI
	q.name = "TvQuad"
	add_child(q)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.55, 0.7, 1.0)
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	glow.position = TV_POS + Vector3(0, 1.0, -0.6)
	add_child(glow)


func _build_people() -> void:
	nora = CutsceneActor.create(self, C + "nora.glb", 1.68, NORA_POS, 0.0)
	nora.play("coffee mug", true, 0.0)
	var mug := MeshInstance3D.new()
	var mc := CylinderMesh.new()
	mc.top_radius = 0.042
	mc.bottom_radius = 0.038
	mc.height = 0.1
	mug.mesh = mc
	mug.material_override = _mat(Color(0.85, 0.82, 0.75), 0.3)
	nora.attach("mixamorig_RightHand", mug, Transform3D(Basis.IDENTITY, Vector3(0.03, 0.08, 0.04)))
	_mug = mug
	june = CutsceneActor.create(self, C + "june.glb", 1.52, JUNE_POS, PI)
	june.play("next to a low", true, 0.0)


func _build_table_items() -> void:
	var y := table_top + 0.004
	# Fotoğraflar: biri Caleb'in (anahtar), diğerleri aile kareleri
	var spots := [
		[KEY_PHOTO_POS, 0.06],
		[Vector3(-0.22, 0, -1.3), -0.25],
		[Vector3(-0.1, 0, -1.07), 0.3],
		[Vector3(-0.42, 0, -1.08), 0.12],
		[Vector3(0.25, 0, -1.05), -0.08],
	]
	for i in spots.size():
		var tex: Texture2D = _photo_textures[i % _photo_textures.size()] if not _photo_textures.is_empty() else null
		var ph := _make_photo(tex, i == 0)
		ph.position = Vector3(spots[i][0].x, y + i * 0.0008, spots[i][0].z)
		ph.rotation.y = spots[i][1]
		add_child(ph)
		photos.append(ph)
		if i == 0:
			key_photo = ph
	# Telefon
	phone = Node3D.new()
	phone.position = Vector3(PHONE_POS.x, y, PHONE_POS.z)
	phone.rotation.y = -0.35
	add_child(phone)
	_box(Vector3(0.075, 0.009, 0.155), Vector3(0, 0.0045, 0), _mat(Color(0.06, 0.06, 0.07), 0.25), phone)
	phone_screen = PhoneScreen.new()
	add_child(phone_screen)
	var scr := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.068, 0.145)
	scr.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = phone_screen.get_texture()
	scr.material_override = m
	scr.rotation.x = -PI / 2.0
	scr.position.y = 0.0095
	phone.add_child(scr)
	# Birkaç küçük eşya
	var cup := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.035
	cc.bottom_radius = 0.03
	cc.height = 0.1
	cup.mesh = cc
	cup.material_override = _mat(Color(0.8, 0.3, 0.2), 0.4)
	cup.position = Vector3(-0.45, y + 0.05, -1.4)
	add_child(cup)


## Fotoğraf kâğıdı. key: köşesi kıvrılabilen anahtar fotoğraf.
func _make_photo(tex: Texture2D, key: bool) -> Node3D:
	var root := Node3D.new()
	var w := 0.15
	var hgt := 0.1
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var paper := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, hgt)
	paper.mesh = q
	paper.material_override = m
	paper.rotation.x = -PI / 2.0
	root.add_child(paper)
	if key:
		# Sağ alt köşe ayrı bir üçgen gibi kalkabilsin
		var pivot := Node3D.new()
		pivot.position = Vector3(w * 0.5 - 0.025, 0.0005, hgt * 0.5 - 0.025)
		pivot.rotation.y = PI / 4.0
		root.add_child(pivot)
		var flap := MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = Vector2(0.036, 0.018)
		flap.mesh = fq
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.93, 0.92, 0.88)
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		flap.material_override = fm
		flap.rotation.x = -PI / 2.0
		flap.position = Vector3(0, 0, 0.009)
		var inner := Node3D.new()
		pivot.add_child(inner)
		inner.add_child(flap)
		key_photo_corner = inner
		inner.rotation.x = -0.55
	return root


# ------------------------------------------------------------------
# Fotoğrafları gerçek sahneden çek (ayrı bir "stüdyo"da, katman 2)
# ------------------------------------------------------------------

func _render_photos() -> void:
	# Ayrı bir dünya: kendi gökyüzü, güneşi ve sahnesi olan küçük bir stüdyo.
	var vp := SubViewport.new()
	vp.size = Vector2i(600, 400)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var studio := Node3D.new()
	vp.add_child(studio)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.68, 0.76, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.76, 0.84)
	env.fog_density = 0.01
	we.environment = env
	studio.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-38, 28, 0)
	studio.add_child(sun)
	var pcam := Camera3D.new()
	pcam.fov = 40.0
	studio.add_child(pcam)

	# Garaj: beton eşik, açık kapı, içeride raflar
	var conc := _mat(Color(0.6, 0.59, 0.55))
	var inside := _mat(Color(0.3, 0.29, 0.27))
	var siding := _mat(Color(0.82, 0.8, 0.74))
	_box(Vector3(14, 0.1, 14), Vector3(0, -0.05, 3.0), _mat(Color(0.36, 0.42, 0.28)), studio)
	_box(Vector3(3.4, 0.03, 4.0), Vector3(0, 0.0, 2.2), conc, studio)
	_box(Vector3(3.2, 0.14, 0.5), Vector3(0, 0.07, 0.05), conc, studio)
	_box(Vector3(3.0, 2.4, 0.05), Vector3(0, 1.2, -2.6), inside, studio)
	_box(Vector3(0.05, 2.4, 2.6), Vector3(-1.5, 1.2, -1.3), inside, studio)
	_box(Vector3(0.05, 2.4, 2.6), Vector3(1.5, 1.2, -1.3), inside, studio)
	_box(Vector3(3.0, 0.05, 2.6), Vector3(0, 2.4, -1.3), inside, studio)
	_box(Vector3(0.7, 2.9, 0.3), Vector3(-1.85, 1.45, -0.15), siding, studio)
	_box(Vector3(0.7, 2.9, 0.3), Vector3(1.85, 1.45, -0.15), siding, studio)
	_box(Vector3(4.4, 0.55, 0.3), Vector3(0, 2.62, -0.15), siding, studio)
	_box(Vector3(1.2, 1.6, 0.4), Vector3(-0.9, 0.8, -2.3), _mat(Color(0.35, 0.25, 0.18)), studio)
	_box(Vector3(0.5, 0.4, 0.4), Vector3(0.9, 0.2, -2.2), _mat(Color(0.6, 0.15, 0.12)), studio)
	var caleb := CutsceneActor.create(studio, C + "player.glb", 1.8, Vector3(0.05, 0.14, 0.1), 0.0)
	caleb.play("tired man", true, 0.0)
	var boot := CutsceneActor.spawn_prop(studio, M + "boot.glb", 0.3, Vector3(0.55, 0.14, 0.75), 2.4)
	boot.rotation.z = PI   # ters çevrilmiş bot
	boot.position.y = 0.45
	# Evin önü (ikinci kare)
	var house := CutsceneActor.spawn_prop(studio, "res://assets/models/props/house.glb", 9.0, Vector3(14, 0, -6), 0.3)
	for i in 4:
		CutsceneActor.spawn_prop(studio, "res://assets/models/props/pine_tree.glb", 4.0, Vector3(8 + i * 3.2, 0, -12 - (i % 2) * 2), i * 1.3)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 0.6
	lamp.omni_range = 4.0
	lamp.position = Vector3(0, 2.0, -1.2)
	studio.add_child(lamp)

	var shots: Array = [
		[Vector3(0.35, 1.0, 2.7), Vector3(0.05, 0.7, 0.0), 30.0],
		[Vector3(-1.2, 1.5, 4.6), Vector3(0.0, 0.9, -0.4), 40.0],
		[Vector3(10.5, 1.6, 6.0), Vector3(14.0, 2.4, -6.0), 50.0],
	]
	_photo_textures.clear()
	for s in shots:
		pcam.position = s[0]
		pcam.look_at(s[1])
		pcam.fov = s[2]
		for i in 8:
			await get_tree().process_frame
		var img := vp.get_texture().get_image()
		_photo_textures.append(ImageTexture.create_from_image(_print_look(img)))
	vp.queue_free()


func _set_layer(n: Node, layer: int) -> void:
	for c in n.find_children("*", "VisualInstance3D", true, false):
		(c as VisualInstance3D).layers = layer
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = layer


## Basılı fotoğraf görünümü: sıcak ton, hafif soluk, beyaz kenar.
func _print_look(img: Image) -> Image:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var border := 14
	for y in h:
		for x in w:
			if x < border or y < border or x >= w - border or y >= h - border:
				img.set_pixel(x, y, Color(0.94, 0.93, 0.89))
				continue
			var c := img.get_pixel(x, y)
			c = c.lerp(Color(c.r * 1.05 + 0.04, c.g * 1.0 + 0.03, c.b * 0.88, 1.0), 0.8)
			var dx := (float(x) / w - 0.5) * 2.0
			var dy := (float(y) / h - 0.5) * 2.0
			var v := 1.0 - 0.25 * (dx * dx + dy * dy)
			img.set_pixel(x, y, Color(c.r * v, c.g * v, c.b * v, 1.0))
	img.generate_mipmaps()
	return img
