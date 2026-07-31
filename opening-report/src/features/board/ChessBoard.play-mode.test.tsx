import { describe, it, expect, afterEach } from 'vitest';
import { createRoot, type Root } from 'react-dom/client';
import { act, createRef } from 'react';
import { createElement } from 'react';
import ChessBoard, { type ChessBoardHandle } from '@/features/board/ChessBoard';

interface RenderResult {
  container: HTMLDivElement;
  root: Root;
  ref: ReturnType<typeof createRef<ChessBoardHandle>>;
}

function renderBoard(props: Record<string, unknown> = {}): RenderResult {
  const ref = createRef<ChessBoardHandle>();
  const container = document.createElement('div');
  document.body.appendChild(container);
  const root = createRoot(container);
  act(() => {
    root.render(createElement(ChessBoard, { ref, ...props } as never));
  });
  act(() => {});
  return { container, root, ref };
}

function clickSquare(container: HTMLElement, square: string) {
  const el = container.querySelector(`[data-square="${square}"]`) as HTMLElement;
  expect(el).toBeTruthy();
  act(() => {
    el.click();
  });
  act(() => {});
}

function isSquareSelected(container: HTMLElement, square: string): boolean {
  const el = container.querySelector(`[data-square="${square}"]`);
  return !!el?.classList.contains('selected');
}

afterEach(() => {
  document.body.innerHTML = '';
});

describe('ChessBoard — play mode (Phase 1)', () => {
  it('disables navigation buttons and hides the FEN bar in play mode', () => {
    const { container } = renderBoard({ mode: 'play' });
    const nav = container.querySelectorAll('.scidb-controls .ctrl-btn');
    // First four are ⏮ ◀ ▶ ⏭ (flip is the 5th and stays enabled).
    expect((nav[0] as HTMLButtonElement).disabled).toBe(true);
    expect((nav[1] as HTMLButtonElement).disabled).toBe(true);
    expect((nav[2] as HTMLButtonElement).disabled).toBe(true);
    expect((nav[3] as HTMLButtonElement).disabled).toBe(true);
    expect((nav[4] as HTMLButtonElement).disabled).toBe(false);
    expect(container.querySelector('.scidb-fen-bar')).toBeNull();
  });

  it('applyExternalMove applies a legal move and rejects an illegal one', () => {
    const { ref } = renderBoard({ mode: 'play' });
    expect(ref.current).toBeTruthy();
    let ok = false;
    act(() => { ok = ref.current!.applyExternalMove('e2e4'); });
    expect(ok).toBe(true);
    expect(ref.current!.getMoves()).toHaveLength(1);
    expect(ref.current!.getMoves()[0].uci).toBe('e2e4');
    act(() => { ok = ref.current!.applyExternalMove('e2e5'); }); // illegal pawn double from e2 after e4
    expect(ok).toBe(false);
    expect(ref.current!.getMoves()).toHaveLength(1);
  });

  it('in play mode with myColor=w, the opponent (black) pieces cannot be selected on black turn', () => {
    const { container, ref } = renderBoard({ mode: 'play', myColor: 'w' });
    act(() => { ref.current!.applyExternalMove('e2e4'); }); // now black to move
    clickSquare(container, 'e7');
    expect(isSquareSelected(container, 'e7')).toBe(false);
  });

  it('in hotseat play mode (no myColor), either side may be selected on its turn', () => {
    const { container, ref } = renderBoard({ mode: 'play' });
    act(() => { ref.current!.applyExternalMove('e2e4'); }); // black to move
    clickSquare(container, 'e7');
    expect(isSquareSelected(container, 'e7')).toBe(true);
  });

  it('shows the promotion picker in play mode and applies the chosen piece', () => {
    const fen = '7k/4P3/8/8/8/8/8/4K2Q w - - 0 1'; // white pawn e7, white to move
    const { container, ref } = renderBoard({ mode: 'play', startFen: fen });
    clickSquare(container, 'e7'); // select pawn
    expect(isSquareSelected(container, 'e7')).toBe(true);
    clickSquare(container, 'e8'); // promotion target → opens picker
    const choices = container.querySelectorAll('.promotion-choice');
    expect(choices.length).toBe(4);
    act(() => { (choices[0] as HTMLButtonElement).click(); }); // queen
    act(() => {});
    const moves = ref.current!.getMoves();
    expect(moves).toHaveLength(1);
    expect(moves[0].uci).toBe('e7e8q');
    expect(ref.current!.getCurrentFen()).toContain('Q');
  });

  it('analysis mode is unchanged: FEN bar present, nav enabled, auto-queen (no picker)', () => {
    const { container, ref } = renderBoard({
      mode: 'analysis',
      startFen: '7k/4P3/8/8/8/8/8/4K2Q w - - 0 1',
    });
    expect(container.querySelector('.scidb-fen-bar')).toBeTruthy();
    const nav = container.querySelectorAll('.scidb-controls .ctrl-btn');
    expect((nav[0] as HTMLButtonElement).disabled).toBe(false);
    let ok = false;
    act(() => { ok = ref.current!.applyExternalMove('e7e8q'); });
    expect(ok).toBe(true);
    expect(container.querySelector('.promotion-picker')).toBeNull();
    expect(ref.current!.getMoves()[0].uci).toBe('e7e8q');
  });
});