import Card from '../components/Card';

export default function VPN() {
  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gold-400">VPN</h1>
        <p className="text-dark-400 mt-1">Virtual Private Network configuration</p>
      </div>

      <Card title="VPN Tunnels">
        <p className="text-dark-400">
          VPN management coming soon. This page will allow you to configure
          site-to-site tunnels, remote access VPN, and WireGuard/IPSec settings.
        </p>
      </Card>
    </div>
  );
}
