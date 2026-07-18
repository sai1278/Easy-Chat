package domain

// UserMetadata represents profile and presence settings stored in Postgres.
type UserMetadata struct {
	UserID    string
	Pseudonym string
	AvatarID  int32
	Status    string
	IsVisible bool
}

// NearbyUser represents a filtered, bucketed user discovered within proximity.
type NearbyUser struct {
	UserID         string
	Pseudonym      string
	AvatarID       int32
	DistanceMeters float64
	DistanceBucket string
}
