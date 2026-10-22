extends RefCounted
## Original metre-space human surfaces, shared across exploration adults.
## A row is [height, half_width, front_depth, back_depth, centre_z].
## Smooth ring normals and clockwise triangles follow Godot's front-face rule.
static var _cache: Dictionary={}
static var _fabric_roughness: Texture2D
static var _round_detail: SphereMesh

static func round_detail() -> SphereMesh:
	if _round_detail!=null:return _round_detail
	_round_detail=SphereMesh.new();_round_detail.radius=.5;_round_detail.height=1.;_round_detail.radial_segments=20;_round_detail.rings=12
	return _round_detail

static func loft(key: String,rows: Array,segments:=24,fold:=0.) -> ArrayMesh:
	if _cache.has(key):return _cache[key]
	var points:=PackedVector3Array();var normals:=PackedVector3Array();var uvs:=PackedVector2Array();var indices:=PackedInt32Array()
	var height: float=maxf(.00001,float(rows.back()[0])-float(rows.front()[0]))
	for ring: int in range(rows.size()):
		var row: Array=rows[ring]
		for column: int in range(segments):
			var angle:=TAU*float(column)/float(segments)
			var ripple:=1.+fold*sin(angle*7.+float(ring)*1.73)*sin(PI*float(ring)/float(rows.size()-1))
			var depth: float=float(row[2]) if cos(angle)<0. else float(row[3])
			points.append(Vector3(sin(angle)*float(row[1])*ripple,float(row[0]),float(row[4])+cos(angle)*depth*ripple))
			uvs.append(Vector2(float(column)/float(segments),(float(row[0])-float(rows.front()[0]))/height))
	for ring: int in range(rows.size()):
		for column: int in range(segments):
			var tangent: Vector3=points[ring*segments+(column+1)%segments]-points[ring*segments+(column+segments-1)%segments]
			var along: Vector3=points[mini(ring+1,rows.size()-1)*segments+column]-points[maxi(0,ring-1)*segments+column]
			normals.append(tangent.cross(along).normalized())
	for ring: int in range(rows.size()-1):
		for column: int in range(segments):
			var a:=ring*segments+column;var b:=ring*segments+(column+1)%segments;var c:=a+segments;var d:=b+segments
			indices.append_array(PackedInt32Array([a,c,b,b,c,d]))
	# Separate cap vertices avoid turning the side normals into hard bevels.
	for cap: int in [0,rows.size()-1]:
		var first:=points.size();var normal:=Vector3.DOWN if cap==0 else Vector3.UP
		points.append(Vector3(0,float(rows[cap][0]),float(rows[cap][4])));normals.append(normal);uvs.append(Vector2(.5,.5))
		for column: int in range(segments):
			points.append(points[cap*segments+column]);normals.append(normal);uvs.append(Vector2(.5+sin(TAU*column/segments)*.5,.5+cos(TAU*column/segments)*.5))
		for column: int in range(segments):
			var a:=first+1+column;var b:=first+1+(column+1)%segments
			indices.append_array(PackedInt32Array([first,a,b] if cap==0 else [first,b,a]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.resource_name="OriginalHuman_"+key;_cache[key]=mesh;return mesh

static func fabric_roughness() -> Texture2D:
	if _fabric_roughness!=null:return _fabric_roughness
	# A subtle original woven roughness swatch, without baked lighting or noise
	# displacement. Colour stays editable for purchased clothes and uniforms.
	var image:=Image.create(64,64,false,Image.FORMAT_RGB8)
	for y: int in range(64):
		for x: int in range(64):
			var value:=.88+.045*sin(float(x)*PI*.5)*sin(float(y)*PI*.5)+.025*sin(float(x*13+y*7))
			image.set_pixel(x,y,Color(value,value,value))
	_fabric_roughness=ImageTexture.create_from_image(image);return _fabric_roughness

static func front_patch(key: String,body_rows: Array,cut_rows: Array,bias:=.0015) -> ArrayMesh:
	# A garment facing follows the fitted torso's actual front ellipse. A
	# separate closed skinny loft leaves a floating bib under directional light.
	if _cache.has(key):return _cache[key]
	var points:=PackedVector3Array();var normals:=PackedVector3Array();var uvs:=PackedVector2Array();var indices:=PackedInt32Array();var columns:=9
	for ring: int in range(cut_rows.size()):
		var cut: Array=cut_rows[ring];var y: float=cut[0];var profile: Array=body_rows.front()
		for index: int in range(1,body_rows.size()):
			if y>float(body_rows[index][0]):continue
			var lower: Array=body_rows[index-1];var upper: Array=body_rows[index];var fraction:=clampf((y-float(lower[0]))/(float(upper[0])-float(lower[0])),0.,1.)
			profile=[]
			for value: int in range(5):profile.append(lerpf(float(lower[value]),float(upper[value]),fraction))
			break
		for column: int in range(columns):
			var u:=float(column)/float(columns-1);var x:=float(cut[2])+lerpf(-float(cut[1]),float(cut[1]),u)
			var z:=float(profile[4])-float(profile[2])*sqrt(maxf(.001,1.-x*x/(float(profile[1])*float(profile[1]))))-bias
			points.append(Vector3(x,y,z));uvs.append(Vector2(u,float(ring)/float(cut_rows.size()-1)))
	for ring: int in range(cut_rows.size()):
		for column: int in range(columns):
			var across: Vector3=points[ring*columns+mini(column+1,columns-1)]-points[ring*columns+maxi(0,column-1)]
			var along: Vector3=points[mini(ring+1,cut_rows.size()-1)*columns+column]-points[maxi(0,ring-1)*columns+column]
			normals.append(along.cross(across).normalized())
	for ring: int in range(cut_rows.size()-1):
		for column: int in range(columns-1):
			var a:=ring*columns+column;var b:=a+1;var c:=a+columns;var d:=c+1;indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.resource_name="OriginalHuman_"+key;_cache[key]=mesh;return mesh
