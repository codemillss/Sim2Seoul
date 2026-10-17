extends Node3D
## Local one-player administrator access to authored hotel guest rooms only.
## Door leaves keep their real collider throughout a short sliding motion.
const INTERACTION_RANGE_M := 1.75
const OPEN_SECONDS := .65
var host: Node3D
var visit: Node3D
var admin_access := true
var opened_count := 0
var closed_count := 0
var locked_rejections := 0
var blocked_closures := 0
var _notice := ""
var _notice_seconds := 0.0
var _last_room_id := 0
var _door_marker: Label3D

func setup(host_scene: Node3D,visit_controller: Node3D) -> bool:
	if not is_instance_valid(host_scene) or not is_instance_valid(visit_controller):return false
	host=host_scene;visit=visit_controller;name="InteriorRoomAccess";process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=1
	_door_marker=Label3D.new();_door_marker.name="GuestDoorAction";_door_marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;_door_marker.font_size=23;_door_marker.pixel_size=.0035;_door_marker.outline_size=4;_door_marker.modulate=Color(.98,.92,.72);_door_marker.visible=false;add_child(_door_marker)
	return true

func set_admin_access(enabled: bool) -> void:
	admin_access=enabled
	_notice="관리자 마스터키를 켰습니다." if enabled else "객실 외부 잠금이 적용됩니다. 객실 안에서는 나갈 수 있습니다."
	_notice_seconds=3.0

func _context() -> bool:
	return is_instance_valid(host) and is_instance_valid(visit) and visit.active and not visit.on_roof and not visit.in_elevator and not visit.elevator_open and is_instance_valid(visit.room) and not host.menu.visible and not host.player.facility_control

func _doors() -> Array:return visit.room.guest_doors if is_instance_valid(visit.room) else []

func _nearest() -> Dictionary:
	if not _context() or not host.player.is_on_floor() or host.player.input_latched:return {}
	var nearest := INTERACTION_RANGE_M;var result: Dictionary={}
	var level: int=visit.room.floor_index_at(host.player.global_position)
	for door: Dictionary in _doors():
		if int(door.level)!=level:continue
		var anchor: Vector3=visit.room.to_global(door.door_point)
		var difference: Vector3=host.player.global_position-anchor
		if absf(difference.y)>.30:continue
		var distance := Vector2(difference.x,difference.z).length()
		if distance>nearest:continue
		var ray := PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP*1.1,anchor+Vector3.UP*1.1,host.player.collision_mask,[host.player.get_rid()])
		var hit: Dictionary=host.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider!=door.body:continue
		nearest=distance;result=door
	return result

func _inside(door: Dictionary) -> bool:
	var point: Vector3=visit.room.to_local(host.player.global_position)
	return (point.x-float(door.door_point.x))*float(door.side)>.18

func _closing_blocked(door: Dictionary) -> bool:
	# Check the complete swept leaf envelope, rather than just its final pose.
	# The unchanged player capsule is the physical occupant of that volume.
	var shape := BoxShape3D.new();shape.size=Vector3(.15,float(door.height)+.04,1.02+absf(float(door.slide_offset.z))+.06)
	var center: Vector3=door.closed_position+door.slide_offset*.5
	var query := PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=visit.room.global_transform*Transform3D(Basis.IDENTITY,center);query.collision_mask=host.player.collision_layer;query.exclude=[door.body.get_rid()]
	return not host.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func handle_interact() -> bool:
	var door := _nearest()
	if door.is_empty():return false
	if float(door.target_fraction)>.5:
		if _closing_blocked(door):
			blocked_closures+=1;_notice="문 이동 구간에 사람이 있습니다. 비운 뒤 닫아주세요.";_notice_seconds=3.0;return true
		door.target_fraction=0.0;closed_count+=1;return true
	if bool(door.locked) and not admin_access and not _inside(door):
		locked_rejections+=1;_notice="잠긴 객실입니다 · Esc에서 관리자 마스터키를 켜세요.";_notice_seconds=3.0;return true
	door.locked=false;door.target_fraction=1.0;opened_count+=1
	_notice="%03d호 · 관리자 마스터키로 열었습니다."%int(door.number) if admin_access else "%03d호 · 객실 안에서 나가기"%int(door.number);_notice_seconds=2.0
	return true

func status_hint() -> String:
	if not _context():return ""
	if _notice_seconds>0.0:return _notice
	var door := _nearest()
	if door.is_empty():return ""
	if float(door.target_fraction)>.5:return "E · %03d호 문 닫기"%int(door.number)
	if bool(door.locked) and not admin_access and not _inside(door):return "잠긴 객실 · 관리자 마스터키 필요 · Esc"
	return "E · %03d호 문 열기%s"%[int(door.number)," · 관리자 마스터키" if admin_access else " · 안에서 나가기"]

func _physics_process(delta: float) -> void:
	if not is_instance_valid(host) or not is_instance_valid(visit):return
	if not _context():
		if is_instance_valid(_door_marker):_door_marker.visible=false
		return
	if visit.room.get_instance_id()!=_last_room_id:_last_room_id=visit.room.get_instance_id();_notice_seconds=0.0
	_notice_seconds=maxf(0.0,_notice_seconds-delta)
	for door: Dictionary in _doors():
		var closing: bool=float(door.target_fraction)<float(door.fraction)
		if closing and _closing_blocked(door):
			blocked_closures+=1;door.target_fraction=1.0;_notice="끼임을 막기 위해 문을 다시 열었습니다.";_notice_seconds=3.0
		door.fraction=move_toward(float(door.fraction),float(door.target_fraction),maxf(0.0,delta)/OPEN_SECONDS)
		door.body.position=door.closed_position+door.slide_offset*float(door.fraction)
		if float(door.fraction)<=.0001:door.locked=true
		var label: Label3D=door.label
		label.text="%03d\n%s"%[int(door.number),"잠김 · E" if bool(door.locked) else "열림 · E"]
		label.visible=int(door.level)==visit.room.active_floor
	var nearest := _nearest();_door_marker.visible=not nearest.is_empty()
	if _door_marker.visible:
		_door_marker.global_position=visit.room.to_global(nearest.door_point)+Vector3.UP*2.05;_door_marker.text=status_hint()

func snapshot() -> Dictionary:
	return {"admin_access":admin_access,"scope":"authored_hotel_guest_rooms_only","opened_count":opened_count,"closed_count":closed_count,"locked_rejections":locked_rejections,"blocked_closures":blocked_closures,"hint":status_hint(),"doors":visit.room.guest_door_snapshot() if is_instance_valid(visit) and is_instance_valid(visit.room) else [],"active":_context()}
