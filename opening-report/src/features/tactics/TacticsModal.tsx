import { useEffect, useState, useRef, useCallback } from 'react';
import { Chess } from 'chess.js';
import type { TacticPosition } from '@/lib/chess-helpers';
import MiniBoard from '@/features/board/MiniBoard';

interface TacticsEventDetail {
  tactics: TacticPosition[];
  startIndex: number;
}

export default function TacticsModal() {
  const [isOpen, setIsOpen] = useState(false);
  const [tactics, setTactics] = useState<TacticPosition[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [inputValue, setInputValue] = useState('');
  const [resultText, setResultText] = useState('');
  const [resultClass, setResultClass] = useState('tactic-result');
  const [showSolutionVisible, setShowSolutionVisible] = useState(false);
  const [selectedSquare, setSelectedSquare] = useState<string | null>(null);
  const [validTargets, setValidTargets] = useState<Set<string>>(new Set());

  const inputRef = useRef<HTMLInputElement>(null);

  const currentTactic = tactics[currentIndex];

  const loadTactic = useCallback(
    (index: number) => {
      if (index < 0 || index >= tactics.length) return;
      setCurrentIndex(index);
      setInputValue('');
      setResultText('');
      setResultClass('tactic-result');
      setShowSolutionVisible(false);
      setSelectedSquare(null);
      setValidTargets(new Set());
    },
    [tactics],
  );

  useEffect(() => {
    const handleOpen = (event: Event) => {
      const detail = (event as CustomEvent<TacticsEventDetail>).detail;
      if (!detail || !detail.tactics || detail.tactics.length === 0) return;
      setTactics(detail.tactics);
      setCurrentIndex(detail.startIndex || 0);
      setIsOpen(true);
    };
    window.addEventListener('scidb:open-tactics', handleOpen);
    return () => window.removeEventListener('scidb:open-tactics', handleOpen);
  }, []);

  // Focus input when modal opens
  useEffect(() => {
    if (isOpen) {
      const timer = setTimeout(() => inputRef.current?.focus(), 100);
      return () => clearTimeout(timer);
    }
  }, [isOpen]);

  // Reset selection when tactic changes
  useEffect(() => {
    setSelectedSquare(null);
    setValidTargets(new Set());
  }, [currentIndex]);

  const handleSquareClick = useCallback(
    (square: string) => {
      if (!currentTactic) return;

      if (selectedSquare && validTargets.has(square)) {
        // Attempt to make the move
        const tempChess = new Chess(currentTactic.fen);
        try {
          const move = tempChess.move({ from: selectedSquare, to: square, promotion: 'q' });
          if (move) {
            const moveUci = move.from + move.to + (move.promotion || '');
            if (moveUci === currentTactic.solutionUci || move.san === currentTactic.solution) {
              setResultText(`✓ Correct! ${move.san} is the best move!`);
              setResultClass('tactic-result correct');
              setShowSolutionVisible(false);
            } else {
              if (move.flags.includes('c') || move.san.includes('+') || move.san.includes('#')) {
                setResultText(`Not quite — you played ${move.san}. The best move is different. Try again or click "Show Solution".`);
              } else {
                setResultText(`❌ ${move.san} is not the best move. Try again!`);
              }
              setResultClass('tactic-result wrong');
              setShowSolutionVisible(true);
            }
            setSelectedSquare(null);
            setValidTargets(new Set());
            return;
          }
        } catch {
          // fall through
        }
      }

      if (square === selectedSquare) {
        setSelectedSquare(null);
        setValidTargets(new Set());
        return;
      }

      // Select a piece if it belongs to the side to move
      const tempChess = new Chess(currentTactic.fen);
      try {
        const piece = tempChess.get(square as never);
        if (piece && piece.color === tempChess.turn()) {
          setSelectedSquare(square);
          const moves = tempChess.moves({ square: square as never, verbose: true });
          setValidTargets(new Set(moves.map((m) => m.to)));
        } else {
          setSelectedSquare(null);
          setValidTargets(new Set());
        }
      } catch {
        setSelectedSquare(null);
        setValidTargets(new Set());
      }
    },
    [currentTactic, selectedSquare, validTargets],
  );

  const checkMove = () => {
    const input = inputValue.trim();
    if (!input || !currentTactic) return;

    const tempChess = new Chess(currentTactic.fen);
    try {
      const move = tempChess.move(input);
      if (move) {
        const moveUci = move.from + move.to + (move.promotion || '');
        if (moveUci === currentTactic.solutionUci || move.san === currentTactic.solution) {
          setResultText(`✓ Correct! ${move.san} is the best move!`);
          setResultClass('tactic-result correct');
          setShowSolutionVisible(false);
        } else {
          if (move.flags.includes('c') || move.san.includes('+') || move.san.includes('#')) {
            setResultText(`Not quite — you played ${move.san}. The best move is different. Try again or click "Show Solution".`);
          } else {
            setResultText(`❌ ${move.san} is not the best move. Try again!`);
          }
          setResultClass('tactic-result wrong');
          setShowSolutionVisible(true);
        }
      } else {
        setResultText('Invalid move. Try again!');
        setResultClass('tactic-result wrong');
      }
    } catch {
      setResultText('Invalid move. Try again!');
      setResultClass('tactic-result wrong');
    }
  };

  const showSolution = () => {
    if (!currentTactic) return;
    setResultText(`The solution is: ${currentTactic.solution}`);
    setResultClass('tactic-result');
  };

  const handleClose = () => {
    setIsOpen(false);
    setSelectedSquare(null);
    setValidTargets(new Set());
  };

  if (!isOpen) return null;

  const tactic = currentTactic;

  return (
    <div
      id="tactics-modal"
      className="modal"
      style={{ display: 'flex' }}
      onClick={(e) => {
        if (e.target === e.currentTarget) handleClose();
      }}
    >
      <div className="modal-content">
        <div className="modal-header">
          <h3>
            ⚡ Tactical Training — <span id="tactic-title">{tactic?.motif || ''}</span>
          </h3>
          <button id="tactics-close" className="modal-close" onClick={handleClose}>
            ✕
          </button>
        </div>
        <div className="modal-body">
          <div id="tactics-board" style={{ width: '100%', maxWidth: '400px' }}>
            {tactic && (
              <MiniBoard
                fen={tactic.fen}
                onSquareClick={handleSquareClick}
                selectedSquare={selectedSquare}
                validTargets={validTargets}
              />
            )}
          </div>
          <div id="tactics-info">
            <p id="tactics-prompt" className="tactic-prompt">
              {tactic ? `${tactic.turn === 'w' ? 'White' : 'Black'} to move — find the best continuation!` : ''}
            </p>
            <p id="tactics-turn" className="tactic-turn">
              {tactic ? `Move ${tactic.moveNum} from the original game` : ''}
            </p>
            <input
              type="text"
              id="tactics-input"
              ref={inputRef}
              placeholder="Enter your move (e.g. Nf3)…"
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') checkMove();
              }}
            />
            <button id="tactics-check" className="small-btn" onClick={checkMove}>
              Check Move
            </button>
            <p id="tactics-result" className={resultClass}>
              {resultText}
            </p>
            {showSolutionVisible && (
              <button id="tactics-show" className="small-btn" onClick={showSolution}>
                Show Solution
              </button>
            )}
            <div id="tactics-nav">
              <button
                id="tactics-prev"
                className="ctrl-btn"
                disabled={currentIndex === 0}
                onClick={() => loadTactic(currentIndex - 1)}
              >
                ◀ Prev
              </button>
              <span id="tactics-counter">
                {tactics.length > 0 ? `${currentIndex + 1} / ${tactics.length}` : ''}
              </span>
              <button
                id="tactics-next"
                className="ctrl-btn"
                disabled={currentIndex === tactics.length - 1}
                onClick={() => loadTactic(currentIndex + 1)}
              >
                Next ▶
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}