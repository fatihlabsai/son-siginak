class_name CutsceneActor
extends Node3D
## Ara sahne oyuncusu: Tripo karakterini yükler, boyuna göre ölçekler,
## animasyonu adındaki bir parçayla oynatır ve kemiğe nesne bağlar.
## Tripo animasyon adları istemin ilk 64 harfidir; anahtar kelimeyle buluruz.

var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var _current := ""


static func create(parent: Node, path: String, height: float, pos: Vector3, yaw: float) -> CutsceneActor:
	var a := CutsceneActor.new()
	parent.add_child(a)
	a.position = pos
	a.rotation.y = yaw
	var scene := load(path) as PackedScene
	a.model = scene.instantiate() as Node3D
	a.model.scale = Vector3.ONE * height   # Tripo karakterleri ~1 birim boyunda gelir
	a.add_child(a.model)
	var aps := a.model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		a.anim = aps[0]
	var sks := a.model.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		a.skeleton = sks[0]
	return a


func find_anim(keyword: String) -> String:
	if anim == null:
		return ""
	var kw := keyword.to_lower()
	for n in anim.get_animation_list():
		if String(n).to_lower().contains(kw):
			return n
	return ""


## Animasyonu oynat. loop: döngü; from_end: tersten oynat.
func play(keyword: String, loop := true, blend := 0.35, speed := 1.0, from_end := false) -> float:
	var n := find_anim(keyword)
	if n == "":
		push_warning("CutsceneActor: animasyon yok: " + keyword)
		return 0.0
	var a := anim.get_animation(n)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if from_end:
		anim.play_backwards(n, blend)
	else:
		anim.play(n, blend, speed)
	_current = n
	return a.length / maxf(speed, 0.01)


func seek(t: float) -> void:
	if anim and anim.current_animation != "":
		anim.seek(t, true)


func pause() -> void:
	if anim:
		anim.pause()


func anim_length(keyword: String) -> float:
	var n := find_anim(keyword)
	return anim.get_animation(n).length if n != "" else 0.0


## Kemiğe bir nesne bağla (örn. eldeki kupa). Kemik uzayında konum/dönüş ver.
func attach(bone: String, node: Node3D, offset := Transform3D.IDENTITY) -> BoneAttachment3D:
	if skeleton == null:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	skeleton.add_child(att)
	# Model ölçeği kemik uzayına da yansır; bağlanan nesne gerçek boyutunda kalsın.
	var holder := Node3D.new()
	holder.scale = Vector3.ONE / model.scale.x
	att.add_child(holder)
	node.transform = offset
	holder.add_child(node)
	return att


func bone_global(bone: String) -> Vector3:
	if skeleton == null:
		return global_position
	var i := skeleton.find_bone(bone)
	if i < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin


## Tripo eşya modelini yükler; en uzun yatay kenarı `length` olacak şekilde ölçekler,
## tabanını y=0'a, ortasını kökün altına getirir.
static func spawn_prop(parent: Node, path: String, length: float, pos: Vector3, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var scene := load(path) as PackedScene
	if scene == null:
		return root
	var m := scene.instantiate() as Node3D
	root.add_child(m)
	var box := _aabb_of(m)
	var longest := maxf(box.size.x, box.size.z)
	var s := length / maxf(longest, 0.001)
	m.scale = Vector3.ONE * s
	var c := box.get_center()
	m.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	root.set_meta("size", box.size * s)
	return root


static func _aabb_of(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := _relative_transform(n, m)
		var b: AABB = t * m.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


static func _relative_transform(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
