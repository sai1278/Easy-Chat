module nearby/backend/services/notification

go 1.24

require nearby/backend/shared v0.0.0

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/klauspost/compress v1.15.9 // indirect
	github.com/pierrec/lz4/v4 v4.1.15 // indirect
	github.com/redis/go-redis/v9 v9.21.0 // indirect
	github.com/segmentio/kafka-go v0.4.51 // indirect
	go.uber.org/atomic v1.11.0 // indirect
)

replace nearby/backend/shared => ../../shared
