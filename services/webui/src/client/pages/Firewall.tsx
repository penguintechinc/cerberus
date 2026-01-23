import { useState, useEffect } from 'react';
import { Shield, Plus, Trash2, Edit, ChevronUp, ChevronDown, Power } from 'lucide-react';

interface FirewallRule {
  id: number;
  name: string;
  source_zone: string;
  dest_zone: string;
  source_ip: string;
  dest_ip: string;
  source_port: string;
  dest_port: string;
  protocol: string;
  action: string;
  enabled: boolean;
  priority: number;
  log_enabled: boolean;
}

interface Zone {
  id: number;
  name: string;
  type: string;
  interfaces: string;
}

const API_URL = '/api/v1';

export default function Firewall() {
  const [rules, setRules] = useState<FirewallRule[]>([]);
  const [zones, setZones] = useState<Zone[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);
  const [editingRule, setEditingRule] = useState<FirewallRule | null>(null);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const [rulesRes, zonesRes] = await Promise.all([
        fetch(`${API_URL}/firewall/rules`),
        fetch(`${API_URL}/firewall/zones`)
      ]);
      if (rulesRes.ok) setRules(await rulesRes.json());
      if (zonesRes.ok) setZones(await zonesRes.json());
    } catch (error) {
      console.error('Failed to fetch firewall data:', error);
    } finally {
      setLoading(false);
    }
  };

  const toggleRule = async (id: number, enabled: boolean) => {
    try {
      await fetch(`${API_URL}/firewall/rules/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ enabled: !enabled })
      });
      fetchData();
    } catch (error) {
      console.error('Failed to toggle rule:', error);
    }
  };

  const deleteRule = async (id: number) => {
    if (!confirm('Are you sure you want to delete this rule?')) return;
    try {
      await fetch(`${API_URL}/firewall/rules/${id}`, { method: 'DELETE' });
      fetchData();
    } catch (error) {
      console.error('Failed to delete rule:', error);
    }
  };

  const getActionColor = (action: string) => {
    switch (action) {
      case 'accept': return 'text-green-400 bg-green-900/30';
      case 'drop': return 'text-red-400 bg-red-900/30';
      case 'reject': return 'text-yellow-400 bg-yellow-900/30';
      default: return 'text-gray-400 bg-gray-900/30';
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gold-400">Loading firewall rules...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Shield className="w-8 h-8 text-gold-400" />
          <h1 className="text-2xl font-bold text-white">Firewall Rules</h1>
        </div>
        <button
          onClick={() => setShowAddModal(true)}
          className="flex items-center gap-2 px-4 py-2 bg-gold-500 text-dark-950 rounded-lg hover:bg-gold-400 transition-colors"
        >
          <Plus className="w-4 h-4" />
          Add Rule
        </button>
      </div>

      {/* Zones Summary */}
      <div className="grid grid-cols-4 gap-4">
        {zones.map(zone => (
          <div key={zone.id} className="bg-dark-800 rounded-lg p-4 border border-dark-700">
            <div className="text-sm text-gray-400 uppercase">{zone.type}</div>
            <div className="text-lg font-semibold text-white">{zone.name}</div>
            <div className="text-sm text-gray-500">{zone.interfaces || 'No interfaces'}</div>
          </div>
        ))}
      </div>

      {/* Rules Table */}
      <div className="bg-dark-800 rounded-lg border border-dark-700 overflow-hidden">
        <table className="w-full">
          <thead className="bg-dark-900">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">#</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Name</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Source</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Destination</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Protocol</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Action</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Status</th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-400 uppercase">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-dark-700">
            {rules.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-4 py-8 text-center text-gray-500">
                  No firewall rules configured
                </td>
              </tr>
            ) : (
              rules.map((rule, index) => (
                <tr key={rule.id} className={`hover:bg-dark-700/50 ${!rule.enabled ? 'opacity-50' : ''}`}>
                  <td className="px-4 py-3 text-gray-400">{index + 1}</td>
                  <td className="px-4 py-3 text-white font-medium">{rule.name}</td>
                  <td className="px-4 py-3">
                    <div className="text-sm text-gray-300">{rule.source_zone}</div>
                    <div className="text-xs text-gray-500">{rule.source_ip || 'any'}:{rule.source_port || '*'}</div>
                  </td>
                  <td className="px-4 py-3">
                    <div className="text-sm text-gray-300">{rule.dest_zone}</div>
                    <div className="text-xs text-gray-500">{rule.dest_ip || 'any'}:{rule.dest_port || '*'}</div>
                  </td>
                  <td className="px-4 py-3 text-gray-300">{rule.protocol?.toUpperCase() || 'ANY'}</td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-1 rounded text-xs font-medium ${getActionColor(rule.action)}`}>
                      {rule.action?.toUpperCase()}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => toggleRule(rule.id, rule.enabled)}
                      className={`p-1 rounded ${rule.enabled ? 'text-green-400' : 'text-gray-500'}`}
                    >
                      <Power className="w-4 h-4" />
                    </button>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <div className="flex items-center justify-end gap-2">
                      <button className="p-1 text-gray-400 hover:text-white">
                        <ChevronUp className="w-4 h-4" />
                      </button>
                      <button className="p-1 text-gray-400 hover:text-white">
                        <ChevronDown className="w-4 h-4" />
                      </button>
                      <button
                        onClick={() => setEditingRule(rule)}
                        className="p-1 text-gray-400 hover:text-gold-400"
                      >
                        <Edit className="w-4 h-4" />
                      </button>
                      <button
                        onClick={() => deleteRule(rule.id)}
                        className="p-1 text-gray-400 hover:text-red-400"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
