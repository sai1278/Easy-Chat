package config

import (
	"os"
	"strconv"
)

// BaseConfig contains central database and cluster configuration strings.
type BaseConfig struct {
	Port         int
	DatabaseURL  string
	RedisURL     string
	Environment  string
}

// LoadBaseConfig parses configurations from active environment values.
func LoadBaseConfig() *BaseConfig {
	portVal := os.Getenv("PORT")
	port := 8080
	if portVal != "" {
		if p, err := strconv.Atoi(portVal); err == nil {
			port = p
		}
	}

	env := os.Getenv("ENV")
	if env == "" {
		env = "production"
	}

	return &BaseConfig{
		Port:         port,
		DatabaseURL:  os.Getenv("DATABASE_URL"),
		RedisURL:     os.Getenv("REDIS_URL"),
		Environment:  env,
	}
}
