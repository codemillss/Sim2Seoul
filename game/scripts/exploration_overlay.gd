extends Node3D
## This game-only floor opens outdoor exploration; it is not surveyed terrain/access.
## The player polygon follows the projected corners of the existing source bbox.
const EXPLORATION_BOUNDS := Rect2(-450.0,-460.0,900.0,920.0)
const EXTENT_PATH := "res://assets/authored/exploration_extent.json"
const FLOOR_LAYER := 32
var bounds := EXPLORATION_BOUNDS
var support: StaticBody3D
var old_guide: Node3D
var building_facades: Node3D
var exploration_enabled := false
var polygon := PackedVector2Array()
var extent: Dictionary={}
var _player: CharacterBody3D

func setup(city: Node3D,player: CharacterBody3D) -> bool:
	if not city.get_parent().runtime_ok:return false
	if not _load_extent():return false
	_player=player
	var shape:=BoxShape3D.new()
	shape.size=Vector3(bounds.size.x,0.2,bounds.size.y)
	var collider:=CollisionShape3D.new();collider.shape=shape
	support=StaticBody3D.new();support.name="ExplorationGround"
	# Shared authored support for exploration and independent layer32 NPCs.
	# Walking mode disables only the player's bit; source traffic stays intact.
	support.collision_layer=FLOOR_LAYER;support.collision_mask=2
	support.position=Vector3(bounds.get_center().x,-0.1,bounds.get_center().y)
	support.add_child(collider);add_child(support)
	player.free_roam_bounds=bounds
	player.free_roam_polygon=polygon
	player.collision_mask=player.collision_mask|FLOOR_LAYER
	var rig: Node3D=city.get_parent().rig
	rig.arm.collision_mask=rig.arm.collision_mask|FLOOR_LAYER
	old_guide=city.get_parent().get_node_or_null("Presentation/BoundaryGuide")
	building_facades=preload("res://scripts/city_facades.gd").new()
	building_facades.name="CityFacades";add_child(building_facades)
	if not building_facades.setup(city):return false
	print("EXTERIORS_READY buildings=",building_facades.building_count," materials=",building_facades.material_count)
	return true

func _load_extent() -> bool:
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(EXTENT_PATH))
	var world_path: String="res://resources/world_geometry/world.json"
	var world: Variant=JSON.parse_string(FileAccess.get_file_as_string(world_path))
	if not parsed is Dictionary or parsed.get("schema_version")!=1 or parsed.get("coordinate_space")!="local_xz_metres" or not parsed.get("polygon_xz") is Array:return false
	if not world is Dictionary or parsed.get("world_sha256")!=FileAccess.get_sha256(world_path) or parsed.get("coordinate_contract_sha256")!=world.get("coordinate_contract_sha256"):return false
	if parsed.polygon_xz.size()!=4 or not is_equal_approx(float(parsed.get("capsule_edge_margin_m",0.)),.4):return false
	var candidate:=PackedVector2Array()
	for point: Variant in parsed.polygon_xz:
		if not point is Array or point.size()!=2:return false
		if not (point[0] is float or point[0] is int) or not (point[1] is float or point[1] is int):return false
		var p:=Vector2(float(point[0]),float(point[1]))
		if not p.is_finite():return false
		candidate.append(p)
	if Geometry2D.triangulate_polygon(candidate).size()!=6:return false
	var minimum: Vector2=candidate[0];var maximum: Vector2=candidate[0]
	for point: Vector2 in candidate:
		minimum=minimum.min(point);maximum=maximum.max(point)
	var next_bounds:=Rect2(minimum,maximum-minimum)
	if next_bounds.size.x<900. or next_bounds.size.y<920. or next_bounds.size.x>1000. or next_bounds.size.y>1000.:return false
	for point: Vector2 in [EXPLORATION_BOUNDS.position,EXPLORATION_BOUNDS.end,Vector2(EXPLORATION_BOUNDS.position.x,EXPLORATION_BOUNDS.end.y),Vector2(EXPLORATION_BOUNDS.end.x,EXPLORATION_BOUNDS.position.y)]:
		if not Geometry2D.is_point_in_polygon(point,candidate):return false
	polygon=candidate;bounds=next_bounds;extent=parsed
	return true

func set_enabled(enabled: bool) -> void:
	exploration_enabled=enabled
	# Independent scenery/NPCs retain their shared authored support. The
	# historical walking mode excludes it only from this player's collision
	# queries, while keeping every pre-existing player mask bit unchanged.
	if is_instance_valid(support):support.collision_layer=FLOOR_LAYER
	if is_instance_valid(_player):_player.collision_mask=(_player.collision_mask|FLOOR_LAYER) if enabled else (_player.collision_mask&~FLOOR_LAYER)
	if is_instance_valid(old_guide):old_guide.visible=not enabled
