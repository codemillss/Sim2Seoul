extends "res://scripts/player/movement_controller.gd"
## A local W01 area and volume guard supplement the inherited physical spawn checks.
@export var world_path: NodePath
@onready var connection_world: Node3D=get_node(world_path)
func _inside(point: Vector3) -> bool:
	return point.is_finite() and not connection_world.connection.is_empty() and Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),connection_world.movement_polygon())
func _valid_spawn() -> bool:
	if not super._valid_spawn():return false
	return connection_world.volume_clear(spawn_transform.origin,$CollisionShape.shape.height,$CollisionShape.shape.radius)
