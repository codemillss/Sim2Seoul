extends Node
## Temporary ownership of a real adult capsule for a bounded physical stagger.
## Normal route controllers retain their identity/route and resume afterwards.
var safety: Node3D
var body: CharacterBody3D
var remaining_s := 0.0
var impulse := Vector3.ZERO
var distance_m := 0.0
var maximum_step_m := 0.0
var active := false
static func owns(actor: CharacterBody3D) -> bool:
	var owner: Variant=actor.get_meta("sandbox_reaction_owner") if actor.has_meta("sandbox_reaction_owner") else null
	return is_instance_valid(owner) and bool(owner.active)
func start(service: Node3D,actor: CharacterBody3D,direction: Vector3,kind: String) -> void:
	safety=service;body=actor;process_physics_priority=-2;process_mode=Node.PROCESS_MODE_PAUSABLE
	var prior: Variant=body.get_meta("sandbox_reaction_owner") if body.has_meta("sandbox_reaction_owner") else null
	if is_instance_valid(prior):prior.finish("refreshed_contact")
	remaining_s=.65 if kind=="shove" else .48;impulse=direction*(1.75 if kind=="shove" else 1.15);active=true
	body.set_meta("sandbox_reaction_owner",self)
func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(body):queue_free();return
	if safety.host.menu.visible:return
	if remaining_s<=0.:finish("route_restored");return
	remaining_s-=delta
	var before:=body.global_position;var next:=before+impulse*delta
	var support: Dictionary=safety._supported(next)
	var allowed: bool=not support.is_empty() and safety._segment_allowed(before,support.point,body)
	# Street walkers keep the same road/private/entrance rules as their route.
	var parent: Node=body.get_parent()
	if allowed and parent.has_method("_allowed"):allowed=parent._allowed(next,.27)
	if allowed:body.velocity=Vector3(impulse.x,(support.point.y-before.y)/delta-.9,impulse.z)
	else:body.velocity=Vector3(0.,-.9,0.)
	body.move_and_slide()
	var step: float=Vector2(body.global_position.x-before.x,body.global_position.z-before.z).length()
	distance_m+=step;maximum_step_m=maxf(maximum_step_m,step);impulse=impulse.move_toward(Vector3.ZERO,5.8*delta)
func finish(reason: String) -> void:
	if not active:return
	active=false
	if is_instance_valid(body):
		if body.has_meta("sandbox_reaction_owner") and body.get_meta("sandbox_reaction_owner")==self:body.remove_meta("sandbox_reaction_owner")
		body.velocity=Vector3.ZERO
		safety._event("victim_physical_stagger_finished",{"target_path":String(body.get_path()),"distance_m":distance_m,"maximum_step_m":maximum_step_m,"reason":reason,"original_route_restored":true})
	queue_free()
