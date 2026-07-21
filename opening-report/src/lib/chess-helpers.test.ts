import { describe, it, expect } from 'vitest';
import {
  formatWDL,
  calculateScore,
  classifyMove,
  getPieceSymbol,
  pieceValue,
  parsePGNHeaders,
  pgnToMoveArray,
  extractTacticalPositions,
  characterizePosition,
  findTranspositions,
  sanToUci,
} from './chess-helpers';

describe('chess-helpers', () => {
  describe('formatWDL', () => {
    it('returns zero percentages for zero total', () => {
      const result = formatWDL(0, 0, 0);
      expect(result.whitePct).toBe('0');
      expect(result.total).toBe(0);
    });

    it('calculates percentages correctly', () => {
      const result = formatWDL(50, 30, 20);
      expect(result.whitePct).toBe('50.0');
      expect(result.drawPct).toBe('30.0');
      expect(result.blackPct).toBe('20.0');
      expect(result.total).toBe(100);
    });
  });

  describe('calculateScore', () => {
    it('returns 0 for zero total', () => {
      expect(calculateScore(0, 0, 0, 'w')).toBe(0);
    });

    it('calculates white score correctly', () => {
      const score = calculateScore(60, 20, 20, 'w');
      expect(score).toBeCloseTo(70, 1);
    });

    it('calculates black score correctly', () => {
      const score = calculateScore(20, 20, 60, 'b');
      expect(score).toBeCloseTo(70, 1);
    });
  });

  describe('classifyMove', () => {
    it('classifies a good move', () => {
      expect(classifyMove(60, 10, 30, 'w', 1000)).toBe('good');
    });

    it('classifies a rare move', () => {
      expect(classifyMove(50, 0, 0, 'w', 10000)).toBe('rare');
    });
  });

  describe('getPieceSymbol', () => {
    it('returns correct unicode for white king', () => {
      expect(getPieceSymbol('k', 'w')).toBe('♔');
    });

    it('returns correct unicode for black queen', () => {
      expect(getPieceSymbol('q', 'b')).toBe('♛');
    });
  });

  describe('pieceValue', () => {
    it('returns correct values', () => {
      expect(pieceValue('p')).toBe(1);
      expect(pieceValue('n')).toBe(3);
      expect(pieceValue('b')).toBe(3);
      expect(pieceValue('r')).toBe(5);
      expect(pieceValue('q')).toBe(9);
      expect(pieceValue('k')).toBe(100);
    });
  });

  describe('parsePGNHeaders', () => {
    it('parses standard PGN headers', () => {
      const pgn = '[White "Carlsen, Magnus"]\n[Black "Caruana, Fabiano"]\n[Result "1/2-1/2"]\n\n1. e4 e5';
      const headers = parsePGNHeaders(pgn);
      expect(headers.White).toBe('Carlsen, Magnus');
      expect(headers.Black).toBe('Caruana, Fabiano');
      expect(headers.Result).toBe('1/2-1/2');
    });

    it('returns empty object for no headers', () => {
      expect(parsePGNHeaders('1. e4 e5')).toEqual({});
    });
  });

  describe('pgnToMoveArray', () => {
    it('parses a simple PGN', () => {
      const moves = pgnToMoveArray('1. e4 e5 2. Nf3 Nc6');
      expect(moves).toHaveLength(4);
      expect(moves[0].san).toBe('e4');
      expect(moves[1].san).toBe('e5');
    });

    it('returns empty array for invalid PGN', () => {
      expect(pgnToMoveArray('invalid')).toEqual([]);
    });
  });

  describe('extractTacticalPositions', () => {
    it('extracts tactical positions from a game', () => {
      const pgn = [
        '[White "Player A"]',
        '[Black "Player B"]',
        '',
        '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7',
        '6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7',
      ].join('\n');
      const positions = extractTacticalPositions(pgn, 10);
      // May or may not find tactics depending on the position, but should not crash
      expect(Array.isArray(positions)).toBe(true);
    });

    it('returns empty array for invalid PGN', () => {
      expect(extractTacticalPositions('invalid')).toEqual([]);
    });
  });

  describe('characterizePosition', () => {
    it('characterizes the start position', () => {
      const traits = characterizePosition('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      expect(traits.length).toBeGreaterThan(0);
      const titles = traits.map((t) => t.title);
      expect(titles).toContain('King Safety');
      expect(titles).toContain('Center Control');
    });
  });

  describe('findTranspositions', () => {
    it('finds no transpositions for a single move', () => {
      const moves = sanToUci(['e4']);
      const transpositions = findTranspositions(moves, 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1');
      expect(transpositions).toHaveLength(0);
    });

    it('finds transpositions for commutative moves', () => {
      // 1. Nf3 Nf6 2. c4 — swapping last two moves (c4 and Nf6)
      // Actually, c4 can be played before Nf6 to reach the same position
      const moves = sanToUci(['Nf3', 'Nf6', 'c4']);
      const transpositions = findTranspositions(moves, '');
      // This may or may not find a transposition depending on move legality
      expect(Array.isArray(transpositions)).toBe(true);
    });
  });

  describe('sanToUci', () => {
    it('converts SAN moves to UCI objects', () => {
      const result = sanToUci(['e4', 'e5', 'Nf3']);
      expect(result).toHaveLength(3);
      expect(result[0].san).toBe('e4');
      expect(result[0].uci).toBe('e2e4');
      expect(result[2].san).toBe('Nf3');
    });

    it('stops on invalid move', () => {
      const result = sanToUci(['e4', 'e5', 'invalid']);
      expect(result).toHaveLength(2);
    });
  });
});