// Code generated by "stringer -type=SynapseRequestStatus"; DO NOT EDIT.

package db

import "strconv"

func _() {
	// An "invalid array index" compiler error signifies that the constant values have changed.
	// Re-run the stringer command to generate them again.
	var x [1]struct{}
	_ = x[Seen-1]
	_ = x[Signed-2]
	_ = x[Broadcast-3]
	_ = x[Completed-4]
}

const _SynapseRequestStatus_name = "SeenSignedBroadcastCompleted"

var _SynapseRequestStatus_index = [...]uint8{0, 4, 10, 19, 28}

func (i SynapseRequestStatus) String() string {
	i -= 1
	if i >= SynapseRequestStatus(len(_SynapseRequestStatus_index)-1) {
		return "SynapseRequestStatus(" + strconv.FormatInt(int64(i+1), 10) + ")"
	}
	return _SynapseRequestStatus_name[_SynapseRequestStatus_index[i]:_SynapseRequestStatus_index[i+1]]
}
