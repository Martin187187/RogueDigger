## marching_squares_debug.gd
## Attach this to a MeshInstance3D (or any Node3D – it overrides its own mesh)

extends MeshInstance3D

@export var threshold: float = 0.5  # isovalue
@export var num_voxels: int = 16   # number of cells per side
@export var size: float = 4.0      # world-space side length
@export var show_debug_cubes = false
var voxels: PackedFloat32Array = PackedFloat32Array()  # (n+1)^2 scalar samples


func _ready() -> void:
	randomize()
	_fill_voxels()
	if show_debug_cubes:
		_create_debug_cubes()
	_build_mesh()

func _fill_voxels() -> void:
	var dim := num_voxels + 1
	voxels.resize(dim * dim)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = randi()
	noise.frequency = 1.5  # adjust for zoom

	for y in range(dim):
		for x in range(dim):
			# Convert to centered world space coordinates (optional)
			var fx := float(x - dim / 2) / float(dim)
			var fy := float(y - dim / 2) / float(dim)

			# Get noise value and normalize it from [-1,1] to [0,1]
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
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	cube.scale = Vector3.ONE * radius
	cube.position = Vector3(pos2d.x, pos2d.y, 0.0)

	var cell := size / float(num_voxels)
	var x := int(round((pos2d.x + size * 0.5) / cell))
	var y := int(round((pos2d.y + size * 0.5) / cell))
	var dim := num_voxels + 1

	if x >= 0 and y >= 0 and x < dim and y < dim:
		var value := voxels[y * dim + x]
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if value > threshold:
			mat.albedo_color = Color.BLACK
		else:
			mat.albedo_color = Color.WHITE
		cube.material_override = mat

	add_child(cube)


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	st.set_material(mat)

	var cell := size / float(num_voxels)
	for y in range(num_voxels):
		for x in range(num_voxels):
			_emit_cell(st, Vector2i(x, y), cell)

	mesh = st.commit()


func interpolate(p1: Vector2, p2: Vector2, val1: float, val2: float) -> Vector2:
	if abs(val1 - val2) < 0.0001:
		return (p1 + p2) * 0.5
	var t := (threshold - val1) / (val2 - val1)
	return p1.lerp(p2, clamp(t, 0.0, 1.0))
func _emit_cell(st: SurfaceTool, idx: Vector2i, cell: float) -> void:
	var origin := Vector3(
		idx.x * cell - size * 0.5,
		idx.y * cell - size * 0.5,
		0.0
	)

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
			st.add_vertex(origin + Vector3(p.x * cell, p.y * cell, 0.0))


func _sample(x: int, y: int) -> float:
	var dim := num_voxels + 1
	return voxels[y * dim + x]
