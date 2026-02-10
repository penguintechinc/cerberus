// Package main is the entry point for the Go backend server.
package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"

	gocommon "github.com/penguintechinc/penguin-libs/packages/go-common"

	"github.com/penguintechinc/cerberus/services/go-backend/internal/config"
	"github.com/penguintechinc/cerberus/services/go-backend/internal/memory"
	"github.com/penguintechinc/cerberus/services/go-backend/internal/server"
	"github.com/penguintechinc/cerberus/services/go-backend/internal/xdp"
)

var logger = gocommon.NewSanitizedLogger("cerberus-xdp")

func main() {
	logger.Info("Starting Go high-performance backend...")

	// Load configuration
	cfg := config.Load()

	logger.Info("Configuration loaded",
		"environment", cfg.Environment,
		"host", cfg.Host,
		"port", cfg.Port,
		"numa_enabled", cfg.NUMAEnabled,
		"xdp_enabled", cfg.XDPEnabled,
	)

	// Set GOMAXPROCS based on available CPUs
	numCPU := runtime.NumCPU()
	runtime.GOMAXPROCS(numCPU)
	logger.Info("GOMAXPROCS set", "cpus", numCPU)

	// Initialize NUMA if enabled
	if cfg.NUMAEnabled {
		initNUMA()
	}

	// Set memlock rlimit for BPF if XDP is enabled
	if cfg.XDPEnabled {
		if err := xdp.SetRLimitMemlock(); err != nil {
			logger.Warn("Failed to set memlock rlimit", "error", err)
		}
	}

	// Create and start server
	srv, err := server.NewServer(cfg)
	if err != nil {
		logger.Fatal("Failed to create server", "error", err)
	}

	// Start server in a goroutine
	go func() {
		logger.Info("Server listening", "host", cfg.Host, "port", cfg.Port)
		if err := srv.Start(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("Server failed", "error", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("Shutting down server...")

	// Give outstanding requests 30 seconds to complete
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Error("Server forced to shutdown", "error", err)
	}

	logger.Info("Server stopped")
}

// initNUMA initializes NUMA-aware settings.
func initNUMA() {
	info := memory.GetNUMAInfo()

	if !info.Available {
		logger.Info("NUMA: Not available on this system")
		return
	}

	logger.Info("NUMA available", "nodes", info.NodeCount, "current_node", info.CurrentNode)

	// Log memory per node
	for node, memMB := range info.MemoryMB {
		logger.Info("NUMA node memory", "node", node, "memory_mb", memMB)
	}

	// Log CPUs per node
	for node, cpus := range info.CPUsPerNode {
		logger.Info("NUMA node CPUs", "node", node, "cpus", cpus)
	}

	// Optionally bind to a specific node (node 0 by default)
	if err := memory.BindToNUMANode(0); err != nil {
		logger.Warn("Failed to bind to NUMA node 0", "error", err)
	} else {
		logger.Info("Successfully bound to NUMA node 0")
	}
}
