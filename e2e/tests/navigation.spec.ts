import { test, expect } from '@playwright/test';
import {
  generateTestUser,
  registerUser,
  waitForLiveView,
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
      await waitForLiveView(page);

      // Navigation is in the sidebar (nav element)
      const nav = page.locator('nav');

      // Should have Dashboard link
      await expect(nav.getByRole('link', { name: /Dashboard/i })).toBeVisible();

      // Should have Connections link
      await expect(nav.getByRole('link', { name: /Connections/i })).toBeVisible();

      // Should have Reminders link
      await expect(nav.getByRole('link', { name: /Reminders/i })).toBeVisible();

      // Should have Settings link
      await expect(nav.getByRole('link', { name: /Settings/i })).toBeVisible();
    });

    test('should display app name in sidebar', async ({ page }) => {
      await page.goto('/');
      await waitForLiveView(page);

      // Conezia branding in sidebar
      await expect(page.getByText('Conezia').first()).toBeVisible();
    });

    test('should navigate to connections from navbar', async ({ page }) => {
      await page.goto('/');
      await waitForLiveView(page);

      // Find nav link (not the "Add Connection" button)
      const navLink = page.locator('nav').getByRole('link', { name: /Connections/i });
      await navLink.click();

      await expect(page).toHaveURL('/connections');
      await expect(page.getByRole('heading', { name: 'Connections', level: 1 })).toBeVisible();
    });

    test('should navigate to reminders from navbar', async ({ page }) => {
      await page.goto('/');
      await waitForLiveView(page);

      const navLink = page.locator('nav').getByRole('link', { name: /Reminders/i });
      await navLink.click();

      await expect(page).toHaveURL('/reminders');
      await expect(page.getByRole('heading', { name: 'Reminders', level: 1 })).toBeVisible();
    });

    test('should navigate to settings from navbar', async ({ page }) => {
      await page.goto('/');
      await waitForLiveView(page);

      const navLink = page.locator('nav').getByRole('link', { name: /Settings/i });
      await navLink.click();

      await expect(page).toHaveURL('/settings');
      await expect(page.getByRole('heading', { name: 'Settings', level: 1 })).toBeVisible();
    });

    test('should navigate to dashboard from navbar', async ({ page }) => {
      await page.goto('/connections');
      await waitForLiveView(page);

      // Click on Dashboard link in nav
      const homeLink = page.locator('nav').getByRole('link', { name: /Dashboard/i });
      await homeLink.click();

      await expect(page).toHaveURL('/');
      await expect(page.getByRole('heading', { name: 'Welcome back!' })).toBeVisible();
    });
  });

  test.describe('User Menu', () => {
    test('should display user menu button', async ({ page }) => {
      await page.goto('/');
      await waitForLiveView(page);

      // User menu button is in the header
      await expect(page.locator('#user-menu-button')).toBeVisible();
    });

    test('should show user initials', async ({ page }) => {
      await page.goto('/');
      await waitForLiveView(page);

      // User avatar shows initials
      const avatar = page.locator('#user-menu-button .rounded-full');
      await expect(avatar).toBeVisible();
    });

    test('should open user dropdown on click', async ({ page }) => {
      await page.goto('/');
      await waitForLiveView(page);

      // Click user menu button
      await page.locator('#user-menu-button').click();

      // Dropdown should become visible
      const dropdown = page.locator('#user-dropdown-menu');
      await expect(dropdown).not.toHaveClass(/hidden/);

      // Sign out link should be visible
      await expect(dropdown.getByRole('link', { name: /Sign out/i })).toBeVisible();
    });
  });

  test.describe('Breadcrumbs and Context Navigation', () => {
    test('should navigate back from connection detail', async ({ page }) => {
      // Create a connection
      await page.goto('/connections');
      await waitForLiveView(page);
      await page.getByRole('button', { name: 'Add Connection' }).first().click();

      const connectionName = `Nav Test ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(connectionName);
      await page.getByLabel('Entity Type').selectOption('person');
      await page.getByRole('button', { name: 'Save Connection' }).click();
      await expect(page.getByRole('heading', { name: 'New Connection' })).not.toBeVisible({ timeout: 5000 });

      // Navigate to connection detail by clicking the name
      await page.getByText(connectionName).click();
      await expect(page).toHaveURL(/\/connections\/[a-f0-9-]+/);

      // Navigate back using the nav link
      const navLink = page.locator('nav').getByRole('link', { name: /Connections/i });
      await navLink.click();

      await expect(page).toHaveURL('/connections');
    });
  });

  test.describe('Deep Linking', () => {
    test('should handle direct URL to connections', async ({ page }) => {
      await page.goto('/connections');
      await waitForLiveView(page);

      await expect(page.getByRole('heading', { name: 'Connections', level: 1 })).toBeVisible();
    });

    test('should handle direct URL to reminders', async ({ page }) => {
      await page.goto('/reminders');
      await waitForLiveView(page);

      await expect(page.getByRole('heading', { name: 'Reminders', level: 1 })).toBeVisible();
    });

    test('should handle direct URL to settings tab', async ({ page }) => {
      await page.goto('/settings/account');
      await waitForLiveView(page);

      await expect(page.getByText('Account Information')).toBeVisible();
    });

    test('should handle direct URL to new connection', async ({ page }) => {
      await page.goto('/connections/new');
      await waitForLiveView(page);

      await expect(page.getByRole('heading', { name: 'New Connection' })).toBeVisible();
    });

    test('should handle direct URL to new reminder', async ({ page }) => {
      await page.goto('/reminders/new');
      await waitForLiveView(page);

      await expect(page.getByRole('heading', { name: 'New Reminder' })).toBeVisible();
    });
  });

  test.describe('Browser History', () => {
    test('should support browser back button', async ({ page }) => {
      await page.goto('/');
      await waitForLiveView(page);

      await page.goto('/connections');
      await waitForLiveView(page);

      await page.goto('/reminders');
      await waitForLiveView(page);

      // Go back
      await page.goBack();
      await expect(page).toHaveURL('/connections');

      // Go back again
      await page.goBack();
      await expect(page).toHaveURL('/');
    });

    test('should support browser forward button', async ({ page }) => {
      await page.goto('/');
      await waitForLiveView(page);

      await page.goto('/connections');
      await waitForLiveView(page);

      // Go back
      await page.goBack();
      await expect(page).toHaveURL('/');

      // Go forward
      await page.goForward();
      await expect(page).toHaveURL('/connections');
    });
  });
});
