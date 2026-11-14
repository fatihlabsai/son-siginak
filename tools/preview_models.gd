extends Node3D
## Geliştirme aracı: verilen modelleri yan yana dizip önden ve yukarıdan gösterir.
const KEYS := ["knife", "bat", "axe", "pistol", "shotgun"]

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	for i in KEYS.size():
		var m := PropLibrary.instance(KEYS[i], 1.0)
		if m:
			m.position = Vector3(i * 1.3 - 2.6, 0, 0)
			add_child(m)
	# Eksen göstergesi: kırmızı X, yeşil Y, mavi Z
	for ax in [[Vector3.RIGHT, Color.RED], [Vector3.UP, Color.GREEN], [Vector3.BACK, Color.BLUE]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.04 + ax[0].abs() * 0.6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ax[1]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.material = mat
		mi.mesh = bm
		mi.position = Vector3(-3.6, 0, 0) + ax[0] * 0.3
		add_child(mi)
	var cam := Camera3D.new()
	cam.position = Vector3(-0.3, 2.2, 4.2)
	add_child(cam)
	cam.look_at(Vector3(-0.3, 0.4, 0))
	cam.current = true
