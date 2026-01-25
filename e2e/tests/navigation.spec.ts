import { test, expect } from '@playwright/test';
import {
  generateTestUser,
  registerUser,
} from '../helpers/test-utils';

test.describe('Navigation', () => {
  test.beforeEach(async ({ page }) => {
    // Register and login a fresh user for each test
    const user = generateTestUser('navigation');
    await registerUser(page, user);
  });

  test.describe('Main Navigation', () => {
    test('should have navigation bar with main links', async ({ page }) => {
      await page.goto('/');

      // Should have Dashboard/Home link
      await expect(page.getByRole('link', { name: /dashboard|home/i })).toBeVisible();

      // Should have Connections link
      await expect(page.getByRole('link', { name: /connections/i })).toBeVisible();

      // Should have Reminders link
      await expect(page.getByRole('link', { name: /reminders/i })).toBeVisible();

      // Should have Settings link
      await expect(page.getByRole('link', { name: /settings/i })).toBeVisible();
    });

    test('should navigate to connections from navbar', async ({ page }) => {
      await page.goto('/');

      // Find nav link (not the "Add Connection" button)
      const navLink = page.locator('nav').getByRole('link', { name: /connections/i });
      await navLink.click();

      await expect(page).toHaveURL('/connections');
    });

    test('should navigate to reminders from navbar', async ({ page }) => {
      await page.goto('/');

      const navLink = page.locator('nav').getByRole('link', { name: /reminders/i });
      await navLink.click();

      await expect(page).toHaveURL('/reminders');
    });

    test('should navigate to settings from navbar', async ({ page }) => {
      await page.goto('/');

      const navLink = page.locator('nav').getByRole('link', { name: /settings/i });
      await navLink.click();

      await expect(page).toHaveURL('/settings');
    });

    test('should navigate to dashboard from logo or home', async ({ page }) => {
      await page.goto('/connections');

      // Click on logo or home link
      const homeLink = page.locator('nav').getByRole('link', { name: /conezia|dashboard|home/i }).first();
      await homeLink.click();

      await expect(page).toHaveURL('/');
    });
  });

  test.describe('Breadcrumbs and Context Navigation', () => {
    test('should navigate back from connection detail', async ({ page }) => {
      // Create a connection
      await page.goto('/connections');
      await page.getByRole('link', { name: /add connection/i }).click();

      const connectionName = `Nav Test ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(connectionName);
      await page.getByRole('button', { name: /save|create/i }).click();
      await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });

      // Navigate to connection detail
      await page.getByText(connectionName).click();
      await expect(page).toHaveURL(/\/connections\/[a-f0-9-]+/);

      // Find and click back/connections link
      const backLink = page.getByRole('link', { name: /connections|back/i });
      await backLink.click();

      await expect(page).toHaveURL('/connections');
    });
  });

  test.describe('Deep Linking', () => {
    test('should handle direct URL to connections', async ({ page }) => {
      await page.goto('/connections');

      await expect(page.getByRole('heading', { name: /connections/i })).toBeVisible();
    });

    test('should handle direct URL to reminders', async ({ page }) => {
      await page.goto('/reminders');

      await expect(page.getByRole('heading', { name: /reminders/i })).toBeVisible();
    });

    test('should handle direct URL to settings tab', async ({ page }) => {
      await page.goto('/settings/account');

      await expect(page.getByText(/account information/i)).toBeVisible();
    });
  });

  test.describe('Browser History', () => {
    test('should support browser back button', async ({ page }) => {
      await page.goto('/');
      await page.goto('/connections');
      await page.goto('/reminders');

      // Go back
      await page.goBack();
      await expect(page).toHaveURL('/connections');

      // Go back again
      await page.goBack();
      await expect(page).toHaveURL('/');
    });

    test('should support browser forward button', async ({ page }) => {
      await page.goto('/');
      await page.goto('/connections');

      // Go back
      await page.goBack();
      await expect(page).toHaveURL('/');

      // Go forward
      await page.goForward();
      await expect(page).toHaveURL('/connections');
    });
  });
});
