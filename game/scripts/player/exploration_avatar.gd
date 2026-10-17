extends Node3D
## Latest exploration scene only. Articulated clothing follows the retained
## 1.7m controller capsule; meshes never supply movement or collision.
const LEG_LENGTH := .36
const STANDING_ANKLE_Y := .12
const HIP_Y := .79
const MAX_CADENCE_HZ := 2.2
var player: CharacterBody3D
var state := "idle"
var clock := 0.0
var stride_phase := 0.0
var cadence_hz := 0.0
var actual_speed_mps := 0.0
var measured_displacement_m := 0.0
var walk_weight := 0.0
var _ready_avatar := false
var _last_position := Vector3.ZERO
var _last_grounded := true
var _air_weight := 0.0
var _run_weight := 0.0
var _upper_body: Node3D
var _old_body: MeshInstance3D
var _old_body_visible := true
var _joints: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []
var _hands: Array[MeshInstance3D] = []
var _materials: Dictionary = {}
var _activity_kind := ""
var _activity_elapsed := 0.0
var _feet := {"Left":Vector3(-.105,STANDING_ANKLE_Y,-.025),"Right":Vector3(.105,STANDING_ANKLE_Y,-.025)}

func setup(controlled_player: CharacterBody3D) -> bool:
	if _ready_avatar or not is_instance_valid(controlled_player):return false
	var visual := controlled_player.get_node_or_null("Visual") as Node3D
	var original := controlled_player.get_node_or_null("Visual/Body") as MeshInstance3D
	if visual==null or original==null:return false
	player=controlled_player;name="ExplorationAvatar"
	if get_parent()==null:visual.add_child(self)
	elif get_parent()!=visual:reparent(visual,false)
	transform=Transform3D.IDENTITY
	process_mode=Node.PROCESS_MODE_PAUSABLE
	process_physics_priority=2
	_old_body=original;_old_body_visible=original.visible;original.visible=false
	_last_position=player.global_position;_last_grounded=player.is_on_floor()
	_make_materials();_build_body();_rest_pose()
	_ready_avatar=true
	return true

func _make_materials() -> void:
	var colors := {"jacket":Color(.13,.24,.31),"jacket_trim":Color(.23,.37,.42),"shirt":Color(.82,.84,.80),"trousers":Color(.27,.31,.34),"skin":Color(.76,.55,.39),"hair":Color(.10,.09,.08),"shoes":Color(.84,.86,.83),"sole":Color(.18,.23,.25),"eye":Color(.08,.11,.12)}
	for key: String in colors:
		var material := StandardMaterial3D.new();material.albedo_color=colors[key];material.roughness=.84
		_materials[key]=material

func _mesh(parent: Node3D,title: String,shape: Mesh,at: Vector3,material: String) -> MeshInstance3D:
	var node := MeshInstance3D.new();node.name=title;node.mesh=shape;node.position=at;node.material_override=_materials[material]
	node.set_meta("avatar_part",title);parent.add_child(node);_meshes.append(node);return node

func _box(parent: Node3D,title: String,size: Vector3,at: Vector3,material: String) -> MeshInstance3D:
	var mesh := BoxMesh.new();mesh.size=size;return _mesh(parent,title,mesh,at,material)

func _round(parent: Node3D,title: String,size: Vector3,at: Vector3,material: String) -> MeshInstance3D:
	var mesh := SphereMesh.new();mesh.radius=.5;mesh.height=1.0;mesh.radial_segments=16;mesh.rings=8
	var node := _mesh(parent,title,mesh,at,material);node.scale=size;return node

func _limb(parent: Node3D,title: String,length: float,radius: float,material: String) -> MeshInstance3D:
	var mesh := CapsuleMesh.new();mesh.radius=radius;mesh.height=length;mesh.radial_segments=12;mesh.rings=5
	return _mesh(parent,title,mesh,Vector3(0,-length*.5,0),material)

func _joint(parent: Node3D,title: String,at: Vector3) -> Node3D:
	var joint := Node3D.new();joint.name=title;joint.position=at;joint.set_meta("avatar_joint",title)
	parent.add_child(joint);_joints[title]=joint;return joint

func _build_body() -> void:
	_upper_body=_joint(self,"UpperBody",Vector3(0,.85,0))
	_box(_upper_body,"Torso",Vector3(.40,.43,.25),Vector3(0,.225,0),"jacket")
	_box(_upper_body,"Shirt",Vector3(.16,.36,.018),Vector3(0,.235,-.133),"shirt")
	for side in [-1.0,1.0]:_box(_upper_body,"JacketFront",Vector3(.12,.39,.023),Vector3(side*.135,.225,-.144),"jacket_trim")
	_box(_upper_body,"JacketHem",Vector3(.41,.045,.26),Vector3(0,.025,0),"jacket_trim")
	_round(_upper_body,"Neck",Vector3(.13,.14,.13),Vector3(0,.47,0),"skin")
	_round(_upper_body,"Head",Vector3(.235,.285,.235),Vector3(0,.65,-.005),"skin")
	_round(_upper_body,"Hair",Vector3(.245,.15,.24),Vector3(0,.745,.005),"hair")
	_box(_upper_body,"HairBack",Vector3(.215,.13,.07),Vector3(0,.655,.085),"hair")
	_round(_upper_body,"Nose",Vector3(.043,.05,.05),Vector3(0,.64,-.124),"skin")
	for side in [-1.0,1.0]:_round(_upper_body,"Eye",Vector3(.018,.024,.012),Vector3(side*.047,.682,-.111),"eye")
	_box(self,"Pelvis",Vector3(.34,.17,.235),Vector3(0,.80,0),"trousers")
	for side_name in ["Left","Right"]:
		var side := -1.0 if side_name=="Left" else 1.0
		var thigh := _joint(self,side_name+"Thigh",Vector3(side*.105,HIP_Y,0))
		_limb(thigh,side_name+"UpperLeg",LEG_LENGTH,.074,"trousers")
		var shin := _joint(thigh,side_name+"Shin",Vector3(0,-LEG_LENGTH,0))
		_limb(shin,side_name+"LowerLeg",LEG_LENGTH,.060,"trousers")
		var foot := _joint(shin,side_name+"Foot",Vector3(0,-LEG_LENGTH,0))
		_box(foot,side_name+"Shoe",Vector3(.15,.105,.29),Vector3(0,-.057,-.060),"shoes")
		_box(foot,side_name+"ShoeSole",Vector3(.155,.025,.30),Vector3(0,-.102,-.060),"sole")
		_box(foot,side_name+"ShoeLaces",Vector3(.095,.010,.07),Vector3(0,-.001,-.095),"jacket_trim")
		var arm := _joint(self,side_name+"UpperArm",Vector3(side*.252,1.25,0))
		_limb(arm,side_name+"Sleeve",.27,.060,"jacket")
		var forearm := _joint(arm,side_name+"Forearm",Vector3(0,-.27,0))
		_limb(forearm,side_name+"LowerSleeve",.24,.050,"jacket_trim")
		_hands.append(_round(forearm,side_name+"Hand",Vector3(.085,.105,.075),Vector3(0,-.265,0),"skin"))

func _rest_pose() -> void:
	walk_weight=0.0;_air_weight=0.0;_run_weight=0.0;cadence_hz=0.0
	position=Vector3.ZERO
	_upper_body.position=Vector3(0,.85,0);_upper_body.rotation=Vector3.ZERO
	for side_name: String in ["Left","Right"]:
		var side := -1.0 if side_name=="Left" else 1.0
		_feet[side_name]=Vector3(side*.105,STANDING_ANKLE_Y,-.025)
		_leg_pose(side_name,_feet[side_name])
		(_joints[side_name+"UpperArm"] as Node3D).rotation=Vector3(-.04,0,side*.035)
		(_joints[side_name+"Forearm"] as Node3D).rotation=Vector3(.14,0,0)

func set_activity(kind: String,elapsed: float) -> void:
	if kind!=_activity_kind and is_instance_valid(player):
		_last_position=player.global_position;actual_speed_mps=0.0;measured_displacement_m=0.0
	_activity_kind=kind;_activity_elapsed=elapsed
	for hand: MeshInstance3D in _hands:hand.visible=kind not in ["eat","weights"]
	if not _ready_avatar:return
	if kind.is_empty():_rest_pose();return
	_activity_pose()

func _arm_to(side_name: String,target: Vector3) -> void:
	var arm := _joints[side_name+"UpperArm"] as Node3D
	var forearm := _joints[side_name+"Forearm"] as Node3D
	var side := -1.0 if side_name=="Left" else 1.0
	var offset := target-arm.position
	var direction := offset.normalized()
	var distance := clampf(offset.length(),.06,.27+.265-.0002)
	var pole := Vector3(side*.8,-.3,.3)
	pole=(pole-direction*pole.dot(direction)).normalized()
	var along := (.27*.27-.265*.265+distance*distance)/(2.0*distance)
	var elbow := arm.position+direction*along+pole*sqrt(maxf(0.,.27*.27-along*along))
	var grip := arm.position+direction*distance
	arm.basis=Basis(Quaternion(Vector3.DOWN,(elbow-arm.position).normalized()))
	forearm.basis=arm.basis.inverse()*Basis(Quaternion(Vector3.DOWN,(grip-elbow).normalized()))

func _activity_pose() -> void:
	_rest_pose();state="facility"
	var elapsed := _activity_elapsed
	match _activity_kind:
		"eat":
			var bite_phase := fmod(elapsed/1.2,1.0)
			var lift := sin(clampf((bite_phase-.1)/.7,0.,1.)*PI)
			_arm_to("Right",Vector3(.515-lift*.41,1.12+lift*.37,-.38+lift*.40))
			_arm_to("Left",Vector3(.07,1.02,-.33))
			_upper_body.position.y+=sin(elapsed*PI)*.008
		"weights":
			var curl := (1.-cos(elapsed*TAU/2.0))*.5
			for side_name: String in ["Left","Right"]:
				var side := -1.0 if side_name=="Left" else 1.0
				_arm_to(side_name,Vector3(side*.43,.76+curl*.60,-.12-curl*.14))
		"treadmill":
			# The physical passenger stays on the validated deck. These legs use
			# the belt's 6km/h activity cadence, independently of ordinary travel.
			position.y=-.055
			var phase := fmod(elapsed*1.45*TAU,TAU)
			_upper_body.rotation.x=-.035
			for side_name: String in ["Left","Right"]:
				var side := -1.0 if side_name=="Left" else 1.0
				var cycle := fmod(phase+(PI if side_name=="Right" else 0.0),TAU)
				var foot := _gait_foot(side,cycle,.16,.09)
				_feet[side_name]=foot;_leg_pose(side_name,foot)
				(_joints[side_name+"UpperArm"] as Node3D).rotation.x=-cos(cycle)*.35-.04
				(_joints[side_name+"Forearm"] as Node3D).rotation.x=.28
		"cycle":
			# Display-only seated pelvis; the original physical capsule stays clear
			# at the machine's validated floor marker throughout the session.
			position.y=-.14;_upper_body.rotation.x=-.13
			for side_name: String in ["Left","Right"]:
				var side := -1.0 if side_name=="Left" else 1.0
				var phase := elapsed*TAU+(0.0 if side<0 else PI)
				var foot := Vector3(side*.22,.31+sin(phase)*.17+.06,-.25+cos(phase)*.17-.02)
				_feet[side_name]=foot;_leg_pose(side_name,foot)
				_arm_to(side_name,Vector3(side*.25,1.02,-.49))
		"rowing":
			var stroke := (1.0-cos(elapsed*TAU/2.4))*.5
			position=Vector3(0,-.44,.38*stroke)
			_upper_body.rotation.x=lerpf(-.20,.15,stroke)
			for side_name: String in ["Left","Right"]:
				var side := -1.0 if side_name=="Left" else 1.0
				var foot := Vector3(side*.22,.75,-.52-.38*stroke)
				_feet[side_name]=foot;_leg_pose(side_name,foot)
				_arm_to(side_name,Vector3(side*.245,1.02+.16*stroke,-.52+.04*stroke))

		"shower":_upper_body.rotation.z=sin(elapsed*2.1)*.025

func _leg_pose(side_name: String,foot: Vector3) -> void:
	var down := HIP_Y-foot.y
	var reach := minf(sqrt(down*down+foot.z*foot.z),LEG_LENGTH*2.0-.002)
	var direction := atan2(-foot.z,down)
	var bend := acos(clampf(reach/(LEG_LENGTH*2.0),.01,1.0))
	var upper := direction+bend
	var lower := direction-bend
	(_joints[side_name+"Thigh"] as Node3D).rotation.x=upper
	(_joints[side_name+"Shin"] as Node3D).rotation.x=lower-upper
	(_joints[side_name+"Foot"] as Node3D).rotation.x=-lower

func _gait_foot(side: float,phase: float,reach: float,lift: float) -> Vector3:
	# Continuous turnarounds and a zero-speed toe-off/landing avoid the
	# abrupt foot reversals of a triangular stride, without lifting stance.
	var foot := Vector3(side*.105,STANDING_ANKLE_Y,-cos(phase)*reach)
	if phase>=PI:
		var arch := sin(phase-PI)
		foot.y+=arch*arch*lift
	return foot

func _physics_process(delta: float) -> void:
	if not _ready_avatar or not is_instance_valid(player) or delta<=0.0:return
	var movement: Vector3=player.global_position-_last_position
	_last_position=player.global_position
	measured_displacement_m=Vector2(movement.x,movement.z).length()
	actual_speed_mps=measured_displacement_m/delta
	if player.facility_control or not player.is_physics_processing():
		state="facility" if player.facility_control else "transport"
		actual_speed_mps=0.0;measured_displacement_m=0.0
		if player.facility_control and not _activity_kind.is_empty():_activity_pose()
		else:_rest_pose()
		return
	# Region changes and recovery are transitions, never one giant stride.
	if movement.length()>2.0:
		state="idle";actual_speed_mps=0.0;measured_displacement_m=0.0;_rest_pose();return
	var grounded: bool=player.is_on_floor()
	var moving := grounded and actual_speed_mps>.08 and Vector2(player.velocity.x,player.velocity.z).length()>.08
	var blend := 1.0-exp(-delta*14.0)
	walk_weight=lerpf(walk_weight,minf(1.0,actual_speed_mps/.75) if moving else 0.0,blend)
	if walk_weight<.001:walk_weight=0.0
	_run_weight=lerpf(_run_weight,clampf((actual_speed_mps-3.2)/3.5,0.0,1.0),blend)
	_air_weight=lerpf(_air_weight,0.0 if grounded else 1.0,blend)
	cadence_hz=0.0
	if moving:
		var nominal_stride := lerpf(1.00,1.42,_run_weight)
		var cadence_limit := lerpf(1.65,MAX_CADENCE_HZ,_run_weight)
		var advance := minf(measured_displacement_m/nominal_stride,delta*cadence_limit)
		stride_phase=fmod(stride_phase+advance*TAU,TAU);cadence_hz=advance/delta
		clock+=delta
	state="air" if not grounded else ("run" if _run_weight>.45 and moving else ("walk" if moving else "idle"))
	var reach := lerpf(.17,.25,_run_weight)*walk_weight
	var lift := lerpf(.09,.17,_run_weight)*walk_weight
	# The limbs carry the gait. A steady head/torso removes the former
	# four-pulses-per-stride bob (8.8Hz at turbo cadence) and lateral sway.
	_upper_body.position=Vector3(0,.85,0)
	_upper_body.rotation.x=-.075*_run_weight*walk_weight-.035*_air_weight
	_upper_body.rotation.z=0.0
	for side_name: String in ["Left","Right"]:
		var side := -1.0 if side_name=="Left" else 1.0
		var phase := fmod(stride_phase+(PI if side_name=="Right" else 0.0),TAU)
		var foot := _gait_foot(side,phase,reach,lift)
		foot.z-=.025*(1.0-walk_weight)
		var air_foot := Vector3(side*.105,.22+(.06 if side_name=="Left" else 0.0),-.11 if side_name=="Left" else .10)
		foot=foot.lerp(air_foot,_air_weight)
		# IK retains flat shoe soles through stance; only the swing foot lifts.
		_feet[side_name]=foot;_leg_pose(side_name,foot)
		var arm_swing := -cos(phase)*lerpf(.38,.80,_run_weight)*walk_weight
		var arm := _joints[side_name+"UpperArm"] as Node3D
		var forearm := _joints[side_name+"Forearm"] as Node3D
		arm.rotation=Vector3(lerpf(arm_swing-.04,.48,_air_weight),0,side*.035)
		forearm.rotation=Vector3(lerpf(.14+.45*_run_weight*walk_weight,.50,_air_weight),0,0)
	_last_grounded=grounded

func snapshot() -> Dictionary:
	var transforms := {};var feet := {};var body_bounds := AABB();var initialized := false
	for joint_name: String in _joints:transforms[joint_name]=(_joints[joint_name] as Node3D).transform
	for side_name: String in ["Left","Right"]:
		if _joints.has(side_name+"Foot"):feet[side_name]=(_joints[side_name+"Foot"] as Node3D).global_position
	for mesh: MeshInstance3D in _meshes:
		var bounds: AABB=mesh.global_transform*mesh.get_aabb()
		body_bounds=bounds if not initialized else body_bounds.merge(bounds);initialized=true
	return {"ready":_ready_avatar,"state":state,"clock":clock,"stride_phase":stride_phase,"cadence_hz":cadence_hz,"cadence_cap_hz":MAX_CADENCE_HZ,"actual_speed_mps":actual_speed_mps,"measured_displacement_m":measured_displacement_m,"walk_weight":walk_weight,"air_weight":_air_weight,"run_weight":_run_weight,
		"joint_transforms":transforms,"feet_world":feet,"mesh_count":_meshes.size(),"body_bounds":body_bounds,"original_body_hidden":is_instance_valid(_old_body) and not _old_body.visible,"uses_original_physics_capsule":true,"visual_forward":-global_basis.z,"facility_control":player.facility_control if is_instance_valid(player) else false,"activity_kind":_activity_kind,"activity_elapsed":_activity_elapsed,"avatar_hands_visible":_hands[0].visible if not _hands.is_empty() else false}

func _exit_tree() -> void:
	if is_instance_valid(_old_body):_old_body.visible=_old_body_visible
