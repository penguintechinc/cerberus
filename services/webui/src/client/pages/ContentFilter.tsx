import { useState, useEffect } from 'react';
import { Filter, Plus, Trash2, RefreshCw, Globe, Ban, Check, Search } from 'lucide-react';

interface Category {
  name: string;
  description: string;
  blocked: boolean;
  url_count: number;
}

interface BlocklistEntry {
  domain: string;
  type: 'block' | 'allow';
}

interface FilterStats {
  blocklist_size: number;
  allowlist_size: number;
  blocked_count: number;
  lookup_count: number;
}

const API_URL = '/api/v1';

export default function ContentFilter() {
  const [categories, setCategories] = useState<Category[]>([]);
  const [blocklist, setBlocklist] = useState<string[]>([]);
  const [allowlist, setAllowlist] = useState<string[]>([]);
  const [stats, setStats] = useState<FilterStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'categories' | 'blocklist' | 'allowlist' | 'test'>('categories');
  const [newDomain, setNewDomain] = useState('');
  const [testUrl, setTestUrl] = useState('');
  const [testResult, setTestResult] = useState<any>(null);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const [catRes, blRes, alRes, statsRes] = await Promise.all([
        fetch(`${API_URL}/filter/categories`),
        fetch(`${API_URL}/filter/blocklist`),
        fetch(`${API_URL}/filter/allowlist`),
        fetch(`${API_URL}/filter/stats`)
      ]);

      if (catRes.ok) {
        const data = await catRes.json();
        setCategories(data.categories || []);
      }
      if (blRes.ok) {
        const data = await blRes.json();
        setBlocklist(data.entries || []);
      }
      if (alRes.ok) {
        const data = await alRes.json();
        setAllowlist(data.entries || []);
      }
      if (statsRes.ok) {
        setStats(await statsRes.json());
      }
    } catch (error) {
      console.error('Failed to fetch filter data:', error);
    } finally {
      setLoading(false);
    }
  };

  const toggleCategory = async (name: string, blocked: boolean) => {
    try {
      await fetch(`${API_URL}/filter/categories/${name}/${blocked ? 'allow' : 'block'}`, {
        method: 'POST'
      });
      fetchData();
    } catch (error) {
      console.error('Failed to toggle category:', error);
    }
  };

  const addToList = async (type: 'blocklist' | 'allowlist') => {
    if (!newDomain) return;
    try {
      await fetch(`${API_URL}/filter/${type}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ domain: newDomain })
      });
      setNewDomain('');
      fetchData();
    } catch (error) {
      console.error('Failed to add domain:', error);
    }
  };

  const removeFromList = async (domain: string, type: 'blocklist' | 'allowlist') => {
    try {
      await fetch(`${API_URL}/filter/${type}/${domain}`, {
        method: 'DELETE'
      });
      fetchData();
    } catch (error) {
      console.error('Failed to remove domain:', error);
    }
  };

  const testUrlFilter = async () => {
    if (!testUrl) return;
    try {
      const res = await fetch(`${API_URL}/filter/check`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: testUrl })
      });
      if (res.ok) {
        setTestResult(await res.json());
      }
    } catch (error) {
      console.error('Failed to test URL:', error);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gold-400">Loading filter data...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Filter className="w-8 h-8 text-gold-400" />
          <h1 className="text-2xl font-bold text-white">Content Filter</h1>
        </div>
        <button
          onClick={fetchData}
          className="flex items-center gap-2 px-4 py-2 bg-dark-700 text-white rounded-lg hover:bg-dark-600 transition-colors"
        >
          <RefreshCw className="w-4 h-4" />
          Refresh
        </button>
      </div>

      {/* Stats */}
      {stats && (
        <div className="grid grid-cols-4 gap-4">
          <div className="bg-dark-800 rounded-lg p-4 border border-dark-700">
            <div className="text-sm text-gray-400">Blocked Domains</div>
            <div className="text-2xl font-bold text-red-400">{stats.blocklist_size.toLocaleString()}</div>
          </div>
          <div className="bg-dark-800 rounded-lg p-4 border border-dark-700">
            <div className="text-sm text-gray-400">Allowed Domains</div>
            <div className="text-2xl font-bold text-green-400">{stats.allowlist_size.toLocaleString()}</div>
          </div>
          <div className="bg-dark-800 rounded-lg p-4 border border-dark-700">
            <div className="text-sm text-gray-400">Requests Blocked</div>
            <div className="text-2xl font-bold text-yellow-400">{stats.blocked_count.toLocaleString()}</div>
          </div>
          <div className="bg-dark-800 rounded-lg p-4 border border-dark-700">
            <div className="text-sm text-gray-400">Total Lookups</div>
            <div className="text-2xl font-bold text-white">{stats.lookup_count.toLocaleString()}</div>
          </div>
        </div>
      )}

      {/* Tabs */}
      <div className="border-b border-dark-700">
        <nav className="flex gap-4">
          {(['categories', 'blocklist', 'allowlist', 'test'] as const).map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-4 py-2 font-medium transition-colors capitalize ${
                activeTab === tab
                  ? 'text-gold-400 border-b-2 border-gold-400'
                  : 'text-gray-400 hover:text-white'
              }`}
            >
              {tab}
            </button>
          ))}
        </nav>
      </div>

      {/* Categories Tab */}
      {activeTab === 'categories' && (
        <div className="grid grid-cols-2 gap-4">
          {categories.map(category => (
            <div
              key={category.name}
              className={`bg-dark-800 rounded-lg p-4 border ${
                category.blocked ? 'border-red-700' : 'border-dark-700'
              }`}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  {category.blocked ? (
                    <Ban className="w-5 h-5 text-red-400" />
                  ) : (
                    <Check className="w-5 h-5 text-green-400" />
                  )}
                  <div>
                    <div className="text-white font-medium capitalize">{category.name}</div>
                    <div className="text-sm text-gray-500">{category.description}</div>
                    <div className="text-xs text-gray-600">{category.url_count} URLs</div>
                  </div>
                </div>
                <button
                  onClick={() => toggleCategory(category.name, category.blocked)}
                  className={`px-3 py-1.5 rounded text-sm font-medium transition-colors ${
                    category.blocked
                      ? 'bg-red-900/30 text-red-400 hover:bg-red-900/50'
                      : 'bg-green-900/30 text-green-400 hover:bg-green-900/50'
                  }`}
                >
                  {category.blocked ? 'Blocked' : 'Allowed'}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Blocklist Tab */}
      {activeTab === 'blocklist' && (
        <div className="bg-dark-800 rounded-lg border border-dark-700">
          <div className="p-4 border-b border-dark-700">
            <div className="flex gap-2">
              <input
                type="text"
                value={newDomain}
                onChange={e => setNewDomain(e.target.value)}
                placeholder="Enter domain to block..."
                className="flex-1 px-3 py-2 bg-dark-900 border border-dark-600 rounded-lg text-white focus:border-gold-500 focus:outline-none"
              />
              <button
                onClick={() => addToList('blocklist')}
                className="px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-500 transition-colors"
              >
                <Plus className="w-4 h-4" />
              </button>
            </div>
          </div>
          <div className="divide-y divide-dark-700 max-h-96 overflow-y-auto">
            {blocklist.length === 0 ? (
              <div className="p-8 text-center text-gray-500">No blocked domains</div>
            ) : (
              blocklist.map((domain, idx) => (
                <div key={idx} className="flex items-center justify-between p-3 hover:bg-dark-700/50">
                  <div className="flex items-center gap-2">
                    <Ban className="w-4 h-4 text-red-400" />
                    <span className="text-gray-300">{domain}</span>
                  </div>
                  <button
                    onClick={() => removeFromList(domain, 'blocklist')}
                    className="p-1 text-gray-400 hover:text-red-400"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              ))
            )}
          </div>
        </div>
      )}

      {/* Allowlist Tab */}
      {activeTab === 'allowlist' && (
        <div className="bg-dark-800 rounded-lg border border-dark-700">
          <div className="p-4 border-b border-dark-700">
            <div className="flex gap-2">
              <input
                type="text"
                value={newDomain}
                onChange={e => setNewDomain(e.target.value)}
                placeholder="Enter domain to allow..."
                className="flex-1 px-3 py-2 bg-dark-900 border border-dark-600 rounded-lg text-white focus:border-gold-500 focus:outline-none"
              />
              <button
                onClick={() => addToList('allowlist')}
                className="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-500 transition-colors"
              >
                <Plus className="w-4 h-4" />
              </button>
            </div>
          </div>
          <div className="divide-y divide-dark-700 max-h-96 overflow-y-auto">
            {allowlist.length === 0 ? (
              <div className="p-8 text-center text-gray-500">No allowed domains</div>
            ) : (
              allowlist.map((domain, idx) => (
                <div key={idx} className="flex items-center justify-between p-3 hover:bg-dark-700/50">
                  <div className="flex items-center gap-2">
                    <Check className="w-4 h-4 text-green-400" />
                    <span className="text-gray-300">{domain}</span>
                  </div>
                  <button
                    onClick={() => removeFromList(domain, 'allowlist')}
                    className="p-1 text-gray-400 hover:text-red-400"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              ))
            )}
          </div>
        </div>
      )}

      {/* Test Tab */}
      {activeTab === 'test' && (
        <div className="bg-dark-800 rounded-lg border border-dark-700 p-6">
          <h3 className="text-lg font-semibold text-white mb-4">Test URL Filter</h3>
          <div className="flex gap-2 mb-4">
            <input
              type="text"
              value={testUrl}
              onChange={e => setTestUrl(e.target.value)}
              placeholder="Enter URL or domain to test..."
              className="flex-1 px-3 py-2 bg-dark-900 border border-dark-600 rounded-lg text-white focus:border-gold-500 focus:outline-none"
            />
            <button
              onClick={testUrlFilter}
              className="px-4 py-2 bg-gold-500 text-dark-950 rounded-lg hover:bg-gold-400 transition-colors"
            >
              <Search className="w-4 h-4" />
            </button>
          </div>
          {testResult && (
            <div className={`p-4 rounded-lg ${testResult.blocked ? 'bg-red-900/30' : 'bg-green-900/30'}`}>
              <div className="flex items-center gap-2 mb-2">
                {testResult.blocked ? (
                  <Ban className="w-5 h-5 text-red-400" />
                ) : (
                  <Check className="w-5 h-5 text-green-400" />
                )}
                <span className={`font-medium ${testResult.blocked ? 'text-red-400' : 'text-green-400'}`}>
                  {testResult.blocked ? 'BLOCKED' : 'ALLOWED'}
                </span>
              </div>
              <div className="text-sm text-gray-300">
                <div>Domain: {testResult.domain}</div>
                {testResult.reason && <div>Reason: {testResult.reason}</div>}
                {testResult.categories && (
                  <div>Categories: {testResult.categories.join(', ')}</div>
                )}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
