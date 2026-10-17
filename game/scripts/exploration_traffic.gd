extends Node
## A small game traffic stream on the existing two source-forward road polylines.
const COLORS := [Color(.17,.37,.56),Color(.88,.86,.78),Color(.62,.65,.68),Color(.86,.63,.18),Color(.23,.43,.35),Color(.51,.25,.23)]
var vehicle_count := 0
var extra_vehicles := []
var _host: Node3D

func setup(host: Node3D) -> bool:
	_host=host
	if host.vehicles.size()!=2 or not is_instance_valid(host.traffic):return false
	var packed: PackedScene=load("res://scenes/npc/vehicle.tscn")
	for index in range(2):
		var original: Dictionary=host.traffic_bundle.routes[index]
		for sequence in range(1,3):
			var route: Dictionary=original.duplicate(true)
			# The FIFO owner is a route key, so each extra vehicle needs a distinct key.
			route.id=String(original.id)+"_stream_"+str(sequence)
			host.traffic.routes[route.id]=route
			var body: CharacterBody3D=packed.instantiate()
			body.set_script(preload("res://scripts/traffic/exploration_vehicle.gd"))
			body.name="Vehicle_"+route.id
			body.set_meta("geometry_id","EXP02_"+route.id)
			body.initial_station_m=float(original.length_m)*float(sequence)/3.0
			body.configure(route,host.traffic,host.city)
			host.get_node("Actors/Vehicles").add_child(body)
			host.vehicles.append(body);host.traffic.register_vehicle(body)
			extra_vehicles.append(body)
	for index in range(host.vehicles.size()):_dress(host.vehicles[index],COLORS[index%COLORS.size()])
	vehicle_count=host.vehicles.size()
	print("EXPLORATION_TRAFFIC_READY vehicles=",vehicle_count)
	return true

func refresh_terrain() -> void:
	if not is_instance_valid(_host):return
	for body: CharacterBody3D in _host.vehicles:body.refresh_terrain()
	if is_instance_valid(_host.traffic):_host.traffic.refresh_terrain()

func _material(color: Color,roughness: float=.65) -> StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.albedo_color=color;result.roughness=roughness
	return result

func _box(parent: Node3D,title: String,size: Vector3,point: Vector3,material: Material) -> void:
	var mesh:=BoxMesh.new();mesh.size=size;mesh.material=material
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.position=point
	parent.add_child(node)

func _dress(body: CharacterBody3D,color: Color) -> void:
	var visual: Node3D=body.get_node("Visual")
	for original in visual.get_children():original.visible=false
	var paint:=_material(color,.38)
	var glass:=_material(Color(.12,.21,.26),.25)
	var tire:=_material(Color(.055,.06,.065))
	var lights:=_material(Color(.98,.95,.78))
	var rear:=_material(Color(.65,.08,.06))
	_box(visual,"SedanBody",Vector3(1.76,.54,4.08),Vector3(0,.60,0),paint)
	_box(visual,"Windows",Vector3(1.48,.58,1.92),Vector3(0,1.12,-.05),glass)
	_box(visual,"Roof",Vector3(1.5,.10,1.94),Vector3(0,1.44,-.05),paint)
	for side in [-1.,1.]:
		_box(visual,"Headlight",Vector3(.46,.15,.035),Vector3(side*.56,.66,-2.058),lights)
		_box(visual,"TailLight",Vector3(.40,.15,.035),Vector3(side*.57,.68,2.058),rear)
		for axle in [-1.25,1.25]:
			var wheel:=CylinderMesh.new();wheel.top_radius=.31;wheel.bottom_radius=.31;wheel.height=.17;wheel.radial_segments=12;wheel.material=tire
			var node:=MeshInstance3D.new();node.name="Wheel";node.mesh=wheel;node.position=Vector3(side*.85,.32,axle);node.rotation.z=PI/2.
			visual.add_child(node)
