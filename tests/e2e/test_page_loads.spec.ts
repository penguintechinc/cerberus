/**
 * E2E Smoke Test: Page & Tab Loading
 *
 * Verifies every page and tab in the WebUI loads without errors.
 *
 * Prerequisites:
 *   - All services running (make dev or docker-compose up)
 *   - Default admin user created (admin@example.com / changeme123)
 *
 * Run: npx playwright test tests/e2e/test_page_loads.spec.ts
 */
import { test, expect, type Page, type ConsoleMessage } from '@playwright/test';

const BASE_URL = process.env.WEBUI_URL || 'http://localhost:3000';
const ADMIN_EMAIL = 'admin@example.com';
const ADMIN_PASSWORD = 'changeme123';

// ─── Helpers ──────────────────────────────────────────────

/** Collect console errors during a callback. */
async function collectConsoleErrors(
  page: Page,
  fn: () => Promise<void>,
): Promise<string[]> {
  const errors: string[] = [];
  const handler = (msg: ConsoleMessage) => {
    if (msg.type() === 'error') {
      errors.push(msg.text());
    }
  };
  page.on('console', handler);
  await fn();
  page.off('console', handler);
  return errors;
}

/** Login via API and inject tokens into localStorage so the app is authenticated. */
async function loginViaApi(page: Page, email: string, password: string) {
  const response = await page.request.post(`${BASE_URL}/api/v1/auth/login`, {
    data: { email, password },
  });

  if (!response.ok()) {
    // Fallback: login via UI if API auth endpoint differs
    await loginViaUi(page, email, password);
    return;
  }

  const body = await response.json();
  const accessToken = body.access_token;
  const refreshToken = body.refresh_token || '';

  // Inject auth state into localStorage (matches Zustand persist shape)
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
  await page.evaluate(
    ([token, refresh]) => {
      const state = {
        state: {
          accessToken: token,
          refreshToken: refresh,
          isAuthenticated: true,
          isLoading: false,
          user: null,
        },
        version: 0,
      };
      localStorage.setItem('auth-storage', JSON.stringify(state));
    },
    [accessToken, refreshToken],
  );
}

/** Fallback: login through the actual UI form. */
async function loginViaUi(page: Page, email: string, password: string) {
  await page.goto(`${BASE_URL}/login`);
  await page.fill('input[type="email"]', email);
  await page.fill('input[type="password"]', password);
  await page.click('button[type="submit"]');
  await page.waitForURL(`${BASE_URL}/`);
}

// ─── Public Routes ────────────────────────────────────────

test.describe('Public Routes', () => {
  test('login page renders', async ({ page }) => {
    await page.goto(`${BASE_URL}/login`);
    await expect(page.getByText('Cerberus NGFW')).toBeVisible();
  });

  test('unauthenticated user is redirected to login', async ({ page }) => {
    await page.goto(`${BASE_URL}/`);
    await expect(page).toHaveURL(/\/login/);
  });
});

// ─── Authenticated Page Loads ─────────────────────────────

test.describe('Authenticated Page Loads', () => {
  test.beforeEach(async ({ page }) => {
    await loginViaApi(page, ADMIN_EMAIL, ADMIN_PASSWORD);
  });

  const pages = [
    { path: '/', heading: 'Dashboard' },
    { path: '/profile', heading: 'Profile' },
    { path: '/firewall', heading: 'Firewall' },
    { path: '/ips', heading: 'IPS' },
    { path: '/vpn', heading: 'VPN' },
    { path: '/filter', heading: 'Content Filter' },
    { path: '/settings', heading: 'Settings' },
    { path: '/users', heading: 'Users' },
  ];

  for (const { path, heading } of pages) {
    test(`${path} — renders "${heading}" heading`, async ({ page }) => {
      const errors = await collectConsoleErrors(page, async () => {
        await page.goto(`${BASE_URL}${path}`, { waitUntil: 'networkidle' });
      });

      // Page heading visible
      await expect(page.getByRole('heading', { name: heading })).toBeVisible();

      // No JS console errors (filter out benign network errors from backends that may be down)
      const criticalErrors = errors.filter(
        (e) => !e.includes('net::ERR_') && !e.includes('Failed to fetch'),
      );
      expect(criticalErrors).toEqual([]);
    });
  }
});

// ─── Tab Navigation ───────────────────────────────────────

test.describe('Tab Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await loginViaApi(page, ADMIN_EMAIL, ADMIN_PASSWORD);
  });

  test('Dashboard tabs: Overview, System Status, Metrics', async ({ page }) => {
    await page.goto(`${BASE_URL}/`, { waitUntil: 'networkidle' });

    // Overview tab (default)
    await expect(page.getByText('Welcome')).toBeVisible();

    // System Status tab
    await page.click('button:has-text("System Status")');
    await expect(page.getByText('Flask Backend')).toBeVisible();

    // Metrics tab
    await page.click('button:has-text("Metrics")');
    await expect(page.getByText('System Metrics')).toBeVisible();
  });

  test('Settings tabs: General, Notifications, Security', async ({ page }) => {
    await page.goto(`${BASE_URL}/settings`, { waitUntil: 'networkidle' });

    // General tab (default)
    await expect(page.getByText('General Settings')).toBeVisible();

    // Notifications tab
    await page.click('button:has-text("Notifications")');
    await expect(page.getByText('Notification Settings')).toBeVisible();

    // Security tab
    await page.click('button:has-text("Security")');
    await expect(page.getByText('Security Settings')).toBeVisible();
  });
});

// ─── Role-Based Access ────────────────────────────────────

test.describe('Role-Based Access Control', () => {
  // These tests require a viewer user to exist.
  // If the viewer user doesn't exist, skip gracefully.
  const VIEWER_EMAIL = 'viewer@example.com';
  const VIEWER_PASSWORD = 'changeme123';

  test('viewer is redirected from /users to /', async ({ page }) => {
    // Try to login as viewer — skip if user doesn't exist
    const response = await page.request.post(`${BASE_URL}/api/v1/auth/login`, {
      data: { email: VIEWER_EMAIL, password: VIEWER_PASSWORD },
    });

    if (!response.ok()) {
      test.skip(true, 'Viewer user not available — skipping RBAC test');
      return;
    }

    await loginViaApi(page, VIEWER_EMAIL, VIEWER_PASSWORD);
    await page.goto(`${BASE_URL}/users`);

    // RoleGuard redirects unauthorized users to /
    await expect(page).toHaveURL(`${BASE_URL}/`);
  });

  test('viewer is redirected from /firewall to /', async ({ page }) => {
    const response = await page.request.post(`${BASE_URL}/api/v1/auth/login`, {
      data: { email: VIEWER_EMAIL, password: VIEWER_PASSWORD },
    });

    if (!response.ok()) {
      test.skip(true, 'Viewer user not available — skipping RBAC test');
      return;
    }

    await loginViaApi(page, VIEWER_EMAIL, VIEWER_PASSWORD);
    await page.goto(`${BASE_URL}/firewall`);

    await expect(page).toHaveURL(`${BASE_URL}/`);
  });
});
