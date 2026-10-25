extends RefCounted
## Schedules only the skinned display retarget. Actor/action/physics clocks are
## untouched, and direct rig.sync_pose() calls never consult this scheduler.
static var total_sync_count := 0
static var total_skipped_count := 0
static var total_sync_usec := 0
var tier := "unclassified"
var sync_count := 0
var skipped_count := 0
var sync_usec := 0
var last_sync_usec := -1
var _interval_usec := 0
var _phase := 0
var _rig: Node3D
var _actor: Node3D
var _visual_root: Node3D
var _local_player := false

func configure(rig: Node3D,source_avatar: Node3D,visual: Node3D) -> void:
	_rig=rig;_actor=source_avatar.get("player") as Node3D;_visual_root=visual
	_local_player=is_instance_valid(_actor) and _actor.has_method("set_facility_control")
	_phase=absi(int(rig.get_instance_id()))%500_000

static func interval_for(distance_squared: float,visible: bool,in_frustum: bool,local_player: bool,phase:=0) -> int:
	if local_player or distance_squared<=100.0:return 0
	if not visible:return 1_000_000+posmod(phase,1_000_000)
	if distance_squared>10_000.0:return 500_000+posmod(phase,500_000)
	if not in_frustum:return 100_000+posmod(phase,100_000)
	return 33_333 if distance_squared<=900.0 else 100_000

func should_update(now_usec: int) -> bool:
	if not is_instance_valid(_rig) or not is_instance_valid(_actor):return true
	var camera:=_rig.get_viewport().get_camera_3d()
	if camera==null:return true
	var point:=_actor.global_position+Vector3.UP*.9
	var distance_squared:=camera.global_position.distance_squared_to(point)
	var visible:=is_instance_valid(_visual_root) and _visual_root.is_visible_in_tree()
	# Remote actors need only a distance check. Closer actors use the current
	# camera each frame so turning towards them resumes the latest pose at once.
	var in_frustum:=true
	if not _local_player and distance_squared>100.0 and distance_squared<=10_000.0 and visible:
		in_frustum=camera.is_position_in_frustum(point)
	var interval:=interval_for(distance_squared,visible,in_frustum,_local_player,_phase)
	var previous_interval:=_interval_usec
	_interval_usec=interval
	tier="local" if _local_player else ("near" if distance_squared<=100.0 else ("hidden" if not visible else ("remote" if distance_squared>10_000.0 else ("offscreen" if not in_frustum else ("visible_near" if distance_squared<=900.0 else "visible_far")))))
	if interval==0 or last_sync_usec<0 or interval<previous_interval or now_usec-last_sync_usec>=interval:return true
	skipped_count+=1;total_skipped_count+=1
	return false

func record_sync(start_usec: int,end_usec: int) -> void:
	last_sync_usec=end_usec
	var cost:=maxi(0,end_usec-start_usec)
	sync_count+=1;total_sync_count+=1
	sync_usec+=cost;total_sync_usec+=cost

func snapshot() -> Dictionary:
	return {"tier":tier,"syncs":sync_count,"skips":skipped_count,"sync_ms":snappedf(float(sync_usec)/1000.0,.01),"interval_ms":float(_interval_usec)/1000.0,"local_player":_local_player}

static func totals() -> Dictionary:
	return {"syncs":total_sync_count,"skips":total_skipped_count,"sync_usec":total_sync_usec}
