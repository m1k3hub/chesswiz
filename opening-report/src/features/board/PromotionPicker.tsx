/*
 * PromotionPicker — overlay that asks the user to choose a promotion piece.
 *
 * Shown by ChessBoard in play mode when a pawn move reaches the last rank.
 * Analysis mode keeps the legacy auto-queen behaviour, so the picker is only
 * used when `mode === 'play'`.
 */

export type PromoPiece = 'q' | 'r' | 'b' | 'n';

export interface PromotionPickerProps {
  color: 'w' | 'b';
  onSelect: (piece: PromoPiece) => void;
  onCancel: () => void;
}

const GLYPH: Record<PromoPiece, string> = {
  q: '♛',
  r: '♜',
  b: '♝',
  n: '♞',
};

const ORDER: PromoPiece[] = ['q', 'r', 'b', 'n'];

export default function PromotionPicker({ color, onSelect, onCancel }: PromotionPickerProps) {
  return (
    <div
      className="promotion-picker-overlay"
      onClick={(e) => {
        if (e.target === e.currentTarget) onCancel();
      }}
    >
      <div className="promotion-picker" role="dialog" aria-label="Choose promotion piece">
        <div className="promotion-picker-title">Promote to</div>
        <div className="promotion-picker-choices">
          {ORDER.map((p) => (
            <button
              key={p}
              className={`promotion-choice ${color === 'w' ? 'white' : 'black'}`}
              onClick={() => onSelect(p)}
              aria-label={p}
            >
              {GLYPH[p]}
            </button>
          ))}
        </div>
        <button className="promotion-cancel" onClick={onCancel}>Cancel</button>
      </div>
    </div>
  );
}