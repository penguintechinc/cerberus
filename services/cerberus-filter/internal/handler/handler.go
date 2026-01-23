// Cerberus Content Filter - HTTP Handlers
package handler

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/penguintechinc/cerberus/cerberus-filter/internal/blocklist"
	"github.com/penguintechinc/cerberus/cerberus-filter/internal/categorizer"
	"github.com/penguintechinc/cerberus/cerberus-filter/internal/config"
)

// Handler handles HTTP requests.
type Handler struct {
	cfg         *config.Config
	blocklist   *blocklist.Manager
	categorizer *categorizer.Categorizer
}

// New creates a new handler.
func New(cfg *config.Config, bl *blocklist.Manager, cat *categorizer.Categorizer) *Handler {
	return &Handler{
		cfg:         cfg,
		blocklist:   bl,
		categorizer: cat,
	}
}

// CheckRequest is the request for URL check.
type CheckRequest struct {
	URL    string `json:"url"`
	Domain string `json:"domain,omitempty"`
}

// CheckResponse is the response for URL check.
type CheckResponse struct {
	URL        string   `json:"url"`
	Domain     string   `json:"domain"`
	Blocked    bool     `json:"blocked"`
	Reason     string   `json:"reason,omitempty"`
	Categories []string `json:"categories,omitempty"`
}

// BatchCheckRequest is the request for batch URL check.
type BatchCheckRequest struct {
	URLs []string `json:"urls"`
}

// BatchCheckResponse is the response for batch URL check.
type BatchCheckResponse struct {
	Results []CheckResponse `json:"results"`
}

// Healthz handles health check.
func (h *Handler) Healthz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

// Readyz handles readiness check.
func (h *Handler) Readyz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ready"))
}

// CheckURL checks a single URL.
func (h *Handler) CheckURL(w http.ResponseWriter, r *http.Request) {
	var req CheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	url := req.URL
	if url == "" {
		url = req.Domain
	}
	if url == "" {
		http.Error(w, "url or domain required", http.StatusBadRequest)
		return
	}

	// Check blocklist first
	blocked, blReason := h.blocklist.Check(r.Context(), url)

	// Get categories
	catResult := h.categorizer.Categorize(r.Context(), url)

	// Combine results
	resp := CheckResponse{
		URL:        url,
		Domain:     catResult.Domain,
		Categories: catResult.Categories,
	}

	if blocked {
		resp.Blocked = true
		resp.Reason = blReason
	} else if catResult.Blocked {
		resp.Blocked = true
		resp.Reason = catResult.Reason
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// CheckURLBatch checks multiple URLs.
func (h *Handler) CheckURLBatch(w http.ResponseWriter, r *http.Request) {
	var req BatchCheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if len(req.URLs) > h.cfg.MaxBatchSize {
		http.Error(w, "batch size exceeds limit", http.StatusBadRequest)
		return
	}

	results := make([]CheckResponse, 0, len(req.URLs))
	for _, url := range req.URLs {
		blocked, blReason := h.blocklist.Check(r.Context(), url)
		catResult := h.categorizer.Categorize(r.Context(), url)

		resp := CheckResponse{
			URL:        url,
			Domain:     catResult.Domain,
			Categories: catResult.Categories,
		}

		if blocked {
			resp.Blocked = true
			resp.Reason = blReason
		} else if catResult.Blocked {
			resp.Blocked = true
			resp.Reason = catResult.Reason
		}

		results = append(results, resp)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(BatchCheckResponse{Results: results})
}

// ListBlocklists lists blocklist entries.
func (h *Handler) ListBlocklists(w http.ResponseWriter, r *http.Request) {
	entries := h.blocklist.GetBlocklist()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"entries": entries,
		"count":   len(entries),
	})
}

// AddBlocklistEntry adds an entry to blocklist.
func (h *Handler) AddBlocklistEntry(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Domain string `json:"domain"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	h.blocklist.AddBlock(req.Domain)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "added", "domain": req.Domain})
}

// RemoveBlocklistEntry removes an entry from blocklist.
func (h *Handler) RemoveBlocklistEntry(w http.ResponseWriter, r *http.Request) {
	entry := chi.URLParam(r, "entry")
	h.blocklist.RemoveBlock(entry)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "removed", "domain": entry})
}

// ReloadBlocklists reloads blocklists from disk.
func (h *Handler) ReloadBlocklists(w http.ResponseWriter, r *http.Request) {
	if err := h.blocklist.Reload(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "reloaded"})
}

// ListAllowlists lists allowlist entries.
func (h *Handler) ListAllowlists(w http.ResponseWriter, r *http.Request) {
	entries := h.blocklist.GetAllowlist()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"entries": entries,
		"count":   len(entries),
	})
}

// AddAllowlistEntry adds an entry to allowlist.
func (h *Handler) AddAllowlistEntry(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Domain string `json:"domain"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	h.blocklist.AddAllow(req.Domain)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "added", "domain": req.Domain})
}

// RemoveAllowlistEntry removes an entry from allowlist.
func (h *Handler) RemoveAllowlistEntry(w http.ResponseWriter, r *http.Request) {
	entry := chi.URLParam(r, "entry")
	h.blocklist.RemoveAllow(entry)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "removed", "domain": entry})
}

// ListCategories lists all categories.
func (h *Handler) ListCategories(w http.ResponseWriter, r *http.Request) {
	cats := h.categorizer.GetCategories()
	catInfo := make([]map[string]interface{}, 0, len(cats))

	for _, name := range cats {
		if info, ok := h.categorizer.GetCategoryInfo(name); ok {
			catInfo = append(catInfo, map[string]interface{}{
				"name":        info.Name,
				"description": info.Description,
				"blocked":     info.Blocked,
				"url_count":   len(info.URLs),
			})
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"categories": catInfo,
		"count":      len(catInfo),
	})
}

// ListCategoryURLs lists URLs in a category.
func (h *Handler) ListCategoryURLs(w http.ResponseWriter, r *http.Request) {
	category := chi.URLParam(r, "category")
	urls := h.categorizer.GetURLsInCategory(category, 100)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"category": category,
		"urls":     urls,
		"count":    len(urls),
	})
}

// BlockCategory blocks a category.
func (h *Handler) BlockCategory(w http.ResponseWriter, r *http.Request) {
	category := chi.URLParam(r, "category")
	if ok := h.categorizer.SetCategoryBlocked(category, true); !ok {
		http.Error(w, "category not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "blocked", "category": category})
}

// AllowCategory allows a category.
func (h *Handler) AllowCategory(w http.ResponseWriter, r *http.Request) {
	category := chi.URLParam(r, "category")
	if ok := h.categorizer.SetCategoryBlocked(category, false); !ok {
		http.Error(w, "category not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "allowed", "category": category})
}

// GetStats returns filter statistics.
func (h *Handler) GetStats(w http.ResponseWriter, r *http.Request) {
	blStats := h.blocklist.GetStats()
	catStats := h.categorizer.GetStats()

	stats := map[string]interface{}{
		"blocklist":  blStats,
		"categorizer": catStats,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}
