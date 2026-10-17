/**
 * play.spec.ts — Playwright end-to-end test for online play (Phase 2 mock
 * backend, per docs/ONLINE_PLAY_PLAN.md §9): two players, seek creation + accept,
 * play to mate, assert board/clock/finish.
 *
 * Two BROWSER TABS in the SAME context, not two contexts. The mock backend
 * (mockPlayBackend.ts) syncs players via BroadcastChannel, which is scoped to
 * a storage partition; Playwright's browser.newContext() creates a fresh
 * partition per context (like separate profiles), so two contexts never see
 * each other's seeks/moves. Two pages opened on the same `context` share a
 * partition and do sync, while each still gets its own sessionStorage (so
 * each tab is a distinct guest identity — see mockPlayBackend's
 * `makeGuestUser`). This was verified empirically against the mock backend
 * before writing this spec.
 *
 * Prerequisites:
 *   1. Install browsers:  npx playwright install chromium
 *   2. Start the dev server:  npm run dev  (or `vite preview` in CI, see
 *      playwright.config.ts / .github/workflows/ci.yml)
 *
 * Run:
 *   npx playwright test src/e2e/play.spec.ts
 */

import { test, expect, type Page } from '@playwright/test';

const BASE_URL = process.env.PLAYWRIGHT_BASE_URL || 'http://localhost:8765';

async function openPlay(page: Page): Promise<void> {
  await page.goto(BASE_URL);
  await page.waitForSelector('#app-header', { timeout: 10_000 });
  await page.locator('.top-nav-item', { hasText: 'Play' }).click();
  await page.waitForSelector('#play-center', { timeout: 5_000 });
}

async function myColor(page: Page): Promise<'w' | 'b'> {
  const text = (await page.locator('#play-center .clock-row.mine .clock-side').textContent())?.trim();
  return text === 'White' ? 'w' : 'b';
}

async function clickSquare(page: Page, square: string): Promise<void> {
  await page.locator(`#play-center [data-square="${square}"]`).click();
}

/** Click from-square then to-square, and wait for BOTH boards to reach the
 * expected ply count (i.e. the move has round-tripped through the mock
 * backend and been applied to the opponent's board via applyExternalMove). */
async function playMoveAndSync(mover: Page, other: Page, from: string, to: string, expectedPly: number): Promise<void> {
  await clickSquare(mover, from);
  await clickSquare(mover, to);
  for (const page of [mover, other]) {
    await page.waitForFunction(
      (n) => document.querySelectorAll('#play-center .scidb-move-list .move-cell').length === n,
      expectedPly,
      { timeout: 10_000 },
    );
  }
}

test.describe('Online play — two players', () => {
  test('create seek, accept, play Fool\'s mate, board/clock/finish reflect the result on both sides', async ({ browser }) => {
    // Two SEPARATE browser contexts. Each context has its own storage partition
    // and therefore its own guest identity (sessionStorage). This is required
    // for the real backend: the server keys the local player by the
    // X-Play-Guest-Id header, so two players must be distinct guests (A cannot
    // accept its own seek). The two clients then sync through the server, not
    // a local BroadcastChannel.
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();
    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    await openPlay(pageA);
    await openPlay(pageB);

    await expect(pageA.locator('#play-center .seek-lobby')).toBeVisible();
    await expect(pageB.locator('#play-center .seek-lobby')).toBeVisible();

    // A creates a seek; B sees it and accepts.
    await pageA.locator('#play-center .primary-btn:has-text("Create seek")').click();
    await pageB.waitForSelector('#play-center .seek-row .small-btn', { timeout: 5_000 });
    await pageB.locator('#play-center .seek-row .small-btn').click();

    // Both land on the live board.
    await pageA.waitForSelector('#play-center .play-board-panel', { timeout: 5_000 });
    await pageB.waitForSelector('#play-center .play-board-panel', { timeout: 5_000 });
    await expect(pageA.locator('#play-center .scidb-board')).toBeVisible();
    await expect(pageB.locator('#play-center .scidb-board')).toBeVisible();
    await expect(pageA.locator('#play-center .clock-widget')).toBeVisible();
    await expect(pageB.locator('#play-center .clock-widget')).toBeVisible();

    // Colours are assigned randomly by acceptSeek; figure out who is who.
    const [colorA, colorB] = await Promise.all([myColor(pageA), myColor(pageB)]);
    expect(new Set([colorA, colorB])).toEqual(new Set(['w', 'b']));
    const white = colorA === 'w' ? pageA : pageB;
    const black = colorA === 'w' ? pageB : pageA;

    // Fool's mate: 1. f3 e5 2. g4 Qh4#
    await playMoveAndSync(white, black, 'f2', 'f3', 1);
    await playMoveAndSync(black, white, 'e7', 'e5', 2);
    await playMoveAndSync(white, black, 'g2', 'g4', 3);
    await playMoveAndSync(black, white, 'd8', 'h4', 4);

    // Both sides land on the finish banner, and match controls disappear.
    await expect(white.locator('#play-center .play-result')).toContainText('Checkmate', { timeout: 5_000 });
    await expect(black.locator('#play-center .play-result')).toContainText('Checkmate', { timeout: 5_000 });
    await expect(white.locator('#play-center .play-result')).toContainText('Black wins');
    await expect(black.locator('#play-center .play-result')).toContainText('Black wins');
    await expect(white.locator('#play-center .match-controls')).toHaveCount(0);
    await expect(black.locator('#play-center .match-controls')).toHaveCount(0);
  });
});
