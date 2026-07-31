import { describe, it, expect, vi, afterEach } from 'vitest';
import { createRoot } from 'react-dom/client';
import { act } from 'react';
import { createElement } from 'react';
import PromotionPicker from './PromotionPicker';

function renderPicker(props: { color: 'w' | 'b'; onSelect: (p: 'q' | 'r' | 'b' | 'n') => void; onCancel: () => void }) {
  const container = document.createElement('div');
  document.body.appendChild(container);
  const root = createRoot(container);
  act(() => { root.render(createElement(PromotionPicker, props)); });
  act(() => {});
  return { container, root };
}

afterEach(() => { document.body.innerHTML = ''; });

describe('PromotionPicker', () => {
  it('renders four choices in q/r/b/n order', () => {
    const { container } = renderPicker({ color: 'w', onSelect: () => {}, onCancel: () => {} });
    const choices = container.querySelectorAll('.promotion-choice');
    expect(choices).toHaveLength(4);
    expect((choices[0] as HTMLButtonElement).getAttribute('aria-label')).toBe('q');
    expect((choices[1] as HTMLButtonElement).getAttribute('aria-label')).toBe('r');
    expect((choices[2] as HTMLButtonElement).getAttribute('aria-label')).toBe('b');
    expect((choices[3] as HTMLButtonElement).getAttribute('aria-label')).toBe('n');
  });

  it('calls onSelect with the chosen piece', () => {
    const onSelect = vi.fn();
    const { container } = renderPicker({ color: 'b', onSelect, onCancel: () => {} });
    act(() => { (container.querySelectorAll('.promotion-choice')[2] as HTMLButtonElement).click(); });
    expect(onSelect).toHaveBeenCalledWith('b');
  });

  it('calls onCancel when the overlay backdrop is clicked', () => {
    const onCancel = vi.fn();
    const { container } = renderPicker({ color: 'w', onSelect: () => {}, onCancel });
    const overlay = container.querySelector('.promotion-picker-overlay') as HTMLElement;
    expect(overlay).toBeTruthy();
    act(() => { overlay.click(); });
    expect(onCancel).toHaveBeenCalled();
  });
});