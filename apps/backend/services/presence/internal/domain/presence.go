package domain

import (
	"time"
)

type PresenceState string

const (
	StateOnline    PresenceState = "online"
	StateOffline   PresenceState = "offline"
	StateInvisible PresenceState = "invisible"
)

// UserPresence represents the aggregated real-time presence of a user.
type UserPresence struct {
	UserID    string        `json:"user_id"`
	State     PresenceState `json:"state"`
	H3Index   string        `json:"h3_index"`
	LastSeen  time.Time     `json:"last_seen"`
}

// DevicePresence represents a single device connection heartbeat state.
type DevicePresence struct {
	DeviceID  string        `json:"device_id"`
	State     PresenceState `json:"state"`
	H3Index   string        `json:"h3_index"`
	UpdatedAt time.Time     `json:"updated_at"`
}
