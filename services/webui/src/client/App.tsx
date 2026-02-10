import { Routes, Route, Navigate } from 'react-router-dom';
import { AppConsoleVersion } from '@penguintechinc/react-libs';
import { useAuth } from './hooks/useAuth';
import Layout from './components/Layout';
import ProtectedRoute from './components/ProtectedRoute';
import RoleGuard from './components/RoleGuard';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Users from './pages/Users';
import UserDetail from './pages/UserDetail';
import Profile from './pages/Profile';
import Settings from './pages/Settings';
import Firewall from './pages/Firewall';
import IPS from './pages/IPS';
import VPN from './pages/VPN';
import ContentFilter from './pages/ContentFilter';

function App() {
  const { isAuthenticated, isLoading } = useAuth();

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-dark-950">
        <div className="text-gold-400 text-xl">Loading...</div>
      </div>
    );
  }

  return (
    <>
      <AppConsoleVersion
        appName="Cerberus NGFW"
        webuiVersion={import.meta.env.VITE_VERSION || '1.0.0'}
        webuiBuildEpoch={Number(import.meta.env.VITE_BUILD_TIME) || 0}
        environment={import.meta.env.MODE}
        apiStatusUrl="/api/v1/status"
        webuiEmoji="🛡️"
        styleConfig={{ primaryColor: '#fbbf24', accentColor: '#60a5fa' }}
      />
      <Routes>
        {/* Public routes */}
        <Route
          path="/login"
          element={isAuthenticated ? <Navigate to="/" replace /> : <Login />}
        />

        {/* Protected routes with layout */}
        <Route
          element={
            <ProtectedRoute>
              <Layout />
            </ProtectedRoute>
          }
        >
          {/* Dashboard - all authenticated users */}
          <Route path="/" element={<Dashboard />} />
          <Route path="/dashboard" element={<Navigate to="/" replace />} />

          {/* NGFW Pages - Maintainer and Admin */}
          <Route
            path="/firewall"
            element={
              <RoleGuard allowedRoles={['admin', 'maintainer']}>
                <Firewall />
              </RoleGuard>
            }
          />
          <Route
            path="/ips"
            element={
              <RoleGuard allowedRoles={['admin', 'maintainer']}>
                <IPS />
              </RoleGuard>
            }
          />
          <Route
            path="/vpn"
            element={
              <RoleGuard allowedRoles={['admin', 'maintainer']}>
                <VPN />
              </RoleGuard>
            }
          />
          <Route
            path="/filter"
            element={
              <RoleGuard allowedRoles={['admin', 'maintainer']}>
                <ContentFilter />
              </RoleGuard>
            }
          />

          {/* Profile - all authenticated users */}
          <Route path="/profile" element={<Profile />} />

          {/* Settings - Maintainer and Admin */}
          <Route
            path="/settings"
            element={
              <RoleGuard allowedRoles={['admin', 'maintainer']}>
                <Settings />
              </RoleGuard>
            }
          />

          {/* User management - Admin only */}
          <Route
            path="/users"
            element={
              <RoleGuard allowedRoles={['admin']}>
                <Users />
              </RoleGuard>
            }
          />
          <Route
            path="/users/:id"
            element={
              <RoleGuard allowedRoles={['admin']}>
                <UserDetail />
              </RoleGuard>
            }
          />
        </Route>

        {/* Catch all - redirect to dashboard or login */}
        <Route
          path="*"
          element={<Navigate to={isAuthenticated ? '/' : '/login'} replace />}
        />
      </Routes>
    </>
  );
}

export default App;
