extends Node3D
## Latest exploration scene only. Articulated clothing follows the retained
## 1.7m controller capsule; meshes never supply movement or collision.
const LEG_LENGTH := .43
const STANDING_ANKLE_Y := .12
const HIP_Y := .978
const ADULT_VISUAL_HEIGHT_M := 1.70
const HEAD_HEIGHT_M := .23
const UPPER_ARM_LENGTH_M := .31
const FOREARM_LENGTH_M := .29
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
var _stance_fraction := .60
var _cycle_distance_m := 1.26
var _gait_speed_mps := 0.0
var _air_tuck := 0.0
var _facility_property := false
var _upper_body: Node3D
var _pelvis: MeshInstance3D
var _hip_pose_y := HIP_Y
var _old_body: MeshInstance3D
var _old_body_visible := true
var _joints: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []
var _hands: Array[MeshInstance3D] = []
var _materials: Dictionary = {}
var _sandbox_action := ""
var _sandbox_remaining_s := 0.0
var _sandbox_duration_s := 0.0
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
	for property: Dictionary in player.get_property_list():
		if String(property.name)=="facility_control":_facility_property=true;break
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
	# Adult-size authored geometry, independently of the untouched safety capsule.
	# The jacket tapers at the waist; the head is no longer nearly a sixth of height.
	var torso:=CylinderMesh.new();torso.top_radius=.205;torso.bottom_radius=.170;torso.height=.46;torso.radial_segments=16
	var jacket:=_mesh(_upper_body,"Torso",torso,Vector3(0,.27,0),"jacket");jacket.scale.z=.67
	_box(_upper_body,"Shirt",Vector3(.14,.37,.018),Vector3(0,.285,-.133),"shirt")
	for side in [-1.0,1.0]:_box(_upper_body,"JacketFront",Vector3(.095,.40,.023),Vector3(side*.117,.27,-.136),"jacket_trim")
	_box(_upper_body,"JacketHem",Vector3(.35,.035,.235),Vector3(0,.055,0),"jacket_trim")
	var neck:=CylinderMesh.new();neck.top_radius=.048;neck.bottom_radius=.052;neck.height=.12;neck.radial_segments=12
	_mesh(_upper_body,"Neck",neck,Vector3(0,.535,0),"skin")
	_box(_upper_body,"ShirtCollar",Vector3(.145,.035,.145),Vector3(0,.505,-.005),"shirt")
	_round(_upper_body,"Head",Vector3(.175,HEAD_HEIGHT_M,.195),Vector3(0,.705,-.005),"skin")
	_round(_upper_body,"Hair",Vector3(.185,.12,.202),Vector3(0,.790,.005),"hair")
	_box(_upper_body,"HairBack",Vector3(.165,.11,.055),Vector3(0,.710,.075),"hair")
	_round(_upper_body,"Nose",Vector3(.035,.043,.046),Vector3(0,.695,-.110),"skin")
	for side in [-1.0,1.0]:
		_round(_upper_body,"Eye",Vector3(.014,.019,.010),Vector3(side*.037,.735,-.099),"eye")
		_round(_upper_body,"Ear",Vector3(.030,.058,.037),Vector3(side*.088,.705,0),"skin")
	_pelvis=_box(self,"Pelvis",Vector3(.32,.15,.22),Vector3(0,HIP_Y,0),"trousers")
	for side_name in ["Left","Right"]:
		var side := -1.0 if side_name=="Left" else 1.0
		var thigh := _joint(self,side_name+"Thigh",Vector3(side*.105,HIP_Y,0))
		_limb(thigh,side_name+"UpperLeg",LEG_LENGTH,.074,"trousers")
		var shin := _joint(thigh,side_name+"Shin",Vector3(0,-LEG_LENGTH,0))
		_round(shin,side_name+"Knee",Vector3(.13,.13,.14),Vector3.ZERO,"trousers")
		_limb(shin,side_name+"LowerLeg",LEG_LENGTH,.060,"trousers")
		var foot := _joint(shin,side_name+"Foot",Vector3(0,-LEG_LENGTH,0))
		_box(foot,side_name+"Shoe",Vector3(.15,.105,.29),Vector3(0,-.057,-.060),"shoes")
		_box(foot,side_name+"ShoeSole",Vector3(.155,.025,.30),Vector3(0,-.102,-.060),"sole")
		_box(foot,side_name+"ShoeLaces",Vector3(.095,.010,.07),Vector3(0,-.001,-.095),"jacket_trim")
		var arm := _joint(self,side_name+"UpperArm",Vector3(side*.235,1.36,0))
		_round(arm,side_name+"Shoulder",Vector3(.108,.12,.115),Vector3(0,-.025,0),"jacket")
		_limb(arm,side_name+"Sleeve",UPPER_ARM_LENGTH_M,.054,"jacket")
		var forearm := _joint(arm,side_name+"Forearm",Vector3(0,-UPPER_ARM_LENGTH_M,0))
		_round(forearm,side_name+"Elbow",Vector3(.088,.10,.095),Vector3.ZERO,"jacket_trim")
		_limb(forearm,side_name+"LowerSleeve",FOREARM_LENGTH_M,.043,"jacket_trim")
		_hands.append(_round(forearm,side_name+"Hand",Vector3(.075,.105,.062),Vector3(0,-FOREARM_LENGTH_M-.025,0),"skin"))

func _rest_pose() -> void:
	walk_weight=0.0;_air_weight=0.0;_run_weight=0.0;cadence_hz=0.0
	_stance_fraction=.60;_cycle_distance_m=1.26;_gait_speed_mps=0.;_air_tuck=0.;_hip_pose_y=HIP_Y
	position=Vector3.ZERO
	_upper_body.position=Vector3(0,.85,0);_upper_body.rotation=Vector3.ZERO
	_pelvis.position.y=HIP_Y
	for side_name: String in ["Left","Right"]:
		(_joints[side_name+"Thigh"] as Node3D).position.y=HIP_Y
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
	var distance := clampf(offset.length(),.06,UPPER_ARM_LENGTH_M+FOREARM_LENGTH_M+.025-.0002)
	var pole := Vector3(side*.8,-.3,.3)
	pole=(pole-direction*pole.dot(direction)).normalized()
	var forearm_reach:=FOREARM_LENGTH_M+.025
	var along := (UPPER_ARM_LENGTH_M*UPPER_ARM_LENGTH_M-forearm_reach*forearm_reach+distance*distance)/(2.0*distance)
	var elbow := arm.position+direction*along+pole*sqrt(maxf(0.,UPPER_ARM_LENGTH_M*UPPER_ARM_LENGTH_M-along*along))
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
	var down := _hip_pose_y-foot.y
	var reach := minf(sqrt(down*down+foot.z*foot.z),LEG_LENGTH*2.0-.002)
	var direction := atan2(-foot.z,down)
	var bend := acos(clampf(reach/(LEG_LENGTH*2.0),.01,1.0))
	var upper := direction+bend
	var lower := direction-bend
	(_joints[side_name+"Thigh"] as Node3D).rotation.x=upper
	(_joints[side_name+"Shin"] as Node3D).rotation.x=lower-upper
	(_joints[side_name+"Foot"] as Node3D).rotation.x=-lower

func _supported_hips(feet: Dictionary) -> void:
	# Standing legs are nearly straight. During locomotion only the pelvis
	# follows the two contact-leg reach limits under the jacket. The torso/head
	# and camera anchor stay level, avoiding the former visible head bob.
	var height:=HIP_Y
	var maximum_reach:=LEG_LENGTH*2.-.002
	for foot: Vector3 in feet.values():
		height=minf(height,foot.y+sqrt(maxf(.01,maximum_reach*maximum_reach-foot.z*foot.z)))
	_hip_pose_y=height;_pelvis.position.y=height
	for side: String in ["Left","Right"]:(_joints[side+"Thigh"] as Node3D).position.y=height

func _gait_foot(side: float,phase: float,reach: float,lift: float) -> Vector3:
	# During stance the ankle travels backwards at a constant body-relative
	# speed. With uncapped distance-driven cadence, that cancels world travel.
	# Cubic swing matches that derivative at both contacts; no impact snap/bob.
	var fraction:=fposmod(phase/TAU,1.0)
	var duty:=clampf(_stance_fraction,.38,.65)
	var foot := Vector3(side*.105,STANDING_ANKLE_Y,0)
	if fraction<duty:foot.z=lerpf(-reach,reach,fraction/duty)
	else:
		var swing:=(fraction-duty)/(1.-duty)
		var tangent:=2.*reach*(1.-duty)/duty
		var t2:=swing*swing;var t3:=t2*swing
		foot.z=(2.*t3-3.*t2+1.)*reach+(t3-2.*t2+swing)*tangent+(-2.*t3+3.*t2)*(-reach)+(t3-t2)*tangent
		foot.y+=pow(sin(swing*PI),2.)*lift
	return foot

func _facility_controlled() -> bool:return bool(player.get("facility_control")) if _facility_property else false

func play_sandbox_action(kind: String,seconds := .4) -> void:
	if kind not in ["punch","flinch"]:return
	_sandbox_action=kind;_sandbox_remaining_s=seconds;_sandbox_duration_s=seconds

func _sandbox_pose(delta: float) -> void:
	if _sandbox_remaining_s<=0. or _sandbox_duration_s<=0.:return
	_sandbox_remaining_s=maxf(0.,_sandbox_remaining_s-delta)
	var phase:=1.0-_sandbox_remaining_s/_sandbox_duration_s
	var weight:=sin(phase*PI)
	if _sandbox_action=="punch":
		_arm_to("Right",Vector3(.24,1.22,-.12-.52*weight))
		_arm_to("Left",Vector3(-.23,1.17,-.25))
	else:_upper_body.rotation.x=.16*weight

func _physics_process(delta: float) -> void:
	if not _ready_avatar or not is_instance_valid(player) or delta<=0.0:return
	var movement: Vector3=player.global_position-_last_position
	_last_position=player.global_position
	measured_displacement_m=Vector2(movement.x,movement.z).length()
	actual_speed_mps=measured_displacement_m/delta
	var facility:=_facility_controlled()
	var adapter_walked:=bool(player.get_meta("exploration_avoidance_adapter",false))
	if facility or (not player.is_physics_processing() and not adapter_walked):
		state="facility" if facility else "transport"
		actual_speed_mps=0.0;measured_displacement_m=0.0
		if facility and not _activity_kind.is_empty():_activity_pose()
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
	_run_weight=lerpf(_run_weight,clampf((actual_speed_mps-1.9)/2.1,0.0,1.0),blend)
	_air_weight=lerpf(_air_weight,0.0 if grounded else 1.0,blend)
	_air_tuck=lerpf(_air_tuck,clampf(player.velocity.y/7.5,0.,1.),blend)
	_stance_fraction=lerpf(.60,.40,_run_weight)
	_cycle_distance_m=lerpf(1.26,1.86,_run_weight)
	cadence_hz=0.0
	if moving:
		var cadence_limit := lerpf(1.65,MAX_CADENCE_HZ,_run_weight)
		var advance := minf(measured_displacement_m/_cycle_distance_m,delta*cadence_limit)
		stride_phase=fmod(stride_phase+advance*TAU,TAU);cadence_hz=advance/delta
		clock+=delta
	_gait_speed_mps=cadence_hz*_cycle_distance_m
	state="air" if not grounded else ("run" if _run_weight>.45 and moving else ("walk" if moving else "idle"))
	var reach := _cycle_distance_m*_stance_fraction*.5*walk_weight
	var lift := lerpf(.075,.21,_run_weight)*walk_weight
	# The limbs carry the gait. A steady head/torso removes the former
	# four-pulses-per-stride bob (8.8Hz at turbo cadence) and lateral sway.
	_upper_body.position=Vector3(0,.85,0)
	_upper_body.rotation.x=-.075*_run_weight*walk_weight-.035*_air_weight
	_upper_body.rotation.z=0.0
	var posed_feet:={}
	for side_name: String in ["Left","Right"]:
		var side := -1.0 if side_name=="Left" else 1.0
		var phase := fmod(stride_phase+(PI if side_name=="Right" else 0.0),TAU)
		var foot := _gait_foot(side,phase,reach,lift)
		foot.z-=.025*(1.0-walk_weight)
		var air_foot := Vector3(side*.105,.15+.18*_air_tuck,(-.10 if side_name=="Left" else .08)*(.5+.5*_air_tuck))
		foot=foot.lerp(air_foot,_air_weight)
		posed_feet[side_name]=foot
	_supported_hips(posed_feet)
	for side_name: String in ["Left","Right"]:
		var side := -1.0 if side_name=="Left" else 1.0
		var foot: Vector3=posed_feet[side_name]
		# IK retains flat shoe soles through stance; only the swing foot lifts.
		_feet[side_name]=foot;_leg_pose(side_name,foot)
		var arm_swing := clampf(foot.z/maxf(reach,.001),-1.,1.)*lerpf(.32,.70,_run_weight)*walk_weight
		var arm := _joints[side_name+"UpperArm"] as Node3D
		var forearm := _joints[side_name+"Forearm"] as Node3D
		arm.rotation=Vector3(lerpf(arm_swing-.04,.48,_air_weight),0,side*.035)
		forearm.rotation=Vector3(lerpf(.14+.72*_run_weight*walk_weight,.50,_air_weight),0,0)
	_last_grounded=grounded
	_sandbox_pose(delta)

func snapshot() -> Dictionary:
	var transforms := {};var feet := {};var body_bounds := AABB();var initialized := false
	for joint_name: String in _joints:transforms[joint_name]=(_joints[joint_name] as Node3D).transform
	for side_name: String in ["Left","Right"]:
		if _joints.has(side_name+"Foot"):feet[side_name]=(_joints[side_name+"Foot"] as Node3D).global_position
	for mesh: MeshInstance3D in _meshes:
		var bounds: AABB=mesh.global_transform*mesh.get_aabb()
		body_bounds=bounds if not initialized else body_bounds.merge(bounds);initialized=true
	return {"ready":_ready_avatar,"state":state,"clock":clock,"stride_phase":stride_phase,"cadence_hz":cadence_hz,"cadence_cap_hz":MAX_CADENCE_HZ,"actual_speed_mps":actual_speed_mps,"measured_displacement_m":measured_displacement_m,"walk_weight":walk_weight,"air_weight":_air_weight,"run_weight":_run_weight,
		"joint_transforms":transforms,"feet_world":feet,"mesh_count":_meshes.size(),"body_bounds":body_bounds,"original_body_hidden":is_instance_valid(_old_body) and not _old_body.visible,"uses_original_physics_capsule":true,"visual_forward":-global_basis.z,"facility_control":_facility_controlled() if is_instance_valid(player) else false,"activity_kind":_activity_kind,"activity_elapsed":_activity_elapsed,"avatar_hands_visible":_hands[0].visible if not _hands.is_empty() else false,
		"authored_adult_height_m":ADULT_VISUAL_HEIGHT_M,"head_height_m":HEAD_HEIGHT_M,"standing_hip_joint_height_m":HIP_Y,"hip_height_m":_hip_pose_y,"head_units":ADULT_VISUAL_HEIGHT_M/HEAD_HEIGHT_M,"stance_fraction":_stance_fraction,"cycle_distance_m":_cycle_distance_m,"represented_gait_speed_mps":_gait_speed_mps,"arcade_speed_excess_mps":maxf(0.,actual_speed_mps-_gait_speed_mps),"motion_scope":"Authored adult proportions and distance-driven stance/swing, not a scanned human or motion capture. Turbo speeds retain bounded cadence and can visibly exceed plausible limb travel."}

func _exit_tree() -> void:
	if is_instance_valid(_old_body):_old_body.visible=_old_body_visible
