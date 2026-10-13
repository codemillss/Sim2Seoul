extends CharacterBody3D
## P01 support only. Horizontal input, recovery and locomotion belong to P02.
signal physics_stepped(delta_seconds: float)
@export var gravity_mps2 := 9.8

func _physics_process(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if is_on_floor(): velocity.y = 0.0
	velocity.y -= gravity_mps2 * delta
	move_and_slide()
	physics_stepped.emit(delta)
