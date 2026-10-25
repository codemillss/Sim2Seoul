extends SceneTree
## Tiny scheduler integration fixture: production _process, one bone and current
## source marker. Does not load city assets or validate the anatomical solver.
const LOD := preload("res://scripts/player/web_human_visual_lod.gd")
class FixtureAvatar extends Node3D:
	var player: Node3D
	var marker: Node3D
class FixtureRig extends "res://scripts/player/textured_human_rig.gd":
	var sync_calls := 0
	func sync_pose() -> bool:
		var started:=Time.get_ticks_usec()
		var source: Node3D=avatar.get("marker")
		skeleton.set_bone_pose(0,Transform3D(Basis.from_euler(Vector3(.1,.2,.3)),source.position))
		sync_calls+=1
		if _web_visual_lod!=null:_web_visual_lod.record_sync(started,Time.get_ticks_usec())
		return true
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check(LOD.interval_for(1_000_000.,true,false,true)==0,"local player stays current even with distant camera")
	_check(LOD.interval_for(100.,false,false,false)==0,"within ten metres stays current including offscreen")
	_check(LOD.interval_for(900.,true,true,false)==33_333,"visible thirty metre boundary updates at thirty Hz")
	_check(LOD.interval_for(900.01,true,true,false)==100_000,"farther visible actor updates at ten Hz")
	_check(LOD.interval_for(10_000.,true,true,false)==100_000,"visible hundred metre boundary stays at ten Hz")
	_check(LOD.interval_for(10_000.01,true,true,false)>=500_000,"remote actor is bounded to one to two Hz")
	_check(LOD.interval_for(400.,true,false,false,99_999)==199_999,"offscreen rate spans five to ten Hz")
	_check(LOD.interval_for(40_000.,true,true,false,499_999)==999_999,"remote phase staggering remains above one Hz")
	_check(LOD.interval_for(400.,false,true,false)>=1_000_000,"hidden geometry retains a bounded update")
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.make_current()
	var actor:=CharacterBody3D.new();world.add_child(actor);actor.position=Vector3(0.,0.,-200.)
	actor.collision_layer=4;actor.collision_mask=37;actor.velocity=Vector3(1.,0.,2.)
	var capsule:=CollisionShape3D.new();capsule.shape=CapsuleShape3D.new();actor.add_child(capsule)
	var physics_hz:=Engine.physics_ticks_per_second
	var original_velocity:=actor.velocity
	var avatar:=FixtureAvatar.new();avatar.player=actor;actor.add_child(avatar)
	var visual:=Node3D.new();avatar.add_child(visual)
	var marker:=Node3D.new();avatar.add_child(marker);avatar.marker=marker
	marker.position=Vector3(.2,1.1,-.3)
	var skeleton:=Skeleton3D.new();visual.add_child(skeleton);skeleton.add_bone("FixtureBone")
	var rig:=FixtureRig.new();avatar.add_child(rig);rig.set_process(false)
	rig.avatar=avatar;rig.skeleton=skeleton;rig.loaded=true
	rig._web_visual_lod=LOD.new();rig._web_visual_lod.configure(rig,avatar,visual)
	_check(rig.get_viewport().get_camera_3d()==camera,"fixture camera is the actual active viewport camera")
	rig._process(1./60.)
	_check(rig.sync_calls==1,"production automatic process initializes an unsampled rig")
	var held:=skeleton.get_bone_pose(0)
	_check(held.origin==marker.position and held!=Transform3D.IDENTITY,"first visual pose is current and nonidentity")
	marker.position=Vector3(-.4,.7,.6)
	rig._web_visual_lod.last_sync_usec=Time.get_ticks_usec()
	rig._process(1./60.)
	_check(rig.sync_calls==1 and skeleton.get_bone_pose(0)==held,"skipped remote frame preserves its full last pose")
	_check(rig._web_visual_lod.skipped_count==1,"skipped work is observable")
	actor.position=Vector3(0.,0.,-5.)
	rig._process(1./60.)
	_check(rig.sync_calls==2 and skeleton.get_bone_pose(0).origin==marker.position,"approaching immediately samples latest markers without rest reset")
	marker.position=Vector3(.7,.9,-.8);rig._process(1./60.)
	_check(rig.sync_calls==3 and skeleton.get_bone_pose(0).origin==marker.position,"near pose updates on every automatic frame")
	actor.position=Vector3(0.,0.,-200.);rig._web_visual_lod.last_sync_usec=Time.get_ticks_usec()
	marker.position=Vector3(-.9,.3,.1)
	rig.sync_pose()
	_check(rig.sync_calls==4 and skeleton.get_bone_pose(0).origin==marker.position,"explicit contact sync bypasses a remote budget")
	rig._process(1./60.)
	_check(rig.sync_calls==4,"automatic update reuses a fresh explicit sync at distance")
	visual.visible=false;var hidden_pose:=skeleton.get_bone_pose(0)
	marker.position=Vector3(.1,.4,.9);rig._process(1./60.)
	_check(skeleton.get_bone_pose(0)==hidden_pose,"hidden display keeps current stored pose while skipped")
	visual.visible=true;actor.position=Vector3(0.,0.,-20.)
	rig._process(1./60.)
	_check(rig.sync_calls==5 and skeleton.get_bone_pose(0).origin==marker.position,"becoming visible upgrades immediately to current pose")
	_check(not rig.is_processing(),"scheduler never re-enables externally disabled processing")
	_check(actor.velocity==original_velocity and actor.collision_layer==4 and actor.collision_mask==37 and capsule.shape is CapsuleShape3D,"actor velocity and capsule collision configuration remain untouched")
	_check(Engine.physics_ticks_per_second==physics_hz,"scheduler never changes physics frequency")
	var state: Dictionary=rig.web_visual_lod_snapshot()
	rig.add_to_group("web_human_visual_rigs")
	var profiler:=load("res://scripts/web_runtime_profile.gd").new() as Node
	world.add_child(profiler);profiler.set_process(false)
	var window: Dictionary=profiler._human_visual_window()
	_check(window.rigs==1 and window.processing_rigs==0 and window.syncs==5 and window.skips==3,"actual profiler aggregates active group and cumulative scheduler work")
	var next_window: Dictionary=profiler._human_visual_window()
	_check(next_window.syncs==0 and next_window.skips==0,"consecutive profiler windows do not double count sync work")
	var result:={"task":"WEB_HUMAN_VISUAL_LOD","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"fixture_syncs":rig.sync_calls,"visual_lod":state,"engine":Engine.get_version_info().string,"scope":"Uses production rig _process scheduling with one actual Skeleton3D bone and a fixture resolver reading the latest marker. Checks skip retention, distance/visibility resume, immediate direct sync and preserved externally disabled processing/collision settings. Does not validate anatomical posing, rendered motion quality, full game physics or browser FPS."}
	print("WEB_HUMAN_VISUAL_LOD_CHECK ",JSON.stringify(result))
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		var file:=FileAccess.open(args[0],FileAccess.WRITE)
		if file==null:push_error("Could not save visual LOD check");quit(1);return
		file.store_string(JSON.stringify(result,"  ")+"\n");file.close()
	world.free()
	quit(0 if failures.is_empty() else 1)

func _check(passed: bool,message: String) -> void:
	checks+=1
	if not passed:failures.append(message)
