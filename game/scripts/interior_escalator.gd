extends Node3D
## Authored 1F↔2F↔3F↔4F commercial escalators in the source-sized SFC plate.
## Smooth conveyor supports carry the unchanged player capsule through actual
## floor openings. Moving visible treads do not introduce collidable risers.
const BUILDING_ID := "osm:way:332565592:building"
const SPEED_MPS := .70
const LANE_WIDTH := 1.24
const LANE_SPACING := 1.72
const TREAD_PITCH := .34
var room: Node3D
var opening := Rect2()
var reservation := AABB()
var connecting_levels: Array[int] = []
var pair_count := 0
var lower_z := 0.0
var upper_z := 0.0
var left_x := 0.0
var rise := 0.0
var run := 0.0
var travel_length := 0.0
var elapsed := 0.0
var supports: Array[StaticBody3D] = []
var steps: Array[Dictionary] = []
var rail_markers: Array[Dictionary] = []
var _built := false

func configure(owner_room: Node3D) -> bool:
	room=owner_room
	if String(room.spec.get("id",""))!=BUILDING_ID or room.floor_count<2 or room.width<22.0 or room.depth<30.0:return false
	rise=room.floor_height;run=rise*1.95;travel_length=Vector2(run,rise).length()
	pair_count=mini(3,int(room.floor_count)-1)
	for level in range(pair_count+1):connecting_levels.append(level)
	left_x=room.width*.5-7.15
	lower_z=room.depth*.5-10.0;upper_z=lower_z-run
	opening=Rect2(left_x-LANE_WIDTH*.5-.24,upper_z-.12,LANE_SPACING+LANE_WIDTH+.48,run+.24)
	# Legacy pair-0 callers retain the original footprint and reservation.
	reservation=reservation_for_level(0)
	process_mode=Node.PROCESS_MODE_PAUSABLE
	return true

func opening_for_level(level: int) -> Rect2:
	return opening if level>=1 and level<=pair_count else Rect2()

func reservation_for_level(level: int) -> AABB:
	if level<0 or level>pair_count:return AABB()
	# Include a capsule-width walking route beside the guarded opening, so a
	# passenger can reach the next stacked pair without a scenario teleport.
	return AABB(Vector3(opening.position.x-1.05,float(level)*rise-.2,upper_z-2.0),Vector3(opening.size.x+2.1,rise+.4,run+4.0))

func build() -> void:
	if _built:return
	for lower_level in range(pair_count):_build_pair(lower_level)
	_built=true;_animate()

func _build_pair(lower_level: int) -> void:
	var base := float(lower_level)*rise
	var lower_floor := lower_level+1;var upper_floor := lower_level+2
	for lane in range(2):
		var x := lane_x(lane);var direction := 1.0 if lane==0 else -1.0
		var suffix := "" if lower_level==0 else "_%dF_%dF"%[lower_floor,upper_floor]
		var body := StaticBody3D.new();body.name=("EscalatorUpSupport" if lane==0 else "EscalatorDownSupport")+suffix
		body.collision_layer=1;body.collision_mask=0
		body.set_meta("geometry_id","EXP16_interior_"+String(body.name));body.set_meta("escalator_lane",lane);body.set_meta("escalator_lower_level",lower_level)
		body.constant_linear_velocity=Vector3(0,rise,-run).normalized()*SPEED_MPS*direction
		var shape := ConvexPolygonShape3D.new();var half := LANE_WIDTH*.5
		shape.points=PackedVector3Array([
			Vector3(x-half,base-.18,lower_z),Vector3(x+half,base-.18,lower_z),Vector3(x-half,base,lower_z),Vector3(x+half,base,lower_z),
			Vector3(x-half,base+rise-.18,upper_z),Vector3(x+half,base+rise-.18,upper_z),Vector3(x-half,base+rise,upper_z),Vector3(x+half,base+rise,upper_z)])
		var collision := CollisionShape3D.new();collision.shape=shape;body.add_child(collision);room.add_child(body)
		room.bodies.append(body);supports.append(body)
		# Flat, supported slabs on both ends let the conveyor release naturally.
		for top in [false,true]:
			var y := base+(rise if top else 0.0);var z := upper_z-.55 if top else lower_z+.55
			room._box("EscalatorComb",Vector3(LANE_WIDTH,.025,1.1),Vector3(x,y-.014,z),"steel")
			for line in range(12):room._box("EscalatorCombGroove",Vector3(.025,.006,.85),Vector3(x-.53+line*.095,y+.003,z),"dark")
		var count := int(ceil(travel_length/TREAD_PITCH))
		for index in range(count):
			var tread := _mesh("MovingEscalatorTread",Vector3(LANE_WIDTH-.04,.12,run/float(count)+.016),"stairs")
			var nosing := _mesh("MovingTreadYellowEdge",Vector3(LANE_WIDTH-.06,.018,.027),"light")
			steps.append({"tread":tread,"nosing":nosing,"lane":lane,"lower_level":lower_level,"phase":float(index)/float(count)})
		for side in [-1.0,1.0]:
			var edge: float=x+float(side)*(LANE_WIDTH*.5+.085)
			var middle := Vector3(edge,base+rise*.5+.54,(lower_z+upper_z)*.5)
			var tilt := Basis(Vector3.RIGHT,atan2(rise,run))
			room._box("EscalatorBalustrade",Vector3(.10,1.04,travel_length),middle,"clear_glass",true,tilt)
			room._box("EscalatorHandrail",Vector3(.12,.09,travel_length+.05),middle+Vector3.UP*.54,"dark",false,tilt)
			for end in [0,1]:
				var y := base+(.95 if end==0 else rise+.95);var z := lower_z+.43 if end==0 else upper_z-.43
				room._box("EscalatorHandrailReturn",Vector3(.12,.12,.90),Vector3(edge,y,z),"dark")
			for index in range(10):
				var marker := _mesh("MovingHandrailSeam",Vector3(.14,.025,.085),"steel")
				rail_markers.append({"mesh":marker,"lane":lane,"lower_level":lower_level,"x":edge,"phase":float(index)/10.0})
		var lower_text := "%d층 → %d층  ↑"%[lower_floor,upper_floor] if lane==0 else "%d층 → %d층  ↓"%[upper_floor,lower_floor]
		var lower_label: Label3D=room._sign("EscalatorDirection%d_%d"%[lower_level,lane],lower_text,Vector3(x,base+1.45,lower_z+.85),25)
		lower_label.pixel_size=.0036;lower_label.outline_size=2;lower_label.set_meta("escalator_lower_level",lower_level)
		var upper_text := "↑  %d층 도착"%upper_floor if lane==0 else "↓  %d층 내려가기"%lower_floor
		var upper_label: Label3D=room._sign("EscalatorDirectionUpper%d_%d"%[lower_level,lane],upper_text,Vector3(x,base+rise+1.45,upper_z-.85),25,false)
		upper_label.pixel_size=.0036;upper_label.outline_size=2;upper_label.set_meta("escalator_lower_level",lower_level)
	# Long-edge guards protect each slab opening. At intermediate floors the
	# next pair starts at the near edge: a transverse rail there would block it.
	var upper_y := base+rise
	for x in [opening.position.x,opening.end.x]:room._rail("EscalatorOpeningGuard%d"%lower_level,Vector3(x,upper_y,upper_z-.08),Vector3(x,upper_y,lower_z+.08))
	if lower_level==pair_count-1:room._rail("EscalatorOpeningFrontGuard%d"%lower_level,Vector3(opening.position.x,upper_y,lower_z+.12),Vector3(opening.end.x,upper_y,lower_z+.12))
	var guide: Label3D=room._sign("CommercialEscalatorGuide%d"%lower_level,"상업 라운지 · %d층 ↔ %d층\n왼쪽 올라가기 / 오른쪽 내려오기 · 걸어서 탑승"%[lower_floor,upper_floor],Vector3(left_x+.86,base+2.55,lower_z+2.0),27)
	guide.pixel_size=.0032;guide.outline_size=2

func lane_x(lane: int) -> float:return left_x+float(lane)*LANE_SPACING

func endpoint(lane: int,top: bool,apron := 1.05,lower_level := 0) -> Vector3:
	var base := float(clampi(lower_level,0,maxi(0,pair_count-1)))*rise
	return room.to_global(Vector3(lane_x(lane),base+(rise+.08 if top else .08),upper_z-apron if top else lower_z+apron))

func _mesh(title: String,size: Vector3,material: String) -> MeshInstance3D:
	var node := MeshInstance3D.new();node.name=title;var box := BoxMesh.new();box.size=size;node.mesh=box
	node.material_override=room._materials[material];node.set_meta("role",title);add_child(node);return node

func _process(delta: float) -> void:
	if not _built or not room.visible:return
	elapsed+=delta;_animate()

func _animate() -> void:
	for row: Dictionary in steps:
		var direction := 1.0 if int(row.lane)==0 else -1.0
		var t := fposmod(float(row.phase)+elapsed*SPEED_MPS/travel_length*direction,1.0)
		var point := Vector3(lane_x(int(row.lane)),float(row.lower_level)*rise+rise*t-.075,lerpf(lower_z,upper_z,t))
		row.tread.position=point;row.nosing.position=point+Vector3(0,.062,-.13)
	for row: Dictionary in rail_markers:
		var direction := 1.0 if int(row.lane)==0 else -1.0
		var t := fposmod(float(row.phase)+elapsed*SPEED_MPS/travel_length*direction,1.0)
		row.mesh.position=Vector3(float(row.x),float(row.lower_level)*rise+rise*t+1.075,lerpf(lower_z,upper_z,t))

func snapshot() -> Dictionary:
	var velocity: Array=[]
	for support: StaticBody3D in supports:velocity.append(support.constant_linear_velocity)
	var pairs: Array=[]
	for lower_level in range(pair_count):
		pairs.append({"lower_level":lower_level,"upper_level":lower_level+1,"up_lower":endpoint(0,false,1.05,lower_level),"up_upper":endpoint(0,true,1.05,lower_level),"down_upper":endpoint(1,true,1.05,lower_level),"down_lower":endpoint(1,false,1.05,lower_level)})
	return {"building_id":BUILDING_ID,"authored_not_surveyed":true,"connecting_floors":connecting_levels.duplicate(),"connecting_levels":connecting_levels.duplicate(),"pair_count":pair_count,"pairs":pairs,"opening":opening,"reservation":reservation,"rise_m":rise,"run_m":run,"speed_mps":SPEED_MPS,"elapsed":elapsed,"tread_count":steps.size(),"moving_handrail_seams":rail_markers.size(),"support_count":supports.size(),"support_velocities":velocity,"up_lower":endpoint(0,false),"up_upper":endpoint(0,true),"down_upper":endpoint(1,true),"down_lower":endpoint(1,false),"carrier_method":"unchanged CharacterBody capsule on actual sloped StaticBody conveyor support"}
