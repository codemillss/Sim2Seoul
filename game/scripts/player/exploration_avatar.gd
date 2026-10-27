extends Node3D
## Latest exploration scene only. Articulated clothing follows the retained
## 1.7m controller capsule; meshes never supply movement or collision.
const HUMAN_SURFACES := preload("res://scripts/player/human_surface_meshes.gd")
const TEXTURED_SURFACE := preload("res://scripts/player/textured_human_surface.gd")
const ACTIVITY_DIMENSIONS := preload("res://scripts/player/human_activity_dimensions.gd")
const GAIT_SUPPORT := preload("res://scripts/player/human_gait_support.gd")
const COMBAT_POSES := preload("res://scripts/player/human_combat_poses.gd")
const TORSO_ROWS := [[.025,.160,.113,.106,0.],[.055,.174,.119,.114,0.],[.130,.170,.124,.119,0.],[.225,.178,.135,.121,0.],[.335,.197,.141,.121,0.],[.430,.205,.125,.111,0.],[.490,.206,.109,.101,0.],[.525,.205,.092,.085,0.],[.543,.164,.071,.066,0.],[.558,.061,.048,.045,0.]]
const LEG_LENGTH := .43
const STANDING_ANKLE_Y := .12
const HIP_Y := .978
const ADULT_VISUAL_HEIGHT_M := 1.70
const HEAD_HEIGHT_M := .23
const UPPER_ARM_LENGTH_M := .31
const FOREARM_LENGTH_M := .29
const MAX_CADENCE_HZ := 2.2
const WALK_CYCLE_DISTANCE_M := 1.10
const RUN_CYCLE_DISTANCE_M := 1.75
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
var _sandbox_guarding := false
var _sandbox_guard_weight := 0.0
var _sandbox_authored_pose: Dictionary={}
var _activity_kind := ""
var _activity_elapsed := 0.0
var _swim_mesh_defaults: Array[Dictionary]=[]
var _textured_surface: Node3D
var _pose_proxy_only:=false
var _gait_ankle_center_z: Dictionary={"Left":0.,"Right":0.}
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
	_pose_proxy_only=bool(player.get_meta("pose_proxy_only",false))
	if not _pose_proxy_only:
		_textured_surface=TEXTURED_SURFACE.new();add_child(_textured_surface)
		var requested:=String(player.get_meta("human_model_id",""))
		if requested not in ["SeoulResident_M01","SeoulResident_F01","Male_Adult_04","Female_Adult_07"]:
			var gender:=String(player.get_meta("human_gender","")).to_lower()
			requested="SeoulResident_F01" if gender=="female" or (gender!="male" and not player.has_method("set_facility_control") and absi(String(player.name).hash())%3==0) else "SeoulResident_M01"
		var requested_profile:=String(player.get_meta("human_body_profile","standard"))
		if requested_profile not in TEXTURED_SURFACE.BODY_PROFILES:requested_profile="standard"
		if not _textured_surface.setup(self,requested,requested_profile):_hide_pose_proxies();return false
		player.set_meta("human_model_id",_textured_surface.model_id);player.set_meta("human_body_profile",requested_profile)
		_fit_gait_to_native(_textured_surface.rig)
	_hide_pose_proxies()
	return true

func _hide_pose_proxies() -> void:
	# Retain public contact nodes and wardrobe material handles, but render the
	# weighted human only. Old geometric hands/cloth never become a fallback.
	for mesh: MeshInstance3D in _meshes:mesh.visible=false
	for side: String in ["Left","Right"]:
		var foot: Node3D=_joints.get(side+"Foot")
		if is_instance_valid(foot):
			for child: Node in foot.get_children():
				if child is Node3D and "SwimBareFoot" in String(child.name):child.visible=false
	var detail:=_upper_body.get_node_or_null("GameShopWornClothing") as Node3D
	if detail!=null:detail.visible=false

func _process(_delta: float) -> void:
	_hide_pose_proxies()

func textured_model_snapshot(refresh_actual_bounds:=true) -> Dictionary:
	if is_instance_valid(_textured_surface):return _textured_surface.snapshot(refresh_actual_bounds)
	return {"loaded":false,"error":"pose_proxy_fixture" if _pose_proxy_only else "weighted_human_unavailable","model_id":"","visible_mesh_count":0,"skeleton_bone_count":0,"surface_texture_uv_ready":false,"actual_visible_bounds_m":AABB(),"actual_height_m":0.,"normalized_rest_height_m":0.,"rig_contact_metrics":{},"legacy_geometry_rendered":false}

func set_authored_model(model_id: String,body_profile: String="standard") -> bool:
	# Replace presentation resources only. Reuse the same player, capsule,
	# invisible game joints, wardrobe handles and camera interpolation owner.
	if model_id not in ["SeoulResident_M01","SeoulResident_F01"] or body_profile not in TEXTURED_SURFACE.BODY_PROFILES or not _ready_avatar or not is_instance_valid(_textured_surface):return false
	if _textured_surface.model_id==model_id and _textured_surface.body_profile==body_profile:return true
	if _facility_controlled() or not _activity_kind.is_empty() or _textured_surface._swimwear_active or _sandbox_remaining_s>0.:return false
	var old: Node3D=_textured_surface;var values: Dictionary={};var poses: Dictionary={}
	for key: String in ["state","walk_weight","_air_weight","_run_weight","cadence_hz","_stance_fraction","_cycle_distance_m","_gait_speed_mps","_air_tuck","_hip_pose_y","_feet"]:
		var value: Variant=get(key);values[key]=value.duplicate(true) if value is Dictionary else value
	var nodes: Array=[self,_upper_body,_pelvis,find_child("Head",true,false)]
	nodes.append_array(_joints.values());nodes.append_array(_hands)
	for node: Node3D in nodes:
		if is_instance_valid(node):poses[node]=node.transform
	_rest_pose()
	# The camera has moved drawable branches under its RenderProxy. Retain that
	# presentation parent; putting the new skin under the simulation root would
	# bypass render interpolation and split skin/source marker coordinate frames.
	var presentation_parent: Node=old.get_parent()
	var presentation_pose:=Transform3D.IDENTITY
	if presentation_parent is Node3D:presentation_pose=presentation_parent.transform;presentation_parent.transform=Transform3D.IDENTITY
	var replacement: Node3D=TEXTURED_SURFACE.new();presentation_parent.add_child(replacement)
	var accepted: bool=replacement.setup(self,model_id,body_profile)
	if accepted:accepted=replacement.set_customization(old._custom_colors,old._custom_preview_clothes)
	if presentation_parent is Node3D:presentation_parent.transform=presentation_pose
	for key: String in values:set(key,values[key])
	for node: Node3D in poses:
		if is_instance_valid(node):node.transform=poses[node]
	if not accepted:
		for helper: Variant in [replacement.rig,replacement._swim_rig]:
			if is_instance_valid(helper):helper.get_parent().remove_child(helper);helper.queue_free()
		presentation_parent.remove_child(replacement);replacement.queue_free();return false
	_textured_surface=replacement;player.set_meta("human_model_id",model_id);player.set_meta("human_body_profile",body_profile)
	for helper: Variant in [old.rig,old._swim_rig]:
		if is_instance_valid(helper):helper.set_process(false);helper.get_parent().remove_child(helper);helper.queue_free()
	old.visible=false;old.get_parent().remove_child(old);old.queue_free()
	_fit_gait_to_native(replacement.rig);replacement.rig.sync_pose();_hide_pose_proxies()
	return true

func _make_materials() -> void:
	var colors := {"jacket":Color(.12,.20,.25),"jacket_trim":Color(.17,.28,.33),"shirt":Color(.79,.80,.75),"trousers":Color(.20,.24,.27),"skin":Color(.67,.48,.35),"hair":Color(.065,.055,.045),"shoes":Color(.64,.67,.65),"sole":Color(.14,.17,.18),"eye":Color(.055,.042,.033),"eye_white":Color(.68,.66,.60),"lips":Color(.43,.24,.19),"seam":Color(.09,.14,.16)}
	for key: String in colors:
		var material := StandardMaterial3D.new();material.albedo_color=colors[key]
		material.roughness=.87;material.metallic_specular=.23
		if key in ["jacket","jacket_trim","shirt","trousers"]:
			material.roughness_texture=HUMAN_SURFACES.fabric_roughness();material.uv1_scale=Vector3(3.,6.,1.)
		elif key=="skin":material.roughness=.60;material.metallic_specular=.31
		elif key in ["eye","eye_white"]:material.roughness=.27;material.metallic_specular=.38
		elif key=="hair":material.roughness=.72;material.metallic_specular=.23
		elif key=="shoes":material.roughness=.64
		_materials[key]=material

func _mesh(parent: Node3D,title: String,shape: Mesh,at: Vector3,material: String,part:="") -> MeshInstance3D:
	var node := MeshInstance3D.new();node.name=title;node.mesh=shape;node.position=at;node.material_override=_materials[material]
	node.set_meta("avatar_part",title if part.is_empty() else part);parent.add_child(node);_meshes.append(node);return node

func _box(parent: Node3D,title: String,size: Vector3,at: Vector3,material: String,part:="") -> MeshInstance3D:
	var mesh := BoxMesh.new();mesh.size=size;return _mesh(parent,title,mesh,at,material,part)

func _round(parent: Node3D,title: String,size: Vector3,at: Vector3,material: String,part:="") -> MeshInstance3D:
	var node := _mesh(parent,title,HUMAN_SURFACES.round_detail(),at,material,part);node.scale=size;return node

func _surface(parent: Node3D,title: String,key: String,rows: Array,at: Vector3,material: String,part:="",segments:=24,fold:=0.) -> MeshInstance3D:
	return _mesh(parent,title,HUMAN_SURFACES.loft(key,rows,segments,fold),at,material,part)

func _joint(parent: Node3D,title: String,at: Vector3) -> Node3D:
	var joint := Node3D.new();joint.name=title;joint.position=at;joint.set_meta("avatar_joint",title)
	parent.add_child(joint);_joints[title]=joint;return joint

func _build_head() -> void:
	# Chin, jaw, cheek and cranium are one smooth authored surface. The face is
	# attached to Head so the retained dog-walk head pivot carries every feature.
	var head:=_surface(_upper_body,"Head","adult_head",[
		[-.115,.025,.039,.030,-.018],[-.103,.048,.063,.048,-.010],[-.081,.064,.077,.068,-.003],[-.047,.079,.087,.085,0.],[-.012,.0875,.094,.098,0.],[.025,.085,.088,.097,.002],[.062,.079,.082,.089,.004],[.092,.061,.063,.070,.005],[.110,.031,.032,.037,.005],[.115,.002,.003,.003,.005]],Vector3(0,.705,-.005),"skin", "Head",32)
	_surface(head,"Hair","short_hair_silhouette",[[.010,.080,.054,.093,.010],[.045,.090,.078,.100,.007],[.085,.090,.083,.096,.004],[.117,.071,.064,.080,.003],[.136,.038,.034,.050,.002],[.145,.002,.002,.002,0.]],Vector3.ZERO,"hair","Hair",32,.012)
	# A shaped fringe and sideburns break the helmet silhouette without cards.
	for side: float in [-1.,1.]:
		_round(head,"HairSideburn",Vector3(.018,.065,.041),Vector3(side*.083,.012,.017),"hair","HairBack")
		var ear:=_round(head,"Ear",Vector3(.027,.052,.032),Vector3(side*.088,-.012,.006),"skin")
		_round(ear,"EarConcha",Vector3(.009,.028,.016),Vector3(side*.008,-.002,-.003),"lips")
		# Eye openings stay small: visible sclera sits in a skin lid surround,
		# iris and pupil share one dark surface, instead of floating black balls.
		_round(head,"EyeLid",Vector3(.042,.020,.012),Vector3(side*.035,.026,-.086),"skin")
		_round(head,"EyeSclera",Vector3(.030,.010,.008),Vector3(side*.035,.026,-.092),"eye_white")
		_round(head,"EyeIris",Vector3(.009,.010,.005),Vector3(side*.034,.026,-.097),"eye")
		var brow:=_round(head,"EyeBrow",Vector3(.038,.006,.007),Vector3(side*.037,.047,-.085),"hair");brow.rotation.z=side*-.08
		_round(head,"NoseWing",Vector3(.016,.014,.018),Vector3(side*.012,-.018,-.096),"skin")
	_surface(head,"Nose","nose_bridge_tip",[[-.027,.012,.014,.008,-.096],[-.018,.016,.030,.009,-.096],[-.004,.012,.027,.007,-.091],[.016,.007,.015,.006,-.086],[.042,.005,.004,.004,-.083]],Vector3.ZERO,"skin","Nose",16)
	_round(head,"UpperLip",Vector3(.036,.007,.010),Vector3(0,-.048,-.084),"lips")
	_round(head,"LowerLip",Vector3(.033,.009,.009),Vector3(0,-.054,-.083),"lips")

func _build_body() -> void:
	_upper_body=_joint(self,"UpperBody",Vector3(0,.85,0))
	# Fitted chest/waist/shoulder rings replace the cylindrical robot torso.
	_surface(_upper_body,"Torso","connected_fitted_jacket",TORSO_ROWS,Vector3.ZERO,"jacket","Torso",32,.003)
	_mesh(_upper_body,"Shirt",HUMAN_SURFACES.front_patch("fitted_shirt_front",TORSO_ROWS,[[.070,.065,0.],[.130,.067,0.],[.225,.069,0.],[.335,.069,0.],[.430,.063,0.],[.490,.055,0.],[.525,.048,0.],[.545,.036,0.]],.0012),Vector3.ZERO,"shirt","Shirt")
	for side: float in [-1.,1.]:
		_mesh(_upper_body,"JacketFront",HUMAN_SURFACES.front_patch("fitted_placket_"+str(side),TORSO_ROWS,[[.060,.009,side*.079],[.130,.009,side*.081],[.225,.009,side*.083],[.335,.009,side*.083],[.430,.009,side*.077],[.490,.009,side*.069],[.525,.009,side*.061],[.543,.008,side*.046]],.0024),Vector3.ZERO,"jacket_trim","JacketFront")
		_mesh(_upper_body,"JacketPocketWelt",HUMAN_SURFACES.front_patch("fitted_pocket_"+str(side),TORSO_ROWS,[[.147,.040,side*.121],[.157,.040,side*.121]],.0022),Vector3.ZERO,"jacket_trim","JacketFront")
	_surface(_upper_body,"ShirtCollar","connected_neckline",[[.540,.062,.048,.045,0.],[.550,.064,.048,.045,0.],[.561,.060,.046,.044,0.]],Vector3.ZERO,"shirt","Shirt",28)
	_surface(_upper_body,"JacketHem","fitted_hem",[[.025,.164,.116,.111,0.],[.042,.175,.122,.117,0.],[.056,.175,.123,.117,0.]],Vector3.ZERO,"jacket_trim","JacketHem",28)
	_surface(_upper_body,"Neck","short_connected_neck",[[.510,.082,.059,.055,0.],[.535,.058,.048,.046,0.],[.560,.047,.043,.043,0.],[.594,.047,.044,.044,0.]],Vector3.ZERO,"skin","Neck",28)
	_build_head()
	_pelvis=_surface(self,"Pelvis","fitted_pelvis",[[-.085,.149,.103,.110,0.],[-.050,.169,.119,.128,0.],[.030,.170,.123,.122,0.],[.073,.161,.111,.111,0.]],Vector3(0,HIP_Y,0),"trousers","Pelvis",28,.008)
	for side_name: String in ["Left","Right"]:
		var side := -1.0 if side_name=="Left" else 1.0
		var thigh := _joint(self,side_name+"Thigh",Vector3(side*.105,HIP_Y,0))
		_surface(thigh,side_name+"UpperLeg","trouser_thigh",[[-.448,.058,.067,.061,0.],[-.411,.063,.071,.067,-.003],[-.332,.071,.078,.072,0.],[-.190,.080,.087,.082,.002],[-.059,.082,.090,.086,.006],[.045,.071,.078,.075,.004]],Vector3.ZERO,"trousers",side_name+"UpperLeg",24,.010)
		var shin := _joint(thigh,side_name+"Shin",Vector3(0,-LEG_LENGTH,0))
		_surface(shin,side_name+"LowerLeg","trouser_shin",[[-.435,.047,.050,.046,0.],[-.407,.050,.055,.050,0.],[-.325,.054,.058,.060,.006],[-.208,.062,.062,.070,.009],[-.100,.061,.067,.065,.002],[.030,.058,.067,.060,0.]],Vector3.ZERO,"trousers",side_name+"LowerLeg",24,.010)
		var foot := _joint(shin,side_name+"Foot",Vector3(0,-LEG_LENGTH,0))
		_surface(foot,side_name+"Shoe","rounded_sneaker",[[-.098,.067,.151,.082,-.047],[-.074,.073,.158,.086,-.048],[-.046,.070,.151,.082,-.046],[-.020,.060,.112,.072,-.025],[.005,.047,.055,.054,0.]],Vector3.ZERO,"shoes",side_name+"Shoe",28)
		_surface(foot,side_name+"ShoeSole","rounded_rubber_sole",[[-.1145,.065,.150,.081,-.048],[-.108,.074,.160,.089,-.048],[-.089,.074,.160,.089,-.048]],Vector3.ZERO,"sole",side_name+"ShoeSole",28)
		for lace: int in range(3):
			var band:=_round(foot,side_name+"ShoeLaces",Vector3(.065,.006,.007),Vector3(0,-.015-float(lace)*.006,-.054-float(lace)*.021),"shirt",side_name+"ShoeLaces");band.rotation.z=side*.08
		var arm := _joint(self,side_name+"UpperArm",Vector3(side*.235,1.36,0))
		_surface(arm,side_name+"Sleeve","shaped_upper_sleeve",[[-.327,.044,.046,.044,0.],[-.290,.047,.050,.047,0.],[-.185,.053,.058,.052,0.],[-.075,.058,.063,.057,0.],[-.015,.054,.059,.053,0.],[.020,.039,.044,.041,0.],[.040,.015,.019,.018,0.],[.045,.002,.002,.002,0.]],Vector3.ZERO,"jacket",side_name+"Sleeve",24,.012)
		var forearm := _joint(arm,side_name+"Forearm",Vector3(0,-UPPER_ARM_LENGTH_M,0))
		_surface(forearm,side_name+"LowerSleeve","shaped_forearm_sleeve",[[-.299,.032,.034,.031,0.],[-.266,.036,.038,.035,0.],[-.183,.043,.046,.042,0.],[-.077,.044,.049,.045,0.],[.025,.044,.047,.044,0.]],Vector3.ZERO,"jacket_trim",side_name+"LowerSleeve",24,.013)
		# The retained hand centre is still the IK grip point used by equipment.
		var hand:=_surface(forearm,side_name+"Hand","anatomical_palm",[[-.056,.025,.019,.020,0.],[-.042,.031,.023,.023,0.],[.006,.034,.024,.025,0.],[.031,.025,.020,.020,0.],[.053,.022,.018,.018,0.]],Vector3(0,-FOREARM_LENGTH_M-.025,0),"skin",side_name+"Hand",20)
		_round(hand,"Thumb",Vector3(.027,.051,.031),Vector3(-side*.030,-.006,-.009),"skin")
		for finger: int in range(3):_round(hand,"FingerCrease",Vector3(.0018,.010,.002),Vector3(-.013+finger*.013,-.045,-.021),"lips")
		_hands.append(hand)

func _rest_pose() -> void:
	walk_weight=0.0;_air_weight=0.0;_run_weight=0.0;cadence_hz=0.0
	_stance_fraction=.60;_cycle_distance_m=WALK_CYCLE_DISTANCE_M;_gait_speed_mps=0.;_air_tuck=0.;_hip_pose_y=HIP_Y
	position=Vector3.ZERO
	_upper_body.position=Vector3(0,.85,0);_upper_body.rotation=Vector3.ZERO
	_pelvis.position.y=HIP_Y;_pelvis.rotation=Vector3.ZERO
	for side_name: String in ["Left","Right"]:
		(_joints[side_name+"Thigh"] as Node3D).position.y=HIP_Y
		var side := -1.0 if side_name=="Left" else 1.0
		_feet[side_name]=Vector3(side*.105,STANDING_ANKLE_Y,-.025)
		_leg_pose(side_name,_feet[side_name])
		(_joints[side_name+"UpperArm"] as Node3D).rotation=Vector3(-.04,0,side*.035)
		(_joints[side_name+"Forearm"] as Node3D).rotation=Vector3(.14,0,0)

func set_swimwear_visuals(enabled: bool) -> void:
	# A jacket recoloured to skin still has a low coat hem and raised trouser
	# hips. Wardrobe retains material/visibility ownership; this switches only
	# four existing mesh resources to a coherent bare torso and swim shorts.
	if is_instance_valid(_textured_surface):_textured_surface.set_swimwear(enabled)
	if not enabled:
		for saved: Dictionary in _swim_mesh_defaults:
			if is_instance_valid(saved.node):saved.node.mesh=saved.mesh
		_swim_mesh_defaults.clear();return
	if not _swim_mesh_defaults.is_empty():return
	var torso: MeshInstance3D=find_child("Torso",true,false)
	_swim_mesh_defaults.append({"node":torso,"mesh":torso.mesh})
	torso.mesh=HUMAN_SURFACES.loft("bare_connected_torso",[[.160,.159,.112,.114,0.],[.225,.164,.122,.115,0.],[.335,.181,.130,.115,0.],[.430,.198,.116,.105,0.],[.490,.203,.100,.095,0.],[.525,.198,.086,.080,0.],[.543,.156,.068,.063,0.],[.558,.055,.043,.042,0.]],32)
	_swim_mesh_defaults.append({"node":_pelvis,"mesh":_pelvis.mesh})
	_pelvis.mesh=HUMAN_SURFACES.loft("swim_shorts_hips",[[-.085,.149,.108,.114,0.],[-.040,.165,.121,.128,0.],[.025,.167,.124,.126,0.],[.045,.162,.118,.119,0.]],28,.004)
	for side: String in ["Left","Right"]:
		var thigh: MeshInstance3D=find_child(side+"UpperLeg",true,false);_swim_mesh_defaults.append({"node":thigh,"mesh":thigh.mesh})
		thigh.mesh=HUMAN_SURFACES.loft("swim_shorts_thigh",[[-.448,.058,.067,.061,0.],[-.411,.063,.071,.067,-.003],[-.332,.071,.078,.072,0.],[-.190,.080,.087,.082,.002],[-.059,.082,.090,.086,.006],[.020,.071,.078,.075,.004]],24,.005)

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
		"study":
			# Seat height is authored by the library service. Only the visible
			# skeleton sits; the retained capsule remains supported at the desk.
			position.y=-.36;_upper_body.rotation.x=-.08
			for side_name: String in ["Left","Right"]:
				var side := -1. if side_name=="Left" else 1.
				var foot:=Vector3(side*.16,.40,-.28)
				_feet[side_name]=foot;_leg_pose(side_name,foot)
				var write:=sin(elapsed*3.4)*.012 if side>0. else 0.
				_arm_to(side_name,Vector3(side*.18+write,1.16,-.62))
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
				_arm_to(side_name,Vector3(side*.43,ACTIVITY_DIMENSIONS.WEIGHT_LOW_M+curl*ACTIVITY_DIMENSIONS.WEIGHT_TRAVEL_M,-.12-curl*.14))
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
			position=Vector3(0,-.44,ACTIVITY_DIMENSIONS.ROWING_TRAVEL_M*stroke)
			_upper_body.rotation.x=lerpf(-.20,.15,stroke)
			for side_name: String in ["Left","Right"]:
				var side := -1.0 if side_name=="Left" else 1.0
				var foot := Vector3(side*.22,.75,-.52-ACTIVITY_DIMENSIONS.ROWING_TRAVEL_M*stroke)
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
	if _activity_kind.is_empty() and (state in ["walk","run"] or (state=="idle" and walk_weight>.001)):
		var phase:=stride_phase+(PI if side_name=="Right" else 0.)
		(_joints[side_name+"Foot"] as Node3D).rotation.x+=GAIT_SUPPORT.angle(phase,_stance_fraction,_run_weight,walk_weight)

func _supported_hips(feet: Dictionary) -> void:
	# These invisible compatibility legs solve their own contact reach. The
	# actual weighted human has a separate smooth, common hip support profile;
	# this instantaneous proxy envelope never supplies its body height.
	var height:=HIP_Y
	var maximum_reach:=LEG_LENGTH*2.-.002
	for foot: Vector3 in feet.values():
		height=minf(height,foot.y+sqrt(maxf(.01,maximum_reach*maximum_reach-foot.z*foot.z)))
	_hip_pose_y=height;_pelvis.position.y=height
	for side: String in ["Left","Right"]:(_joints[side+"Thigh"] as Node3D).position.y=height

func _fit_gait_to_native(rig: Node3D) -> void:
	# Original export ankle rests can sit behind the hip (6cm in this female
	# model). Centre travel under each actual hip, rather than adding that
	# export bias to every walking step. The controller/capsule is unchanged.
	var native: Skeleton3D=rig.skeleton;var forward_axis:=global_basis.z.normalized()
	var hip: Vector3=native.global_basis*rig._rest_global[rig._find("Pelvis")].origin
	for side: String in ["Left","Right"]:
		var foot: Vector3=native.global_basis*rig._rest_global[rig._find(side+"Foot")].origin
		_gait_ankle_center_z[side]=(foot-hip).dot(forward_axis)+.025

func _walking_foot(side_name: String,phase: float,reach: float,lift: float) -> Vector3:
	var foot:=_gait_foot(-1. if side_name=="Left" else 1.,phase,reach,lift)
	foot.z-=float(_gait_ankle_center_z[side_name])*walk_weight
	return foot

func _pose_pelvis_gait(feet: Dictionary) -> void:
	# This marker is already part of the camera's twelve-joint render history.
	# Pose the small body rotation here, so the weighted rig reads interpolated
	# rotations rather than a raw physics-phase staircase. The camera stays level.
	var signed_step:=clampf((Vector3(feet.Right)-Vector3(feet.Left)).z/.65,-1.,1.)*walk_weight
	_pelvis.rotation=Vector3(0.,deg_to_rad(3.)*signed_step,deg_to_rad(1.2)*sin(stride_phase)*walk_weight)
	# Publish the small continuous support wave in the interpolated marker.
	# The native rig solves one safe cycle-wide height for the connected hips,
	# rather than dragging the whole torso down with each instantaneous reach.
	_pelvis.position.y=HIP_Y+gait_support_wave(stride_phase,_run_weight,walk_weight)

func gait_support_wave(phase: float,run_weight: float,weight: float) -> float:
	return -lerpf(.016,.024,clampf(run_weight,0.,1.))*(1.+cos(phase*2.))*clampf(weight,0.,1.)

func sample_upper_gait(phase: float,run_weight: float,weight: float) -> Dictionary:
	# A smooth independent arm pendulum avoids the flat pauses made by
	# clipping the foot's stance/swing path. The faster style bends elbows
	# rather than making a long straight arm swing farther through the coat.
	var amount:=clampf(weight,0.,1.);var run:=smoothstep(0.,.70,clampf(run_weight,0.,1.))
	var torso:=Vector3(-deg_to_rad(lerpf(1.5,7.,run))*amount,-deg_to_rad(lerpf(2.5,4.,run))*cos(phase-.10)*amount,-deg_to_rad(lerpf(.4,.65,run))*sin(phase)*amount)
	var result:={"torso":torso}
	for side_name: String in ["Left","Right"]:
		var side:=-1. if side_name=="Left" else 1.
		var cycle:=phase+(PI if side>0. else 0.)
		var swing:=-cos(cycle-.16)
		var upper:=Vector3(-.04+(.14*run+lerpf(.28,.52,run)*swing)*amount,side*lerpf(.02,.06,run)*(.5+.5*swing)*amount,side*lerpf(.035,deg_to_rad(lerpf(5.,7.,run)),amount))
		var elbow:=deg_to_rad(lerpf(17.+5.*swing,85.+10.*swing,run))
		var lower:=Vector3(lerpf(.14,elbow,amount),side*.045*run*sin(cycle-.35)*amount,0.)
		result[side_name]={"upper":upper,"lower":lower}
	return result

func _gait_foot(side: float,phase: float,reach: float,lift: float) -> Vector3:
	return _gait_foot_with_duty(side,phase,reach,lift,_stance_fraction)

func sample_gait_foot(side_name: String,phase: float,run: float,weight: float,duty: float,cycle: float) -> Vector3:
	# Evaluate a displayed gait phase without assigning simulation pose/state.
	# A contact boundary can lie between two physical ticks; blending the old
	# planted ankle with a future swing ankle would move the planted sole early.
	var foot:=_gait_foot_with_duty(-1. if side_name=="Left" else 1.,phase,cycle*duty*.5*weight,lerpf(.10,.24,run)*weight,duty)
	foot.z-=float(_gait_ankle_center_z[side_name])*weight+.025*(1.-weight)
	return foot

func _gait_foot_with_duty(side: float,phase: float,reach: float,lift: float,stance_fraction: float) -> Vector3:
	# During stance the ankle travels backwards at a constant body-relative
	# speed. With uncapped distance-driven cadence, that cancels world travel.
	# Cubic swing matches that derivative at both contacts; no impact snap/bob.
	var fraction:=fposmod(phase/TAU,1.0)
	var duty:=clampf(stance_fraction,.36,.65)
	var foot := Vector3(side*.105,STANDING_ANKLE_Y,0)
	if fraction<duty:foot.z=lerpf(-reach,reach,fraction/duty)
	else:
		var swing:=(fraction-duty)/(1.-duty)
		var tangent:=2.*reach*(1.-duty)/duty
		var t2:=swing*swing;var t3:=t2*swing
		foot.z=(2.*t3-3.*t2+1.)*reach+(t3-2.*t2+swing)*tangent+(-2.*t3+3.*t2)*(-reach)+(t3-t2)*tangent
		# Toe-off lifts early enough for a native adult leg to clear the rear
		# step without dragging its hip down. Both ends have zero Y velocity.
		foot.y+=smoothstep(0.,.16,swing)*smoothstep(0.,.35,1.-swing)*lift
	return foot

func _facility_controlled() -> bool:return bool(player.get("facility_control")) if _facility_property else false

func play_sandbox_action(kind: String,seconds := .4) -> void:
	if kind not in ["punch","flinch","jab_left","cross_right","hook_left","shove","guard","vehicle_enter","vehicle_exit"]:return
	if kind=="guard":set_sandbox_guarding(true);return
	_sandbox_action=kind;_sandbox_remaining_s=maxf(.05,seconds);_sandbox_duration_s=_sandbox_remaining_s

func sandbox_action_duration(kind: String) -> float:return COMBAT_POSES.duration(kind)
func sandbox_contact_phase(kind: String) -> float:return COMBAT_POSES.contact_phase(kind)

func get_sandbox_strike_contact(kind: String="") -> Dictionary:
	if kind.is_empty():kind=_sandbox_action
	var side:="Right" if kind in ["punch","cross_right"] else "Left"
	var result:={"valid":false,"point":global_position,"radius_m":.105,"side":side,"kind":kind,"phase":0.}
	if _sandbox_authored_pose.is_empty() or not is_instance_valid(_textured_surface):return result
	var rig: Node3D=_textured_surface.active_native_rig()
	if not is_instance_valid(rig) or not rig.has_method("combat_contact_world"):return result
	# Safety runs after this avatar's physics pose. Read the same anatomical
	# wrist/finger location that the renderer will display, never a remote ray.
	rig.sync_pose();result=rig.combat_contact_world(side)
	result.merge({"radius_m":.105,"side":side,"kind":kind,"phase":1.-_sandbox_remaining_s/maxf(.0001,_sandbox_duration_s)},true)
	return result

func set_sandbox_guarding(active: bool) -> void:
	_sandbox_guarding=active

func cancel_sandbox_action(expected_kind: String="") -> void:
	# Ownership can change after a newer vehicle pose has already started.
	# A previous melee owner must never erase that new owner's animation.
	if not expected_kind.is_empty() and _sandbox_action!=expected_kind:return
	if expected_kind.is_empty() or _sandbox_action=="guard":_sandbox_guarding=false;_sandbox_guard_weight=0.
	_sandbox_action="";_sandbox_remaining_s=0.;_sandbox_duration_s=0.
	_sandbox_authored_pose.clear()
	remove_meta("render_sandbox_pose")

func _blend_arm_to(side_name: String,target: Vector3,amount: float) -> void:
	var arm:=_joints[side_name+"UpperArm"] as Node3D
	var forearm:=_joints[side_name+"Forearm"] as Node3D
	var original_arm:=arm.basis;var original_forearm:=forearm.basis
	_arm_to(side_name,target)
	arm.basis=original_arm.slerp(arm.basis,amount)
	forearm.basis=original_forearm.slerp(forearm.basis,amount)

func _guard_pose(amount: float) -> void:
	_apply_authored_combat(COMBAT_POSES.sample("guard",0.,amount))

func _apply_authored_combat(pose: Dictionary) -> void:
	_sandbox_authored_pose=pose
	var amount:=clampf(float(pose.weight),0.,1.)
	var stance_amount:=amount*(1.-clampf(walk_weight,0.,1.))
	_upper_body.rotation=_upper_body.rotation.lerp(Vector3(pose.torso),amount)
	_pelvis.position=Vector3(0.,_pelvis.position.y,0.)+Vector3(pose.pelvis)*stance_amount
	_pelvis.rotation=_pelvis.rotation.lerp(Vector3(pose.pelvis_rotation),amount)
	for side: String in ["Left","Right"]:
		var arm:=_joints[side+"UpperArm"] as Node3D;var forearm:=_joints[side+"Forearm"] as Node3D
		var origin_arm:=arm.basis;var origin_forearm:=forearm.basis
		var target: Vector3=pose[side].wrist;var elbow_hint: Vector3=pose[side].elbow
		var offset:=target-arm.position;var distance:=clampf(offset.length(),.02,UPPER_ARM_LENGTH_M+FOREARM_LENGTH_M+.025-.001)
		var direction:=offset.normalized();var pole:=elbow_hint-arm.position
		pole=(pole-direction*pole.dot(direction)).normalized()
		var forearm_reach:=FOREARM_LENGTH_M+.025
		var along:=(UPPER_ARM_LENGTH_M*UPPER_ARM_LENGTH_M-forearm_reach*forearm_reach+distance*distance)/(2.*distance)
		var elbow:=arm.position+direction*along+pole*sqrt(maxf(0.,UPPER_ARM_LENGTH_M*UPPER_ARM_LENGTH_M-along*along))
		var desired_arm:=Basis(Quaternion(Vector3.DOWN,(elbow-arm.position).normalized()))
		var desired_forearm:=desired_arm.inverse()*Basis(Quaternion(Vector3.DOWN,(arm.position+direction*distance-elbow).normalized()))
		arm.basis=origin_arm.slerp(desired_arm,amount);forearm.basis=origin_forearm.slerp(desired_forearm,amount)
		if stance_amount>.001:
			var base: Vector3=_feet[side];var goal: Vector3=pose[side+"Foot"]
			_feet[side]=base.lerp(goal,stance_amount);_leg_pose(side,_feet[side])
			var thigh:=_joints[side+"Thigh"] as Node3D;var shin:=_joints[side+"Shin"] as Node3D
			var contact_basis:=Basis(Vector3.UP,float(pose[side+"FootYaw"])*stance_amount)
			(_joints[side+"Foot"] as Node3D).basis=(thigh.basis*shin.basis).inverse()*contact_basis

func _sandbox_pose(delta: float) -> void:
	_sandbox_authored_pose.clear()
	_sandbox_guard_weight=lerpf(_sandbox_guard_weight,1. if _sandbox_guarding else 0.,1.-exp(-delta*16.))
	if _sandbox_action=="guard" or _sandbox_remaining_s<=0.:
		if _sandbox_guard_weight>.001:
			_sandbox_action="guard";_sandbox_remaining_s=.1;_sandbox_duration_s=.1;_guard_pose(_sandbox_guard_weight);return
		_sandbox_guard_weight=0.;_sandbox_remaining_s=0.;_sandbox_action="";return
	if _sandbox_duration_s<=0.:return
	_sandbox_remaining_s=maxf(0.,_sandbox_remaining_s-delta)
	var phase:=1.0-_sandbox_remaining_s/_sandbox_duration_s
	var weight:=sin(phase*PI)
	if _sandbox_action=="flinch":_upper_body.rotation.x=.16*weight
	elif _sandbox_action in ["vehicle_enter","vehicle_exit"]:
		var direction:=1. if _sandbox_action=="vehicle_enter" else -1.
		_upper_body.rotation=Vector3(.16*weight,direction*.15*weight,direction*.075*weight)
		_blend_arm_to("Left",Vector3(-.29,1.21,-.34-.18*weight),weight)
		_blend_arm_to("Right",Vector3(.26,1.08,-.16-.16*weight),weight)
	else:
		_apply_authored_combat(COMBAT_POSES.sample(_sandbox_action,phase))

func _physics_process(delta: float) -> void:
	if not _ready_avatar or not is_instance_valid(player) or delta<=0.0:return
	_sandbox_authored_pose.clear();_pelvis.position.x=0.;_pelvis.position.z=0.
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
		if _sandbox_action in ["vehicle_enter","vehicle_exit"]:_sandbox_pose(delta)
		return
	# Region changes and recovery are transitions, never one giant stride.
	if movement.length()>2.0:
		state="idle";actual_speed_mps=0.0;measured_displacement_m=0.0;_rest_pose();return
	var grounded: bool=player.is_on_floor()
	# Remote room displays have no collider/move_and_slide or native floor.
	# Only their isolated presentation adapter may interpret approved motion as
	# grounded; the actual local player/controller always keeps native contact.
	if bool(player.get_meta("shared_city_remote",false)) and adapter_walked and player.collision_layer==0 and player.collision_mask==0 and not player.has_method("set_facility_control"):
		grounded=String(player.get_meta("shared_city_motion","idle")) in ["idle","walk","run"]
	var moving := grounded and actual_speed_mps>.08 and Vector2(player.velocity.x,player.velocity.z).length()>.08
	var blend := 1.0-exp(-delta*14.0)
	walk_weight=lerpf(walk_weight,minf(1.0,actual_speed_mps/.75) if moving else 0.0,blend)
	if walk_weight<.001:walk_weight=0.0
	_run_weight=lerpf(_run_weight,clampf((actual_speed_mps-1.9)/2.1,0.0,1.0),blend)
	_air_weight=lerpf(_air_weight,0.0 if grounded else 1.0,blend)
	_air_tuck=lerpf(_air_tuck,clampf(player.velocity.y/7.5,0.,1.),blend)
	_stance_fraction=lerpf(.56,.36,_run_weight)
	_cycle_distance_m=lerpf(WALK_CYCLE_DISTANCE_M,RUN_CYCLE_DISTANCE_M,_run_weight)
	cadence_hz=0.0
	if moving:
		var cadence_limit := MAX_CADENCE_HZ
		var advance := minf(measured_displacement_m/_cycle_distance_m,delta*cadence_limit)
		stride_phase=fmod(stride_phase+advance*TAU,TAU);cadence_hz=advance/delta
		clock+=delta
	_gait_speed_mps=cadence_hz*_cycle_distance_m
	state="air" if not grounded else ("run" if _run_weight>.45 and moving else ("walk" if moving else "idle"))
	var reach := _cycle_distance_m*_stance_fraction*.5*walk_weight
	var lift := lerpf(.10,.24,_run_weight)*walk_weight
	# Marker poses retain physical-time contacts. The native rig evaluates
	# this same smooth gait at displayed time; no camera bob/roll is added.
	var upper_gait:=sample_upper_gait(stride_phase,_run_weight,walk_weight)
	_upper_body.position=Vector3(0,.85,0)
	_upper_body.rotation=Vector3(upper_gait.torso).lerp(Vector3(-.035,0.,0.),_air_weight)
	var posed_feet:={}
	for side_name: String in ["Left","Right"]:
		var side := -1.0 if side_name=="Left" else 1.0
		var phase := fmod(stride_phase+(PI if side_name=="Right" else 0.0),TAU)
		var foot := _walking_foot(side_name,phase,reach,lift)
		foot.z-=.025*(1.0-walk_weight)
		var air_foot := Vector3(side*.105,.15+.18*_air_tuck,(-.10 if side_name=="Left" else .08)*(.5+.5*_air_tuck))
		foot=foot.lerp(air_foot,_air_weight)
		posed_feet[side_name]=foot
	_supported_hips(posed_feet)
	if _air_weight<.001:_pose_pelvis_gait(posed_feet)
	else:_pelvis.rotation=Vector3.ZERO
	for side_name: String in ["Left","Right"]:
		var side := -1.0 if side_name=="Left" else 1.0
		var foot: Vector3=posed_feet[side_name]
		# IK retains flat shoe soles through stance; only the swing foot lifts.
		_feet[side_name]=foot;_leg_pose(side_name,foot)
		var arm := _joints[side_name+"UpperArm"] as Node3D
		var forearm := _joints[side_name+"Forearm"] as Node3D
		arm.rotation=Vector3(upper_gait[side_name].upper).lerp(Vector3(.48,0.,side*.035),_air_weight)
		forearm.rotation=Vector3(upper_gait[side_name].lower).lerp(Vector3(.50,0.,0.),_air_weight)
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
	var textured:=textured_model_snapshot(false)
	if bool(textured.loaded):body_bounds=global_transform*textured.actual_visible_bounds_m
	return {"ready":_ready_avatar,"state":state,"clock":clock,"stride_phase":stride_phase,"cadence_hz":cadence_hz,"cadence_cap_hz":MAX_CADENCE_HZ,"actual_speed_mps":actual_speed_mps,"measured_displacement_m":measured_displacement_m,"walk_weight":walk_weight,"air_weight":_air_weight,"run_weight":_run_weight,
		"joint_transforms":transforms,"feet_world":feet,"mesh_count":int(textured.visible_mesh_count),"hidden_pose_proxy_mesh_count":_meshes.size(),"body_bounds":body_bounds,"textured_model":textured,"textured_model_loaded":bool(textured.loaded),"original_body_hidden":is_instance_valid(_old_body) and not _old_body.visible,"uses_original_physics_capsule":true,"visual_forward":-global_basis.z,"facility_control":_facility_controlled() if is_instance_valid(player) else false,"activity_kind":_activity_kind,"activity_elapsed":_activity_elapsed,"avatar_hands_visible":bool(textured.loaded) and _activity_kind not in ["eat","weights"],
		"appearance_scope":"Original Sim2Seoul SeoulResident skinned mesh, facial detail, clothing and articulated hands authored in this repository; retained invisible markers supply game contacts.","eye_height_m":1.581,"human_surface_version":"EXP33_ORIGINAL_SEOUL_RESIDENT_01","authored_adult_height_m":ADULT_VISUAL_HEIGHT_M,"head_height_m":HEAD_HEIGHT_M,"standing_hip_joint_height_m":HIP_Y,"hip_height_m":_hip_pose_y,"head_units":ADULT_VISUAL_HEIGHT_M/HEAD_HEIGHT_M,"stance_fraction":_stance_fraction,"cycle_distance_m":_cycle_distance_m,"represented_gait_speed_mps":_gait_speed_mps,"arcade_speed_excess_mps":maxf(0.,actual_speed_mps-_gait_speed_mps),"motion_scope":"Distance-driven game-contact markers and original combat keyposes drive the native weighted human. Not motion capture. Turbo speeds retain bounded cadence and can visibly exceed plausible limb travel."}

func _enter_tree() -> void:
	# Reparenting a live avatar can leave and re-enter within one frame.
	# Queue the retained hidden state after any pending fallback restore.
	if is_instance_valid(_old_body):_old_body.set_deferred("visible",false)

func _exit_tree() -> void:
	# The old body may be a sibling in the same player being destroyed.
	# Restore a surviving fallback after teardown; a freed body discards the
	# deferred write instead of rebuilding renderer dependencies mid-delete.
	if is_instance_valid(_old_body):_old_body.set_deferred("visible",_old_body_visible)
