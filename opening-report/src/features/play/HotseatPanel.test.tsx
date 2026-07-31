import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { createElement } from 'react';
import HotseatPanel from './HotseatPanel';
import { useWorkspaceStore } from '@/state/workspace';

let currentRoot: Root | null = null;

function renderPanel(): { container: HTMLDivElement; root: Root } {
  const container = document.createElement('div');
  document.body.appendChild(container);
  const root = createRoot(container);
  currentRoot = root;
  act(() => { root.render(createElement(HotseatPanel)); });
  act(() => {});
  return { container, root };
}

afterEach(() => {
  const root = currentRoot;
  if (root) {
    act(() => { root.unmount(); });
    currentRoot = null;
  }
  document.body.innerHTML = '';
});

describe('HotseatPanel — board mode wiring (Phase 1)', () => {
  beforeEach(() => {
    useWorkspaceStore.getState().setPlayMode('analysis');
  });

  it('renders the board in analysis mode when activePlayMode=analysis (FEN bar visible, nav enabled)', () => {
    const { container } = renderPanel();
    expect(container.querySelector('.scidb-fen-bar')).toBeTruthy();
    const nav = container.querySelectorAll('.scidb-controls .ctrl-btn');
    expect((nav[0] as HTMLButtonElement).disabled).toBe(false);
  });

  it('renders the board in play mode when activePlayMode=play (FEN bar hidden, nav disabled)', () => {
    useWorkspaceStore.getState().setPlayMode('play');
    const { container } = renderPanel();
    expect(container.querySelector('.scidb-fen-bar')).toBeNull();
    const nav = container.querySelectorAll('.scidb-controls .ctrl-btn');
    expect((nav[0] as HTMLButtonElement).disabled).toBe(true);
  });

  it('switches board behaviour when activePlayMode changes after mount', () => {
    useWorkspaceStore.getState().setPlayMode('play');
    const { container } = renderPanel();
    expect(container.querySelector('.scidb-fen-bar')).toBeNull();
    act(() => { useWorkspaceStore.getState().setPlayMode('analysis'); });
    act(() => {});
    expect(container.querySelector('.scidb-fen-bar')).toBeTruthy();
    const nav = container.querySelectorAll('.scidb-controls .ctrl-btn');
    expect((nav[0] as HTMLButtonElement).disabled).toBe(false);
  });
});