class_name ShelterIntro
extends Node3D
## "Altı gün sonra" — belediye bakım sahası, fırtına sığınağı, sabah.
## Caleb duvara yaslanmış uyanır, ayağı acır, su şişesinde son birkaç damla kalmış.
## Dışarıda bir sac levha iki kez çarpar. Sonra izometrik kamera sığınağın içini açar
## ve kontrol oyuncuya geçer: "Çantanı kontrol et".

const A := "res://assets/audio/intro/"

var ui: CutsceneUI
var cam: Camera3D
var player: Player
var level: Level
var _fill: OmniLight3D
var _players: Array[AudioStreamPlayer] = []
var _skipped := false
var _done := false
var _amb: AudioStreamPlayer


func _ready() -> void:
	Game.cutscene_active = true
	Game.ui_open = true
	Game.ambient_scale = 0.3
	player = Game.player
	level = Game.level
	_set_hud(false)
	ui = CutsceneUI.new()
	add_child(ui)
	ui.bars(true, 0.01)
	ui.set_black(1.0)
	ui.skip_requested.connect(_skip)
	player.scripted = true
	_anim_player().stop()
	_play_player("tired man", true, 0.0)
	cam = Camera3D.new()
	cam.near = 0.05
	add_child(cam)
	cam.make_current()
	_fill = OmniLight3D.new()
	_fill.light_color = Color(0.62, 0.68, 0.8)
	_fill.light_energy = 1.1
	_fill.omni_range = 5.0
	add_child(_fill)
	_fill.global_position = level.shelter_center + Vector3(-0.6, 2.1, 0.6)
	# Oturuşta sırtı duvara değsin: model biraz geriye
	_model_root().position.z = -0.38
	_run()


func _run() -> void:
	var c := level.shelter_center
	var caleb := player.global_position
	_amb = _sound("amb_shelter_wind", -12.0, true)
	if await _wait(0.6): return
	ui.fade_to(0.0, 3.0)

	# A — Geniş: karanlık sığınak, kapının altından ince ışık, duvara yaslanmış Caleb
	_shot(c + Vector3(-0.2, 2.0, 1.8), c + Vector3(0.3, 0.3, -0.6), 76.0, 6.5, c + Vector3(-0.35, 1.9, 1.65), c + Vector3(0.1, 0.3, -0.6))
	if await _wait(6.0): return

	# B — Caleb doğrulur, ayağına basınca yüzü buruşur
	_shot(caleb + Vector3(1.55, 1.0, 1.0), caleb + Vector3(0.1, 0.6, 0.0), 45.0, 5.0, caleb + Vector3(1.45, 1.35, 0.9), caleb + Vector3(0.15, 1.1, 0.0))
	if await _wait(0.4): return
	var up_len := _play_player("slowly gets up", false, 0.4)
	create_tween().tween_property(_model_root(), "position:z", 0.0, 2.5).set_delay(0.8)
	_sfx("sfx_stand_up", -6.0)
	if await _wait(1.1): return
	_sfx("caleb_4", -2.0)
	if await _wait(maxf(up_len - 1.5, 2.5)): return
	_play_player("idle", true, 0.5)

	# C — Su şişesi: son birkaç damla
	var bottle := level.shelter_node().get_node_or_null("WaterBottle") as Node3D
	if bottle:
		var bp := bottle.global_position
		_shot(bp + Vector3(0.5, 0.28, 0.42), bp + Vector3(0, 0.05, 0), 38.0, 3.6, bp + Vector3(0.45, 0.75, 0.5), bp + Vector3(0, 0.62, 0))
		var tw := create_tween()
		tw.tween_property(bottle, "global_position", bp + Vector3(0.05, 0.62, 0.0), 1.0).set_trans(Tween.TRANS_SINE)
		tw.tween_property(bottle, "rotation:z", 2.1, 0.8).set_trans(Tween.TRANS_SINE)
		_sfx("sfx_bottle", -6.0)
		await get_tree().create_timer(1.6).timeout
		if not _skipped:
			_drops(bottle)
		if await _wait(2.2): return
		var tw2 := create_tween()
		tw2.tween_property(bottle, "rotation:z", 0.0, 0.5)
		tw2.tween_property(bottle, "global_position", bp, 0.5)

	# D — Dışarıda sac levha iki kez çarpar; Caleb kapıya bakar ve dinler
	_shot(caleb + Vector3(-0.15, 1.75, 1.15), c + Vector3(2.5, 1.0, 0.6), 50.0, 5.5, caleb + Vector3(-0.1, 1.7, 1.0), c + Vector3(2.5, 0.9, 0.6))
	if await _wait(0.4): return
	_sfx("sfx_metal_bang", -3.0)
	if await _wait(4.6): return

	# E — İzometrik kamera sığınağın içini açar, kontrol oyuncuya geçer
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var rig_cam := get_tree().current_scene.get_node_or_null("CameraRig/Camera3D") as Camera3D
	if rig_cam:
		rig_cam.make_current()
	var rig := get_tree().current_scene.get_node_or_null("CameraRig")
	if rig:
		rig.set("zoom", 10.5)
		rig.set("_zoom_target", 10.5)
		get_tree().create_timer(5.0).timeout.connect(func(): if is_instance_valid(rig): rig.set("_zoom_target", Settings.camera_zoom))
	_model_root().position.z = 0.0
	player.scripted = false
	Game.cutscene_active = false
	Game.ui_open = false
	_play_player("idle", true, 0.3)
	ui.clear_subtitle()
	ui.bars(false, 1.2)
	ui.fade_to(0.0, 0.6)
	var tw := create_tween()
	tw.tween_property(Game, "ambient_scale", 1.0, 2.5)
	if is_instance_valid(_fill):
		tw.parallel().tween_property(_fill, "light_energy", 0.0, 2.0)
	_set_hud(true)
	if is_instance_valid(_amb):
		create_tween().tween_property(_amb, "volume_db", -40.0, 6.0)
	Game.play_shelter_intro = false
	await get_tree().create_timer(6.5).timeout
	queue_free()


func _skip() -> void:
	if _skipped or _done:
		return
	_skipped = true
	for p in _players:
		if is_instance_valid(p) and p != _amb:
			p.stop()
	await ui.fade_to(1.0, 0.35).finished
	var bottle := level.shelter_node().get_node_or_null("WaterBottle") as Node3D
	if bottle:
		bottle.rotation = Vector3.ZERO
	_finish()


func _wait(t: float) -> bool:
	if _skipped:
		return true
	await get_tree().create_timer(t).timeout
	return _skipped


# ------------------------------------------------------------------

func _model_root() -> Node3D:
	var ap := _anim_player()
	var n := ap.get_parent()
	return n as Node3D if n is Node3D else Node3D.new()


func _anim_player() -> AnimationPlayer:
	var aps := player.find_children("*", "AnimationPlayer", true, false)
	return aps[0] if not aps.is_empty() else AnimationPlayer.new()


func _play_player(keyword: String, loop: bool, blend: float) -> float:
	var ap := _anim_player()
	var kw := keyword.to_lower()
	for n in ap.get_animation_list():
		if String(n).to_lower().contains(kw):
			var a := ap.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
			ap.speed_scale = 1.0
			ap.play(n, blend)
			return a.length
	return 0.0


func _set_hud(v: bool) -> void:
	var hud := get_tree().current_scene.get_node_or_null("HUD") as CanvasLayer
	if hud:
		hud.visible = v


func _shot(from: Vector3, look: Vector3, fov: float, dur: float, to := Vector3.INF, look_to := Vector3.INF) -> void:
	if cam.has_meta("tween"):
		var t0: Tween = cam.get_meta("tween")
		if t0 and t0.is_valid():
			t0.kill()
	cam.fov = fov
	cam.global_position = from
	cam.look_at(look)
	if to == Vector3.INF:
		return
	if look_to == Vector3.INF:
		look_to = look
	var tw := create_tween()
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
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.play()
	_players.append(p)
	return p


func _sfx(name: String, db: float) -> void:
	var p := _sound(name, db)
	p.finished.connect(p.queue_free)


## Şişeden düşen birkaç damla
func _drops(bottle: Node3D) -> void:
	var d := CPUParticles3D.new()
	d.amount = 5
	d.lifetime = 0.6
	d.one_shot = true
	d.explosiveness = 0.0
	d.direction = Vector3.DOWN
	d.spread = 4.0
	d.gravity = Vector3(0, -9.8, 0)
	d.initial_velocity_min = 0.1
	d.initial_velocity_max = 0.3
	var m := SphereMesh.new()
	m.radius = 0.006
	m.height = 0.014
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.9, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	m.material = mat
	d.mesh = m
	add_child(d)
	d.global_position = bottle.global_position + bottle.global_transform.basis.y * 0.13
	d.emitting = true
	get_tree().create_timer(2.0).timeout.connect(d.queue_free)
