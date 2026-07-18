module nearby/backend/services/user

go 1.23.0

require (
	github.com/lib/pq v1.12.3
	nearby/backend/shared v0.0.0
)

require (
	github.com/go-logr/logr v1.4.1 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	go.opentelemetry.io/otel v1.24.0 // indirect
	go.opentelemetry.io/otel/metric v1.24.0 // indirect
	go.opentelemetry.io/otel/sdk v1.24.0 // indirect
	go.opentelemetry.io/otel/trace v1.24.0 // indirect
	golang.org/x/sys v0.35.0 // indirect
)

replace nearby/backend/shared => ../../shared
