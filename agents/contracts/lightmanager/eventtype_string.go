// Code generated by "stringer -type=EventType"; DO NOT EDIT.

package lightmanager

import "strconv"

func _() {
	// An "invalid array index" compiler error signifies that the constant values have changed.
	// Re-run the stringer command to generate them again.
	var x [1]struct{}
	_ = x[DisputeOpenedEvent-0]
	_ = x[RootUpdatedEvent-1]
}

const _EventType_name = "DisputeOpenedEventRootUpdatedEvent"

var _EventType_index = [...]uint8{0, 18, 34}

func (i EventType) String() string {
	if i >= EventType(len(_EventType_index)-1) {
		return "EventType(" + strconv.FormatInt(int64(i), 10) + ")"
	}
	return _EventType_name[_EventType_index[i]:_EventType_index[i+1]]
}