extends "res://scripts/city_bike_service.gd"
## Authored electric kickboards use the same native riding, source limits,
## fresh-E dispatcher and capsule handoff as bicycles. Only art and posture
## differ; there is no second movement controller or external rental service.
var maximum_deck_sole_height_error_m:=0.0
var maximum_deck_footprint_error_m:=0.0

func _design_path() -> String:return "res://assets/authored/scooter_service.json"
func _ride_label() -> String:return "전동 킥보드"
func _ride_status_prefix() -> String:return "CITY_SCOOTERS_READY"

func _make_station(record: Dictionary) -> bool:
	if not super._make_station(record):return false
	var station: Dictionary=stations.back()
	var node: Node3D=station.node
	var turquoise:=_mat(Color(.025,.47,.47));var cream:=_mat(Color(.94,.98,.95))
	for name: String in ["RackUpright","RackHoop"]:
		for child: Node in node.get_children():
			if String(child.name).begins_with(name):child.queue_free()
	var plate:=node.get_node_or_null("DockGreenPlate") as MeshInstance3D
	if is_instance_valid(plate):plate.material_override=turquoise
	var panel: Node3D=station.panel
	(panel.get_node("StationHeader") as MeshInstance3D).material_override=turquoise
	for face_name: String in ["Front","Back"]:
		var title:=panel.get_node("StationTitle"+face_name) as Label3D
		title.text="전동 킥보드\nELECTRIC · 게임 체험";title.outline_modulate=Color(.01,.20,.20)
		var help:=panel.get_node("StationHelp"+face_name) as Label3D
		help.text="E · 빌리기 / 반납\n"+String(record.name)
	var icon: Node3D=station.pictogram
	for child: Node in icon.get_children():child.queue_free()
	_box(icon,"ScooterIconBackground",Vector3(.96,.68,.06),Vector3.ZERO,turquoise)
	for face: float in [-1.,1.]:
		for x: float in [-.27,.25]:
			var ring:=TorusMesh.new();ring.inner_radius=.065;ring.outer_radius=.087;ring.rings=20;ring.ring_segments=6
			var wheel:=_mesh(icon,"SignScooterWheel",ring,cream,Vector3(x,-.18,face*.045));wheel.rotation.x=PI*.5
		_tube(icon,"SignScooterDeck",Vector3(-.27,-.10,face*.045),Vector3(.22,-.10,face*.045),.024,cream)
		_tube(icon,"SignScooterStem",Vector3(.25,-.15,face*.045),Vector3(.14,.24,face*.045),.018,cream)
		_tube(icon,"SignScooterGrip",Vector3(.04,.24,face*.045),Vector3(.23,.24,face*.045),.020,cream)
	node.name=String(record.id)
	return true

func _build_bike(row: Dictionary,parent: Node3D) -> void:
	row.body.name="RentalScooter"+str(bikes.size()+1)
	var dark:=_mat(Color(.055,.065,.07));var rubber:=_mat(Color(.022,.026,.030));var silver:=_mat(Color(.52,.59,.61),.7);var turquoise:=_mat(Color(.015,.58,.56));var orange:=_mat(Color(1.,.45,.055));var red:=_mat(Color(.78,.035,.02));var white:=_mat(Color(.96,1.,.93))
	_box(parent,"BatteryDeck",Vector3(.235,.085,.90),Vector3(0,.205,.10),dark)
	_box(parent,"DeckGripPad",Vector3(.218,.012,.80),Vector3(0,.254,.10),rubber)
	for x: float in [-.121,.121]:
		_box(parent,"TurquoiseDeckRail",Vector3(.012,.035,.83),Vector3(x,.215,.10),turquoise)
		for z: float in [-.21,.12,.43]:_box(parent,"DeckSideReflector",Vector3(.016,.025,.07),Vector3(x,.218,z),orange)
	for z: float in [-.22,-.14,-.06,.02,.10,.18,.26,.34,.42]:_box(parent,"DeckTractionRib",Vector3(.20,.005,.007),Vector3(0,.263,z),_mat(Color(.10,.12,.13)))
	for front: bool in [false,true]:
		var assembly:=Node3D.new();assembly.name="Steering" if front else "RearWheelAssembly";assembly.position=Vector3(0,0,-.50 if front else .56);parent.add_child(assembly)
		if front:row.front=assembly
		var wheel:=Node3D.new();wheel.name="FrontWheel" if front else "RearWheel";wheel.position.y=.12;assembly.add_child(wheel);row.wheels.append(wheel)
		for spec: Array in [[.080,.120,rubber],[.050,.077,silver]]:
			var ring:=TorusMesh.new();ring.inner_radius=spec[0];ring.outer_radius=spec[1];ring.rings=28;ring.ring_segments=8
			var mesh:=_mesh(wheel,"Tyre" if spec[2]==rubber else "MotorHubRim",ring,spec[2]);mesh.rotation.z=PI*.5
		_tube(wheel,"MotorHub",Vector3(-.035,0,0),Vector3(.035,0,0),.05,dark)
		for index: int in range(6):
			var angle:=TAU*index/6.;_tube(wheel,"HubSpoke",Vector3(.037,0,0),Vector3(.037,sin(angle)*.075,cos(angle)*.075),.005,turquoise)
		for side: float in [-1.,1.]:_tube(assembly,"FrontFork" if front else "RearAxleStay",Vector3(side*.075,.12,0),Vector3(side*.075,.28,.11 if front else -.13),.014,dark)
		for index: int in range(9):
			var a:=PI*index/9.;var b:=PI*(index+1)/9.;_tube(assembly,"Mudguard",Vector3(0,.12+sin(a)*.14,cos(a)*.14),Vector3(0,.12+sin(b)*.14,cos(b)*.14),.018,dark)
	var steering: Node3D=row.front
	_tube(steering,"LowerStem",Vector3(0,.16,.02),Vector3(0,.52,.10),.038,dark)
	_tube(steering,"TurquoiseStem",Vector3(0,.42,.08),Vector3(0,1.13,.24),.029,turquoise)
	_box(steering,"FoldingLatch",Vector3(.09,.14,.075),Vector3(0,.39,.07),silver)
	_box(steering,"LatchHandle",Vector3(.025,.11,.025),Vector3(.061,.39,.07),orange)
	_tube(steering,"HandleBar",Vector3(-.29,1.15,.24),Vector3(.29,1.15,.24),.023,dark)
	for side: float in [-1.,1.]:
		_tube(steering,"TexturedGrip",Vector3(side*.19,1.15,.24),Vector3(side*.31,1.15,.24),.030,rubber)
		_tube(steering,"BrakeLever",Vector3(side*.23,1.12,.22),Vector3(side*.28,1.10,.16),.010,silver)
	_tube(steering,"BrakeCable",Vector3(-.23,1.11,.21),Vector3(-.06,.40,.045),.005,dark)
	_box(steering,"Throttle",Vector3(.045,.038,.05),Vector3(.16,1.115,.24),orange)
	_box(steering,"SpeedDisplayHousing",Vector3(.092,.027,.10),Vector3(0,1.17,.24),dark)
	_box(steering,"SpeedDisplay",Vector3(.075,.006,.074),Vector3(0,1.187,.24),_mat(Color(.04,.36,.33)))
	var display:=_label(steering,"DisplayDigits","00",Vector3(0,1.193,.24),.0009);display.rotation.x=-PI*.5;display.billboard=BaseMaterial3D.BILLBOARD_DISABLED;display.modulate=Color(.96,1.,.93);display.outline_size=0
	_box(steering,"Headlamp",Vector3(.075,.045,.035),Vector3(0,1.06,.185),white)
	_box(parent,"RearBrakeLamp",Vector3(.08,.035,.025),Vector3(0,.27,.705),red)
	var flag:=_label(steering,"ScooterName","전동 킥보드",Vector3(0,.72,.047),.0017);flag.modulate=Color(.90,1.,.97)
	row.kickstand=_tube(parent,"Kickstand",Vector3(.09,.21,.29),Vector3(.23,.015,.36),.011,silver)
	# The shared wheel/pedal animation hook accepts a harmless empty crank.
	# Scooters have fixed deck feet and never display bicycle pedals.
	var crank:=Node3D.new();crank.name="UnusedPedalAnimationAnchor";parent.add_child(crank);row.crank=crank

func _attach_player(delta: float) -> void:
	if not riding:return
	var body: CharacterBody3D=bikes[rental_index].body
	host.player.global_transform=body.global_transform.translated_local(Vector3(0,.20,-.02));host.player.get_node("Visual").rotation=Vector3.ZERO;host.player.velocity=Vector3.ZERO;host.player.physics_stepped.emit(delta)

func _rider_pose(measure:=true) -> void:
	if not riding:return
	var avatar: Node3D=host.exploration_avatar;avatar.position=Vector3.ZERO;avatar._upper_body.position=Vector3(0,.85,0);avatar._upper_body.rotation=Vector3(-.035,0,0)
	var row: Dictionary=bikes[rental_index];var body: CharacterBody3D=row.body
	for side_name: String in ["Left","Right"]:
		var side: float=-1. if side_name=="Left" else 1.
		var foot:=Vector3(side*.035,.3785-.20,-.10 if side<0 else .17)
		avatar._joints[side_name+"Thigh"].position.x=side*.035
		avatar._leg_pose(side_name,foot)
		var grip: Vector3=row.front.to_global(Vector3(side*.265,1.15,.24));avatar._arm_to(side_name,avatar.to_local(grip))
		if measure:
			maximum_hand_gap_m=maxf(maximum_hand_gap_m,avatar._hands[0 if side<0 else 1].global_position.distance_to(grip))
			var sole: Vector3=avatar._joints[side_name+"Foot"].to_global(Vector3(0,-.1145,-.06));var local: Vector3=body.to_local(sole)
			maximum_deck_sole_height_error_m=maxf(maximum_deck_sole_height_error_m,absf(local.y-.264))
			maximum_deck_footprint_error_m=maxf(maximum_deck_footprint_error_m,maxf(0.,maxf(absf(local.x)+.0775-.1175,maxf(-.35-(local.z-.15),(local.z+.15)-.55))))
	var display:=row.front.get_node_or_null("DisplayDigits") as Label3D
	if is_instance_valid(display):display.text="%02d"%roundi(absf(speed_mps)*3.6)

func snapshot() -> Dictionary:
	var data: Dictionary=super.snapshot()
	for key: String in ["bike_count","bikes","pedal_phase","maximum_pedal_rotation","maximum_pedal_sole_height_error_m"]:data.erase(key)
	data.scooter_count=bikes.size();data.scooters=[]
	for row: Dictionary in bikes:data.scooters.append({"name":row.body.name,"position":row.body.global_position,"on_floor":row.body.is_on_floor(),"rented":row.rented,"station_id":row.station_id,"kickstand_visible":row.kickstand.visible,"distance_m":row.distance_m,"wheel_phase":row.wheel_phase,"source_allowed":_footprint_allowed(row.body.global_position,row.body.global_basis)})
	data.maximum_deck_sole_height_error_m=maximum_deck_sole_height_error_m;data.maximum_deck_footprint_error_m=maximum_deck_footprint_error_m
	data.scope="Authored physical electric kickboard game experience; no real service, inventory, payment or legal riding-access claim. Shared conservative bicycle collision envelope and native source/support protections."
	return data
