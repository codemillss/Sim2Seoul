extends SceneTree
var host
var output := "/private/tmp/street-businesses-setup.json"
func _initialize() -> void:_run.call_deferred()
func _desc(node: Node) -> Array:
 var out := []
 for child in node.get_children():out.append(child);out.append_array(_desc(child))
 return out
func _inventory() -> Dictionary:
 var result := {}
 for node in _desc(host.city):
  if node is CollisionObject3D:
   var shapes := []
   for child in node.get_children():
    if child is CollisionShape3D:shapes.append([child.get_instance_id(),child.shape.get_instance_id(),child.transform,child.disabled])
   result[str(node.get_instance_id())]=[node.global_transform,node.collision_layer,node.collision_mask,shapes]
 return result
func _json(v):
 if v is Vector3:return [v.x,v.y,v.z]
 if v is Vector2:return [v.x,v.y]
 if v is Transform3D:return {"origin":_json(v.origin),"basis":[_json(v.basis.x),_json(v.basis.y),_json(v.basis.z)]}
 if v is AABB:return {"position":_json(v.position),"size":_json(v.size)}
 if v is Dictionary:
  var o := {}
  for k in v:o[str(k)]=_json(v[k])
  return o
 if v is Array:
  var a := []
  for item in v:a.append(_json(item))
  return a
 return v
func _run() -> void:
 host=load("res://scenes/world/explore_walk.tscn").instantiate()
 host.exploration_settings_path="/private/tmp/street-business-probe-exploration.json"
 host.quality_settings_path="/private/tmp/street-business-probe-quality.json"
 root.add_child(host)
 for index in range(5):await physics_frame
 var before := _inventory()
 var business=load("res://scripts/street_businesses.gd").new();host.add_child(business)
 var accepted: bool=business.setup(host.city,host.player,host.rig)
 for index in range(5):await physics_frame
 var checks := {"host_runtime_ok":host.runtime_ok,"setup_accepted":accepted,"four_source_stores":business.stores.size()==4,"original_source_collision_unchanged":before==_inventory()}
 var rows := []
 var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/street_businesses.json"))
 for row: Dictionary in raw.records:
  var point: Vector3=host.city.to_global(Vector3(row.approach_xz[0],.08,row.approach_xz[1]))
  var capsule: CollisionShape3D=host.player.get_node("CollisionShape")
  var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.transform=Transform3D(Basis.IDENTITY,point)*capsule.transform;query.collision_mask=host.player.collision_mask;query.exclude=[host.player.get_rid()]
  var hits := root.get_world_3d().direct_space_state.intersect_shape(query,8)
  var support := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.5,point-Vector3.UP*.5,host.player.collision_mask,[host.player.get_rid()]))
  var good: bool=hits.is_empty() and not support.is_empty() and absf(support.position.y)<.04
  checks["approach_clear_"+String(row.id)]=good
  rows.append({"id":row.id,"point":point,"capsule_hits":hits.size(),"support":support.get("position",Vector3.INF)})
 var colliders:=0;var geometry:=0;var labels:=0
 for node in _desc(business):
  if node is CollisionObject3D or node is CollisionShape3D:colliders+=1
  if node is GeometryInstance3D:geometry+=1
  if node is Label3D:labels+=1
 checks["actual_no_new_colliders"]=colliders==0
 checks["actual_geometry_and_hangul_signs"]=geometry>30 and labels>=12
 var found_names := {}
 for node in _desc(business):
  if node is Label3D and node.text in ["진주회관","GS25","emart24","CU"]:found_names[node.text]=true
 checks["four_actual_distinct_store_names"]=found_names.size()==4
 var ok:=true
 for k in checks:ok=ok and checks[k]
 var result:={"result":"PASS" if ok else "FAIL","checks":checks,"approaches":rows,"source_bodies_before":before.size(),"actual_geometry_nodes":geometry,"actual_label_nodes":labels,"snapshot":business.snapshot(),"source_sha256":{"business_script":FileAccess.get_sha256("res://scripts/street_businesses.gd"),"catalog":FileAccess.get_sha256("res://assets/authored/street_businesses.json")},"scope":"Actual latest exploration city startup and 4-store setup, original source body/shape transforms/layers preserved, real capsule+support query at authored facade approaches. Headless only; no GPU visual acceptance or new shop entry claim."}
 var f:=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify(_json(result),"\t")+"\n");f.close()
 print("STREET_BUSINESSES_SETUP ",result.result," checks=",checks.size()," source_bodies=",before.size()," geometry=",geometry," labels=",labels)
 quit(0 if ok else 1)
