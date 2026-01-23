// Cerberus Content Filter - URL Categorization Engine
package categorizer

import (
	"bufio"
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/penguintechinc/cerberus/cerberus-filter/internal/config"
)

// Category represents a URL category.
type Category struct {
	Name        string
	Description string
	Blocked     bool
	URLs        map[string]struct{}
}

// CategoryResult is the result of categorizing a URL.
type CategoryResult struct {
	URL        string   `json:"url"`
	Domain     string   `json:"domain"`
	Categories []string `json:"categories"`
	Blocked    bool     `json:"blocked"`
	Reason     string   `json:"reason,omitempty"`
}

// Categorizer handles URL categorization.
type Categorizer struct {
	cfg        *config.Config
	redis      *redis.Client
	categories map[string]*Category
	domainMap  map[string][]string // domain -> list of category names
	mu         sync.RWMutex

	// Stats
	statsLock       sync.Mutex
	categorizeCount int64
	unknownCount    int64
}

// New creates a new URL categorizer.
func New(cfg *config.Config) (*Categorizer, error) {
	c := &Categorizer{
		cfg:        cfg,
		categories: make(map[string]*Category),
		domainMap:  make(map[string][]string),
	}

	// Initialize Redis client if caching enabled
	if cfg.CacheEnabled && cfg.RedisAddr != "" {
		c.redis = redis.NewClient(&redis.Options{
			Addr:     cfg.RedisAddr,
			Password: cfg.RedisPassword,
			DB:       cfg.RedisDB,
		})
	}

	// Load categories from disk
	if err := c.loadCategories(); err != nil {
		return nil, err
	}

	// Set blocked categories from config
	for _, cat := range cfg.BlockedCategories {
		if category, ok := c.categories[cat]; ok {
			category.Blocked = true
		}
	}

	return c, nil
}

// Categorize returns categories for a URL.
func (c *Categorizer) Categorize(ctx context.Context, url string) *CategoryResult {
	domain := normalizeDomain(url)

	c.statsLock.Lock()
	c.categorizeCount++
	c.statsLock.Unlock()

	// Check cache first
	if c.cfg.CacheEnabled && c.redis != nil {
		if cached, err := c.redis.Get(ctx, "cat:"+domain).Result(); err == nil {
			cats := strings.Split(cached, ",")
			blocked, reason := c.checkBlocked(cats)
			return &CategoryResult{
				URL:        url,
				Domain:     domain,
				Categories: cats,
				Blocked:    blocked,
				Reason:     reason,
			}
		}
	}

	// Look up categories
	c.mu.RLock()
	cats, found := c.domainMap[domain]
	if !found {
		// Try parent domains
		parts := strings.Split(domain, ".")
		for i := 1; i < len(parts); i++ {
			parent := strings.Join(parts[i:], ".")
			if parentCats, ok := c.domainMap[parent]; ok {
				cats = parentCats
				found = true
				break
			}
		}
	}
	c.mu.RUnlock()

	if !found {
		c.statsLock.Lock()
		c.unknownCount++
		c.statsLock.Unlock()

		return &CategoryResult{
			URL:        url,
			Domain:     domain,
			Categories: []string{"uncategorized"},
			Blocked:    false,
		}
	}

	// Cache result
	if c.cfg.CacheEnabled && c.redis != nil {
		ttl := time.Duration(c.cfg.CacheTTL) * time.Second
		c.redis.Set(ctx, "cat:"+domain, strings.Join(cats, ","), ttl)
	}

	blocked, reason := c.checkBlocked(cats)
	return &CategoryResult{
		URL:        url,
		Domain:     domain,
		Categories: cats,
		Blocked:    blocked,
		Reason:     reason,
	}
}

// GetCategories returns all available categories.
func (c *Categorizer) GetCategories() []string {
	c.mu.RLock()
	defer c.mu.RUnlock()

	cats := make([]string, 0, len(c.categories))
	for name := range c.categories {
		cats = append(cats, name)
	}
	return cats
}

// GetCategoryInfo returns info about a specific category.
func (c *Categorizer) GetCategoryInfo(name string) (*Category, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	cat, ok := c.categories[name]
	return cat, ok
}

// SetCategoryBlocked sets whether a category is blocked.
func (c *Categorizer) SetCategoryBlocked(name string, blocked bool) bool {
	c.mu.Lock()
	defer c.mu.Unlock()

	if cat, ok := c.categories[name]; ok {
		cat.Blocked = blocked
		return true
	}
	return false
}

// GetURLsInCategory returns URLs in a category (limited).
func (c *Categorizer) GetURLsInCategory(name string, limit int) []string {
	c.mu.RLock()
	defer c.mu.RUnlock()

	cat, ok := c.categories[name]
	if !ok {
		return nil
	}

	urls := make([]string, 0, limit)
	count := 0
	for url := range cat.URLs {
		if count >= limit {
			break
		}
		urls = append(urls, url)
		count++
	}
	return urls
}

// GetStats returns categorizer statistics.
func (c *Categorizer) GetStats() map[string]interface{} {
	c.statsLock.Lock()
	defer c.statsLock.Unlock()

	c.mu.RLock()
	categoryCount := len(c.categories)
	domainCount := len(c.domainMap)
	c.mu.RUnlock()

	return map[string]interface{}{
		"category_count":   categoryCount,
		"domain_count":     domainCount,
		"categorize_count": c.categorizeCount,
		"unknown_count":    c.unknownCount,
	}
}

func (c *Categorizer) checkBlocked(cats []string) (blocked bool, reason string) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	for _, catName := range cats {
		if cat, ok := c.categories[catName]; ok && cat.Blocked {
			return true, "category_blocked:" + catName
		}
	}
	return false, ""
}

func (c *Categorizer) loadCategories() error {
	categoriesDir := filepath.Join(c.cfg.BlocklistDir, "categories")
	if err := os.MkdirAll(categoriesDir, 0755); err != nil {
		return err
	}

	// Default categories if none exist
	defaultCategories := []struct {
		name string
		desc string
	}{
		{"adult", "Adult/Pornographic content"},
		{"gambling", "Gambling sites"},
		{"malware", "Malware and phishing sites"},
		{"ads", "Advertising and tracking"},
		{"social", "Social media platforms"},
		{"streaming", "Video streaming sites"},
		{"gaming", "Online gaming sites"},
		{"news", "News and media"},
		{"shopping", "E-commerce and shopping"},
		{"finance", "Banking and financial services"},
	}

	c.mu.Lock()
	for _, dc := range defaultCategories {
		c.categories[dc.name] = &Category{
			Name:        dc.name,
			Description: dc.desc,
			Blocked:     false,
			URLs:        make(map[string]struct{}),
		}
	}
	c.mu.Unlock()

	// Load category files
	files, err := filepath.Glob(filepath.Join(categoriesDir, "*.txt"))
	if err != nil {
		return err
	}

	for _, file := range files {
		catName := strings.TrimSuffix(filepath.Base(file), ".txt")

		c.mu.Lock()
		if _, ok := c.categories[catName]; !ok {
			c.categories[catName] = &Category{
				Name:        catName,
				Description: catName + " category",
				Blocked:     false,
				URLs:        make(map[string]struct{}),
			}
		}
		cat := c.categories[catName]
		c.mu.Unlock()

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
			c.mu.Lock()
			cat.URLs[domain] = struct{}{}
			if existing, ok := c.domainMap[domain]; ok {
				c.domainMap[domain] = append(existing, catName)
			} else {
				c.domainMap[domain] = []string{catName}
			}
			c.mu.Unlock()
		}
		f.Close()
	}

	return nil
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
