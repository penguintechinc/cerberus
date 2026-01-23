// Cerberus Content Filter - Configuration
package config

import (
	"os"
	"strconv"
	"strings"
)

// Config holds the filter configuration.
type Config struct {
	ListenAddr string
	LogLevel   string

	// Redis cache
	RedisAddr     string
	RedisPassword string
	RedisDB       int

	// Blocklist settings
	BlocklistDir       string
	BlocklistUpdateURL string
	UpdateInterval     int // hours

	// Category settings
	DefaultAction    string // block, allow, log
	BlockedCategories []string

	// Performance
	CacheEnabled bool
	CacheTTL     int // seconds
	MaxBatchSize int
}

// Load loads configuration from environment variables.
func Load() (*Config, error) {
	cfg := &Config{
		ListenAddr:         getEnv("LISTEN_ADDR", ":8080"),
		LogLevel:           getEnv("LOG_LEVEL", "info"),
		RedisAddr:          getEnv("REDIS_ADDR", "redis:6379"),
		RedisPassword:      getEnv("REDIS_PASSWORD", ""),
		RedisDB:            getEnvInt("REDIS_DB", 0),
		BlocklistDir:       getEnv("BLOCKLIST_DIR", "/data/blocklists"),
		BlocklistUpdateURL: getEnv("BLOCKLIST_UPDATE_URL", ""),
		UpdateInterval:     getEnvInt("UPDATE_INTERVAL", 24),
		DefaultAction:      getEnv("DEFAULT_ACTION", "allow"),
		CacheEnabled:       getEnvBool("CACHE_ENABLED", true),
		CacheTTL:           getEnvInt("CACHE_TTL", 3600),
		MaxBatchSize:       getEnvInt("MAX_BATCH_SIZE", 100),
	}

	// Parse blocked categories
	if cats := getEnv("BLOCKED_CATEGORIES", ""); cats != "" {
		cfg.BlockedCategories = strings.Split(cats, ",")
	}

	return cfg, nil
}

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getEnvInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if i, err := strconv.Atoi(val); err == nil {
			return i
		}
	}
	return defaultVal
}

func getEnvBool(key string, defaultVal bool) bool {
	if val := os.Getenv(key); val != "" {
		return strings.ToLower(val) == "true" || val == "1"
	}
	return defaultVal
}
