extends "res://../tests/game/check_rooftops.gd"
## Keep the historical all125 geometry/landing checks and its three physical
## visits. Old edge guards intentionally apply only with free roaming OFF;
## unrestricted outdoor departure is covered by check_outdoor_roof_jumping.

func _ride_to(index: int, title: String) -> bool:
	for path: String in ["res://../tests/game/check_rooftops_bounded_regression.gd","res://scripts/exploration_rooftop_access.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	if index==int(visit.current_spec.floor_count):
		scene.set_free_roam(false);_keys();await _ticks(3)
	var completed: bool=await super._ride_to(index,title)
	if completed and index==0:
		# Restore outdoor traversal before the next original-source doorway.
		scene.set_free_roam(true);_keys();await _ticks(3)
	return completed
