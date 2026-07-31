import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { createElement } from 'react';
import MatchControls from './MatchControls';
import { mockPlay, __resetMockPlay } from './mockPlayBackend';
import type { PlayMatch, PlayUser } from '@/types';

const userA: PlayUser = { id: 'userA', name: 'Alice', rating: 1500 };
const userB: PlayUser = { id: 'userB', name: 'Bob', rating: 1500 };

let currentRoot: Root | null = null;

function render(elt: ReturnType<typeof createElement>): HTMLDivElement {
  const container = document.createElement('div');
  document.body.appendChild(container);
  const root = createRoot(container);
  currentRoot = root;
  act(() => { root.render(elt); });
  act(() => {});
  return container;
}

async function click(container: HTMLElement, text: string) {
  const btn = Array.from(container.querySelectorAll('button')).find((b) => b.textContent === text) as HTMLButtonElement;
  expect(btn).toBeTruthy();
  await act(async () => { btn.click(); });
  // The api proxy tries HTTP (fails in jsdom) then falls back to the mock;
  // flush a few microtask ticks so the fallback resolves before asserting.
  for (let i = 0; i < 3; i++) await act(async () => {});
}

function makeMatch(overrides: Partial<PlayMatch> = {}): PlayMatch {
  return {
    id: 'm1',
    variant: 'standard',
    timeControl: { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2 },
    rated: false,
    white: userB,
    black: userA,
    startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    ply: 0,
    status: 'playing',
    result: null,
    clocks: { whiteMs: 180000, blackMs: 180000 },
    clockUpdatedAt: Date.now(),
    drawOfferSide: null,
    rematchOfferSide: null,
    ...overrides,
  };
}

let origConfirm: typeof window.confirm;
beforeEach(() => {
  __resetMockPlay();
  mockPlay.__setMe(userA);
  origConfirm = window.confirm;
  window.confirm = () => true;
});
afterEach(() => {
  if (currentRoot) act(() => { currentRoot!.unmount(); });
  currentRoot = null;
  document.body.innerHTML = '';
  window.confirm = origConfirm;
});

function setupMatch(): PlayMatch {
  mockPlay.__injectSeek({
    id: 's1', owner: userB,
    timeControl: { kind: 'blitz', baseSeconds: 180, incrementSeconds: 2 },
    variant: 'standard', rated: false, color: 'w', ratingRange: null, createdAt: 0,
  });
  return mockPlay.acceptSeek('s1'); // me is black
}

describe('MatchControls (Phase 5)', () => {
  it('offers a draw via the API (mock backend)', async () => {
    const match = setupMatch();
    const container = render(createElement(MatchControls, { match }));
    await click(container, 'Draw');
    expect(mockPlay.getMatch(match.id)?.drawOfferSide).toBe('b');
  });

  it('shows Accept/Decline for an opponent draw offer and accepting finishes the game', async () => {
    const match = setupMatch();
    mockPlay.getMatch(match.id)!.drawOfferSide = 'w';
    const container = render(createElement(MatchControls, { match: { ...match, drawOfferSide: 'w' } }));
    expect(container.textContent).toContain('Opponent offers draw');
    await click(container, 'Accept');
    expect(mockPlay.getMatch(match.id)?.status).toBe('finished');
    expect(mockPlay.getMatch(match.id)?.result).toEqual({ kind: 'draw', reason: 'agreement' });
  });

  it('declining clears the offer', async () => {
    const match = setupMatch();
    mockPlay.getMatch(match.id)!.drawOfferSide = 'w';
    const container = render(createElement(MatchControls, { match: { ...match, drawOfferSide: 'w' } }));
    await click(container, 'Decline');
    expect(mockPlay.getMatch(match.id)?.drawOfferSide).toBeNull();
    expect(mockPlay.getMatch(match.id)?.status).toBe('playing');
  });

  it('resigns via the API', async () => {
    const match = setupMatch();
    const container = render(createElement(MatchControls, { match }));
    await click(container, 'Resign');
    expect(mockPlay.getMatch(match.id)?.status).toBe('finished');
    expect(mockPlay.getMatch(match.id)?.result).toEqual({ kind: 'resign', winner: 'w' });
  });

  it('renders nothing when the match is finished', () => {
    const container = render(createElement(MatchControls, { match: makeMatch({ status: 'finished' }) }));
    expect(container.querySelector('.match-controls')).toBeNull();
  });
});