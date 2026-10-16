extends Node3D
## Small, bounded action props; no collision or independent input processing.
var kind := ""
var time := 0.0
var _target: Dictionary = {}
var _player: CharacterBody3D
var _room: Node3D
var _avatar_root: Node3D
var _equipment_root: Node3D
var _meshes: Array[MeshInstance3D] = []
var _stripes: Array[MeshInstance3D] = []
var _drops: Array[MeshInstance3D] = []
var _streams: Array[MeshInstance3D] = []
var _food: Array[MeshInstance3D] = []
var _chopsticks: Array[MeshInstance3D] = []
var _hands: Array[MeshInstance3D] = []
var _shoes: Array[MeshInstance3D] = []
var _dumbbells: Array[Node3D] = []
var _bite: MeshInstance3D
var _display: Label3D
var _water_height := 1.95
var _belt_offset := 0.0
var _dumbbell_height := 0.0
var _bite_phase := 0.0
var _human_avatar := false

func build(activity: String, player: CharacterBody3D, room: Node3D, target: Dictionary) -> void:
	kind=activity;_player=player;_room=room;_target=target.duplicate(true)
	_human_avatar=is_instance_valid(player.get_node_or_null("Visual/ExplorationAvatar"))
	name="FacilityActivityVisuals"
	_avatar_root=Node3D.new();_avatar_root.name="ActiveFacilityVisuals";add_child(_avatar_root)
	_equipment_root=Node3D.new();_equipment_root.name="ActiveEquipmentVisuals";add_child(_equipment_root)
	_equipment_root.global_transform=room.global_transform
	_equipment_root.position=room.to_global(target.anchor_point)
	match kind:
		"eat":_build_meal()
		"shower":_build_shower()
		"treadmill":_build_treadmill()
		"weights":_build_weights()
	animate(0.0,0.0,{})

func _material(color: Color, transparent := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new();result.albedo_color=color;result.roughness=.60
	if transparent:result.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;result.roughness=.16
	return result

func _mesh(parent: Node3D, role: String, shape: Mesh, point: Vector3, color: Color, transparent := false) -> MeshInstance3D:
	var node := MeshInstance3D.new();node.name=role;node.mesh=shape;node.material_override=_material(color,transparent);node.position=point
	node.set_meta("role",role);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node);_meshes.append(node);return node

func _box(parent: Node3D,role: String,size: Vector3,point: Vector3,color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new();shape.size=size;return _mesh(parent,role,shape,point,color)

func _sphere(parent: Node3D,role: String,size: Vector3,point: Vector3,color: Color,transparent := false) -> MeshInstance3D:
	var shape := SphereMesh.new();shape.radius=.5;shape.height=1.0;shape.radial_segments=10;shape.rings=5
	var node := _mesh(parent,role,shape,point,color,transparent);node.scale=size;return node

func _cylinder(parent: Node3D,role: String,radius: float,height: float,point: Vector3,color: Color,transparent := false) -> MeshInstance3D:
	var shape := CylinderMesh.new();shape.top_radius=radius;shape.bottom_radius=radius;shape.height=height;shape.radial_segments=12
	return _mesh(parent,role,shape,point,color,transparent)

func _build_meal() -> void:
	# Keep the held meal visible beside the retained capsule from its normal
	# rear camera. All bite/hand motion remains relative to the same meal.
	var meal := Node3D.new();meal.name="HeldMeal";meal.position=Vector3(.35,0,0);_avatar_root.add_child(meal)
	_cylinder(meal,"meal_plate",.245,.028,Vector3(0,1.03,-.48),Color(.95,.94,.88))
	_cylinder(meal,"meal_plate_rim",.256,.014,Vector3(0,1.045,-.48),Color(.65,.75,.77))
	var food_color: Color={"food_rice":Color(.96,.91,.76),"food_soup":Color(.55,.33,.11),"food_kimchi":Color(.72,.19,.07),"food_green":Color(.27,.58,.15)}.get(String(_target.get("data",{}).get("food_material","food_rice")),Color(.96,.91,.76))
	for i in range(3):_food.append(_sphere(meal,"meal_food",Vector3(.10,.065,.10),Vector3(-.11+i*.11,1.09,-.48),food_color))
	for side in [-1.0,1.0]:_chopsticks.append(_box(meal,"chopstick",Vector3(.012,.012,.29),Vector3(.16+side*.018,1.15,-.48),Color(.38,.23,.12)))
	_bite=_sphere(meal,"food_bite",Vector3(.065,.045,.065),Vector3(.13,1.12,-.45),food_color)
	_hands.append(_sphere(meal,"activity_hand",Vector3(.105,.11,.10),Vector3(.17,1.15,-.36),Color(.80,.56,.34)))
	_hands.append(_sphere(meal,"activity_hand",Vector3(.10,.10,.10),Vector3(-.28,1.02,-.33),Color(.80,.56,.34)))

func _build_shower() -> void:
	var actual_user: Vector3=_room.to_local(_player.global_position)
	var downward := maxf(1.5,_target.anchor_point.y-actual_user.y+.03)
	var offset: Vector3=actual_user-_target.anchor_point
	var horizontal := Vector2(offset.x,offset.z).length()
	_water_height=sqrt(downward*downward+horizontal*horizontal)
	# Angle the actual stream from the fitted showerhead onto the user's
	# clear standing spot, rather than dropping water behind the capsule.
	var toward := Vector3(offset.x,-downward,offset.z).normalized()
	_equipment_root.global_basis=_room.global_basis*Basis(Quaternion(Vector3.DOWN,toward))
	for index in range(14):
		var angle := TAU*float(index)/14.0
		var radius := .075+.10*float(index%3)/2.0
		_streams.append(_cylinder(_equipment_root,"shower_stream",.006,_water_height-.10,Vector3(cos(angle)*radius,-_water_height*.5,sin(angle)*radius+.09),Color(.58,.86,1.0,.48),true))
	for index in range(24):_drops.append(_sphere(_equipment_root,"shower_drop",Vector3(.025,.075,.025),Vector3.ZERO,Color(.73,.92,1.0,.80),true))
	for index in range(5):
		var shape := TorusMesh.new();shape.inner_radius=.06;shape.outer_radius=.075;shape.rings=12;shape.ring_segments=12
		_mesh(_equipment_root,"shower_ripple",shape,Vector3(sin(index*2.1)*.20,-_water_height+.065,cos(index*1.8)*.20+.16),Color(.58,.85,.93,.60),true)

func _build_treadmill() -> void:
	var data: Dictionary=_target.get("data",{})
	if data.get("belt_center") is Vector3:_equipment_root.position=_room.to_global(data.belt_center)
	var belt: Vector3=data.get("belt_size",Vector3(.75,.025,1.65))
	for index in range(8):_stripes.append(_box(_equipment_root,"belt_stripe",Vector3(belt.x*.83,.012,.055),Vector3(0,.007,0),Color(.48,.68,.63)))
	if not _human_avatar:
		for side in [-1.0,1.0]:_shoes.append(_box(_avatar_root,"activity_shoe",Vector3(.18,.11,.31),Vector3(side*.17,0,0),Color(.10,.24,.27)))
	_display=Label3D.new();_display.name="LiveWorkoutDisplay";_display.text="운동 중";_display.font_size=24;_display.pixel_size=.004
	_display.position=Vector3(0,1.28,-.51);_display.modulate=Color(.73,1.0,.81);_display.outline_modulate=Color(.02,.08,.08);_display.outline_size=4
	_equipment_root.add_child(_display)

func _build_weights() -> void:
	for side in [-1.0,1.0]:
		var bell := Node3D.new();bell.name="AnimatedDumbbell";bell.set_meta("role","activity_dumbbell");_avatar_root.add_child(bell);_dumbbells.append(bell)
		_box(bell,"activity_dumbbell",Vector3(.29,.035,.035),Vector3.ZERO,Color(.65,.68,.69))
		for end in [-1.0,1.0]:
			var weight := _cylinder(bell,"activity_dumbbell",.10,.07,Vector3(end*.15,0,0),Color(.12,.19,.22));weight.rotation.z=PI*.5
		_hands.append(_sphere(_avatar_root,"activity_hand",Vector3(.10,.11,.10),Vector3(side*.43,.80,-.12),Color(.80,.56,.34)))

func animate(elapsed: float, progress: float, session: Dictionary) -> void:
	time=elapsed
	if not is_instance_valid(_player) or not is_instance_valid(_avatar_root):return
	_avatar_root.global_transform=Transform3D(Basis(Vector3.UP,_player.get_node("Visual").rotation.y),_player.global_position)
	match kind:
		"eat":
			_bite_phase=fmod(progress*3.0,1.0)
			var lift := sin(clampf((_bite_phase-.1)/.7,0.,1.)*PI)
			var at := Vector3(.14-lift*.41,1.13+lift*.37,-.48+lift*.40)
			for index in range(_chopsticks.size()):_chopsticks[index].position=at+Vector3((index-.5)*.036,0,0);_chopsticks[index].rotation.x=-lift*.45
			_bite.position=at+Vector3(0,-.02,-.075);_bite.visible=_bite_phase>.12 and _bite_phase<.72
			_hands[0].position=at+Vector3(.025,-.01,.10)
			var bites := int(session.get("bites",0))
			for index in range(_food.size()):_food[index].visible=index>=bites
		"shower":
			for index in range(_drops.size()):
				var angle := float(index)*2.399
				var depth := fmod(time*2.8+float(index)*.137,_water_height-.10)
				_drops[index].position=Vector3(cos(angle)*(.07+float(index%4)*.038),-.05-depth,sin(angle)*(.07+float(index%3)*.045)+.09)
			for index in range(_streams.size()):_streams[index].scale.x=.80+.22*sin(time*12.+index);_streams[index].scale.z=_streams[index].scale.x
			for node: MeshInstance3D in _meshes:
				if String(node.get_meta("role",""))=="shower_ripple":node.scale=Vector3.ONE*(.7+.65*fmod(time*1.5+float(node.get_index())*.2,1.0))
		"treadmill":
			_belt_offset=fmod(time*1.65,.20)
			for index in range(_stripes.size()):_stripes[index].position.z=-.76+fmod(float(index)*.20+time*1.65,1.56)
			for index in range(_shoes.size()):_shoes[index].position.y=maxf(0.,sin(time*10.+index*PI))*.18;_shoes[index].position.z=sin(time*10.+index*PI)*.24
			_display.text="6.0 km/h · %.0f m"%float(session.get("distance_m",0.0))
		"weights":
			var curl := (1.-cos(time*TAU/2.0))*.5
			_dumbbell_height=.76+curl*.60
			for index in range(_dumbbells.size()):
				var side := -1.0 if index==0 else 1.0
				_dumbbells[index].position=Vector3(side*.43,_dumbbell_height,-.12-curl*.14)
				_dumbbells[index].rotation.z=side*curl*.20
				_hands[index].position=_dumbbells[index].position

func snapshot() -> Dictionary:
	var visible_count := 0
	var moving_count := 0
	var bounds := AABB()
	var initialized := false
	for node: MeshInstance3D in _meshes:
		if not is_instance_valid(node):continue
		if node.visible:visible_count+=1
		if String(node.get_meta("role","")) in ["chopstick","food_bite","shower_drop","shower_stream","shower_ripple","belt_stripe","activity_dumbbell","activity_hand","activity_shoe"]:moving_count+=1
		var actual: AABB=node.global_transform*node.get_aabb()
		if not initialized:bounds=actual;initialized=true
		else:bounds=bounds.merge(actual)
	return {"kind":kind,"time":time,"mesh_count":_meshes.size(),"visible_mesh_count":visible_count,"moving_mesh_count":moving_count,"effect_bounds":bounds,"water_on":kind=="shower" and is_visible_in_tree(),"belt_offset":_belt_offset,"dumbbell_height":_dumbbell_height,"bite_phase":_bite_phase}
