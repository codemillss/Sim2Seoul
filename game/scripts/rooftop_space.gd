extends Node3D
## A fictional roof amenity at this building's real source XZ position.
## Source bodies remain intact. The deck clears observed source/visible tops.
const DECK_CLEARANCE_M := .28
const SOURCE_INSET_M := .80
const MAX_DECK_SIZE := Vector2(32.0,36.0)
var spec: Dictionary = {}
var world_bounds := AABB()
var frame := Transform3D.IDENTITY
var walkable_rect := Rect2()
var bodies: Array[StaticBody3D] = []
var profile_id := "garden"
var profile_title := "옥상 정원"
var width := 0.0
var depth := 0.0
var deck_height_y := 0.0
var source_height_y := 0.0
var observed_top_y := 0.0
var observations: Array[Dictionary] = []
var features: Array[String] = []
var water_effects: Node3D
var _pool_rect := Rect2()
var _pool_point := Vector3.ZERO
var _pool_size := Vector2.ZERO
var _pool_access_x := 0.0
const POOL_MIN_LONG_M := 12.0
const POOL_MIN_SHORT_M := 6.0
const POOL_MAX_LONG_M := 24.0
const POOL_MAX_SHORT_M := 10.0
const REPRESENTATIVE_POOL_ID := "osm:way:233593619:building"
const POOL_DECK_RAISE_M := 1.55
const POOL_FLOOR_Y := -1.40
const POOL_SURFACE_Y := -.18
const POOL_RIM_Y := 0.0
var _pool_deck_opening := Rect2()
var _materials: Dictionary = {}
var _loaded := false

func setup(host: Node3D, building: Dictionary) -> bool:
	if _loaded or not is_instance_valid(host) or not is_inside_tree():return false
	var centre: Variant = building.get("rectangle_center")
	var along: Variant = building.get("rectangle_along")
	var outward: Variant = building.get("rectangle_outward")
	if not centre is Vector2 or not along is Vector3 or not outward is Vector3:return false
	if not centre.is_finite() or not along.is_finite() or not outward.is_finite():return false
	width = minf(float(building.get("width",0.0))-SOURCE_INSET_M*2.0,MAX_DECK_SIZE.x)
	depth = minf(float(building.get("depth",0.0))-SOURCE_INSET_M*2.0,MAX_DECK_SIZE.y)
	source_height_y = float(building.get("source_roof_world_y",building.get("source_height",0.0)))
	if not is_finite(width) or not is_finite(depth) or not is_finite(source_height_y):return false
	if width<10.0 or depth<14.0 or float(building.get("source_height",0.0))<=0.0:return false
	var axis := Vector3(along.x,0.0,along.z).normalized()
	if axis.length_squared()<.99 or absf(axis.dot(outward.normalized()))>.001:return false
	# The source rectangle may use a reflected outward axis. A symmetric deck
	# uses the same footprint with a proper basis, preserving front-face normals.
	var axes := Basis(axis,Vector3.UP,axis.cross(Vector3.UP))
	if not axes.is_finite() or absf(axes.determinant()-1.0)>.001:return false
	spec = building.duplicate(true)
	walkable_rect = Rect2(-width*.5,-depth*.5,width,depth)
	var plan := Transform3D(axes,Vector3(centre.x,0.0,centre.y))*AABB(Vector3(-width*.5,0.0,-depth*.5),Vector3(width,1.0,depth))
	observed_top_y = source_height_y
	var city: Node3D = host.get("city")
	if not is_instance_valid(city):return false
	var sources: Variant = city.get("source_nodes")
	if not sources is Dictionary:return false
	var source := sources.get(String(spec.get("id",""))) as MeshInstance3D
	if source==null or source.mesh==null:return false
	_observe(source.global_transform*source.get_aabb(),String(source.get_path()),"retained_source_mesh",plan)
	# Read the exact same-feature L03 vertices, independent of renderer readback.
	# Photo details are source-height-bounded. Never use a city-wide MultiMesh
	# AABB or our own generated roof/cabin as a new source of roof height.
	var landmark_root := host.get("city_visuals") as Node3D
	if landmark_root!=null:
		var bundle: Variant = landmark_root.get("bundle")
		var components: Variant = landmark_root.get("components")
		if bundle is Dictionary and components is Dictionary:
			for item: Dictionary in bundle.get("landmarks",[]):
				if item.get("feature_id")!=spec.get("id"):continue
				for component: Dictionary in item.get("components",[]):
					var visual := components.get(component.get("id")) as MeshInstance3D
					if visual==null or not visual.is_visible_in_tree():continue
					var vertices: Array = component.get("vertices",[])
					if vertices.size()<3:continue
					var first := visual.global_transform*Vector3(float(vertices[0]),float(vertices[1]),float(vertices[2]))
					var box := AABB(first,Vector3.ZERO)
					for index in range(3,vertices.size(),3):
						box = box.expand(visual.global_transform*Vector3(float(vertices[index]),float(vertices[index+1]),float(vertices[index+2])))
					_observe(box,String(spec.id)+"/"+String(component.id),"same_feature_visible_landmark_json",plan)
	_select_profile()
	deck_height_y = maxf(source_height_y,observed_top_y)+DECK_CLEARANCE_M+(POOL_DECK_RAISE_M if profile_id=="outdoor_pool" else 0.0)
	frame = Transform3D(axes,Vector3(centre.x,deck_height_y,centre.y))
	global_transform = frame
	# Finite validation for supported landings and water registration. The
	# player keeps this footprint/lower plane but can jump into the open sky.
	var lower_y: float=-1.65 if profile_id=="outdoor_pool" else -.35
	world_bounds = frame*AABB(Vector3(-width*.5,lower_y,-depth*.5),Vector3(width,9.0-lower_y,depth))
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_materials_setup()
	if profile_id=="outdoor_pool":_prepare_pool_layout()
	_build_deck()
	_build_lift_headhouse()
	match profile_id:
		"outdoor_pool":
			_build_pool()
			water_effects = preload("res://scripts/water_effect.gd").new()
			water_effects.name = "WaterEffects";add_child(water_effects)
			var actor := host.get("player") as CharacterBody3D
			if actor!=null and actor.has_signal("water_splashed"):actor.water_splashed.connect(_water_splash)
		"penthouse":_build_penthouse()
		_:_build_garden()
	_loaded = true
	return true

func _xz_bounds(box: AABB) -> Rect2:
	return Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z))

func _observe(box: AABB, path: String, kind: String, plan: AABB) -> void:
	if not box.position.is_finite() or not box.size.is_finite() or not _xz_bounds(box).intersects(_xz_bounds(plan),true):return
	observed_top_y = maxf(observed_top_y,box.end.y)
	observations.append({"path":path,"kind":kind,"top_y":box.end.y,"bounds_position":_v(box.position),"bounds_size":_v(box.size)})

func _select_profile() -> void:
	var title := String(spec.get("title",""))
	var kind := String(spec.get("kind","office"))
	var hotel := title.contains("호텔") or title.to_lower().contains("hotel")
	var residence := title.contains("아파트") or title.contains("주거") or title.contains("레지던스") or title.contains("디팰리스")
	var highrise := kind=="office" and int(spec.get("floor_count",1))>=15 and posmod(String(spec.get("id","")).hash(),3)==0
	if hotel and not _pool_dimensions().is_zero_approx():
		profile_id = "outdoor_pool";profile_title = "야외 수영장 · 루프톱 테라스"
	elif hotel:
		profile_id = "garden";profile_title = "옥상 정원 · 작은 지붕"
	elif residence or highrise:
		profile_id = "penthouse";profile_title = "펜트하우스 · 테라스"
	else:
		profile_id = "garden";profile_title = "옥상 정원"

func _material(key: String, color: Color, roughness := .8) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color;material.roughness = roughness
	if color.a<1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material

func _materials_setup() -> void:
	_material("stone",Color(.63,.64,.59))
	_material("wood",Color(.43,.31,.20))
	_material("steel",Color(.18,.26,.26),.36)
	_material("glass",Color(.41,.64,.65,.34),.12)
	_material("leaf",Color(.25,.43,.25))
	_material("grass",Color(.38,.51,.30))
	_material("soil",Color(.22,.18,.13))
	_material("terracotta",Color(.49,.31,.23))
	_material("cream",Color(.88,.85,.74))
	_material("fabric",Color(.39,.49,.46))
	_material("pool",Color(.17,.56,.64,.78),.09)
	_material("tile",Color(.71,.81,.78))
	_material("ink",Color(.09,.19,.20))
	_material("aqua",Color(.13,.63,.67))
	_material("towel",Color(.96,.97,.94))
	for key in ["stone","wood"]:
		var surface := ShaderMaterial.new()
		surface.shader = preload("res://scripts/interior_surface.gdshader")
		surface.set_shader_parameter("base_color",Color(.63,.64,.59) if key=="stone" else Color(.43,.31,.20))
		surface.set_shader_parameter("surface_kind",0 if key=="stone" else 1)
		_materials[key] = surface

func _box(title: String, size: Vector3, point: Vector3, material: String, solid := false, axes := Basis.IDENTITY) -> MeshInstance3D:
	var visual := MeshInstance3D.new();visual.name = title
	var mesh := BoxMesh.new();mesh.size = size
	visual.mesh = mesh;visual.material_override = _materials[material]
	visual.position = point;visual.basis = axes;add_child(visual)
	if solid:
		var body := StaticBody3D.new();body.name = title+"Body"
		body.position = point;body.basis = axes
		body.collision_layer = 1;body.collision_mask = 0
		body.set_meta("geometry_id","EXP08_rooftop_"+title)
		var collision := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size = size
		collision.shape = shape;body.add_child(collision);add_child(body);bodies.append(body)
	return visual

func _cylinder(title: String, point: Vector3, radius: float, height: float, material: String) -> void:
	var visual := MeshInstance3D.new();visual.name = title
	var mesh := CylinderMesh.new();mesh.top_radius = radius;mesh.bottom_radius = radius*.92;mesh.height = height;mesh.radial_segments = 12
	visual.mesh = mesh;visual.material_override = _materials[material];visual.position = point;add_child(visual)

func _sign(title: String, text: String, point: Vector3, font_size := 28) -> Label3D:
	var label := Label3D.new();label.name = title;label.text = text;label.position = point
	label.font_size = font_size;label.pixel_size = .009;label.outline_size = 3
	label.modulate = Color(.10,.22,.21);label.outline_modulate = Color(.95,.95,.86);add_child(label)
	return label

func _build_deck() -> void:
	if profile_id=="outdoor_pool":
		# Four separate solid panels leave a real open basin. The original
		# source roof stays below the raised authored deck and pool floor.
		var hole: Rect2=_pool_deck_opening
		_pool_deck_panel("DeckFloorLeft",Rect2(walkable_rect.position,Vector2(hole.position.x-walkable_rect.position.x,depth)))
		_pool_deck_panel("DeckFloorRight",Rect2(Vector2(hole.end.x,walkable_rect.position.y),Vector2(walkable_rect.end.x-hole.end.x,depth)))
		_pool_deck_panel("DeckFloorRear",Rect2(Vector2(hole.position.x,walkable_rect.position.y),Vector2(hole.size.x,hole.position.y-walkable_rect.position.y)))
		_pool_deck_panel("DeckFloorFront",Rect2(Vector2(hole.position.x,hole.end.y),Vector2(hole.size.x,walkable_rect.end.y-hole.end.y)))
		var front_depth: float=walkable_rect.end.y-hole.end.y
		_box("DeckArrivalStripe",Vector3(1.8,.008,maxf(1.0,front_depth-1.1)),Vector3(0,.006,hole.end.y+front_depth*.5),"wood")
	else:
		_box("DeckFloor",Vector3(width,.24,depth),Vector3(0,-.12,0),"stone",true)
		_box("DeckArrivalStripe",Vector3(1.8,.008,depth-1.1),Vector3(0,.006,0),"wood")
	for side in [-1.0,1.0]:
		_box("GuardRailX"+str(side),Vector3(.14,1.25,depth),Vector3(side*(width*.5-.10),.625,0),"glass",true)
		_box("GuardRailZ"+str(side),Vector3(width,1.25,.14),Vector3(0,.625,side*(depth*.5-.10)),"glass",true)
		_box("RailCapX"+str(side),Vector3(.18,.065,depth),Vector3(side*(width*.5-.10),1.25,0),"steel")
		_box("RailCapZ"+str(side),Vector3(width,.065,.18),Vector3(0,1.25,side*(depth*.5-.10)),"steel")
	for x in [-width*.5+.11,width*.5-.11]:
		for z in [-depth*.5+.11,depth*.5-.11]:_box("RailCorner",Vector3(.13,1.3,.13),Vector3(x,.65,z),"steel")
	features.append("four_sided_physical_rails_and_rotated_player_footprint_guard")

func _pool_deck_panel(title: String, rectangle: Rect2) -> void:
	if not rectangle.has_area():return
	var centre: Vector2=rectangle.get_center()
	_box(title,Vector3(rectangle.size.x,.24,rectangle.size.y),Vector3(centre.x,-.12,centre.y),"stone",true)

func _build_lift_headhouse() -> void:
	var rear := depth*.5-.55
	var front := rear-2.1
	_box("LiftRear",Vector3(3.4,2.8,.16),Vector3(0,1.4,rear),"cream",true)
	for side in [-1.0,1.0]:
		_box("LiftSide",Vector3(.14,2.8,2.1),Vector3(side*1.7,1.4,(rear+front)*.5),"steel",true)
		_box("LiftDoorJamb",Vector3(.24,2.65,.20),Vector3(side*1.48,1.325,front),"wood",true)
	_box("LiftCanopy",Vector3(3.6,.15,2.35),Vector3(0,2.88,(rear+front)*.5),"steel",true)
	_box("LiftThreshold",Vector3(2.8,.025,.25),Vector3(0,.0125,front),"steel")
	# The landing camera sits behind this sign. A front-only panel keeps the
	# rear view clear while retaining a readable fascia from the terrace.
	var fascia := MeshInstance3D.new();fascia.name = "LiftFascia"
	var panel := QuadMesh.new();panel.size = Vector2(3.15,.66)
	var panel_material := StandardMaterial3D.new();panel_material.albedo_color = Color(.88,.85,.74)
	panel_material.cull_mode = BaseMaterial3D.CULL_BACK
	fascia.mesh = panel;fascia.material_override = panel_material;fascia.position = Vector3(0,2.35,front-.15);fascia.rotation.y = PI;add_child(fascia)
	var title := _sign("RoofTitle",profile_title,Vector3(0,2.47,front-.157),22)
	title.pixel_size = .0065;title.double_sided = false;title.rotation.y = PI
	var lift_sign := _sign("LiftReturnSign","E · 엘리베이터",Vector3(0,2.17,front-.157),20)
	lift_sign.pixel_size = .0045;lift_sign.double_sided = false;lift_sign.rotation.y = PI
	features.append("clear_central_lift_landing")

func _plant(point: Vector3, scale_factor := 1.0) -> void:
	_box("Planter",Vector3(.95,.48,.95)*scale_factor,point+Vector3.UP*.24*scale_factor,"terracotta",true)
	_box("PlanterSoil",Vector3(.83,.05,.83)*scale_factor,point+Vector3.UP*.49*scale_factor,"soil")
	_cylinder("TreeTrunk",point+Vector3.UP*1.05*scale_factor,.07*scale_factor,1.1*scale_factor,"wood")
	var visual := MeshInstance3D.new();visual.name = "TreeCrown"
	var mesh := SphereMesh.new();mesh.radius = .60*scale_factor;mesh.height = 1.28*scale_factor;mesh.radial_segments = 12;mesh.rings = 6
	visual.mesh = mesh;visual.material_override = _materials.leaf;visual.position = point+Vector3.UP*1.65*scale_factor;add_child(visual)

func _bench(point: Vector3) -> void:
	_box("BenchSeat",Vector3(2.2,.16,.62),point+Vector3.UP*.48,"wood",true)
	_box("BenchBack",Vector3(2.2,.63,.10),point+Vector3(0,.86,-.28),"wood",true)
	for x in [-.82,.82]:_box("BenchLeg",Vector3(.12,.42,.44),point+Vector3(x,.21,0),"steel")

func _build_garden() -> void:
	var garden_x := minf(width*.28,width*.5-1.6)
	var garden_z := -depth*.5+3.1
	var bed_width := minf(4.5,width*.5-2.15)
	_box("GardenBed",Vector3(bed_width,.30,4.2),Vector3(garden_x,.15,garden_z),"terracotta",true)
	_box("GardenGrass",Vector3(bed_width-.20,.05,4.0),Vector3(garden_x,.325,garden_z),"grass")
	for z in [-1.25,1.25]:_plant(Vector3(garden_x,.34,garden_z+z),.8)
	var lounge_x := -garden_x
	_bench(Vector3(lounge_x,0,garden_z+1.8))
	_bench(Vector3(garden_x,0,minf(1.4,depth*.5-5.5)))
	var pergola_width := minf(3.6,width*.5-1.9)
	for side in [-1.0,1.0]:
		for z in [-1.8,1.8]:_box("PergolaPost",Vector3(.14,2.75,.14),Vector3(lounge_x+side*pergola_width*.5,1.375,garden_z+z),"wood",true)
	for index in range(7):_box("PergolaSlat",Vector3(pergola_width+.35,.12,.14),Vector3(lounge_x,2.8,garden_z-1.8+index*.6),"wood")
	_plant(Vector3(-width*.5+1.1,0,depth*.5-4.8),.8)
	_sign("GardenNotice","하늘정원 · 잠시 쉬어 가세요",Vector3(garden_x,1.35,garden_z+2.22),22)
	features.append_array(["planted_garden","benches","open_pergola"])

func _pool_dimensions() -> Vector2:
	# Keep a 4.08m lounge side, 2.20m far side, rear skyline strip and
	# independent front access/lift zone inside the existing inset source deck.
	# Rotate the long swimming direction on narrow roofs rather than calling a
	# small tub a swimming pool. A roof that cannot fit 12x6m stays a garden.
	var available := Vector2(width-6.28,depth-9.0)
	if available.x>=POOL_MIN_LONG_M and available.y>=POOL_MIN_SHORT_M:
		return Vector2(minf(POOL_MAX_LONG_M,available.x),minf(POOL_MAX_SHORT_M,available.y))
	if available.y>=POOL_MIN_LONG_M and available.x>=POOL_MIN_SHORT_M:
		return Vector2(minf(POOL_MAX_SHORT_M,available.x),minf(POOL_MAX_LONG_M,available.y))
	return Vector2.ZERO

func _prepare_pool_layout() -> void:
	var clear_size: Vector2=_pool_dimensions()
	_pool_size=clear_size+Vector2(.28,.28)
	_pool_point=Vector3(width*.5-2.20-_pool_size.x*.5,0,-depth*.5+1.45+_pool_size.y*.5)
	_pool_rect=Rect2(Vector2(_pool_point.x,_pool_point.z)-clear_size*.5,clear_size)
	_pool_deck_opening=_pool_rect.grow(.25)
	_pool_access_x=_pool_rect.end.x-1.10

func _build_pool() -> void:
	var clear_size: Vector2=_pool_rect.size
	var basin: Vector2=_pool_size
	var point: Vector3=_pool_point
	var wall_height: float=POOL_RIM_Y-POOL_FLOOR_Y
	var wall_middle: float=(POOL_RIM_Y+POOL_FLOOR_Y)*.5
	_box("PoolSafetyFloor",Vector3(basin.x,.08,basin.y),point+Vector3(0,POOL_FLOOR_Y-.04,0),"tile",true)
	_box("PoolWaterSurface",Vector3(clear_size.x+.05,.035,clear_size.y+.05),point+Vector3.UP*(POOL_SURFACE_Y-.0175),"pool")
	for side: float in [-1.0,1.0]:
		_box("PoolRimX",Vector3(.22,wall_height,basin.y+.22),point+Vector3(side*basin.x*.5,wall_middle,0),"tile",true)
		_box("PoolRimZ",Vector3(basin.x+.22,wall_height,.22),point+Vector3(0,wall_middle,side*basin.y*.5),"tile",true)
		_box("PoolCopingX",Vector3(.38,.06,basin.y+.38),point+Vector3(side*basin.x*.5,.03,0),"cream")
		_box("PoolCopingZ",Vector3(basin.x+.38,.06,.38),point+Vector3(0,.03,side*basin.y*.5),"cream")
	var along_x: bool=clear_size.x>=clear_size.y
	var long_m: float=maxf(clear_size.x,clear_size.y)
	var short_m: float=minf(clear_size.x,clear_size.y)
	for lane: float in [-1.0,0.0,1.0]:
		var size: Vector3=Vector3(long_m-.7,.008,.075) if along_x else Vector3(.075,.008,long_m-.7)
		var offset: Vector3=Vector3(0,POOL_FLOOR_Y+.009,lane*short_m*.25) if along_x else Vector3(lane*short_m*.25,POOL_FLOOR_Y+.009,0)
		_box("PoolLaneTile",size,point+offset,"ink")
	_build_pool_access(Vector3(_pool_access_x,0,point.z),basin.y)
	_build_pool_inside_steps(Vector3(_pool_access_x,0,point.z),basin.y)
	var lounge_x: float=-width*.5+1.65
	var lounge_count: int=mini(4,maxi(2,int((clear_size.y-1.0)/2.8)))
	for index: int in range(lounge_count):
		var z: float=-depth*.5+2.9+float(index)*2.8
		_box("SunLounger",Vector3(1.1,.35,2.2),Vector3(lounge_x,.175,z),"wood",true)
		_box("SunLoungerCushion",Vector3(1.03,.09,2.08),Vector3(lounge_x,.40,z),"cream")
		_box("SunLoungerBack",Vector3(1.02,.09,.72),Vector3(lounge_x,.58,z-.82),"fabric",false,Basis(Vector3.RIGHT,-.42))
		_box("SunLoungerTowel",Vector3(.55,.025,.70),Vector3(lounge_x,.46,z+.42),"towel")
		if index%2==0:_pool_parasol(Vector3(lounge_x,0,z+1.35))
		_cylinder("LoungeSideTable",Vector3(lounge_x+.77,.28,z+.90),.22,.56,"cream")
	var lounge_length: float=minf(clear_size.y+.9,depth-6.0)
	_box("PoolLoungeDeck",Vector3(2.8,.012,lounge_length),Vector3(lounge_x,.008,-depth*.5+1.2+lounge_length*.5),"wood")
	_build_hotel_pool_amenities(lounge_x,point.z+basin.y*.5,long_m,short_m)
	var dimensions: String="%.1f × %.1fm"%[snappedf(long_m,.1),snappedf(short_m,.1)]
	var entry: Label3D=_sign("PoolEntrySign","계단으로 입수 · Space 물 밖 점프\n수심 1.22m · "+dimensions,Vector3(_pool_access_x,1.28,point.z+basin.y*.5+1.14),19)
	entry.pixel_size=.0055
	features.append_array(["flush_sunken_pool_in_raised_authored_deck","real_open_deck_cutout","large_outdoor_swimming_pool","buoyant_water_region","walk_down_pool_entry","submerged_entry_steps","continuous_access_handrails","visible_splash_and_ripples","solid_safe_pool_floor","sun_loungers","parasol","towels_and_outdoor_shower","hotel_pool_entrance","open_sky_and_city_views","human_scale_lane_tiles"])

func _build_hotel_pool_amenities(lounge_x: float, pool_front: float, long_m: float, short_m: float) -> void:
	var gate_z: float=pool_front+2.20
	for side: float in [-1.0,1.0]:
		_box("HotelPoolGatePost",Vector3(.12,2.45,.12),Vector3(_pool_access_x+side*1.45,1.225,gate_z),"wood",true)
	_box("HotelPoolEntranceFascia",Vector3(3.15,.60,.12),Vector3(_pool_access_x,2.50,gate_z),"ink")
	var brand: Label3D=_sign("PoolNotice","ROOFTOP POOL\n야외 수영장 · %.0f × %.0fm"%[long_m,short_m],Vector3(_pool_access_x,2.48,gate_z+.075),25)
	brand.pixel_size=.0055;brand.modulate=Color(.96,.94,.82);brand.outline_modulate=Color(.08,.17,.18)
	var shower_z: float=pool_front+1.55
	_box("OutdoorShowerPad",Vector3(1.6,.025,1.6),Vector3(lounge_x,.015,shower_z),"tile")
	_box("OutdoorShowerColumn",Vector3(.16,2.3,.16),Vector3(lounge_x-.53,1.15,shower_z-.50),"steel",true)
	_box("OutdoorShowerArm",Vector3(.16,.10,.75),Vector3(lounge_x-.53,2.27,shower_z-.15),"steel")
	_cylinder("OutdoorShowerHead",Vector3(lounge_x-.53,2.20,shower_z+.17),.20,.07,"steel")
	_cylinder("OutdoorShowerTap",Vector3(lounge_x-.40,1.05,shower_z-.49),.07,.04,"cream")
	var shower_sign: Label3D=_sign("OutdoorShowerSign","야외 샤워",Vector3(lounge_x,1.62,shower_z-.58),18);shower_sign.pixel_size=.0045
	_box("TowelStand",Vector3(1.10,.74,.55),Vector3(lounge_x,.37,shower_z+1.35),"wood",true)
	for index: int in range(3):
		_box("FoldedPoolTowel",Vector3(.82,.09,.40),Vector3(lounge_x,.79+float(index)*.095,shower_z+1.35),"towel")
	var towel_sign: Label3D=_sign("TowelSign","POOL TOWELS",Vector3(lounge_x,1.35,shower_z+1.35),16);towel_sign.pixel_size=.0045
	_plant(Vector3(-width*.5+1.0,0,depth*.5-2.4),.80)
	_plant(Vector3(_pool_point.x,0,-depth*.5+.65),.65)
	_box("PoolLifeRingHolder",Vector3(.10,1.2,.10),Vector3(_pool_access_x-2.0,.60,gate_z+.10),"steel")
	var ring: MeshInstance3D=MeshInstance3D.new();ring.name="PoolLifeRing"
	var torus: TorusMesh=TorusMesh.new();torus.inner_radius=.22;torus.outer_radius=.37;torus.rings=16;torus.ring_segments=8
	ring.mesh=torus;ring.material_override=_materials.cream;ring.position=Vector3(_pool_access_x-2.0,1.0,gate_z+.10);ring.rotation.x=PI*.5;add_child(ring)

func _pool_parasol(point: Vector3) -> void:
	_cylinder("ParasolPole",point+Vector3.UP*1.2,.04,2.4,"steel")
	var canopy := MeshInstance3D.new();canopy.name = "ParasolCanopy"
	var mesh := CylinderMesh.new();mesh.top_radius = .18;mesh.bottom_radius = 1.55;mesh.height = .48;mesh.radial_segments = 12
	canopy.mesh = mesh;canopy.position = point+Vector3.UP*2.57;canopy.material_override = _materials.cream;add_child(canopy)

func _pool_rail(title: String, first: Vector3, last: Vector3) -> void:
	var direction := last-first
	_box(title,Vector3(.07,.07,direction.length()),(first+last)*.5,"steel",false,Basis.looking_at(direction,Vector3.UP))

func _build_pool_inside_steps(point: Vector3, pool_depth: float) -> void:
	var front := point.z+pool_depth*.5
	var top_z := front-.25
	var bottom_z := front-3.05
	var body := StaticBody3D.new();body.name = "PoolSubmergedRampBody";body.collision_layer = 1;body.collision_mask = 0
	body.set_meta("geometry_id","EXP16_rooftop_PoolSubmergedRamp")
	var collision := CollisionShape3D.new();var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(point.x-.73,POOL_FLOOR_Y-.05,bottom_z),Vector3(point.x+.73,POOL_FLOOR_Y-.05,bottom_z),
		Vector3(point.x-.73,POOL_FLOOR_Y,bottom_z),Vector3(point.x+.73,POOL_FLOOR_Y,bottom_z),
		Vector3(point.x-.73,POOL_RIM_Y-.12,top_z),Vector3(point.x+.73,POOL_RIM_Y-.12,top_z),
		Vector3(point.x-.73,POOL_RIM_Y,top_z),Vector3(point.x+.73,POOL_RIM_Y,top_z)])
	collision.shape = shape;body.add_child(collision);add_child(body);bodies.append(body)
	for index in range(8):
		var step_y := lerpf(POOL_RIM_Y,POOL_FLOOR_Y,(float(index)+.5)/8.0)
		var step_z := lerpf(top_z,bottom_z,float(index)/8.0)
		_box("PoolSubmergedTread",Vector3(1.46,.09,(top_z-bottom_z)/8.0+.02),Vector3(point.x,step_y-.045,step_z-.18),"tile")
	for side in [-1.0,1.0]:
		_pool_rail("PoolSubmergedHandrail",Vector3(point.x+side*.79,POOL_RIM_Y+.88,top_z),Vector3(point.x+side*.79,POOL_FLOOR_Y+.88,bottom_z))
		for z in [top_z,bottom_z]:
			var y := POOL_RIM_Y if z==top_z else POOL_FLOOR_Y
			_box("PoolSubmergedRailPost",Vector3(.07,.88,.07),Vector3(point.x+side*.79,y+.44,z),"steel")

func _build_pool_access(point: Vector3, pool_depth: float) -> void:
	var front: float=point.z+pool_depth*.5
	# Deck and threshold share Y=0. Only the stairs inside the open water
	# descend; there is no exterior tank staircase or raised opaque wall.
	_box("PoolRimLanding",Vector3(1.50,.14,.50),Vector3(point.x,-.07,front),"tile",true)
	for side: float in [-1.0,1.0]:
		_pool_rail("PoolAccessHandrail",Vector3(point.x+side*.79,.95,front+.90),Vector3(point.x+side*.79,.95,front-.25))
		_box("PoolAccessRailPost",Vector3(.07,.95,.07),Vector3(point.x+side*.79,.475,front+.90),"steel")

func _water_splash(world_point: Vector3, impact_speed_mps: float) -> void:
	if water_effects==null or _pool_rect==Rect2():return
	var local: Vector3 = frame.affine_inverse()*world_point
	if not _pool_rect.has_point(Vector2(local.x,local.z)):return
	water_effects.emit_splash(Vector3(local.x,POOL_SURFACE_Y,local.z),impact_speed_mps)

func pool_water_region() -> Dictionary:
	if profile_id!="outdoor_pool" or _pool_rect==Rect2():return {}
	return {"id":String(spec.get("id",""))+":roof_pool","frame":frame,"rect":_pool_rect,"floor_y":POOL_FLOOR_Y,"surface_y":POOL_SURFACE_Y}

func pool_entry_point() -> Vector3:
	return frame*Vector3(_pool_access_x,.08,_pool_point.z+_pool_size.y*.5+1.40)

func pool_rim_point() -> Vector3:
	return frame*Vector3(_pool_access_x,POOL_RIM_Y+.08,_pool_point.z+_pool_size.y*.5+.40)

func pool_float_point() -> Vector3:
	return frame*Vector3(_pool_point.x,POOL_SURFACE_Y-1.0,_pool_point.z)

func pool_dimensions() -> Dictionary:
	if profile_id!="outdoor_pool":return {}
	return {"clear_water_width_m":_pool_rect.size.x,"clear_water_depth_m":_pool_rect.size.y,"clear_water_area_m2":_pool_rect.get_area(),
		"long_dimension_m":maxf(_pool_rect.size.x,_pool_rect.size.y),"short_dimension_m":minf(_pool_rect.size.x,_pool_rect.size.y),
		"water_depth_m":POOL_SURFACE_Y-POOL_FLOOR_Y,"minimum_long_m":POOL_MIN_LONG_M,"minimum_short_m":POOL_MIN_SHORT_M,
		"open_sky":true,"roof_canopy_over_water":false,"deck_raise_m":POOL_DECK_RAISE_M,"surface_below_deck_m":-POOL_SURFACE_Y,"floor_below_deck_m":-POOL_FLOOR_Y,"rim_above_deck_m":POOL_RIM_Y,"deck_opening_rect":_pool_deck_opening,"submerged_steps_rect":Rect2(Vector2(_pool_access_x-.73,_pool_point.z+_pool_size.y*.5-3.05),Vector2(1.46,2.80))}

func pool_camera_point() -> Vector3:
	return frame*Vector3(-width*.5+2.2,4.2,minf(depth*.5-4.5,_pool_point.z+_pool_size.y*.5+1.8))

func pool_camera_pivot_hint(_world_point: Vector3) -> Dictionary:
	# The sunken pool has a flush deck edge. Its production view uses the
	# normal third-person pivot; the former raised-wall hint is unnecessary.
	return {}

func pool_steps_bottom_point() -> Vector3:
	return frame*Vector3(_pool_access_x,POOL_FLOOR_Y+.08,_pool_point.z+_pool_size.y*.5-3.20)

func _build_penthouse() -> void:
	var house_width := minf(13.0,width-2.5)
	var house_depth := minf(9.5,depth-7.0)
	var rear := -depth*.5+1.1
	var front := rear+house_depth
	var height := 2.85
	_box("PenthouseFloor",Vector3(house_width,.015,house_depth),Vector3(0,.012,(rear+front)*.5),"wood")
	_box("PenthouseRear",Vector3(house_width,height,.14),Vector3(0,height*.5,rear),"cream",true)
	for side in [-1.0,1.0]:
		_box("PenthouseGlassSide",Vector3(.10,height,house_depth),Vector3(side*house_width*.5,height*.5,(rear+front)*.5),"glass",true)
		var segment := (house_width-2.2)*.5
		_box("PenthouseFrontGlass",Vector3(segment,height,.10),Vector3(side*(1.1+segment*.5),height*.5,front),"glass",true)
		_box("PenthouseDoorJamb",Vector3(.08,2.5,.13),Vector3(side*1.1,1.25,front),"steel",true)
	_box("PenthouseCanopy",Vector3(house_width+.25,.16,house_depth+.25),Vector3(0,height+.08,(rear+front)*.5),"cream",true)
	# The front has an actual 2.2m opening; its leaf is held open along one jamb.
	_box("PenthouseOpenDoor",Vector3(.08,2.35,1.05),Vector3(-1.1,1.175,front-.54),"glass",true)
	_box("PenthouseDoorHandle",Vector3(.04,.35,.06),Vector3(-1.02,1.10,front-.86),"steel")
	var lounge_x := -minf(3.1,house_width*.5-1.25)
	var lounge_z := rear+2.4
	_box("PenthouseSofa",Vector3(2.0,.42,2.6),Vector3(lounge_x,.30,lounge_z),"fabric",true)
	_box("PenthouseSofaBack",Vector3(.24,.65,2.65),Vector3(lounge_x-.9,.77,lounge_z),"fabric",true)
	_box("PenthouseCoffeeTable",Vector3(1.1,.42,1.4),Vector3(-lounge_x,.21,lounge_z),"wood",true)
	_box("PenthouseBook",Vector3(.26,.055,.35),Vector3(-lounge_x,.455,lounge_z),"cream")
	_sign("PenthouseTitle","스카이라운지 · 열린 테라스",Vector3(0,2.50,front+.08),24)
	_plant(Vector3(width*.5-1.1,0,depth*.5-5.0),.8)
	_bench(Vector3(-width*.5+1.7,0,depth*.5-5.0))
	features.append_array(["open_2_2m_penthouse_door","glass_lounge","sofa_and_table","outdoor_terrace"])

func spawn_point() -> Vector3:
	return frame*Vector3(0,.08,depth*.5-3.65)

func lift_point() -> Vector3:
	return spawn_point()

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]

func snapshot() -> Dictionary:
	return {"building_id":String(spec.get("id","")),"building_title":String(spec.get("title","")),"profile_id":profile_id,"profile_title":profile_title,"loaded":_loaded,
		"source_height_y":source_height_y,"source_height_m":spec.get("source_height",0.0),"base_offset_m":spec.get("base_offset_m",0.0),"terrain_elevation_applied":spec.get("terrain_elevation_applied",false),"observed_top_y":observed_top_y,"deck_height_y":deck_height_y,"source_height_offset_m":deck_height_y-source_height_y,
		"clearance_above_observed_m":deck_height_y-observed_top_y,"base_source_clearance_m":DECK_CLEARANCE_M,"authored_pool_deck_raise_m":POOL_DECK_RAISE_M if profile_id=="outdoor_pool" else 0.0,"source_inset_m":SOURCE_INSET_M,"source_rectangle_width":spec.get("width",0.0),"source_rectangle_depth":spec.get("depth",0.0),
		"width":width,"depth":depth,"frame_origin":_v(frame.origin),"frame_axes":[_v(frame.basis.x),_v(frame.basis.y),_v(frame.basis.z)],"frame_determinant":frame.basis.determinant(),
		"walkable_rect_position":[walkable_rect.position.x,walkable_rect.position.y],"walkable_rect_size":[walkable_rect.size.x,walkable_rect.size.y],
		"world_bounds_position":_v(world_bounds.position),"world_bounds_size":_v(world_bounds.size),"spawn":_v(spawn_point()),"lift_point":_v(lift_point()),
		"ceiling_unbounded":true,"open_sky_jump_space":true,"landing_validation_height_m":9.35,
		"features":features.duplicate(),"collision_bodies":bodies.size(),"height_observations":observations.duplicate(true),
		"pool_dimensions":pool_dimensions(),"pool_camera_point":_v(pool_camera_point()) if profile_id=="outdoor_pool" else [],"water_region":pool_water_region(),"water_effects":water_effects.snapshot() if water_effects!=null else {},"pool_entry":_v(pool_entry_point()) if profile_id=="outdoor_pool" else [],"pool_rim":_v(pool_rim_point()) if profile_id=="outdoor_pool" else [],
		"basis":"Source-positioned fictional game amenity on an inset source rectangle; observed source-top clearance is an authored offset, not a surveyed roof or factual pool/penthouse. Pool deck is authored 1.55m above the normal source-clearance deck, with four solid surround panels and a real water opening. The basin floor remains above the intact source roof; water is 0.18m below deck and 1.22m deep. No source height correction, surveyed venue amenity or full fluid simulation."}
