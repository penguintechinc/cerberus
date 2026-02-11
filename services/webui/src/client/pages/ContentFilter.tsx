import Card from '../components/Card';

export default function ContentFilter() {
  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gold-400">Content Filter</h1>
        <p className="text-dark-400 mt-1">Web content filtering and URL categorization</p>
      </div>

      <Card title="Content Filtering Rules">
        <p className="text-dark-400">
          Content filtering coming soon. This page will allow you to configure
          URL categories, blocklists, and web access policies.
        </p>
      </Card>
    </div>
  );
}
