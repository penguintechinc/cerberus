// Package server provides the HTTP server for the Go backend.
package server

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/penguintechinc/project-template/services/go-backend/internal/config"
	"github.com/penguintechinc/project-template/services/go-backend/internal/memory"
	"github.com/penguintechinc/project-template/services/go-backend/internal/metrics"
)

// Server represents the HTTP server.
type Server struct {
	config     *config.Config
	router     *gin.Engine
	httpServer *http.Server
	handlers   *Handlers
	metrics    *metrics.Metrics
	memPool    *memory.MemoryPool
}

// NewServer creates a new HTTP server instance.
func NewServer(cfg *config.Config) (*Server, error) {
	// Set Gin mode based on environment
	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()

	// Add recovery middleware
	router.Use(gin.Recovery())

	// Initialize metrics
	m := metrics.NewMetrics("go_backend")

	// Add logging and metrics middleware
	router.Use(loggingMiddleware())
	router.Use(metricsMiddleware(m))

	// Initialize memory pool if enabled
	var memPool *memory.MemoryPool
	if cfg.MemoryPoolSlots > 0 {
		var err error
		memPool, err = memory.NewMemoryPool(cfg.MemoryPoolSlots, cfg.MemoryPoolSlotSize)
		if err != nil {
			return nil, fmt.Errorf("failed to create memory pool: %w", err)
		}
	}

	// Initialize handlers
	handlers := NewHandlers(cfg.Version, memPool, cfg.XDPEnabled, cfg.XDPMode, cfg.XDPInterface)

	server := &Server{
		config:   cfg,
		router:   router,
		handlers: handlers,
		metrics:  m,
		memPool:  memPool,
	}

	// Register routes
	server.registerRoutes()

	return server, nil
}

// registerRoutes sets up all HTTP routes.
func (s *Server) registerRoutes() {
	// Health check endpoints
	s.router.GET("/healthz", s.handlers.HealthCheck)
	s.router.GET("/readyz", s.handlers.ReadinessCheck)

	// Metrics endpoint
	s.router.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// API v1 routes
	v1 := s.router.Group("/api/v1")
	{
		v1.GET("/status", s.handlers.Status)
		v1.GET("/hello", s.handlers.Hello)

		// Memory pool endpoints
		v1.POST("/packet/forward", s.handlers.PacketForward)
		v1.GET("/memory/stats", s.handlers.MemoryPoolStats)

		// NUMA information
		v1.GET("/numa/info", s.handlers.NUMAInfo)
	}
}

// Start starts the HTTP server.
func (s *Server) Start() error {
	addr := fmt.Sprintf("%s:%d", s.config.Host, s.config.Port)

	s.httpServer = &http.Server{
		Addr:         addr,
		Handler:      s.router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	return s.httpServer.ListenAndServe()
}

// Shutdown gracefully shuts down the server.
func (s *Server) Shutdown(ctx context.Context) error {
	// Close memory pool
	if s.memPool != nil {
		s.memPool.Close()
	}

	// Shutdown HTTP server
	if s.httpServer != nil {
		return s.httpServer.Shutdown(ctx)
	}

	return nil
}

// loggingMiddleware provides request logging.
func loggingMiddleware() gin.HandlerFunc {
	return gin.LoggerWithConfig(gin.LoggerConfig{
		SkipPaths: []string{"/healthz", "/readyz", "/metrics"},
	})
}

// metricsMiddleware records request metrics.
func metricsMiddleware(m *metrics.Metrics) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		m.HTTPActiveRequests.Inc()
		defer m.HTTPActiveRequests.Dec()

		c.Next()

		duration := time.Since(start).Seconds()
		status := fmt.Sprintf("%d", c.Writer.Status())

		m.RecordHTTPRequest(c.Request.Method, c.FullPath(), status, duration)
	}
}
