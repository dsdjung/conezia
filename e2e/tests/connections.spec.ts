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

      // Check empty state
      await expect(page.getByRole('heading', { name: /no connections/i })).toBeVisible();

      // Check Add Connection button
      await expect(page.getByRole('link', { name: /add connection/i }).first()).toBeVisible();
    });

    test('should have search input', async ({ page }) => {
      await page.goto('/connections');

      await expect(page.getByPlaceholder(/search/i)).toBeVisible();
    });

    test('should have type filter dropdown', async ({ page }) => {
      await page.goto('/connections');

      // Check for type filter select
      const typeFilter = page.locator('select[name="type"]');
      await expect(typeFilter).toBeVisible();

      // Check options
      await expect(typeFilter.locator('option')).toHaveCount(3); // All, People, Organizations
    });
  });

  test.describe('Create Connection', () => {
    test('should open new connection modal', async ({ page }) => {
      await page.goto('/connections');

      await page.getByRole('link', { name: /add connection/i }).click();

      // Wait for modal
      await expect(page.getByRole('heading', { name: /new connection/i })).toBeVisible();

      // Check form fields
      await expect(page.getByLabel('Name', { exact: true })).toBeVisible();
    });

    test('should create a person connection successfully', async ({ page }) => {
      await page.goto('/connections');

      // Click Add Connection
      await page.getByRole('link', { name: /add connection/i }).click();

      // Wait for modal
      await expect(page.getByRole('heading', { name: /new connection/i })).toBeVisible();

      // Fill in connection details
      const connectionName = `Test Person ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(connectionName);

      // Select person type if there's a dropdown
      const typeSelect = page.getByLabel('Type');
      if (await typeSelect.isVisible()) {
        await typeSelect.selectOption('person');
      }

      // Add description if field exists
      const descriptionField = page.getByLabel(/description/i);
      if (await descriptionField.isVisible()) {
        await descriptionField.fill('A test connection created by E2E tests');
      }

      // Submit form
      await page.getByRole('button', { name: /save|create/i }).click();

      // Modal should close
      await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });

      // Connection should appear in the list
      await expect(page.getByText(connectionName)).toBeVisible();
    });

    test('should create an organization connection', async ({ page }) => {
      await page.goto('/connections');

      await page.getByRole('link', { name: /add connection/i }).click();

      await expect(page.getByRole('heading', { name: /new connection/i })).toBeVisible();

      const connectionName = `Test Organization ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(connectionName);

      const typeSelect = page.getByLabel('Type');
      if (await typeSelect.isVisible()) {
        await typeSelect.selectOption('organization');
      }

      await page.getByRole('button', { name: /save|create/i }).click();

      await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });
      await expect(page.getByText(connectionName)).toBeVisible();
    });

    test('should show validation error for empty name', async ({ page }) => {
      await page.goto('/connections');

      await page.getByRole('link', { name: /add connection/i }).click();

      await expect(page.getByRole('heading', { name: /new connection/i })).toBeVisible();

      // Try to submit without filling name
      await page.getByRole('button', { name: /save|create/i }).click();

      // Should show validation error
      await expect(page.getByText(/required|blank|name/i)).toBeVisible();
    });

    test('should close modal when clicking cancel or X', async ({ page }) => {
      await page.goto('/connections');

      await page.getByRole('link', { name: /add connection/i }).click();

      await expect(page.getByRole('heading', { name: /new connection/i })).toBeVisible();

      // Find and click the close button (X)
      const closeButton = page.locator('[aria-label*="close" i]').or(
        page.locator('button:has(svg[class*="x"])').first()
      );

      if (await closeButton.isVisible()) {
        await closeButton.click();
      } else {
        // Try pressing Escape
        await page.keyboard.press('Escape');
      }

      // Modal should be closed
      await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible();
    });
  });

  test.describe('View Connection', () => {
    test('should navigate to connection detail page', async ({ page }) => {
      // First create a connection
      await page.goto('/connections');
      await page.getByRole('link', { name: /add connection/i }).click();

      const connectionName = `View Test ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(connectionName);
      await page.getByRole('button', { name: /save|create/i }).click();

      await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });

      // Click on the connection to view details
      await page.getByText(connectionName).click();

      // Should navigate to detail page
      await expect(page).toHaveURL(/\/connections\/[a-f0-9-]+/);

      // Should show connection name
      await expect(page.getByRole('heading', { name: connectionName })).toBeVisible();
    });

    test('should display connection details', async ({ page }) => {
      // Create a connection
      await page.goto('/connections');
      await page.getByRole('link', { name: /add connection/i }).click();

      const connectionName = `Detail Test ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(connectionName);

      const descriptionField = page.getByLabel(/description/i);
      if (await descriptionField.isVisible()) {
        await descriptionField.fill('Test description for details');
      }

      await page.getByRole('button', { name: /save|create/i }).click();
      await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });

      // Navigate to detail page
      await page.getByText(connectionName).click();

      // Verify details are displayed
      await expect(page.getByText(connectionName)).toBeVisible();
    });
  });

  test.describe('Edit Connection', () => {
    test('should edit a connection successfully', async ({ page }) => {
      // Create a connection first
      await page.goto('/connections');
      await page.getByRole('link', { name: /add connection/i }).click();

      const originalName = `Edit Test ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(originalName);
      await page.getByRole('button', { name: /save|create/i }).click();
      await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });

      // Click edit button
      const editButton = page.locator(`[title="Edit"]`).or(
        page.getByRole('link', { name: /edit/i })
      ).first();
      await editButton.click();

      // Wait for edit form/modal
      await expect(page.getByLabel('Name', { exact: true })).toBeVisible();

      // Update the name
      const updatedName = `Updated ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(updatedName);

      await page.getByRole('button', { name: /save|update/i }).click();

      // Verify update
      await expect(page.getByText(updatedName)).toBeVisible({ timeout: 5000 });
    });
  });

  test.describe('Delete Connection', () => {
    test('should delete a connection', async ({ page }) => {
      // Create a connection first
      await page.goto('/connections');
      await page.getByRole('link', { name: /add connection/i }).click();

      const connectionName = `Delete Test ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(connectionName);
      await page.getByRole('button', { name: /save|create/i }).click();
      await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });

      // Verify connection exists
      await expect(page.getByText(connectionName)).toBeVisible();

      // Click delete button
      const deleteButton = page.locator(`[title="Delete"]`).or(
        page.getByRole('button', { name: /delete/i })
      ).first();

      // Set up dialog handler for confirmation
      page.on('dialog', dialog => dialog.accept());

      await deleteButton.click();

      // Connection should be removed from list
      await expect(page.getByText(connectionName)).not.toBeVisible({ timeout: 5000 });
    });

    test('should show confirmation dialog before deleting', async ({ page }) => {
      // Create a connection
      await page.goto('/connections');
      await page.getByRole('link', { name: /add connection/i }).click();

      const connectionName = `Confirm Delete ${Date.now()}`;
      await page.getByLabel('Name', { exact: true }).fill(connectionName);
      await page.getByRole('button', { name: /save|create/i }).click();
      await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });

      // Set up dialog handler to dismiss
      let dialogMessage = '';
      page.on('dialog', async dialog => {
        dialogMessage = dialog.message();
        await dialog.dismiss();
      });

      // Click delete
      const deleteButton = page.locator(`[title="Delete"]`).or(
        page.getByRole('button', { name: /delete/i })
      ).first();
      await deleteButton.click();

      // Verify dialog was shown
      expect(dialogMessage).toMatch(/sure|delete|confirm/i);

      // Connection should still exist (we dismissed the dialog)
      await expect(page.getByText(connectionName)).toBeVisible();
    });
  });

  test.describe('Search and Filter', () => {
    test.beforeEach(async ({ page }) => {
      // Create multiple connections for filtering
      for (const name of ['Alice Smith', 'Bob Johnson', 'Charlie Brown']) {
        await page.goto('/connections');
        await page.getByRole('link', { name: /add connection/i }).click();
        await page.getByLabel('Name', { exact: true }).fill(name);
        await page.getByRole('button', { name: /save|create/i }).click();
        await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });
      }
    });

    test('should filter connections by search term', async ({ page }) => {
      await page.goto('/connections');

      // Wait for all connections to load
      await expect(page.getByText('Alice Smith')).toBeVisible();
      await expect(page.getByText('Bob Johnson')).toBeVisible();

      // Search for Alice
      await page.getByPlaceholder(/search/i).fill('Alice');

      // Wait for filter to apply
      await page.waitForTimeout(500); // debounce delay

      // Only Alice should be visible
      await expect(page.getByText('Alice Smith')).toBeVisible();
      await expect(page.getByText('Bob Johnson')).not.toBeVisible();
    });

    test('should clear search and show all connections', async ({ page }) => {
      await page.goto('/connections');

      // Wait for connections
      await expect(page.getByText('Alice Smith')).toBeVisible();

      // Search
      await page.getByPlaceholder(/search/i).fill('Bob');
      await page.waitForTimeout(500);
      await expect(page.getByText('Alice Smith')).not.toBeVisible();

      // Clear search
      await page.getByPlaceholder(/search/i).fill('');
      await page.waitForTimeout(500);

      // All should be visible again
      await expect(page.getByText('Alice Smith')).toBeVisible();
      await expect(page.getByText('Bob Johnson')).toBeVisible();
    });
  });
});
