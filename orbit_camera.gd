class_name OrbitCamera
extends Camera3D

# External var
@export var pan_speed: float = 2 # Speed when use scroll mouse
@export var base_scroll_speed: float = 10 # Speed when use scroll mouse
@export var scroll_speed_anchor_dist_curve: Curve
@export var scroll_out_anchor_dist_curve: Curve
@export var base_scroll_distance: float = 0.1 # Distance use when use scroll mouse
@export var scroll_dist_anchor_dist_curve: Curve
@export var rotate_speed: float = 10
@export var min_anchor_distance: float = 1.0
@export var max_anchor_distance: float = 30.0
@export var anchor_node_path: NodePath

# Event var
var camera_rot_delta: Vector2
var camera_forward_delta: float
var anchor_delta: Vector2
var scroll_multiplier: float
var dist_to_anchor: float
var dist_percent: float

# Transform var
var _rotation: Vector3
var _anchor_node: Node3D
var rot_tween: Tween

func _ready():
	_anchor_node = get_node(anchor_node_path)
	_rotation = _anchor_node.transform.basis.get_rotation_quaternion().get_euler()
	set_meta("orig_rotation", _rotation)
	set_meta("orig_position", position)


func _process(delta: float):
	# if rot_tween and rot_tween.is_running():
	# 	return
	_process_transformation(delta)


func reset_rotation():
	var orig_rot = get_meta("orig_rotation")
	if rot_tween:
		rot_tween.kill()
	rot_tween = create_tween()
	rot_tween.set_trans(Tween.TRANS_SPRING)
	rot_tween.set_ease(Tween.EASE_OUT)
	# rot_tween.tween_property(_anchor_node, "transform:basis", Basis(Quaternion.from_euler(orig_rot)), time)
	rot_tween.tween_property(self, "_rotation", orig_rot, 1.0)
	rot_tween.parallel().tween_property(self, "position", get_meta("orig_position"), 1.5).set_trans(Tween.TRANS_SPRING)
	# _rotation = orig_rot

func set_anchor_position(pos: Vector3):
	# reparent(_anchor_node.get_parent())
	# _anchor_node.global_position = pos
	# await get_tree().create_timer(1.0).timeout
	# reparent.call_deferred(_anchor_node)
	pass


func _process_transformation(delta: float):
	# Update rotation

	var _rot_speed = lerp(rotate_speed, rotate_speed * 0.5, dist_percent)
	_rotation.x += -camera_rot_delta.y * delta * _rot_speed
	_rotation.y += -camera_rot_delta.x * delta * _rot_speed
	if _rotation.x < -PI / 2:
		_rotation.x = -PI / 2
	if _rotation.x > PI / 2:
		_rotation.x = PI / 2
	camera_rot_delta = Vector2.ZERO

	dist_to_anchor = global_position.distance_to(_anchor_node.global_position)
	dist_percent = (dist_to_anchor - min_anchor_distance) / (max_anchor_distance - min_anchor_distance)
	
	if camera_forward_delta != 0:
		var forward_delta = camera_forward_delta * delta * base_scroll_speed
		if camera_forward_delta < 0:
			if dist_to_anchor + forward_delta < min_anchor_distance:
				forward_delta = min_anchor_distance - dist_to_anchor

		camera_forward_delta = move_toward(camera_forward_delta, 0.0, abs(forward_delta))
		translate_object_local(Vector3(0, 0, forward_delta))
		# position = position + transform.basis.z * move_dist

	# _anchor_node.set_identity()
	_anchor_node.transform.basis = Basis(Quaternion.from_euler(_rotation))
	# translate anchor node
	_anchor_node.translate_object_local(Vector3(-anchor_delta.x, anchor_delta.y, 0))
	anchor_delta = Vector2()


func _input(event):
	if event is InputEventMouseMotion:
		_process_mouse_rotation_event(event)
	elif event is InputEventMouseButton:
		_process_mouse_scroll_event(event)


func _process_mouse_rotation_event(e: InputEventMouseMotion):
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		if Input.is_key_pressed(KEY_SHIFT):
			# scale pan_speed with dist_percent. The closer to the anchor, the slower the pan_speed
			# the further from the anchor, the faster the pan_speed
			var _pan_speed = clampf(pan_speed * (dist_percent * 2.0), pan_speed, pan_speed * 2.0)
			anchor_delta = e.relative * _pan_speed
		else:
			camera_rot_delta = e.relative


func _process_mouse_scroll_event(e: InputEventMouseButton):
	if e.button_index == MOUSE_BUTTON_WHEEL_UP:
		scroll_multiplier = scroll_speed_anchor_dist_curve.sample_baked(dist_percent)
		if camera_forward_delta > 0:
			camera_forward_delta = 0
		camera_forward_delta -= base_scroll_distance * scroll_multiplier
	elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll_multiplier = scroll_speed_anchor_dist_curve.sample_baked(1.0 - dist_percent)
		# scroll_multiplier = scroll_out_anchor_dist_curve.sample_baked(dist_percent)
		if camera_forward_delta < 0:
			camera_forward_delta = 0
		camera_forward_delta += base_scroll_distance * scroll_multiplier
