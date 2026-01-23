// Cerberus SSL Inspector - SSL/TLS MITM Proxy
package proxy

import (
	"bufio"
	"crypto/tls"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/penguintechinc/cerberus/cerberus-ssl-inspector/internal/certs"
	"github.com/penguintechinc/cerberus/cerberus-ssl-inspector/internal/config"
)

// Connection represents an active connection.
type Connection struct {
	ID        string
	Host      string
	StartTime time.Time
	BytesIn   int64
	BytesOut  int64
}

// Proxy is the SSL/TLS MITM proxy.
type Proxy struct {
	cfg       *config.Config
	caManager *certs.CAManager
	listener  net.Listener

	// Bypass rules
	bypassDomains map[string]struct{}
	bypassMu      sync.RWMutex

	// Active connections
	connections   map[string]*Connection
	connectionsMu sync.RWMutex
	connCounter   int64

	// Stats
	statsLock        sync.Mutex
	totalConnections int64
	activeConns      int64
	bytesIn          int64
	bytesOut         int64
	bypassedConns    int64

	// Control
	running bool
	stopCh  chan struct{}
}

// New creates a new SSL proxy.
func New(cfg *config.Config, caManager *certs.CAManager) (*Proxy, error) {
	p := &Proxy{
		cfg:           cfg,
		caManager:     caManager,
		bypassDomains: make(map[string]struct{}),
		connections:   make(map[string]*Connection),
		stopCh:        make(chan struct{}),
	}

	// Add configured bypass domains
	for _, domain := range cfg.BypassDomains {
		p.bypassDomains[strings.ToLower(domain)] = struct{}{}
	}

	return p, nil
}

// Start starts the SSL proxy.
func (p *Proxy) Start() error {
	listener, err := net.Listen("tcp", p.cfg.ProxyListenAddr)
	if err != nil {
		return fmt.Errorf("failed to start listener: %w", err)
	}

	p.listener = listener
	p.running = true

	for p.running {
		conn, err := listener.Accept()
		if err != nil {
			if !p.running {
				return nil
			}
			log.Printf("Accept error: %v", err)
			continue
		}

		go p.handleConnection(conn)
	}

	return nil
}

// Stop stops the SSL proxy.
func (p *Proxy) Stop() {
	p.running = false
	close(p.stopCh)
	if p.listener != nil {
		p.listener.Close()
	}
}

// AddBypass adds a domain to the bypass list.
func (p *Proxy) AddBypass(domain string) {
	p.bypassMu.Lock()
	p.bypassDomains[strings.ToLower(domain)] = struct{}{}
	p.bypassMu.Unlock()
}

// RemoveBypass removes a domain from the bypass list.
func (p *Proxy) RemoveBypass(domain string) {
	p.bypassMu.Lock()
	delete(p.bypassDomains, strings.ToLower(domain))
	p.bypassMu.Unlock()
}

// GetBypassList returns the bypass domain list.
func (p *Proxy) GetBypassList() []string {
	p.bypassMu.RLock()
	defer p.bypassMu.RUnlock()

	list := make([]string, 0, len(p.bypassDomains))
	for domain := range p.bypassDomains {
		list = append(list, domain)
	}
	return list
}

// GetActiveConnections returns active connections.
func (p *Proxy) GetActiveConnections() []*Connection {
	p.connectionsMu.RLock()
	defer p.connectionsMu.RUnlock()

	conns := make([]*Connection, 0, len(p.connections))
	for _, conn := range p.connections {
		conns = append(conns, conn)
	}
	return conns
}

// GetStats returns proxy statistics.
func (p *Proxy) GetStats() map[string]int64 {
	p.statsLock.Lock()
	defer p.statsLock.Unlock()

	return map[string]int64{
		"total_connections":  p.totalConnections,
		"active_connections": p.activeConns,
		"bytes_in":           p.bytesIn,
		"bytes_out":          p.bytesOut,
		"bypassed_conns":     p.bypassedConns,
	}
}

func (p *Proxy) handleConnection(clientConn net.Conn) {
	defer clientConn.Close()

	// Set timeouts
	clientConn.SetDeadline(time.Now().Add(time.Duration(p.cfg.ReadTimeout) * time.Second))

	// Read the first line to get the CONNECT request
	reader := bufio.NewReader(clientConn)
	req, err := http.ReadRequest(reader)
	if err != nil {
		return
	}

	if req.Method != http.MethodConnect {
		// Not a CONNECT request, respond with error
		resp := &http.Response{
			StatusCode: http.StatusMethodNotAllowed,
			ProtoMajor: 1,
			ProtoMinor: 1,
		}
		resp.Write(clientConn)
		return
	}

	host := req.Host
	if !strings.Contains(host, ":") {
		host = host + ":443"
	}

	// Track connection
	connID := fmt.Sprintf("%d", atomic.AddInt64(&p.connCounter, 1))
	conn := &Connection{
		ID:        connID,
		Host:      host,
		StartTime: time.Now(),
	}

	p.connectionsMu.Lock()
	p.connections[connID] = conn
	p.connectionsMu.Unlock()

	p.statsLock.Lock()
	p.totalConnections++
	p.activeConns++
	p.statsLock.Unlock()

	defer func() {
		p.connectionsMu.Lock()
		delete(p.connections, connID)
		p.connectionsMu.Unlock()

		p.statsLock.Lock()
		p.activeConns--
		p.statsLock.Unlock()
	}()

	// Check if domain should be bypassed
	hostOnly := strings.Split(host, ":")[0]
	if p.shouldBypass(hostOnly) {
		p.handleBypass(clientConn, host)
		p.statsLock.Lock()
		p.bypassedConns++
		p.statsLock.Unlock()
		return
	}

	// Perform MITM
	p.handleMITM(clientConn, hostOnly, conn)
}

func (p *Proxy) shouldBypass(host string) bool {
	p.bypassMu.RLock()
	defer p.bypassMu.RUnlock()

	host = strings.ToLower(host)

	// Check exact match
	if _, ok := p.bypassDomains[host]; ok {
		return true
	}

	// Check parent domains
	parts := strings.Split(host, ".")
	for i := 1; i < len(parts); i++ {
		parent := strings.Join(parts[i:], ".")
		if _, ok := p.bypassDomains[parent]; ok {
			return true
		}
	}

	return false
}

func (p *Proxy) handleBypass(clientConn net.Conn, host string) {
	// Connect to upstream
	upstreamConn, err := net.DialTimeout("tcp", host, time.Duration(p.cfg.ConnectTimeout)*time.Second)
	if err != nil {
		log.Printf("Failed to connect to %s: %v", host, err)
		return
	}
	defer upstreamConn.Close()

	// Send 200 Connection Established
	clientConn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))

	// Tunnel the connection
	p.tunnel(clientConn, upstreamConn)
}

func (p *Proxy) handleMITM(clientConn net.Conn, host string, conn *Connection) {
	// Get certificate for host
	cert, err := p.caManager.GetCertForHost(host)
	if err != nil {
		log.Printf("Failed to get cert for %s: %v", host, err)
		return
	}

	// Connect to upstream
	upstreamConn, err := tls.DialWithDialer(
		&net.Dialer{Timeout: time.Duration(p.cfg.ConnectTimeout) * time.Second},
		"tcp",
		host+":443",
		&tls.Config{InsecureSkipVerify: true},
	)
	if err != nil {
		log.Printf("Failed to connect to %s: %v", host, err)
		return
	}
	defer upstreamConn.Close()

	// Send 200 Connection Established
	clientConn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))

	// Wrap client connection with TLS
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{*cert},
	}
	tlsClientConn := tls.Server(clientConn, tlsConfig)
	if err := tlsClientConn.Handshake(); err != nil {
		log.Printf("TLS handshake failed for %s: %v", host, err)
		return
	}
	defer tlsClientConn.Close()

	// Tunnel the decrypted connection
	p.tunnelWithStats(tlsClientConn, upstreamConn, conn)
}

func (p *Proxy) tunnel(clientConn, upstreamConn net.Conn) {
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		io.Copy(upstreamConn, clientConn)
	}()

	go func() {
		defer wg.Done()
		io.Copy(clientConn, upstreamConn)
	}()

	wg.Wait()
}

func (p *Proxy) tunnelWithStats(clientConn, upstreamConn net.Conn, conn *Connection) {
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		n, _ := io.Copy(upstreamConn, clientConn)
		atomic.AddInt64(&conn.BytesOut, n)
		p.statsLock.Lock()
		p.bytesOut += n
		p.statsLock.Unlock()
	}()

	go func() {
		defer wg.Done()
		n, _ := io.Copy(clientConn, upstreamConn)
		atomic.AddInt64(&conn.BytesIn, n)
		p.statsLock.Lock()
		p.bytesIn += n
		p.statsLock.Unlock()
	}()

	wg.Wait()
}
