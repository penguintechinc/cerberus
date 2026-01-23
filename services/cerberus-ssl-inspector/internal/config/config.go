// Cerberus SSL Inspector - Configuration
package config

import (
	"os"
	"strconv"
	"strings"
)

// Config holds the SSL inspector configuration.
type Config struct {
	// Server addresses
	APIListenAddr   string
	ProxyListenAddr string

	// CA settings
	CADir        string
	CACertFile   string
	CAKeyFile    string
	CACommonName string
	CAOrg        string
	CAValidity   int // days

	// Proxy settings
	ConnectTimeout  int // seconds
	ReadTimeout     int // seconds
	WriteTimeout    int // seconds
	MaxConnections  int
	BufferSize      int

	// Inspection settings
	InspectHTTPS    bool
	LogConnections  bool
	BypassDomains   []string

	// Filter integration
	FilterURL string

	// Logging
	LogLevel string
}

// Load loads configuration from environment variables.
func Load() (*Config, error) {
	cfg := &Config{
		APIListenAddr:   getEnv("API_LISTEN_ADDR", ":8081"),
		ProxyListenAddr: getEnv("PROXY_LISTEN_ADDR", ":8443"),
		CADir:           getEnv("CA_DIR", "/data/ca"),
		CACertFile:      getEnv("CA_CERT_FILE", "ca.crt"),
		CAKeyFile:       getEnv("CA_KEY_FILE", "ca.key"),
		CACommonName:    getEnv("CA_COMMON_NAME", "Cerberus SSL Inspector CA"),
		CAOrg:           getEnv("CA_ORG", "Cerberus NGFW"),
		CAValidity:      getEnvInt("CA_VALIDITY", 3650), // 10 years
		ConnectTimeout:  getEnvInt("CONNECT_TIMEOUT", 10),
		ReadTimeout:     getEnvInt("READ_TIMEOUT", 30),
		WriteTimeout:    getEnvInt("WRITE_TIMEOUT", 30),
		MaxConnections:  getEnvInt("MAX_CONNECTIONS", 10000),
		BufferSize:      getEnvInt("BUFFER_SIZE", 32768),
		InspectHTTPS:    getEnvBool("INSPECT_HTTPS", true),
		LogConnections:  getEnvBool("LOG_CONNECTIONS", true),
		FilterURL:       getEnv("FILTER_URL", "http://cerberus-filter:8080"),
		LogLevel:        getEnv("LOG_LEVEL", "info"),
	}

	// Parse bypass domains
	if domains := getEnv("BYPASS_DOMAINS", ""); domains != "" {
		cfg.BypassDomains = strings.Split(domains, ",")
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
