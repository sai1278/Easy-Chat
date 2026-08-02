package application

import "time"

// Clock abstracts system wall-clock time to ensure deterministic behavior across timezones and test environments.
type Clock interface {
	Now() time.Time
}

// RealClock returns the current system wall-clock time.
type RealClock struct{}

func (RealClock) Now() time.Time {
	return time.Now()
}

// MockClock returns a fixed or controlled time for deterministic testing.
type MockClock struct {
	Time time.Time
}

func (m MockClock) Now() time.Time {
	return m.Time
}
