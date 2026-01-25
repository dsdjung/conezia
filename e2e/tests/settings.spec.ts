import { test, expect } from '@playwright/test';
import {
  generateTestUser,
  registerUser,
} from '../helpers/test-utils';

test.describe('Settings', () => {
  test.beforeEach(async ({ page }) => {
    // Register and login a fresh user for each test
    const user = generateTestUser('settings');
    await registerUser(page, user);
  });

  test.describe('Settings Page', () => {
    test('should display settings page with tabs', async ({ page }) => {
      await page.goto('/settings');

      // Check page heading
      await expect(page.getByRole('heading', { name: /settings/i })).toBeVisible();

      // Check tabs exist
      await expect(page.getByRole('link', { name: /integrations/i })).toBeVisible();
      await expect(page.getByRole('link', { name: /account/i })).toBeVisible();
    });

    test('should default to integrations tab', async ({ page }) => {
      await page.goto('/settings');

      // Integrations tab should be active
      const integrationsTab = page.getByRole('link', { name: /integrations/i });
      await expect(integrationsTab).toHaveClass(/indigo/); // Active tab has indigo color

      // Should show Connected Services section
      await expect(page.getByText(/connected services/i)).toBeVisible();
    });
  });

  test.describe('Integrations Tab', () => {
    test('should display available services', async ({ page }) => {
      await page.goto('/settings/integrations');

      // Should show services list
      await expect(page.getByText(/connected services/i)).toBeVisible();

      // Google Contacts should be available
      await expect(page.getByText(/google contacts/i)).toBeVisible();
    });

    test('should show Connect button for disconnected services', async ({ page }) => {
      await page.goto('/settings/integrations');

      // Google should have a Connect button (assuming not connected)
      const connectButton = page.getByRole('link', { name: /connect/i }).first();
      await expect(connectButton).toBeVisible();
    });

    test('should show import history section', async ({ page }) => {
      await page.goto('/settings/integrations');

      // Should show Import History section
      await expect(page.getByText(/import history/i)).toBeVisible();

      // For a new user, should show empty state
      await expect(page.getByText(/no imports yet/i)).toBeVisible();
    });

    test('should initiate Google connection', async ({ page }) => {
      await page.goto('/settings/integrations');

      // Click Connect for Google
      const googleService = page.locator('text=Google Contacts').locator('..');
      const connectButton = googleService.getByRole('link', { name: /connect/i });

      // Note: We don't actually complete OAuth in E2E tests
      // Just verify the link points to the right place
      const href = await connectButton.getAttribute('href');
      expect(href).toContain('/integrations/google_contacts/authorize');
    });
  });

  test.describe('Account Tab', () => {
    test('should display account information', async ({ page }) => {
      await page.goto('/settings/account');

      // Account tab should be active
      await expect(page.getByText(/account information/i)).toBeVisible();

      // Should show user email
      await expect(page.getByText(/email/i)).toBeVisible();

      // Should show member since
      await expect(page.getByText(/member since/i)).toBeVisible();
    });

    test('should show current user email', async ({ page }) => {
      const user = generateTestUser('account-view');
      await registerUser(page, user);

      await page.goto('/settings/account');

      // Should display the user's email
      await expect(page.getByText(user.email)).toBeVisible();
    });
  });

  test.describe('Tab Navigation', () => {
    test('should switch to account tab', async ({ page }) => {
      await page.goto('/settings');

      // Click Account tab
      await page.getByRole('link', { name: /account/i }).click();

      // URL should update
      await expect(page).toHaveURL('/settings/account');

      // Account content should be visible
      await expect(page.getByText(/account information/i)).toBeVisible();
    });

    test('should switch back to integrations tab', async ({ page }) => {
      await page.goto('/settings/account');

      // Click Integrations tab
      await page.getByRole('link', { name: /integrations/i }).click();

      // URL should update
      await expect(page).toHaveURL('/settings/integrations');

      // Integrations content should be visible
      await expect(page.getByText(/connected services/i)).toBeVisible();
    });

    test('should preserve tab on page reload', async ({ page }) => {
      await page.goto('/settings/account');

      // Reload page
      await page.reload();

      // Should still be on account tab
      await expect(page).toHaveURL('/settings/account');
      await expect(page.getByText(/account information/i)).toBeVisible();
    });
  });
});
