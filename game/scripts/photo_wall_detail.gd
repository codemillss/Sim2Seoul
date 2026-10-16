extends Node3D
## Rounded tile/rafter ends fitted inside the existing 2 m wall envelope.
var loaded := false
var load_error := ""
var tile_end_count := 0
var detail_mesh_count := 0
func setup(host: Node3D) -> bool:
 var body: StaticBody3D=host.city.fragments.get("W01_palace_wall")
 if body==null:load_error="돌담의 기존 충돌 형상을 찾지 못했습니다.";return false
 var shape: ConcavePolygonShape3D=body.get_node("CollisionShape").shape
 var vertices:=shape.get_faces()
 var edges:={};var counts:={}
 for index in range(0,vertices.size(),3):
  var tri:=[vertices[index],vertices[index+1],vertices[index+2]]
  if absf(tri[0].y-2.0)>0.001 or absf(tri[1].y-2.0)>0.001 or absf(tri[2].y-2.0)>0.001:continue
  var centre: Vector3=(tri[0]+tri[1]+tri[2])/3.0
  for side in range(3):
   var a: Vector3=tri[side];var b: Vector3=tri[(side+1)%3]
   var ka:="%.5f,%.5f"%[a.x,a.z];var kb:="%.5f,%.5f"%[b.x,b.z]
   var key:=ka+":"+kb if ka<kb else kb+":"+ka
   counts[key]=int(counts.get(key,0))+1;edges[key]=[a,b,centre]
 var poses:=[]
 for key in edges:
  if counts[key]!=1:continue
  var a: Vector3=edges[key][0];var b: Vector3=edges[key][1]
  var length:=a.distance_to(b)
  if length<0.65:continue
  var direction:=(b-a).normalized()
  var inward:=Vector3(-direction.z,0,direction.x)
  if inward.dot(edges[key][2]-(a+b)*0.5)<0:inward=-inward
  var steps:=int(floor(length/0.24))
  for index in range(1,steps):
   var p:=a.lerp(b,float(index)/float(steps))+inward*0.065;p.y=1.87
   var axis:=inward
   var basis:=Basis(axis.cross(Vector3.UP).normalized(),axis,Vector3.UP)
   poses.append(body.global_transform*Transform3D(basis,p))
 if poses.is_empty():load_error="돌담 기와 끝을 놓을 가장자리를 찾지 못했습니다.";return false
 var tile:=CylinderMesh.new();tile.top_radius=0.055;tile.bottom_radius=0.055;tile.height=0.095;tile.radial_segments=8;tile.rings=1
 var material:=StandardMaterial3D.new();material.albedo_color=Color(0.36,0.38,0.37);material.roughness=0.87
 tile.material=material
 var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=tile;batch.instance_count=poses.size()
 for index in range(poses.size()):batch.set_instance_transform(index,poses[index])
 var visual:=MultiMeshInstance3D.new();visual.name="CopingTileEnds";visual.multimesh=batch
 visual.visibility_range_end=105.0;visual.visibility_range_end_margin=12.0
 add_child(visual)
 tile_end_count=poses.size();detail_mesh_count=1;loaded=true
 print("PHOTO_WALL_READY tile_ends=",tile_end_count)
 return true
