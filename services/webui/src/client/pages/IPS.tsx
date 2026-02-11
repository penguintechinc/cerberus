import Card from '../components/Card';

export default function IPS() {
  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gold-400">IPS / IDS</h1>
        <p className="text-dark-400 mt-1">Intrusion Prevention and Detection System</p>
      </div>

      <Card title="Intrusion Prevention">
        <p className="text-dark-400">
          IPS/IDS management coming soon. This page will allow you to configure
          threat detection rules, signature updates, and alert policies.
        </p>
      </Card>
    </div>
  );
}
