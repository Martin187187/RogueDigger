extends Node2D

@export var chunk_scene: PackedScene
@export var chunk_size: float = 4.0
@export var num_voxels: int = 16
@export var num_chunks: int = 3

var chunks :Dictionary[Vector2i, Chunk] = {} # Dictionary to store chunks by offset (Vector2i -> Chunk)


func _ready() -> void:
	var half := num_chunks / 2

	for y in range(num_chunks):
		for x in range(num_chunks):
			var offset_x = x - half
			var offset_y = y - half
			var offset := Vector2i(offset_x, offset_y)
			var position := Vector2(offset_x, offset_y) * chunk_size
			_create_chunk(position, offset)

	# Example dig test
	dig_at_global(Vector2(0, 0), 100)

func _create_chunk(pos: Vector2, offset: Vector2i):
	if not chunk_scene:
		push_error("Chunk scene not assigned!")
		return

	var chunk := chunk_scene.instantiate() as Chunk
	chunk.position = pos
	chunk.size = chunk_size
	chunk.num_voxels = num_voxels
	chunk.offset = offset 
	add_child(chunk)

	chunks[offset] = chunk  # Store it in the dictionary

func dig_at_global(center: Vector2, half_size: float) -> void:
	var dig_rect = Rect2(center - Vector2(half_size, half_size), Vector2(half_size * 2, half_size * 2))

	for offset in chunks.keys():
		var chunk := chunks[offset]
		var chunk_rect = Rect2(chunk.position - Vector2(chunk_size, chunk_size) * 0.5, Vector2(chunk_size, chunk_size))

		if dig_rect.intersects(chunk_rect):
			var local_pos := center - chunk.position  # Convert world position to chunk-local
			chunk.dig_circle(local_pos, half_size, 1)
