module nearby/backend/services/auth

go 1.25.0

require (
	github.com/golang-jwt/jwt/v5 v5.2.1
	github.com/google/uuid v1.6.0
	github.com/lib/pq v1.12.3
	github.com/redis/go-redis/v9 v9.21.0
	golang.org/x/crypto v0.55.0
	nearby/backend/shared v0.0.0
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/go-logr/logr v1.4.3 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	go.opentelemetry.io/auto/sdk v1.2.1 // indirect
	go.opentelemetry.io/otel v1.43.0 // indirect
	go.opentelemetry.io/otel/metric v1.43.0 // indirect
	go.opentelemetry.io/otel/sdk v1.43.0 // indirect
	go.opentelemetry.io/otel/trace v1.43.0 // indirect
	go.uber.org/atomic v1.11.0 // indirect
	golang.org/x/sys v0.47.0 // indirect
)

replace nearby/backend/shared => ../../shared
