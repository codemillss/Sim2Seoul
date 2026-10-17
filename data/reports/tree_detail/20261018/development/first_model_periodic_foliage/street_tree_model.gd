extends RefCounted
## Original procedural art in metres, not a surveyed tree/species reconstruction.
## One shared model per layer; individual source points vary in yaw and stature.
const CANONICAL_HEIGHT_M: float=10.0

class Surface extends RefCounted:
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var uvs:=PackedVector2Array()
	var colors:=PackedColorArray()
	func triangle(a: Vector3,b: Vector3,c: Vector3,na: Vector3,nb: Vector3,nc: Vector3,ta: Vector2,tb: Vector2,tc: Vector2,color: Color) -> void:
		vertices.append_array(PackedVector3Array([a,c,b]));normals.append_array(PackedVector3Array([na,nc,nb]));uvs.append_array(PackedVector2Array([ta,tc,tb]));colors.append_array(PackedColorArray([color,color,color]))
	func mesh() -> ArrayMesh:
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_COLOR]=colors
		var output:=ArrayMesh.new();output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return output

var _rng:=RandomNumberGenerator.new()
var _bark:=Surface.new()
var _foliage:=Surface.new()
var _detail:=Surface.new()
var _clusters: Array[Dictionary]=[]
var _branch_segments: int=0
var _leaf_blades: int=0

func _direction() -> Vector3:
	var y: float=_rng.randf_range(-1.,1.);var angle: float=_rng.randf_range(0.,TAU);var radius: float=sqrt(1.-y*y)
	return Vector3(cos(angle)*radius,y,sin(angle)*radius)

func _tube(a: Vector3,b: Vector3,r0: float,r1: float,segments: int=9) -> void:
	var axis: Vector3=(b-a).normalized();var side: Vector3=axis.cross(Vector3.FORWARD if absf(axis.y)>.9 else Vector3.UP).normalized();var other: Vector3=axis.cross(side).normalized()
	var color:=Color(.30,.235,.16).lightened(_rng.randf_range(0.,.10))
	for index: int in range(segments):
		var u: float=float(index)/segments;var v: float=float(index+1)/segments
		var n0: Vector3=side*cos(u*TAU)+other*sin(u*TAU);var n1: Vector3=side*cos(v*TAU)+other*sin(v*TAU)
		var p0: Vector3=a+n0*r0;var p1: Vector3=a+n1*r0;var p2: Vector3=b+n1*r1;var p3: Vector3=b+n0*r1
		_bark.triangle(p0,p1,p2,n0,n1,n1,Vector2(u,a.y),Vector2(v,a.y),Vector2(v,b.y),color)
		_bark.triangle(p0,p2,p3,n0,n1,n0,Vector2(u,a.y),Vector2(v,b.y),Vector2(u,b.y),color)
	_branch_segments+=1

func _cluster(center: Vector3,size: Vector3,phase: float) -> void:
	_clusters.append({"center":center,"size":size})
	var rings: int=5;var sectors: int=9
	var tint:=Color(.19,.33,.075).lightened(_rng.randf_range(0.,.105))
	for ring: int in range(rings):
		for sector: int in range(sectors):
			var ps: Array[Vector3]=[];var ns: Array[Vector3]=[];var ts: Array[Vector2]=[]
			for corner: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
				var u: float=float(sector+corner.x)/sectors;var v: float=float(ring+corner.y)/rings
				var normal:=Vector3(sin(v*PI)*cos(u*TAU),cos(v*PI),sin(v*PI)*sin(u*TAU))
				var ripple: float=1.+.13*sin(u*TAU*3.+phase)*sin(v*PI)*sin(v*PI)+.065*sin(v*PI*4.+u*TAU*2.)
				ps.append(center+normal*size*ripple);ns.append((normal/size).normalized());ts.append(Vector2(u,v))
			_foliage.triangle(ps[0],ps[1],ps[2],ns[0],ns[1],ns[2],ts[0],ts[1],ts[2],tint)
			_foliage.triangle(ps[0],ps[2],ps[3],ns[0],ns[2],ns[3],ts[0],ts[2],ts[3],tint)

func _leaf(at: Vector3,out: Vector3,length: float,width: float,color: Color) -> void:
	# Four folded triangles form a blade; no rectangular transparent billboard.
	var normal: Vector3=(out*.6+Vector3.UP*.4).normalized()
	var along: Vector3=normal.cross(Vector3.FORWARD if absf(normal.y)>.9 else Vector3.UP).normalized().rotated(normal,_rng.randf_range(0.,TAU))
	var across: Vector3=normal.cross(along).normalized()
	var tip: Vector3=at+along*length*.58;var base: Vector3=at-along*length*.42
	var left: Vector3=at-across*width*.5;var right: Vector3=at+across*width*.5;var ridge: Vector3=at+normal*width*.13
	_detail.triangle(base,left,ridge,normal,normal,normal,Vector2(.5,0),Vector2(0,.42),Vector2(.5,.42),color)
	_detail.triangle(left,tip,ridge,normal,normal,normal,Vector2(0,.42),Vector2(.5,1),Vector2(.5,.42),color)
	_detail.triangle(tip,right,ridge,normal,normal,normal,Vector2(.5,1),Vector2(1,.42),Vector2(.5,.42),color)
	_detail.triangle(right,base,ridge,normal,normal,normal,Vector2(1,.42),Vector2(.5,0),Vector2(.5,.42),color)
	_leaf_blades+=1

func build() -> Dictionary:
	_rng.seed=2201810
	var trunk: Array[Vector3]=[Vector3.ZERO,Vector3(.005,.4,0),Vector3(-.015,1.6,.012),Vector3(.018,3.1,-.015),Vector3(.08,4.65,.04),Vector3(.12,6.2,.02),Vector3(.18,7.8,.08),Vector3(.20,9.35,.1)]
	var radii: Array[float]=[.17,.165,.15,.137,.112,.085,.055,.016]
	for index: int in range(trunk.size()-1):_tube(trunk[index],trunk[index+1],radii[index],radii[index+1],12)
	for root: int in range(6):
		var radial:=Vector3(cos(root*TAU/6.),0.,sin(root*TAU/6.))
		_tube(Vector3.UP*.15+radial*.09,Vector3.UP*.06+radial*.32,.045,.012,7)
	for limb: int in range(8):
		var angle: float=TAU*float(limb)/8.+_rng.randf_range(-.12,.12)
		var radial:=Vector3(cos(angle),0.,sin(angle));var cross: Vector3=Vector3.UP.cross(radial)
		var start:=Vector3(.035,3.35+float(limb%3)*.26,.005)
		var middle: Vector3=radial*_rng.randf_range(.78,1.15)+Vector3.UP*(5.1+_rng.randf_range(-.1,.3))
		var end: Vector3=radial*_rng.randf_range(2.05,2.65)+Vector3.UP*(6.95+_rng.randf_range(-.2,1.0))
		_tube(start,middle,.108,.062);_tube(middle,end,.062,.022)
		for fork: int in range(2):
			var tip: Vector3=end+cross*(-.47 if fork==0 else .47)+radial*.2+Vector3.UP*_rng.randf_range(.8,1.2)
			_tube(middle.lerp(end,.55),tip,.032,.008,7)
			_cluster(tip,Vector3(.75,.82,.78),angle+fork)
		_cluster(middle.lerp(end,.74)+Vector3.UP*.22,Vector3(.98,1.12,.94),angle)
		_cluster(middle+radial*.28+Vector3.UP*.55,Vector3(.83,.93,.78),angle+2.)
	for top: int in range(5):
		var center:=Vector3(cos(top*TAU/5.)*.55,8.9+float(top%2)*.25,sin(top*TAU/5.)*.55)
		_cluster(center,Vector3(.83,.86,.83),float(top))
	for cluster: Dictionary in _clusters:
		for sprig: int in range(27):
			var out: Vector3=_direction();var at: Vector3=cluster.center+out*(cluster.size as Vector3)*_rng.randf_range(.87,1.13)
			_leaf(at,out,_rng.randf_range(.23,.39),_rng.randf_range(.12,.23),Color(.22,.39,.09).lightened(_rng.randf_range(0.,.17)))
	var meshes: Dictionary={"bark":_bark.mesh(),"leaf":_foliage.mesh(),"detail":_detail.mesh()}
	return {"meshes":meshes,"branch_segments":_branch_segments,"foliage_clusters":_clusters.size(),"individual_leaf_blades":_leaf_blades,"canonical_height_m":CANONICAL_HEIGHT_M,"triangles":{"bark":_bark.vertices.size()/3,"leaf":_foliage.vertices.size()/3,"detail":_detail.vertices.size()/3},"scope":"Original procedural broadleaf streetscape art, not a botanical model or surveyed source tree height."}
