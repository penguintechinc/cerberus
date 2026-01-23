// Cerberus SSL Inspector - Main Entry Point
// SSL/TLS MITM Proxy for Deep Packet Inspection
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/penguintechinc/cerberus/cerberus-ssl-inspector/internal/certs"
	"github.com/penguintechinc/cerberus/cerberus-ssl-inspector/internal/config"
	"github.com/penguintechinc/cerberus/cerberus-ssl-inspector/internal/handler"
	"github.com/penguintechinc/cerberus/cerberus-ssl-inspector/internal/proxy"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Initialize CA certificate manager
	caManager, err := certs.NewCAManager(cfg)
	if err != nil {
		log.Fatalf("Failed to initialize CA manager: %v", err)
	}

	// Initialize SSL proxy
	sslProxy, err := proxy.New(cfg, caManager)
	if err != nil {
		log.Fatalf("Failed to initialize SSL proxy: %v", err)
	}

	// Create API handler
	h := handler.New(cfg, caManager, sslProxy)

	// Setup API router
	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.RealIP)

	// Health endpoints
	r.Get("/healthz", h.Healthz)
	r.Get("/readyz", h.Readyz)

	// Metrics
	r.Handle("/metrics", promhttp.Handler())

	// API v1 routes
	r.Route("/api/v1", func(r chi.Router) {
		// CA certificate management
		r.Route("/ca", func(r chi.Router) {
			r.Get("/", h.GetCACert)
			r.Get("/download", h.DownloadCACert)
			r.Post("/regenerate", h.RegenerateCA)
			r.Get("/fingerprint", h.GetCAFingerprint)
		})

		// Bypass rules
		r.Route("/bypass", func(r chi.Router) {
			r.Get("/", h.ListBypassRules)
			r.Post("/", h.AddBypassRule)
			r.Delete("/{domain}", h.RemoveBypassRule)
		})

		// Inspection settings
		r.Route("/settings", func(r chi.Router) {
			r.Get("/", h.GetSettings)
			r.Put("/", h.UpdateSettings)
		})

		// Stats
		r.Get("/stats", h.GetStats)
		r.Get("/connections", h.GetActiveConnections)
	})

	// Start API server
	apiSrv := &http.Server{
		Addr:         cfg.APIListenAddr,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("API server starting on %s", cfg.APIListenAddr)
		if err := apiSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("API server error: %v", err)
		}
	}()

	// Start SSL proxy
	go func() {
		log.Printf("SSL proxy starting on %s", cfg.ProxyListenAddr)
		if err := sslProxy.Start(); err != nil {
			log.Fatalf("SSL proxy error: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down...")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := apiSrv.Shutdown(ctx); err != nil {
		log.Printf("API server shutdown error: %v", err)
	}

	sslProxy.Stop()
	log.Println("Server exited")
}
