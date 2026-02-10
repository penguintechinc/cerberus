/**
 * E2E test: Login flow via Playwright.
 *
 * Prerequisites:
 *   - All services running (make dev or docker-compose up)
 *   - Default admin user created (admin@example.com / changeme123)
 *
 * Run: npx playwright test tests/e2e/test_login_flow.spec.ts
 */
import { test, expect } from '@playwright/test';

const BASE_URL = process.env.WEBUI_URL || 'http://localhost:3000';

test.describe('Login Flow', () => {
  test('should show login page when not authenticated', async ({ page }) => {
    await page.goto(BASE_URL);
    // Should redirect to login
    await expect(page).toHaveURL(/\/login/);
    await expect(page.getByText('Cerberus NGFW')).toBeVisible();
  });

  test('should login with valid credentials', async ({ page }) => {
    await page.goto(`${BASE_URL}/login`);

    await page.fill('input[type="email"]', 'admin@example.com');
    await page.fill('input[type="password"]', 'changeme123');
    await page.click('button[type="submit"]');

    // Should redirect to dashboard
    await page.waitForURL(`${BASE_URL}/`);
    await expect(page.getByText('Dashboard')).toBeVisible();
  });

  test('should show error for invalid credentials', async ({ page }) => {
    await page.goto(`${BASE_URL}/login`);

    await page.fill('input[type="email"]', 'bad@example.com');
    await page.fill('input[type="password"]', 'wrongpassword');
    await page.click('button[type="submit"]');

    await expect(page.getByText('Invalid email or password')).toBeVisible();
  });

  test('should logout successfully', async ({ page }) => {
    // Login first
    await page.goto(`${BASE_URL}/login`);
    await page.fill('input[type="email"]', 'admin@example.com');
    await page.fill('input[type="password"]', 'changeme123');
    await page.click('button[type="submit"]');
    await page.waitForURL(`${BASE_URL}/`);

    // Click logout
    await page.click('button:has-text("Logout")');

    // Should redirect to login
    await expect(page).toHaveURL(/\/login/);
  });
});
