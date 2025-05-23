extends StaticBody2D
class_name Chunk

@export var threshold: float = 0.5
@export var num_voxels: int = 16
@export var size: float = 4.0
@export var offset: Vector2i
@export var seed = 13
@export var show_debug_cubes = false

enum MaterialType { AIR, DIRT, ROCK, COAL, IRON }

var voxels: PackedFloat32Array = PackedFloat32Array()
var materials: PackedInt32Array = PackedInt32Array()

func _ready() -> void:
	randomize()
	_fill_voxels()
	_build_mesh()


func set_voxel(x: int, y: int, value: float, material: int = MaterialType.AIR) -> void:
	var dim := num_voxels + 1
	if x >= 0 and y >= 0 and x < dim and y < dim:
		voxels[y * dim + x] = value
		materials[y * dim + x] = material


func dig_square(center: Vector2, half_size: float) -> void:
	var cell := size / float(num_voxels)
	var dim := num_voxels + 1

	var min_x := int(floor((center.x - half_size + size * 0.5) / cell))
	var max_x := int(ceil((center.x + half_size + size * 0.5) / cell))
	var min_y := int(floor((center.y - half_size + size * 0.5) / cell))
	var max_y := int(ceil((center.y + half_size + size * 0.5) / cell))

	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			if x >= 0 and y >= 0 and x < dim and y < dim:
				set_voxel(x, y, 0.0, MaterialType.AIR)

	_build_mesh()
func dig_circle(center: Vector2, radius: float, sigma: float) -> void:
	var cell := size / float(num_voxels)
	var dim := num_voxels + 1

	var min_x := int(floor((center.x - radius + size * 0.5) / cell))
	var max_x := int(ceil((center.x + radius + size * 0.5) / cell))
	var min_y := int(floor((center.y - radius + size * 0.5) / cell))
	var max_y := int(ceil((center.y + radius + size * 0.5) / cell))

	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			if x >= 0 and y >= 0 and x < dim and y < dim:
				var voxel_pos := Vector2(x, y) * cell - Vector2(size * 0.5, size * 0.5)
				var dist := center.distance_to(voxel_pos)
				if dist <= radius:
					var fade = clamp(1.0 - (dist / radius), 0.0, 1.0)
					var current := voxels[y * dim + x]
					var new_val = clamp(current - fade * sigma, 0.0, 1.0)
					voxels[y * dim + x] = new_val
					if new_val <= 0.0:
						materials[y * dim + x] = MaterialType.AIR

	_build_mesh()

func _fill_voxels() -> void:
	var dim := num_voxels + 1
	voxels.resize(dim * dim)
	materials.resize(dim * dim)

	var surface_noise := FastNoiseLite.new()
	surface_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	surface_noise.seed = seed
	surface_noise.frequency = 0.05

	var patch_noise := FastNoiseLite.new()
	patch_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	patch_noise.seed = seed + 1000
	patch_noise.frequency = 0.2

	var world_offset := offset * num_voxels
	var cell_size := size / float(num_voxels)

	for y in range(dim):
		for x in range(dim):
			var world_x := float(world_offset.x + x)
			var world_y := float(world_offset.y + y)

			# Actual Y in world space (for surface comparison)
			var world_pos_y := (world_y - 0.5 * num_voxels) * cell_size

			# Surface height at this X
			var surface_y := surface_noise.get_noise_2d(world_x, 0.0) * 5.0  # +/- 5 units

			var index := y * dim + x

			if world_pos_y < surface_y:
				voxels[index] = 0.0
				materials[index] = MaterialType.AIR
			else:
				voxels[index] = 1.0

				var depth := surface_y - world_pos_y

				if depth > -20.0:
					materials[index] = MaterialType.DIRT
				elif depth > -50.0:
					materials[index] = MaterialType.ROCK
				else:
					var patch_val := patch_noise.get_noise_2d(world_x/10, world_y/10) 
					if patch_val > 0.4:
						materials[index] = MaterialType.COAL
					elif patch_val < -0.4:
						materials[index] = MaterialType.IRON
					else:
						materials[index] = MaterialType.ROCK



func _build_mesh() -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()

	var cell := size / float(num_voxels)
	var collision_tris := PackedVector2Array()
	var vertex_count := 0

	for y in range(num_voxels):
		for x in range(num_voxels):
			var result = _emit_cell_2d(Vector2i(x, y), cell)
			var points: PackedVector2Array = result.points
			var mats: Array = result.materials

			for i in range(0, points.size(), 3):
				var tri_materials = [mats[i], mats[i + 1], mats[i + 2]]
				var color_sum := Color(0, 0, 0, 0)
				for mat in tri_materials:
					color_sum += _material_to_color(mat)
				var color := color_sum / 3.0

				for j in range(3):
					var p := points[i + j]
					vertices.append(Vector3(p.x, p.y, 0.0))
					indices.append(vertex_count)
					colors.append(color)
					vertex_count += 1
					collision_tris.append(p)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	$MeshInstance2D.mesh = mesh

	var shape := ConcavePolygonShape2D.new()
	shape.set_segments(_vector2_array_to_segments(collision_tris))
	$CollisionShape2D.shape = shape


func _emit_cell_2d(idx: Vector2i, cell: float) -> Dictionary:
	var origin := Vector2(
		idx.x * cell - size * 0.5,
		idx.y * cell - size * 0.5
	)

	var result := {
		"points": PackedVector2Array(),
		"materials": []
	}

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
			result.points.append(origin + p * cell)
			var mat_pos := idx + Vector2i(p.round())
			result.materials.append(_sample_material(mat_pos.x, mat_pos.y))

	return result


func _sample(x: int, y: int) -> float:
	var dim := num_voxels + 1
	return voxels[y * dim + x]


func _sample_material(x: int, y: int) -> int:
	var dim := num_voxels + 1
	x = clamp(x, 0, dim - 1)
	y = clamp(y, 0, dim - 1)
	return materials[y * dim + x]


func _material_to_color(material: int) -> Color:
	match material:
		MaterialType.DIRT:
			return Color(0.4, 0.26, 0.13)
		MaterialType.ROCK:
			return Color(0.5, 0.5, 0.5)
		MaterialType.COAL:
			return Color(0.1, 0.1, 0.1)
		MaterialType.IRON:
			return Color(0.8, 0.4, 0.1)
		_:
			return Color(1, 1, 1, 0.0)


func _dominant_material(materials: Array) -> int:
	var counts := {}
	for m in materials:
		counts[m] = counts.get(m, 0) + 1
	var max_m = MaterialType.AIR
	var max_count = 0
	for m in counts.keys():
		if counts[m] > max_count:
			max_count = counts[m]
			max_m = m
	return max_m


func interpolate(p1: Vector2, p2: Vector2, val1: float, val2: float) -> Vector2:
	if abs(val1 - val2) < 0.0001:
		return (p1 + p2) * 0.5
	var t := (threshold - val1) / (val2 - val1)
	return p1.lerp(p2, clamp(t, 0.0, 1.0))


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
