import { test, expect } from '@playwright/test';
import {
  generateTestUser,
  registerUser,
} from '../helpers/test-utils';

test.describe('Reminders', () => {
  test.beforeEach(async ({ page }) => {
    // Register and login a fresh user for each test
    const user = generateTestUser('reminders');
    await registerUser(page, user);
  });

  test.describe('Reminders List', () => {
    test('should display reminders page with empty state', async ({ page }) => {
      await page.goto('/reminders');

      // Check page heading
      await expect(page.getByRole('heading', { name: /reminders/i })).toBeVisible();

      // Check empty state
      await expect(page.getByText(/no reminders/i)).toBeVisible();

      // Check Add Reminder button
      await expect(page.getByRole('link', { name: /add reminder/i })).toBeVisible();
    });

    test('should have status filter dropdown', async ({ page }) => {
      await page.goto('/reminders');

      const statusFilter = page.locator('select[name="status"]');
      await expect(statusFilter).toBeVisible();

      // Check options
      await expect(statusFilter.locator('option')).toHaveCount(5); // All, Pending, Overdue, Snoozed, Completed
    });
  });

  test.describe('Create Reminder', () => {
    test('should open new reminder modal', async ({ page }) => {
      await page.goto('/reminders');

      await page.getByRole('link', { name: /add reminder/i }).click();

      // Wait for modal
      await expect(page.getByRole('heading', { name: /new reminder/i })).toBeVisible();

      // Check form fields
      await expect(page.getByLabel('Title')).toBeVisible();
    });

    test('should create a reminder successfully', async ({ page }) => {
      await page.goto('/reminders');

      // Click Add Reminder
      await page.getByRole('link', { name: /add reminder/i }).click();

      // Wait for modal
      await expect(page.getByRole('heading', { name: /new reminder/i })).toBeVisible();

      // Fill in reminder details
      const reminderTitle = `Test Reminder ${Date.now()}`;
      await page.getByLabel('Title').fill(reminderTitle);

      // Set due date (tomorrow)
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      const dueDate = tomorrow.toISOString().slice(0, 16); // Format: YYYY-MM-DDTHH:MM

      const dueDateField = page.getByLabel(/due/i);
      if (await dueDateField.isVisible()) {
        await dueDateField.fill(dueDate);
      }

      // Add description if field exists
      const descriptionField = page.getByLabel(/description|notes/i);
      if (await descriptionField.isVisible()) {
        await descriptionField.fill('A test reminder created by E2E tests');
      }

      // Submit form
      await page.getByRole('button', { name: /save|create/i }).click();

      // Modal should close
      await expect(page.getByRole('heading', { name: /new reminder/i })).not.toBeVisible({ timeout: 5000 });

      // Reminder should appear in the list
      await expect(page.getByText(reminderTitle)).toBeVisible();
    });

    test('should create reminder with type', async ({ page }) => {
      await page.goto('/reminders');

      await page.getByRole('link', { name: /add reminder/i }).click();

      await expect(page.getByRole('heading', { name: /new reminder/i })).toBeVisible();

      const reminderTitle = `Birthday Reminder ${Date.now()}`;
      await page.getByLabel('Title').fill(reminderTitle);

      // Select reminder type
      const typeSelect = page.getByLabel('Type');
      if (await typeSelect.isVisible()) {
        await typeSelect.selectOption('birthday');
      }

      await page.getByRole('button', { name: /save|create/i }).click();

      await expect(page.getByRole('heading', { name: /new reminder/i })).not.toBeVisible({ timeout: 5000 });
      await expect(page.getByText(reminderTitle)).toBeVisible();
    });

    test('should show validation error for empty title', async ({ page }) => {
      await page.goto('/reminders');

      await page.getByRole('link', { name: /add reminder/i }).click();

      await expect(page.getByRole('heading', { name: /new reminder/i })).toBeVisible();

      // Try to submit without filling title
      await page.getByRole('button', { name: /save|create/i }).click();

      // Should show validation error
      await expect(page.getByText(/required|blank|title/i)).toBeVisible();
    });
  });

  test.describe('Reminder Actions', () => {
    async function createReminder(page: import('@playwright/test').Page, title: string) {
      await page.goto('/reminders');
      await page.getByRole('link', { name: /add reminder/i }).click();
      await page.getByLabel('Title').fill(title);

      // Set due date
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      const dueDateField = page.getByLabel(/due/i);
      if (await dueDateField.isVisible()) {
        await dueDateField.fill(tomorrow.toISOString().slice(0, 16));
      }

      await page.getByRole('button', { name: /save|create/i }).click();
      await expect(page.getByRole('heading', { name: /new reminder/i })).not.toBeVisible({ timeout: 5000 });
    }

    test('should mark reminder as complete', async ({ page }) => {
      const reminderTitle = `Complete Test ${Date.now()}`;
      await createReminder(page, reminderTitle);

      // Verify reminder exists
      await expect(page.getByText(reminderTitle)).toBeVisible();

      // Click complete button
      const completeButton = page.locator('[title*="complete" i]').or(
        page.getByRole('button', { name: /complete|check/i })
      ).first();

      await completeButton.click();

      // Should show success message or update UI
      // The reminder might be styled differently (strikethrough) or moved to completed filter
      await page.waitForTimeout(1000);

      // Verify the action happened (flash message or style change)
      // Could check for flash message
      const flashOrStyle = page.getByText(/completed/i).or(
        page.locator('.line-through')
      );

      await expect(flashOrStyle.first()).toBeVisible({ timeout: 5000 });
    });

    test('should delete reminder', async ({ page }) => {
      const reminderTitle = `Delete Test ${Date.now()}`;
      await createReminder(page, reminderTitle);

      // Verify reminder exists
      await expect(page.getByText(reminderTitle)).toBeVisible();

      // Set up dialog handler
      page.on('dialog', dialog => dialog.accept());

      // Click delete button
      const deleteButton = page.locator('[title*="delete" i]').or(
        page.getByRole('button', { name: /delete|trash/i })
      ).first();

      await deleteButton.click();

      // Reminder should be removed
      await expect(page.getByText(reminderTitle)).not.toBeVisible({ timeout: 5000 });
    });

    test('should snooze reminder', async ({ page }) => {
      const reminderTitle = `Snooze Test ${Date.now()}`;
      await createReminder(page, reminderTitle);

      // Verify reminder exists
      await expect(page.getByText(reminderTitle)).toBeVisible();

      // Click snooze button to open menu
      const snoozeButton = page.locator('[title*="snooze" i]').or(
        page.getByRole('button', { name: /snooze|clock/i })
      ).first();

      await snoozeButton.click();

      // Select snooze duration (e.g., "1 hour")
      await page.getByRole('button', { name: /1 hour/i }).click();

      // Should show success message
      await expect(page.getByText(/snoozed/i)).toBeVisible({ timeout: 5000 });
    });
  });

  test.describe('Edit Reminder', () => {
    test('should edit a reminder successfully', async ({ page }) => {
      // Create a reminder first
      await page.goto('/reminders');
      await page.getByRole('link', { name: /add reminder/i }).click();

      const originalTitle = `Edit Test ${Date.now()}`;
      await page.getByLabel('Title').fill(originalTitle);
      await page.getByRole('button', { name: /save|create/i }).click();
      await expect(page.getByRole('heading', { name: /new reminder/i })).not.toBeVisible({ timeout: 5000 });

      // Click edit button
      const editButton = page.locator(`[title*="edit" i]`).or(
        page.getByRole('link', { name: /edit/i })
      ).first();
      await editButton.click();

      // Wait for edit form
      await expect(page.getByLabel('Title')).toBeVisible();

      // Update the title
      const updatedTitle = `Updated Reminder ${Date.now()}`;
      await page.getByLabel('Title').fill(updatedTitle);

      await page.getByRole('button', { name: /save|update/i }).click();

      // Verify update
      await expect(page.getByText(updatedTitle)).toBeVisible({ timeout: 5000 });
    });
  });

  test.describe('Status Filtering', () => {
    test('should filter reminders by status', async ({ page }) => {
      // Create a pending reminder
      await page.goto('/reminders');
      await page.getByRole('link', { name: /add reminder/i }).click();

      const pendingTitle = `Pending ${Date.now()}`;
      await page.getByLabel('Title').fill(pendingTitle);

      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      const dueDateField = page.getByLabel(/due/i);
      if (await dueDateField.isVisible()) {
        await dueDateField.fill(tomorrow.toISOString().slice(0, 16));
      }

      await page.getByRole('button', { name: /save|create/i }).click();
      await expect(page.getByRole('heading', { name: /new reminder/i })).not.toBeVisible({ timeout: 5000 });

      // Verify reminder appears
      await expect(page.getByText(pendingTitle)).toBeVisible();

      // Filter by "Pending"
      await page.locator('select[name="status"]').selectOption('pending');
      await page.waitForTimeout(500);

      // Reminder should still be visible
      await expect(page.getByText(pendingTitle)).toBeVisible();

      // Filter by "Completed"
      await page.locator('select[name="status"]').selectOption('completed');
      await page.waitForTimeout(500);

      // Pending reminder should not be visible
      await expect(page.getByText(pendingTitle)).not.toBeVisible();

      // Switch back to "All" or "Pending"
      await page.locator('select[name="status"]').selectOption('');
      await page.waitForTimeout(500);

      // Reminder should be visible again
      await expect(page.getByText(pendingTitle)).toBeVisible();
    });
  });
});
