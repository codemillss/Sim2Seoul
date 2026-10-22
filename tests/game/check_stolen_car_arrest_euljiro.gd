extends "res://../tests/game/check_stolen_car_arrest.gd"
## Reproduce dev02's actual Euljiro source-car pursuit and formerly missing
## 1.5m public-TIN connection, using the same production integration harness.
func _initialize() -> void:
	region_fixture="euljiro"
	super._initialize()
