class_name MultiMeshTest
extends Node

##############################
## EXPORT VARIABLES
##############################

@export var voxel_grid_size: Vector3i = Vector3i(150, 1, 150):
	set(value):
		voxel_grid_size = value
		_set_dirty()

@export var voxel_size: float = 0.15:
	set(value):
		voxel_size = value
		_set_dirty()


@export var debug_cube_size: float = 0.14:
	set(value):
		debug_cube_size = value
		_set_dirty()


@export var selection_weight_falloff: float = 1.0:
	set(value):
		selection_weight_falloff = max(0.0, value)
		_update_selected_point_weights()

@export var influence_radius: float = 2.0:
	set(value):
		influence_radius = max(0.1, value)
		_update_selected_point_weights()


@export var axis_influence: Vector3 = Vector3.ONE:
	set(value):
		axis_influence = value
		_update_selected_point_weights()

@export var weight_exponent: float = 4.0
@export var selection_weight_influence: float = 1.0
@export var drag_speed: float = 1.0
@export var weight_change_radius_speed: float = 0.1
@export var weight_change_falloff_speed: float = 0.1
@export var select_on_click: bool = true

@export var base_color: Color = Color.WHITE:
	set(value):
		base_color = value
		_update_selected_point_weights()

@export var selected_color: Color = Color.GREEN:
	set(value):
		selected_color = value
		_update_selected_point_weights()


##############################
## ONREADY VARIABLES
##############################

@onready var multi_mesh_instance: MultiMeshInstance3D = $MultiMeshInstance3D
@onready var orbit_camera: OrbitCamera = %OrbitCamera
@onready var game_ui: GameUI = %GameUI
@onready var world_environment: WorldEnvironment = $WorldEnvironment


##############################
## VARIABLES
##############################

const CUBE_VERTICES: Array[Vector3] = [
	Vector3(-0.5, -0.5, -0.5),
	Vector3(0.5, -0.5, -0.5),
	Vector3(-0.5, 0.5, -0.5),
	Vector3(0.5, 0.5, -0.5),
	Vector3(-0.5, -0.5, 0.5),
	Vector3(0.5, -0.5, 0.5),
	Vector3(-0.5, 0.5, 0.5),
	Vector3(0.5, 0.5, 0.5),
]

var is_dirty: bool = false
var influenced_indices: PackedInt32Array
var points: PackedVector3Array
var orig_points: PackedVector3Array
var multi_mesh: MultiMesh
var selected_point_index: int
var last_selected_point_index: int
var selected_point_weights: PackedFloat32Array
var are_points_resetting: bool = false

var camera: Camera3D
var selected_point_node: Node3D
var drag_plane: Plane
var is_dragging: bool = false
var is_changing_weight: bool = false
var weight_delta: Vector2

##############################
## LIFECYCLE METHODS
##############################

func _ready():
	camera = get_viewport().get_camera_3d()
	is_dirty = true
	multi_mesh = multi_mesh_instance.multimesh
	orbit_camera.set_meta("orig_rot", orbit_camera.rotation)
	if not multi_mesh:
		multi_mesh = MultiMesh.new()
		multi_mesh_instance.multimesh = multi_mesh


func _unhandled_input(event: InputEvent):
	if event is InputEventKey:
		event = event as InputEventKey
		if event.keycode == KEY_P:
			orbit_camera.reset_rotation()
		if event.keycode == KEY_L:
			orbit_camera.set_meta("orig_rotation", orbit_camera._anchor_node.transform.basis.get_rotation_quaternion().get_euler())
			orbit_camera.set_meta("orig_position", orbit_camera.position)

	if event is InputEventMouseButton:
		event = event as InputEventMouseButton
		if event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().gui_release_focus()
			if event.is_pressed():
				_create_drag_plane()
				if select_on_click:
					_handle_select(get_viewport().get_mouse_position())
				elif event.ctrl_pressed:
					_handle_select(get_viewport().get_mouse_position())
			is_dragging = event.is_pressed()

	if event is InputEventMouseMotion:
		event = event as InputEventMouseMotion
		if not selected_point_node:
			return
		if selected_point_index != -1 and is_dragging:
			# Start dragging
			var ray_origin = camera.project_ray_origin(event.position)
			var ray_dir = camera.project_ray_normal(event.position)
			# Find the intersection point with the drag plane
			var intersection = drag_plane.intersects_ray(ray_origin, ray_dir)
			if intersection:
				selected_point_node.global_position = intersection
		elif is_changing_weight:
			var delta = event.relative
			if abs(delta.x) > abs(delta.y):
				influence_radius += delta.x * weight_change_radius_speed
			else:
				selection_weight_falloff += delta.y * weight_change_falloff_speed


func _process(delta: float):
	if is_dirty:
		_create_grid()
		_set_selected_index(-1)

	is_changing_weight = Input.is_action_pressed("change_weight")

	if Input.is_action_just_released("reset"):
		_reset()

	if selected_point_index != -1:
		_update_follow_positions(delta)
	elif are_points_resetting:
		_spring_back(delta)

	last_selected_point_index = selected_point_index


##############################
## PRIVATE METHODS
##############################

func _handle_select(mouse_pos: Vector2):
	var closest_idx = _get_closest_point_index_to_mouse(mouse_pos)
	_set_selected_index(closest_idx)


func _set_selected_index(new_index: int):
	if not selected_point_node:
		selected_point_node = Node3D.new()
		add_child(selected_point_node)

	if new_index == selected_point_index:
		return

	if new_index == -1 and selected_point_index != -1:
		are_points_resetting = true

	# Handle previous selection
	if selected_point_index != -1:
		multi_mesh.set_instance_color(selected_point_index, base_color)

	# Handle new selection
	if new_index != -1:
		multi_mesh.set_instance_color(new_index, selected_color)
		selected_point_node.global_position = multi_mesh_instance.to_global(points[new_index])
		orbit_camera.set_anchor_position(selected_point_node.global_position)
		_create_drag_plane()

	selected_point_index = new_index
	_update_selected_point_weights()


func _create_drag_plane():
	if not selected_point_node:
		return
	drag_plane = Plane(-camera.global_transform.basis.z, selected_point_node.global_position)


func _update_selected_point_weights():
	# when a point is selected, determine influence for each point
	# based on distance to selected point

	selected_point_weights = PackedFloat32Array()
	selected_point_weights.resize(points.size())
	influenced_indices = PackedInt32Array()
	if selected_point_index == -1:
		for i in range(points.size()):
			selected_point_weights[i] = 0.0
	else:
		for i in range(points.size()):
			var dist = (orig_points[i] - orig_points[selected_point_index]).length()
			if dist > influence_radius:
				selected_point_weights[i] = 0.0
			else:
				selected_point_weights[i] = (1.0 - (dist / influence_radius)) ** selection_weight_falloff
				influenced_indices.append(i)
	
	# update colors based on weights
	for i in range(points.size()):
		var color = lerp(base_color, selected_color, selected_point_weights[i])
		multi_mesh.set_instance_color(i, color)


func _update_follow_positions(delta: float):
	# each point follows the selected point based on the weights
	if not selected_point_node:
		return

	var selected_node_pos = multi_mesh_instance.to_local(selected_point_node.global_position)
	for i in influenced_indices:
		var offset = orig_points[i] - orig_points[selected_point_index]
		var weight = selected_point_weights[i] * selection_weight_influence
		var t = pow(weight, weight_exponent) * delta * 5.0
		var selected_pos = selected_node_pos + offset
		var target = lerp(orig_points[i], selected_pos, weight)
		var new_point = lerp(points[i], target, t)
		points[i] = new_point
		multi_mesh.set_instance_transform(i, Transform3D().translated(points[i]))


func _spring_back(delta: float):
	# spring back to original positions
	var reset_finished = true
	for i in range(points.size()):
		var sq_dist = (points[i] - orig_points[i]).length_squared()
		if sq_dist <= 0.0001:
			points[i] = orig_points[i]
		else:
			reset_finished = false
			points[i] = lerp(points[i], orig_points[i], delta * randf_range(1.0, 15.0))
		multi_mesh.set_instance_transform(i, Transform3D().translated(points[i]))
	are_points_resetting = not reset_finished


func _get_closest_point_index_to_mouse(mouse_pos: Vector2):
	var closest_idx: int = -1
	var min_depth = INF

	for i in range(points.size()):
		var cube_center = points[i]
		var is_visible = false
		var screen_min = Vector2(INF, INF)
		var screen_max = Vector2(-INF, -INF)
		var depth_sum = 0.0

		# Project each vertex of the cube to the screen space
		for vertex in CUBE_VERTICES:
			var world_pos = cube_center + vertex * debug_cube_size
			if camera.is_position_behind(world_pos):
				continue
			var screen_pos = camera.unproject_position(world_pos)
			depth_sum += (camera.global_position - world_pos).length()
			screen_min = screen_min.min(screen_pos)
			screen_max = screen_max.max(screen_pos)
			is_visible = true

		# Skip cubes that are entirely behind the camera
		if not is_visible:
			continue
		# Check if mouse position is within the cube's projected bounds
		if mouse_pos.x >= screen_min.x and mouse_pos.x <= screen_max.x and \
				mouse_pos.y >= screen_min.y and mouse_pos.y <= screen_max.y:
			var avg_depth = depth_sum / CUBE_VERTICES.size()
			if avg_depth < min_depth:
				min_depth = avg_depth
				closest_idx = i

	return closest_idx


func _reset():
	influenced_indices.clear()
	selected_point_weights.clear()
	_set_selected_index(-1)


func _set_dirty():
	is_dirty = true


func _create_grid():
	_reset()
	points = _create_points()
	orig_points = points.duplicate()
	_update_multi_mesh()
	is_dirty = false


func _create_points():
	var _points: PackedVector3Array = PackedVector3Array()
	for x in range(0, voxel_grid_size.x):
		for y in range(0, voxel_grid_size.y):
			for z in range(0, voxel_grid_size.z):
				_points.append(Vector3(x, y, z) * voxel_size)
	return _points


func _update_multi_mesh():
	multi_mesh.instance_count = 0
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	multi_mesh.instance_count = points.size()
	var mesh = BoxMesh.new()
	mesh.size = Vector3.ONE * debug_cube_size
	multi_mesh.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, mat)
	for i in range(points.size()):
		multi_mesh.set_instance_transform(i, Transform3D().translated(points[i]))
		multi_mesh.set_instance_color(i, base_color)


##############################
## SIGNAL CALLBACKS
##############################

func _on_grid_size_changed(size: Vector3i):
	voxel_grid_size = size
