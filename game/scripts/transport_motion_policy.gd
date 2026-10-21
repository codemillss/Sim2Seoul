extends RefCounted
## Game travel speeds follow the selected on-foot profile. Historical authored
## geometry/support limits remain intact; this is not a real vehicle speed rule.
const RUN_RATIOS:={"bike":1.60,"scooter":2.00,"car":2.50,"bus":1.80,"subway":2.50,"helicopter":4.00}

static func resolve(kind: String,authored: Dictionary,run_speed: float) -> Dictionary:
	var result:=authored.duplicate(true)
	var base: float=float(authored.get("maximum_speed_mps",authored.get("maximum_forward_mps",0.)))
	if not RUN_RATIOS.has(kind) or not is_finite(base) or base<=0. or not is_finite(run_speed) or run_speed<=0.:return result
	var cap:=maxf(base,run_speed*float(RUN_RATIOS[kind]));var gain:=cap/base
	result.maximum_speed_mps=cap
	if authored.has("maximum_forward_mps"):result.maximum_forward_mps=cap
	for key: String in ["acceleration_mps2","coast_deceleration_mps2","braking_mps2","horizontal_acceleration_mps2","horizontal_braking_mps2"]:
		if authored.has(key):result[key]=float(authored[key])*gain
	# Directly controlled arcade rides reach cruise promptly; service-driven
	# bus/rail keep their smooth schedule acceleration and stop safety.
	if kind in ["bike","scooter","car","helicopter"]:
		var acceleration_key:="horizontal_acceleration_mps2" if kind=="helicopter" else "acceleration_mps2"
		result[acceleration_key]=maxf(float(result.get(acceleration_key,0.)),cap/1.8)
		if kind=="helicopter":
			result.ascent_mps=maxf(float(authored.get("ascent_mps",4.)),run_speed*.65)
			result.descent_mps=maxf(float(authored.get("descent_mps",2.5)),run_speed*.45)
			result.vertical_acceleration_mps2=maxf(float(authored.get("vertical_acceleration_mps2",5.)),float(result.ascent_mps)/.8)
	result.on_foot_run_speed_mps=run_speed;result.speed_gain=gain
	return result
