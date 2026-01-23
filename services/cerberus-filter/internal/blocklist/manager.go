// Cerberus Content Filter - Blocklist Manager
package blocklist

import (
	"bufio"
	"context"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/penguintechinc/cerberus/cerberus-filter/internal/config"
)

// Manager handles blocklist and allowlist operations.
type Manager struct {
	cfg       *config.Config
	redis     *redis.Client
	blocklist map[string]struct{}
	allowlist map[string]struct{}
	mu        sync.RWMutex

	// Stats
	statsLock      sync.Mutex
	blockedCount   int64
	allowedCount   int64
	lookupCount    int64
	cacheHits      int64
	cacheMisses    int64
}

// NewManager creates a new blocklist manager.
func NewManager(cfg *config.Config) (*Manager, error) {
	m := &Manager{
		cfg:       cfg,
		blocklist: make(map[string]struct{}),
		allowlist: make(map[string]struct{}),
	}

	// Initialize Redis client if caching enabled
	if cfg.CacheEnabled && cfg.RedisAddr != "" {
		m.redis = redis.NewClient(&redis.Options{
			Addr:     cfg.RedisAddr,
			Password: cfg.RedisPassword,
			DB:       cfg.RedisDB,
		})
	}

	// Load blocklists from disk
	if err := m.loadBlocklists(); err != nil {
		return nil, err
	}

	return m, nil
}

// Check checks if a domain/URL should be blocked.
func (m *Manager) Check(ctx context.Context, domain string) (blocked bool, reason string) {
	domain = normalizeDomain(domain)

	m.statsLock.Lock()
	m.lookupCount++
	m.statsLock.Unlock()

	// Check cache first
	if m.cfg.CacheEnabled && m.redis != nil {
		if result, err := m.redis.Get(ctx, "filter:"+domain).Result(); err == nil {
			m.statsLock.Lock()
			m.cacheHits++
			m.statsLock.Unlock()

			if result == "blocked" {
				return true, "cached_block"
			} else if result == "allowed" {
				return false, "cached_allow"
			}
		} else {
			m.statsLock.Lock()
			m.cacheMisses++
			m.statsLock.Unlock()
		}
	}

	// Check allowlist first (allowlist takes priority)
	m.mu.RLock()
	if _, ok := m.allowlist[domain]; ok {
		m.mu.RUnlock()
		m.cacheResult(ctx, domain, "allowed")
		m.statsLock.Lock()
		m.allowedCount++
		m.statsLock.Unlock()
		return false, "allowlist"
	}

	// Check parent domains in allowlist
	parts := strings.Split(domain, ".")
	for i := 1; i < len(parts); i++ {
		parent := strings.Join(parts[i:], ".")
		if _, ok := m.allowlist[parent]; ok {
			m.mu.RUnlock()
			m.cacheResult(ctx, domain, "allowed")
			m.statsLock.Lock()
			m.allowedCount++
			m.statsLock.Unlock()
			return false, "allowlist_parent"
		}
	}

	// Check blocklist
	if _, ok := m.blocklist[domain]; ok {
		m.mu.RUnlock()
		m.cacheResult(ctx, domain, "blocked")
		m.statsLock.Lock()
		m.blockedCount++
		m.statsLock.Unlock()
		return true, "blocklist"
	}

	// Check parent domains in blocklist
	for i := 1; i < len(parts); i++ {
		parent := strings.Join(parts[i:], ".")
		if _, ok := m.blocklist[parent]; ok {
			m.mu.RUnlock()
			m.cacheResult(ctx, domain, "blocked")
			m.statsLock.Lock()
			m.blockedCount++
			m.statsLock.Unlock()
			return true, "blocklist_parent"
		}
	}
	m.mu.RUnlock()

	// Not in any list
	m.cacheResult(ctx, domain, "allowed")
	return false, ""
}

// AddBlock adds a domain to the blocklist.
func (m *Manager) AddBlock(domain string) {
	domain = normalizeDomain(domain)
	m.mu.Lock()
	m.blocklist[domain] = struct{}{}
	m.mu.Unlock()
}

// RemoveBlock removes a domain from the blocklist.
func (m *Manager) RemoveBlock(domain string) {
	domain = normalizeDomain(domain)
	m.mu.Lock()
	delete(m.blocklist, domain)
	m.mu.Unlock()
}

// AddAllow adds a domain to the allowlist.
func (m *Manager) AddAllow(domain string) {
	domain = normalizeDomain(domain)
	m.mu.Lock()
	m.allowlist[domain] = struct{}{}
	m.mu.Unlock()
}

// RemoveAllow removes a domain from the allowlist.
func (m *Manager) RemoveAllow(domain string) {
	domain = normalizeDomain(domain)
	m.mu.Lock()
	delete(m.allowlist, domain)
	m.mu.Unlock()
}

// GetBlocklist returns a copy of the blocklist.
func (m *Manager) GetBlocklist() []string {
	m.mu.RLock()
	defer m.mu.RUnlock()

	list := make([]string, 0, len(m.blocklist))
	for domain := range m.blocklist {
		list = append(list, domain)
	}
	return list
}

// GetAllowlist returns a copy of the allowlist.
func (m *Manager) GetAllowlist() []string {
	m.mu.RLock()
	defer m.mu.RUnlock()

	list := make([]string, 0, len(m.allowlist))
	for domain := range m.allowlist {
		list = append(list, domain)
	}
	return list
}

// GetStats returns blocklist statistics.
func (m *Manager) GetStats() map[string]int64 {
	m.statsLock.Lock()
	defer m.statsLock.Unlock()

	m.mu.RLock()
	blocklistSize := int64(len(m.blocklist))
	allowlistSize := int64(len(m.allowlist))
	m.mu.RUnlock()

	return map[string]int64{
		"blocklist_size": blocklistSize,
		"allowlist_size": allowlistSize,
		"blocked_count":  m.blockedCount,
		"allowed_count":  m.allowedCount,
		"lookup_count":   m.lookupCount,
		"cache_hits":     m.cacheHits,
		"cache_misses":   m.cacheMisses,
	}
}

// Reload reloads blocklists from disk.
func (m *Manager) Reload() error {
	return m.loadBlocklists()
}

func (m *Manager) loadBlocklists() error {
	// Ensure directory exists
	if err := os.MkdirAll(m.cfg.BlocklistDir, 0755); err != nil {
		return err
	}

	// Load all .txt files from blocklist directory
	files, err := filepath.Glob(filepath.Join(m.cfg.BlocklistDir, "*.txt"))
	if err != nil {
		return err
	}

	newBlocklist := make(map[string]struct{})
	newAllowlist := make(map[string]struct{})

	for _, file := range files {
		isAllow := strings.Contains(filepath.Base(file), "allow")

		f, err := os.Open(file)
		if err != nil {
			continue
		}

		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}

			domain := normalizeDomain(line)
			if isAllow {
				newAllowlist[domain] = struct{}{}
			} else {
				newBlocklist[domain] = struct{}{}
			}
		}
		f.Close()
	}

	m.mu.Lock()
	m.blocklist = newBlocklist
	m.allowlist = newAllowlist
	m.mu.Unlock()

	return nil
}

func (m *Manager) cacheResult(ctx context.Context, domain, result string) {
	if m.cfg.CacheEnabled && m.redis != nil {
		ttl := time.Duration(m.cfg.CacheTTL) * time.Second
		m.redis.Set(ctx, "filter:"+domain, result, ttl)
	}
}

// UpdateFromURL downloads and updates blocklist from URL.
func (m *Manager) UpdateFromURL(url string, filename string) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	filepath := filepath.Join(m.cfg.BlocklistDir, filename)
	f, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = io.Copy(f, resp.Body)
	if err != nil {
		return err
	}

	return m.Reload()
}

func normalizeDomain(domain string) string {
	domain = strings.ToLower(domain)
	domain = strings.TrimPrefix(domain, "http://")
	domain = strings.TrimPrefix(domain, "https://")
	domain = strings.TrimPrefix(domain, "www.")
	domain = strings.Split(domain, "/")[0]
	domain = strings.Split(domain, ":")[0]
	return domain
}
