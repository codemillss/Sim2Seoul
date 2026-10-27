extends SceneTree
var scene: Node3D
func _initialize()->void:run.call_deferred()
func run()->void:
 scene=load("res://scenes/world/explore_walk.tscn").instantiate()
 scene.exploration_settings_path="/private/tmp/s2s_walk_diag_absent_exploration.json"
 scene.quality_settings_path="/private/tmp/s2s_walk_diag_absent_quality.json"
 scene.character_settings_path="/private/tmp/s2s_walk_diag_absent_character.json"
 root.add_child(scene)
 for frame in range(4):await process_frame
 for tick in range(8):await physics_frame
 if scene.menu.visible:scene.toggle_menu()
 scene.set_pedestrians_running(false);scene.set_vehicles_running(false)
 await physics_frame
 var origin:=Vector3(120.163299560547,-.860539555549622,-107.709693908691)
 var goal:=Vector3(91.9013137817383,-.776779890060425,-93.5418395996094)
 var results: Array=[]
 var guard_points: Array=[]
 for angle: float in [0.0,PI/4.,-PI/4.,PI/2.,-PI/2.,PI]:
  var direction: Vector3=(goal-origin).normalized().rotated(Vector3.UP,angle)
  for dist: float in [.05,.2,.5,1.,2.]:
   var p: Vector3=origin+direction*dist
   guard_points.append({"angle":angle,"distance":dist,"point":[p.x,p.y,p.z],"inside":scene.player._inside(p)})
 var edges: Array=[]
 for polygon in scene.player.connection_world.private_cache:
  for ring in polygon:
   for i in range(ring.size()-1):
    var nearest: Vector2=Geometry2D.get_closest_point_to_segment(Vector2(origin.x,origin.z),ring[i],ring[i+1])
    if nearest.distance_to(Vector2(origin.x,origin.z))<3.0:
     edges.append({"distance":nearest.distance_to(Vector2(origin.x,origin.z)),"a":[ring[i].x,ring[i].y],"b":[ring[i+1].x,ring[i+1].y]})
 for elevation: float in [0.0,.08,.2]:
  var from: Transform3D=scene.player.global_transform;from.origin=origin+Vector3.UP*elevation
  for dist: float in [.5,2.0,10.0,32.0]:
   var result:=PhysicsTestMotionResult3D.new()
   var hit: bool=scene.player.test_move(from,(goal-origin).normalized()*dist,result,.001,false,16)
   var row: Dictionary={"origin":[from.origin.x,from.origin.y,from.origin.z],"distance":dist,"hit":hit,"colliders":[]}
   if hit:
    row.travel=[result.get_travel().x,result.get_travel().y,result.get_travel().z]
    for index in range(result.get_collision_count()):
     var collider: Object=result.get_collider(index);var normal: Vector3=result.get_collision_normal(index)
     row.colliders.append({"path":str(collider.get_path()) if collider is Node else str(collider),"class":collider.get_class(),"normal":[normal.x,normal.y,normal.z],"position":[collider.global_position.x,collider.global_position.y,collider.global_position.z] if collider is Node3D else [],"layer":collider.collision_layer if collider is CollisionObject3D else -1})
   results.append(row)
 var f:=FileAccess.open("/Users/jmjeon/Desktop/jobseeker/원서_제출/02_핵심프로젝트_마스터풀/sim2seoul/data/reports/shared_city/20261027/shared_actors_walk_blocker_query02.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"task":"EXP41_TEST_ROUTE_BLOCKER_QUERY","scope":"Prospective actual production CharacterBody capsule sweeps at attempt10 stall coordinate; no actor transform writes. Fresh standalone full city, not exact attempt10 dynamic actor state.","player_mask":scene.player.collision_mask,"shape_disabled":scene.player.get_node("CollisionShape").disabled,"queries":results,"guard_points":guard_points,"near_private_edges":edges},"  "));f.close();f=null
 scene.queue_free();await process_frame;await process_frame
 await create_timer(.1).timeout
 quit(0)
