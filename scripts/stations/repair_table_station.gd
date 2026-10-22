class_name RepairTableStation
extends WorkbenchStation

## Dedicated hardware repair station.
## Inherits from WorkbenchStation (Repair Table and Workbench functionality are unified).

func _ready() -> void:
	super._ready()
	station_name = "Repair Table"
	station_type = "repair_table"
	add_to_group("repair_tables")
