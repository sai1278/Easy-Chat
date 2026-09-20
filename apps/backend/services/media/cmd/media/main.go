package main

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"sync"
	"time"

	_ "github.com/lib/pq"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	"nearby/backend/services/media/internal/application"
	"nearby/backend/services/media/internal/domain"
	"nearby/backend/services/media/internal/infrastructure/persistence"
	"nearby/backend/services/media/internal/infrastructure/scanner"
	"nearby/backend/services/media/internal/infrastructure/storage"
	transport "nearby/backend/services/media/internal/transport/http"
	sharedconfig "nearby/backend/shared/config"
	"nearby/backend/shared/logger"
	"nearby/backend/shared/tracing"
)

func main() {
	log := logger.NewJSONLogger()
	slog.SetDefault(log)

	cfg := sharedconfig.LoadBaseConfig()

	log.Info("Starting Media Service...", "environment", cfg.Environment, "port", cfg.Port)

	// Initialize OpenTelemetry tracing
	_, err := tracing.InitTracer("media-service")
	if err != nil {
		log.Error("Failed to initialize OpenTelemetry tracing", "err", err)
	}

	// 1. Initialize PostgreSQL Connection
	var db *sql.DB
	if cfg.DatabaseURL != "" {
		d, err := sql.Open("postgres", cfg.DatabaseURL)
		if err != nil {
			log.Error("Failed to open Postgres connection", "err", err)
			os.Exit(1)
		}
		db = d
		defer db.Close()

		db.SetMaxOpenConns(25)
		db.SetMaxIdleConns(25)
		db.SetConnMaxLifetime(5 * time.Minute)

		if err := db.Ping(); err != nil {
			log.Error("Failed to ping Postgres database", "err", err)
			os.Exit(1)
		}
		log.Info("Successfully connected to PostgreSQL")
	} else {
		log.Warn("DATABASE_URL is empty. Continuing without persistent DB metadata (mock mode).")
	}

	// 2. Initialize S3-compatible cloud storage Client (MinIO / S3)
	var s3Client *s3.Client
	s3Bucket := os.Getenv("S3_BUCKET")
	if s3Bucket == "" {
		s3Bucket = "easychat-media"
	}
	s3Endpoint := os.Getenv("S3_ENDPOINT") // Set for local MinIO instances
	s3Region := os.Getenv("AWS_REGION")
	if s3Region == "" {
		s3Region = "us-east-1"
	}

	awsAccessKey := os.Getenv("AWS_ACCESS_KEY_ID")
	awsSecretKey := os.Getenv("AWS_SECRET_ACCESS_KEY")

	if awsAccessKey != "" && awsSecretKey != "" {
		// Custom credentials solver
		creds := credentials.NewStaticCredentialsProvider(awsAccessKey, awsSecretKey, "")
		
		var opts []func(*config.LoadOptions) error
		opts = append(opts, config.WithRegion(s3Region))
		opts = append(opts, config.WithCredentialsProvider(creds))

		awsCfg, err := config.LoadDefaultConfig(context.Background(), opts...)
		if err == nil {
			s3Client = s3.NewFromConfig(awsCfg, func(o *s3.Options) {
				if s3Endpoint != "" {
					o.BaseEndpoint = aws.String(s3Endpoint)
					o.UsePathStyle = true // Required for MinIO
				}
			})
			log.Info("S3 Storage Client initialized successfully", "bucket", s3Bucket, "endpoint", s3Endpoint)
		} else {
			log.Error("Failed to load AWS configuration", "err", err)
		}
	} else if os.Getenv("APP_ENV") == "production" || os.Getenv("USE_AWS_IAM") == "true" {
		awsCfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(s3Region))
		if err == nil {
			s3Client = s3.NewFromConfig(awsCfg)
			log.Info("S3 Storage Client initialized via AWS IAM Instance Profile", "bucket", s3Bucket, "region", s3Region)
		} else {
			log.Warn("Failed to resolve AWS IAM credentials, falling back to local storage", "err", err)
		}
	} else {
		log.Warn("S3 credentials not set. Falling back to local in-memory storage mode.")
	}

	// CDN target mapping (if configured)
	cdnURL := os.Getenv("CDN_URL")

	// 3. Initialize Repositories
	var metaRepo domain.MetadataRepository
	if db != nil {
		metaRepo = persistence.NewPostgresMetadataRepository(db)
	} else {
		metaRepo = &mockMetadataRepository{}
	}

	storeRepo := storage.NewS3StorageRepository(s3Client, s3Bucket, cdnURL)

	clamavAddr := os.Getenv("CLAMAV_ADDRESS") // e.g. "localhost:3310"
	virusScanner := scanner.NewClamAVScanner(clamavAddr)

	// 4. Initialize Usecase and Handlers
	usecase := application.NewMediaUsecase(metaRepo, storeRepo, virusScanner)
	handler := transport.NewMediaHandler(usecase)

	// 5. Register HTTP endpoints
	http.HandleFunc("/upload", handler.UploadHandler)
	http.HandleFunc("/download/", handler.DownloadRedirectHandler)
	http.HandleFunc("/signed-upload-url", handler.SignedUploadURLHandler)
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})
	http.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ready"))
	})
	http.HandleFunc("/live", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("live"))
	})
	http.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("media_service_status 1"))
	})

	serverAddr := fmt.Sprintf(":%d", cfg.Port)
	log.Info("Media HTTP API Server listening", "addr", serverAddr)
	if err := http.ListenAndServe(serverAddr, nil); err != nil {
		log.Error("Media service HTTP server crashed", "err", err)
		os.Exit(1)
	}
}

// Minimal mock in-memory Metadata Repository fallback when DB is omitted
type mockMetadataRepository struct {
	mu    sync.RWMutex
	cache map[string]*domain.FileMetadata
}

func (m *mockMetadataRepository) SaveMetadata(ctx context.Context, meta *domain.FileMetadata) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cache == nil {
		m.cache = make(map[string]*domain.FileMetadata)
	}
	m.cache[meta.ID] = meta
	return nil
}

func (m *mockMetadataRepository) GetMetadata(ctx context.Context, id string) (*domain.FileMetadata, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	meta, exists := m.cache[id]
	if !exists {
		return nil, fmt.Errorf("metadata not found: %s", id)
	}
	return meta, nil
}

func (m *mockMetadataRepository) DeleteMetadata(ctx context.Context, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cache != nil {
		delete(m.cache, id)
	}
	return nil
}

func (m *mockMetadataRepository) IsUserInRoom(ctx context.Context, userID, roomID string) (bool, error) {
	return true, nil
}

func (m *mockMetadataRepository) IsMessageActiveInRoom(ctx context.Context, messageID, roomID string) (bool, error) {
	return true, nil
}
