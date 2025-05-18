extends StaticBody2D

@export var threshold: float = 0.5
@export var num_voxels: int = 16
@export var size: float = 4.0
@export var show_debug_cubes = false

var voxels: PackedFloat32Array = PackedFloat32Array()  # (n+1)^2 scalar samples

func _ready() -> void:
	randomize()
	_fill_voxels()
	if show_debug_cubes:
		_create_debug_cubes()
	_build_mesh()
	dig_circle(Vector2(0, 0), 200)


func set_voxel(x: int, y: int, value: float) -> void:
	var dim := num_voxels + 1
	if x >= 0 and y >= 0 and x < dim and y < dim:
		voxels[y * dim + x] = value


func dig_circle(center: Vector2, radius: float) -> void:
	var dim := num_voxels + 1
	var cell := size / float(num_voxels)

	for y in range(dim):
		for x in range(dim):
			var world_pos := Vector2(x * cell - size * 0.5, y * cell - size * 0.5)
			if world_pos.distance_to(center) < radius:
				set_voxel(x, y, 0.0)

	_build_mesh()


func _fill_voxels() -> void:
	var dim := num_voxels + 1
	voxels.resize(dim * dim)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = randi()
	noise.frequency = 1.5

	for y in range(dim):
		for x in range(dim):
			var fx := float(x - dim / 2) / float(dim)
			var fy := float(y - dim / 2) / float(dim)
			var raw := noise.get_noise_2d(fx, fy)
			var value := (raw + 1.0) * 0.5
			voxels[y * dim + x] = value


func _create_debug_cubes() -> void:
	var cell := size / float(num_voxels)
	for y in range(num_voxels + 1):
		for x in range(num_voxels + 1):
			var pos := Vector2(x * cell - size * 0.5, y * cell - size * 0.5)
			_spawn_debug_cube(pos, 0.05)


func _spawn_debug_cube(pos2d: Vector2, radius: float) -> void:
	var cube := ColorRect.new()
	cube.size = Vector2.ONE * radius
	cube.position = pos2d - cube.size * 0.5

	var cell := size / float(num_voxels)
	var x := int(round((pos2d.x + size * 0.5) / cell))
	var y := int(round((pos2d.y + size * 0.5) / cell))
	var dim := num_voxels + 1

	if x >= 0 and y >= 0 and x < dim and y < dim:
		var value := voxels[y * dim + x]
		if value > threshold:
			cube.albedo_color = Color.BLACK
		else:
			cube.albedo_color = Color.WHITE

	add_child(cube)


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := CanvasItemMaterial.new()
	st.set_material(mat)

	var cell := size / float(num_voxels)
	var collision_tris := PackedVector2Array()

	for y in range(num_voxels):
		for x in range(num_voxels):
			var tris := _emit_cell(st, Vector2i(x, y), cell)
			for pt in tris:
				collision_tris.append(pt)

	$MeshInstance2D.mesh = st.commit()

	var shape := ConcavePolygonShape2D.new()
	shape.set_segments(_vector2_array_to_segments(collision_tris))

	$CollisionShape2D.shape = shape

func _vector2_array_to_segments(tris: PackedVector2Array) -> PackedVector2Array:
	var segments := PackedVector2Array()
	for i in range(0, tris.size(), 3):
		segments.append(tris[i])
		segments.append(tris[i + 1])
		segments.append(tris[i + 1])
		segments.append(tris[i + 2])
		segments.append(tris[i + 2])
		segments.append(tris[i])
	return segments


func interpolate(p1: Vector2, p2: Vector2, val1: float, val2: float) -> Vector2:
	if abs(val1 - val2) < 0.0001:
		return (p1 + p2) * 0.5
	var t := (threshold - val1) / (val2 - val1)
	return p1.lerp(p2, clamp(t, 0.0, 1.0))


func _emit_cell(st: SurfaceTool, idx: Vector2i, cell: float) -> PackedVector2Array:
	var origin := Vector2(
		idx.x * cell - size * 0.5,
		idx.y * cell - size * 0.5
	)

	var points := PackedVector2Array()

	var v0 := _sample(idx.x, idx.y)
	var v1 := _sample(idx.x + 1, idx.y)
	var v2 := _sample(idx.x + 1, idx.y + 1)
	var v3 := _sample(idx.x, idx.y + 1)

	var ci := 0
	if v0 > threshold: ci |= 1
	if v1 > threshold: ci |= 2
	if v2 > threshold: ci |= 4
	if v3 > threshold: ci |= 8
	
	var P: Dictionary[StringName, Vector2] = {
		"p0": Vector2(0, 0),
		"p1": Vector2(1, 0),
		"p2": Vector2(1, 1),
		"p3": Vector2(0, 1),
		"e0": interpolate(Vector2(0, 0), Vector2(1, 0), v0, v1),
		"e1": interpolate(Vector2(1, 0), Vector2(1, 1), v1, v2),
		"e2": interpolate(Vector2(1, 1), Vector2(0, 1), v2, v3),
		"e3": interpolate(Vector2(0, 1), Vector2(0, 0), v3, v0),
	}

	const LUT := {
		0: [],
		1: [["p0", "e3", "e0"]],
		2: [["p1", "e0", "e1"]],
		3: [["p0", "e3", "e1"], ["p0", "e1", "p1"]],
		4: [["p2", "e1", "e2"]],
		5: [["p0", "e3", "e0"], ["e3", "e2", "e0"], ["e0", "e2", "e1"], ["e2", "p2", "e1"]],
		6: [["p1", "e0", "p2"], ["e0", "e2", "p2"]],
		7: [["p0", "e3", "e2"], ["p0", "e2", "p2"], ["p0", "p2", "p1"]],
		8: [["p3", "e2", "e3"]],
		9: [["p0", "p3", "e2"], ["p0", "e2", "e0"]],
		10: [["p3", "e2", "e3"], ["e3", "e2", "e0"], ["e0", "e2", "e1"], ["e1", "p1", "e0"]],
		11: [["p0", "p3", "p1"], ["p1", "p3", "e2"], ["p1", "e2", "e1"]],
		12: [["p3", "p2", "e3"], ["p2", "e1", "e3"]],
		13: [["p0", "p3", "p2"], ["p0", "p2", "e1"], ["p0", "e1", "e0"]],
		14: [["p1", "p3", "p2"], ["p1", "e3", "p3"], ["e0", "e3", "p1"]],
		15: [["p0", "p2", "p1"], ["p0", "p3", "p2"]],
	}

	for tri in LUT[ci]:
		for key in tri:
			var p := P[key]
			var final := origin + p * cell
			st.add_vertex(Vector3(final.x, final.y, 0.0))
			points.append(final)

	return points


func _sample(x: int, y: int) -> float:
	var dim := num_voxels + 1
	return voxels[y * dim + x]
