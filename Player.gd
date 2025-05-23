extends CharacterBody2D
@export var terrain = Node
@export var speed := 200.0
@export var jump_velocity := -400.0
var gravity := 800.0

func _physics_process(delta: float) -> void:
	var input_vector = Vector2.ZERO

	if Input.is_action_pressed("move_left"):
		input_vector.x -= 1
	if Input.is_action_pressed("move_right"):
		input_vector.x += 1

	velocity.x = input_vector.x * speed

	if not is_on_floor():
		velocity.y += gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	move_and_slide()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 1. Get mouse world position
		var mouse_pos := get_global_mouse_position()

		# 2. Calculate direction from player to mouse
		var dir := (mouse_pos - global_position).normalized()

		# 3. Clamp distance to 20 pixels from player
		var dig_pos := global_position + dir * 20.0

		# 4. Call dig at that position with some radius and strength
		terrain.dig_at_global(dig_pos, 40.0)  # radius = 6px, strength = 1.0
