extends "res://scripts/traffic/vehicle.gd"
## Only initial placement is offset; subsequent motion/recycling uses the N03 controller.
var initial_station_m := 0.0

func _ready() -> void:
	super._ready()
	if not _configured or initial_station_m<=0.0:return
	_station_m=clampf(initial_station_m,0.0,_length_m-12.0)
	_segment=0
	while _segment<_points.size()-2 and _arc[_segment+1]<_station_m:_segment+=1
	var span: float=_arc[_segment+1]-_arc[_segment]
	global_position=_points[_segment].lerp(_points[_segment+1],(_station_m-_arc[_segment])/span)
	global_rotation.y=_heading(_segment_direction(_segment))
	_find_support()
