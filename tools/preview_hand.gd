extends Node3D
## Geliştirme aracı: oyuncu modelinin sağ el kemiğinin eksenlerini ve tutulan silahı gösterir.
## Kırmızı = kemiğin X, yeşil = Y, mavi = Z ekseni.

var weapon_id := "bat"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		weapon_id = args[0]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 20, 0)
	add_child(sun)

	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	await get_tree().process_frame
	(player as Player).inv.weapons.clear()
	(player as Player).inv.add(weapon_id)
	(player as Player).inv.equip(0)
	var anim: ModelAnimator = player.get("_animator")
	var pose := "idle"
	if args.size() > 1:
		pose = args[1]
	anim.play(pose)
	if args.size() > 2 and anim.anim_player:
		anim.anim_player.seek(float(args[2]), true)
		anim.anim_player.pause()

	var hand: Node3D = player.get("_hand")
	if hand:
		for ax in [[Vector3.RIGHT, Color.RED], [Vector3.UP, Color.GREEN], [Vector3.BACK, Color.BLUE]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = (Vector3.ONE * 0.01 + ax[0].abs() * 0.15) / 1.8
			var mat := StandardMaterial3D.new()
			mat.albedo_color = ax[1]
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true
			bm.material = mat
			mi.mesh = bm
			mi.position = ax[0] * 0.075 / 1.8
			hand.add_child(mi)

	var cam := Camera3D.new()
	cam.position = Vector3(-1.2, 1.4, 1.8)
	add_child(cam)
	cam.look_at(Vector3(-0.1, 0.95, 0))
	cam.fov = 40
	cam.current = true
