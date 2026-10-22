extends SceneTree
## Captures the production mixer, not `playing` flags. The temporary bus only
## receives selected production voices. Listener/player observer fixtures never
## move a vehicle, officer or firefighter, or shorten a production clock.
var scene: Node3D
var service: Node3D
var listener: AudioListener3D
var capture: AudioEffectCapture
var bus_index:=-1
var bus_name: StringName
var checks: Array=[]
var recordings: Array=[]
var pitch_observations: Array=[]
var hashes: Dictionary={}
var report_path:="/tmp/sim2seoul-city-vehicle-audio.json"
var started:=0
var finished:=false
var native_mix_required:=false
var _routed: Array=[]
var _original_ids: Array=[]
var _fire_start:=Vector3.ZERO
var _police_start:=Vector3.ZERO

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	started=Time.get_ticks_msec();Engine.max_fps=0
	create_timer(240.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_audio_test_timeout",false);_finish()
	)
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:out[str(key)]=_json(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item: Variant in value:out.append(_json(item))
		return out
	if value is float:return value if is_finite(value) else null
	return value

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)});print("VEHICLE_AUDIO_CHECK ",title," ",passed)

func _hashes() -> Dictionary:
	var out: Dictionary={}
	for path: String in ["res://scripts/city_vehicle_audio.gd","res://scripts/explore_walk.gd","res://scripts/city_public_safety.gd","res://scripts/city_police_patrol.gd","res://scripts/city_police_facility.gd","res://scripts/city_weather_emergency.gd","res://scripts/fire_station_facility.gd","res://scripts/traffic_car_takeover.gd","res://scripts/city_bus_service.gd","res://scripts/drivable_car_service.gd","res://scripts/city_helicopter_service.gd","res://assets/authored/fire_station_service.json","res://assets/authored/police_patrol.json","res://assets/authored/police_facility.json","res://assets/authored/neighborhood_population.json","res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://data/generated/terrain_surface.json","res://data/generated/traffic.json","res://../tools/make_city_vehicle_audio.py","res://assets/audio/city_vehicles/provenance.json","res://../tests/game/check_city_vehicle_audio.gd"]:
		if FileAccess.file_exists(path):out[path]=FileAccess.get_sha256(path)
	for kind: String in ["engine","diesel","tyres","police_siren","fire_siren","rotor","rain","water","door_air"]:
		var path: String="res://assets/audio/city_vehicles/"+kind+".wav";out[path]=FileAccess.get_sha256(path)
	return out

func _ticks(count: int) -> void:
	for i: int in range(count):await physics_frame;await process_frame

func _ids() -> Array:
	var out: Array=[]
	for body: CharacterBody3D in scene.traffic_car_takeover.traffic_cars:out.append(body.get_instance_id())
	for body: CharacterBody3D in scene.city_bus_service.buses:out.append(body.get_instance_id())
	return out

func _asset_checks() -> void:
	var rows: Array=[];var all_pcm:=true;var all_nonzero:=true;var all_unclipped:=true
	for kind: String in ["engine","diesel","tyres","police_siren","fire_siren","rotor","rain","water","door_air"]:
		var bytes:=FileAccess.get_file_as_bytes("res://assets/audio/city_vehicles/"+kind+".wav")
		var header_ok: bool=bytes.size()>44 and bytes.slice(0,4).get_string_from_ascii()=="RIFF" and bytes.slice(8,12).get_string_from_ascii()=="WAVE" and bytes.slice(12,16).get_string_from_ascii()=="fmt " and bytes.decode_u32(16)==16 and bytes.decode_u16(20)==1 and bytes.decode_u16(22)==1 and bytes.decode_u32(24)==22050 and bytes.decode_u16(34)==16 and bytes.slice(36,40).get_string_from_ascii()=="data" and bytes.decode_u32(40)==bytes.size()-44
		var sum_sq:=0.;var peak:=0.;var count: int=maxi(0,(bytes.size()-44)/2)
		for i: int in range(count):
			var sample:=float(bytes.decode_s16(44+i*2))/32768.;sum_sq+=sample*sample;peak=maxf(peak,absf(sample))
		var rms:=sqrt(sum_sq/maxi(1,count));all_pcm=all_pcm and header_ok;all_nonzero=all_nonzero and rms>.005;all_unclipped=all_unclipped and peak<.95
		rows.append({"kind":kind,"pcm16_mono_22050":header_ok,"samples":count,"rms":rms,"peak":peak,"sha256":FileAccess.get_sha256("res://assets/audio/city_vehicles/"+kind+".wav")})
	_check("nine_original_assets_have_canonical_pcm16_mono_22050_headers",all_pcm,{"assets":rows})
	_check("all_nine_source_signals_are_nonzero_and_unclipped",all_nonzero and all_unclipped,{"source_only_not_mixer_acceptance":true})
	_check("fire_and_police_sirens_are_different_original_signals",FileAccess.get_sha256("res://assets/audio/city_vehicles/fire_siren.wav")!=FileAccess.get_sha256("res://assets/audio/city_vehicles/police_siren.wav"))

func _make_capture_bus() -> void:
	bus_index=AudioServer.bus_count;AudioServer.add_bus(bus_index);bus_name=StringName("EXP27AudioProof"+str(OS.get_process_id()));AudioServer.set_bus_name(bus_index,bus_name)
	capture=AudioEffectCapture.new();capture.buffer_length=8.;AudioServer.add_bus_effect(bus_index,capture)
	listener=AudioListener3D.new();listener.name="TestOnlyAudioProofListener";scene.add_child(listener);listener.make_current()

func _restore_routes() -> void:
	for row: Dictionary in _routed:
		if is_instance_valid(row.voice):row.voice.bus=row.bus
	_routed.clear()

func _isolate(voice: AudioStreamPlayer3D) -> void:
	_restore_routes();_routed.append({"voice":voice,"bus":voice.bus});voice.bus=bus_name

func _voice(kind: String) -> Dictionary:
	var best: Dictionary={};var distance:=INF
	for row: Dictionary in service.voices:
		if String(row.kind)!=kind:continue
		var now: float=row.body.global_position.distance_to(scene.rig.camera.global_position)
		if now<distance:best=row;distance=now
	return best

func _write_wav(path: String,frames: PackedVector2Array) -> Error:
	var pcm:=PackedByteArray();pcm.resize(frames.size()*4)
	for i: int in range(frames.size()):
		pcm.encode_s16(i*4,int(round(clampf(frames[i].x,-1.,1.)*32767.)));pcm.encode_s16(i*4+2,int(round(clampf(frames[i].y,-1.,1.)*32767.)))
	var header:=PackedByteArray();header.resize(44)
	for pair: Array in [[0,"RIFF"],[8,"WAVE"],[12,"fmt "],[36,"data"]]:
		var bytes: PackedByteArray=String(pair[1]).to_ascii_buffer()
		for j: int in range(4):header[int(pair[0])+j]=bytes[j]
	header.encode_u32(4,36+pcm.size());header.encode_u32(16,16);header.encode_u16(20,1);header.encode_u16(22,2);header.encode_u32(24,int(AudioServer.get_mix_rate()));header.encode_u32(28,int(AudioServer.get_mix_rate())*4);header.encode_u16(32,4);header.encode_u16(34,16);header.encode_u32(40,pcm.size())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_buffer(header);file.store_buffer(pcm);file.close();return OK

func _observe_pitch() -> void:
	var row:=_voice("fire")
	if row.is_empty():return
	pitch_observations.append({"speed_mps":float(row.speed_mps),"pitch_scale":float(row.engine.pitch_scale),"position":row.body.global_position,"fire_state":scene.city_weather_emergency.fire_state})

func _stream_source(voice: AudioStreamPlayer3D) -> String:
	for kind: String in service._streams:
		if service._streams[kind]==voice.stream:return "res://assets/audio/city_vehicles/"+kind+".wav"
	return ""

func _record(title: String,voice: AudioStreamPlayer3D,target: Node3D,offset: Vector3,ticks:=20) -> Dictionary:
	_isolate(voice)
	# Let prior voice/mixer blocks settle, then discard every old frame.
	for i: int in range(8):listener.global_transform=Transform3D(Basis.IDENTITY,target.global_position+offset);await _ticks(1);_observe_pitch()
	capture.clear_buffer();var frames:=PackedVector2Array();var start_point: Vector3=target.global_position;var positions: Array=[]
	var position_before: float=voice.get_playback_position()
	for i: int in range(ticks):
		listener.global_transform=Transform3D(Basis.IDENTITY,target.global_position+offset);await _ticks(1);_observe_pitch()
		positions.append({"target":target.global_position,"listener":listener.global_position})
		var available: int=capture.get_frames_available()
		if available>0:frames.append_array(capture.get_buffer(available))
	var left:=0.;var right:=0.;var peak:=0.;var clips:=0
	for frame: Vector2 in frames:
		left+=frame.x*frame.x;right+=frame.y*frame.y;peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)))
		if maxf(absf(frame.x),absf(frame.y))>=.999:clips+=1
	var path:=report_path.get_basename()+"_"+title+".wav";var error:=_write_wav(path,frames)
	var stream_path:=_stream_source(voice)
	var result: Dictionary={"name":title,"path":path,"sha256":FileAccess.get_sha256(path) if error==OK else "","frames":frames.size(),"mix_rate_hz":AudioServer.get_mix_rate(),"rms_left":sqrt(left/maxi(1,frames.size())),"rms_right":sqrt(right/maxi(1,frames.size())),"peak":peak,"clipped_frames":clips,"write_error":error,"production_voice_path":String(voice.get_path()),"production_stream_path":stream_path,"production_stream_sha256":FileAccess.get_sha256(stream_path) if not stream_path.is_empty() else "","listener_fixture":"Identity-basis listener follows actual source with disclosed offset; no actor movement fixture.","listener_offset":offset,"actual_target_travel_m":target.global_position.distance_to(start_point),"positions":positions,"playback_before_s":position_before,"playback_after_s":voice.get_playback_position(),"bus_isolation":"Only this production AudioStreamPlayer3D is rerouted. Master, buskers and other voices stay unchanged."}
	recordings.append(_json(result));print("VEHICLE_AUDIO_RECORD ",title," frames=",frames.size()," rms=",result.rms_left,"/",result.rms_right);return result

func _audible(row: Dictionary) -> bool:
	return int(row.frames)>=512 and float(row.peak)<.99 and maxi(0,int(row.clipped_frames))==0 and maxf(float(row.rms_left),float(row.rms_right))>.00001

func _quiet(row: Dictionary) -> bool:
	return int(row.frames)>=512 and float(row.peak)<.0000001 and float(row.rms_left)<.0000001 and float(row.rms_right)<.0000001

func _police_observer_away_from_officers(body: CharacterBody3D) -> bool:
	for offset: Vector3 in [Vector3(45,0,0),Vector3(-45,0,0),Vector3(0,0,45),Vector3(0,0,-45),Vector3(32,0,32),Vector3(-32,0,-32)]:
		var safe: Dictionary=scene.interior_visit._safe_external_point(body.global_position+offset)
		if safe.is_empty():continue
		var far:=true
		for officer: Dictionary in scene.city_public_safety.officers:far=far and officer.body.global_position.distance_to(safe.point)>22.
		if not far or not scene._commit_exploration_teleport(safe.point):continue
		scene.rig.snap_to_target_pose();await _ticks(3);return true
	return false

func _run() -> void:
	hashes=_hashes();_asset_checks()
	var settings:="/tmp/city-audio-test-"+str(OS.get_process_id())+".json";var file:=FileAccess.open(settings,FileAccess.WRITE);file.store_string(JSON.stringify({"schema_version":1,"speed_id":"realistic","free_roam":true}));file.close()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=settings;scene.quality_settings_path=settings+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(10);service=scene.get("city_vehicle_audio")
	_check("whole_production_scene_and_original_sound_service_loaded",scene.runtime_ok and is_instance_valid(service) and service.loaded,{"scene_error":scene.exploration_error,"audio_error":service.load_error if is_instance_valid(service) else "service missing"})
	if not scene.runtime_ok or not is_instance_valid(service) or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	var sound_switch: CheckButton=scene.find_child("VehicleSound",true,false);var volume: HSlider=scene.find_child("VehicleVolume",true,false)
	_check("ordinary_menu_sound_switch_and_gain_slider_are_present",is_instance_valid(sound_switch) and is_instance_valid(volume) and volume.min_value==0. and volume.max_value==100.)
	if not is_instance_valid(sound_switch) or not is_instance_valid(volume):_finish();return
	_original_ids=_ids();var counts: Dictionary={};var body_ids: Dictionary={};var bound_ids: Array=[];var expected_ids: Array=_original_ids.duplicate()
	for body: CharacterBody3D in [scene.drivable_car_service.bikes[0].body,scene.city_helicopter_service.body,scene.city_weather_emergency.engine,scene.city_public_safety.patrol_vehicle_service.vehicle]:expected_ids.append(body.get_instance_id())
	for row: Dictionary in service.voices:counts[row.kind]=int(counts.get(row.kind,0))+1;body_ids[row.body.get_instance_id()]=true;bound_ids.append(row.body.get_instance_id())
	bound_ids.sort();expected_ids.sort()
	_check("twenty_one_unique_actual_vehicle_bodies_bound_without_clones",service.voices.size()==21 and body_ids.size()==21 and bound_ids==expected_ids and counts.get("traffic",0)==14 and counts.get("bus",0)==3 and counts.get("player_car",0)==1 and counts.get("helicopter",0)==1 and counts.get("fire",0)==1 and counts.get("police",0)==1,{"counts":counts,"exact_expected_body_ids":expected_ids,"exact_bound_body_ids":bound_ids,"audio_snapshot":service.snapshot()})
	_make_capture_bus()
	if DisplayServer.get_name()=="headless":
		native_mix_required=true;_check("native_stereo_mixer_required_headless_cannot_claim_audibility",false,{"display":DisplayServer.get_name(),"device":AudioServer.get_output_device(),"reason":"Headless preparation validates assets and production binding only. No zero-signal or playing-flag audibility pass."});_finish();return
	sound_switch.set_pressed(true);volume.value=75.
	scene._visit_city_life("traffic_car");await _ticks(5);var car:=_voice("traffic")
	_check("ordinary_menu_destination_reaches_actual_original_traffic_audio",not car.is_empty() and car.body.global_position.distance_to(scene.rig.camera.global_position)<50.)
	if car.is_empty():_finish();return
	var left:=await _record("traffic_engine_source_left",car.engine,car.body,Vector3(6.,1.1,0))
	var right:=await _record("traffic_engine_source_right",car.engine,car.body,Vector3(-6.,1.1,0))
	_check("real_traffic_engine_stereo_pcm_is_audible_unclipped",_audible(left) and _audible(right),{"left":left,"right":right})
	_check("three_dimensional_listener_left_right_panning_reverses_actual_mix",float(left.rms_left)>float(left.rms_right)*1.15 and float(right.rms_right)>float(right.rms_left)*1.15,{"left_ratio":float(left.rms_left)/maxf(.00000001,float(left.rms_right)),"right_ratio":float(right.rms_right)/maxf(.00000001,float(right.rms_left)),"no_vehicle_warp":true})
	var master_index:=AudioServer.get_bus_index(&"Master");var master_before:=AudioServer.is_bus_mute(master_index);var guitar_bus: StringName=scene.neighborhood_life.audio.bus
	sound_switch.set_pressed(false);var muted:=await _record("vehicle_service_muted",car.engine,car.body,Vector3(-6.,1.1,0),12)
	_check("vehicle_mute_stops_real_mixer_signal_without_muting_master_or_busker",_quiet(muted) and not service.enabled and AudioServer.is_bus_mute(master_index)==master_before and scene.neighborhood_life.audio.bus==guitar_bus,{"record":muted,"master_mute":master_before,"busker_bus":guitar_bus,"input_fixture":"Actual VehicleSound toggled signal; OS click remains separate."})
	sound_switch.set_pressed(true);volume.value=0.;var zero_gain:=await _record("vehicle_volume_slider_zero",car.engine,car.body,Vector3(-6.,1.1,0),12)
	_check("actual_volume_slider_zero_silences_all_service_voices_and_stereo_mix",service.gain==0. and service.enabled and _quiet(zero_gain) and service.voices.all(func(row: Dictionary)->bool:return not row.engine.playing and (not is_instance_valid(row.siren) or not row.siren.playing) and (not is_instance_valid(row.rolling) or not row.rolling.playing) and (not is_instance_valid(row.door) or not row.door.playing)) and not service._rain.playing and not service._water.playing and AudioServer.is_bus_mute(master_index)==master_before and scene.neighborhood_life.audio.bus==guitar_bus,{"record":zero_gain,"input_fixture":"Actual VehicleVolume value_changed signal, no Master/busker mutation."})
	volume.value=75.;await _ticks(12);scene.toggle_menu();await _ticks(8);var pause_before: float=car.engine.get_playback_position();var paused:=await _record("ordinary_menu_pauses_vehicle_stream",car.engine,car.body,Vector3(-6.,1.1,0),12)
	_check("ordinary_menu_pauses_audio_clock_and_real_stereo_mix",_quiet(paused) and car.engine.stream_paused and absf(car.engine.get_playback_position()-pause_before)<.03,{"record":paused,"position_before_menu":pause_before});scene.toggle_menu()
	var resumed:=await _record("traffic_engine_resumed_after_menu",car.engine,car.body,Vector3(-6.,1.1,0),12)
	_check("closing_menu_restores_actual_audio_without_manual_replay",_audible(resumed) and not car.engine.stream_paused,{"record":resumed})
	_restore_routes();scene._visit_city_life("fire_demo");await _ticks(3);var fire:=_voice("fire");_fire_start=fire.body.global_position
	_check("ordinary_fire_demo_starts_production_dispatch_and_siren_state",scene.city_weather_emergency.fire_state=="dispatch" and bool(scene.city_weather_emergency.audio_state().siren_active),{"fire_state":scene.city_weather_emergency.fire_state,"timer_policy":scene.city_weather_emergency.policy})
	var fire_siren:=await _record("actual_dispatch_fire_siren",fire.siren,fire.body,Vector3(6.,1.1,0),25)
	_check("actual_moving_fireengine_emits_distinct_audible_siren_pcm",_audible(fire_siren) and fire.body.global_position.distance_to(_fire_start)>.1,{"record":fire_siren,"engine_distance_m":scene.city_weather_emergency.engine_distance_m})
	var diesel:=await _record("actual_fireengine_diesel",fire.engine,fire.body,Vector3(-6.,1.1,0),20)
	_check("actual_fireengine_diesel_is_audible_and_unclipped",_audible(diesel),{"record":diesel})
	var rain:=await _record("actual_outdoor_rain",service._rain,scene.rig.camera,Vector3.ZERO,18)
	_check("actual_outdoor_rain_state_emits_nonzero_pcm",scene.city_weather_emergency.weather=="rain" and scene.city_weather_emergency.outdoors and _audible(rain),{"record":rain})
	var extinguishing:=false
	for tick: int in range(30*100):
		_observe_pitch()
		if scene.city_weather_emergency.fire_state=="extinguishing":extinguishing=true;break
		await _ticks(1)
	_check("fireengine_and_crew_physically_reach_real_water_stage_without_clock_changes",extinguishing,{"snapshot":scene.city_weather_emergency.snapshot()})
	if extinguishing:
		scene._visit_city_life("fire_station");await _ticks(3);var water:=await _record("actual_firefighters_water_spray",service._water,service._water,Vector3(0,0,3.),18)
		_check("actual_firefighter_water_stage_emits_audible_pcm",_audible(water) and bool(scene.city_weather_emergency.audio_state().water_active),{"record":water})
	var min_speed:=INF;var max_speed:=0.;var min_pitch:=INF;var max_pitch:=0.;var source_moved:=false
	for row: Dictionary in pitch_observations:
		min_speed=minf(min_speed,float(row.speed_mps));max_speed=maxf(max_speed,float(row.speed_mps));min_pitch=minf(min_pitch,float(row.pitch_scale));max_pitch=maxf(max_pitch,float(row.pitch_scale));source_moved=source_moved or Vector3(row.position).distance_to(_fire_start)>.5
	_check("engine_pitch_changes_with_real_native_fireengine_speed",source_moved and max_speed-min_speed>.3 and max_pitch-min_pitch>.01,{"min_speed_mps":min_speed,"max_speed_mps":max_speed,"min_pitch":min_pitch,"max_pitch":max_pitch,"observations":pitch_observations})
	_restore_routes();scene._visit_city_life("police_post");await _ticks(3);var police:=_voice("police")
	_check("actual_police_car_is_bound_to_separate_siren_voice",not police.is_empty() and is_instance_valid(police.siren))
	if not police.is_empty():
		var observer_ok:=await _police_observer_away_from_officers(police.body);_police_start=police.body.global_position
		_check("supported_player_only_police_observer_fixture_keeps_approach_time",observer_ok,{"player":scene.player.global_position,"vehicle":police.body.global_position,"fixture":"Direct offense report below is a dispatch fixture, not a user F/theft integration claim."})
		if observer_ok:
			scene.city_public_safety.report_offense("audio_test_direct_dispatch_fixture",scene.player.global_position);await _ticks(3)
			var siren:=await _record("actual_dispatch_police_siren",police.siren,police.body,Vector3(-6.,1.1,0),25)
			_check("actual_police_dispatch_emits_audible_siren_while_native_vehicle_moves",_audible(siren) and police.body.global_position.distance_to(_police_start)>.1 and bool(police.provider.audio_state().siren_active),{"record":siren,"vehicle_state":police.provider.snapshot() if police.provider.has_method("snapshot") else {}})
	_check("original_fourteen_car_and_three_bus_identities_retained",_ids()==_original_ids,{"original_count":_original_ids.size()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;_restore_routes();_check("all_audio_and_game_inputs_stable_during_run",hashes==_hashes() and not hashes.values().has(""),{"start":hashes,"end":_hashes()})
	var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size();var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(_json({"task":"EXP27_VEHICLE_AUDIO_MIX","result":"NATIVE_AUDIO_REQUIRED" if native_mix_required else "PASS" if passed==checks.size() else "FAIL","passed":passed,"total":checks.size(),"checks":checks,"recordings":recordings,"source_hashes":hashes,"snapshot":service.snapshot() if is_instance_valid(service) else {},"physics_hz":Engine.physics_ticks_per_second,"display":DisplayServer.get_name(),"output_device":AudioServer.get_output_device(),"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Original source signal audit plus actual production 3D mixer PCM captured to a temporary isolated proof bus. Supported player observer and identity-basis audio listener fixtures only; direct police offense report is disclosed. No vehicle/officer warp, shortened response clock, speaker acoustic measurement, actual Korean siren reconstruction, OS-keyboard, human comfort or sustained FPS claim. Headless zero signals never count as audible acceptance."}),"  "));file.close()
	if is_instance_valid(scene):
		if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
		if is_instance_valid(service):service.set_enabled(false)
		await physics_frame;await physics_frame;scene.queue_free();await process_frame;await process_frame
	if bus_index>=0:AudioServer.remove_bus(bus_index)
	print("VEHICLE_AUDIO_RESULT ",passed,"/",checks.size()," native_required=",native_mix_required);quit(0 if passed==checks.size() else 3 if native_mix_required else 1)
