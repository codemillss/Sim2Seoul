extends "res://../tests/game/check_textured_human_rig.gd"
## Actual weighted-vertex observations at the production walking/running
## stride dimensions. Raw rear-pelvis vertices and triangles are retained.
var _regions: Array=[]

var _baseline_replay:=false
var _avatar_source: GDScript
var _rig_source: GDScript
const FROZEN_SOURCE_ROOT:="res://../data/reports/human_presence/20261022/skin_gait/source_snapshots/"

func _initialize() -> void:
	_baseline_replay="--replay-before-hip" in OS.get_cmdline_user_args()
	super._initialize()

func _cycle(avatar: Node3D,mode: String) -> float:
	return float(avatar.get_script().get_script_constant_map().get("RUN_CYCLE_DISTANCE_M" if mode=="run" else "WALK_CYCLE_DISTANCE_M",1.86 if mode=="run" else 1.26))

func _walking_foot(avatar: Node3D,side: String,phase: float,reach: float,lift: float) -> Vector3:
	return avatar._walking_foot(side,phase,reach,lift) if avatar.has_method("_walking_foot") else avatar._gait_foot(-1. if side=="Left" else 1.,phase,reach,lift)

func _vertices(skeleton: Skeleton3D,mesh: MeshInstance3D,surface: int) -> PackedVector3Array:
	var arrays:=mesh.mesh.surface_get_arrays(surface);var raw: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	var matrices: Array[Transform3D]=[]
	for bind: int in range(mesh.skin.get_bind_count()):
		var name_: String=mesh.skin.get_bind_name(bind);var index:=skeleton.find_bone(name_) if not name_.is_empty() else mesh.skin.get_bind_bone(bind)
		matrices.append(skeleton.global_transform*skeleton.get_bone_global_pose(index)*mesh.skin.get_bind_pose(bind))
	var out:=PackedVector3Array();var influences: int=bones.size()/raw.size()
	for vertex: int in range(raw.size()):
		var at:=Vector3.ZERO
		for slot: int in range(influences):
			var weight:=weights[vertex*influences+slot]
			if weight>0.:at+=matrices[bones[vertex*influences+slot]]*raw[vertex]*weight
		out.append(at)
	return out

func _percentile(values: Array[float],fraction: float) -> float:
	if values.is_empty():return 0.
	values.sort();return values[mini(values.size()-1,int(ceil(fraction*values.size()))-1)]

func _prepare_regions(skeleton: Skeleton3D,model: Node3D,helper: Node3D) -> void:
	_regions.clear()
	var pelvis: Vector3=skeleton.global_transform*helper._rest_global[helper._find("Pelvis")].origin
	var waist: Vector3=skeleton.global_transform*helper._rest_global[helper._find("Spine1")].origin
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh:=node as MeshInstance3D
		if mesh.skin==null:continue
		for surface: int in range(mesh.mesh.get_surface_count()):
			var vertices:=_vertices(skeleton,mesh,surface);var indices: PackedInt32Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX];var triangles: Array=[];var ids:={}
			for index: int in range(0,indices.size(),3):
				var a: int=indices[index];var b: int=indices[index+1];var c: int=indices[index+2];var center: Vector3=(vertices[a]+vertices[b]+vertices[c])/3.
				if center.y>pelvis.y-.14 and center.y<waist.y+.02 and center.z>pelvis.z+.025 and absf(center.x-pelvis.x)<.25:
					var area: float=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).length()*.5
					if area>.0000001:triangles.append([a,b,c]);ids[a]=true;ids[b]=true;ids[c]=true
			if not triangles.is_empty():_regions.append({"mesh":mesh,"surface":surface,"rest":vertices,"triangles":triangles,"vertex_ids":ids.keys()})

func _observe(label_: String,skeleton: Skeleton3D,model: Node3D,helper: Node3D) -> void:
	var edges: Array[float]=[];var areas: Array[float]=[];var inverted:=0;var triangle_count:=0;var raw: Array=[]
	for region: Dictionary in _regions:
		var current:=_vertices(skeleton,region.mesh,region.surface);var rest: PackedVector3Array=region.rest;var mapped:={};var rest_raw: Array=[];var current_raw: Array=[]
		for id_: int in region.vertex_ids:mapped[id_]=current_raw.size();rest_raw.append(rest[id_]);current_raw.append(current[id_])
		var remapped_triangles: Array=[]
		for t: Array in region.triangles:
			var before: Vector3=(rest[t[1]]-rest[t[0]]).cross(rest[t[2]]-rest[t[0]]);var after: Vector3=(current[t[1]]-current[t[0]]).cross(current[t[2]]-current[t[0]])
			areas.append(after.length()/before.length());triangle_count+=1
			if before.normalized().dot(after.normalized())<-.1:inverted+=1
			for edge: Array in [[t[0],t[1]],[t[1],t[2]],[t[2],t[0]]]:
				var length: float=rest[edge[0]].distance_to(rest[edge[1]])
				if length>.0001:edges.append(absf(log(current[edge[0]].distance_to(current[edge[1]])/length)))
			remapped_triangles.append([mapped[t[0]],mapped[t[1]],mapped[t[2]]])
		raw.append({"mesh":region.mesh.name,"surface":region.surface,"original_vertex_indices":region.vertex_ids,"neutral_vertices_m":rest_raw,"posed_vertices_m":current_raw,"triangles":remapped_triangles})
	var left: int=helper._find("LeftThigh");var right: int=helper._find("RightThigh");var actual: Vector3=skeleton.global_basis*(skeleton.get_bone_global_pose(left).origin-skeleton.get_bone_global_pose(right).origin);var rest: Vector3=skeleton.global_basis*(helper._rest_global[left].origin-helper._rest_global[right].origin)
	var local_error:=0.
	for semantic: String in ["Spine","LeftThigh","RightThigh"]:
		var bone: int=helper._find(semantic);local_error=maxf(local_error,skeleton.get_bone_pose(bone).origin.distance_to(skeleton.get_bone_rest(bone).origin)*skeleton.global_basis.get_scale().abs().x)
	var finite:=true
	for bone: int in range(skeleton.get_bone_count()):finite=finite and skeleton.get_bone_global_pose(bone).is_finite()
	var bounds:=_skin_bounds(skeleton,model);var snapshot: Dictionary=helper.snapshot()
	_check(label_+".actual_hip_width_preserved",absf(actual.length()-rest.length())<.00001,{"actual_hip_center_delta_m":actual,"native_hip_center_delta_m":rest})
	_check(label_+".anatomical_pelvis_spine_thigh_local_connections",local_error<(.0003 if label_.ends_with("neutral") else .00001),{"maximum_lower_joint_local_translation_error_m":local_error})
	_check(label_+".actual_foot_contacts",float(snapshot.maximum_contact_error_m)<.01,snapshot)
	_check(label_+".actual_cpu_skin_and_all_bones_finite",finite and bounds.position.is_finite() and bounds.size.is_finite() and triangle_count>30)
	cases.append({"name":label_,"actual_hip_center_delta_m":actual,"native_hip_width_m":rest.length(),"actual_hip_width_m":actual.length(),"maximum_lower_joint_local_translation_error_m":local_error,"rear_pelvis_triangles":triangle_count,"rear_pelvis_log_edge_strain_p95":_percentile(edges,.95),"rear_pelvis_log_edge_strain_p99":_percentile(edges,.99),"rear_pelvis_area_ratio_p01":_percentile(areas,.01),"rear_pelvis_area_ratio_p99":_percentile(areas,.99),"rear_pelvis_normals_opposed_to_neutral":inverted,"actual_cpu_skin_bounds":bounds,"rig":snapshot,"raw_rear_pelvis_skin":raw})

func _stance_motion(id: String,player: Node3D,avatar: Node3D,skeleton: Skeleton3D,model: Node3D,helper: Node3D,mode: String="walk",speed: float=1.4) -> void:
	avatar._rest_pose();helper.sync_pose()
	var patches: Array=[]
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh:=node as MeshInstance3D
		if mesh.skin==null:continue
		var points:=_vertices(skeleton,mesh,0);var left: Array[int]=[];var right: Array[int]=[]
		for vertex: int in range(points.size()):
			if points[vertex].y<.015 and points[vertex].y>-.02:
				if points[vertex].x<-.02:left.append(vertex)
				elif points[vertex].x>.02:right.append(vertex)
		if not left.is_empty() and not right.is_empty():patches.append({"mesh":mesh,"Left":left,"Right":right})
	var previous:={};var maximum_bone:={"Left":0.,"Right":0.};var maximum_skin:={"Left":0.,"Right":0.};var counts:={"Left":0,"Right":0};var trace: Array=[]
	var run_weight:=clampf((speed-1.9)/2.1,0.,1.);var cycle:=lerpf(_cycle(avatar,"walk"),_cycle(avatar,"run"),run_weight);var duty:=lerpf(.60,.40,run_weight);var lift:=lerpf(.075,.21,run_weight);var interval:=cycle/speed/60.
	for frame: int in range(61):
		var phase:=float(frame)/60.;player.position.z=-cycle*phase
		avatar._rest_pose();avatar.state=mode;avatar.walk_weight=1.;avatar._run_weight=run_weight;avatar.stride_phase=phase*TAU;avatar._stance_fraction=duty;avatar._upper_body.rotation.x=-.075*run_weight
		var feet:={}
		for side: String in ["Left","Right"]:feet[side]=_walking_foot(avatar,side,phase*TAU+(PI if side=="Right" else 0.),cycle*duty*.5,lift)
		avatar._supported_hips(feet)
		if avatar.has_method("_pose_pelvis_gait"):avatar._pose_pelvis_gait(feet)
		for side: String in ["Left","Right"]:avatar._feet[side]=feet[side];avatar._leg_pose(side,feet[side])
		helper.sync_pose();var skin_points:={"Left":Vector3.ZERO,"Right":Vector3.ZERO};var skin_counts:={"Left":0,"Right":0}
		for patch: Dictionary in patches:
			var posed:=_vertices(skeleton,patch.mesh,0)
			for side: String in ["Left","Right"]:
				for vertex: int in patch[side]:skin_points[side]+=posed[vertex];skin_counts[side]+=1
		var row:={"frame":frame,"phase":phase,"dt_s":interval,"feet":{}}
		for side: String in ["Left","Right"]:
			var fraction:=fposmod(phase+(.5 if side=="Right" else 0.),1.);var stance:=fraction>.02 and fraction<duty-.02
			var bone: Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(helper._find(side+"Foot")).origin
			var skin: Vector3=skin_points[side]/maxi(1,skin_counts[side])
			if previous.has(side) and stance and previous[side].stance:
				maximum_bone[side]=maxf(maximum_bone[side],bone.distance_to(previous[side].bone)/interval)
				maximum_skin[side]=maxf(maximum_skin[side],skin.distance_to(previous[side].skin)/interval);counts[side]+=1
			previous[side]={"stance":stance,"bone":bone,"skin":skin};row.feet[side]={"stance":stance,"actual_bone_world_m":bone,"actual_cpu_skin_sole_centroid_world_m":skin,"skin_vertex_count":skin_counts[side]}
		trace.append(row)
	for side: String in ["Left","Right"]:
		_check(id+"."+mode+"."+side+"_actual_foot_bone_stance_speed_under_25mmps",counts[side]>15 and float(maximum_bone[side])<.025,{"maximum_mps":maximum_bone[side],"intervals":counts[side]})
		_check(id+"."+mode+"."+side+"_actual_cpu_skin_sole_stance_speed_under_25mmps",counts[side]>15 and not patches.is_empty() and float(maximum_skin[side])<.025,{"maximum_mps":maximum_skin[side],"intervals":counts[side]})
	cases.append({"name":id+"_"+mode+"_continuous_stance_motion","speed_mps":speed,"run_weight":run_weight,"actual_foot_bone_maximum_mps":maximum_bone,"actual_cpu_skin_sole_maximum_mps":maximum_skin,"samples":trace,"scope":"Independent engine bone positions and CPU-deformed shoe-sole patch centroid, steady configured native walking/running, interior stance intervals only; contact boundaries/start/stop are not included."})
	player.position=Vector3.ZERO

func _run() -> void:
	if _baseline_replay:
		_avatar_source=GDScript.new();_avatar_source.source_code=FileAccess.get_file_as_string(FROZEN_SOURCE_ROOT+"exploration_avatar.before_hip.gd.txt");
		if _avatar_source.reload()!=OK:push_error("Frozen avatar source compile failed");quit(2);return
		_rig_source=GDScript.new();_rig_source.source_code=FileAccess.get_file_as_string(FROZEN_SOURCE_ROOT+"textured_human_rig.before_hip.gd.txt");
		if _rig_source.reload()!=OK:push_error("Frozen helper source compile failed");quit(2);return
	else:
		_avatar_source=load("res://scripts/player/exploration_avatar.gd");_rig_source=load("res://scripts/player/textured_human_rig.gd")
	for path: String in ["res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/human_activity_dimensions.gd","res://scripts/player/textured_human_rig.gd","res://../tests/game/check_textured_human_rig.gd","res://../tests/game/check_human_skin_gait.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	if _baseline_replay:
		for name_: String in ["exploration_avatar","textured_human_rig"]:
			source_hashes.erase("res://scripts/player/"+name_+".gd");var path:=FROZEN_SOURCE_ROOT+name_+".before_hip.gd.txt";source_hashes[path]=FileAccess.get_sha256(path)
	for id: String in ["Male_Adult_04","Female_Adult_07"]:
		var path:=asset_root+id+"/Export/"+id+".fbx";source_hashes[path]=FileAccess.get_sha256(path)
		var player:=CharacterBody3D.new();player.set_meta("pose_proxy_only",true);var visual:=Node3D.new();visual.name="Visual";player.add_child(visual);var original:=MeshInstance3D.new();original.name="Body";original.mesh=CapsuleMesh.new();visual.add_child(original);root.add_child(player)
		var avatar: Node3D=_avatar_source.new();visual.add_child(avatar);_check(id+".production_avatar_setup",avatar.setup(player));avatar.set_physics_process(false)
		var model: Node3D=(load(path) as PackedScene).instantiate();avatar.add_child(model);var skeleton:=model.find_child("Skeleton3D",true,false) as Skeleton3D
		for animation: Node in model.find_children("*","AnimationPlayer",true,false):animation.stop();animation.active=false
		var initial:=_skin_bounds(skeleton,model);var factor:=1.70/initial.size.y;model.scale=Vector3.ONE*factor;model.rotation.y=PI;model.position.y=-initial.position.y*factor
		var helper:=_rig_source.new() as Node3D;avatar.add_child(helper);_check(id+".actual_skin_rig_setup",helper.setup(avatar,model,skeleton))
		if avatar.has_method("_fit_gait_to_native"):avatar._fit_gait_to_native(helper)
		_prepare_regions(skeleton,model,helper);_observe(id+"_neutral",skeleton,model,helper)
		for mode: String in ["walk","run"]:
			for phase: float in [0.,.125,.25,.375,.5,.625,.75,.875]:
				avatar._rest_pose();avatar.state=mode;avatar.walk_weight=1.;avatar._run_weight=1. if mode=="run" else 0.;avatar.stride_phase=phase*TAU;avatar._stance_fraction=.4 if mode=="run" else .6
				var feet:={};var reach: float=_cycle(avatar,mode)*avatar._stance_fraction*.5;var lift:=.21 if mode=="run" else .075
				for side: String in ["Left","Right"]:feet[side]=_walking_foot(avatar,side,phase*TAU+(PI if side=="Right" else 0.),reach,lift)
				avatar._supported_hips(feet)
				if avatar.has_method("_pose_pelvis_gait"):avatar._pose_pelvis_gait(feet)
				for side: String in ["Left","Right"]:avatar._feet[side]=feet[side];avatar._leg_pose(side,feet[side])
				helper.sync_pose();_observe(id+"_"+mode+"_"+str(phase),skeleton,model,helper)
		_stance_motion(id,player,avatar,skeleton,model,helper)
		_stance_motion(id,player,avatar,skeleton,model,helper,"run",3.5)
		player.free();await process_frame
	var bindings:=true
	for path: String in source_hashes:bindings=bindings and FileAccess.get_sha256(path)==source_hashes[path]
	_check("source_bindings_unchanged",bindings)
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"task":"EXP29_WEIGHTED_HUMAN_SKIN_GAIT","replay_original_frozen_sources":_baseline_replay,"result":"PASS" if failed==0 else "FAIL","summary":{"checks":checks.size(),"failed":failed},"checks":checks,"cases":cases,"source_sha256":source_hashes,"display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"scope":"Actual neutral and eight walk/eight run phase CPU-deformed Rocketbox meshes. Rear pelvis region is selected geometrically on neutral skin; log edge strain and area/normal changes are observations, not guarantees of realism. Lower joint rigid connections and width/foot goals are structural acceptance, native front/back/side images remain separate."}),"  ")+"\n");file.close();print("HUMAN_SKIN_GAIT_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
