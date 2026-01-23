// Cerberus SSL Inspector - HTTP Handlers
package handler

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/penguintechinc/cerberus/cerberus-ssl-inspector/internal/certs"
	"github.com/penguintechinc/cerberus/cerberus-ssl-inspector/internal/config"
	"github.com/penguintechinc/cerberus/cerberus-ssl-inspector/internal/proxy"
)

// Handler handles HTTP requests.
type Handler struct {
	cfg       *config.Config
	caManager *certs.CAManager
	proxy     *proxy.Proxy
}

// New creates a new handler.
func New(cfg *config.Config, caManager *certs.CAManager, p *proxy.Proxy) *Handler {
	return &Handler{
		cfg:       cfg,
		caManager: caManager,
		proxy:     p,
	}
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

// GetCACert returns the CA certificate info.
func (h *Handler) GetCACert(w http.ResponseWriter, r *http.Request) {
	fingerprint := h.caManager.GetCAFingerprint()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"fingerprint": fingerprint,
		"common_name": h.cfg.CACommonName,
		"org":         h.cfg.CAOrg,
	})
}

// DownloadCACert returns the CA certificate for download.
func (h *Handler) DownloadCACert(w http.ResponseWriter, r *http.Request) {
	certPEM := h.caManager.GetCACertPEM()

	w.Header().Set("Content-Type", "application/x-pem-file")
	w.Header().Set("Content-Disposition", "attachment; filename=cerberus-ca.crt")
	w.Write(certPEM)
}

// RegenerateCA regenerates the CA certificate.
func (h *Handler) RegenerateCA(w http.ResponseWriter, r *http.Request) {
	if err := h.caManager.RegenerateCA(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	fingerprint := h.caManager.GetCAFingerprint()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":      "regenerated",
		"fingerprint": fingerprint,
	})
}

// GetCAFingerprint returns only the CA fingerprint.
func (h *Handler) GetCAFingerprint(w http.ResponseWriter, r *http.Request) {
	fingerprint := h.caManager.GetCAFingerprint()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"fingerprint": fingerprint,
	})
}

// ListBypassRules lists bypass domains.
func (h *Handler) ListBypassRules(w http.ResponseWriter, r *http.Request) {
	domains := h.proxy.GetBypassList()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"domains": domains,
		"count":   len(domains),
	})
}

// AddBypassRule adds a bypass domain.
func (h *Handler) AddBypassRule(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Domain string `json:"domain"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	h.proxy.AddBypass(req.Domain)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "added",
		"domain": req.Domain,
	})
}

// RemoveBypassRule removes a bypass domain.
func (h *Handler) RemoveBypassRule(w http.ResponseWriter, r *http.Request) {
	domain := chi.URLParam(r, "domain")
	h.proxy.RemoveBypass(domain)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "removed",
		"domain": domain,
	})
}

// GetSettings returns current settings.
func (h *Handler) GetSettings(w http.ResponseWriter, r *http.Request) {
	settings := map[string]interface{}{
		"inspect_https":   h.cfg.InspectHTTPS,
		"log_connections": h.cfg.LogConnections,
		"connect_timeout": h.cfg.ConnectTimeout,
		"read_timeout":    h.cfg.ReadTimeout,
		"write_timeout":   h.cfg.WriteTimeout,
		"max_connections": h.cfg.MaxConnections,
		"filter_url":      h.cfg.FilterURL,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(settings)
}

// UpdateSettings updates settings (limited runtime changes).
func (h *Handler) UpdateSettings(w http.ResponseWriter, r *http.Request) {
	var req struct {
		InspectHTTPS   *bool `json:"inspect_https,omitempty"`
		LogConnections *bool `json:"log_connections,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if req.InspectHTTPS != nil {
		h.cfg.InspectHTTPS = *req.InspectHTTPS
	}
	if req.LogConnections != nil {
		h.cfg.LogConnections = *req.LogConnections
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "updated"})
}

// GetStats returns proxy statistics.
func (h *Handler) GetStats(w http.ResponseWriter, r *http.Request) {
	proxyStats := h.proxy.GetStats()
	caStats := h.caManager.GetStats()

	stats := map[string]interface{}{
		"proxy": proxyStats,
		"ca":    caStats,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

// GetActiveConnections returns active connections.
func (h *Handler) GetActiveConnections(w http.ResponseWriter, r *http.Request) {
	conns := h.proxy.GetActiveConnections()

	connList := make([]map[string]interface{}, 0, len(conns))
	for _, c := range conns {
		connList = append(connList, map[string]interface{}{
			"id":         c.ID,
			"host":       c.Host,
			"start_time": c.StartTime,
			"bytes_in":   c.BytesIn,
			"bytes_out":  c.BytesOut,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"connections": connList,
		"count":       len(connList),
	})
}
