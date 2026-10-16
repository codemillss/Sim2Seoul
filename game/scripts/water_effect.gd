extends Node3D
## Small finite mesh bursts: visible splash droplets and expanding water rings.
var splash_count := 0
var ripple_count := 0
var _bursts: Array[Dictionary] = []
var _elapsed := 0.0
var _drop_material: StandardMaterial3D
var _ring_material: StandardMaterial3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_drop_material = StandardMaterial3D.new();_drop_material.albedo_color = Color(.65,.90,.97,.88)
	_drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;_drop_material.roughness = .12
	_ring_material = StandardMaterial3D.new();_ring_material.albedo_color = Color(.83,.96,.96,.80)
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA;_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func emit_splash(point: Vector3, impact_speed_mps: float) -> void:
	if not point.is_finite():return
	while _bursts.size()>=4:
		var expired: Dictionary = _bursts.pop_front()
		expired.node.queue_free()
	var burst := Node3D.new();burst.name = "Splash%d"%splash_count;burst.position = point;add_child(burst)
	var drops: Array[Dictionary] = []
	var strength := clampf(impact_speed_mps*.12,.65,1.6)
	for index in range(12):
		var angle := TAU*float(index)/12.0
		var mesh := SphereMesh.new();mesh.radius = .035+.012*float(index%3);mesh.height = mesh.radius*2.0;mesh.radial_segments = 8;mesh.rings = 4
		var visual := MeshInstance3D.new();visual.name = "Droplet%d"%index;visual.mesh = mesh;visual.material_override = _drop_material;burst.add_child(visual)
		drops.append({"node":visual,"velocity":Vector3(cos(angle)*(1.1+.3*(index%2))*strength,2.1+.2*(index%4),sin(angle)*(1.1+.3*(index%2))*strength)})
	var rings: Array[MeshInstance3D] = []
	for index in range(2):
		var visual := MeshInstance3D.new();visual.name = "Ripple%d"%index
		var mesh := TorusMesh.new();mesh.inner_radius = .46;mesh.outer_radius = .50;mesh.rings = 24;mesh.ring_segments = 6
		visual.mesh = mesh;visual.material_override = _ring_material;visual.position.y = .012+index*.006;visual.scale = Vector3.ONE*.15
		burst.add_child(visual);rings.append(visual)
	_bursts.append({"node":burst,"age":0.0,"drops":drops,"rings":rings})
	splash_count += 1;ripple_count += 2

func _process(delta: float) -> void:
	_elapsed += delta
	for index in range(_bursts.size()-1,-1,-1):
		var row: Dictionary = _bursts[index]
		row.age = float(row.age)+delta
		var t: float = row.age
		for drop: Dictionary in row.drops:
			var node: MeshInstance3D = drop.node
			var velocity: Vector3 = drop.velocity
			node.position = velocity*t+Vector3.DOWN*(4.9*t*t)
			node.visible = t<.85 and node.position.y>=-.04
			node.scale = Vector3.ONE*maxf(.08,1.0-t*.75)
		for ring_index in range(row.rings.size()):
			var ring: MeshInstance3D = row.rings[ring_index]
			var radius := maxf(.05,(t-float(ring_index)*.15)*2.2)
			ring.scale = Vector3(radius,1.0,radius)
			ring.visible = t>float(ring_index)*.15 and t<1.35
		if t>1.5:
			row.node.queue_free();_bursts.remove_at(index)

func snapshot() -> Dictionary:
	var meshes := 0
	for row: Dictionary in _bursts:meshes += row.drops.size()+row.rings.size()
	return {"splash_count":splash_count,"ripple_count":ripple_count,"active_splashes":_bursts.size(),"mesh_nodes":meshes,"elapsed":_elapsed,"visual_kind":"finite_mesh_droplets_and_expanding_surface_rings"}
