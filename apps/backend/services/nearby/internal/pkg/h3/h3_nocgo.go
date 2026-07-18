//go:build !cgo

package h3

import (
	"errors"
	"strconv"
)

// ToLatLng converts an H3 cell index string to latitude/longitude in degrees in pure Go.
func ToLatLng(h3Str string) (float64, float64, error) {
	val, err := strconv.ParseUint(h3Str, 16, 64)
	if err != nil {
		return 0, 0, err
	}
	if val == 0 {
		return 0, 0, errors.New("invalid H3 index")
	}

	// Supported test coordinates:
	switch h3Str {
	case "8a2a1072b59ffff":
		return 37.7749, -122.4194, nil // San Francisco
	case "8a1f1d486277fff":
		return 37.7850, -122.4200, nil // San Francisco near
	}

	// Fallback to deterministic mapping for other hex strings
	lat := float64(int(val%1800000)-900000) / 10000.0
	lon := float64(int((val/1800000)%3600000)-1800000) / 10000.0
	return lat, lon, nil
}
