import { test, expect } from '@playwright/test';
import {
  generateTestUser,
  registerUser,
} from '../helpers/test-utils';

test.describe('Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    // Register and login a fresh user for each test
    const user = generateTestUser('dashboard');
    await registerUser(page, user);
  });

  test('should display dashboard after login', async ({ page }) => {
    await page.goto('/');

    // Check welcome message
    await expect(page.getByRole('heading', { name: /welcome back/i })).toBeVisible();

    // Check stats cards
    await expect(page.getByText(/total connections/i)).toBeVisible();
    await expect(page.getByText(/healthy/i)).toBeVisible();
    await expect(page.getByText(/needs attention/i)).toBeVisible();
    await expect(page.getByText(/upcoming reminders/i)).toBeVisible();
  });

  test('should display zero stats for new user', async ({ page }) => {
    await page.goto('/');

    // New user should have 0 connections
    const totalConnections = page.locator('text=Total Connections').locator('..').locator('..');
    await expect(totalConnections.getByText('0')).toBeVisible();
  });

  test('should display recent connections section', async ({ page }) => {
    await page.goto('/');

    // Check Recent Connections section
    await expect(page.getByText(/recent connections/i)).toBeVisible();

    // For a new user, should show empty state
    await expect(page.getByText(/no connections yet/i)).toBeVisible();

    // Should have link to add connection
    await expect(page.getByRole('link', { name: /add connection/i })).toBeVisible();
  });

  test('should display upcoming reminders section', async ({ page }) => {
    await page.goto('/');

    // Check Upcoming Reminders section
    await expect(page.getByText(/upcoming reminders/i)).toBeVisible();

    // For a new user, should show empty state
    await expect(page.getByText(/no upcoming reminders/i)).toBeVisible();

    // Should have link to add reminder
    await expect(page.getByRole('link', { name: /add reminder/i })).toBeVisible();
  });

  test('should navigate to connections page from dashboard', async ({ page }) => {
    await page.goto('/');

    // Click "View all" link in Recent Connections
    const viewAllConnections = page.locator('text=Recent Connections')
      .locator('..')
      .getByRole('link', { name: /view all/i });

    await viewAllConnections.click();

    await expect(page).toHaveURL('/connections');
  });

  test('should navigate to reminders page from dashboard', async ({ page }) => {
    await page.goto('/');

    // Click "View all" link in Upcoming Reminders
    const viewAllReminders = page.locator('text=Upcoming Reminders')
      .locator('..')
      .getByRole('link', { name: /view all/i });

    await viewAllReminders.click();

    await expect(page).toHaveURL('/reminders');
  });

  test('should navigate to new connection from dashboard', async ({ page }) => {
    await page.goto('/');

    await page.getByRole('link', { name: /add connection/i }).first().click();

    await expect(page).toHaveURL('/connections/new');
  });

  test('should navigate to new reminder from dashboard', async ({ page }) => {
    await page.goto('/');

    await page.getByRole('link', { name: /add reminder/i }).first().click();

    await expect(page).toHaveURL('/reminders/new');
  });

  test.describe('With Data', () => {
    test('should show connection in recent connections after creation', async ({ page }) => {
      // Create a connection first
      await page.goto('/connections');
      await page.getByRole('link', { name: /add connection/i }).click();

      const connectionName = `Dashboard Test ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(connectionName);
      await page.getByRole('button', { name: /save|create/i }).click();
      await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });

      // Go to dashboard
      await page.goto('/');

      // Should show the connection in recent connections
      await expect(page.getByText(connectionName)).toBeVisible();
    });
  });
});
