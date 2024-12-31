@tool
extends Node

@export var voxel_grid_size: Vector3 = Vector3(10, 10, 10):
	set(value):
		voxel_grid_size = value
		_set_dirty()

@export var voxel_size: float = 1.0:
	set(value):
		voxel_size = value
		_set_dirty()


@export var debug_cube_size: float = 0.1:
	set(value):
		debug_cube_size = value
		_set_dirty()


@export var selection_weight_falloff: float = 1.0:
	set(value):
		selection_weight_falloff = value
		_update_selected_point_weights()

@export var influence_radius: float = 1.0:
	set(value):
		influence_radius = max(0.1, value)
		_update_selected_point_weights()


@export var axis_influence: Vector3 = Vector3.ONE:
	set(value):
		axis_influence = value
		_update_selected_point_weights()

@export var axis_offset: Vector3 = Vector3.ZERO

@export var weight_exponent: float = 4.0

@export var selection_weight_influence: float = 1.0

@export var detect_mouse: bool = true

@export var base_color: Color = Color.WHITE:
	set(value):
		base_color = value
		_update_selected_point_weights()

@export var selected_color: Color = Color.GREEN:
	set(value):
		selected_color = value
		_update_selected_point_weights()

@onready var multi_mesh_instance: MultiMeshInstance3D = $MultiMeshInstance3D

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
var last_mouse_pos: Vector2
var last_closest_index: int
var selected_point_index: int
var selected_point_weights: PackedFloat32Array

var selected_point_node: Node3D

##############################
## LIFECYCLE METHODS
##############################

func _ready():
	multi_mesh = multi_mesh_instance.multimesh
	if not multi_mesh:
		multi_mesh = MultiMesh.new()
		multi_mesh_instance.multimesh = multi_mesh

	is_dirty = true
	if not InputMap.has_action("click"):
		InputMap.add_action("click")
		var ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("click", ev)


func _process(delta: float):
	var mouse_pos = _get_mouse_position()
	var is_inside = true
	if Engine.is_editor_hint():
		var viewport_size = EditorInterface.get_editor_viewport_3d(0).size
		# check if mouse_pos is inside of viewport
		is_inside = mouse_pos.x >= 0 and mouse_pos.x <= viewport_size.x and \
						mouse_pos.y >= 0 and mouse_pos.y <= viewport_size.y

	if is_inside and Input.is_action_just_pressed("click"):
		_handle_select(mouse_pos)

	if selected_point_index != -1:
		_update_follow_positions(delta)
	else:
		_spring_back(delta)

	if is_dirty:
		_create_grid()


func _handle_select(mouse_pos: Vector2):
	if Engine.is_editor_hint():
		var selected_nodes = EditorInterface.get_selection().get_transformable_selected_nodes()
		if selected_nodes.size() > 0:
			return

	var closest_idx = get_closest_point_index_to_mouse(mouse_pos)

	if not selected_point_node:
		selected_point_node = Node3D.new()
		add_child(selected_point_node)

	# Handle previous selection
	if selected_point_index != -1:
		multi_mesh.set_instance_color(selected_point_index, base_color)

	# Handle new selection
	if closest_idx != -1:
		multi_mesh.set_instance_color(closest_idx, selected_color)
		selected_point_node.global_position = multi_mesh_instance.to_global(points[closest_idx])
		if Engine.is_editor_hint():
			wait(0.1).connect(EditorInterface.get_selection().add_node.bind(selected_point_node), CONNECT_ONE_SHOT)

	selected_point_index = closest_idx
	_update_selected_point_weights()


func _update_selected_point_weights():
	# when a point is selected, determine influence for each point
	# based on distance to selected point
	if selected_point_index == -1:
		return

	selected_point_weights = PackedFloat32Array()
	selected_point_weights.resize(points.size())
	influenced_indices = PackedInt32Array()
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
		var selected_pos = selected_node_pos + offset + axis_offset
		var target_x = lerp(orig_points[i].x, selected_pos.x, weight * axis_influence.x)
		var target_y = lerp(orig_points[i].y, selected_pos.y, weight * axis_influence.y)
		var target_z = lerp(orig_points[i].z, selected_pos.z, weight * axis_influence.z)
		var new_x = lerp(points[i].x, target_x, t)
		var new_y = lerp(points[i].y, target_y, t)
		var new_z = lerp(points[i].z, target_z, t)
		var new_point = Vector3(new_x, new_y, new_z)
		points[i] = new_point
		multi_mesh.set_instance_transform(i, Transform3D().translated(points[i]))


func _spring_back(delta: float):
	# spring back to original positions
	for i in range(points.size()):
		points[i] = lerp(points[i], orig_points[i], 0.1)
		multi_mesh.set_instance_transform(i, Transform3D().translated(points[i]))


func get_closest_point_index_to_mouse(mouse_pos: Vector2):
	print(mouse_pos)
	var camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
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

	print(closest_idx)

	return closest_idx


func _update_closest(closest_index: int):
	if last_closest_index == closest_index:
		return
	if last_closest_index != -1:
		multi_mesh.set_instance_color(last_closest_index, base_color)
	last_closest_index = closest_index
	if closest_index != -1:
		multi_mesh.set_instance_color(closest_index, Color.ORANGE_RED)


func _set_dirty():
	is_dirty = true


func _create_grid():
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


func _get_mouse_position():
	if Engine.is_editor_hint():
		return EditorInterface.get_editor_viewport_3d(0).get_mouse_position()
	else:
		return get_viewport().get_mouse_position()


func wait(time: float) -> Signal:
	return get_tree().create_timer(time).timeout
