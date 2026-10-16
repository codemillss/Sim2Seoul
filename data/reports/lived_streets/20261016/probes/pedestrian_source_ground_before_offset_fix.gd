extends SceneTree
func _initialize()->void:run.call_deferred()
func ticks(n:int)->void:
 for i in range(n):await physics_frame
 await process_frame
func run()->void:
 var scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/private/tmp/street_ped_ground.settings.json";scene.quality_settings_path="/private/tmp/street_ped_ground.quality.json";root.add_child(scene);await ticks(12)
 var module=load("res://scripts/street_pedestrians.gd").new();scene.add_child(module);module.setup(scene.city,scene.player,scene.rig)
 var missing:=[];var sources:={}
 for group:Dictionary in module.groups:
  for i in range(int(ceil(group.length/.5))+1):
   for row:Dictionary in group.members:
    var p:Vector3=module._at(group,minf(group.length,i*.5),row.side)
    var ray:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*2.,p-Vector3.UP*2.,1)
    var hit:Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray)
    if hit.is_empty():missing.append([group.id,i,row.side])
    else:sources[hit.collider.name]=int(sources.get(hit.collider.name,0))+1
 scene.set_free_roam(false);await ticks(120)
 var grounded:=0
 for row:Dictionary in module.actors:
  if row.body.is_on_floor():grounded+=1
 print("NPC_SOURCE_GROUND missing=",missing," hits=",sources," free_roam_off_grounded=",grounded)
 quit(0 if missing.is_empty() and grounded==8 else 1)
