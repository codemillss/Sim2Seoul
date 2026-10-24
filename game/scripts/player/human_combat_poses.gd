extends RefCounted
## Original game poses, authored in metres in the avatar's +Y-up/-Z-forward
## frame. These are wrist and elbow landmarks, not motion-capture data.
const DURATIONS := {"jab_left":.48,"cross_right":.58,"hook_left":.66,"shove":.68,"punch":.58}
const CONTACT_SECONDS := {"jab_left":.14,"cross_right":.20,"hook_left":.24,"shove":.22,"punch":.20}

static func duration(kind: String) -> float:return float(DURATIONS.get(kind,.4))
static func contact_phase(kind: String) -> float:return float(CONTACT_SECONDS.get(kind,.20))/duration(kind)

static func hand_basis(longitudinal: Vector3,palm_normal: Vector3) -> Basis:
	# Fingers point down the hand's -Y axis in the original mesh. Project the
	# palm normal to prevent wrist roll from silently turning a punch palm-up.
	var y:=-longitudinal.normalized();var z:=(palm_normal-y*palm_normal.dot(y)).normalized()
	return Basis(y.cross(z).normalized(),y,z).orthonormalized()

static func _guard() -> Dictionary:
	return {"pelvis":Vector3(-.012,-.027,.010),"pelvis_rotation":Vector3(0.,-.13,0.),"torso":Vector3(-.035,-.23,-.015),
		"Left":{"wrist":Vector3(-.145,1.445,-.245),"elbow":Vector3(-.31,1.185,-.13),"basis":hand_basis(Vector3(-.08,.98,-.18),Vector3.BACK)},
		"Right":{"wrist":Vector3(.135,1.425,-.215),"elbow":Vector3(.30,1.17,-.06),"basis":hand_basis(Vector3(.10,.98,-.17),Vector3.BACK)},
		"LeftFoot":Vector3(-.125,.12,-.14),"RightFoot":Vector3(.135,.12,.125),"LeftFootYaw":-.12,"RightFootYaw":.20,"fist":1.}

static func sample(kind: String,phase: float,guard_weight:=0.) -> Dictionary:
	var pose:=_guard();var p:=clampf(phase,0.,1.)
	pose["kind"]=kind;pose["phase"]=p
	if kind=="guard":pose["weight"]=clampf(guard_weight,0.,1.);return pose
	if kind=="punch":kind="cross_right"
	var contact:=contact_phase(kind)
	var anticipation:=smoothstep(0.,contact*.58,p)*(1.-smoothstep(contact*.58,contact,p))
	var drive:=smoothstep(contact*.42,contact,p)*(1.-smoothstep(contact+.045,.83,p))
	var settle:=smoothstep(.72,1.,p)
	pose["weight"]=smoothstep(0.,.105,p)*(1.-settle)
	if kind=="jab_left":
		pose.Left.wrist+=Vector3(-.035,.005,.035)*anticipation
		pose.Left.wrist=Vector3(pose.Left.wrist).lerp(Vector3(-.105,1.475,-.535),drive)
		pose.Left.elbow=Vector3(pose.Left.elbow).lerp(Vector3(-.235,1.445,-.285),drive)
		pose.Left.basis=Basis(pose.Left.basis).slerp(hand_basis(Vector3.FORWARD,Vector3.DOWN),drive)
		pose.pelvis+=Vector3(-.008,-.008,-.022)*drive
		pose.pelvis_rotation+=Vector3(0.,-.09*drive,0.)
		pose.torso+=Vector3(-.025,-.13,.018)*drive
	elif kind=="cross_right":
		pose.Right.wrist+=Vector3(.020,-.010,.050)*anticipation
		pose.Right.wrist=Vector3(pose.Right.wrist).lerp(Vector3(-.015,1.465,-.540),drive)
		pose.Right.elbow=Vector3(pose.Right.elbow).lerp(Vector3(.185,1.420,-.285),drive)
		pose.Right.basis=Basis(pose.Right.basis).slerp(hand_basis(Vector3(-.10,0.,-1.),Vector3.DOWN),drive)
		pose.pelvis+=Vector3(-.018,-.015,-.038)*drive
		pose.pelvis_rotation+=Vector3(0.,.38*drive,0.)
		pose.torso+=Vector3(-.055,.65,.025)*drive
		pose.RightFootYaw=lerpf(.20,.42,drive)
	elif kind=="hook_left":
		pose.Left.wrist+=Vector3(-.14,-.025,.015)*anticipation
		pose.Left.elbow=Vector3(pose.Left.elbow).lerp(Vector3(-.27,1.435,-.24),drive)
		# Hook travels on an arc across the target; the forearm remains bent.
		var arc:=smoothstep(contact*.40,contact,p)
		var hook_goal:=Vector3(lerpf(-.37,.105,arc),1.455,-.36-.105*sin(arc*PI*.5))
		pose.Left.wrist=Vector3(pose.Left.wrist).lerp(hook_goal,drive)
		pose.Left.basis=Basis(pose.Left.basis).slerp(hand_basis(Vector3(.75,.0,-.66),Vector3.DOWN),drive)
		pose.pelvis+=Vector3(.012,-.025,-.018)*drive
		pose.pelvis_rotation+=Vector3(0.,-.16*drive,0.)
		pose.torso+=Vector3(-.025,-.42,-.025)*drive
		pose.LeftFootYaw=lerpf(-.12,-.40,drive)
	elif kind=="shove":
		for side: String in ["Left","Right"]:
			var sign_x:=-1. if side=="Left" else 1.
			pose[side].wrist=Vector3(pose[side].wrist).lerp(Vector3(sign_x*.18,1.31,-.50),drive)
			pose[side].elbow=Vector3(pose[side].elbow).lerp(Vector3(sign_x*.29,1.24,-.25),drive)
			pose[side].basis=Basis(pose[side].basis).slerp(hand_basis(Vector3.UP,Vector3.FORWARD),drive)
		pose.pelvis+=Vector3(0.,-.025,-.035)*drive;pose.torso+=Vector3(-.10,0.,0.)*drive;pose.fist=0.
	return pose
