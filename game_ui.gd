class_name GameUI
extends Control

##############################
## EXPORT VARIABLES
##############################

@export var mm_test: MultiMeshTest


##############################
## ONREADY VARIABLES
##############################

@onready var label_fps: Label = %Label_FPS
@onready var grid_input_x: SpinBox = %GridInput_X
@onready var grid_input_y: SpinBox = %GridInput_Y
@onready var grid_input_z: SpinBox = %GridInput_Z
@onready var label_point_count: Label = %Label_PointCount
@onready var label_selection_radius: Label = %Label_SelectionRadius
@onready var label_selection_falloff: Label = %Label_SelectionFalloff
@onready var label_points_influenced: Label = %Label_PointsInfluenced
@onready var checkbox_select_on_click: CheckButton = %Checkbox_SelectOnClick
@onready var color_picker_base: ColorPickerButton = %ColorPicker_Base
@onready var color_picker_selection: ColorPickerButton = %ColorPicker_Selection
@onready var color_picker_background: ColorPickerButton = %ColorPicker_Background
@onready var checkbox_sdfgi: CheckButton = %Checkbox_SDFGI
@onready var settings_panel: PanelContainer = %SettingsPanel


##############################
## VARIABLES
##############################

var mouse_inside_settings_panel: bool = false


##############################
## LIFECYCLE METHODS
##############################

func _ready():
	_setup.call_deferred()
	settings_panel.set_meta("orig_scale", settings_panel.scale)


func _process(_delta):
	label_fps.text = "FPS: %.0f" % Engine.get_frames_per_second()
	set_point_count(mm_test.points.size())
	set_selection_radius(mm_test.influence_radius)
	set_selection_falloff(mm_test.selection_weight_falloff)
	set_points_influenced(mm_test.influenced_indices.size())
	# _check_mouse_settings_panel()


##############################
## PUBLIC METHODS
##############################

func set_grid_size(grid_size: Vector3i):
	grid_input_x.value = grid_size.x
	grid_input_y.value = grid_size.y
	grid_input_z.value = grid_size.z


func set_point_count(count: int):
	label_point_count.text = "(Point Count: %d)" % count


func set_selection_radius(radius: float):
	label_selection_radius.text = "Selection Radius: %.1fm" % radius


func set_selection_falloff(falloff: float):
	label_selection_falloff.text = "Selection Falloff: %.1f" % falloff


func set_points_influenced(count: int):
	label_points_influenced.text = "Points Influenced: %d" % count


##############################
## PRVIATE METHODS
##############################

func _setup():
	_set_initial_values()
	_setup_callbacks()

func _set_initial_values():
	set_point_count(0)
	set_selection_radius(0)
	set_selection_falloff(0)
	set_points_influenced(0)
	set_grid_size(mm_test.voxel_grid_size)
	checkbox_select_on_click.button_pressed = mm_test.select_on_click
	checkbox_sdfgi.button_pressed = mm_test.world_environment.environment.sdfgi_enabled
	color_picker_base.color = mm_test.base_color
	color_picker_selection.color = mm_test.selected_color
	color_picker_background.color = mm_test.world_environment.environment.background_color


func _setup_callbacks():
	checkbox_select_on_click.toggled.connect(_on_select_on_click_toggled)
	checkbox_sdfgi.toggled.connect(_on_sdfgi_toggled)
	color_picker_base.color_changed.connect(_on_base_color_changed)
	color_picker_selection.color_changed.connect(_on_selection_color_changed)
	color_picker_background.color_changed.connect(_on_background_color_changed)
	# settings_panel.mouse_entered.connect(_show_settings_panel)
	# settings_panel.mouse_exited.connect(_hide_settings_panel)
	_setup_color_picker(color_picker_base)
	_setup_color_picker(color_picker_selection)
	_setup_color_picker(color_picker_background)
	_setup_grid_input(grid_input_x)
	_setup_grid_input(grid_input_y)
	_setup_grid_input(grid_input_z)


func _setup_color_picker(color_picker: ColorPickerButton):
	var picker = color_picker.get_picker()
	picker.sliders_visible = false
	picker.color_modes_visible = false
	picker.presets_visible = false
	picker.sampler_visible = false
	picker.can_add_swatches = false
	picker.hex_visible = true
	picker.can_add_swatches = false


func _setup_grid_input(grid_input: SpinBox):
	grid_input.value_changed.connect(_on_grid_input_value_changed.bind(grid_input))


func _check_mouse_settings_panel():
	if settings_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
		if not mouse_inside_settings_panel:
			mouse_inside_settings_panel = true
			_show_settings_panel()
	else:
		if mouse_inside_settings_panel:
			mouse_inside_settings_panel = false
			_hide_settings_panel()


func _hide_settings_panel():
	if settings_panel.has_meta("tween"):
		settings_panel.get_meta("tween").kill()
	var tween = settings_panel.create_tween()
	var orig_scale = settings_panel.get_meta("orig_scale")
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(settings_panel, "scale", orig_scale * 0.75, 0.25)
	tween.tween_property(settings_panel, "modulate:a", 0.35, 0.25)


func _show_settings_panel():
	if settings_panel.has_meta("tween"):
		settings_panel.get_meta("tween").kill()
	var tween = settings_panel.create_tween()
	var orig_scale = settings_panel.get_meta("orig_scale")
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(settings_panel, "scale", orig_scale, 0.25)
	tween.tween_property(settings_panel, "modulate:a", 1.0, 0.25)


##############################
## SIGNAL CALLBACKS
##############################

func _on_grid_input_value_changed(_value: float, _grid_input: SpinBox):
	var x = int(grid_input_x.value)
	var y = int(grid_input_y.value)
	var z = int(grid_input_z.value)
	mm_test.voxel_grid_size = Vector3i(x, y, z)


func _on_select_on_click_toggled(toggled_on: bool):
	mm_test.select_on_click = toggled_on


func _on_base_color_changed(color: Color):
	mm_test.base_color = color


func _on_selection_color_changed(color: Color):
	mm_test.selected_color = color


func _on_background_color_changed(color: Color):
	mm_test.world_environment.environment.background_color = color


func _on_sdfgi_toggled(toggled_on: bool):
	mm_test.world_environment.environment.sdfgi_enabled = toggled_on
