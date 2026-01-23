// Cerberus Content Filter - Main Entry Point
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

	"github.com/penguintechinc/cerberus/cerberus-filter/internal/blocklist"
	"github.com/penguintechinc/cerberus/cerberus-filter/internal/categorizer"
	"github.com/penguintechinc/cerberus/cerberus-filter/internal/config"
	"github.com/penguintechinc/cerberus/cerberus-filter/internal/handler"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Initialize blocklist manager
	blManager, err := blocklist.NewManager(cfg)
	if err != nil {
		log.Fatalf("Failed to initialize blocklist manager: %v", err)
	}

	// Initialize URL categorizer
	urlCategorizer, err := categorizer.New(cfg)
	if err != nil {
		log.Fatalf("Failed to initialize URL categorizer: %v", err)
	}

	// Create handler with dependencies
	h := handler.New(cfg, blManager, urlCategorizer)

	// Setup router
	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.RealIP)
	r.Use(middleware.Timeout(30 * time.Second))

	// Health endpoints
	r.Get("/healthz", h.Healthz)
	r.Get("/readyz", h.Readyz)

	// Metrics endpoint
	r.Handle("/metrics", promhttp.Handler())

	// API v1 routes
	r.Route("/api/v1", func(r chi.Router) {
		// URL check endpoint (main filtering)
		r.Post("/check", h.CheckURL)
		r.Post("/check/batch", h.CheckURLBatch)

		// Blocklist management
		r.Route("/blocklist", func(r chi.Router) {
			r.Get("/", h.ListBlocklists)
			r.Post("/", h.AddBlocklistEntry)
			r.Delete("/{entry}", h.RemoveBlocklistEntry)
			r.Post("/reload", h.ReloadBlocklists)
		})

		// Allowlist management
		r.Route("/allowlist", func(r chi.Router) {
			r.Get("/", h.ListAllowlists)
			r.Post("/", h.AddAllowlistEntry)
			r.Delete("/{entry}", h.RemoveAllowlistEntry)
		})

		// Category management
		r.Route("/categories", func(r chi.Router) {
			r.Get("/", h.ListCategories)
			r.Get("/{category}/urls", h.ListCategoryURLs)
			r.Post("/{category}/block", h.BlockCategory)
			r.Post("/{category}/allow", h.AllowCategory)
		})

		// Stats
		r.Get("/stats", h.GetStats)
	})

	// Create server
	srv := &http.Server{
		Addr:         cfg.ListenAddr,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Cerberus Content Filter starting on %s", cfg.ListenAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}
