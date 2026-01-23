import { useState, useEffect } from 'react';
import { AlertTriangle, Shield, RefreshCw, Download, Filter, Eye } from 'lucide-react';

interface IPSAlert {
  id: number;
  timestamp: string;
  src_ip: string;
  src_port: number;
  dest_ip: string;
  dest_port: number;
  protocol: string;
  signature: string;
  signature_id: number;
  severity: number;
  category: string;
  action: string;
}

interface IPSCategory {
  id: number;
  name: string;
  enabled: boolean;
  rule_count: number;
}

interface IPSStats {
  total_alerts: number;
  alerts_today: number;
  blocked_today: number;
  top_signatures: { signature: string; count: number }[];
  top_sources: { ip: string; count: number }[];
}

const API_URL = '/api/v1';

export default function IPS() {
  const [alerts, setAlerts] = useState<IPSAlert[]>([]);
  const [categories, setCategories] = useState<IPSCategory[]>([]);
  const [stats, setStats] = useState<IPSStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'alerts' | 'rules' | 'categories'>('alerts');
  const [selectedAlert, setSelectedAlert] = useState<IPSAlert | null>(null);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const [alertsRes, categoriesRes, statsRes] = await Promise.all([
        fetch(`${API_URL}/ips/alerts?limit=100`),
        fetch(`${API_URL}/ips/categories`),
        fetch(`${API_URL}/ips/stats`)
      ]);
      if (alertsRes.ok) setAlerts(await alertsRes.json());
      if (categoriesRes.ok) setCategories(await categoriesRes.json());
      if (statsRes.ok) setStats(await statsRes.json());
    } catch (error) {
      console.error('Failed to fetch IPS data:', error);
    } finally {
      setLoading(false);
    }
  };

  const toggleCategory = async (id: number, enabled: boolean) => {
    try {
      await fetch(`${API_URL}/ips/categories/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ enabled: !enabled })
      });
      fetchData();
    } catch (error) {
      console.error('Failed to toggle category:', error);
    }
  };

  const getSeverityColor = (severity: number) => {
    switch (severity) {
      case 1: return 'text-red-400 bg-red-900/30';
      case 2: return 'text-orange-400 bg-orange-900/30';
      case 3: return 'text-yellow-400 bg-yellow-900/30';
      default: return 'text-blue-400 bg-blue-900/30';
    }
  };

  const getSeverityLabel = (severity: number) => {
    switch (severity) {
      case 1: return 'Critical';
      case 2: return 'High';
      case 3: return 'Medium';
      default: return 'Low';
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gold-400">Loading IPS data...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Shield className="w-8 h-8 text-gold-400" />
          <h1 className="text-2xl font-bold text-white">Intrusion Prevention</h1>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={fetchData}
            className="flex items-center gap-2 px-4 py-2 bg-dark-700 text-white rounded-lg hover:bg-dark-600 transition-colors"
          >
            <RefreshCw className="w-4 h-4" />
            Refresh
          </button>
          <button className="flex items-center gap-2 px-4 py-2 bg-dark-700 text-white rounded-lg hover:bg-dark-600 transition-colors">
            <Download className="w-4 h-4" />
            Update Rules
          </button>
        </div>
      </div>

      {/* Stats Cards */}
      {stats && (
        <div className="grid grid-cols-4 gap-4">
          <div className="bg-dark-800 rounded-lg p-4 border border-dark-700">
            <div className="text-sm text-gray-400">Total Alerts</div>
            <div className="text-2xl font-bold text-white">{stats.total_alerts.toLocaleString()}</div>
          </div>
          <div className="bg-dark-800 rounded-lg p-4 border border-dark-700">
            <div className="text-sm text-gray-400">Alerts Today</div>
            <div className="text-2xl font-bold text-yellow-400">{stats.alerts_today.toLocaleString()}</div>
          </div>
          <div className="bg-dark-800 rounded-lg p-4 border border-dark-700">
            <div className="text-sm text-gray-400">Blocked Today</div>
            <div className="text-2xl font-bold text-red-400">{stats.blocked_today.toLocaleString()}</div>
          </div>
          <div className="bg-dark-800 rounded-lg p-4 border border-dark-700">
            <div className="text-sm text-gray-400">Active Categories</div>
            <div className="text-2xl font-bold text-green-400">
              {categories.filter(c => c.enabled).length}/{categories.length}
            </div>
          </div>
        </div>
      )}

      {/* Tabs */}
      <div className="border-b border-dark-700">
        <nav className="flex gap-4">
          {(['alerts', 'rules', 'categories'] as const).map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-4 py-2 font-medium transition-colors ${
                activeTab === tab
                  ? 'text-gold-400 border-b-2 border-gold-400'
                  : 'text-gray-400 hover:text-white'
              }`}
            >
              {tab.charAt(0).toUpperCase() + tab.slice(1)}
            </button>
          ))}
        </nav>
      </div>

      {/* Alerts Tab */}
      {activeTab === 'alerts' && (
        <div className="bg-dark-800 rounded-lg border border-dark-700 overflow-hidden">
          <table className="w-full">
            <thead className="bg-dark-900">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Time</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Severity</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Source</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Destination</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Signature</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Action</th>
                <th className="px-4 py-3 text-right text-xs font-medium text-gray-400 uppercase">Details</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-dark-700">
              {alerts.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-8 text-center text-gray-500">
                    No alerts found
                  </td>
                </tr>
              ) : (
                alerts.map(alert => (
                  <tr key={alert.id} className="hover:bg-dark-700/50">
                    <td className="px-4 py-3 text-gray-400 text-sm">
                      {new Date(alert.timestamp).toLocaleString()}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-1 rounded text-xs font-medium ${getSeverityColor(alert.severity)}`}>
                        {getSeverityLabel(alert.severity)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm">
                      <div className="text-gray-300">{alert.src_ip}</div>
                      <div className="text-gray-500">:{alert.src_port}</div>
                    </td>
                    <td className="px-4 py-3 text-sm">
                      <div className="text-gray-300">{alert.dest_ip}</div>
                      <div className="text-gray-500">:{alert.dest_port}</div>
                    </td>
                    <td className="px-4 py-3">
                      <div className="text-sm text-white truncate max-w-xs">{alert.signature}</div>
                      <div className="text-xs text-gray-500">SID: {alert.signature_id}</div>
                    </td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-1 rounded text-xs font-medium ${
                        alert.action === 'blocked' ? 'text-red-400 bg-red-900/30' : 'text-yellow-400 bg-yellow-900/30'
                      }`}>
                        {alert.action}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <button
                        onClick={() => setSelectedAlert(alert)}
                        className="p-1 text-gray-400 hover:text-gold-400"
                      >
                        <Eye className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* Categories Tab */}
      {activeTab === 'categories' && (
        <div className="grid grid-cols-2 gap-4">
          {categories.map(category => (
            <div
              key={category.id}
              className={`bg-dark-800 rounded-lg p-4 border ${
                category.enabled ? 'border-green-700' : 'border-dark-700'
              }`}
            >
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-white font-medium">{category.name}</div>
                  <div className="text-sm text-gray-500">{category.rule_count} rules</div>
                </div>
                <button
                  onClick={() => toggleCategory(category.id, category.enabled)}
                  className={`px-3 py-1 rounded text-sm font-medium ${
                    category.enabled
                      ? 'bg-green-900/30 text-green-400'
                      : 'bg-dark-700 text-gray-400'
                  }`}
                >
                  {category.enabled ? 'Enabled' : 'Disabled'}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Rules Tab */}
      {activeTab === 'rules' && (
        <div className="bg-dark-800 rounded-lg p-6 border border-dark-700 text-center text-gray-400">
          <Filter className="w-12 h-12 mx-auto mb-4 text-gray-600" />
          <p>Rule management coming soon</p>
          <p className="text-sm text-gray-500 mt-2">Configure individual Suricata rules</p>
        </div>
      )}
    </div>
  );
}
