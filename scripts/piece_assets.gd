class_name PieceAssets
extends RefCounted

## Shared meshes and materials for the pieces.
##
## Shape x hollow gives four meshes, colour x spotted gives four materials, and
## that is the entire cost of 64 pieces - size is node scale and spin is
## behaviour. Everything is built once per run and cached statically.

const PIECE_SHADER: Shader = preload("res://shaders/piece.gdshader")

## Outer size of a big piece, in local units.
const UNIT := 0.9
## Thickness of the bars in the hollow cube frame.
const BAR := 0.13
## How far the shading normals lean towards the flat face normal.
## 1.0 is fully flat, which bands hard under sky ambient because each
## facet takes a single sky sample; 0.0 is fully smooth, which hides
## the spin again. In between keeps the facets readable but softens
## the steps between them.
const FACET_STRENGTH := 0.55
## Cross-product length below which a triangle is treated as collapsed.
const DEGENERATE_AREA := 1e-6
## Sphere tessellation - see _build_sphere() for why it is this coarse.
const SPHERE_SEGMENTS := 12
const SPHERE_RINGS := 6

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}


static func mesh_for(is_sphere: bool, is_hollow: bool) -> Mesh:
	var key := (1 if is_sphere else 0) | (2 if is_hollow else 0)
	if not _meshes.has(key):
		_meshes[key] = _build_mesh(is_sphere, is_hollow)
	return _meshes[key]


static func material_for(is_black: bool, is_spotted: bool) -> ShaderMaterial:
	var key := (1 if is_black else 0) | (2 if is_spotted else 0)
	if not _materials.has(key):
		_materials[key] = _build_material(is_black, is_spotted)
	return _materials[key]


static func _build_mesh(is_sphere: bool, is_hollow: bool) -> Mesh:
	if is_sphere:
		return _build_sphere_shell() if is_hollow else _build_sphere()
	return _build_cube_frame() if is_hollow else _build_cube()


static func _build_cube() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(UNIT, UNIT, UNIT)
	return mesh


## Coarse and flat-shaded on purpose. A smooth plain sphere is rotationally
## symmetric about every axis, so nothing on it can ever betray a spin -
## the spinning solid plain spheres were pixel-identical to their still
## twins. Facets give the light something to catch as the piece turns.
static func _build_sphere() -> Mesh:
	var source := SphereMesh.new()
	source.radius = UNIT * 0.5
	source.height = UNIT
	source.radial_segments = SPHERE_SEGMENTS
	source.rings = SPHERE_RINGS
	return _flat_shaded(source)


## One normal per triangle, so each facet shades as a flat plane.
##
## Done by hand rather than with SurfaceTool.generate_normals(), which
## honours smoothing groups and averages coincident vertices - that quietly
## undoes a deindex and hands back the smooth ball you started with.
static func _flat_shaded(source: PrimitiveMesh) -> ArrayMesh:
	var source_arrays := source.get_mesh_arrays()
	var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	var source_uvs: PackedVector2Array = source_arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in range(0, indices.size(), 3):
		var corners := [indices[i], indices[i + 1], indices[i + 2]]
		var a: Vector3 = source_vertices[corners[0]]
		var b: Vector3 = source_vertices[corners[1]]
		var c: Vector3 = source_vertices[corners[2]]

		# The sphere is centred on the origin, so the direction of the face
		# centroid is always a sane outward normal. Using the centroid rather
		# than one vertex matters at the poles, where SphereMesh collapses its
		# rings: a single vertex there sits almost perpendicular to the true
		# normal, so it cannot tell you which way is out.
		var outward := ((a + b + c) / 3.0).normalized()
		var face := (b - a).cross(c - a)
		var normal := outward
		if face.length() > DEGENERATE_AREA:
			normal = face.normalized()
			if normal.dot(outward) < 0.0:
				normal = -normal
		else:
			# A collapsed sliver has no meaningful cross product; normalising it
			# just amplifies float noise into an arbitrary direction, which then
			# lights the face backwards.
			continue
		for corner in corners:
			var vertex: Vector3 = source_vertices[corner]
			# Lean the true sphere normal towards the face normal rather than
			# replacing it. Because this is per vertex, the shading also gets
			# interpolated across the face instead of sitting flat.
			var shading := vertex.normalized().lerp(normal, FACET_STRENGTH)
			vertices.append(vertex)
			normals.append(shading.normalized())
			uvs.append(source_uvs[corner])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Hollow cube: the 12 edges of the box as chunky bars, merged into one mesh.
## Bars overlap at the corners so the joints read as solid.
static func _build_cube_frame() -> Mesh:
	var bar_x := BoxMesh.new()
	bar_x.size = Vector3(UNIT, BAR, BAR)
	var bar_y := BoxMesh.new()
	bar_y.size = Vector3(BAR, UNIT, BAR)
	var bar_z := BoxMesh.new()
	bar_z.size = Vector3(BAR, BAR, UNIT)

	var offset := UNIT * 0.5 - BAR * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in [-offset, offset]:
		for b in [-offset, offset]:
			st.append_from(bar_x, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, a, b)))
			st.append_from(bar_y, 0, Transform3D(Basis.IDENTITY, Vector3(a, 0.0, b)))
			st.append_from(bar_z, 0, Transform3D(Basis.IDENTITY, Vector3(a, b, 0.0)))
	return st.commit()


## Hollow sphere: three crossed rings on the XZ, XY and YZ planes.
static func _build_sphere_shell() -> Mesh:
	var ring := TorusMesh.new()
	ring.outer_radius = UNIT * 0.5
	ring.inner_radius = UNIT * 0.5 - BAR
	ring.rings = 32
	ring.ring_segments = 8

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(ring, 0, Transform3D.IDENTITY)
	st.append_from(ring, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	st.append_from(ring, 0, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO))
	return st.commit()


static func _build_material(is_black: bool, is_spotted: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PIECE_SHADER
	# Spot colours are picked per body colour: dark blue on white pieces,
	# yellow on black ones, so the pattern carries on either background.
	var base := Color(0.07, 0.07, 0.09) if is_black else Color(0.91, 0.90, 0.87)
	var spot := Color(0.95, 0.78, 0.18) if is_black else Color(0.09, 0.15, 0.45)
	material.set_shader_parameter("base_color", base)
	material.set_shader_parameter("spot_color", spot)
	material.set_shader_parameter("spot_strength", 1.0 if is_spotted else 0.0)
	material.set_shader_parameter("piece_roughness", 0.30 if is_black else 0.40)
	material.set_shader_parameter("piece_specular", 0.55)
	return material
