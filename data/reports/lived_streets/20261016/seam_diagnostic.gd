extends "res://../tests/game/check_lived_streets.gd"
class StandProbe extends CharacterBody3D:
 func _physics_process(delta: float) -> void:
  velocity=Vector3(0,-.12 if is_on_floor() else velocity.y-9.8*delta,0);move_and_slide()
const TARGET := Vector3(-235.609191894531,2.56493878364563,14.4173154830933)
func _hit(point: Vector3,span: float) -> Dictionary:
 var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*span,point-Vector3.UP*span,1|32))
 if hit.is_empty():return {"hit":false}
 return {"hit":true,"position":hit.position,"normal":hit.normal,"body":String(hit.collider.name),"shape_index":hit.shape}
func _run() -> void:
 scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/private/tmp/seam-diagnostic-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene);await _ticks(12)
 if scene.menu.visible:await _menu_edge()
 scene.street_pedestrians.set_running(false);await _ticks(3)
 var rays:=[]
 for step in [0.,.000001,.00001,.0001,.001,.01,.03,.10]:
  for offset: Vector3 in ([Vector3.ZERO] if step==0. else [Vector3(step,0,0),Vector3(-step,0,0),Vector3(0,0,step),Vector3(0,0,-step)]):
   var p:=TARGET+offset
   rays.append({"offset":offset,"actual_position":p,"result":_hit(p,.65)})
 var spans:=[]
 for span in [.15,.3,.65,1.,2.,5.]:spans.append({"span":span,"result":_hit(TARGET,span)})
 var near:=[]
 for body: StaticBody3D in scene.museum_approach.bodies:
  for child in body.get_children():
   if not child is CollisionShape3D or not child.shape is ConvexPolygonShape3D:continue
   var ps: PackedVector3Array=child.shape.points
   if ps.size()<3:continue
   var a: Vector3=child.to_global(ps[0]);var b: Vector3=child.to_global(ps[1]);var c: Vector3=child.to_global(ps[2]);var at:=Vector2(TARGET.x,TARGET.z)
   var aa:=Vector2(a.x,a.z);var bb:=Vector2(b.x,b.z);var cc:=Vector2(c.x,c.z)
   var mind:=minf(at.distance_to(Geometry2D.get_closest_point_to_segment(at,aa,bb)),minf(at.distance_to(Geometry2D.get_closest_point_to_segment(at,bb,cc)),at.distance_to(Geometry2D.get_closest_point_to_segment(at,cc,aa))))
   if mind>.002:continue
   var den: float=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
   if absf(den)<.0000001:continue
   var u: float=((b.z-c.z)*(TARGET.x-c.x)+(c.x-b.x)*(TARGET.z-c.z))/den
   var v: float=((c.z-a.z)*(TARGET.x-c.x)+(a.x-c.x)*(TARGET.z-c.z))/den
   var w:=1.-u-v;var plane:=Plane(a,b,c)
   near.append({"body":String(body.name),"shape":String(child.name),"top_triangle":[a,b,c],"edge_distance_m":mind,"barycentric":[u,v,w],"surface_y_m":a.y*u+b.y*v+c.y*w,"normal":plane.normal})
 var actor: Dictionary={}
 for row: Dictionary in scene.street_pedestrians.actors:
  if row.body.name=="museum_slope_walker":actor=row
 var body:=StandProbe.new();body.name="FreshDiagnosticStandCapsule";body.collision_layer=0;body.collision_mask=1|32;body.safe_margin=.001;body.floor_snap_length=.35;body.floor_max_angle=deg_to_rad(42.)
 var node:=CollisionShape3D.new();node.name="CollisionShape";node.shape=actor.collider.shape.duplicate();node.transform=actor.collider.transform;body.add_child(node);scene.add_child(body);body.global_position=TARGET+Vector3.UP*.06;await _ticks(30)
 var contacts:=[]
 for i in range(body.get_slide_collision_count()):
  var collision: KinematicCollision3D=body.get_slide_collision(i)
  contacts.append({"normal":collision.get_normal(),"point":collision.get_position(),"collider":String(collision.get_collider().name),"shape_index":collision.get_collider_shape_index()})
 var capsule: CollisionShape3D=body.get_node("CollisionShape");var casts:=[]
 for down in [.05,.1,.2]:
  var q:=PhysicsShapeQueryParameters3D.new();q.shape=capsule.shape;q.transform=capsule.global_transform;q.transform.origin+=Vector3.UP*.025;q.motion=Vector3.DOWN*down;q.collision_mask=1|32;q.margin=.001
  casts.append({"down_m":down,"fractions":Array(scene.get_world_3d().direct_space_state.cast_motion(q))})
 var report:={"task":"exact_native_support_failure_diagnostic","display":DisplayServer.get_name(),"target_from_native":TARGET,"source_sha256":{},"ray_offsets":rays,"ray_spans":spans,"actual_nearby_convex_top_triangles":near,"actual_character_stand_probe":{"explicit_diagnostic_start":TARGET+Vector3.UP*.06,"settled_position":body.global_position,"grounded":body.is_on_floor(),"floor_normal":body.get_floor_normal(),"floor_contacts":contacts,"capsule_down_casts":casts},"scope":"Read-only production geometry inspection; one actor explicitly repositioned only in this disposable diagnostic process, fresh independent actual capsule using move_and_slide settles for30ticks. No source or normal test acceptance changes."}
 for p in ["res://scripts/museum_approach.gd","res://assets/authored/museum_approach.json","res://scripts/street_pedestrians.gd","res://scripts/explore_walk.gd","res://../tests/game/check_lived_streets.gd","/private/tmp/check_lived_street_seam.gd"]:report.source_sha256[p]=FileAccess.get_sha256(p)
 var f:=FileAccess.open(report_path,FileAccess.WRITE);f.store_string(JSON.stringify(_json(report),"  "));f.close();finished=true;print("SEAM_DIAGNOSTIC saved ",report_path," grounded=",body.is_on_floor()," neartriangles=",near.size());quit(0)
