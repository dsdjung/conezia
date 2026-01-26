import { test, expect } from '@playwright/test';
import {
  generateTestUser,
  registerUser,
  waitForLiveView,
} from '../helpers/test-utils';

test.describe('Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    // Register and login a fresh user for each test
    const user = generateTestUser('dashboard');
    await registerUser(page, user);
  });

  test('should display dashboard after login', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    // Check welcome message
    await expect(page.getByRole('heading', { name: 'Welcome back!' })).toBeVisible();

    // Check stats cards exist (use .first() to avoid strict mode violations for elements that appear multiple times)
    await expect(page.getByText('Total Connections').first()).toBeVisible();
    await expect(page.getByText('Healthy').first()).toBeVisible();
    await expect(page.getByText('Needs Attention').first()).toBeVisible();
    await expect(page.getByText('Upcoming Reminders').first()).toBeVisible();
  });

  test('should display zero stats for new user', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    // New user should have 0 connections - find the card and check value
    // The stats card structure has title and then value as "0"
    const statsContainer = page.locator('.grid.grid-cols-1');
    await expect(statsContainer.getByText('0').first()).toBeVisible();
  });

  test('should display recent connections section', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    // Check Recent Connections text
    await expect(page.getByText('Recent Connections')).toBeVisible();

    // For a new user, should show empty state
    await expect(page.getByRole('heading', { name: 'No connections yet' })).toBeVisible();

    // Should have button to add connection
    await expect(page.getByRole('button', { name: 'Add Connection' }).first()).toBeVisible();
  });

  test('should display upcoming reminders section', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    // Check Upcoming Reminders text
    await expect(page.getByText('Upcoming Reminders').first()).toBeVisible();

    // For a new user, should show empty state
    await expect(page.getByRole('heading', { name: 'No upcoming reminders' })).toBeVisible();

    // Should have button to add reminder
    await expect(page.getByRole('button', { name: 'Add Reminder' })).toBeVisible();
  });

  test('should navigate to connections page from dashboard', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    // Click "View all" link in Recent Connections section
    await page.getByRole('link', { name: 'View all →' }).first().click();

    await expect(page).toHaveURL('/connections', { timeout: 5000 });
  });

  test('should navigate to reminders page from dashboard', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    // Click "View all" link in Upcoming Reminders section (second "View all")
    await page.getByRole('link', { name: 'View all →' }).nth(1).click();

    await expect(page).toHaveURL('/reminders', { timeout: 5000 });
  });

  test('should navigate to new connection from dashboard', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    // Click Add Connection button in the empty state
    await page.getByRole('link', { name: 'Add Connection' }).first().click();

    await expect(page).toHaveURL('/connections/new', { timeout: 5000 });
  });

  test('should navigate to new reminder from dashboard', async ({ page }) => {
    await page.goto('/');
    await waitForLiveView(page);

    // Click Add Reminder button in the empty state
    await page.getByRole('link', { name: 'Add Reminder' }).click();

    await expect(page).toHaveURL('/reminders/new', { timeout: 5000 });
  });

  test.describe('With Data', () => {
    test('should show connection in recent connections after creation', async ({ page }) => {
      // Create a connection first
      await page.goto('/connections/new');
      await waitForLiveView(page);

      const connectionName = `Dashboard Test ${Date.now()}`;
      await page.getByLabel('Name').fill(connectionName);
      await page.getByLabel('Entity Type').selectOption('person');
      await page.getByRole('button', { name: 'Save Connection' }).click();

      await expect(page).toHaveURL('/connections', { timeout: 10000 });

      // Go to dashboard
      await page.goto('/');
      await waitForLiveView(page);

      // Should show the connection in recent connections
      await expect(page.getByText(connectionName)).toBeVisible();
    });
  });
});
