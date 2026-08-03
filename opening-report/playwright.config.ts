import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for scidb-beta e2e tests.
 *
 * Run with:  npx playwright test
 * Or:        npm run test:e2e
 *
 * Make sure the Vite dev server is running first:
 *   npm run dev
 *
 * To install browsers:  npx playwright install chromium
 */

export default defineConfig({
  testDir: './src/e2e',
  // Only collect Playwright specs; exclude the Vitest/jsdom tests that live
  // alongside them in src/e2e (e.g. workspace.e2e.test.tsx). Playwright's
  // default testMatch also matches *.test.tsx, which would make it try to run
  // jsdom-only tests and fail on CSS imports.
  testMatch: '**/*.spec.ts',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: 'list',
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:8765',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});