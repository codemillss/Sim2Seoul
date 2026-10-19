extends RefCounted
## Authored medium companion dog, metres. Visual articulation only: the host
## retains all physical movement, safety sweeps, route stations and collision.
const STRIDE_M := .64
const STANCE := .63
const PAW_Y := .034
var head: Node3D
var neck: Node3D
var tail: Node3D
var collar: Node3D
var legs: Array[Dictionary]=[]
var phase := 0.0
var head_pitch := 0.0
var head_yaw := 0.0
var maximum_stance_drift_m := 0.0
var planted_samples := 0
var swing_samples := 0
var maximum_paw_ground_gap_m := 0.0
var minimum_paw_ground_gap_m := INF
var mesh_count := 0
var _visual: Node3D
var _host: Node3D

func _mat(color: Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.94;return material

func _mesh(parent: Node3D,title: String,mesh: Mesh,material: Material,at := Vector3.ZERO) -> MeshInstance3D:
	var part:=MeshInstance3D.new();part.name=title;part.mesh=mesh;part.material_override=material;part.position=at;parent.add_child(part);mesh_count+=1;return part

func _oval(parent: Node3D,title: String,size: Vector3,at: Vector3,material: Material) -> MeshInstance3D:
	var sphere:=SphereMesh.new();sphere.radius=.5;sphere.height=1.;sphere.radial_segments=16;sphere.rings=8
	var part:=_mesh(parent,title,sphere,material,at);part.scale=size;return part

func _bone(parent: Node3D,title: String,length: float,radius: float,material: Material) -> MeshInstance3D:
	var capsule:=CapsuleMesh.new();capsule.radius=radius;capsule.height=length;capsule.radial_segments=10;capsule.rings=4
	return _mesh(parent,title,capsule,material,Vector3(0,-length*.5,0))

func _rings(parent: Node3D,title: String,rings: Array,material: Material) -> MeshInstance3D:
	# Each section is [z, centre_y, half_width, half_height]. The tucked
	# abdomen and tapering muzzle are silhouettes rather than joined balls.
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3]=[];const SIDES := 16
	for section: Array in rings:
		for index: int in range(SIDES):
			var angle:=TAU*index/SIDES;points.append(Vector3(cos(angle)*section[2],section[1]+sin(angle)*section[3],section[0]))
	for ring_index: int in range(rings.size()-1):
		for index: int in range(SIDES):
			var a:=ring_index*SIDES+index;var b:=ring_index*SIDES+(index+1)%SIDES;var c:=a+SIDES;var d:=b+SIDES
			for vertex: int in [a,c,b,b,c,d]:surface.add_vertex(points[vertex])
	for end_index: int in [0,rings.size()-1]:
		var center:=Vector3(0,rings[end_index][1],rings[end_index][0])
		for index: int in range(SIDES):
			var a:=points[end_index*SIDES+index];var b:=points[end_index*SIDES+(index+1)%SIDES]
			for vertex: Vector3 in ([center,b,a] if end_index==0 else [center,a,b]):surface.add_vertex(vertex)
	surface.generate_normals();return _mesh(parent,title,surface.commit(),material)

func _ear(parent: Node3D,side: float,material: Material,inner: Material) -> void:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3]=[Vector3(side*.072,.065,.01),Vector3(side*.138,.075,.025),Vector3(side*.112,.205,.035),Vector3(side*.092,.09,-.045)]
	for index: int in [0,1,2,0,2,3,1,3,2,0,3,1]:surface.add_vertex(points[index])
	surface.generate_normals();_mesh(parent,"FoldedEar",surface.commit(),material)
	var inset:=_oval(parent,"EarInset",Vector3(.027,.079,.015),Vector3(side*.108,.128,-.012),inner);inset.rotation.z=side*-.16

func build(host: Node3D,visual: Node3D,record: Dictionary) -> void:
	_host=host;_visual=visual
	var color:=Color(record.dog_color[0],record.dog_color[1],record.dog_color[2])
	var coat:=_mat(color);var saddle:=_mat(color.darkened(.13));var cream:=_mat(color.lightened(.27));var shadow:=_mat(color.darkened(.34));var black:=_mat(Color(.035,.028,.023));var pink:=_mat(Color(.32,.19,.16));var lead:=_mat(Color(.48,.055,.035));var metal:=_mat(Color(.48,.46,.39))
	_rings(visual,"DogTuckedTorso",[[.30,.36,.075,.09],[.22,.385,.13,.125],[.05,.39,.12,.115],[-.11,.365,.14,.15],[-.26,.37,.105,.135]],coat)
	_oval(visual,"DogWithers",Vector3(.22,.11,.40),Vector3(0,.475,-.025),saddle)
	_oval(visual,"DogBrisket",Vector3(.18,.25,.17),Vector3(0,.345,-.225),cream)
	neck=_oval(visual,"DogNeck",Vector3(.19,.29,.20),Vector3(0,.465,-.275),coat);neck.rotation.x=-.33
	for side: float in [-1.,1.]:
		_oval(visual,"DogShoulder",Vector3(.10,.21,.18),Vector3(side*.105,.36,-.19),coat)
		_oval(visual,"DogHaunch",Vector3(.125,.235,.18),Vector3(side*.105,.345,.205),coat)
	head=Node3D.new();head.name="DogHead";head.position=Vector3(0,.54,-.335);visual.add_child(head)
	_rings(head,"DogSkull",[[.09,.018,.06,.07],[.025,.035,.098,.105],[-.065,.025,.078,.082],[-.105,-.014,.060,.054]],coat)
	_rings(head,"DogTaperedMuzzle",[[-.07,-.018,.063,.052],[-.16,-.033,.049,.039],[-.23,-.031,.039,.031]],cream)
	_oval(head,"DogLowerJaw",Vector3(.073,.041,.14),Vector3(0,-.064,-.142),shadow)
	_oval(head,"DogNose",Vector3(.077,.048,.038),Vector3(0,-.021,-.232),black)
	for side: float in [-1.,1.]:
		_ear(head,side,saddle,pink)
		_oval(head,"DogBrow",Vector3(.064,.037,.036),Vector3(side*.066,.067,-.068),saddle)
		_oval(head,"DogEye",Vector3(.023,.024,.015),Vector3(side*.066,.048,-.086),black)
		_oval(head,"DogEyeGlint",Vector3(.007,.007,.005),Vector3(side*.064,.053,-.094),cream)
	var collar_mesh:=CylinderMesh.new();collar_mesh.top_radius=.106;collar_mesh.bottom_radius=.106;collar_mesh.height=.036;collar_mesh.radial_segments=20
	collar=_mesh(visual,"DogCollar",collar_mesh,lead,Vector3(0,.485,-.274));collar.rotation.x=-.40
	var ring_mesh:=TorusMesh.new();ring_mesh.inner_radius=.010;ring_mesh.outer_radius=.018;ring_mesh.rings=12;ring_mesh.ring_segments=6
	var ring:=_mesh(collar,"LeadRing",ring_mesh,metal,Vector3(0,.029,0));ring.rotation.x=PI*.5
	_oval(collar,"CollarTag",Vector3(.029,.045,.009),Vector3(0,-.055,-.097),metal)
	tail=Node3D.new();tail.name="DogTail";tail.position=Vector3(0,.435,.275);visual.add_child(tail)
	var tail_base:=_oval(tail,"DogTailRoot",Vector3(.064,.072,.17),Vector3(0,.035,.068),coat);tail_base.rotation.x=-.34
	var tail_tip:=_oval(tail,"DogTailTip",Vector3(.046,.052,.18),Vector3(0,.092,.191),cream);tail_tip.rotation.x=-.53
	for front: bool in [true,false]:
		for side: float in [-1.,1.]:
			var joint:=Node3D.new();joint.name=("Front" if front else "Back")+("Left" if side<0 else "Right")+"Leg";joint.position=Vector3(side*.10,.365 if front else .37,-.205 if front else .205);visual.add_child(joint)
			var upper_length:=.22 if front else .225;var lower_length:=.22 if front else .225
			_bone(joint,"UpperLeg",upper_length,.029 if front else .040,coat)
			var knee:=Node3D.new();knee.name="Elbow" if front else "Stifle";knee.position=Vector3(0,-upper_length,0);joint.add_child(knee)
			_bone(knee,"Foreleg" if front else "LowerHindLeg",lower_length,.022 if front else .025,cream)
			_oval(knee,"CarpalJoint" if front else "Hock",Vector3(.048,.061,.054),Vector3(0,-lower_length*.70,0),coat)
			var ankle:=Node3D.new();ankle.name="PawAnchor";knee.add_child(ankle);ankle.position=Vector3(0,-lower_length,0)
			var paw:=_oval(ankle,"DogPaw",Vector3(.074,.064,.115),Vector3(0,0,-.022),cream)
			for toe: int in range(3):_oval(ankle,"Toe",Vector3(.022,.036,.033),Vector3((toe-1)*.021,-.004,-.068),shadow)
			var offset:=0. if front and side<0 else (.50 if front else (.75 if side<0 else .25))
			legs.append({"joint":joint,"knee":knee,"ankle":ankle,"paw":paw,"front":front,"side":side,"upper":upper_length,"lower":lower_length,"phase_offset":offset,"rest":joint.position,"planted":false,"anchor":Vector3.ZERO,"swing_start":Vector3.ZERO,"cycle":0.,"initialized":false})

func reset_support() -> void:
	for leg: Dictionary in legs:leg.initialized=false;leg.planted=false
	maximum_stance_drift_m=0.;minimum_paw_ground_gap_m=INF;maximum_paw_ground_gap_m=0.

func _foot_support(at: Vector3) -> Vector3:
	var sample: Dictionary=_host._ground(at,.8)
	return Vector3(at.x,sample.point.y-.025+PAW_Y,at.z) if not sample.is_empty() else at

func _leg_pose(leg: Dictionary,foot: Vector3) -> void:
	var joint: Node3D=leg.joint;var offset:=foot-joint.position
	var length:=clampf(offset.length(),.06,float(leg.upper)+float(leg.lower)-.001)
	var direction:=offset.normalized();var pole:=Vector3(0,0,1. if leg.front else -1.)
	pole=(pole-direction*pole.dot(direction)).normalized()
	var along: float=(leg.upper*leg.upper-leg.lower*leg.lower+length*length)/(2.*length)
	var knee:=joint.position+direction*along+pole*sqrt(maxf(0.,leg.upper*leg.upper-along*along))
	var ankle:=joint.position+direction*length
	joint.basis=Basis(Quaternion(Vector3.DOWN,(knee-joint.position).normalized()))
	leg.knee.basis=joint.basis.inverse()*Basis(Quaternion(Vector3.DOWN,(ankle-knee).normalized()))
	leg.ankle.basis=(joint.basis*leg.knee.basis).inverse()

func pose(distance: float,delta: float,behaviour: String,clock: float,player_at: Vector3) -> void:
	phase=fmod(phase+distance/STRIDE_M,1.)
	var moving:=distance>.0001
	var target_pitch:=-.95 if behaviour=="sniffing" else (.035*sin(clock*.85) if moving else -.035)
	var toward: Vector3=_visual.to_local(player_at)-head.position
	var target_yaw:=clampf(atan2(-toward.x,-toward.z),-.50,.50) if behaviour=="looking" else sin(clock*.65)*.10
	head_pitch=move_toward(head_pitch,target_pitch,delta*1.45);head_yaw=move_toward(head_yaw,target_yaw,delta*.85)
	head.rotation=Vector3(head_pitch,head_yaw,0)
	var sniff:=clampf(-head_pitch/.95,0.,1.)
	head.position=Vector3(0,.54-sniff*.17,-.335-sniff*.045)
	neck.rotation.x=lerpf(-.33,-.80,sniff);neck.position.y=.465-sniff*.055
	tail.rotation=Vector3(-.12 if behaviour=="looking" else .04,sin(clock*(5.4 if behaviour=="looking" else 3.2))*(.30 if behaviour=="looking" else .12),0)
	for leg: Dictionary in legs:
		var cycle:=fmod(phase+float(leg.phase_offset),1.);var planted:=cycle<STANCE or not moving
		var neutral:=Vector3(float(leg.side)*.10,PAW_Y,(-.205 if leg.front else .205))
		var world_foot: Vector3
		if not leg.initialized:
			leg.anchor=_foot_support(_visual.to_global(neutral+Vector3(0,0,-.20+minf(cycle,STANCE)*STRIDE_M)))
			leg.swing_start=_foot_support(_visual.to_global(neutral+Vector3(0,0,.20)));leg.initialized=true;leg.planted=planted
		if planted:
			if not leg.planted:leg.anchor=_foot_support(leg.ankle.global_position);leg.planted=true
			world_foot=leg.anchor
			# Rotating in place may exhaust a leg's reach. Replant locally with
			# a bounded visible step; never shift the body's transform or route.
			var reach: Vector3=_visual.to_local(world_foot)-leg.rest
			if reach.length()>.435:
				world_foot=world_foot.move_toward(_foot_support(_visual.to_global(neutral)),delta*.45);leg.anchor=world_foot
			planted_samples+=1
		else:
			if leg.planted:leg.swing_start=leg.ankle.global_position;leg.planted=false
			var swing:=clampf((cycle-STANCE)/(1.-STANCE),0.,1.);var eased:=swing*swing*(3.-2.*swing)
			var landing:=_foot_support(_visual.to_global(neutral+Vector3(0,0,-.20)))
			world_foot=(leg.swing_start as Vector3).lerp(landing,eased)+Vector3.UP*sin(swing*PI)*.063
			swing_samples+=1
		var local:=_visual.to_local(world_foot)
		_leg_pose(leg,local)
		var actual: Vector3=leg.ankle.global_position;var floor_at:=_foot_support(actual)
		var gap: float=actual.y-floor_at.y+PAW_Y
		minimum_paw_ground_gap_m=minf(minimum_paw_ground_gap_m,gap);maximum_paw_ground_gap_m=maxf(maximum_paw_ground_gap_m,gap)
		if moving and leg.planted and float(leg.cycle)<STANCE:maximum_stance_drift_m=maxf(maximum_stance_drift_m,actual.distance_to(world_foot))
		leg.cycle=cycle

func snapshot() -> Dictionary:
	return {"model":"authored_articulated_medium_dog","mesh_count":mesh_count,"stride_m":STRIDE_M,"stance_fraction":STANCE,"distance_phase":phase,"head_pitch":head_pitch,"head_yaw":head_yaw,"planted_samples":planted_samples,"swing_samples":swing_samples,"maximum_planted_target_error_m":maximum_stance_drift_m,"paw_center_ground_gap_range_m":[minimum_paw_ground_gap_m,maximum_paw_ground_gap_m],"body_bob_m":0.0,"scope":"Articulated visual dog; retained host physics/corridor safety. Grounded stance and lifted swing, no mesh-driven body movement."}
