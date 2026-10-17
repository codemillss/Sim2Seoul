extends SceneTree
## Diagnostic priority windows; no gameplay/FPS acceptance.
class TimingProbe extends Node:
	var sink: Dictionary
	var slot: String
	var begin: bool
	func _physics_process(_delta: float) -> void:
		if begin:sink[slot+"_start"]=Time.get_ticks_usec()
		elif sink.has(slot+"_start"):sink[slot].append(Time.get_ticks_usec()-int(sink[slot+"_start"]))
class CallbackProbe extends RefCounted:
	var original: Callable
	var count: int=0
	var total_us: int=0
	var max_us: int=0
	func record(start: int) -> void:
		var elapsed: int=Time.get_ticks_usec()-start;count+=1;total_us+=elapsed;max_us=maxi(max_us,elapsed)
	func ground(point: Vector3) -> Dictionary:
		var start: int=Time.get_ticks_usec();var result: Dictionary=original.call(point);record(start);return result
	func point(group: Dictionary,station: float,side: float) -> Vector3:
		var start: int=Time.get_ticks_usec();var result: Vector3=original.call(group,station,side);record(start);return result
	func allowed(point: Vector3,radius: float) -> bool:
		var start: int=Time.get_ticks_usec();var result: bool=original.call(point,radius);record(start);return result
	func neighbors(group: Dictionary) -> Array:
		var start: int=Time.get_ticks_usec();var result: Array=original.call(group);record(start);return result
var scene: Node3D
var report_path: String=""
func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if not report_path.is_absolute_path():quit(1);return
	_run.call_deferred()
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();var settings: String="/private/tmp/exp21-subsystems-"+str(OS.get_process_id())+".json"
	scene.exploration_settings_path=settings;scene.quality_settings_path=settings+".quality";root.add_child(scene)
	for tick: int in range(5):await physics_frame
	if not scene.runtime_ok:quit(1);return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_vehicles_running(false);scene.set_pedestrians_running(true)
	var times: Dictionary={"street":[],"original":[],"coverage":[]};var priorities: Dictionary={}
	var modules: Array=[scene.street_pedestrians,scene.exploration_pedestrians,scene.neighborhood_population.walkers]
	var labels: Array[String]=["street","original","coverage"]
	var callbacks: Dictionary={}
	for index: int in range(modules.size()):
		var module: Node=modules[index];var priority: int=100*(index+1);priorities[labels[index]]=module.process_physics_priority;module.process_physics_priority=priority
		if index!=1:
			var avoidance: RefCounted=module.avoidance
			for kind: String in ["ground","point","allowed","neighbors"]:
				var property: String={"ground":"ground_at","point":"point_at","allowed":"allowed_at","neighbors":"neighbors"}[kind]
				var callback: CallbackProbe=CallbackProbe.new();callback.original=avoidance.get(property);avoidance.set(property,Callable(callback,kind));callbacks[labels[index]+"_"+kind]=callback
		for start: bool in [true,false]:
			var probe: TimingProbe=TimingProbe.new();probe.sink=times;probe.slot=labels[index];probe.begin=start;probe.process_physics_priority=priority+(-1 if start else 1);root.add_child(probe)
	for tick: int in range(40):await physics_frame
	var callback_rows: Dictionary={}
	for key: String in callbacks:
		var callback: CallbackProbe=callbacks[key];callback_rows[key]={"count":callback.count,"total_us":callback.total_us,"max_us":callback.max_us}
	var report: Dictionary={"task":"EXP21_SUBSYSTEM_TIMING","result":"OBSERVED","display":DisplayServer.get_name(),"timing_usec":times,"callback_usec":callback_rows,"original_priorities":priorities,"scope":"Explicit diagnostic fixture sets three pedestrian controllers to unique priorities100/200/300 with before/after timing nodes and wraps exact avoidance callbacks for timing. Counts40physics frames; no gameplay/order-equivalence or performance acceptance claim."}
	var file: FileAccess=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ")+"\n");file.close();print("EXP21_SUBSYSTEM_TIMING OBSERVED");quit()
