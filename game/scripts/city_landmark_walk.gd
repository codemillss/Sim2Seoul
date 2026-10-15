extends "res://scripts/landmark_walk.gd"
## Additive L03 scene retains the exact L02 palace and W04 physics.
@onready var city_visuals: Node3D = $CityLandmarks

func _ready() -> void:
	super._ready()
	if not runtime_ok: return
	if not city_visuals.apply_to(city):
		runtime_ok = false
		input_router.gameplay_enabled = false
		rig.set_capture(false)
		status.text = city_visuals.load_error
		push_error(city_visuals.load_error)
		return
	print("L03_READY landmarks=", city_visuals.bundle.landmarks.size(), " components=", city_visuals.components.size(), " new_collision=0")
