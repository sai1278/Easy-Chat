package validation

import (
	"regexp"
)

var (
	// Standard validation patterns
	rxUUID      = regexp.MustCompile("^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$")
	rxPseudonym = regexp.MustCompile("^[a-z]+ [a-z]+$") // Matches "adjective noun" format in lowercase
	rxH3Res10   = regexp.MustCompile("^[8][0-9a-fA-F]{14}$") // Matches standard H3 index format beginning with 8 (Resolution 10)
)

// ValidateUUID asserts formatting of UUID strings.
func ValidateUUID(id string) bool {
	return rxUUID.MatchString(id)
}

// ValidatePseudonym asserts format of system-generated pseudonyms.
func ValidatePseudonym(name string) bool {
	return rxPseudonym.MatchString(name)
}

// ValidateH3Index asserts format of Uber H3 resolution 10 cell string.
func ValidateH3Index(h3 string) bool {
	return rxH3Res10.MatchString(h3)
}

// ValidateRadius restricts options to 100m, 150m, or 200m thresholds.
func ValidateRadius(radius int) bool {
	return radius == 100 || radius == 150 || radius == 200
}
