extends "res://scripts/elevator_cabin.gd"
## Adds authored B1 labels while preserving original above-ground floor indices,
## native cabin/camera/shape and the bounded 28-floor operating-panel geometry.
var game_basement_count:=0
var above_ground_count:=0
var has_roof:=true
var destination_indices: Array[int]=[]
func configure_catalog(floors: int,basements: int,roof: bool) -> void:
	above_ground_count=floors;game_basement_count=basements;has_roof=roof;destination_indices.clear()
	for floor_index: int in range(-game_basement_count,above_ground_count+(1 if has_roof else 0)):destination_indices.append(floor_index)
func configure_floors(count: int) -> void:
	super.configure_floors(count)
	for ordinal: int in range(_floor_buttons.size()):
		var floor_index: int=destination_indices[ordinal] if ordinal<destination_indices.size() else ordinal
		_floor_buttons[ordinal].floor_index=floor_index
		_floor_buttons[ordinal].label.text="B%d"%(-floor_index) if floor_index<0 else "R" if has_roof and floor_index==above_ground_count else str(floor_index+1)
func begin(from_floor: int,target_floor: int,count: int) -> void:
	super.begin(from_floor,target_floor,count)
	roof_index=above_ground_count if has_roof else -999
	update_state("boarding",from_floor,target_floor,float(from_floor),0.,0.,1.,false)
func _destination_text(index: int) -> String:
	return "B%d"%(-index) if index<0 else "옥상" if has_roof and index==above_ground_count else "%d층"%(index+1)
func update_state(phase: String,from_floor: int,target_floor: int,floor_value: float,progress: float,speed: float,door_fraction: float,returning: bool) -> void:
	super.update_state(phase,from_floor,target_floor,floor_value,progress,speed,door_fraction,returning)
	var shown: int=int(round(floor_value))
	if shown<0:
		var direction: String="↑" if target_floor>floor_value+.015 else "↓" if target_floor<floor_value-.015 else ""
		if phase in ["arriving","opening","exit_hold","blocked"]:direction=""
		floor_label.text="%s B%d"%[direction,-shown]
	for row: Dictionary in _floor_buttons:row.mesh.material_override=_materials["teal"] if int(row.get("floor_index",0))==target_floor else _materials["button"]
