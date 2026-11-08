@tool
extends EditorNode3DGizmoPlugin
## Draws Populate's zones in the 3D view: a see-through disc in the zone's colour with a clear rim, drawn
## over everything so it shows through rocks and sand, and a handle on the rim that sizes it as it's dragged.
## Each kind's look in Zone.KINDS can stripe the disc, or leave it nearly empty inside a thick dashed rim, so
## kinds alike in colour over the water still look different. Clicking the rim selects the zone, to move it
## with Godot's own arrows. It lives only in the editor.

const Zone := preload("populate_zone.gd")

const DISC_ALPHA := 0.3
## A dashed zone's disc, nearly see-through so that it reads as an empty ring.
const EMPTY_ALPHA := 0.1
const STRIPE_ALPHA := 0.55
## How many straight bits a rim is drawn with. A dashed rim draws every other one.
const RIM_STEPS := 64
## How wide a dashed rim is, as a share of the radius, so it looks the same at any size.
const DASH_WIDTH := 0.05
## How many bands a striped disc is cut across into, every other one a stripe, the outer two included; and
## how many straight bits each stripe's curved ends are drawn with.
const BANDS := 9
const BAND_STEPS := 8

var undo: EditorUndoRedoManager


func _init() -> void:
	for kind: Zone.Kind in Zone.KINDS:
		var colour: Color = Zone.KINDS[kind]["colour"]
		add_material("disc %d" % kind, overlay_material(Color(colour, disc_alpha_of(Zone.KINDS[kind]["look"]))))
		add_material("rim %d" % kind, overlay_material(colour))
		add_material("stripes %d" % kind, overlay_material(Color(colour, STRIPE_ALPHA)))
	create_handle_material("handles")


## How see-through a disc of `look` is drawn.
static func disc_alpha_of(look: Zone.Look) -> float:
	return EMPTY_ALPHA if look == Zone.Look.DASHED else DISC_ALPHA


## Unshaded and drawn over everything: the water's own screen pass draws over anything see-through that
## tests depth.
static func overlay_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if colour.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.no_depth_test = true
	material.disable_fog = true
	material.render_priority = Material.RENDER_PRIORITY_MAX - 1
	material.albedo_color = colour
	return material


func _get_gizmo_name() -> String:
	return "Smart Fellas Populate zone"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() == Zone


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var zone := gizmo.get_node_3d()
	var radius: float = zone.radius
	var look: Zone.Look = Zone.KINDS[zone.kind]["look"]
	var disc := disc_of(radius)
	gizmo.add_mesh(mesh_of(disc), get_material("disc %d" % zone.kind, gizmo))
	if look == Zone.Look.STRIPED:
		gizmo.add_mesh(mesh_of(stripes_of(radius)), get_material("stripes %d" % zone.kind, gizmo))
	if look == Zone.Look.DASHED:
		gizmo.add_mesh(mesh_of(dashes_of(radius)), get_material("rim %d" % zone.kind, gizmo))
	gizmo.add_lines(rim_of(radius, look), get_material("rim %d" % zone.kind, gizmo))
	gizmo.add_collision_segments(rim_of(radius, Zone.Look.PLAIN))
	gizmo.add_collision_triangles(triangles_of(disc))
	gizmo.add_handles(PackedVector3Array([Vector3(radius, 0.0, 0.0)]), get_material("handles", gizmo), [])


## A flat disc of `radius` round the middle, as triangles.
static func disc_of(radius: float) -> PackedVector3Array:
	var disc := PackedVector3Array()
	for step in RIM_STEPS:
		disc.append_array([Vector3.ZERO, _on_rim(radius, step), _on_rim(radius, step + 1)])
	return disc


## The rim of a disc of `radius`, as pairs of points: all the way round, or every other bit if `look` is
## dashed.
static func rim_of(radius: float, look: Zone.Look) -> PackedVector3Array:
	var rim := PackedVector3Array()
	var every := 2 if look == Zone.Look.DASHED else 1
	for step in range(0, RIM_STEPS, every):
		rim.append_array([_on_rim(radius, step), _on_rim(radius, step + 1)])
	return rim


## The thick dashes round the inside of a disc of `radius`'s rim, as triangles: every other rim bit, DASH_WIDTH
## of the radius wide.
static func dashes_of(radius: float) -> PackedVector3Array:
	var dashes := PackedVector3Array()
	var inner := radius * (1.0 - DASH_WIDTH)
	for step in range(0, RIM_STEPS, 2):
		var corners := [_on_rim(inner, step), _on_rim(radius, step), _on_rim(radius, step + 1), _on_rim(inner, step + 1)]
		dashes.append_array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]])
	return dashes


## Stripes across a disc of `radius`, slanting from corner to corner and cut off at the rim, as triangles.
static func stripes_of(radius: float) -> PackedVector3Array:
	var across := Vector3(1.0, 0.0, 1.0).normalized()
	var along := Vector3(-1.0, 0.0, 1.0).normalized()
	var width := 2.0 * radius / BANDS
	var stripes := PackedVector3Array()
	for band in range(0, BANDS, 2):
		for step in BAND_STEPS:
			var near := -radius + width * (band + float(step) / BAND_STEPS)
			var far := -radius + width * (band + float(step + 1) / BAND_STEPS)
			var near_half := sqrt(maxf(radius * radius - near * near, 0.0))
			var far_half := sqrt(maxf(radius * radius - far * far, 0.0))
			var corners := [
				across * near - along * near_half, across * near + along * near_half,
				across * far + along * far_half, across * far - along * far_half,
			]
			stripes.append_array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]])
	return stripes


static func _on_rim(radius: float, step: int) -> Vector3:
	var angle := TAU * step / RIM_STEPS
	return Vector3(cos(angle), 0.0, sin(angle)) * radius


static func mesh_of(points: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func triangles_of(points: PackedVector3Array) -> TriangleMesh:
	var triangles := TriangleMesh.new()
	triangles.create_from_faces(points)
	return triangles


func _get_handle_name(_gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> String:
	return "Size"


func _get_handle_value(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().radius


## The rim follows the mouse across the flat the zone lies on.
func _set_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var zone := gizmo.get_node_3d()
	var flat := Plane(Vector3.UP, zone.global_position.y)
	var at: Variant = flat.intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if at != null:
		zone.radius = Zone.radius_toward(zone, at)


func _commit_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var zone := gizmo.get_node_3d()
	if cancel:
		zone.radius = restore
		return
	Zone.sized(zone, restore, undo)
