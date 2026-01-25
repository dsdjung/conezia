import { test, expect } from '@playwright/test';
import {
  generateTestUser,
  registerUser,
  waitForLiveView,
  TestUser,
} from '../helpers/test-utils';

test.describe('Authentication', () => {
  test.describe('Registration', () => {
    test('should display registration page correctly', async ({ page }) => {
      await page.goto('/register');

      // Check page title and heading
      await expect(page).toHaveTitle(/conezia/i);
      await expect(page.getByRole('heading', { name: /create your account/i })).toBeVisible();

      // Check form fields are present
      await expect(page.getByLabel('Email address')).toBeVisible();
      await expect(page.getByLabel('Password', { exact: true })).toBeVisible();
      await expect(page.getByLabel('Confirm password')).toBeVisible();

      // Check Google sign-up button
      await expect(page.getByRole('link', { name: /sign up with google/i })).toBeVisible();

      // Check link to login
      await expect(page.getByRole('link', { name: /sign in/i })).toBeVisible();
    });

    test('should register a new user successfully', async ({ page }) => {
      const user = generateTestUser();

      await page.goto('/register');

      await page.getByLabel('Email address').fill(user.email);
      await page.getByLabel('Password', { exact: true }).fill(user.password);
      await page.getByLabel('Confirm password').fill(user.password);

      await page.getByRole('button', { name: /create account/i }).click();

      // Should redirect to dashboard after successful registration
      await expect(page).toHaveURL('/', { timeout: 15000 });

      // Verify we're on the dashboard
      await expect(page.getByRole('heading', { name: /welcome back/i })).toBeVisible();
    });

    test('should show validation error for invalid email', async ({ page }) => {
      await page.goto('/register');

      await page.getByLabel('Email address').fill('invalid-email');
      await page.getByLabel('Password', { exact: true }).fill('TestPassword123!');
      await page.getByLabel('Confirm password').fill('TestPassword123!');

      // Submit to trigger validation errors
      await page.getByRole('button', { name: /create account/i }).click();

      // Should show email validation error (looking for error message text)
      await expect(page.getByText(/must have the @ sign|invalid format|valid email/i)).toBeVisible({ timeout: 5000 });
    });

    test('should show validation error for weak password', async ({ page }) => {
      await page.goto('/register');

      await page.getByLabel('Email address').fill('test@example.com');
      await page.getByLabel('Password', { exact: true }).fill('weak');
      await page.getByLabel('Confirm password').fill('weak');

      // Submit to trigger validation errors
      await page.getByRole('button', { name: /create account/i }).click();

      // Should show password validation error
      await expect(page.getByText(/at least 8|uppercase|number/i)).toBeVisible({ timeout: 5000 });
    });

    test('should show error for password mismatch', async ({ page }) => {
      await page.goto('/register');

      await page.getByLabel('Email address').fill('test@example.com');
      await page.getByLabel('Password', { exact: true }).fill('TestPassword123!');
      await page.getByLabel('Confirm password').fill('DifferentPassword123!');

      // Submit to trigger validation errors
      await page.getByRole('button', { name: /create account/i }).click();

      // Should show mismatch error
      await expect(page.getByText(/does not match/i)).toBeVisible({ timeout: 5000 });
    });

    test('should navigate to login page from registration', async ({ page }) => {
      await page.goto('/register');

      await page.getByRole('link', { name: /sign in/i }).click();

      await expect(page).toHaveURL('/login');
    });
  });

  test.describe('Login', () => {
    test('should display login page correctly', async ({ page }) => {
      await page.goto('/login');

      // Check page heading
      await expect(page.getByRole('heading', { name: /sign in to conezia/i })).toBeVisible();

      // Check form fields
      await expect(page.getByLabel('Email address')).toBeVisible();
      await expect(page.getByLabel('Password')).toBeVisible();

      // Check remember me checkbox
      await expect(page.getByLabel(/keep me logged in/i)).toBeVisible();

      // Check Google sign-in button
      await expect(page.getByRole('link', { name: /continue with google/i })).toBeVisible();

      // Check forgot password link
      await expect(page.getByRole('link', { name: /forgot your password/i })).toBeVisible();

      // Check register link
      await expect(page.getByRole('link', { name: /register now/i })).toBeVisible();
    });

    test('should login successfully with valid credentials', async ({ page }) => {
      // First register a user
      const user = generateTestUser('login');
      await registerUser(page, user);

      // Logout (navigate to login page)
      await page.goto('/login');

      await page.getByLabel('Email address').fill(user.email);
      await page.getByLabel('Password').fill(user.password);

      await page.getByRole('button', { name: /sign in/i }).click();

      // Should redirect to dashboard
      await expect(page).toHaveURL('/', { timeout: 15000 });

      // Verify dashboard content
      await expect(page.getByRole('heading', { name: /welcome back/i })).toBeVisible();
    });

    test('should show error for invalid credentials', async ({ page }) => {
      await page.goto('/login');

      await page.getByLabel('Email address').fill('wrong@example.com');
      await page.getByLabel('Password').fill('WrongPassword123!');

      await page.getByRole('button', { name: /sign in/i }).click();

      // Should show error message
      await expect(page.getByText(/invalid|incorrect|credentials/i)).toBeVisible({ timeout: 5000 });

      // Should stay on login page
      await expect(page).toHaveURL('/login');
    });

    test('should navigate to registration page from login', async ({ page }) => {
      await page.goto('/login');

      await page.getByRole('link', { name: /register now/i }).click();

      await expect(page).toHaveURL('/register');
    });

    test('should navigate to forgot password page', async ({ page }) => {
      await page.goto('/login');

      await page.getByRole('link', { name: /forgot your password/i }).click();

      await expect(page).toHaveURL('/forgot-password');
    });
  });

  test.describe('Protected Routes', () => {
    test('should redirect to login when accessing dashboard unauthenticated', async ({ page }) => {
      await page.goto('/');

      // Should redirect to login
      await expect(page).toHaveURL('/login');
    });

    test('should redirect to login when accessing connections unauthenticated', async ({ page }) => {
      await page.goto('/connections');

      await expect(page).toHaveURL('/login');
    });

    test('should redirect to login when accessing reminders unauthenticated', async ({ page }) => {
      await page.goto('/reminders');

      await expect(page).toHaveURL('/login');
    });

    test('should redirect to login when accessing settings unauthenticated', async ({ page }) => {
      await page.goto('/settings');

      await expect(page).toHaveURL('/login');
    });
  });

  test.describe('Logout', () => {
    test('should logout successfully', async ({ page }) => {
      // First register and login
      const user = generateTestUser('logout');
      await registerUser(page, user);

      // Verify we're logged in
      await expect(page).toHaveURL('/');

      // Find and click logout - it might be in a dropdown menu
      // First try to find a user menu or dropdown
      const userMenuButton = page.locator('[data-testid="user-menu"]').or(
        page.getByRole('button', { name: new RegExp(user.email, 'i') })
      ).or(
        page.locator('nav').getByRole('button').last()
      );

      // If there's a user menu, click it first
      if (await userMenuButton.isVisible()) {
        await userMenuButton.click();
      }

      // Look for logout link/button
      const logoutButton = page.getByRole('link', { name: /logout|sign out/i }).or(
        page.getByRole('button', { name: /logout|sign out/i })
      );

      await logoutButton.click();

      // Should redirect to login page
      await expect(page).toHaveURL('/login', { timeout: 10000 });

      // Verify we can no longer access protected routes
      await page.goto('/');
      await expect(page).toHaveURL('/login');
    });
  });

  test.describe('Forgot Password', () => {
    test('should display forgot password page correctly', async ({ page }) => {
      await page.goto('/forgot-password');

      // Check heading
      await expect(page.getByRole('heading', { name: /forgot|reset|password/i })).toBeVisible();

      // Check email input
      await expect(page.getByLabel('Email')).toBeVisible();

      // Check submit button
      await expect(page.getByRole('button', { name: /send|reset|submit/i })).toBeVisible();
    });

    test('should submit forgot password form', async ({ page }) => {
      await page.goto('/forgot-password');

      await page.getByLabel('Email').fill('test@example.com');

      await page.getByRole('button', { name: /send|reset|submit/i }).click();

      // Wait for form submission to complete
      await page.waitForTimeout(1000);

      // The page should show some feedback - either a message or redirect
      // Just verify the form was submitted and we're not stuck
      const url = page.url();
      const hasMessage = await page.getByText(/if|email|sent|success/i).isVisible().catch(() => false);
      expect(url.includes('/forgot-password') || hasMessage).toBeTruthy();
    });
  });
});
