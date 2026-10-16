extends Node3D
## A detached opaque game car, not a surveyed shaft. The visit controller owns
## every phase and passenger pose; nothing here advances while a menu is open.
const ORIGIN := Vector3(1100.0,-140.0,0.0)
const DOOR_HALF_WIDTH := .54
const DOOR_TRAVEL := 1.12
var camera: Camera3D
var door_left: MeshInstance3D
var door_right: MeshInstance3D
var floor_label: Label3D
var status_label: Label3D
var stage_label: Label3D
var landing_label: Label3D
var floor_band: MeshInstance3D
var cabin_bounds := AABB()
var bodies: Array[StaticBody3D] = []
var door_open_fraction := 1.0
var _materials: Dictionary = {}
var _camera_rest := Vector3(.30,1.58,1.55)
var _floor_buttons: Array[Dictionary] = []
var _ready_car := false
var roof_index := -1

func setup() -> bool:
	if _ready_car:return true
	name="DetachedElevatorCabin"
	global_position=ORIGIN
	cabin_bounds=AABB(ORIGIN+Vector3(-2.05,-.25,-2.20),Vector3(4.10,3.1,4.4))
	var colors := {"steel":Color(.42,.47,.49),"steel_light":Color(.63,.67,.67),"dark":Color(.045,.065,.075),"floor":Color(.22,.25,.25),"oak":Color(.47,.33,.21),"white":Color(.90,.92,.88),"teal":Color(.16,.80,.72),"button":Color(.28,.33,.34)}
	for key: String in colors:
		var material := StandardMaterial3D.new()
		material.albedo_color=colors[key]
		material.roughness=.34 if key.begins_with("steel") else .72
		material.metallic=.70 if key.begins_with("steel") else .0
		if key=="teal" or key=="white":
			material.emission_enabled=true
			material.emission=colors[key]
			material.emission_energy_multiplier=.55 if key=="teal" else .30
		_materials[key]=material
	for key in ["floor","oak"]:
		var surface := ShaderMaterial.new()
		surface.shader=preload("res://scripts/interior_surface.gdshader")
		surface.set_shader_parameter("surface_kind",0 if key=="floor" else 1)
		surface.set_shader_parameter("base_color",colors[key])
		_materials[key]=surface
	_mesh("CabinFloor",Vector3(4.5,.20,7.8),Vector3(0,-.10,-1.35),"floor",true)
	_mesh("CabinCeiling",Vector3(4.6,.12,7.8),Vector3(0,2.95,-1.35),"steel_light",true)
	_mesh("CabinRearWall",Vector3(4.5,2.96,.14),Vector3(0,1.47,2.32),"steel",true)
	for side in [-1.0,1.0]:
		_mesh("CabinSideWall",Vector3(.14,2.96,7.8),Vector3(side*2.20,1.47,-1.35),"steel",true)
		_mesh("OakWallInset",Vector3(.035,.92,4.3),Vector3(side*2.11,.94,0),"oak")
		for z in [-1.50,0.0,1.50]:_mesh("WallPanelJoint",Vector3(.025,2.65,.014),Vector3(side*2.10,1.47,z),"dark")
		if side<0.0:
			_mesh("CabinHandrail",Vector3(.055,.055,3.8),Vector3(side*1.99,.96,.10),"steel_light")
		else:
			# Leave the full operating-panel Z span clear; a rail in front of
			# the buttons would hide rows even when every button fits the board.
			_mesh("CabinHandrailRightFront",Vector3(.055,.055,.68),Vector3(1.99,.96,-1.46),"steel_light")
			_mesh("CabinHandrailRightRear",Vector3(.055,.055,2.28),Vector3(1.99,.96,.86),"steel_light")
		for z in [-1.4,1.5]:_mesh("RailBracket",Vector3(.13,.035,.035),Vector3(side*2.045,.96,z),"steel_light")
		_mesh("DoorSurround",Vector3(1.05,2.96,.15),Vector3(side*1.66,1.47,-2.39),"oak",true)
		_mesh("DoorJamb",Vector3(.075,2.28,.20),Vector3(side*1.13,1.14,-2.30),"steel_light")
	_mesh("DoorHeader",Vector3(2.26,.68,.17),Vector3(0,2.60,-2.34),"steel")
	door_left=_mesh("DoorLeft",Vector3(1.08,2.24,.075),Vector3(-DOOR_HALF_WIDTH,1.12,-2.35),"steel_light")
	door_right=_mesh("DoorRight",Vector3(1.08,2.24,.075),Vector3(DOOR_HALF_WIDTH,1.12,-2.35),"steel_light")
	_mesh("DoorSill",Vector3(2.26,.014,.23),Vector3(0,.009,-2.33),"steel_light")
	# The open doorway shows a closed landing vestibule. It never reveals
	# intermediate slabs or a skyline outside the detached interior.
	_mesh("LandingRearWall",Vector3(4.5,2.96,.15),Vector3(0,1.47,-5.13),"steel_light",true)
	_mesh("LandingNoticeBack",Vector3(1.9,.72,.035),Vector3(0,1.65,-5.03),"dark")
	landing_label=_label("LandingFloor","1층 · 승강장",Vector3(0,1.65,-4.99),38,.007)
	landing_label.modulate=Color(.91,.95,.91)
	_mesh("FloorIndicatorBack",Vector3(1.8,.45,.04),Vector3(0,2.61,-2.23),"dark")
	floor_label=_label("FloorIndicator","1",Vector3(0,2.64,-2.195),58,.006)
	floor_label.modulate=Color(.41,1.0,.82)
	_mesh("TravelBandBack",Vector3(1.50,.035,.018),Vector3(0,2.405,-2.19),"dark")
	floor_band=_mesh("TravelBand",Vector3(1.0,.035,.020),Vector3(-.75,2.405,-2.17),"teal")
	_mesh("CabinOperatingPanel",Vector3(.045,1.75,.68),Vector3(2.075,1.46,-.70),"dark")
	stage_label=_label("CabinStage","승차 중",Vector3(2.036,2.16,-.70),26,.006,-PI*.5)
	stage_label.modulate=Color(.95,.98,.95)
	status_label=_label("RideStatus","1층 → 2층",Vector3(2.035,1.88,-.70),25,.0055,-PI*.5)
	status_label.modulate=Color(.48,.95,.84)
	var notice := _label("CabinSafetyNotice","자동문\n문에 기대지 마세요",Vector3(-2.08,1.95,-.50),26,.006,PI*.5)
	notice.modulate=Color(.91,.93,.86)
	_mesh("CeilingLight",Vector3(3.6,.025,.40),Vector3(0,2.875,.25),"white")
	var light := OmniLight3D.new();light.name="CabinLight";light.position=Vector3(0,2.55,-.10);light.omni_range=9.;light.light_energy=2.0;light.light_color=Color(1.,.95,.86);light.shadow_enabled=false;add_child(light)
	camera=Camera3D.new();camera.name="CabinCamera";camera.position=_camera_rest;camera.near=.08;camera.far=24.;camera.fov=70.;camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;add_child(camera)
	camera.look_at(to_global(Vector3(.08,1.65,-2.35)),Vector3.UP)
	set_doors(1.0)
	visible=false
	_ready_car=true
	return true

func _mesh(title: String,size: Vector3,point: Vector3,material: String,solid := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new();mesh.name=title
	var shape := BoxMesh.new();shape.size=size;mesh.mesh=shape;mesh.material_override=_materials[material];mesh.position=point;add_child(mesh)
	if solid:
		var body := StaticBody3D.new();body.name=title+"Support";body.position=point;body.collision_layer=1;body.collision_mask=0
		var collision := CollisionShape3D.new();var box := BoxShape3D.new();box.size=size;collision.shape=box;body.add_child(collision);add_child(body);bodies.append(body)
	return mesh

func _label(title: String,text: String,point: Vector3,font_size: int,pixel_size: float,yaw := 0.0) -> Label3D:
	var label := Label3D.new();label.name=title;label.text=text;label.position=point;label.rotation.y=yaw;label.font_size=font_size;label.pixel_size=pixel_size;label.outline_size=1;label.outline_modulate=Color(.03,.05,.06);label.no_depth_test=false;add_child(label)
	return label

func configure_floors(count: int) -> void:
	if _floor_buttons.size()==count:return
	for row in _floor_buttons:
		row.mesh.queue_free();row.label.queue_free()
	_floor_buttons.clear()
	var rows := maxi(1,int(ceil(float(count)/3.0)))
	# The operating panel spans Y .585..2.335. Its upper part is reserved for
	# status text; every floor button fits inside this lower Y .72..1.51 region.
	var spacing := minf(.15,.79/float(maxi(1,rows-1)))
	var button_height := minf(.085,spacing*.78)
	var number_pixel_size := minf(.0035,button_height/23.0)
	for index in range(count):
		var point := Vector3(2.035,1.51-float(index/3)*spacing,-.94+float(index%3)*.24)
		var mesh := _mesh("FloorButton%d"%(index+1),Vector3(.025,button_height,.13),point,"button")
		var label := _label("FloorButtonText%d"%(index+1),"R" if index==count-1 else str(index+1),point+Vector3(-.018,0,0),18,number_pixel_size,-PI*.5)
		label.modulate=Color(.85,.88,.84)
		_floor_buttons.append({"mesh":mesh,"label":label})

func passenger_point() -> Vector3:return to_global(Vector3(-.70,.08,.25))

func set_doors(fraction: float) -> void:
	door_open_fraction=clampf(fraction,0.0,1.0)
	door_left.position.x=-DOOR_HALF_WIDTH-DOOR_TRAVEL*door_open_fraction
	door_right.position.x=DOOR_HALF_WIDTH+DOOR_TRAVEL*door_open_fraction

func begin(from_floor: int,target_floor: int,count: int) -> void:
	roof_index=count-1
	configure_floors(count)
	visible=true
	set_doors(1.0)
	update_state("boarding",from_floor,target_floor,float(from_floor),0.,0.,1.,false)
	camera.make_current()

func update_state(phase: String,from_floor: int,target_floor: int,floor_value: float,progress: float,speed: float,door_fraction: float,returning: bool) -> void:
	set_doors(door_fraction)
	var direction := "↑" if target_floor>floor_value+.015 else "↓" if target_floor<floor_value-.015 else ""
	if phase in ["arriving","opening","exit_hold","blocked"]:direction=""
	var display_index := int(round(floor_value))
	floor_label.text="%s %s"%[direction,"옥상" if display_index==roof_index else "%02d"%(display_index+1)]
	landing_label.text="%s · 승강장"%_destination_text(target_floor if phase in ["opening","exit_hold"] else from_floor)
	var phase_text: String={"boarding":"승차 중","closing":"문이 닫힙니다","accelerating":"출발합니다","cruising":"이동 중","decelerating":"도착합니다","arriving":"정차 중","opening":"문이 열립니다","exit_hold":"내리세요","blocked":"안전 대기"}.get(phase,"엘리베이터")
	stage_label.text=phase_text
	status_label.text="%s → %s\n%s"%[_destination_text(from_floor),_destination_text(target_floor),"안전한 층으로 복귀" if returning else "승강장 확인 중" if phase=="blocked" else ""]
	var band_width := maxf(.025,1.5*clampf(progress,0.,1.))
	floor_band.scale.x=band_width
	floor_band.position.x=-.75+band_width*.5
	for index in range(_floor_buttons.size()):
		_floor_buttons[index].mesh.material_override=_materials["teal"] if index==target_floor else _materials["button"]
	# Small physically bounded eye movement hints at starting/braking; it never
	# moves the passenger or exposes the outside scene through a clipping plane.
	var settle := -.018*sin(PI*clampf(speed/8.0,0.,1.)) if phase=="accelerating" else .012*sin(PI*clampf(speed/8.0,0.,1.)) if phase=="decelerating" else 0.0
	camera.position=_camera_rest+Vector3.UP*settle

func _destination_text(index: int) -> String:return "옥상" if index==roof_index else "%d층"%(index+1)

func finish() -> void:
	camera.clear_current(false)
	visible=false

func snapshot() -> Dictionary:
	return {"visible":visible,"camera_current":camera.current,"camera_position":camera.global_position,"door_open_fraction":door_open_fraction,"door_left_position":door_left.position,"door_right_position":door_right.position,"floor_text":floor_label.text,"status_text":stage_label.text,"passenger_point":passenger_point(),"bounds":cabin_bounds,"support_bodies":bodies.size(),"layout_basis":"detached_game_car_not_surveyed_shaft"}
