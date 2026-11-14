extends Node3D
## İzometrik kamera: oyuncuyu yumuşakça takip eder, fare tekerleği ile yakınlaşır.
## orthographic = true klasik izometrik görünüm verir; false yaparsan hafif perspektif olur.

@export var target_path: NodePath
@export var follow_speed := 6.0
@export var yaw_deg := 45.0
@export var pitch_deg := 40.0
@export var distance := 35.0
@export var orthographic := true
@export var zoom := 20.0
@export var min_zoom := 10.0
@export var max_zoom := 34.0
@export var perspective_fov := 30.0

@onready var cam: Camera3D = $Camera3D

var _target: Node3D
var _zoom_target := 20.0


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	cam.rotation_degrees = Vector3(-pitch_deg, 0.0, 0.0)
	cam.near = 0.5
	cam.far = 150.0
	if orthographic:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = perspective_fov
	zoom = Settings.camera_zoom
	_zoom_target = zoom
	_apply_zoom()
	Settings.changed.connect(_on_settings_changed)
	if _target:
		global_position = _target.global_position
	# Sesler kameradan (35 m yukarıdan) değil, oyuncunun bulunduğu yerden dinlenir.
	var listener := AudioListener3D.new()
	listener.position = Vector3.UP * 1.5
	add_child(listener)
	listener.make_current()


func _on_settings_changed() -> void:
	_zoom_target = Settings.camera_zoom


func _physics_process(delta: float) -> void:
	if is_instance_valid(_target):
		global_position = global_position.lerp(_target.global_position, 1.0 - exp(-follow_speed * delta))
	zoom = lerpf(zoom, _zoom_target, 1.0 - exp(-10.0 * delta))
	_apply_zoom()


func _apply_zoom() -> void:
	var r := deg_to_rad(pitch_deg)
	if orthographic:
		cam.size = zoom
		cam.position = Vector3(0.0, sin(r) * distance, cos(r) * distance)
	else:
		var d := distance * zoom / 20.0
		cam.position = Vector3(0.0, sin(r) * d, cos(r) * d)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target - 1.5, min_zoom, max_zoom)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target + 1.5, min_zoom, max_zoom)
