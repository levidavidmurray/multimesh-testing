extends VBoxContainer

@export var is_expanded = true

enum STATE {OPEN, CLOSE, OPENING, CLOSING}

var init = false
var state: STATE
var max_size: Vector2i
var last_size: Vector2i

func _ready():
	state = STATE.OPEN


#func _gui_input(event):
	#if event is InputEventMouseButton:
		#if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			#self.expand()

func expand():
	is_expanded = !is_expanded
	if is_expanded:
		state = STATE.OPENING
	else:
		state = STATE.CLOSING


func _process(delta):
	if not init: # not in ready beacuse ready do not get corret size
		max_size = size
		last_size = size
		custom_minimum_size.y = max_size.y
		init = true
				
	if state == STATE.CLOSING:
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		#print(last_size)
		if custom_minimum_size.y > 0:
			custom_minimum_size.y = lerp(last_size.y, 0, 0.1)
			last_size = custom_minimum_size
		elif custom_minimum_size.y == 0:
			size_flags_vertical = Control.SIZE_FILL
			for child in get_children():
				child.visible = true if is_expanded else child == $show
			state = STATE.CLOSE
	
	elif state == STATE.OPENING:
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		for child in get_children():
			child.visible = true if is_expanded else child == $show
		if custom_minimum_size.y < max_size.y:
			custom_minimum_size.y = lerp(last_size.y, max_size.y, 0.1)
			last_size = custom_minimum_size
		elif custom_minimum_size.y == max_size.y:
			size_flags_vertical = Control.SIZE_FILL
			state = STATE.OPEN


func _on_button_pressed():
	expand()
