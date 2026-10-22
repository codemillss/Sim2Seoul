extends Node3D
## Presentation-only bridge from the retained game IK markers to a skinned
## human. No player pose, capsule, source joint or import rest is ever changed.
## Godot4 bone poses include their rest transforms; set complete local poses.
var loaded:=false
var load_error:=""
var avatar: Node3D
var visual_root: Node3D
var skeleton: Skeleton3D
var _rest: Array[Transform3D]=[]
var _rest_global: Array[Transform3D]=[]
var _poses: Array[Transform3D]=[]
var _global_poses: Array[Transform3D]=[]
var _parents: Array[int]=[]
var _bones: Dictionary={}
var _source_reference: Dictionary={}
var _corrections: Dictionary={}
var _hand_contacts: Dictionary={}
var _foot_offsets: Dictionary={}
var _goals: Dictionary={}
var _source_pelvis_reference:=Vector3.ZERO
var _frame_count:=0
var _finite:=true
var _maximum_reach_clamp_m:=0.
var _last_hip_delta:=Vector3.ZERO
var _contact_mode:=false
var _contact_lean_radians:=0.
var _ground_gait:=false
var _pelvis_gait_turn:=Basis.IDENTITY
var _pelvis_yaw_radians:=0.
var _pelvis_roll_radians:=0.
var reference_skeleton: Skeleton3D
var _fitted_rest_global: Array[Transform3D]=[]
var _fit_heights: Array[Vector2]=[]
var _fit_planar_offsets: Array[Vector3]=[]
var _fit_diagnostics: Dictionary={}
var _fit_neck_index:=-1
const MAX_CONTACT_LEAN_RADIANS:=PI*25./180.

func setup(source_avatar: Node3D,imported_root: Node3D,imported_skeleton: Skeleton3D,original_head_skeleton: Skeleton3D=null) -> bool:
	if loaded or not is_instance_valid(source_avatar) or not is_instance_valid(imported_root) or not is_instance_valid(imported_skeleton):return _fail("missing_source_or_imported_skeleton")
	avatar=source_avatar;visual_root=imported_root;skeleton=imported_skeleton;reference_skeleton=original_head_skeleton
	if get_parent()==null:avatar.add_child(self)
	name="TexturedHumanRig";process_mode=Node.PROCESS_MODE_PAUSABLE;process_priority=100
	# Import animation players must not overwrite this procedural pose owner.
	for node: Node in imported_root.find_children("*","AnimationPlayer",true,false):node.stop();node.active=false
	for index: int in range(skeleton.get_bone_count()):
		var parent:=skeleton.get_bone_parent(index)
		if parent>=index:return _fail("non_topological_imported_bones")
		_parents.append(parent);_rest.append(skeleton.get_bone_rest(index))
		_rest_global.append(_rest[index] if parent<0 else _rest_global[parent]*_rest[index])
		_bones[_normal_name(skeleton.get_bone_name(index))]=index
	for semantic: String in ["Pelvis","Spine","Head"]:
		if _find(semantic)<0:return _fail("missing_bone_"+semantic)
	for side: String in ["Left","Right"]:
		for segment: String in ["Thigh","Shin","Foot","UpperArm","Forearm","Hand"]:
			if _find(side+segment)<0:return _fail("missing_bone_"+side+segment)
	var reference_rig: Node3D
	if is_instance_valid(reference_skeleton):
		for candidate: Node in avatar.get_children():
			if candidate!=self and candidate.get_script()==get_script() and candidate.get("skeleton")==reference_skeleton and candidate.get("loaded")==true:reference_rig=candidate;break
	for title: String in ["UpperBody","Pelvis","Head","LeftThigh","LeftShin","LeftFoot","RightThigh","RightShin","RightFoot","LeftUpperArm","LeftForearm","LeftHand","RightUpperArm","RightForearm","RightHand"]:
		var node:=_source_node(title)
		if not is_instance_valid(node):return _fail("missing_source_marker_"+title)
		if is_instance_valid(reference_rig):
			# Changing clothes may happen mid-gait. Reuse the original actor's
			# neutral reference rather than calibrating a new body to that step.
			var frame:=skeleton.global_transform.affine_inverse()*reference_skeleton.global_transform
			var value: Transform3D=frame*reference_rig._source_reference[title];value.basis=value.basis.orthonormalized();_source_reference[title]=value
		else:_source_reference[title]=_source_pose(node)
	_source_pelvis_reference=_source_reference.Pelvis.origin
	for side: String in ["Left","Right"]:
		_calibrate_segment(side+"Thigh",side+"Shin")
		_calibrate_segment(side+"Shin",side+"Foot")
		_calibrate_segment(side+"UpperArm",side+"Forearm")
		_calibrate_segment(side+"Forearm",side+"Hand")
		var foot_index:=_find(side+"Foot")
		_corrections[side+"Foot"]=_source_reference[side+"Foot"].basis.inverse()*_rest_global[foot_index].basis
		_foot_offsets[side]=_rest_global[foot_index].origin-_source_reference[side+"Foot"].origin
		var hand_index:=_find(side+"Hand");var forearm_index:=_find(side+"Forearm")
		var calibrated_forearm: Basis=_source_reference[side+"Forearm"].basis*_corrections[side+"Forearm"]
		var hand_neutral:=calibrated_forearm*_rest_global[forearm_index].basis.inverse()*_rest_global[hand_index].basis
		_corrections[side+"Hand"]=_source_reference[side+"Forearm"].basis.inverse()*hand_neutral
		_hand_contacts[side]=_hand_contact(hand_index)
	if is_instance_valid(reference_skeleton) and not _prepare_reference_fit():return _fail("invalid_reference_upper_body_fit")
	_poses=_rest.duplicate();_global_poses=_rest_global.duplicate();loaded=true;sync_pose();return _finite

func _fail(reason: String) -> bool:
	load_error=reason;loaded=false;return false

func _normal_name(title: String) -> String:
	return title.to_lower().replace(" ","").replace("_","").get_slice(":",title.count(":"))

func _find(semantic: String) -> int:
	var side:="l" if semantic.begins_with("Left") else ("r" if semantic.begins_with("Right") else "")
	var part:=semantic.trim_prefix("Left").trim_prefix("Right").to_lower()
	var aliases: Array[String]=[part]
	if part=="shin":aliases=["calf","shin","leg"]
	for alias: String in aliases:
		for candidate: String in ["bip01"+side+alias,"bip001"+side+alias,side+alias,alias+"."+side,semantic.to_lower()]:
			if _bones.has(candidate):return int(_bones[candidate])
	return -1

func _reference_index(semantic: String) -> int:
	var wanted:=_normal_name("Bip01 "+semantic.replace("Left","L ").replace("Right","R "))
	for index: int in range(reference_skeleton.get_bone_count()):
		if _normal_name(reference_skeleton.get_bone_name(index))==wanted:return index
	return -1

func _reference_rest(semantic: String) -> Transform3D:
	var frame:=skeleton.global_transform.affine_inverse()*reference_skeleton.global_transform
	return frame*reference_skeleton.get_bone_global_rest(_reference_index(semantic))

func _descends_from(index: int,ancestor: int) -> bool:
	if ancestor<0:return false
	var cursor:=index
	while cursor>=0:
		if cursor==ancestor:return true
		cursor=_parents[cursor]
	return false

func _fit_y(height: float) -> float:
	if height<=_fit_heights[0].x:return height
	for index: int in range(1,_fit_heights.size()):
		var first:=_fit_heights[index-1];var second:=_fit_heights[index]
		if height<=second.x:return lerpf(first.y,second.y,inverse_lerp(first.x,second.x,height))
	var end: Vector2=_fit_heights.back();return height+end.y-end.x

func _fit_point(point: Vector3) -> Vector3:
	var offset:=Vector2.ZERO
	if point.y>_fit_planar_offsets[0].x:
		offset=Vector2(_fit_planar_offsets.back().y,_fit_planar_offsets.back().z)
		for index: int in range(1,_fit_planar_offsets.size()):
			var first:=_fit_planar_offsets[index-1];var second:=_fit_planar_offsets[index]
			if point.y<=second.x:
				offset=Vector2(first.y,first.z).lerp(Vector2(second.y,second.z),inverse_lerp(first.x,second.x,point.y));break
	return Vector3(point.x+offset.x,_fit_y(point.y),point.z+offset.y)

func _prepare_reference_fit() -> bool:
	# Fit only the new body's upper torso/neck to the already-normalized head.
	# Height and forward/back centers vary continuously through the spine.
	# Arms move as rigid chains: no anatomical limb stretch or rest/bind edits.
	for semantic: String in ["Spine2","Neck","Head","LeftClavicle","RightClavicle","LeftUpperArm","RightUpperArm"]:
		if _reference_index(semantic)<0:return false
	if not _bones.has("neck01") or _find("Spine4")<0 or _find("Spine2")<0:return false
	_fit_neck_index=_bones.neck01
	var mid:=_rest_global[_find("Spine2")].origin
	var points: Array[Dictionary]=[{"from":mid,"to":mid},{"from":_rest_global[_find("Spine4")].origin,"to":_reference_rest("Spine2").origin}]
	for semantic: String in ["UpperArm","Clavicle"]:
		var source:=(_rest_global[_find("Left"+semantic)].origin+_rest_global[_find("Right"+semantic)].origin)*.5
		var target:=(_reference_rest("Left"+semantic).origin+_reference_rest("Right"+semantic).origin)*.5
		points.append({"from":source,"to":target})
	points.append({"from":_rest_global[_fit_neck_index].origin,"to":_reference_rest("Neck").origin})
	points.append({"from":_rest_global[_find("Head")].origin,"to":_reference_rest("Head").origin})
	points.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.from.y<b.from.y)
	for point: Dictionary in points:
		var source: Vector3=point.from;var target: Vector3=point.to
		_fit_heights.append(Vector2(source.y,target.y))
		_fit_planar_offsets.append(Vector3(source.y,target.x-source.x,target.z-source.z))
	for index: int in range(1,_fit_heights.size()):
		if _fit_heights[index].x<=_fit_heights[index-1].x or _fit_heights[index].y<=_fit_heights[index-1].y:return false
	_fitted_rest_global=_rest_global.duplicate()
	var arm_offsets:={}
	for side: String in ["Left","Right"]:
		arm_offsets[side]=_reference_rest(side+"UpperArm").origin-_rest_global[_find(side+"UpperArm")].origin
	for index: int in range(_fitted_rest_global.size()):
		if not _is_upper_body_bone(index):continue
		var at:=_rest_global[index].origin;var arm:=false
		for side: String in ["Left","Right"]:
			if _descends_from(index,_find(side+"UpperArm")):
				at+=Vector3(arm_offsets[side]);arm=true;break
		if not arm:at=_fit_point(at)
		_fitted_rest_global[index].origin=at
	var anchors: Array=[];var planar_anchors: Array=[]
	for at: Vector2 in _fit_heights:anchors.append([at.x,at.y])
	for at: Vector3 in _fit_planar_offsets:planar_anchors.append([at.x,at.y,at.z])
	_fit_diagnostics={"enabled":true,"method":"continuous_upper_torso_neck_height_and_center_fit_to_original_head_skeleton","original_import_rests_modified":false,"original_head_moved":false,"hips_and_legs_fitted":false,"arm_chains_translated_without_stretching":true,"height_anchors_m":anchors,"height_and_planar_offset_anchors_m":planar_anchors,"source_neck_base_y_m":_rest_global[_fit_neck_index].origin.y,"fitted_neck_base_y_m":_fitted_rest_global[_fit_neck_index].origin.y,"source_head_joint_y_m":_rest_global[_find("Head")].origin.y,"fitted_head_joint_y_m":_fitted_rest_global[_find("Head")].origin.y}
	return true

func _apply_reference_fit_rest() -> void:
	if _fitted_rest_global.is_empty():return
	for index: int in range(_poses.size()):_poses[index]=_fitted_rest_global[index] if _parents[index]<0 else _fitted_rest_global[_parents[index]].affine_inverse()*_fitted_rest_global[index]
	_rebuild_globals()

func _source_node(title: String) -> Node3D:
	if title=="Pelvis":return avatar.get("_pelvis") as Node3D
	if title=="Head":return avatar.find_child("Head",true,false) as Node3D
	if title.ends_with("Hand"):
		var hands: Variant=avatar.get("_hands")
		if hands is Array and hands.size()==2:return hands[0 if title.begins_with("Left") else 1] as Node3D
	var joints: Variant=avatar.get("_joints")
	return joints.get(title) as Node3D if joints is Dictionary else null

func _source_pose(node: Node3D) -> Transform3D:
	# The imported model and markers share the camera/NPC render proxy. Reading
	# both in skeleton coordinates cancels that presentation-root translation.
	var value:=skeleton.global_transform.affine_inverse()*node.global_transform
	value.basis=value.basis.orthonormalized();return value

func _calibrate_segment(semantic: String,child_semantic: String) -> void:
	var index:=_find(semantic);var child_index:=_find(child_semantic)
	var native_axis:=(_rest_global[child_index].origin-_rest_global[index].origin).normalized()
	var source_axis: Vector3=(_source_reference[child_semantic].origin-_source_reference[semantic].origin).normalized()
	var neutral:=Basis(_safe_between(native_axis,source_axis))*_rest_global[index].basis
	_corrections[semantic]=_source_reference[semantic].basis.inverse()*neutral

func _safe_between(from: Vector3,to: Vector3) -> Quaternion:
	if from.length_squared()<.000001 or to.length_squared()<.000001:return Quaternion.IDENTITY
	return Quaternion(from.normalized(),to.normalized()).normalized()

func _hand_contact(index: int) -> Vector3:
	# Biped Hand is the wrist. The midpoint towards first finger joints is a
	# palm contact, rather than incorrectly treating that wrist as the grip.
	var sum:=Vector3.ZERO;var count:=0
	for child: int in skeleton.get_bone_children(index):
		if "finger" in _normal_name(skeleton.get_bone_name(child)):
			sum+=_rest_global[child].origin;count+=1
	if count==0:return Vector3.ZERO
	var palm:=_rest_global[index].origin.lerp(sum/float(count),.50)
	return _rest_global[index].affine_inverse()*palm

func _process(_delta: float) -> void:
	if loaded:sync_pose()

func _rebuild_globals() -> void:
	for index: int in range(_poses.size()):_global_poses[index]=_poses[index] if _parents[index]<0 else _global_poses[_parents[index]]*_poses[index]

func _set_global(index: int,pose: Transform3D) -> void:
	if index<0:return
	var parent:=_parents[index]
	_poses[index]=pose if parent<0 else _global_poses[parent].affine_inverse()*pose
	_rebuild_globals()

func _set_rotation(index: int,basis: Basis) -> void:
	var value:=_global_poses[index];value.basis=basis.orthonormalized();_set_global(index,value)

func _aligned_basis(semantic: String,source_pose: Transform3D,target_direction: Vector3,child_index: int) -> Basis:
	var index:=_find(semantic)
	var suggested: Basis=(source_pose.basis*_corrections[semantic]).orthonormalized()
	var rest_axis_local:=_rest_global[index].basis.inverse()*(_rest_global[child_index].origin-_rest_global[index].origin)
	return Basis(_safe_between(suggested*rest_axis_local,target_direction))*suggested

func _two_bone(upper_name: String,lower_name: String,end_name: String,goal: Vector3,pole_hint: Vector3) -> void:
	var upper:=_find(upper_name);var lower:=_find(lower_name);var ending:=_find(end_name)
	var start:=_global_poses[upper].origin
	var length_a:=_rest_global[lower].origin.distance_to(_rest_global[upper].origin)
	var length_b:=_rest_global[ending].origin.distance_to(_rest_global[lower].origin)
	var offset:=goal-start;var distance:=offset.length()
	var reach:=clampf(distance,absf(length_a-length_b)+.0001,length_a+length_b-.0001)
	_maximum_reach_clamp_m=maxf(_maximum_reach_clamp_m,absf(reach-distance)*skeleton.global_basis.get_scale().abs().x)
	var direction:=offset.normalized() if distance>.00001 else Vector3.DOWN
	var pole:=pole_hint-start;pole-=direction*pole.dot(direction)
	if pole.length_squared()<.00001:
		pole=Vector3.FORWARD-direction*Vector3.FORWARD.dot(direction)
		if pole.length_squared()<.00001:pole=Vector3.RIGHT-direction*Vector3.RIGHT.dot(direction)
	pole=pole.normalized()
	var along:=(length_a*length_a-length_b*length_b+reach*reach)/(2.*reach)
	var middle:=start+direction*along+pole*sqrt(maxf(0.,length_a*length_a-along*along))
	var end:=start+direction*reach
	_set_rotation(upper,_aligned_basis(upper_name,_source_pose(_source_node(upper_name)),middle-start,lower))
	_set_rotation(lower,_aligned_basis(lower_name,_source_pose(_source_node(lower_name)),end-middle,ending))

func _is_upper_body_bone(index: int) -> bool:
	var spine:=_find("Spine");var left_thigh:=_find("LeftThigh");var right_thigh:=_find("RightThigh")
	var cursor:=index
	while cursor>=0:
		if cursor==left_thigh or cursor==right_thigh:return false
		if cursor==spine:return true
		cursor=_parents[cursor]
	return false

func _contact_hinge(angle: float) -> Transform3D:
	var axis: Vector3=(skeleton.global_basis.inverse()*avatar.global_basis.x).normalized()
	var turn:=Basis(axis,-angle);var pivot:=_global_poses[_find("Pelvis")].origin
	return Transform3D(turn,pivot-turn*pivot)

func _contact_reach_error(angle: float) -> float:
	var hinge:=_contact_hinge(angle);var maximum:=0.
	for side: String in ["Left","Right"]:
		var upper:=_find(side+"UpperArm");var lower:=_find(side+"Forearm");var hand:=_find(side+"Hand")
		var basis: Basis=(_source_pose(_source_node(side+"Forearm")).basis*_corrections[side+"Hand"]).orthonormalized()
		var target: Vector3=_source_pose(_source_node(side+"Hand")).origin-basis*_hand_contacts[side]
		var reach:=_rest_global[upper].origin.distance_to(_rest_global[lower].origin)+_rest_global[lower].origin.distance_to(_rest_global[hand].origin)-.0001
		maximum=maxf(maximum,(hinge*_global_poses[upper].origin).distance_to(target)-reach)
	return maximum

func _apply_contact_lean() -> void:
	_contact_lean_radians=0.
	if not _contact_mode or _contact_reach_error(0.)<.0001:return
	# Search the smallest actual forward hip hinge that makes both hands
	# reachable with original limb lengths. Upper body, clavicles and head
	# share the hinge; the legs/pelvis and all equipment targets stay fixed.
	var best_error:=_contact_reach_error(0.)
	for step: int in range(1,51):
		var angle:=MAX_CONTACT_LEAN_RADIANS*float(step)/50.
		var error:=_contact_reach_error(angle)
		if error<best_error:best_error=error;_contact_lean_radians=angle
		if error<.0001:
			# Remove the coarse search's visible half-degree staircase. Read
			# interpolated marker goals and solve a continuous minimal hinge.
			var low:=MAX_CONTACT_LEAN_RADIANS*float(step-1)/50.;var high:=angle
			for iteration: int in range(10):
				var middle:=(low+high)*.5
				if _contact_reach_error(middle)<.0001:high=middle
				else:low=middle
			_contact_lean_radians=high;break
	if _contact_lean_radians<=0.:return
	var hinge:=_contact_hinge(_contact_lean_radians);var targets: Array[Transform3D]=_global_poses.duplicate()
	for index: int in range(targets.size()):
		if _is_upper_body_bone(index):targets[index]=hinge*targets[index]
	for index: int in range(targets.size()):_poses[index]=targets[index] if _parents[index]<0 else targets[_parents[index]].affine_inverse()*targets[index]
	_rebuild_globals()

func _prepare_ground_pelvis(pelvis: int) -> void:
	# Feet retain actual contact targets. A single pelvis displacement meets
	# both native leg reaches, instead of pulling each hip out of its socket.
	var player: Variant=avatar.get("player")
	var walking: bool=String(avatar.get("state")) in ["walk","run"] or (String(avatar.get("state"))=="idle" and float(avatar.get("walk_weight"))>.001)
	_ground_gait=walking and not _contact_mode and String(avatar.get("_activity_kind")).is_empty() and not (is_instance_valid(player) and player.get("facility_control")==true)
	_pelvis_gait_turn=Basis.IDENTITY;_pelvis_yaw_radians=0.;_pelvis_roll_radians=0.
	if not _ground_gait:return
	_pelvis_gait_turn=(_source_pose(_source_node("Pelvis")).basis*_source_reference.Pelvis.basis.inverse()).orthonormalized()
	var source_pelvis:=_source_node("Pelvis")
	_pelvis_yaw_radians=source_pelvis.rotation.y;_pelvis_roll_radians=source_pelvis.rotation.z
	var initial:=_rest_global[pelvis];initial.basis=_pelvis_gait_turn*initial.basis
	_set_global(pelvis,initial)
	var drop:=0.
	for side: String in ["Left","Right"]:
		var thigh:=_find(side+"Thigh");var shin:=_find(side+"Shin");var foot:=_find(side+"Foot")
		var hip:=_global_poses[thigh].origin;var goal: Vector3=_source_pose(_source_node(side+"Foot")).origin+_foot_offsets[side]
		var length:=_rest_global[thigh].origin.distance_to(_rest_global[shin].origin)+_rest_global[shin].origin.distance_to(_rest_global[foot].origin)-.0002
		var horizontal:=Vector2(hip.x-goal.x,hip.z-goal.z).length()
		drop=minf(drop,goal.y+sqrt(maxf(.0001,length*length-horizontal*horizontal))-hip.y)
	_last_hip_delta=Vector3(0.,drop,0.)
	initial.origin+=_last_hip_delta;_set_global(pelvis,initial)

func sync_pose() -> bool:
	if not loaded or not is_instance_valid(avatar) or not is_instance_valid(skeleton):return false
	_poses=_rest.duplicate();_global_poses=_rest_global.duplicate();_goals.clear();_maximum_reach_clamp_m=0.
	_apply_reference_fit_rest()
	var player: Variant=avatar.get("player")
	var activity:=String(avatar.get("_activity_kind"))
	_contact_mode=activity in ["eat","weights","cycle","rowing"] or (activity in ["","rope"] and is_instance_valid(player) and player.get("facility_control")==true)
	var pelvis:=_find("Pelvis");var pelvis_pose:=_rest_global[pelvis]
	_last_hip_delta=_source_pose(_source_node("Pelvis")).origin-_source_pelvis_reference
	pelvis_pose.origin+=_last_hip_delta;_set_global(pelvis,pelvis_pose)
	_prepare_ground_pelvis(pelvis)
	var upper_pose:=_source_pose(_source_node("UpperBody"))
	var upper_delta: Basis=(upper_pose.basis*_source_reference.UpperBody.basis.inverse()).orthonormalized()
	var spine_bones: Array[int]=[]
	for key: String in ["bip01spine","bip01spine1","bip01spine2","bip01spine3","bip01spine4"]:
		if _bones.has(key):spine_bones.append(_bones[key])
	if spine_bones.is_empty():spine_bones.append(_find("Spine"))
	for index: int in range(spine_bones.size()):
		var bone:=spine_bones[index];var weight:=float(index+1)/float(spine_bones.size())
		var spine_pose:=_global_poses[bone]
		# The retained gait lowers only the hips to meet leg reach, while its
		# upper body/head deliberately remain level. Do not reintroduce a head
		# bob by blindly inheriting that pelvis displacement through the spine.
		if index==0 and not _ground_gait:spine_pose.origin=_rest_global[bone].origin+(upper_pose.origin-_source_reference.UpperBody.origin)
		spine_pose.basis=Basis(Quaternion.IDENTITY.slerp(upper_delta.get_rotation_quaternion(),weight))*_rest_global[bone].basis
		if _ground_gait and index==0:spine_pose.basis=_pelvis_gait_turn*spine_pose.basis
		_set_global(bone,spine_pose)
	var head:=_find("Head");var head_pose:=_source_pose(_source_node("Head"))
	var target_head:=_global_poses[head];var base_head:=_rest_global[head] if _fitted_rest_global.is_empty() else _fitted_rest_global[head]
	target_head.origin=base_head.origin+(head_pose.origin-_source_reference.Head.origin)+(_last_hip_delta if _ground_gait else Vector3.ZERO)
	target_head.basis=head_pose.basis*_source_reference.Head.basis.inverse()*_rest_global[head].basis;_set_global(head,target_head)
	_apply_contact_lean()
	for side: String in ["Left","Right"]:
		var foot:=_find(side+"Foot");var source_foot:=_source_pose(_source_node(side+"Foot"))
		var foot_goal: Vector3=source_foot.origin+_foot_offsets[side]
		# Rocketbox thighs are children of Spine rather than Pelvis. Restore
		# the independent game hip displacement explicitly after stabilizing
		# the upper body, using this model's true leg reach for the stance.
		var thigh:=_find(side+"Thigh");var shin:=_find(side+"Shin")
		var thigh_pose:=_global_poses[thigh]
		if not _ground_gait:thigh_pose.origin=_rest_global[thigh].origin+_last_hip_delta
		var maximum_leg:=_rest_global[thigh].origin.distance_to(_rest_global[shin].origin)+_rest_global[shin].origin.distance_to(_rest_global[foot].origin)-.0002
		var horizontal:=Vector2(thigh_pose.origin.x-foot_goal.x,thigh_pose.origin.z-foot_goal.z).length()
		if not _ground_gait:thigh_pose.origin.y=minf(thigh_pose.origin.y,foot_goal.y+sqrt(maxf(.0001,maximum_leg*maximum_leg-horizontal*horizontal)))
		_set_global(thigh,thigh_pose)
		var knee_hint:=_source_pose(_source_node(side+"Shin")).origin
		_two_bone(side+"Thigh",side+"Shin",side+"Foot",foot_goal,knee_hint)
		_set_rotation(foot,source_foot.basis*_corrections[side+"Foot"])
		_goals[side+"Foot"]={"index":foot,"target":foot_goal,"contact":Vector3.ZERO,"required":true}
		var hand:=_find(side+"Hand");var source_hand:=_source_pose(_source_node(side+"Hand"));var source_forearm:=_source_pose(_source_node(side+"Forearm"))
		var hand_basis: Basis=(source_forearm.basis*_corrections[side+"Hand"]).orthonormalized()
		var contact: Vector3=_hand_contacts[side]
		var wrist_goal:=source_hand.origin-hand_basis*contact
		var elbow_hint:=_source_pose(_source_node(side+"Forearm")).origin
		if _contact_mode:_two_bone(side+"UpperArm",side+"Forearm",side+"Hand",wrist_goal,elbow_hint)
		else:
			# Ordinary walking uses the real model's anatomical segment lengths,
			# driven by the retained pose directions. The old long-arm marker is
			# an equipment target only while actual hands hold/use something.
			for segment: String in ["UpperArm","Forearm"]:
				var semantic:=side+segment;_set_rotation(_find(semantic),_source_pose(_source_node(semantic)).basis*_corrections[semantic])
		_set_rotation(hand,hand_basis)
		_goals[side+"Hand"]={"index":hand,"target":source_hand.origin,"contact":contact,"required":_contact_mode}
	_finite=true
	for index: int in range(_poses.size()):
		if not _poses[index].is_finite():_finite=false;return false
		skeleton.set_bone_pose(index,_poses[index])
	_frame_count+=1;return true

func snapshot() -> Dictionary:
	var errors:={};var maximum:=0.;var required_maximum:=0.
	if loaded:
		for semantic: String in _goals:
			var row: Dictionary=_goals[semantic]
			var actual: Vector3=skeleton.global_transform*(_global_poses[int(row.index)]*row.contact)
			var target: Vector3=skeleton.global_transform*row.target
			var error:=actual.distance_to(target);maximum=maxf(maximum,error)
			if row.required:required_maximum=maxf(required_maximum,error)
			errors[semantic]={"error_m":error,"required_contact":row.required,"actual_world":actual,"target_world":target}
	var fit:=_fit_diagnostics.duplicate(true)
	if loaded and is_instance_valid(reference_skeleton) and _fit_neck_index>=0:
		var actual_neck: Vector3=skeleton.global_transform*_global_poses[_fit_neck_index].origin
		var reference_neck: Vector3=reference_skeleton.global_transform*reference_skeleton.get_bone_global_pose(_reference_index("Neck")).origin
		var actual_head: Vector3=skeleton.global_transform*_global_poses[_find("Head")].origin
		var reference_head: Vector3=reference_skeleton.global_transform*reference_skeleton.get_bone_global_pose(_reference_index("Head")).origin
		fit["neck_base_height_error_m"]=actual_neck.y-reference_neck.y
		fit["neck_base_error_m"]=actual_neck.distance_to(reference_neck)
		fit["neck_base_offset_m"]=actual_neck-reference_neck
		fit["actual_neck_base_world_m"]=actual_neck
		fit["reference_neck_base_world_m"]=reference_neck
		fit["head_joint_height_error_m"]=actual_head.y-reference_head.y
		fit["head_joint_error_m"]=actual_head.distance_to(reference_head)
		fit["head_joint_offset_m"]=actual_head-reference_head
		fit["neck_vertical_span_m"]=reference_head.y-actual_neck.y
		var shoulder_errors:={};var shoulder_center_errors:={};var shoulder_offsets:={}
		for side: String in ["Left","Right"]:
			var actual: Vector3=skeleton.global_transform*_global_poses[_find(side+"UpperArm")].origin
			var reference: Vector3=reference_skeleton.global_transform*reference_skeleton.get_bone_global_pose(_reference_index(side+"UpperArm")).origin
			shoulder_errors[side]=actual.y-reference.y
			shoulder_center_errors[side]=actual.distance_to(reference);shoulder_offsets[side]=actual-reference
		fit["shoulder_height_errors_m"]=shoulder_errors
		fit["shoulder_center_errors_m"]=shoulder_center_errors
		fit["shoulder_offsets_m"]=shoulder_offsets
	return {"loaded":loaded,"load_error":load_error,"bone_count":skeleton.get_bone_count() if is_instance_valid(skeleton) else 0,"frames":_frame_count,"finite_bone_poses":_finite,"contacts":errors,"contact_mode":_contact_mode,"ground_gait_common_pelvis":_ground_gait,"pelvis_displacement_skeleton_m":_last_hip_delta,"pelvis_yaw_degrees":rad_to_deg(_pelvis_yaw_radians),"pelvis_roll_degrees":rad_to_deg(_pelvis_roll_radians),"contact_lean_degrees":rad_to_deg(_contact_lean_radians),"maximum_contact_lean_degrees":rad_to_deg(MAX_CONTACT_LEAN_RADIANS),"maximum_marker_gap_m":maximum,"maximum_contact_error_m":required_maximum,"maximum_unreachable_target_clamp_m":_maximum_reach_clamp_m,"source_joint_count":avatar.get("_joints").size() if is_instance_valid(avatar) else 0,"upper_body_reference_fit":fit,"pose_owner":"textured_human_rig_render_priority_100","godot_bone_pose_includes_rest":true,"physics_or_source_joints_modified":false}
