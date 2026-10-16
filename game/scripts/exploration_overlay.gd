extends Node3D
## This game-only floor opens outdoor exploration; it is not surveyed terrain/access.
## The rectangle is inside the four projected corners of the existing regional source.
const EXPLORATION_BOUNDS := Rect2(-450.0,-460.0,900.0,920.0)
const FLOOR_LAYER := 32
var bounds := EXPLORATION_BOUNDS
var support: StaticBody3D
var old_guide: Node3D
var building_facades: Node3D
var exploration_enabled := false

func setup(city: Node3D,player: CharacterBody3D) -> bool:
	if not city.get_parent().runtime_ok:return false
	var shape:=BoxShape3D.new()
	shape.size=Vector3(bounds.size.x,0.2,bounds.size.y)
	var collider:=CollisionShape3D.new();collider.shape=shape
	support=StaticBody3D.new();support.name="ExplorationGround"
	# Layer 6 is used only by this player and its camera. NPC/car support stays unchanged.
	support.collision_layer=FLOOR_LAYER;support.collision_mask=2
	support.position=Vector3(bounds.get_center().x,-0.1,bounds.get_center().y)
	support.add_child(collider);add_child(support)
	player.free_roam_bounds=bounds
	player.collision_mask=player.collision_mask|FLOOR_LAYER
	var rig: Node3D=city.get_parent().rig
	rig.arm.collision_mask=rig.arm.collision_mask|FLOOR_LAYER
	old_guide=city.get_parent().get_node_or_null("Presentation/BoundaryGuide")
	building_facades=preload("res://scripts/city_facades.gd").new()
	building_facades.name="CityFacades";add_child(building_facades)
	if not building_facades.setup(city):return false
	print("EXTERIORS_READY buildings=",building_facades.building_count," materials=",building_facades.material_count)
	return true

func set_enabled(enabled: bool) -> void:
	exploration_enabled=enabled
	if is_instance_valid(support):support.collision_layer=FLOOR_LAYER if enabled else 0
	if is_instance_valid(old_guide):old_guide.visible=not enabled
