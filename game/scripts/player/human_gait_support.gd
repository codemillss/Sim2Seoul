extends RefCounted
## Pure render-pose geometry. A planted heel/toe stays fixed while the ankle
## rocks around an actual native sole contact. No physics/collision ownership.
const HEEL_STRIKE_RADIANS := PI*22./180.
const TOE_OFF_RADIANS := PI*32./180.
const SOLE_BAND_M := .014
const HEEL_PATCH_DEPTH_M := .025
const TOE_PATCH_DEPTH_M := .035

static func angle(phase_radians: float,stance_fraction: float,run_weight:=0.,walk_weight:=1.) -> float:
	var fraction:=fposmod(phase_radians/TAU,1.)
	var duty:=clampf(stance_fraction,.36,.65)
	# Slightly less heel lift at faster cadence; both profiles retain a flat
	# midstance and C1 joins, including the swing/contact cycle boundary.
	var heel:=HEEL_STRIKE_RADIANS*lerpf(1.,.85,clampf(run_weight,0.,1.))
	var toe:=TOE_OFF_RADIANS
	var result:=0.
	if fraction<duty:
		var stance:=fraction/duty
		if stance<.18:result=heel*(1.-smoothstep(0.,.18,stance))
		elif stance>.65:result=-toe*smoothstep(.65,1.,stance)
	else:
		var swing:=(fraction-duty)/(1.-duty)
		if swing<.35:result=-toe*(1.-smoothstep(0.,.35,swing))
		elif swing>.65:result=heel*smoothstep(.65,1.,swing)
	return result*clampf(walk_weight,0.,1.)

static func corrected_goal(neutral_ankle: Vector3,neutral_foot_basis: Basis,contact: Dictionary,angle_radians: float) -> Dictionary:
	if not bool(contact.get("valid",false)) or absf(angle_radians)<.0000001:
		return {"goal":neutral_ankle,"basis":neutral_foot_basis,"pivot":neutral_ankle,"contact_local":Vector3.ZERO,"roll_radians":0.,"valid":bool(contact.get("valid",false))}
	var pivot_local: Vector3=contact.heel_local if angle_radians>=0. else contact.toe_local
	var axis: Vector3=(neutral_foot_basis*Vector3(contact.roll_axis_local)).normalized()
	var rotation:=Basis(axis,angle_radians)
	var pivot:=neutral_ankle+neutral_foot_basis*pivot_local
	return {"goal":pivot+rotation*(neutral_ankle-pivot),"basis":rotation*neutral_foot_basis,"pivot":pivot,"contact_local":pivot_local,"roll_radians":angle_radians,"valid":true}

static func calibrate(rig: Node3D) -> Dictionary:
	# Evaluate original rest skin once, not a potentially moving imported pose.
	# Bind matrices and indexed vertices are the same geometry rendered by the
	# model; the selected sole strips are observations rather than dimensions
	# guessed from the invisible legacy avatar's shoes.
	if not is_instance_valid(rig) or not bool(rig.get("loaded")):
		return {"valid":false,"reason":"rig_not_ready","feet":{}}
	var skeleton: Skeleton3D=rig.get("skeleton")
	var model: Node3D=rig.get("visual_root")
	var avatar: Node3D=rig.get("avatar")
	var rests: Array=rig.get("_rest_global")
	if skeleton==null or model==null or avatar==null or rests.is_empty():
		return {"valid":false,"reason":"missing_native_rest_geometry","feet":{}}
	var skeleton_to_avatar:=avatar.global_transform.affine_inverse()*skeleton.global_transform
	var points: Array[Vector3]=[]
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh:=node as MeshInstance3D
		if mesh.mesh==null or mesh.skin==null or not mesh.visible:continue
		var matrices: Array[Transform3D]=[]
		for bind: int in range(mesh.skin.get_bind_count()):
			var name_: String=mesh.skin.get_bind_name(bind)
			var bone:=skeleton.find_bone(name_) if not name_.is_empty() else mesh.skin.get_bind_bone(bind)
			if bone<0 or bone>=rests.size():return {"valid":false,"reason":"invalid_native_skin_bind","feet":{}}
			matrices.append(rests[bone]*mesh.skin.get_bind_pose(bind))
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays: Array=mesh.mesh.surface_get_arrays(surface)
			var raw: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			if raw.is_empty() or bones.is_empty() or weights.size()!=bones.size():continue
			var slots: int=bones.size()/raw.size()
			var referenced: Dictionary={}
			if indices.is_empty():
				for vertex: int in range(raw.size()):referenced[vertex]=true
			else:
				for vertex: int in indices:referenced[vertex]=true
			for vertex: int in referenced:
				var point:=Vector3.ZERO
				for slot: int in range(slots):
					var weight: float=weights[vertex*slots+slot]
					if weight>0.:point+=(matrices[bones[vertex*slots+slot]]*raw[vertex])*weight
				points.append(skeleton_to_avatar*point)
	if points.is_empty():return {"valid":false,"reason":"no_indexed_native_skin_vertices","feet":{}}
	var minimum_y:=INF
	for point: Vector3 in points:minimum_y=minf(minimum_y,point.y)
	var feet:={};var all_valid:=true
	for side: String in ["Left","Right"]:
		var sole: Array[Vector3]=[];var heel_z:=-INF;var toe_z:=INF
		for point: Vector3 in points:
			var correct_side:=point.x<-.02 if side=="Left" else point.x>.02
			if correct_side and point.y<=minimum_y+SOLE_BAND_M:
				sole.append(point);heel_z=maxf(heel_z,point.z);toe_z=minf(toe_z,point.z)
		var valid:=sole.size()>=8 and heel_z-toe_z>.10
		if not valid:
			feet[side]={"valid":false,"reason":"native_sole_strip_not_found","sole_vertices":sole.size()};all_valid=false;continue
		var heel:=Vector3.ZERO;var toe:=Vector3.ZERO;var heel_count:=0;var toe_count:=0
		for point: Vector3 in sole:
			if point.z>=heel_z-HEEL_PATCH_DEPTH_M:heel+=point;heel_count+=1
			if point.z<=toe_z+TOE_PATCH_DEPTH_M:toe+=point;toe_count+=1
		heel/=float(heel_count);toe/=float(toe_count)
		var forward:=toe-heel;forward.y=0.
		var axis_avatar:=forward.normalized().cross(Vector3.UP).normalized()
		var foot: int=rig.call("_find",side+"Foot")
		var rest: Transform3D=rests[foot]
		var to_local:=rest.affine_inverse()*skeleton_to_avatar.affine_inverse()
		var axis_local: Vector3=rest.basis.inverse()*skeleton_to_avatar.basis.inverse()*axis_avatar
		feet[side]={"valid":true,"heel_local":to_local*heel,"toe_local":to_local*toe,"roll_axis_local":axis_local.normalized(),"neutral_heel_avatar_m":heel,"neutral_toe_avatar_m":toe,"neutral_ankle_avatar_m":(skeleton_to_avatar*rest).origin,"roll_axis_avatar":axis_avatar,"sole_vertices":sole.size(),"heel_patch_vertices":heel_count,"toe_patch_vertices":toe_count,"method":"actual_original_rest_weighted_indexed_sole_strips"}
	return {"valid":all_valid,"feet":feet,"minimum_rest_skin_y_avatar_m":minimum_y,"indexed_native_vertices":points.size(),"scope":"Rest-skinned sole contact calibration only; does not establish moving skin contact, gameplay or visual naturalness."}
