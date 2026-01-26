import { test, expect } from '@playwright/test';
import {
  generateTestUser,
  registerUser,
  waitForLiveView,
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
      await waitForLiveView(page);

      // Check page heading
      await expect(page.getByRole('heading', { name: 'Settings', level: 1 })).toBeVisible();

      // Check tabs exist - they are links in a nav
      await expect(page.getByRole('link', { name: /Integrations/i })).toBeVisible();
      await expect(page.getByRole('link', { name: /Account/i })).toBeVisible();
    });

    test('should default to integrations tab', async ({ page }) => {
      await page.goto('/settings');
      await waitForLiveView(page);

      // Integrations tab should be active (has indigo color)
      const integrationsTab = page.getByRole('link', { name: /Integrations/i });
      await expect(integrationsTab).toHaveClass(/text-indigo-600/);

      // Should show Connected Services section (card header)
      await expect(page.getByText('Connected Services')).toBeVisible();
    });
  });

  test.describe('Integrations Tab', () => {
    test('should display available services', async ({ page }) => {
      await page.goto('/settings/integrations');
      await waitForLiveView(page);

      // Should show Connected Services header
      await expect(page.getByText('Connected Services')).toBeVisible();

      // Google Contacts should be available
      await expect(page.getByText('Google Contacts')).toBeVisible();
    });

    test('should show Connect button for disconnected services', async ({ page }) => {
      await page.goto('/settings/integrations');
      await waitForLiveView(page);

      // Google should have a Connect button (assuming not connected)
      const connectButton = page.getByRole('button', { name: /Connect/i }).first();
      await expect(connectButton).toBeVisible();
    });

    test('should show import history section', async ({ page }) => {
      await page.goto('/settings/integrations');
      await waitForLiveView(page);

      // Should show Import History section
      await expect(page.getByText('Import History')).toBeVisible();

      // For a new user, should show empty state
      await expect(page.getByRole('heading', { name: 'No imports yet' })).toBeVisible();
    });

    test('should have correct authorization link for Google', async ({ page }) => {
      await page.goto('/settings/integrations');
      await waitForLiveView(page);

      // The Connect button should link to the authorization endpoint
      // The structure is: service card with Google Contacts text, containing a link with Connect button
      const googleConnectLink = page.locator('a', { has: page.getByRole('button', { name: /Connect/i }) });

      // Check the href points to the Google authorization
      const href = await googleConnectLink.first().getAttribute('href');
      expect(href).toContain('/integrations/google_contacts/authorize');
    });
  });

  test.describe('Account Tab', () => {
    test('should display account information', async ({ page }) => {
      await page.goto('/settings/account');
      await waitForLiveView(page);

      // Account tab should be active
      const accountTab = page.getByRole('link', { name: /Account/i });
      await expect(accountTab).toHaveClass(/text-indigo-600/);

      // Should show Account Information header
      await expect(page.getByText('Account Information')).toBeVisible();

      // Should show user info fields
      await expect(page.getByText('Email')).toBeVisible();
      await expect(page.getByText('Name')).toBeVisible();
      await expect(page.getByText('Member since')).toBeVisible();
    });

    test('should show current user email', async ({ page }) => {
      // Register a new user with known credentials
      const user = generateTestUser('account-view');
      await registerUser(page, user);

      await page.goto('/settings/account');
      await waitForLiveView(page);

      // Should display the user's email
      await expect(page.getByText(user.email)).toBeVisible();
    });

    test('should show not set for missing name', async ({ page }) => {
      await page.goto('/settings/account');
      await waitForLiveView(page);

      // New user won't have a name set
      await expect(page.getByText('Not set')).toBeVisible();
    });
  });

  test.describe('Tab Navigation', () => {
    test('should switch to account tab', async ({ page }) => {
      await page.goto('/settings');
      await waitForLiveView(page);

      // Click Account tab
      await page.getByRole('link', { name: /Account/i }).click();

      // URL should update
      await expect(page).toHaveURL('/settings/account');

      // Account content should be visible
      await expect(page.getByText('Account Information')).toBeVisible();
    });

    test('should switch back to integrations tab', async ({ page }) => {
      await page.goto('/settings/account');
      await waitForLiveView(page);

      // Click Integrations tab
      await page.getByRole('link', { name: /Integrations/i }).click();

      // URL should update
      await expect(page).toHaveURL('/settings/integrations');

      // Integrations content should be visible
      await expect(page.getByText('Connected Services')).toBeVisible();
    });

    test('should preserve tab on page reload', async ({ page }) => {
      await page.goto('/settings/account');
      await waitForLiveView(page);

      // Reload page
      await page.reload();
      await waitForLiveView(page);

      // Should still be on account tab
      await expect(page).toHaveURL('/settings/account');
      await expect(page.getByText('Account Information')).toBeVisible();
    });

    test('should direct link to integrations tab', async ({ page }) => {
      await page.goto('/settings/integrations');
      await waitForLiveView(page);

      // Should show integrations content
      await expect(page.getByText('Connected Services')).toBeVisible();

      // Integrations tab should be active
      const integrationsTab = page.getByRole('link', { name: /Integrations/i });
      await expect(integrationsTab).toHaveClass(/text-indigo-600/);
    });
  });
});
