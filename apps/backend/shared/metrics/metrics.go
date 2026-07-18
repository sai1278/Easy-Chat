package metrics

import (
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// HttpLatency tracks REST and HTTP API latency response durations.
	HttpLatency = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Duration of HTTP requests in seconds.",
			Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0},
		},
		[]string{"service", "handler", "method", "status"},
	)

	// WebSocketConnections tracks active WebSocket client connection counts.
	WebSocketConnections = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "websocket_active_connections",
			Help: "Number of active WebSocket client connections.",
		},
		[]string{"service"},
	)

	// DbPerformance tracks SQL and database query execution durations.
	DbPerformance = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "db_query_duration_seconds",
			Help:    "Duration of database queries in seconds.",
			Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0},
		},
		[]string{"service", "query_type"},
	)

	// RedisHealth tracks status check metrics (1 = healthy, 0 = disconnected).
	RedisHealth = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "redis_health_status",
			Help: "Health status of Redis connection (1 = healthy, 0 = unhealthy).",
		},
		[]string{"service"},
	)

	// KafkaLag tracks consumer lag offset message counts.
	KafkaLag = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "kafka_consumer_lag_messages",
			Help: "Number of lagged messages for consumer groups.",
		},
		[]string{"service", "topic", "group"},
	)
)

// InitMetrics registers all custom collectors to the default Prometheus registry.
func InitMetrics(serviceName string) {
	_ = prometheus.Register(HttpLatency)
	_ = prometheus.Register(WebSocketConnections)
	_ = prometheus.Register(DbPerformance)
	_ = prometheus.Register(RedisHealth)
	_ = prometheus.Register(KafkaLag)
}

// Handler returns the Prometheus metrics scrape HTTP handler.
func Handler() http.Handler {
	return promhttp.Handler()
}

// TrackHttpLatency tracks request duration.
func TrackHttpLatency(service, handler, method, status string, start time.Time) {
	HttpLatency.WithLabelValues(service, handler, method, status).Observe(time.Since(start).Seconds())
}

// TrackDbQuery tracks DB query duration.
func TrackDbQuery(service, queryType string, start time.Time) {
	DbPerformance.WithLabelValues(service, queryType).Observe(time.Since(start).Seconds())
}
