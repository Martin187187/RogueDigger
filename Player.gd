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
	if event.is_action_pressed("dig") and event is InputEventMouseButton:
		terrain.dig_circle(position, 50.0)  # Adjust radius if needed
