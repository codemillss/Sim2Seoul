extends Node3D
## Original synthesized game voices, positioned at actual physical vehicles.
## This node never changes a vehicle's movement, collision or ownership.
const AUDIO_FOLDER:="res://assets/audio/city_vehicles/"
var host: Node3D
var loaded:=false
var load_error:=""
var enabled:=true
var gain:=.75
var bus_name: StringName=&"Master"
var voices: Array[Dictionary]=[]
var _streams: Dictionary={}
var _registered: Dictionary={}
var _clock:=0.
var _discovery_s:=0.
var _rain: AudioStreamPlayer3D
var _water: AudioStreamPlayer3D
var _special_levels:={"rain":-80.,"water":-80.}
var _special_paused:=false

func setup(scene: Node3D) -> bool:
	if loaded or not is_inside_tree():return false
	host=scene;process_mode=Node.PROCESS_MODE_ALWAYS;process_physics_priority=5
	for kind: String in ["engine","diesel","tyres","police_siren","fire_siren","rotor","rain","water","door_air"]:
		if _stream(kind,kind!="door_air")==null:load_error="차량 음향을 읽지 못했습니다: "+kind;return false
	_rain=_player("RainNearListener",_streams.rain,-26.,5.,18.)
	_water=_player("ActualFireWater",_streams.water,-21.,5.,48.)
	_discover();loaded=true
	print("CITY_VEHICLE_AUDIO_READY original_synthesized_sounds=9 positional=true voices=",voices.size())
	return true

func _stream(kind: String,loop: bool) -> AudioStreamWAV:
	if _streams.has(kind):return _streams[kind]
	# The checked-in generator writes a canonical PCM16 mono WAV header.
	# Direct PCM loading also works on a fresh clone before editor import.
	var bytes:=FileAccess.get_file_as_bytes(AUDIO_FOLDER+kind+".wav")
	if bytes.size()<46 or bytes.slice(0,4).get_string_from_ascii()!="RIFF" or bytes.slice(36,40).get_string_from_ascii()!="data" or bytes.decode_u16(20)!=1 or bytes.decode_u16(22)!=1 or bytes.decode_u16(34)!=16:return null
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.stereo=false;stream.mix_rate=bytes.decode_u32(24);stream.data=bytes.slice(44)
	if loop:stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_begin=0;stream.loop_end=stream.data.size()/2
	_streams[kind]=stream;return stream

func _player(title: String,stream: AudioStream,volume: float,unit: float,range_m: float) -> AudioStreamPlayer3D:
	var voice:=AudioStreamPlayer3D.new();voice.name=title;voice.stream=stream;voice.bus=bus_name;voice.volume_db=-80.;voice.max_db=-8.;voice.unit_size=unit;voice.max_distance=range_m;voice.panning_strength=.9;voice.attenuation_model=AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE;voice.doppler_tracking=AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED;voice.attenuation_filter_cutoff_hz=6500.;voice.set_meta("base_volume_db",volume);add_child(voice);return voice

func _add_vehicle(body: CharacterBody3D,kind: String,provider: Node3D) -> void:
	if not is_instance_valid(body) or _registered.has(body.get_instance_id()):return
	_registered[body.get_instance_id()]=true
	var diesel: bool=kind in ["bus","fire"]
	var engine:=_player(kind+"Engine",_streams.diesel if diesel else _streams.rotor if kind=="helicopter" else _streams.engine,-18. if diesel else -17. if kind=="helicopter" else -24.,7. if diesel else 10. if kind=="helicopter" else 4.,110. if kind=="helicopter" else 75.)
	var rolling: AudioStreamPlayer3D
	if kind!="helicopter":rolling=_player(kind+"Tyres",_streams.tyres,-31.,4.,48.)
	var siren: AudioStreamPlayer3D
	if kind in ["fire","police"]:siren=_player(kind+"Siren",_streams.fire_siren if kind=="fire" else _streams.police_siren,-14.,14.,150.)
	var door: AudioStreamPlayer3D
	if kind=="bus":door=_player("BusAirDoor",_streams.door_air,-20.,3.,28.)
	voices.append({"body":body,"kind":kind,"provider":provider,"engine":engine,"rolling":rolling,"siren":siren,"door":door,"last_point":body.global_position,"speed_mps":0.,"engine_active":false,"siren_active":false,"engine_level":-80.,"rolling_level":-80.,"siren_level":-80.,"door_open":false,"occluded":false,"occlusion_s":0.})

func _discover() -> void:
	if is_instance_valid(host.traffic_car_takeover):
		for body: CharacterBody3D in host.traffic_car_takeover.traffic_cars:_add_vehicle(body,"traffic",host.traffic_car_takeover)
	if is_instance_valid(host.drivable_car_service) and not host.drivable_car_service.bikes.is_empty():_add_vehicle(host.drivable_car_service.bikes[0].body,"player_car",host.drivable_car_service)
	if is_instance_valid(host.city_bus_service):
		for body: CharacterBody3D in host.city_bus_service.buses:_add_vehicle(body,"bus",host.city_bus_service)
	if is_instance_valid(host.city_helicopter_service):_add_vehicle(host.city_helicopter_service.body,"helicopter",host.city_helicopter_service)
	if is_instance_valid(host.city_weather_emergency):_add_vehicle(host.city_weather_emergency.engine,"fire",host.city_weather_emergency)
	if is_instance_valid(host.city_public_safety):
		var provider: Node3D=host.city_public_safety.get("patrol_vehicle_service")
		if is_instance_valid(provider):
			var body: CharacterBody3D=provider.get("vehicle")
			if is_instance_valid(body):_add_vehicle(body,"police",provider)

func _state(row: Dictionary,delta: float) -> Dictionary:
	var body: CharacterBody3D=row.body;var provider: Node3D=row.provider
	var travel: float=Vector2(body.global_position.x-row.last_point.x,body.global_position.z-row.last_point.z).length();row.last_point=body.global_position
	var speed: float=travel/maxf(delta,.001) if travel<6. else 0.
	var out:={"speed_mps":speed,"engine_active":speed>.03,"siren_active":false,"door_open":false}
	if String(row.kind) in ["fire","police"] and provider.has_method("audio_state"):
		var state: Dictionary=provider.audio_state();out.merge(state,true)
	elif row.kind=="fire":out.engine_active=provider.fire_state!="ready";out.siren_active=provider.fire_state in ["garage_exit","responding","engine_to_road","engine_to_fire"]
	elif row.kind=="police":out.engine_active=bool(provider.get("emergency_active")) or speed>.03;out.siren_active=bool(provider.get("emergency_active"))
	elif row.kind=="helicopter":out.engine_active=float(provider.rotor_fraction)>.05;out.rotor_fraction=float(provider.rotor_fraction)
	elif row.kind=="player_car":out.engine_active=provider.riding
	elif row.kind=="traffic":
		var original: bool=not provider._seized.has(body.get_instance_id())
		var driven: bool=provider.riding and provider.rental_index>=0 and provider.bikes[provider.rental_index].body==body
		out.engine_active=(original and body._running) or driven or speed>.03
	elif row.kind=="bus":
		out.engine_active=provider.running
		if provider._records.has(body.get_instance_id()):out.door_open=float(provider._records[body.get_instance_id()].get("door_fraction",0.))>.2
	return out

func set_enabled(value: bool) -> void:
	enabled=value
	if not enabled:_silence()
func _silence() -> void:
	for row: Dictionary in voices:
		for key: String in ["engine","rolling","siren","door"]:
			if is_instance_valid(row[key]):row[key].volume_db=-80.;row[key].stop()
		row.engine_level=-80.;row.rolling_level=-80.;row.siren_level=-80.
	_rain.stop();_water.stop();_special_levels={"rain":-80.,"water":-80.}
func set_gain(value: float) -> void:
	gain=clampf(value,0.,1.)
	if gain<=.001:_silence()

func _mix(voice: AudioStreamPlayer3D,current: float,active: bool,volume: float,delta: float,occluded:=false) -> float:
	if not is_instance_valid(voice):return -80.
	var heard: bool=enabled and gain>.001 and active and voice.global_position.distance_to(host.rig.camera.global_position)<voice.max_distance
	var target: float=volume+linear_to_db(maxf(.0001,gain))-(15. if occluded else 0.) if heard else -80.
	var level: float=lerpf(current,target,1.-exp(-delta*12.));voice.volume_db=level;voice.attenuation_filter_cutoff_hz=1800. if occluded else 6500.
	if heard and not voice.playing:voice.play(fposmod(_clock,1.1))
	elif not heard and level< -70.:voice.stop()
	return level

func _physics_process(delta: float) -> void:
	if not loaded:return
	var paused: bool=host.menu.visible or get_tree().paused
	_clock+=0. if paused else delta;_discovery_s+=delta
	if _discovery_s>.5:_discovery_s=0.;_discover()
	for row: Dictionary in voices:
		if not is_instance_valid(row.body):continue
		var body: CharacterBody3D=row.body
		for key: String in ["engine","rolling","siren","door"]:
			if is_instance_valid(row[key]):row[key].global_position=body.global_position+Vector3.UP*1.1;row[key].stream_paused=paused
		if paused:row.last_point=body.global_position;continue
		var state:=_state(row,delta);var speed: float=absf(float(state.speed_mps));row.speed_mps=speed;row.engine_active=bool(state.engine_active);row.siren_active=bool(state.siren_active)
		row.occlusion_s=float(row.occlusion_s)-delta
		if row.occlusion_s<=0. and body.global_position.distance_to(host.rig.camera.global_position)<90.:
			row.occlusion_s=.25
			var ray:=PhysicsRayQueryParameters3D.create(host.rig.camera.global_position,body.global_position+Vector3.UP*1.1,1|32,[host.player.get_rid(),body.get_rid()])
			row.occluded=not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
		row.engine.pitch_scale=lerpf(float(row.engine.pitch_scale),.8+minf(speed,35.)/35.*.85,1.-exp(-delta*5.)) if row.kind!="helicopter" else .65+float(state.get("rotor_fraction",0.))* .5
		row.engine_level=_mix(row.engine,float(row.engine_level),row.engine_active,float(row.engine.get_meta("base_volume_db"))+minf(speed,25.)*.14,delta,row.occluded)
		row.rolling_level=_mix(row.rolling,float(row.rolling_level),speed>.5,-34.+minf(speed,25.)*.25,delta,row.occluded)
		row.siren_level=_mix(row.siren,float(row.siren_level),row.siren_active,-14.,delta,row.occluded)
		if is_instance_valid(row.door) and bool(state.door_open) and not bool(row.door_open) and enabled and gain>.001:
			row.door.volume_db=-20.+linear_to_db(gain);row.door.play()
		row.door_open=bool(state.door_open)
	for voice: AudioStreamPlayer3D in [_rain,_water]:voice.stream_paused=paused
	if paused:return
	var emergency: Node3D=host.city_weather_emergency
	_rain.global_position=host.rig.camera.global_position+Vector3.UP
	var water_state: Dictionary=emergency.audio_state() if emergency.has_method("audio_state") else {}
	_water.global_position=water_state.get("water_point",emergency._site)+Vector3.UP
	_special_levels.rain=_mix(_rain,float(_special_levels.rain),emergency.outdoors and emergency.weather=="rain",-28.+float(emergency.rain_intensity)*3.,delta)
	_special_levels.water=_mix(_water,float(_special_levels.water),bool(water_state.get("water_active",emergency.fire_state=="extinguishing")),-21.,delta)

func snapshot() -> Dictionary:
	var rows: Array=[]
	for row: Dictionary in voices:
		rows.append({"body_id":row.body.get_instance_id(),"body_path":String(row.body.get_path()),"kind":row.kind,"speed_mps":row.speed_mps,"engine_active":row.engine_active,"siren_active":row.siren_active,"engine_playing":row.engine.playing,"engine_paused":row.engine.stream_paused,"engine_db":row.engine.volume_db,"engine_pitch":row.engine.pitch_scale,"siren_playing":row.siren.playing if is_instance_valid(row.siren) else false,"siren_db":row.siren.volume_db if is_instance_valid(row.siren) else -80.,"occluded":row.occluded})
	return {"loaded":loaded,"error":load_error,"enabled":enabled,"gain":gain,"positional_voices":voices.size(),"assets":_streams.size(),"rows":rows,"rain_playing":_rain.playing,"water_playing":_water.playing,"scope":"Original synthesized game sounds at actual physical vehicles, distance/pan/wall filtering and menu/mute controls. No recorded emergency-service or real-vehicle acoustic reconstruction claim."}
