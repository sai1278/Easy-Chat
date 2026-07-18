package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"os"
	"strings"
	"time"

	transport "nearby/backend/services/gateway/internal/transport/http"
	"nearby/backend/shared/config"
	"nearby/backend/shared/logger"
	"nearby/backend/shared/tracing"
)

func main() {
	log := logger.NewJSONLogger()
	slog.SetDefault(log)

	cfg := config.LoadBaseConfig()
	if os.Getenv("PORT") == "" {
		cfg.Port = 8090
	}

	log.Info("Starting API Gateway Service...", "port", cfg.Port)

	// Initialize OpenTelemetry tracing
	_, err := tracing.InitTracer("api-gateway")
	if err != nil {
		log.Error("Failed to initialize OpenTelemetry tracing", "err", err)
	}

	// Read secret key
	secretEnv := os.Getenv("JWT_SECRET")
	if secretEnv == "" {
		secretEnv = "test_secret_key"
	}
	secretKey := []byte(secretEnv)

	// Parse microservice cluster targets from environment variables (or defaults)
	authHosts := getEnvHosts("AUTH_HOSTS", "http://localhost:8081")
	userHosts := getEnvHosts("USER_HOSTS", "http://localhost:8082")
	chatHosts := getEnvHosts("CHAT_HOSTS", "http://localhost:8083")
	nearbyHosts := getEnvHosts("NEARBY_HOSTS", "http://localhost:8084")
	presHosts := getEnvHosts("PRES_HOSTS", "http://localhost:8085")
	mediaHosts := getEnvHosts("MEDIA_HOSTS", "http://localhost:8086")
	complianceHosts := getEnvHosts("COMPLIANCE_HOSTS", "http://localhost:8087")

	router := transport.NewRouter(secretKey, authHosts, userHosts, chatHosts, nearbyHosts, presHosts, mediaHosts, complianceHosts)
	handler := router.RegisterRoutes()

	serverAddr := fmt.Sprintf(":%d", cfg.Port)

	// Check if TLS termination certificates are present, or dynamically generate self-signed certs
	certFile := os.Getenv("TLS_CERT_FILE")
	if certFile == "" {
		certFile = "cert.pem"
	}
	keyFile := os.Getenv("TLS_KEY_FILE")
	if keyFile == "" {
		keyFile = "key.pem"
	}

	if os.Getenv("DISABLE_TLS") == "true" {
		log.Warn("TLS is disabled. Starting Gateway on HTTP...", "addr", serverAddr)
		if err := http.ListenAndServe(serverAddr, handler); err != nil {
			log.Error("API Gateway HTTP server crashed", "err", err)
			os.Exit(1)
		}
		return
	}

	if _, err := os.Stat(certFile); os.IsNotExist(err) {
		log.Info("TLS certificates not found. Generating self-signed certificates for development...")
		if err := generateSelfSignedCert(certFile, keyFile); err != nil {
			log.Error("Failed to generate self-signed certificates", "err", err)
			os.Exit(1)
		}
		log.Info("Self-signed certificates generated successfully", "cert", certFile, "key", keyFile)
	}

	log.Info("Starting secure API Gateway on HTTPS...", "addr", serverAddr)
	if err := http.ListenAndServeTLS(serverAddr, certFile, keyFile, handler); err != nil {
		log.Error("API Gateway HTTPS server crashed", "err", err)
		os.Exit(1)
	}
}

func getEnvHosts(envName, defaultValue string) []string {
	val := os.Getenv(envName)
	if val == "" {
		val = defaultValue
	}
	return strings.Split(val, ",")
}

// generateSelfSignedCert creates temporary self-signed SSL/TLS keys for local zero-config HTTPS testing.
func generateSelfSignedCert(certPath, keyPath string) error {
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return err
	}

	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			Organization: []string{"EasyChat API Gateway"},
		},
		NotBefore:             time.Now().Add(-10 * time.Minute),
		NotAfter:              time.Now().Add(365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}

	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		return err
	}

	certOut, err := os.Create(certPath)
	if err != nil {
		return err
	}
	defer certOut.Close()
	if err := pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes}); err != nil {
		return err
	}

	keyOut, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	defer keyOut.Close()

	privBytes, err := x509.MarshalPKCS8PrivateKey(priv)
	if err != nil {
		return err
	}

	if err := pem.Encode(keyOut, &pem.Block{Type: "PRIVATE KEY", Bytes: privBytes}); err != nil {
		return err
	}

	return nil
}
