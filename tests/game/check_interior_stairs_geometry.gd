extends SceneTree
var room: Node3D
var actor: CharacterBody3D
var path: Array[Vector3] = []
var next := 0
var ticks := 0
var failures := 0
var case_index := 0
var start_tick := 0
var cases := [{"width":12.0,"depth":16.0,"floor_height":5.0,"floor_count":3},{"width":14.749181,"depth":57.301935,"floor_height":4.625,"floor_count":4},{"width":12.0,"depth":16.0,"floor_height":3.0,"floor_count":3}]
func _initialize() -> void:call_deferred("_begin")
func _begin() -> void:
	room = load("res://scripts/building_interior_space.gd").new()
	root.add_child(room)
	var good: bool = room.setup(cases[case_index],Vector3(650,-100,0))
	if not good:push_error("SPACE_SETUP_FAILED");quit(2);return
	actor = CharacterBody3D.new();actor.collision_layer=4;actor.collision_mask=1;actor.safe_margin=.001;actor.floor_snap_length=.1
	var collision := CollisionShape3D.new();var shape := CapsuleShape3D.new();shape.radius=.3;shape.height=1.7;collision.shape=shape;collision.position.y=.85
	actor.add_child(collision);root.add_child(actor)
	path.clear()
	for level in range(room.floor_count-1):path.append_array(room.stair_path(level,true))
	for level in range(room.floor_count-1,0,-1):path.append_array(room.stair_path(level,false))
	actor.global_position=path[0];next=1;start_tick=ticks
func _physics_process(delta: float) -> bool:
	ticks+=1
	if not is_instance_valid(actor):return false
	if ticks-start_tick<4:return false
	if next>=path.size():
		var error := absf(actor.global_position.y-(-100.0))
		print("SPACE_WALK_CASE ",case_index," ticks=",ticks-start_tick," floor_error=",error," bodies=",room.bodies.size()," people=",room.people.size())
		if error>.2:failures+=1
		actor.free();room.free();case_index+=1
		if case_index>=cases.size():print("SPACE_WALK_DONE failures=",failures);quit(failures);return false
		_begin();return false
	var target: Vector3=path[next]
	var offset := Vector3(target.x-actor.global_position.x,0,target.z-actor.global_position.z)
	if offset.length()<.12:
		if absf(actor.global_position.y-target.y)>.30:
			print("BAD_WAYPOINT index=",next," actual=",actor.global_position," target=",target);failures+=1
		next+=1;return false
	var direction := offset.normalized()
	actor.velocity.x=direction.x*3.5;actor.velocity.z=direction.z*3.5
	if actor.is_on_floor():actor.velocity.y=0.0
	actor.velocity.y-=9.8*delta
	actor.move_and_slide()
	if ticks-start_tick>12000:
		print("SPACE_WALK_STUCK case=",case_index," index=",next," position=",actor.global_position," target=",target," grounded=",actor.is_on_floor());quit(3)
	return false
