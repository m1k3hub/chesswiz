/**
 * workspace.spec.ts — Playwright end-to-end test.
 *
 * These tests launch a browser, navigate to the Vite dev server, and verify
 * the workspace shell renders and rail buttons open modals.
 *
 * Prerequisites:
 *   1. Install browsers:  npx playwright install chromium
 *   2. Start the dev server:  npm run dev  (runs on :8765 or next free port)
 *
 * Run:
 *   npx playwright test src/e2e/workspace.spec.ts
 *
 * Or via package.json:
 *   npm run test:e2e
 */

import { test, expect } from '@playwright/test';

// The dev server runs on port 8765 by default; CI may override with PLAYWRIGHT_BASE_URL.
const BASE_URL = process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:8765';

test.describe('Workspace shell', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(BASE_URL);
    // Wait for the React app to render the header.
    await page.waitForSelector('#app-header', { timeout: 10_000 });
  });

  test('renders header and main layout', async ({ page }) => {
    await expect(page.locator('#app-header')).toBeVisible();
    await expect(page.locator('#main-layout')).toBeVisible();
    await expect(page.locator('.side-rail')).toBeVisible();
  });

  test('rail has expected buttons', async ({ page }) => {
    const rail = page.locator('.side-rail');
    await expect(rail).toContainText('My databases');
    await expect(rail).toContainText('Search games');
    await expect(rail).toContainText('Search center');
    await expect(rail).toContainText('Opening explorer');
    await expect(rail).toContainText('Player center');
  });

  test('clicking "Search games" opens the game switcher modal', async ({ page }) => {
    await page.locator('.side-rail').getByText('Search games').click();
    // The modal is lazy-loaded; wait for it to appear.
    await expect(page.locator('#game-switcher-modal')).toBeVisible({ timeout: 5_000 });
  });

  test('clicking "Search center" opens the search center modal', async ({ page }) => {
    await page.locator('.side-rail').getByText('Search center').click();
    await expect(page.locator('#search-center-modal')).toBeVisible({ timeout: 5_000 });
  });

  test('clicking "Opening explorer" opens the opening tree modal', async ({ page }) => {
    await page.locator('.side-rail').getByText('Opening explorer').click();
    await expect(page.locator('#opening-tree-modal')).toBeVisible({ timeout: 5_000 });
  });

  test('clicking "My databases" opens the database manager modal', async ({ page }) => {
    await page.locator('.side-rail').getByText('My databases').click();
    await expect(page.locator('#database-modal')).toBeVisible({ timeout: 5_000 });
  });

  test('board panel renders the chessboard', async ({ page }) => {
    await expect(page.locator('#board-panel')).toBeVisible();
    // The board container should be present (the actual board may take a moment to init).
    await page.waitForSelector('#board-panel .scidb-board-wrapper, #board-panel .scidb-board', { timeout: 5_000 });
  });

  test('report panel shows overview tab', async ({ page }) => {
    await expect(page.locator('#report-panel')).toBeVisible();
    await expect(page.locator('#tab-overview')).toBeVisible();
  });
});