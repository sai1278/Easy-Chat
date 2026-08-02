package main

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"

	genv1 "nearby/backend/internal/gen/v1"
	"nearby/backend/services/nearby/internal/application"
	"nearby/backend/services/nearby/internal/infrastructure/cache"
	"nearby/backend/services/nearby/internal/infrastructure/persistence"
	transportgrpc "nearby/backend/services/nearby/internal/transport/grpc"
	transporthttp "nearby/backend/services/nearby/internal/transport/http"
	"nearby/backend/shared/config"
	"nearby/backend/shared/logger"
	"nearby/backend/shared/tracing"
)

func main() {
	log := logger.NewJSONLogger()
	slog.SetDefault(log)

	cfg := config.LoadBaseConfig()
	if os.Getenv("PORT") == "" || cfg.Port == 8088 {
		cfg.Port = 8083
	}

	log.Info("Starting Nearby Proximity Service...", "environment", cfg.Environment, "grpcPort", cfg.Port, "httpPort", 8088)

	// Initialize OpenTelemetry Tracing
	_, err := tracing.InitTracer("nearby-service")
	if err != nil {
		log.Error("Failed to initialize OpenTelemetry tracing", "err", err)
	}

	// 1. Initialize PostgreSQL Connection
	if cfg.DatabaseURL == "" {
		log.Error("DATABASE_URL environment variable is not set")
		os.Exit(1)
	}

	db, err := sql.Open("postgres", cfg.DatabaseURL)
	if err != nil {
		log.Error("Failed to open Postgres database connection", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	// Configure connection pool settings for scalability and low latency
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(25)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		log.Error("Failed to ping Postgres database", "err", err)
		os.Exit(1)
	}
	log.Info("Successfully connected to PostgreSQL")

	// 2. Initialize Redis Connection
	var rdb *redis.Client
	if cfg.RedisURL != "" {
		opts, err := redis.ParseURL(cfg.RedisURL)
		if err == nil {
			rdb = redis.NewClient(opts)
		} else {
			// Fallback to direct address if parsing fails
			rdb = redis.NewClient(&redis.Options{
				Addr: cfg.RedisURL,
			})
		}
	} else {
		rdb = redis.NewClient(&redis.Options{
			Addr: "localhost:6379",
		})
	}
	defer rdb.Close()

	// Ping Redis to verify connection
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Error("Failed to ping Redis cache server", "err", err)
		os.Exit(1)
	}
	log.Info("Successfully connected to Redis")

	// 3. Initialize Repositories and Usecase
	userRepo := persistence.NewPostgresUserRepository(db)
	geoRepo := cache.NewRedisGeoRepository(rdb)
	usecase := application.NewNearbyUsecase(userRepo, geoRepo)

	// 4. Create and start gRPC Server with Standard Health Check
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", cfg.Port))
	if err != nil {
		log.Error("Failed to listen on TCP port", "port", cfg.Port, "err", err)
		os.Exit(1)
	}

	grpcServer := grpc.NewServer()
	serviceServer := transportgrpc.NewNearbyServiceServer(usecase)
	genv1.RegisterNearbyServiceServer(grpcServer, serviceServer)

	// Register Standard gRPC Health Checking Service (grpc_health_v1)
	healthServer := health.NewServer()
	healthServer.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
	healthServer.SetServingStatus("nearby.v1.NearbyService", healthpb.HealthCheckResponse_SERVING)
	healthpb.RegisterHealthServer(grpcServer, healthServer)

	log.Info("Nearby Service gRPC server is listening", "port", cfg.Port)

	// 5. Start HTTP REST, Health & Prometheus Metrics Server on Port 8088
	httpPort := 8088
	httpMux := http.NewServeMux()

	httpHandler := transporthttp.NewHandler(usecase, geoRepo)
	httpHandler.RegisterRoutes(httpMux)

	httpMux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})

	httpMux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		if err := db.Ping(); err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"status":"unready","reason":"database ping failed"}`))
			return
		}
		if err := rdb.Ping(r.Context()).Err(); err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte(`{"status":"unready","reason":"redis ping failed"}`))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ready"}`))
	})

	httpMux.HandleFunc("/livez", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"alive"}`))
	})

	httpMux.Handle("/metrics", promhttp.Handler())

	go func() {
		httpAddr := fmt.Sprintf(":%d", httpPort)
		log.Info("Nearby Service HTTP Health & Metrics server listening", "port", httpPort)
		if err := http.ListenAndServe(httpAddr, httpMux); err != nil {
			log.Error("HTTP Health server crashed", "err", err)
		}
	}()

	if err := grpcServer.Serve(lis); err != nil {
		log.Error("gRPC server crashed", "err", err)
		os.Exit(1)
	}
}
