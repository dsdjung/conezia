import { Page, expect } from '@playwright/test';

/**
 * Test utilities and helpers for Conezia E2E tests.
 */

export interface TestUser {
  email: string;
  password: string;
  name?: string;
}

/**
 * Generate a unique test user with random email.
 */
export function generateTestUser(prefix = 'test'): TestUser {
  const timestamp = Date.now();
  const random = Math.random().toString(36).substring(2, 8);
  return {
    email: `${prefix}_${timestamp}_${random}@test.conezia.com`,
    password: 'TestPassword123!',
    name: `Test User ${random}`,
  };
}

/**
 * Register a new user through the UI.
 */
export async function registerUser(page: Page, user: TestUser): Promise<void> {
  await page.goto('/register');

  // Wait for LiveView to be connected before interacting
  await waitForLiveView(page);

  // Fill form fields
  await page.getByLabel('Email address').fill(user.email);
  await page.getByLabel('Password', { exact: true }).fill(user.password);
  await page.getByLabel('Confirm password').fill(user.password);

  // Click the button and wait for form submission
  await page.getByRole('button', { name: /create account/i }).click();

  // Wait for the form to process - the registration flow:
  // 1. LiveView validates and creates user
  // 2. Sets trigger_submit: true which auto-submits POST to /login
  // 3. SessionController creates session and redirects to dashboard

  // Wait for redirect to dashboard (successful registration)
  await expect(page).toHaveURL('/', { timeout: 15000 });
}

/**
 * Login an existing user through the UI.
 */
export async function loginUser(page: Page, user: TestUser): Promise<void> {
  await page.goto('/login');

  // Wait for LiveView to be connected before interacting
  await waitForLiveView(page);

  await page.getByLabel('Email address').fill(user.email);
  await page.getByLabel('Password').fill(user.password);

  await page.getByRole('button', { name: /sign in/i }).click();

  // Wait for navigation to dashboard after successful login
  await expect(page).toHaveURL('/', { timeout: 15000 });
}

/**
 * Logout the current user.
 */
export async function logoutUser(page: Page): Promise<void> {
  // Look for logout button/link in navigation
  await page.getByRole('button', { name: /logout|sign out/i }).click();

  // Wait for redirect to login page
  await expect(page).toHaveURL('/login', { timeout: 10000 });
}

/**
 * Check if user is authenticated by verifying dashboard is accessible.
 */
export async function isAuthenticated(page: Page): Promise<boolean> {
  try {
    await page.goto('/');
    const url = page.url();
    return !url.includes('/login') && !url.includes('/register');
  } catch {
    return false;
  }
}

/**
 * Create a connection/entity through the UI.
 */
export async function createConnection(
  page: Page,
  data: {
    name: string;
    type?: 'person' | 'organization';
    description?: string;
    relationshipType?: string;
  }
): Promise<void> {
  await page.goto('/connections/new');

  // Wait for modal to appear
  await expect(page.getByRole('heading', { name: /new connection/i })).toBeVisible();

  // Fill in connection details
  await page.getByLabel('Name', { exact: true }).fill(data.name);

  if (data.type) {
    await page.getByLabel('Type').selectOption(data.type);
  }

  if (data.description) {
    await page.getByLabel('Description').fill(data.description);
  }

  if (data.relationshipType) {
    await page.getByLabel(/relationship type/i).selectOption(data.relationshipType);
  }

  // Submit the form
  await page.getByRole('button', { name: /save|create/i }).click();

  // Wait for the modal to close and connection list to update
  await expect(page.getByRole('heading', { name: /new connection/i })).not.toBeVisible({ timeout: 5000 });
}

/**
 * Create a reminder through the UI.
 */
export async function createReminder(
  page: Page,
  data: {
    title: string;
    type?: string;
    dueDate?: string;
    notes?: string;
  }
): Promise<void> {
  await page.goto('/reminders/new');

  // Wait for modal/form to appear
  await expect(page.getByLabel('Title')).toBeVisible();

  // Fill in reminder details
  await page.getByLabel('Title').fill(data.title);

  if (data.type) {
    await page.getByLabel('Type').selectOption(data.type);
  }

  if (data.dueDate) {
    await page.getByLabel(/due/i).fill(data.dueDate);
  }

  if (data.notes) {
    await page.getByLabel('Notes').fill(data.notes);
  }

  // Submit
  await page.getByRole('button', { name: /save|create/i }).click();
}

/**
 * Wait for Phoenix LiveView to be connected.
 */
export async function waitForLiveView(page: Page): Promise<void> {
  // LiveView adds a 'phx-connected' class when connected
  await page.waitForSelector('[data-phx-main]', { state: 'attached', timeout: 10000 });
  // Give it a moment to fully initialize
  await page.waitForTimeout(500);
}

/**
 * Wait for flash message to appear with specific text.
 */
export async function expectFlashMessage(
  page: Page,
  type: 'info' | 'error' | 'success',
  textPattern: string | RegExp
): Promise<void> {
  const flashSelector = `[role="alert"]`;
  const flash = page.locator(flashSelector).filter({ hasText: textPattern });
  await expect(flash).toBeVisible({ timeout: 5000 });
}

/**
 * Close any visible flash messages.
 */
export async function dismissFlashMessages(page: Page): Promise<void> {
  const closeButtons = page.locator('[role="alert"] button[aria-label="close"]');
  const count = await closeButtons.count();
  for (let i = 0; i < count; i++) {
    await closeButtons.first().click();
  }
}
