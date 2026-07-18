package config

import (
	"os"
	"strconv"
)

// Config holds all environmental variables for the backend applications.
type Config struct {
	ServerPort           string
	DatabaseURL          string
	RedisAddr            string
	RedisPassword        string
	JWTSecret            string
	RetentionDays        int
	MediaBucketName      string
	MediaUploadExpirySec int // Default to 600 (10 minutes)
}

// LoadConfig reads variables from system environments or returns default values.
func LoadConfig() *Config {
	return &Config{
		ServerPort:           getEnv("SERVER_PORT", ":8080"),
		DatabaseURL:          getEnv("DATABASE_URL", "postgres://nearby_user:nearby_secure_pass@localhost:5432/nearby_connect?sslmode=disable"),
		RedisAddr:            getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:        getEnv("REDIS_PASSWORD", ""),
		JWTSecret:            getEnv("JWT_SECRET", "nearby_connect_default_development_secret_key_64_chars"),
		RetentionDays:        getEnvInt("RETENTION_PURGE_DAYS_THRESHOLD", 180),
		MediaBucketName:      getEnv("MEDIA_BUCKET_NAME", "nearby-transient-media"),
		MediaUploadExpirySec: getEnvInt("MEDIA_UPLOAD_EXPIRY_SECONDS", 600), // 10 minutes TTL
	}
}

func getEnv(key, defaultVal string) string {
	if val, exists := os.LookupEnv(key); exists {
		return val
	}
	return defaultVal
}

func getEnvInt(key string, defaultVal int) int {
	valStr := getEnv(key, "")
	if valStr == "" {
		return defaultVal
	}
	val, err := strconv.Atoi(valStr)
	if err != nil {
		return defaultVal
	}
	return val
}
