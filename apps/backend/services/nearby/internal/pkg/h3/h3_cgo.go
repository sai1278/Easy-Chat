//go:build cgo

package h3

import (
	"strconv"

	"github.com/uber/h3-go/v3"
)

// ToLatLng converts an H3 cell index string to latitude/longitude in degrees using CGO bindings.
func ToLatLng(h3Str string) (float64, float64, error) {
	h3Index := h3.FromString(h3Str)
	if h3Index == 0 {
		// Try parsing as raw hex in case h3.FromString fails
		val, err := strconv.ParseUint(h3Str, 16, 64)
		if err != nil {
			return 0, 0, err
		}
		h3Index = h3.H3Index(val)
	}

	coord := h3.ToGeo(h3Index)
	return coord.Latitude, coord.Longitude, nil
}
