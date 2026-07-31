import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { createElement } from 'react';
import PlayCenter from './PlayCenter';
import { useWorkspaceStore } from '@/state/workspace';

async function renderToDiv(element: ReturnType<typeof createElement>): Promise<{ container: HTMLDivElement; root: Root }> {
  const container = document.createElement('div');
  document.body.appendChild(container);
  const root = createRoot(container);
  await act(async () => { root.render(element); });
  await act(async () => {});
  return { container, root };
}

describe('PlayCenter', () => {
  beforeEach(() => {
    useWorkspaceStore.getState().setPlayMode('analysis');
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('is hidden until the scidb:open-play event fires', async () => {
    const { container } = await renderToDiv(createElement(PlayCenter));
    expect(container.textContent).not.toContain('Online play');
    await act(async () => {
      window.dispatchEvent(new CustomEvent('scidb:open-play'));
    });
    expect(container.textContent).toContain('Online play');
  });

  it('closes on the close button', async () => {
    const { container } = await renderToDiv(createElement(PlayCenter));
    await act(async () => {
      window.dispatchEvent(new CustomEvent('scidb:open-play'));
    });
    const closeBtn = container.querySelector('.modal-close') as HTMLButtonElement;
    expect(closeBtn).toBeTruthy();
    await act(async () => { closeBtn.click(); });
    expect(container.textContent).not.toContain('Online play');
  });

  it('opens in play mode and the toolbar toggles the board-mode flag', async () => {
    const { container } = await renderToDiv(createElement(PlayCenter));
    await act(async () => {
      window.dispatchEvent(new CustomEvent('scidb:open-play'));
    });
    await act(async () => {});
    // Opening Play defaults the board to play mode.
    expect(useWorkspaceStore.getState().activePlayMode).toBe('play');
    expect(container.textContent).toContain('Board mode: play');
    // Switch to analysis.
    const analysisBtn = Array.from(container.querySelectorAll('button')).find(
      (b) => b.textContent === 'Analysis mode',
    ) as HTMLButtonElement;
    await act(async () => { analysisBtn.click(); });
    await act(async () => {});
    expect(useWorkspaceStore.getState().activePlayMode).toBe('analysis');
    expect(container.textContent).toContain('Board mode: analysis');
    // Back to play.
    const playBtn = Array.from(container.querySelectorAll('button')).find(
      (b) => b.textContent === 'Play mode',
    ) as HTMLButtonElement;
    await act(async () => { playBtn.click(); });
    await act(async () => {});
    expect(useWorkspaceStore.getState().activePlayMode).toBe('play');
  });
});