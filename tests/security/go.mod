module easychat/tests/security

go 1.22.0

require (
	nearby/backend/services/gateway v0.0.0
	nearby/backend/shared v0.0.0
)

replace (
	nearby/backend/services/gateway => ../../apps/backend/services/gateway
	nearby/backend/shared => ../../apps/backend/shared
)
