import { test, expect } from '@playwright/test';
import {
  generateTestUser,
  registerUser,
  waitForLiveView,
} from '../helpers/test-utils';

test.describe('Connections', () => {
  test.beforeEach(async ({ page }) => {
    // Register and login a fresh user for each test
    const user = generateTestUser('connections');
    await registerUser(page, user);
  });

  test.describe('Connections List', () => {
    test('should display empty state when no connections exist', async ({ page }) => {
      await page.goto('/connections');
      await waitForLiveView(page);

      // Check page title (use level 1 heading specifically)
      await expect(page.getByRole('heading', { name: 'Connections', level: 1 })).toBeVisible();

      // Check empty state message
      await expect(page.getByRole('heading', { name: 'No connections found' })).toBeVisible();
      await expect(page.getByText('Get started by adding your first connection.')).toBeVisible();

      // Check Add Connection button (there are multiple, use first)
      await expect(page.getByRole('button', { name: 'Add Connection' }).first()).toBeVisible();
    });

    test('should have search input', async ({ page }) => {
      await page.goto('/connections');
      await waitForLiveView(page);

      await expect(page.getByPlaceholder('Search connections...')).toBeVisible();
    });

    test('should have type filter dropdown', async ({ page }) => {
      await page.goto('/connections');
      await waitForLiveView(page);

      // Check for type filter select
      const typeFilter = page.locator('select[name="type"]');
      await expect(typeFilter).toBeVisible();

      // Verify options exist by checking the select contains them
      await expect(typeFilter.locator('option')).toHaveCount(3);

      // Verify we can select different options
      await typeFilter.selectOption('person');
      await typeFilter.selectOption('organization');
      await typeFilter.selectOption(''); // All types
    });
  });

  test.describe('Create Connection', () => {
    test('should open new connection modal', async ({ page }) => {
      await page.goto('/connections');
      await waitForLiveView(page);

      // Click Add Connection link (navigates to /connections/new)
      await page.getByRole('link', { name: 'Add Connection' }).first().click();

      // Wait for modal - the title is "New Connection"
      await expect(page.getByRole('heading', { name: 'New Connection' })).toBeVisible();

      // Check form fields
      await expect(page.getByLabel('Name')).toBeVisible();
      await expect(page.getByLabel('Entity Type')).toBeVisible();
    });

    test('should create a person connection successfully', async ({ page }) => {
      await page.goto('/connections/new');
      await waitForLiveView(page);

      // Wait for modal
      await expect(page.getByRole('heading', { name: 'New Connection' })).toBeVisible();

      // Fill in connection details
      const connectionName = `Test Person ${Date.now()}`;
      await page.getByLabel('Name').fill(connectionName);
      await page.getByLabel('Entity Type').selectOption('person');
      await page.getByLabel('Description').fill('A test connection');

      // Submit form
      await page.getByRole('button', { name: 'Save Connection' }).click();

      // Should redirect to connections list with flash message
      await expect(page).toHaveURL('/connections', { timeout: 10000 });

      // Connection should appear in the list
      await expect(page.getByText(connectionName)).toBeVisible({ timeout: 5000 });
    });

    test('should create an organization connection', async ({ page }) => {
      await page.goto('/connections/new');
      await waitForLiveView(page);

      await expect(page.getByRole('heading', { name: 'New Connection' })).toBeVisible();

      const connectionName = `Test Organization ${Date.now()}`;
      await page.getByLabel('Name').fill(connectionName);
      await page.getByLabel('Entity Type').selectOption('organization');

      await page.getByRole('button', { name: 'Save Connection' }).click();

      await expect(page).toHaveURL('/connections', { timeout: 10000 });
      await expect(page.getByText(connectionName)).toBeVisible({ timeout: 5000 });
    });

    test('should show validation error for empty name', async ({ page }) => {
      await page.goto('/connections/new');
      await waitForLiveView(page);

      await expect(page.getByRole('heading', { name: 'New Connection' })).toBeVisible();

      // Clear the name field and blur to trigger validation
      const nameField = page.getByLabel('Name');
      await nameField.fill('');

      // Submit form to trigger validation
      await page.getByRole('button', { name: 'Save Connection' }).click();

      // Wait a moment for LiveView to process
      await page.waitForTimeout(500);

      // Should show validation error - the form stays open on error
      await expect(page.getByRole('heading', { name: 'New Connection' })).toBeVisible();
    });

    test('should close modal when pressing escape', async ({ page }) => {
      await page.goto('/connections/new');
      await waitForLiveView(page);

      await expect(page.getByRole('heading', { name: 'New Connection' })).toBeVisible();

      // Press Escape to close modal
      await page.keyboard.press('Escape');

      // Modal should be closed, should be back at /connections
      await expect(page).toHaveURL('/connections', { timeout: 5000 });
      await expect(page.getByRole('heading', { name: 'New Connection' })).not.toBeVisible();
    });
  });

  test.describe('View Connection', () => {
    test('should navigate to connection detail page', async ({ page }) => {
      // First create a connection
      await page.goto('/connections/new');
      await waitForLiveView(page);

      const connectionName = `View Test ${Date.now()}`;
      await page.getByLabel('Name').fill(connectionName);
      await page.getByLabel('Entity Type').selectOption('person');
      await page.getByRole('button', { name: 'Save Connection' }).click();

      await expect(page).toHaveURL('/connections', { timeout: 10000 });
      await expect(page.getByText(connectionName)).toBeVisible({ timeout: 5000 });

      // Click on the connection link to view details
      await page.getByRole('link', { name: connectionName }).click();

      // Should navigate to detail page
      await expect(page).toHaveURL(/\/connections\/[a-f0-9-]+/, { timeout: 5000 });
    });
  });

  test.describe('Edit Connection', () => {
    test('should edit a connection successfully', async ({ page }) => {
      // Create a connection first
      await page.goto('/connections/new');
      await waitForLiveView(page);

      const originalName = `Edit Test ${Date.now()}`;
      await page.getByLabel('Name').fill(originalName);
      await page.getByLabel('Entity Type').selectOption('person');
      await page.getByRole('button', { name: 'Save Connection' }).click();

      await expect(page).toHaveURL('/connections', { timeout: 10000 });
      await expect(page.getByText(originalName)).toBeVisible({ timeout: 5000 });

      // Click edit button (has title="Edit")
      await page.locator('a[title="Edit"]').first().click();

      // Wait for edit form
      await expect(page.getByLabel('Name')).toBeVisible();

      // Update the name
      const updatedName = `Updated ${Date.now()}`;
      await page.getByLabel('Name').fill(updatedName);
      await page.getByRole('button', { name: 'Save Connection' }).click();

      // Verify update - should be back at connections list
      await expect(page).toHaveURL(/\/connections/, { timeout: 10000 });
      await expect(page.getByText(updatedName)).toBeVisible({ timeout: 5000 });
    });
  });

  test.describe('Delete Connection', () => {
    test('should delete a connection', async ({ page }) => {
      // Create a connection first
      await page.goto('/connections/new');
      await waitForLiveView(page);

      const connectionName = `Delete Test ${Date.now()}`;
      await page.getByLabel('Name').fill(connectionName);
      await page.getByLabel('Entity Type').selectOption('person');
      await page.getByRole('button', { name: 'Save Connection' }).click();

      await expect(page).toHaveURL('/connections', { timeout: 10000 });
      await expect(page.getByText(connectionName)).toBeVisible({ timeout: 5000 });

      // Set up dialog handler for confirmation
      page.on('dialog', dialog => dialog.accept());

      // Click delete button (has title="Delete")
      await page.locator('button[title="Delete"]').first().click();

      // Connection should be removed from list
      await expect(page.getByText(connectionName)).not.toBeVisible({ timeout: 5000 });
    });

    test('should show confirmation dialog before deleting', async ({ page }) => {
      // Create a connection
      await page.goto('/connections/new');
      await waitForLiveView(page);

      const connectionName = `Confirm Delete ${Date.now()}`;
      await page.getByLabel('Name').fill(connectionName);
      await page.getByLabel('Entity Type').selectOption('person');
      await page.getByRole('button', { name: 'Save Connection' }).click();

      await expect(page).toHaveURL('/connections', { timeout: 10000 });
      await expect(page.getByText(connectionName)).toBeVisible({ timeout: 5000 });

      // Set up dialog handler to dismiss (cancel delete)
      let dialogMessage = '';
      page.on('dialog', async dialog => {
        dialogMessage = dialog.message();
        await dialog.dismiss();
      });

      // Click delete
      await page.locator('button[title="Delete"]').first().click();

      // Verify dialog was shown
      expect(dialogMessage).toMatch(/sure|delete|confirm/i);

      // Connection should still exist (we dismissed the dialog)
      await expect(page.getByText(connectionName)).toBeVisible();
    });
  });

  test.describe('Search and Filter', () => {
    test('should filter connections by search term', async ({ page }) => {
      // Create multiple connections
      const names = ['Alice Smith', 'Bob Johnson'];

      for (const name of names) {
        await page.goto('/connections/new');
        await waitForLiveView(page);
        await page.getByLabel('Name').fill(name);
        await page.getByLabel('Entity Type').selectOption('person');
        await page.getByRole('button', { name: 'Save Connection' }).click();
        await expect(page).toHaveURL('/connections', { timeout: 10000 });
      }

      await page.goto('/connections');
      await waitForLiveView(page);

      // Wait for all connections to load
      await expect(page.getByText('Alice Smith')).toBeVisible();
      await expect(page.getByText('Bob Johnson')).toBeVisible();

      // Search for Alice
      await page.getByPlaceholder('Search connections...').fill('Alice');

      // Wait for filter to apply (debounce)
      await page.waitForTimeout(500);

      // Only Alice should be visible
      await expect(page.getByText('Alice Smith')).toBeVisible();
      await expect(page.getByText('Bob Johnson')).not.toBeVisible();
    });

    test('should clear search and show all connections', async ({ page }) => {
      // Create multiple connections
      const names = ['Charlie Brown', 'Diana Prince'];

      for (const name of names) {
        await page.goto('/connections/new');
        await waitForLiveView(page);
        await page.getByLabel('Name').fill(name);
        await page.getByLabel('Entity Type').selectOption('person');
        await page.getByRole('button', { name: 'Save Connection' }).click();
        await expect(page).toHaveURL('/connections', { timeout: 10000 });
      }

      await page.goto('/connections');
      await waitForLiveView(page);

      // Wait for connections
      await expect(page.getByText('Charlie Brown')).toBeVisible();

      // Search
      await page.getByPlaceholder('Search connections...').fill('Charlie');
      await page.waitForTimeout(500);
      await expect(page.getByText('Diana Prince')).not.toBeVisible();

      // Clear search
      await page.getByPlaceholder('Search connections...').fill('');
      await page.waitForTimeout(500);

      // All should be visible again
      await expect(page.getByText('Charlie Brown')).toBeVisible();
      await expect(page.getByText('Diana Prince')).toBeVisible();
    });
  });
});
