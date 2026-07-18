module nearby/backend/services/gateway

go 1.23

require (
	github.com/golang-jwt/jwt/v5 v5.2.1
	github.com/google/uuid v1.6.0
	github.com/patrickmn/go-cache v2.1.0+incompatible
	golang.org/x/time v0.15.0
	nearby/backend/shared v0.0.0
)

replace nearby/backend/shared => ../../shared
