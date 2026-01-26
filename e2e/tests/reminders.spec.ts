import { test, expect } from '@playwright/test';
import {
  generateTestUser,
  registerUser,
  waitForLiveView,
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
      await waitForLiveView(page);

      // Check page heading - exact match
      await expect(page.getByRole('heading', { name: 'Reminders', level: 1 })).toBeVisible();

      // Check empty state - the actual heading is "No reminders found"
      await expect(page.getByRole('heading', { name: 'No reminders found' })).toBeVisible();

      // Check Add Reminder button in header (it's a link with a button inside)
      await expect(page.getByRole('button', { name: 'Add Reminder' }).first()).toBeVisible();
    });

    test('should have status filter dropdown', async ({ page }) => {
      await page.goto('/reminders');
      await waitForLiveView(page);

      const statusFilter = page.locator('select[name="status"]');
      await expect(statusFilter).toBeVisible();

      // Check options count (All Reminders, Pending, Overdue, Snoozed, Completed)
      await expect(statusFilter.locator('option')).toHaveCount(5);
    });

    test('should have correct filter options', async ({ page }) => {
      await page.goto('/reminders');
      await waitForLiveView(page);

      const statusFilter = page.locator('select[name="status"]');

      // Verify option values exist
      await expect(statusFilter.locator('option[value=""]')).toHaveText('All Reminders');
      await expect(statusFilter.locator('option[value="pending"]')).toHaveText('Pending');
      await expect(statusFilter.locator('option[value="overdue"]')).toHaveText('Overdue');
      await expect(statusFilter.locator('option[value="snoozed"]')).toHaveText('Snoozed');
      await expect(statusFilter.locator('option[value="completed"]')).toHaveText('Completed');
    });
  });

  test.describe('Create Reminder', () => {
    test('should open new reminder modal', async ({ page }) => {
      await page.goto('/reminders');
      await waitForLiveView(page);

      // Click the Add Reminder button
      await page.getByRole('button', { name: 'Add Reminder' }).first().click();

      // Wait for modal - the title shows "New Reminder"
      await expect(page.getByRole('heading', { name: 'New Reminder' })).toBeVisible();

      // Check form fields exist
      await expect(page.getByLabel('Title')).toBeVisible();
      await expect(page.getByLabel('Type')).toBeVisible();
      await expect(page.getByLabel('Description')).toBeVisible();
      await expect(page.getByLabel('Due Date')).toBeVisible();
      await expect(page.getByLabel('Related Contact')).toBeVisible();
    });

    test('should create a reminder successfully', async ({ page }) => {
      await page.goto('/reminders');
      await waitForLiveView(page);

      // Click Add Reminder
      await page.getByRole('button', { name: 'Add Reminder' }).first().click();

      // Wait for modal
      await expect(page.getByRole('heading', { name: 'New Reminder' })).toBeVisible();

      // Fill in reminder details
      const reminderTitle = `Test Reminder ${Date.now()}`;
      await page.getByLabel('Title').fill(reminderTitle);

      // Select type
      await page.getByLabel('Type').selectOption('follow_up');

      // Set due date (tomorrow)
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      const dueDate = tomorrow.toISOString().slice(0, 16); // Format: YYYY-MM-DDTHH:MM
      await page.getByLabel('Due Date').fill(dueDate);

      // Submit form
      await page.getByRole('button', { name: 'Save Reminder' }).click();

      // Modal should close
      await expect(page.getByRole('heading', { name: 'New Reminder' })).not.toBeVisible({ timeout: 5000 });

      // Reminder should appear in the list
      await expect(page.getByText(reminderTitle)).toBeVisible();
    });

    test('should create reminder with birthday type', async ({ page }) => {
      await page.goto('/reminders');
      await waitForLiveView(page);

      await page.getByRole('button', { name: 'Add Reminder' }).first().click();

      await expect(page.getByRole('heading', { name: 'New Reminder' })).toBeVisible();

      const reminderTitle = `Birthday Reminder ${Date.now()}`;
      await page.getByLabel('Title').fill(reminderTitle);

      // Select birthday type
      await page.getByLabel('Type').selectOption('birthday');

      // Set due date
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      await page.getByLabel('Due Date').fill(tomorrow.toISOString().slice(0, 16));

      await page.getByRole('button', { name: 'Save Reminder' }).click();

      await expect(page.getByRole('heading', { name: 'New Reminder' })).not.toBeVisible({ timeout: 5000 });
      await expect(page.getByText(reminderTitle)).toBeVisible();
    });

    test('should show validation error for empty title', async ({ page }) => {
      await page.goto('/reminders');
      await waitForLiveView(page);

      await page.getByRole('button', { name: 'Add Reminder' }).first().click();

      await expect(page.getByRole('heading', { name: 'New Reminder' })).toBeVisible();

      // Fill required fields except title
      await page.getByLabel('Type').selectOption('follow_up');
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      await page.getByLabel('Due Date').fill(tomorrow.toISOString().slice(0, 16));

      // Try to submit without filling title
      await page.getByRole('button', { name: 'Save Reminder' }).click();

      // Should show validation error
      await expect(page.getByText(/can't be blank/i)).toBeVisible({ timeout: 5000 });
    });
  });

  test.describe('Reminder Actions', () => {
    async function createReminder(page: import('@playwright/test').Page, title: string) {
      await page.goto('/reminders');
      await waitForLiveView(page);
      await page.getByRole('button', { name: 'Add Reminder' }).first().click();
      await expect(page.getByRole('heading', { name: 'New Reminder' })).toBeVisible();

      await page.getByLabel('Title').fill(title);
      await page.getByLabel('Type').selectOption('follow_up');

      // Set due date
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      await page.getByLabel('Due Date').fill(tomorrow.toISOString().slice(0, 16));

      await page.getByRole('button', { name: 'Save Reminder' }).click();
      await expect(page.getByRole('heading', { name: 'New Reminder' })).not.toBeVisible({ timeout: 5000 });
      await expect(page.getByText(title)).toBeVisible();
    }

    test('should mark reminder as complete', async ({ page }) => {
      const reminderTitle = `Complete Test ${Date.now()}`;
      await createReminder(page, reminderTitle);

      // Verify reminder exists
      await expect(page.getByText(reminderTitle)).toBeVisible();

      // Click complete button (has title="Mark as complete")
      await page.locator('button[title="Mark as complete"]').first().click();

      // Should show success flash message
      await expect(page.getByText(/Reminder completed/i)).toBeVisible({ timeout: 5000 });

      // The reminder title should have line-through style or show as completed
      // Check for line-through class on the title
      const completedItem = page.locator('.line-through', { hasText: reminderTitle });
      await expect(completedItem).toBeVisible({ timeout: 5000 });
    });

    test('should delete reminder', async ({ page }) => {
      const reminderTitle = `Delete Test ${Date.now()}`;
      await createReminder(page, reminderTitle);

      // Verify reminder exists
      await expect(page.getByText(reminderTitle)).toBeVisible();

      // Set up dialog handler for confirmation
      page.on('dialog', dialog => dialog.accept());

      // Click delete button (has hero-trash icon)
      // Find the row with the reminder and click its delete button
      const reminderRow = page.locator('li', { hasText: reminderTitle });
      await reminderRow.locator('.hero-trash').click();

      // Reminder should be removed
      await expect(page.getByText(reminderTitle)).not.toBeVisible({ timeout: 5000 });

      // Should show deleted flash message
      await expect(page.getByText(/Reminder deleted/i)).toBeVisible();
    });

    test('should open snooze menu', async ({ page }) => {
      const reminderTitle = `Snooze Test ${Date.now()}`;
      await createReminder(page, reminderTitle);

      // Verify reminder exists
      await expect(page.getByText(reminderTitle)).toBeVisible();

      // Click snooze button (has title="Snooze")
      const reminderRow = page.locator('li', { hasText: reminderTitle });
      await reminderRow.locator('button[title="Snooze"]').click();

      // Snooze dropdown should appear with duration options
      await expect(page.getByRole('button', { name: '1 hour' })).toBeVisible();
      await expect(page.getByRole('button', { name: '3 hours' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Tomorrow' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Next week' })).toBeVisible();
    });

    test('should snooze reminder for 1 hour', async ({ page }) => {
      const reminderTitle = `Snooze 1h Test ${Date.now()}`;
      await createReminder(page, reminderTitle);

      // Click snooze button
      const reminderRow = page.locator('li', { hasText: reminderTitle });
      await reminderRow.locator('button[title="Snooze"]').click();

      // Select "1 hour"
      await page.getByRole('button', { name: '1 hour' }).click();

      // Should show success flash message
      await expect(page.getByText(/Reminder snoozed/i)).toBeVisible({ timeout: 5000 });
    });
  });

  test.describe('Edit Reminder', () => {
    test('should edit a reminder successfully', async ({ page }) => {
      // Create a reminder first
      await page.goto('/reminders');
      await waitForLiveView(page);
      await page.getByRole('button', { name: 'Add Reminder' }).first().click();

      const originalTitle = `Edit Test ${Date.now()}`;
      await page.getByLabel('Title').fill(originalTitle);
      await page.getByLabel('Type').selectOption('follow_up');

      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      await page.getByLabel('Due Date').fill(tomorrow.toISOString().slice(0, 16));

      await page.getByRole('button', { name: 'Save Reminder' }).click();
      await expect(page.getByRole('heading', { name: 'New Reminder' })).not.toBeVisible({ timeout: 5000 });

      // Click edit button (pencil icon link)
      const reminderRow = page.locator('li', { hasText: originalTitle });
      await reminderRow.locator('.hero-pencil-square').click();

      // Wait for edit form - title shows "Edit Reminder"
      await expect(page.getByRole('heading', { name: 'Edit Reminder' })).toBeVisible();
      await expect(page.getByLabel('Title')).toBeVisible();

      // Update the title
      const updatedTitle = `Updated Reminder ${Date.now()}`;
      await page.getByLabel('Title').fill(updatedTitle);

      await page.getByRole('button', { name: 'Save Reminder' }).click();

      // Modal should close
      await expect(page.getByRole('heading', { name: 'Edit Reminder' })).not.toBeVisible({ timeout: 5000 });

      // Should show success message
      await expect(page.getByText(/updated successfully/i)).toBeVisible();

      // Verify updated title appears
      await expect(page.getByText(updatedTitle)).toBeVisible({ timeout: 5000 });
    });
  });

  test.describe('Status Filtering', () => {
    test('should filter reminders by status', async ({ page }) => {
      // Create a pending reminder
      await page.goto('/reminders');
      await waitForLiveView(page);
      await page.getByRole('button', { name: 'Add Reminder' }).first().click();

      const pendingTitle = `Filter Test ${Date.now()}`;
      await page.getByLabel('Title').fill(pendingTitle);
      await page.getByLabel('Type').selectOption('follow_up');

      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      await page.getByLabel('Due Date').fill(tomorrow.toISOString().slice(0, 16));

      await page.getByRole('button', { name: 'Save Reminder' }).click();
      await expect(page.getByRole('heading', { name: 'New Reminder' })).not.toBeVisible({ timeout: 5000 });

      // Verify reminder appears (default filter is pending)
      await expect(page.getByText(pendingTitle)).toBeVisible();

      // Filter by "Completed" - should not show pending reminder
      await page.locator('select[name="status"]').selectOption('completed');
      await page.waitForTimeout(500);

      // Pending reminder should not be visible when filtering by completed
      await expect(page.getByText(pendingTitle)).not.toBeVisible();

      // Switch to "All Reminders"
      await page.locator('select[name="status"]').selectOption('');
      await page.waitForTimeout(500);

      // Reminder should be visible again
      await expect(page.getByText(pendingTitle)).toBeVisible();

      // Switch to "Pending"
      await page.locator('select[name="status"]').selectOption('pending');
      await page.waitForTimeout(500);

      // Reminder should still be visible
      await expect(page.getByText(pendingTitle)).toBeVisible();
    });
  });
});
