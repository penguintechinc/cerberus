import Card from '../components/Card';

export default function Firewall() {
  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gold-400">Firewall</h1>
        <p className="text-dark-400 mt-1">Manage firewall rules and policies</p>
      </div>

      <Card title="Firewall Rules">
        <p className="text-dark-400">
          Firewall management coming soon. This page will allow you to configure
          inbound and outbound traffic rules, port forwarding, and zone-based policies.
        </p>
      </Card>
    </div>
  );
}
