extends Node3D
## Authored public-life scenes, never a claim of an event or current business access.
var loaded := false
var host: Node3D
var queue_people: Array[Node3D]=[]
var picnics: Array[Node3D]=[]
var signs: Array[Dictionary]=[]
var placements: Array[Dictionary]=[]
var skipped: Array[Dictionary]=[]
var audio: AudioStreamPlayer3D
var music_enabled := true
var elapsed := 0.0
var _materials := {}
var _boxes := {}
var _daily: Node3D

func setup(source: Node3D) -> bool:
	host=source;name="NeighborhoodLife";process_mode=Node.PROCESS_MODE_PAUSABLE
	_daily=Node3D.new();_daily.name="DaytimePicnics";add_child(_daily)
	_build_queue();_build_picnics();_build_signs();_build_music()
	loaded=not queue_people.is_empty() and not picnics.is_empty() and signs.size()>=4 and is_instance_valid(audio)
	print("NEIGHBORHOOD_READY queue=",queue_people.size()," picnics=",picnics.size()," signs=",signs.size()," music=",is_instance_valid(audio))
	return loaded

func _mat(color: Color) -> StandardMaterial3D:
	var key:=color.to_html()
	if not _materials.has(key):
		var value:=StandardMaterial3D.new();value.albedo_color=color;value.roughness=.85;_materials[key]=value
	return _materials[key]

func _box(parent: Node3D,title: String,size: Vector3,at: Vector3,color: Color) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.position=at;node.material_override=_mat(color)
	node.visibility_range_end=90;parent.add_child(node);return node

func _head(parent: Node3D,at: Vector3,color: Color) -> void:
	var mesh:=SphereMesh.new();mesh.radius=.115;mesh.height=.27;mesh.radial_segments=10;mesh.rings=5
	var node:=MeshInstance3D.new();node.name="Head";node.mesh=mesh;node.position=at;node.material_override=_mat(color);node.visibility_range_end=90;parent.add_child(node)
	_box(parent,"Hair",Vector3(.22,.08,.22),at+Vector3(0,.10,0),Color(.10,.08,.06))

func _person(parent: Node3D,index: int,seated: bool) -> Node3D:
	var person:=Node3D.new();person.name="Person"+str(index);parent.add_child(person)
	var skin: Color=[Color(.91,.72,.56),Color(.63,.40,.26),Color(.36,.22,.16),Color(.77,.53,.36)][index%4]
	var coat: Color=[Color(.20,.44,.50),Color(.64,.31,.24),Color(.78,.69,.45),Color(.40,.29,.54)][index%4]
	var hip:=.32 if seated else .87
	_box(person,"Coat",Vector3(.36,.50,.23),Vector3(0,hip+.23,0),coat)
	_head(person,Vector3(0,hip+.66,0),skin)
	for side in [-1.,1.]:
		if seated:
			_box(person,"BentThigh",Vector3(.14,.14,.40),Vector3(side*.11,.30,-.18),Color(.16,.22,.28))
			_box(person,"FoldedShin",Vector3(.14,.17,.40),Vector3(side*.11,.17,-.40),Color(.16,.22,.28))
		else:
			_box(person,"TrouserLeg",Vector3(.14,.72,.18),Vector3(side*.11,.43,0),Color(.16,.22,.28))
			_box(person,"Shoe",Vector3(.16,.10,.27),Vector3(side*.11,.05,-.04),Color(.09,.10,.11))
		_box(person,"Arm",Vector3(.10,.46,.12),Vector3(side*.24,hip+.19,-.02),coat)
		_box(person,"Hand",Vector3(.10,.12,.10),Vector3(side*.24,hip-.09,-.02),skin)
	return person

func _ground(at: Vector3,size: Vector3) -> Dictionary:
	# Same source/private/floor, route/vehicle and doorway guards as street life.
	var module: Node3D=host.street_life
	var protected: Dictionary=module._protected(at,Vector2(size.x,size.z).length()*.5)
	if not protected.clear:return {}
	var ground: Dictionary=module._ground(at)
	if ground.is_empty():return {}
	var frame:=Transform3D(Basis.IDENTITY,ground.point)
	if not module._volume_clear(frame,size):return {}
	var bounds:=AABB(ground.point-Vector3(size.x*.5,0,size.z*.5),size)
	for old: AABB in _boxes.values():
		if old.grow(.05).intersects(bounds):return {}
	for old: Dictionary in module._owned_bounds:
		if old.bounds.grow(.1).intersects(bounds):return {}
	for corner in [Vector3(-size.x*.45,0,-size.z*.45),Vector3(size.x*.45,0,-size.z*.45),Vector3(-size.x*.45,0,size.z*.45),Vector3(size.x*.45,0,size.z*.45)]:
		var support: Dictionary=module._ground(ground.point+corner)
		if support.is_empty() or absf(support.point.y-ground.point.y)>.15:return {}
	return {"point":ground.point,"support":ground.source,"bounds":bounds,"protection":protected}

func _place(id: String,kind: String,at: Vector3,size: Vector3,parent: Node3D=null) -> Node3D:
	var valid:=_ground(at,size)
	if valid.is_empty():skipped.append({"id":id,"point":at});return null
	var node:=Node3D.new();node.name=id
	(parent if parent!=null else self).add_child(node);node.global_position=valid.point
	node.set_meta("authored_game_placement",true);node.set_meta("source_support",valid.support)
	_boxes[id]=valid.bounds;placements.append({"id":id,"kind":kind,"point":valid.point,"size":size,"support":valid.support,"protection":valid.protection})
	# Solid occupied envelopes keep the player from walking through static people.
	if kind in ["queue","picnic"]:
		var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;shape.position.y=size.y*.5;body.add_child(shape);node.add_child(body)
	return node

func _build_queue() -> void:
	for store: Dictionary in host.street_businesses.stores:
		if store.record.style!="restaurant":continue
		var facade: Node3D=store.node
		# Leave the central door/approach open; wait along the facade, facing it.
		for offset in [-2.9,-1.95,1.95,2.9]:
			var candidate: Vector3=facade.to_global(Vector3(offset,0,1.6))
			var node:=_place("RestaurantQueue"+str(queue_people.size()),"queue",candidate,Vector3(.58,1.75,.58))
			if node==null:continue
			node.rotation.y=facade.global_rotation.y+PI
			_person(node,queue_people.size(),false);queue_people.append(node)
		if not queue_people.is_empty():
			_label(facade,"대기 줄 / Queue →\n출입구를 비워 주세요 · Keep doorway clear",Vector3(1.8,1.8,.5),1.7,Color(.12,.14,.10),24)

func _build_picnics() -> void:
	# Small authored daytime groups on supported open plaza grass, off all routes.
	for at in [Vector3(150,0,-55),Vector3(164,0,-44),Vector3(178,0,-65),Vector3(143,0,-72),Vector3(165,0,-80),Vector3(183,0,-43)]:
		var node:=_place("Picnic"+str(picnics.size()),"picnic",at,Vector3(2.3,1.2,2.0),_daily)
		if node==null:continue
		_box(node,"PicnicMat",Vector3(2.2,.035,1.9),Vector3(0,.025,0),Color(.35,.57,.52))
		for stripe in range(8):_box(node,"MatStripe",Vector3(.045,.008,1.88),Vector3(-.98+stripe*.28,.048,0),Color(.87,.85,.68))
		for index in range(2):
			var person:=_person(node,picnics.size()+index,true);person.position=Vector3(-.60+1.2*index,.05,.32);person.rotation.y=(-.3 if index==0 else .3)
		_box(node,"LunchBasket",Vector3(.33,.30,.27),Vector3(0,.20,-.50),Color(.62,.40,.22))
		_box(node,"Cup",Vector3(.09,.14,.09),Vector3(.3,.12,-.44),Color(.89,.85,.71))
		picnics.append(node)
		if picnics.size()>=3:break

func _label(parent: Node3D,text: String,at: Vector3,width: float,color: Color,font_size:=30) -> Label3D:
	var label:=Label3D.new();label.text=text;label.position=at;label.font_size=font_size;label.pixel_size=.003;label.modulate=color;label.outline_size=0
	label.width=int(width/.003);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.double_sided=true;label.no_depth_test=false;label.visibility_range_end=90;parent.add_child(label);return label

func _build_signs() -> void:
	var routes: Array=host.city.public_data.routes
	var targets: Array[Dictionary]=[]
	var world: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/world_geometry/world.json"))
	for item: Dictionary in world.landmarks:
		if item.name in ["대한문","서울도서관","서울광장"]:
			targets.append({"title":{"대한문":"대한문 · Daehanmun","서울도서관":"서울도서관 · Seoul Library","서울광장":"서울광장 · Seoul Plaza"}[item.name],"point":Vector3(item.position[0],0,item.position[2])})
	for route: Dictionary in routes:
		if String(route.id) not in ["stonewall","city_plaza","entrance"]:continue
		for index in range(1,route.xz.size(),maxi(1,int(route.xz.size()/3))):
			if signs.size()>=10:break
			var p: Array=route.xz[index];var q: Array=route.xz[index-1]
			var forward:=Vector3(float(p[0])-float(q[0]),0,float(p[1])-float(q[1])).normalized()
			var lateral:=Vector3(forward.z,0,-forward.x)
			var node: Node3D
			for side in [1.,-1.]:
				for distance in [3.0,4.0,5.0]:
					node=_place("Wayfinding"+str(signs.size()),"sign",Vector3(p[0],0,p[1])+lateral*side*distance,Vector3(.32,3.3,.32))
					if node!=null:break
				if node!=null:break
			if node==null:continue
			_box(node,"SignPole",Vector3(.10,3.1,.10),Vector3(0,1.55,0),Color(.16,.23,.22))
			var rows:=[]
			for i in range(targets.size()):
				var delta: Vector3=targets[i].point-node.global_position;delta.y=0
				var yaw:=atan2(-delta.z,delta.x)
				var board:=Node3D.new();board.name="DirectionBoard";node.add_child(board);board.rotation.y=yaw
				var y:=2.9-i*.42
				_box(board,"Panel",Vector3(1.9,.37,.08),Vector3(0,y,0),Color(.05,.25,.22))
				_label(board,"→ "+targets[i].title+"\n직선 %dm · straight line"%int(delta.length()),Vector3(0,y,.06),1.85,Color(.95,.95,.84),36)
				rows.append({"target":targets[i].title,"distance_m":delta.length(),"direction":delta.normalized()})
			signs.append({"node":node,"rows":rows,"route":route.id})

func _build_music() -> void:
	for actor: Dictionary in host.street_life.performers:
		if actor.kind!="busker":continue
		audio=AudioStreamPlayer3D.new();audio.name="OriginalStreetGuitar"
		var stream:=load("res://assets/audio/stonewall_guitar.wav") as AudioStreamWAV
		if stream==null:return
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_begin=0;stream.loop_end=stream.data.size()/2
		audio.stream=stream;audio.volume_db=-9.;audio.unit_size=4.;audio.max_distance=32.;audio.attenuation_model=AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		audio.max_db=-5.;audio.position=Vector3(0,1.,0);actor.actor.add_child(audio);audio.play()
		break

func set_music_enabled(enabled: bool) -> void:
	music_enabled=enabled
	if is_instance_valid(audio):audio.volume_db=-9. if enabled else -80.

func set_time_profile(id: String) -> bool:
	if id not in ["day","evening","night"]:return false
	_daily.visible=id=="day"
	# Hidden people cannot leave invisible colliders at night.
	for group in picnics:
		for child in group.get_children():
			if child is StaticBody3D:child.collision_layer=1 if id=="day" else 0
	return true

func snapshot() -> Dictionary:
	return {"loaded":loaded,"queue_count":queue_people.size(),"picnic_groups":picnics.size(),"picnics_visible":_daily.visible,"signs":signs.size(),"placements":placements,"skipped":skipped,"music_enabled":music_enabled,"audio_playing":audio.playing if is_instance_valid(audio) else false,"authored":true,"distance_labels":"horizontal straight-line, not routed distance"}
