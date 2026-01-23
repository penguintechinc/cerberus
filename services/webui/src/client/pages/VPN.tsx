import { useState, useEffect } from 'react';
import { Lock, Plus, Trash2, Download, Users, Server, RefreshCw, Copy, QrCode } from 'lucide-react';

interface VPNServer {
  name: string;
  type: string;
  status: string;
  connected_clients: number;
  public_key?: string;
}

interface VPNClient {
  name: string;
  created: string;
  public_key?: string;
  address?: string;
}

const API_URL = '/api/v1';

export default function VPN() {
  const [servers, setServers] = useState<VPNServer[]>([]);
  const [clients, setClients] = useState<{ [key: string]: VPNClient[] }>({});
  const [loading, setLoading] = useState(true);
  const [activeServer, setActiveServer] = useState<string>('wireguard');
  const [showAddModal, setShowAddModal] = useState(false);
  const [newClientName, setNewClientName] = useState('');
  const [newClientPassword, setNewClientPassword] = useState('');
  const [clientConfig, setClientConfig] = useState<string | null>(null);
  const [qrCode, setQrCode] = useState<string | null>(null);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const statusRes = await fetch(`${API_URL}/vpn/status`);
      if (statusRes.ok) {
        const data = await statusRes.json();
        setServers(data.servers || []);
      }

      // Fetch clients for each server type
      const clientData: { [key: string]: VPNClient[] } = {};
      for (const type of ['wireguard', 'ipsec', 'openvpn']) {
        const res = await fetch(`${API_URL}/vpn/${type}/clients`);
        if (res.ok) {
          const data = await res.json();
          clientData[type] = data.clients || data.peers || data.users || [];
        }
      }
      setClients(clientData);
    } catch (error) {
      console.error('Failed to fetch VPN data:', error);
    } finally {
      setLoading(false);
    }
  };

  const addClient = async () => {
    try {
      let endpoint = '';
      let body: any = { name: newClientName };

      if (activeServer === 'wireguard') {
        endpoint = `${API_URL}/vpn/wireguard/peers`;
      } else if (activeServer === 'ipsec') {
        endpoint = `${API_URL}/vpn/ipsec/users`;
        body = { username: newClientName, password: newClientPassword };
      } else if (activeServer === 'openvpn') {
        endpoint = `${API_URL}/vpn/openvpn/clients`;
      }

      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });

      if (res.ok) {
        const data = await res.json();
        if (data.client_config) {
          setClientConfig(atob(data.client_config));
        }
        if (data.config) {
          setClientConfig(atob(data.config));
        }
        if (data.qr_code) {
          setQrCode(`data:image/png;base64,${data.qr_code}`);
        }
        fetchData();
      }
    } catch (error) {
      console.error('Failed to add client:', error);
    }
    setShowAddModal(false);
    setNewClientName('');
    setNewClientPassword('');
  };

  const removeClient = async (name: string) => {
    if (!confirm(`Remove client "${name}"?`)) return;

    try {
      let endpoint = '';
      if (activeServer === 'wireguard') {
        endpoint = `${API_URL}/vpn/wireguard/peers/${name}`;
      } else if (activeServer === 'ipsec') {
        endpoint = `${API_URL}/vpn/ipsec/users/${name}`;
      } else if (activeServer === 'openvpn') {
        endpoint = `${API_URL}/vpn/openvpn/clients/${name}`;
      }

      await fetch(endpoint, { method: 'DELETE' });
      fetchData();
    } catch (error) {
      console.error('Failed to remove client:', error);
    }
  };

  const downloadConfig = async (name: string) => {
    try {
      let endpoint = '';
      if (activeServer === 'wireguard') {
        endpoint = `${API_URL}/vpn/wireguard/peers/${name}/config`;
      } else if (activeServer === 'openvpn') {
        endpoint = `${API_URL}/vpn/openvpn/clients/${name}/config`;
      }

      const res = await fetch(endpoint);
      if (res.ok) {
        const data = await res.json();
        if (data.config) {
          setClientConfig(atob(data.config));
        }
        if (data.client_config) {
          setClientConfig(atob(data.client_config));
        }
      }
    } catch (error) {
      console.error('Failed to download config:', error);
    }
  };

  const getServerIcon = (type: string) => {
    switch (type) {
      case 'wireguard': return '🔐';
      case 'ipsec': return '🛡️';
      case 'openvpn': return '🔒';
      default: return '🌐';
    }
  };

  const getStatusColor = (status: string) => {
    return status === 'running' ? 'text-green-400' : 'text-red-400';
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gold-400">Loading VPN data...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Lock className="w-8 h-8 text-gold-400" />
          <h1 className="text-2xl font-bold text-white">VPN Gateway</h1>
        </div>
        <button
          onClick={fetchData}
          className="flex items-center gap-2 px-4 py-2 bg-dark-700 text-white rounded-lg hover:bg-dark-600 transition-colors"
        >
          <RefreshCw className="w-4 h-4" />
          Refresh
        </button>
      </div>

      {/* Server Status Cards */}
      <div className="grid grid-cols-3 gap-4">
        {servers.map(server => (
          <button
            key={server.type}
            onClick={() => setActiveServer(server.type)}
            className={`bg-dark-800 rounded-lg p-4 border text-left transition-colors ${
              activeServer === server.type ? 'border-gold-500' : 'border-dark-700 hover:border-dark-600'
            }`}
          >
            <div className="flex items-center justify-between mb-2">
              <span className="text-2xl">{getServerIcon(server.type)}</span>
              <span className={`text-sm ${getStatusColor(server.status)}`}>
                ● {server.status}
              </span>
            </div>
            <div className="text-lg font-semibold text-white">{server.name}</div>
            <div className="flex items-center gap-1 text-sm text-gray-400 mt-1">
              <Users className="w-4 h-4" />
              {server.connected_clients} connected
            </div>
          </button>
        ))}
      </div>

      {/* Clients Section */}
      <div className="bg-dark-800 rounded-lg border border-dark-700">
        <div className="flex items-center justify-between p-4 border-b border-dark-700">
          <h2 className="text-lg font-semibold text-white">
            {activeServer.charAt(0).toUpperCase() + activeServer.slice(1)} Clients
          </h2>
          <button
            onClick={() => setShowAddModal(true)}
            className="flex items-center gap-2 px-3 py-1.5 bg-gold-500 text-dark-950 rounded-lg hover:bg-gold-400 transition-colors text-sm"
          >
            <Plus className="w-4 h-4" />
            Add Client
          </button>
        </div>

        <div className="divide-y divide-dark-700">
          {(clients[activeServer] || []).length === 0 ? (
            <div className="p-8 text-center text-gray-500">
              No clients configured
            </div>
          ) : (
            (clients[activeServer] || []).map((client, idx) => (
              <div key={idx} className="flex items-center justify-between p-4 hover:bg-dark-700/50">
                <div>
                  <div className="text-white font-medium">{client.name}</div>
                  {client.address && (
                    <div className="text-sm text-gray-500">IP: {client.address}</div>
                  )}
                  <div className="text-xs text-gray-600">
                    Created: {new Date(client.created).toLocaleDateString()}
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  {activeServer !== 'ipsec' && (
                    <button
                      onClick={() => downloadConfig(client.name)}
                      className="p-2 text-gray-400 hover:text-gold-400 transition-colors"
                      title="Download Config"
                    >
                      <Download className="w-4 h-4" />
                    </button>
                  )}
                  <button
                    onClick={() => removeClient(client.name)}
                    className="p-2 text-gray-400 hover:text-red-400 transition-colors"
                    title="Remove Client"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      {/* Add Client Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-dark-800 rounded-lg p-6 w-full max-w-md border border-dark-700">
            <h3 className="text-lg font-semibold text-white mb-4">Add New Client</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm text-gray-400 mb-1">
                  {activeServer === 'ipsec' ? 'Username' : 'Client Name'}
                </label>
                <input
                  type="text"
                  value={newClientName}
                  onChange={e => setNewClientName(e.target.value)}
                  className="w-full px-3 py-2 bg-dark-900 border border-dark-600 rounded-lg text-white focus:border-gold-500 focus:outline-none"
                  placeholder="Enter name..."
                />
              </div>
              {activeServer === 'ipsec' && (
                <div>
                  <label className="block text-sm text-gray-400 mb-1">Password</label>
                  <input
                    type="password"
                    value={newClientPassword}
                    onChange={e => setNewClientPassword(e.target.value)}
                    className="w-full px-3 py-2 bg-dark-900 border border-dark-600 rounded-lg text-white focus:border-gold-500 focus:outline-none"
                    placeholder="Enter password..."
                  />
                </div>
              )}
            </div>
            <div className="flex justify-end gap-2 mt-6">
              <button
                onClick={() => setShowAddModal(false)}
                className="px-4 py-2 bg-dark-700 text-white rounded-lg hover:bg-dark-600 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={addClient}
                className="px-4 py-2 bg-gold-500 text-dark-950 rounded-lg hover:bg-gold-400 transition-colors"
              >
                Add Client
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Config Display Modal */}
      {clientConfig && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-dark-800 rounded-lg p-6 w-full max-w-2xl border border-dark-700">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-white">Client Configuration</h3>
              <button
                onClick={() => navigator.clipboard.writeText(clientConfig)}
                className="p-2 text-gray-400 hover:text-gold-400"
                title="Copy to clipboard"
              >
                <Copy className="w-4 h-4" />
              </button>
            </div>
            {qrCode && (
              <div className="flex justify-center mb-4">
                <img src={qrCode} alt="QR Code" className="w-48 h-48" />
              </div>
            )}
            <pre className="bg-dark-900 p-4 rounded-lg text-sm text-gray-300 overflow-x-auto max-h-64">
              {clientConfig}
            </pre>
            <div className="flex justify-end mt-4">
              <button
                onClick={() => {
                  setClientConfig(null);
                  setQrCode(null);
                }}
                className="px-4 py-2 bg-dark-700 text-white rounded-lg hover:bg-dark-600 transition-colors"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
