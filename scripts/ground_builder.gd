class_name GroundBuilder
extends RefCounted
## Zemin, asfalt ve çim öbekleri. Doku dosyası yok: hepsi gürültü (noise) dokularıyla
## shader içinde üretiliyor. Gerçek doku kullanmak istersen shaders/ altındaki
## ground/road shader'larında noise yerine kendi albedo/normal dokunu bağlayabilirsin.

const GROUND_SHADER := preload("res://shaders/ground.gdshader")
const ROAD_SHADER := preload("res://shaders/road.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")

static var _tex := {}
static var _grass_mesh: ArrayMesh
static var _macro: FastNoiseLite


static func clear() -> void:
	_tex.clear()
	_grass_mesh = null
	_macro = null


static func ground_material(camp_center := Vector2.ZERO, camp_radius := 10.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter("macro_noise", _noise_tex("macro"))
	m.set_shader_parameter("detail_noise", _noise_tex("detail"))
	m.set_shader_parameter("normal_noise", _noise_tex("normal"))
	m.set_shader_parameter("camp_center", camp_center)
	m.set_shader_parameter("camp_radius", camp_radius)
	return m


static func road_material(axis: int, half_width := 4.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROAD_SHADER
	m.set_shader_parameter("detail_noise", _noise_tex("detail"))
	m.set_shader_parameter("crack_noise", _noise_tex("crack"))
	m.set_shader_parameter("normal_noise", _noise_tex("normal"))
	m.set_shader_parameter("axis", axis)
	m.set_shader_parameter("half_width", half_width)
	return m


## Kaba olarak shader'daki toprak lekelerini taklit eder (çim oraya az konur). 0..1
static func dirtiness(p: Vector2) -> float:
	if _macro == null:
		_noise_tex("macro")
	var v := _macro.get_noise_2d(p.x * 0.011 * 512.0, p.y * 0.011 * 512.0) * 0.5 + 0.5
	return v


## Çim öbeklerini MultiMesh olarak ekler. accept(Vector2) false dönerse o noktaya çim konmaz.
static func add_grass(parent: Node3D, count: int, area: Rect2, accept: Callable, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	if count <= 0:
		return null
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var tries := 0
	while points.size() < count and tries < count * 6:
		tries += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if not accept.call(p):
			continue
		var dirt := dirtiness(p)
		if dirt > 0.62 or (dirt > 0.52 and rng.randf() < 0.7):
			continue
		var s := rng.randf_range(0.7, 1.5)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		points.append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))
		var dry := clampf(dirt * 1.4 - 0.3 + rng.randf_range(-0.15, 0.15), 0.0, 1.0)
		colors.append(Color(0.22, 0.28, 0.11).lerp(Color(0.4, 0.37, 0.21), dry))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _get_grass_mesh()
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, points[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi


## İki çapraz dörtgen (60 cm yükseklik), tabanı y=0'da.
static func _get_grass_mesh() -> ArrayMesh:
	if _grass_mesh:
		return _grass_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.45
	var h := 0.6
	for a in [0.0, PI / 2.0]:
		var dir := Vector3(cos(a), 0, sin(a)) * w
		var corners := [-dir, dir, dir + Vector3.UP * h, -dir + Vector3.UP * h]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
	_grass_mesh = st.commit()
	return _grass_mesh


static func _noise_tex(kind: String) -> NoiseTexture2D:
	if _tex.has(kind):
		return _tex[kind]
	var n := FastNoiseLite.new()
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	match kind:
		"macro":
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n.frequency = 0.006
			n.fractal_octaves = 4
			n.seed = 11
			_macro = n
		"detail":
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX
			n.frequency = 0.03
			n.fractal_octaves = 5
			n.seed = 23
		"crack":
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.frequency = 0.02
			n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
			n.fractal_type = FastNoiseLite.FRACTAL_NONE
			n.seed = 5
		"normal":
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX
			n.frequency = 0.05
			n.fractal_octaves = 4
			n.seed = 41
			t.as_normal_map = true
			t.bump_strength = 6.0
	t.noise = n
	_tex[kind] = t
	return t
