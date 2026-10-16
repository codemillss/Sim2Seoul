extends "res://scripts/player/public_player.gd"
## Extra outdoor movement belongs to the exploration scene, not the W03 source boundary.
var free_roam_enabled := true
var free_roam_bounds := Rect2(-450.0,-460.0,900.0,920.0)
const EDGE_MARGIN_M := 0.4
const SEGMENT_SAMPLE_M := 0.05

func _inside(point: Vector3) -> bool:
	if not free_roam_enabled:return super._inside(point)
	if not point.is_finite():return false
	var p:=Vector2(point.x,point.z)
	if not free_roam_bounds.grow(-EDGE_MARGIN_M).has_point(p):return false
	# Preserve the authored private exclusion, including the capsule's footprint.
	if connection_world._contains(p,connection_world.private_cache):return false
	for polygon in connection_world.private_cache:
		for ring in polygon:
			for i in range(ring.size()-1):
				if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,ring[i],ring[i+1]))<EDGE_MARGIN_M*EDGE_MARGIN_M:return false
	return true

func _segment_inside(direction: Vector3) -> bool:
	var speed:=run_speed_mps if router.fast_intent() else walk_speed_mps
	var offset:=direction*speed*step_delta
	var samples:=maxi(1,int(ceil(offset.length()/SEGMENT_SAMPLE_M)))
	for i in range(1,samples+1):
		if not _inside(global_position+offset*float(i)/float(samples)):return false
	return true

func _direction(intent: Vector2) -> Vector3:
	var result: Vector3=super._direction(intent)
	if result.is_zero_approx() or not _inside(global_position):return result
	if _segment_inside(result):return result
	boundary_stops+=1
	last_boundary_reason="exploration_edge" if free_roam_enabled else "walk_edge"
	for along in [Vector3(result.x,0,0),Vector3(0,0,result.z)]:
		if not along.is_zero_approx() and _segment_inside(along):return along
	return Vector3.ZERO
