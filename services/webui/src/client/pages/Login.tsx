import { useNavigate, useLocation } from 'react-router-dom';
import { LoginPageBuilder } from '@penguintechinc/react-libs';
import type { LoginResponse, LoginColorConfig } from '@penguintechinc/react-libs';
import { Shield } from 'lucide-react';
import { useAuthStore } from '../hooks/useAuth';
import { setTokens } from '../lib/api';

interface LocationState {
  from?: { pathname: string };
}

const cerberusLoginColors: Partial<LoginColorConfig> = {
  pageBackground: 'bg-dark-950',
  cardBackground: 'bg-dark-800',
  cardBorder: 'border-dark-700',
  inputBackground: 'bg-dark-900',
  inputBorder: 'border-dark-700',
  inputFocusBorder: 'focus:border-gold-500',
  inputText: 'text-white',
  labelText: 'text-gold-400',
  primaryButton: 'bg-gold-500 hover:bg-gold-600 text-dark-950',
  primaryButtonText: 'text-dark-950',
  linkText: 'text-gold-400',
  linkHover: 'hover:text-gold-300',
  errorBackground: 'bg-red-900/30',
  errorBorder: 'border-red-700',
  errorText: 'text-red-400',
  titleText: 'text-gold-400',
  subtitleText: 'text-dark-400',
  footerText: 'text-dark-500',
};

export default function Login() {
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as LocationState)?.from?.pathname || '/';

  const handleSuccess = (response: LoginResponse) => {
    const data = response as LoginResponse & {
      access_token?: string;
      refresh_token?: string;
    };

    const accessToken = data.token || data.access_token || '';
    const refreshToken = data.refreshToken || data.refresh_token || '';

    setTokens(accessToken, refreshToken);

    useAuthStore.setState({
      user: data.user
        ? {
            id: typeof data.user.id === 'string' ? parseInt(data.user.id, 10) : data.user.id as number,
            email: data.user.email || '',
            full_name: (data.user as Record<string, unknown>).full_name as string || data.user.name || '',
            role: (data.user.roles?.[0] || 'viewer') as 'admin' | 'maintainer' | 'viewer',
            is_active: true,
            created_at: new Date().toISOString(),
            updated_at: null,
          }
        : null,
      accessToken,
      refreshToken,
      isAuthenticated: true,
      isLoading: false,
    });

    navigate(from, { replace: true });
  };

  return (
    <LoginPageBuilder
      api={{
        loginUrl: '/api/v1/auth/login',
        method: 'POST',
      }}
      branding={{
        appName: 'Cerberus NGFW',
        logo: <Shield className="h-12 w-12 text-gold-400" />,
        tagline: 'Network Security Gateway',
      }}
      onSuccess={handleSuccess}
      colors={cerberusLoginColors}
      showForgotPassword={false}
      showSignUp={false}
      showRememberMe={false}
    />
  );
}
