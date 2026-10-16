extends Node3D
## Authored interiors use a source-sized floor plate, not a surveyed room plan.
## Local +Z is the front entrance. Every level has a continuous U stair route.
var spec: Dictionary = {}
var width := 16.0
var depth := 20.0
var floor_height := 3.6
var floor_count := 1
var bodies: Array[StaticBody3D] = []
var floor_bodies: Array[StaticBody3D] = []
var people: Array[Node3D] = []
var interior_bounds := AABB()
var stair_width := 1.75
var stair_run := 3.6
var stair_left := 0.0
var stair_back := 0.0
var stair_front := 0.0
var stair_mid_back := 0.0
var active_floor := 0
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _people_state: Array[Dictionary] = []
var _time := 0.0
var _ready_space := false
var detail_kit: RefCounted

func setup(building: Dictionary, origin: Vector3) -> bool:
	if _ready_space or not origin.is_finite():return false
	spec = building.duplicate(true)
	width = float(spec.get("width",16.0))
	depth = float(spec.get("depth",20.0))
	floor_height = float(spec.get("floor_height",3.6))
	floor_count = int(spec.get("floor_count",1))
	if not is_finite(width) or not is_finite(depth) or not is_finite(floor_height):return false
	if width<12.0 or depth<16.0 or floor_height<3.0 or floor_height>6.0 or floor_count<1 or floor_count>60:return false
	position = origin
	name = "SourceSizedInterior"
	# The portal observes E while paused; the room and walkers obey the menu pause.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	stair_run = maxf(3.3,floor_height*.92)
	stair_left = -width*.5+.70
	stair_back = -depth*.5+.65
	stair_mid_back = stair_back+1.40
	stair_front = stair_mid_back+stair_run
	interior_bounds = AABB(origin+Vector3(-width*.5+.32,-.35,-depth*.5+.32),Vector3(width-.64,floor_height*floor_count+.65,depth-.64))
	_make_materials()
	detail_kit = preload("res://scripts/interior_detail_kit.gd").new()
	detail_kit.setup(self)
	_build_shell()
	for level in range(floor_count):
		_build_floor(level)
		if level<floor_count-1:_build_stairs(level)
		_build_elevator(level)
		_build_furniture(level)
		_build_lighting(level)
	detail_kit.finish()
	_flush_batches()
	_make_people()
	_ready_space = true
	return true

func _make_materials() -> void:
	var colors := {"floor":Color(.76,.76,.70),"wall":Color(.89,.88,.82),"ceiling":Color(.84,.85,.81),"wood":Color(.43,.30,.19),"dark":Color(.16,.22,.23),"steel":Color(.51,.57,.57),"stairs":Color(.66,.67,.62),"glass":Color(.23,.37,.41),"seat":Color(.24,.40,.33),"book_red":Color(.53,.20,.15),"book_green":Color(.22,.38,.26),"book_blue":Color(.19,.30,.47),"book_cream":Color(.79,.69,.46),"light":Color(.99,.96,.86),"stripe":Color(.28,.39,.37),"skin":Color(.71,.48,.34),"hair":Color(.12,.10,.09),"coat0":Color(.27,.37,.52),"coat1":Color(.52,.31,.25),"coat2":Color(.28,.43,.34),"coat3":Color(.56,.49,.29)}
	for key: String in colors:
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[key]
		material.roughness = .83
		if key=="light":
			material.emission_enabled = true
			material.emission = Color(.97,.91,.73)
			material.emission_energy_multiplier = .8
		_materials[key] = material
		if key in ["floor","wood","wall","seat"]:
			var surface := ShaderMaterial.new()
			surface.shader = preload("res://scripts/interior_surface.gdshader")
			surface.set_shader_parameter("base_color",colors[key])
			surface.set_shader_parameter("surface_kind",{"floor":0,"wood":1,"wall":2,"seat":3}[key])
			_materials[key] = surface

func _box(title: String, size: Vector3, point: Vector3, material: String, solid := false, basis := Basis.IDENTITY) -> StaticBody3D:
	if not _batches.has(material):_batches[material] = []
	var transforms: Array = _batches[material]
	transforms.append(Transform3D(basis*Basis.from_scale(size),point))
	if not solid:return null
	var body := StaticBody3D.new()
	body.name = title
	body.position = point
	body.basis = basis
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("geometry_id","EXP04_interior_"+title)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	bodies.append(body)
	return body

func _sign(title: String, text: String, point: Vector3, font_size := 42, face_front := true) -> Label3D:
	var sign := Label3D.new()
	sign.name = title
	sign.text = text
	sign.position = point
	sign.font_size = font_size
	sign.pixel_size = .012
	sign.outline_size = 3
	sign.modulate = Color(.12,.22,.21)
	sign.outline_modulate = Color(.95,.94,.87)
	if not face_front:sign.rotation.y = PI
	add_child(sign)
	return sign

func _build_shell() -> void:
	var height := floor_height*floor_count
	_box("WestWall",Vector3(.24,height,depth+.4),Vector3(-width*.5-.12,height*.5,0),"wall",true)
	_box("EastWall",Vector3(.24,height,depth+.4),Vector3(width*.5+.12,height*.5,0),"wall",true)
	_box("RearWall",Vector3(width,height,.24),Vector3(0,height*.5,-depth*.5-.12),"wall",true)
	_box("FrontWall",Vector3(width,height,.24),Vector3(0,height*.5,depth*.5+.12),"wall",true)
	_box("Roof",Vector3(width+.4,.24,depth+.4),Vector3(0,height+.12,0),"ceiling",true)
	# Opaque entry glazing encloses the detached interior scene completely.
	_box("ExitDoor",Vector3(3.2,2.65,.08),Vector3(0,1.325,depth*.5-.06),"glass")
	for x in [-1.65,0.0,1.65]:_box("ExitDoorFrame",Vector3(.07,2.75,.12),Vector3(x,1.375,depth*.5-.13),"steel")
	_box("ExitDoorLintel",Vector3(3.4,.1,.12),Vector3(0,2.75,depth*.5-.13),"steel")
	_sign("ExitSign","출입구 · E 나가기",Vector3(0,2.98,depth*.5-.23),32,false)

func _build_floor(level: int) -> void:
	var y := level*floor_height
	var floor_body: StaticBody3D
	if level==0:
		floor_body = _box("Floor0",Vector3(width,.20,depth),Vector3(0,y-.1,0),"floor",true)
	else:
		# Cut the complete stairwell out of upper slabs, including the headroom
		# above both flights. The common front landing joins the rest of the floor.
		var hole_left := stair_left-.15
		var hole_right := stair_left+stair_width*2.0+.40
		var hole_back := stair_back
		var hole_front := stair_front+.12
		var east_size := width*.5-hole_right
		floor_body = _box("Floor%dEast"%level,Vector3(east_size,.20,depth),Vector3(hole_right+east_size*.5,y-.1,0),"floor",true)
		var west_size := hole_left+width*.5
		_box("Floor%dWest"%level,Vector3(west_size,.20,depth),Vector3(-width*.5+west_size*.5,y-.1,0),"floor",true)
		var rear_depth := hole_back+depth*.5
		_box("Floor%dRear"%level,Vector3(hole_right-hole_left,.20,rear_depth),Vector3((hole_left+hole_right)*.5,y-.1,-depth*.5+rear_depth*.5),"floor",true)
		var front_depth := depth*.5-hole_front
		_box("Floor%dFront"%level,Vector3(hole_right-hole_left,.20,front_depth),Vector3((hole_left+hole_right)*.5,y-.1,hole_front+front_depth*.5),"floor",true)
		# The open long edge has a handrail; the front remains a walkable entrance.
		_rail("StairwellGuard%d"%level,Vector3(hole_right,y,hole_back+.2),Vector3(hole_right,y,hole_front-.25))
	floor_bodies.append(floor_body)
	var title := String(spec.get("title","건물"))
	_sign("FloorTitle%d"%level,title+" · %d층"%(level+1),Vector3(minf(width*.12,3.0),y+floor_height*.70,-depth*.5+.15),48)
	_sign("StairSign%d"%level,"계단 ↑ ↓",Vector3(stair_left+stair_width+.12,y+2.05,stair_front+1.35),30)
	# A broad, low contrast floor stripe makes the route visible without blocking it.
	_box("CirculationStripe",Vector3(.045,.004,depth-2.4),Vector3(0,y+.002,0),"stripe")

func _ramp(title: String, x: float, start_z: float, end_z: float, bottom_y: float, top_y: float) -> void:
	var half := stair_width*.5
	var body := StaticBody3D.new()
	body.name = title
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("geometry_id","EXP04_interior_"+title)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(x-half,bottom_y-.18,start_z),Vector3(x+half,bottom_y-.18,start_z),
		Vector3(x-half,bottom_y,start_z),Vector3(x+half,bottom_y,start_z),
		Vector3(x-half,top_y-.18,end_z),Vector3(x+half,top_y-.18,end_z),
		Vector3(x-half,top_y,end_z),Vector3(x+half,top_y,end_z)])
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	bodies.append(body)
	# Visual treads follow a smooth, physically walkable support underneath.
	# Their tops sit at or slightly below the ramp so the capsule never climbs risers.
	var steps := int(ceil((top_y-bottom_y)/.14))
	var dz := (end_z-start_z)/float(steps)
	for step in range(steps):
		var step_y := (top_y-bottom_y)*float(step)/float(steps)
		var tread_height := (top_y-bottom_y)/float(steps)+.025
		_box(title+"Tread",Vector3(stair_width,tread_height,absf(dz)+.012),Vector3(x,bottom_y+step_y-tread_height*.5-.025,start_z+dz*(float(step)+.5)),"stairs")
		_box(title+"Nosing",Vector3(stair_width,.023,.035),Vector3(x,bottom_y+step_y-.012,start_z+dz*float(step)),"steel")

func _rail(title: String, from: Vector3, to: Vector3) -> void:
	var difference := to-from
	var length := difference.length()
	if length<.1:return
	var middle := (from+to)*.5
	var orientation := Basis.looking_at(difference.normalized(),Vector3.UP)
	_box(title+"Top",Vector3(.055,.065,length),middle+Vector3.UP*1.05,"steel",true,orientation)
	var posts := maxi(2,int(ceil(length/1.3)))
	for index in range(posts+1):
		var point := from.lerp(to,float(index)/float(posts))
		_box(title+"Post",Vector3(.045,1.02,.045),point+Vector3.UP*.51,"steel",true)

func _build_stairs(level: int) -> void:
	var y := level*floor_height
	var half := floor_height*.5
	var left_x := stair_left+stair_width*.5
	var right_x := stair_left+stair_width*1.5+.25
	_ramp("Stair%dFlightA"%level,left_x,stair_front,stair_mid_back,y,y+half)
	_ramp("Stair%dFlightB"%level,right_x,stair_mid_back,stair_front,y+half,y+floor_height)
	_box("Stair%dMiddleLanding"%level,Vector3(stair_width*2.0+.25,.18,1.44),Vector3(stair_left+stair_width+.125,y+half-.09,stair_back+.70),"stairs",true)
	# Front slabs already form each complete top/bottom landing.
	_rail("Stair%dLeftOuter"%level,Vector3(stair_left+.02,y,stair_front),Vector3(stair_left+.02,y+half,stair_mid_back))
	_rail("Stair%dLeftInner"%level,Vector3(stair_left+stair_width-.02,y,stair_front+.03),Vector3(stair_left+stair_width-.02,y+half,stair_mid_back))
	_rail("Stair%dRightOuter"%level,Vector3(stair_left+stair_width*2.0+.23,y+half,stair_mid_back),Vector3(stair_left+stair_width*2.0+.23,y+floor_height,stair_front))
	_rail("Stair%dRightInner"%level,Vector3(stair_left+stair_width+.27,y+half,stair_mid_back),Vector3(stair_left+stair_width+.27,y+floor_height,stair_front))
	_rail("Stair%dMiddleBack"%level,Vector3(stair_left+.03,y+half,stair_back+.08),Vector3(stair_left+stair_width*2.0+.22,y+half,stair_back+.08))

func _build_elevator(level: int) -> void:
	var y := level*floor_height
	var x := -width*.5+2.2
	var z := depth*.5-.13
	_box("ElevatorDoor",Vector3(2.15,2.55,.10),Vector3(x,y+1.275,z),"steel")
	_box("ElevatorSeam",Vector3(.025,2.55,.035),Vector3(x,y+1.275,z-.07),"dark")
	for side in [-1.0,1.0]:_box("ElevatorFrame",Vector3(.12,2.7,.18),Vector3(x+side*1.14,y+1.35,z-.03),"dark")
	_box("ElevatorLintel",Vector3(2.4,.12,.18),Vector3(x,y+2.69,z-.03),"dark")
	_box("ElevatorCall",Vector3(.15,.30,.10),Vector3(x+1.43,y+1.18,z-.10),"dark")
	_sign("ElevatorSign%d"%level,"엘리베이터 · %d층"%(level+1),Vector3(x,y+2.96,z-.14),25,false)
	_box("ElevatorWaitingPad",Vector3(2.1,.005,1.55),Vector3(x,y+.003,z-1.40),"stripe")

func _build_furniture(level: int) -> void:
	detail_kit.build_level(level)

func _shelf(point: Vector3) -> void:
	_box("ShelfBack",Vector3(.12,1.95,2.25),point+Vector3(0,.975,0),"wood",true)
	for end in [-1.0,1.0]:_box("ShelfSide",Vector3(.60,1.95,.08),point+Vector3(-.25,.975,end*1.12),"wood")
	for row in range(4):
		var y := .13+row*.54
		_box("ShelfBoard",Vector3(.60,.065,2.25),point+Vector3(-.25,y,0),"wood")
		if row==3:continue
		for book in range(7):
			var colors := ["book_red","book_green","book_blue","book_cream"]
			_box("Book",Vector3(.34,.34+float(book%3)*.035,.20),point+Vector3(-.25,y+.22,-.94+book*.30),colors[(book+row)%4])

func _build_lighting(level: int) -> void:
	var y := level*floor_height
	# Lights are enabled only on the occupied floor to bound Forward+ light cost.
	var count := mini(4,maxi(2,int(depth/12.0)))
	for index in range(count):
		var z := lerpf(-depth*.32,depth*.30,float(index)/float(count-1))
		var light := OmniLight3D.new()
		light.name = "Floor%dLight%d"%[level,index]
		light.position = Vector3(width*.13,y+floor_height-.45,z)
		light.omni_range = maxf(width,depth)*.75
		light.light_energy = 2.4
		light.light_color = Color(1.0,.95,.85)
		light.shadow_enabled = false
		light.set_meta("floor_index",level)
		light.visible = level==0
		add_child(light)
		_box("CeilingFixture",Vector3(minf(3.0,width*.2),.055,1.0),Vector3(width*.13,y+floor_height-.06,z),"light")

func _flush_batches() -> void:
	for key: String in _batches:
		var transforms: Array = _batches[key]
		var batch := MultiMeshInstance3D.new()
		batch.name = "Interior_"+key
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var unit := BoxMesh.new()
		unit.size = Vector3.ONE
		multimesh.mesh = unit
		multimesh.instance_count = transforms.size()
		for index in range(transforms.size()):multimesh.set_instance_transform(index,transforms[index])
		batch.multimesh = multimesh
		batch.material_override = _materials[key]
		add_child(batch)
	_batches.clear()

func _person_part(parent: Node3D, title: String, size: Vector3, point: Vector3, material: String) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = title
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.position = point
	visual.material_override = _materials[material]
	parent.add_child(visual)
	return visual

func _make_people() -> void:
	for index in range(4):
		var person := Node3D.new()
		person.name = "InteriorWalker%d"%index
		person.set_meta("purpose","authored_indoor_walker")
		add_child(person)
		_person_part(person,"Torso",Vector3(.40,.57,.24),Vector3(0,1.05,0),"coat%d"%index)
		_person_part(person,"Head",Vector3(.25,.27,.24),Vector3(0,1.49,0),"skin")
		_person_part(person,"Hair",Vector3(.27,.09,.26),Vector3(0,1.64,0),"hair")
		var legs: Array[Node3D] = []
		var arms: Array[Node3D] = []
		for side in [-1.0,1.0]:
			var leg := Node3D.new();leg.position = Vector3(side*.115,.76,0);person.add_child(leg)
			_person_part(leg,"Leg",Vector3(.14,.68,.17),Vector3(0,-.34,0),"dark")
			_person_part(leg,"Shoe",Vector3(.16,.10,.27),Vector3(0,-.70,-.035),"hair")
			legs.append(leg)
			var arm := Node3D.new();arm.position = Vector3(side*.26,1.28,0);person.add_child(arm)
			_person_part(arm,"Arm",Vector3(.13,.55,.15),Vector3(0,-.275,0),"coat%d"%index)
			arms.append(arm)
		people.append(person)
		_people_state.append({"legs":legs,"arms":arms,"distance":float(index)*4.3,"speed":.72+float(index)*.06})
	_update_people(0.0)

func set_active_floor(level: int) -> void:
	var next := clampi(level,0,floor_count-1)
	if next==active_floor:return
	active_floor = next
	if detail_kit:detail_kit.set_active_floor(next)
	for child in get_children():
		if child is OmniLight3D:
			var light: OmniLight3D = child
			light.visible = absi(int(light.get_meta("floor_index",-10))-active_floor)<=1
	_update_people(0.0)

func interior_snapshot() -> Dictionary:
	return detail_kit.snapshot() if detail_kit else {}

func _process(delta: float) -> void:
	if not _ready_space or not visible:return
	_time += delta
	_update_people(delta)

func _update_people(delta: float) -> void:
	var route := [Vector3(.30,0,depth*.26),Vector3(.30,0,-depth*.22),Vector3(1.00,0,-depth*.22),Vector3(1.00,0,depth*.26)]
	var total := (depth*.48+.70)*2.0
	for index in range(people.size()):
		var state: Dictionary = _people_state[index]
		state.distance = fposmod(float(state.distance)+float(state.speed)*delta,total)
		var remaining := float(state.distance)
		for segment in range(route.size()):
			var start: Vector3 = route[segment]
			var finish: Vector3 = route[(segment+1)%route.size()]
			var length := start.distance_to(finish)
			if remaining<=length:
				people[index].position = start.lerp(finish,remaining/length)+Vector3.UP*(active_floor*floor_height+.02)
				var direction := finish-start
				people[index].rotation.y = atan2(-direction.x,-direction.z)
				break
			remaining -= length
		var swing := sin(_time*6.0+float(index))*0.40
		var legs: Array = state.legs
		var arms: Array = state.arms
		legs[0].rotation.x = swing;legs[1].rotation.x = -swing
		arms[0].rotation.x = -swing*.7;arms[1].rotation.x = swing*.7

func floor_spawn(level: int) -> Vector3:
	return to_global(Vector3(0,float(clampi(level,0,floor_count-1))*floor_height+.08,depth*.5-3.5))

func elevator_point(level: int) -> Vector3:
	return to_global(Vector3(-width*.5+2.2,float(clampi(level,0,floor_count-1))*floor_height+.08,depth*.5-1.65))

func exit_point() -> Vector3:
	return to_global(Vector3(0,.08,depth*.5-.85))

func floor_index_at(point: Vector3) -> int:
	return clampi(int(floor((to_local(point).y+.12)/floor_height)),0,floor_count-1)

func stair_path(from_floor: int, ascending := true) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not ascending:
		if from_floor<=0 or from_floor>=floor_count:return result
		result = stair_path(from_floor-1,true)
		result.reverse()
		return result
	if from_floor<0 or from_floor>=floor_count-1:return result
	var base := from_floor*floor_height+.08
	var left_x := stair_left+stair_width*.5
	var right_x := stair_left+stair_width*1.5+.25
	result.append(to_global(Vector3(left_x,base,stair_front+.90)))
	var samples := maxi(5,int(ceil(stair_run/.65)))
	for index in range(samples+1):
		var t := float(index)/float(samples)
		result.append(to_global(Vector3(left_x,base+t*floor_height*.5,lerpf(stair_front,stair_mid_back,t))))
	result.append(to_global(Vector3(left_x,base+floor_height*.5,stair_mid_back-.65)))
	result.append(to_global(Vector3(right_x,base+floor_height*.5,stair_mid_back-.65)))
	for index in range(samples+1):
		var t := float(index)/float(samples)
		result.append(to_global(Vector3(right_x,base+floor_height*.5+t*floor_height*.5,lerpf(stair_mid_back,stair_front,t))))
	result.append(to_global(Vector3(right_x,base+floor_height,stair_front+.90)))
	return result
