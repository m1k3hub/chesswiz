import { describe, it, expect } from 'vitest';
import {
  formatWDL,
  calculateFashionIndex,
  getFashionLabel,
  parsePGNHeaders,
  getPieceSymbol,
  deduplicateTactics,
} from './chess-helpers';

describe('formatWDL', () => {
  it('formats non-zero counts', () => {
    const result = formatWDL(40, 30, 30);
    expect(result.total).toBe(100);
    expect(result.whitePct).toBe('40.0');
    expect(result.drawPct).toBe('30.0');
    expect(result.blackPct).toBe('30.0');
  });

  it('returns zeros for all-zero input', () => {
    const result = formatWDL(0, 0, 0);
    expect(result.total).toBe(0);
    expect(result.whitePct).toBe('0');
  });
});

describe('calculateFashionIndex', () => {
  it('calculates percentage of recent games', () => {
    const currentYear = new Date().getFullYear();
    const yearlyData = [
      { year: currentYear - 1, count: 5 },
      { year: currentYear - 3, count: 3 },
      { year: currentYear - 10, count: 2 },
    ];
    const index = calculateFashionIndex(yearlyData);
    expect(index).toBe(80); // 8 out of 10 are recent
  });

  it('returns 0 for empty data', () => {
    expect(calculateFashionIndex([])).toBe(0);
  });
});

describe('getFashionLabel', () => {
  it('returns Very Fashionable for high index', () => {
    expect(getFashionLabel(70).label).toBe('Very Fashionable');
    expect(getFashionLabel(70).color).toBe('badge-green');
  });

  it('returns Declining for low index', () => {
    expect(getFashionLabel(10).label).toBe('Declining');
    expect(getFashionLabel(10).color).toBe('badge-red');
  });

  it('returns Stable for middle index', () => {
    expect(getFashionLabel(37).label).toBe('Stable');
  });
});

describe('parsePGNHeaders', () => {
  it('extracts PGN headers', () => {
    const pgn = '[Event "WCh 2021"]\n[White "Carlsen, Magnus"]\n[Black "Nepomniachtchi, Ian"]\n[Result "1/2-1/2"]\n1. d4 Nf6 *';
    const headers = parsePGNHeaders(pgn);
    expect(headers.Event).toBe('WCh 2021');
    expect(headers.White).toBe('Carlsen, Magnus');
    expect(headers.Black).toBe('Nepomniachtchi, Ian');
    expect(headers.Result).toBe('1/2-1/2');
  });

  it('returns empty object for PGN without headers', () => {
    expect(Object.keys(parsePGNHeaders('1. e4 e5 *')).length).toBe(0);
  });
});

describe('getPieceSymbol', () => {
  it('returns unicode for white pieces', () => {
    expect(getPieceSymbol('k', 'w')).toBe('♔');
    expect(getPieceSymbol('q', 'w')).toBe('♕');
    expect(getPieceSymbol('p', 'w')).toBe('♙');
  });

  it('returns unicode for black pieces', () => {
    expect(getPieceSymbol('k', 'b')).toBe('♚');
    expect(getPieceSymbol('n', 'b')).toBe('♞');
  });
});

describe('deduplicateTactics', () => {
  it('removes tactics with same position', () => {
    const tactics = [
      { fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', solution: 'e4', solutionUci: 'e2e4', motif: 'test', turn: 'w', moveNum: 1, gamePgn: '' },
      { fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 1', solution: 'Nf3', solutionUci: 'g1f3', motif: 'test2', turn: 'w', moveNum: 1, gamePgn: '' },
      { fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1', solution: 'e5', solutionUci: 'e7e5', motif: 'test3', turn: 'b', moveNum: 1, gamePgn: '' },
    ];
    const result = deduplicateTactics(tactics);
    // First and third have same piece placement so deduped; second is unique
    expect(result.length).toBe(2);
  });
});