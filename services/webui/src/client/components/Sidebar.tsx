import { useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import { SidebarMenu } from '@penguintechinc/react-libs';
import type { MenuCategory, SidebarColorConfig } from '@penguintechinc/react-libs';
import {
  LayoutDashboard,
  User,
  Shield,
  AlertTriangle,
  Lock,
  Globe,
  Settings,
  Users,
  LogOut,
} from 'lucide-react';

interface SidebarProps {
  collapsed: boolean;
  onToggle: () => void;
}

const categories: MenuCategory[] = [
  {
    items: [
      { name: 'Dashboard', href: '/', icon: LayoutDashboard },
      { name: 'Profile', href: '/profile', icon: User },
    ],
  },
  {
    header: 'Security',
    collapsible: true,
    items: [
      { name: 'Firewall', href: '/firewall', icon: Shield, roles: ['admin', 'maintainer'] },
      { name: 'IPS/IDS', href: '/ips', icon: AlertTriangle, roles: ['admin', 'maintainer'] },
      { name: 'VPN', href: '/vpn', icon: Lock, roles: ['admin', 'maintainer'] },
      { name: 'Content Filter', href: '/filter', icon: Globe, roles: ['admin', 'maintainer'] },
    ],
  },
  {
    header: 'Management',
    items: [
      { name: 'Settings', href: '/settings', icon: Settings, roles: ['admin', 'maintainer'] },
    ],
  },
  {
    header: 'Administration',
    items: [
      { name: 'Users', href: '/users', icon: Users, roles: ['admin'] },
    ],
  },
];

const cerberusColors: SidebarColorConfig = {
  sidebarBackground: 'bg-dark-900',
  sidebarBorder: 'border-dark-700',
  logoSectionBorder: 'border-dark-700',
  categoryHeaderText: 'text-dark-400',
  menuItemText: 'text-dark-300',
  menuItemHover: 'hover:bg-dark-800 hover:text-gold-300',
  menuItemActive: 'bg-gold-500/20',
  menuItemActiveText: 'text-gold-400',
  collapseIndicator: 'text-gold-400',
  footerBorder: 'border-dark-700',
  footerButtonText: 'text-dark-300',
  footerButtonHover: 'hover:bg-dark-800 hover:text-gold-300',
  scrollbarTrack: 'bg-dark-900',
  scrollbarThumb: 'bg-dark-600',
  scrollbarThumbHover: 'hover:bg-dark-500',
};

export default function Sidebar({ collapsed, onToggle }: SidebarProps) {
  const location = useLocation();
  const navigate = useNavigate();
  const { user, logout } = useAuth();

  const footerItems = [
    { name: 'Logout', href: '#logout', icon: LogOut },
  ];

  const handleNavigate = (href: string) => {
    if (href === '#logout') {
      logout();
      return;
    }
    navigate(href);
  };

  return (
    <SidebarMenu
      logo={
        <span className="text-xl font-bold text-gold-gradient">
          {collapsed ? '' : 'Cerberus'}
        </span>
      }
      categories={categories}
      currentPath={location.pathname}
      onNavigate={handleNavigate}
      footerItems={footerItems}
      userRole={user?.role}
      colors={cerberusColors}
    />
  );
}
