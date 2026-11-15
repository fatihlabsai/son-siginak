extends Node3D
## Ana menü: arka planda gece, kamp ateşi başında oturan hayatta kalan ve
## sisin içinde yürüyen zombiler; solda menü.

const GAME_SCENE := "res://scenes/main.tscn"
const PLAYER_GLB := preload("res://assets/models/characters/player.glb")
const ZOMBIE_GLBS := [
	preload("res://assets/models/zombies/zombie_worker.glb"),
	preload("res://assets/models/zombies/zombie_flannel.glb"),
	preload("res://assets/models/zombies/zombie_woman.glb"),
]
const TIPS := [
	"İpucu: Silah sesi yakındaki bütün zombileri üzerine çeker.",
	"İpucu: Koşmak gürültü yapar. Nişan alarak yürümek neredeyse sessizdir.",
	"İpucu: Gece fener açarsan yolunu görürsün ama onlar da seni görür.",
	"İpucu: Her gece 22:00'de bir sürü gelir. Hazırlıklı ol.",
	"İpucu: Açlık ya da susuzluk sıfıra inerse yavaş yavaş ölürsün.",
	"İpucu: Zombinin saldırısı bir an gecikir. Geri çekilerek kaçabilirsin.",
]

var _env: Environment
var _moon: DirectionalLight3D
var _cam: Camera3D
var _cam_base := Vector3(3.2, 1.9, 7.2)
var _cam_target := Vector3(-3.0, 1.1, -2.0)
var _fire_light: OmniLight3D
var _walkers: Array = []
var _t := 0.0

var _ui: Control
var _main_box: VBoxContainer
var _diff_box: VBoxContainer
var _controls_box: Control
var _settings: SettingsMenu
var _tip: Label
var _tip_index := 0
var _fade: ColorRect
var _busy := false


func _ready() -> void:
	get_tree().paused = false
	_build_world()
	_build_ui()
	Settings.changed.connect(_apply_quality)
	_apply_quality()
	Audio.stop_world_sounds()
	Audio.set_ambience("heartbeat", -60.0)
	Audio.set_ambience("wind", -20.0)
	Audio.set_ambience("crickets", -18.0)
	Audio.play_music("theme", 3.0, -8.0)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.4)


func _process(delta: float) -> void:
	_t += delta
	_cam.position = _cam_base + Vector3(sin(_t * 0.13) * 0.5, sin(_t * 0.21) * 0.12, cos(_t * 0.11) * 0.3)
	_cam.look_at(_cam_target)
	_fire_light.light_energy = 3.6 + sin(_t * 11.0) * 0.35 + sin(_t * 6.7) * 0.3 + randf() * 0.35
	for w in _walkers:
		var n: Node3D = w.node
		n.position.x += w.dir * w.speed * delta
		if absf(n.position.x) > 22.0:
			n.position.x = -22.0 * w.dir


func _apply_quality() -> void:
	Settings.apply_to_world(_moon, _env)
	_env.volumetric_fog_enabled = Settings.quality >= 2


# ------------------------------------------------------------------
# 3D arka plan
# ------------------------------------------------------------------

func _build_world() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.025, 0.035)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.3, 0.35, 0.5)
	_env.ambient_light_energy = 0.25
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.06, 0.07, 0.1)
	_env.fog_density = 0.035
	_env.volumetric_fog_density = 0.02
	_env.volumetric_fog_albedo = Color(0.55, 0.6, 0.75)
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 0.8
	_env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.65, 0.95)
	_moon.light_energy = 0.45
	_moon.shadow_enabled = true
	_moon.rotation_degrees = Vector3(-38, -140, 0)
	add_child(_moon)

	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.position = _cam_base
	add_child(_cam)
	_cam.look_at(_cam_target)
	_cam.current = true

	var ground := PlaneMesh.new()
	ground.size = Vector2(140, 140)
	var gmi := _mesh(ground, Vector3.ZERO, Color(0.12, 0.13, 0.1))
	gmi.material_override = GroundBuilder.ground_material(Vector2.ZERO, 6.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var grass_count: int = [0, 1500, 3500][clampi(Settings.quality, 0, 2)]
	GroundBuilder.add_grass(self, grass_count, Rect2(-22, -30, 44, 40), func(p: Vector2) -> bool: return p.length() > 4.5 and p.y < 1.5, rng)

	_build_campfire()
	_build_props()

	# Ateşin başında oturan hayatta kalan
	var survivor := PLAYER_GLB.instantiate() as Node3D
	survivor.scale = Vector3.ONE * 1.8
	survivor.position = Vector3(-1.7, 0, 1.0)
	survivor.rotation.y = atan2(-survivor.position.x, -survivor.position.z)
	add_child(survivor)
	var anim := ModelAnimator.new()
	anim.setup(survivor)
	anim.play("idle")

	# Sisin içinde dolaşan zombiler
	var lanes := [-5.5, -7.5, -9.0, -10.5, -14.5]
	for i in lanes.size():
		var z := (ZOMBIE_GLBS[i % ZOMBIE_GLBS.size()] as PackedScene).instantiate() as Node3D
		var dir := 1.0 if i % 2 == 0 else -1.0
		z.scale = Vector3.ONE * 1.8 * randf_range(0.94, 1.06)
		z.position = Vector3(randf_range(-18, 18), 0, lanes[i])
		z.rotation.y = PI / 2.0 if dir > 0 else -PI / 2.0
		add_child(z)
		var za := ModelAnimator.new()
		za.setup(z)
		var speed := randf_range(0.5, 0.8)
		za.base_speed = randf_range(0.85, 1.1)
		za.play("walk")
		za.set_speed(speed / 1.4)
		_walkers.append({"node": z, "dir": dir, "speed": speed, "anim": za})

	# Çitin dibinde bekleyen biri
	var lurker := (ZOMBIE_GLBS[0] as PackedScene).instantiate() as Node3D
	lurker.scale = Vector3.ONE * 1.8
	lurker.position = Vector3(6.5, 0, -6.4)
	lurker.rotation.y = atan2(_cam_base.x - lurker.position.x, _cam_base.z - lurker.position.z)
	add_child(lurker)
	var la := ModelAnimator.new()
	la.setup(lurker)
	la.base_speed = 0.7
	la.play("idle")


func _build_campfire() -> void:
	var has_model := PropLibrary.spawn(self, "campfire", Vector3.ZERO, 1.5, 0.0, "none") != null
	if not has_model:
		var stones := CylinderMesh.new()
		stones.top_radius = 0.65
		stones.bottom_radius = 0.75
		stones.height = 0.2
		_mesh(stones, Vector3(0, 0.1, 0), Color(0.25, 0.25, 0.25))
		for i in 3:
			var wood := BoxMesh.new()
			wood.size = Vector3(0.14, 0.14, 1.0)
			var mi := _mesh(wood, Vector3(0, 0.25, 0), Color(0.22, 0.14, 0.08))
			mi.rotation = Vector3(0.35, i * TAU / 3.0, 0)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.22 if has_model else 0.32
	cone.height = 0.6 if has_model else 0.75
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.55, 0.15)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.45, 0.1)
	flame_mat.emission_energy_multiplier = 3.0
	cone.material = flame_mat
	if not has_model:
		var flame := MeshInstance3D.new()
		flame.mesh = cone
		flame.position.y = 0.55
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flame)

	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.55, 0.22)
	_fire_light.light_energy = 3.6
	_fire_light.omni_range = 12.0
	_fire_light.shadow_enabled = true
	_fire_light.position = Vector3(0, 0.9, 0)
	add_child(_fire_light)
	var fire_node := Node3D.new()
	add_child(fire_node)
	Audio.attach_loop("fire", fire_node, Vector3(0, 0.4, 0), 0.0, 6.0)

	# Kıvılcımlar
	var spark := SphereMesh.new()
	spark.radius = 0.025
	spark.height = 0.05
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.6, 0.2)
	spark.material = spark_mat
	var embers := CPUParticles3D.new()
	embers.mesh = spark
	embers.amount = 40
	embers.lifetime = 2.6
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.3
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.initial_velocity_min = 0.6
	embers.initial_velocity_max = 1.5
	embers.gravity = Vector3(0.15, 0.1, 0)
	embers.scale_amount_min = 0.5
	embers.scale_amount_max = 1.3
	embers.position = Vector3(0, 0.6, 0)
	add_child(embers)


func _build_props() -> void:
	if PropLibrary.has("tent"):
		_build_model_props()
		return
	var tent := PrismMesh.new()
	tent.size = Vector3(2.8, 1.9, 3.2)
	var t := _mesh(tent, Vector3(-4.8, 0.95, -2.6), Color(0.22, 0.27, 0.18))
	t.rotation.y = 0.5
	for p in [Vector3(3.6, 0.3, -3.2), Vector3(4.2, 0.3, -2.6), Vector3(3.9, 0.9, -2.9)]:
		var crate := BoxMesh.new()
		crate.size = Vector3(0.6, 0.6, 0.6)
		var c := _mesh(crate, p, Color(0.36, 0.27, 0.16))
		c.rotation.y = randf_range(-0.4, 0.4)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.33
	barrel.bottom_radius = 0.33
	barrel.height = 0.95
	_mesh(barrel, Vector3(-3.0, 0.48, 1.8), Color(0.35, 0.18, 0.1))

	# Arkadaki tahta çit (aralıklı, kırık)
	var x := -14.0
	while x < 14.0:
		if randf() > 0.2:
			var plank := BoxMesh.new()
			plank.size = Vector3(2.2, 0.9 + randf() * 0.4, 0.12)
			var pl := _mesh(plank, Vector3(x, 0.55, -12.5), Color(0.28, 0.2, 0.13))
			pl.rotation = Vector3(randf_range(-0.08, 0.08), randf_range(-0.1, 0.1), randf_range(-0.06, 0.06))
		x += 2.3

	# Terk edilmiş araba
	var car := BoxMesh.new()
	car.size = Vector3(2.0, 1.0, 4.4)
	var cb := _mesh(car, Vector3(8.5, 0.6, -10.0), Color(0.32, 0.16, 0.1))
	cb.rotation.y = 0.9
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.8, 0.65, 2.2)
	var cm := _mesh(cabin, Vector3(0, 0.82, -0.2), Color(0.2, 0.12, 0.08))
	cm.reparent(cb, false)

	# Kuru ağaç siluetleri
	for i in 9:
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.08
		trunk.bottom_radius = 0.25
		trunk.height = randf_range(5.0, 8.0)
		_mesh(trunk, Vector3(randf_range(-20, 20), trunk.height / 2.0, randf_range(-26, -19)), Color(0.08, 0.07, 0.06))


## Tripo modelleriyle arka plan dekoru.
func _build_model_props() -> void:
	PropLibrary.spawn(self, "tent", Vector3(-4.8, 0, -2.6), 3.6, 0.5 + PI, "none")
	PropLibrary.spawn(self, "crate", Vector3(3.6, 0, -3.2), 0.85, 0.2, "none")
	PropLibrary.spawn(self, "crate", Vector3(4.3, 0, -2.6), 0.85, -0.3, "none")
	PropLibrary.spawn(self, "crate", Vector3(3.9, 0.6, -3.0), 0.85, 0.5, "none")
	PropLibrary.spawn(self, "barrel", Vector3(-3.0, 0, 1.8), 0.95, 0.0, "none")
	PropLibrary.spawn(self, "barrel", Vector3(-3.6, 0, 2.5), 0.95, 1.0, "none")
	var x := -14.0
	while x < 14.0:
		if randf() > 0.2:
			PropLibrary.spawn(self, "barricade", Vector3(x, 0, -12.5), 3.4, PI / 2.0 + randf_range(-0.1, 0.1), "none")
		x += 3.5
	PropLibrary.spawn(self, "pickup_truck", Vector3(8.5, 0, -10.0), 5.3, 0.9, "none")
	PropLibrary.spawn(self, "sedan_car", Vector3(-11.0, 0, -9.0), 4.6, -0.6, "none")
	PropLibrary.spawn(self, "farmhouse", Vector3(-6.0, 0, -24.0), 13.0, 0.3, "none")
	for i in 10:
		var dead := randf() < 0.6
		PropLibrary.spawn(self, "dead_tree" if dead else "pine_tree",
			Vector3(randf_range(-22, 22), 0, randf_range(-28, -17)),
			randf_range(6.0, 9.0) if dead else randf_range(8.0, 12.0), randf() * TAU, "none")


func _mesh(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


# ------------------------------------------------------------------
# Arayüz
# ------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UITheme.get_theme()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)

	# Kenar kararması + sol tarafta okunabilirlik için gölge
	var vig := TextureRect.new()
	vig.texture = _gradient_tex([0.0, 0.55, 1.0], [Color(0, 0, 0, 0), Color(0, 0, 0, 0.05), Color(0, 0, 0, 0.85)], true)
	_full(vig)
	_ui.add_child(vig)
	var shade := TextureRect.new()
	shade.texture = _gradient_tex([0.0, 1.0], [Color(0, 0, 0, 0.88), Color(0, 0, 0, 0)], false)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_right = 0.6
	shade.anchor_bottom = 1.0
	_ui.add_child(shade)

	# Başlık
	var title_box := VBoxContainer.new()
	title_box.position = Vector2(90, 80)
	title_box.add_theme_constant_override("separation", 6)
	_ui.add_child(title_box)
	var title := UITheme.label("SON SIĞINAK", 104, UITheme.TEXT, UITheme.title_font())
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title_box.add_child(title)
	title_box.add_child(UITheme.accent_line(140, 5))
	title_box.add_child(UITheme.label("KIYAMET SONRASI HAYATTA KALMA", 16, UITheme.TEXT_DIM, UITheme.spaced_font()))

	# Menü kutuları
	_main_box = _menu_column()
	if Game.has_save():
		_add_btn(_main_box, "DEVAM ET", _continue_game)
		var sub := UITheme.label(Game.save_summary(), 15, UITheme.TEXT_DIM)
		var sm := MarginContainer.new()
		sm.add_theme_constant_override("margin_left", 22)
		sm.add_theme_constant_override("margin_bottom", 6)
		sm.add_child(sub)
		_main_box.add_child(sm)
	_add_btn(_main_box, "YENİ OYUN", _show.bind("diff"))
	_add_btn(_main_box, "AYARLAR", _open_settings)
	_add_btn(_main_box, "KONTROLLER", _show.bind("controls"))
	_add_btn(_main_box, "ÇIKIŞ", _quit)

	_diff_box = _menu_column()
	_diff_box.add_child(UITheme.label("ZORLUK SEÇ", 16, UITheme.ACCENT.lightened(0.25), UITheme.spaced_font()))
	if Game.has_save():
		_diff_box.add_child(UITheme.label("Dikkat: yeni oyun mevcut kaydın üzerine yazılır.", 14, Color(0.95, 0.6, 0.45)))
	var descs := [
		"Daha az zombi, bol erzak, hafif ısırıklar.",
		"Dengeli bir hayatta kalma deneyimi.",
		"Büyük sürüler, kıt erzak, ölümcül ısırıklar.",
	]
	for i in 3:
		var b := _add_btn(_diff_box, Settings.DIFFICULTY_NAMES[i].to_upper(), _start_game.bind(i))
		b.tooltip_text = descs[i]
		var d := UITheme.label(descs[i], 15, UITheme.TEXT_DIM)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 22)
		m.add_theme_constant_override("margin_bottom", 6)
		m.add_child(d)
		_diff_box.add_child(m)
	_add_btn(_diff_box, "GERİ", _show.bind("main"), 20)

	_controls_box = _build_controls()

	# Alt bilgiler
	var ver := UITheme.label("v0.1  ·  Prototip", 14, Color(1, 1, 1, 0.35))
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 90
	ver.offset_top = -48
	_ui.add_child(ver)
	_tip = UITheme.label(TIPS[0], 16, UITheme.TEXT_DIM)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tip.anchor_left = 1.0
	_tip.anchor_right = 1.0
	_tip.anchor_top = 1.0
	_tip.anchor_bottom = 1.0
	_tip.offset_left = -760
	_tip.offset_right = -40
	_tip.offset_top = -50
	_tip.offset_bottom = -24
	_ui.add_child(_tip)
	var timer := Timer.new()
	timer.wait_time = 7.0
	timer.autostart = true
	timer.timeout.connect(_next_tip)
	add_child(timer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_full(_fade)
	_ui.add_child(_fade)

	_show("main")


func _menu_column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = 74
	box.offset_top = -40
	box.offset_right = 470
	_ui.add_child(box)
	return box


func _add_btn(parent: Control, text: String, cb: Callable, size := 30) -> Button:
	var b := UITheme.menu_button(text, size)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_controls() -> Control:
	var box := _menu_column()
	box.offset_top = -190
	box.add_child(UITheme.label("KONTROLLER", 16, UITheme.ACCENT.lightened(0.25), UITheme.spaced_font()))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 8)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 14)
	m.add_child(grid)
	box.add_child(m)
	var rows := [
		["W A S D", "Yürü"],
		["Shift", "Koş"],
		["Sol tık / Space", "Yakın dövüş"],
		["Sağ tık (basılı)", "Nişan al"],
		["Nişan + Sol tık", "Ateş et"],
		["Q", "Silah değiştir"],
		["E", "Eşya al  /  basılı tut: ara"],
		["Tab", "Envanter"],
		["B", "İnşa: barikat / tuzak"],
		["F", "Fener"],
		["1  /  2  /  3  /  4", "Ye  /  İç  /  İlk yardım  /  Bandaj"],
		["C", "Üretim (bandaj, molotof, onarım...)"],
		["G  /  Z", "Fırlat  /  fırlatılacağı değiştir"],
		["Fare tekerleği", "Yakınlaş / uzaklaş"],
		["Esc", "Duraklat"],
	]
	for r in rows:
		grid.add_child(UITheme.label(r[0], 18, Color.WHITE))
		grid.add_child(UITheme.label(r[1], 18, UITheme.TEXT_DIM))
	_add_btn(box, "GERİ", _show.bind("main"), 20)
	return box


func _show(which: String) -> void:
	var boxes := {"main": _main_box, "diff": _diff_box, "controls": _controls_box}
	for key in boxes:
		var box: Control = boxes[key]
		box.visible = key == which
	var target: Control = boxes[which]
	for c in target.get_children():
		if c is Button:
			(c as Button).call_deferred("grab_focus")
			break


func _unhandled_input(event: InputEvent) -> void:
	if (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")) and not _main_box.visible and not is_instance_valid(_settings):
		_show("main")


func _open_settings() -> void:
	for box in [_main_box, _diff_box, _controls_box]:
		(box as Control).visible = false
	_settings = SettingsMenu.new()
	_ui.add_child(_settings)
	_ui.move_child(_fade, -1)
	_settings.closed.connect(_show.bind("main"))


func _start_game(difficulty: int) -> void:
	if _busy:
		return
	_busy = true
	Settings.difficulty = difficulty
	Settings.save_settings()
	Game.reset_run()
	Game.delete_save()
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.7)
	await tw.finished
	get_tree().change_scene_to_file(GAME_SCENE)


func _continue_game() -> void:
	if _busy:
		return
	if not Game.prepare_continue():
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.7)
	await tw.finished
	get_tree().change_scene_to_file(GAME_SCENE)


func _quit() -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	await tw.finished
	get_tree().quit()


func _next_tip() -> void:
	_tip_index = (_tip_index + 1) % TIPS.size()
	var tw := create_tween()
	tw.tween_property(_tip, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): _tip.text = TIPS[_tip_index])
	tw.tween_property(_tip, "modulate:a", 1.0, 0.4)


func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if c is TextureRect:
		(c as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		(c as TextureRect).stretch_mode = TextureRect.STRETCH_SCALE


func _gradient_tex(offsets: Array, colors: Array, radial: bool) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	if radial:
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 1.0)
	else:
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(1, 0)
	return t
