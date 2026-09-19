class_name RepairState
extends RefCounted

## Repair pipeline states and valid transition rules for device progression.
## RECEIVED -> DIAGNOSED -> DISASSEMBLED -> PART_REPLACED -> REASSEMBLED -> SOFTWARE_INSTALLED -> TESTED -> DELIVERED

enum State {
	RECEIVED,           # Device picked up from reception
	DIAGNOSED,          # Fault identified at diagnostic bench
	DISASSEMBLED,       # Opened up at workbench
	PART_REPLACED,      # Broken part swapped with new one
	REASSEMBLED,        # Closed back up
	SOFTWARE_INSTALLED, # OS/drivers installed at software station
	TESTED,             # Final test passed — ready to deliver
	DELIVERED,          # Handed back to customer
}

const TRANSITIONS: Dictionary = {
	State.RECEIVED:           [State.DIAGNOSED],
	State.DIAGNOSED:          [State.DISASSEMBLED],
	State.DISASSEMBLED:       [State.PART_REPLACED],
	State.PART_REPLACED:      [State.REASSEMBLED],
	State.REASSEMBLED:        [State.SOFTWARE_INSTALLED],
	State.SOFTWARE_INSTALLED: [State.TESTED],
	State.TESTED:             [State.DELIVERED],
	State.DELIVERED:          [],
}


## Returns whether transitioning from one state to another is allowed,
## optionally skipping intermediate states if they are in skip_states.
static func can_transition(from: State, to: State, skip_states: Array[String] = []) -> bool:
	if from in TRANSITIONS:
		if to in TRANSITIONS[from]:
			return true
		if not skip_states.is_empty():
			var curr: State = from
			while curr in TRANSITIONS and not TRANSITIONS[curr].is_empty():
				var next_state: State = TRANSITIONS[curr][0]
				if next_state == to:
					return true
				if to_string_name(next_state) in skip_states:
					curr = next_state
				else:
					break
	return false


## Returns string representation of given State enum
static func to_string_name(state: State) -> String:
	match state:
		State.RECEIVED:
			return "RECEIVED"
		State.DIAGNOSED:
			return "DIAGNOSED"
		State.DISASSEMBLED:
			return "DISASSEMBLED"
		State.PART_REPLACED:
			return "PART_REPLACED"
		State.REASSEMBLED:
			return "REASSEMBLED"
		State.SOFTWARE_INSTALLED:
			return "SOFTWARE_INSTALLED"
		State.TESTED:
			return "TESTED"
		State.DELIVERED:
			return "DELIVERED"
		_:
			return "UNKNOWN"


## Returns State enum from its string representation
static func from_string_name(name_str: String) -> State:
	match name_str.to_upper():
		"RECEIVED":
			return State.RECEIVED
		"DIAGNOSED":
			return State.DIAGNOSED
		"DISASSEMBLED":
			return State.DISASSEMBLED
		"PART_REPLACED":
			return State.PART_REPLACED
		"REASSEMBLED":
			return State.REASSEMBLED
		"SOFTWARE_INSTALLED":
			return State.SOFTWARE_INSTALLED
		"TESTED":
			return State.TESTED
		"DELIVERED":
			return State.DELIVERED
		_:
			return State.RECEIVED


## Returns the station type responsible for processing the given state
static func get_required_station(state: State) -> String:
	match state:
		State.RECEIVED:
			return "diagnostic_bench"
		State.DIAGNOSED:
			return "workbench"
		State.DISASSEMBLED:
			return "workbench"
		State.PART_REPLACED:
			return "workbench"
		State.REASSEMBLED:
			return "software_station"
		State.SOFTWARE_INSTALLED:
			return "software_station"
		State.TESTED:
			return "delivery_counter"
		_:
			return ""
