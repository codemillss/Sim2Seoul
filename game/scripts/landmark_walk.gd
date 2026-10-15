extends "res://scripts/public_walk.gd"
## Separate L02 entry point keeps the frozen W04 production scene reproducible.
@onready var landmark_visuals: Node3D = $PalaceLandmarks

func _ready() -> void:
	super._ready()
	if not runtime_ok: return
	if not landmark_visuals.apply_to(city):
		runtime_ok = false
		input_router.gameplay_enabled = false
		rig.set_capture(false)
		status.text = landmark_visuals.load_error
		push_error(landmark_visuals.load_error)
		return
	print("L02_READY landmarks=", landmark_visuals.bundle.landmarks.size(), " components=", landmark_visuals.components.size(), " new_collision=0")
