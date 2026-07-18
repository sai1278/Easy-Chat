module nearby/backend/services/dr-controller

go 1.22.0

require (
	nearby/backend/shared v0.0.0
	k8s.io/apimachinery v0.29.2
	k8s.io/client-go v0.29.2
)

replace nearby/backend/shared => ../../shared
