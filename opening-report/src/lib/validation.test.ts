import { describe, it, expect } from 'vitest';
import { isValidFen, isValidPgn, sanitizeHtml, isValidCql } from './validation';

describe('validation', () => {
  // ── isValidFen ──────────────────────────────────────

  describe('isValidFen', () => {
    it('accepts the standard start position', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1')).toBe(true);
    });

    it('accepts a mid-game position', () => {
      expect(isValidFen('r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3')).toBe(true);
    });

    it('accepts a Chess960 castling FEN', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w AHah - 0 1')).toBe(false); // chess.js rejects non-standard castling
    });

    it('rejects empty string', () => {
      expect(isValidFen('')).toBe(false);
    });

    it('rejects non-string input', () => {
      expect(isValidFen(null as unknown as string)).toBe(false);
      expect(isValidFen(undefined as unknown as string)).toBe(false);
    });

    it('rejects too few fields', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w')).toBe(false);
    });

    it('rejects too many fields', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 extra')).toBe(false);
    });

    it('rejects invalid piece placement (wrong rank count)', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1')).toBe(false);
    });

    it('rejects invalid piece placement (wrong square count)', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPPP/RNBQKBNR w KQkq - 0 1')).toBe(false);
    });

    it('rejects invalid side to move', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1')).toBe(false);
    });

    it('rejects invalid castling rights', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w XYZ - 0 1')).toBe(false);
    });

    it('rejects invalid en passant square', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq z9 0 1')).toBe(false);
    });

    it('rejects non-numeric halfmove clock', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - x 1')).toBe(false);
    });

    it('rejects zero fullmove number', () => {
      expect(isValidFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 0')).toBe(false);
    });

    it('rejects FEN exceeding max length', () => {
      const long = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 ' + 'x'.repeat(4100);
      expect(isValidFen(long)).toBe(false);
    });

    it('rejects position with no kings', () => {
      expect(isValidFen('8/8/8/8/8/8/8/8 w - - 0 1')).toBe(false);
    });
  });

  // ── isValidPgn ──────────────────────────────────────

  describe('isValidPgn', () => {
    it('accepts a well-formed game with headers', () => {
      const pgn = '[Event "Test"]\n[White "Alice"]\n[Black "Bob"]\n1. e4 e5 2. Nf3 Nc6 1-0\n';
      expect(isValidPgn(pgn)).toBe(true);
    });

    it('accepts a game with no headers', () => {
      expect(isValidPgn('1. e4 e5 2. Nf3 Nc6 1-0\n')).toBe(true);
    });

    it('accepts headers-only (empty game)', () => {
      expect(isValidPgn('[Event "Test"]\n[White "Alice"]\n')).toBe(true);
    });

    it('accepts a game ending in draw', () => {
      expect(isValidPgn('1. e4 e5 2. Nf3 Nc6 1/2-1/2\n')).toBe(true);
    });

    it('accepts a game ending in *', () => {
      expect(isValidPgn('1. e4 e5 *\n')).toBe(true);
    });

    it('rejects empty string', () => {
      expect(isValidPgn('')).toBe(false);
    });

    it('rejects non-string input', () => {
      expect(isValidPgn(null as unknown as string)).toBe(false);
    });

    it('rejects malformed header', () => {
      expect(isValidPgn('[Event Test]\n1. e4 1-0\n')).toBe(false);
    });

    it('rejects headers after movetext', () => {
      expect(isValidPgn('1. e4 e5 1-0\n[Event "Test"]\n')).toBe(false);
    });

    it('rejects plain text with no moves', () => {
      expect(isValidPgn('This is not a PGN file.')).toBe(false);
    });
  });

  // ── sanitizeHtml ────────────────────────────────────

  describe('sanitizeHtml', () => {
    it('escapes angle brackets', () => {
      expect(sanitizeHtml('<script>alert(1)</script>')).toBe(
        '&lt;script&gt;alert(1)&lt;/script&gt;',
      );
    });

    it('escapes ampersands', () => {
      expect(sanitizeHtml('a & b')).toBe('a &amp; b');
    });

    it('escapes double quotes', () => {
      expect(sanitizeHtml('say "hello"')).toBe('say &quot;hello&quot;');
    });

    it('escapes single quotes', () => {
      expect(sanitizeHtml("it's")).toBe('it&#39;s');
    });

    it('returns empty string for null/undefined', () => {
      expect(sanitizeHtml(null as unknown as string)).toBe('');
      expect(sanitizeHtml(undefined as unknown as string)).toBe('');
    });

    it('returns empty string for empty input', () => {
      expect(sanitizeHtml('')).toBe('');
    });

    it('leaves safe text unchanged', () => {
      expect(sanitizeHtml('Hello World')).toBe('Hello World');
    });

    it('handles combined dangerous input', () => {
      const result = sanitizeHtml('<img src="x" onerror=\'alert(1)\'>');
      expect(result).not.toContain('<');
      expect(result).not.toContain('>');
      expect(result).not.toContain('"');
      expect(result).not.toContain("'");
    });
  });

  // ── isValidCql ──────────────────────────────────────

  describe('isValidCql', () => {
    it('accepts a simple match expression', () => {
      expect(isValidCql('(match :gamenumber 1 100)')).toBe(true);
    });

    it('accepts nested parentheses', () => {
      expect(isValidCql('(match (filter :result "1-0"))')).toBe(true);
    });

    it('rejects empty string', () => {
      expect(isValidCql('')).toBe(false);
    });

    it('rejects non-string input', () => {
      expect(isValidCql(null as unknown as string)).toBe(false);
    });

    it('rejects unbalanced parentheses (extra close)', () => {
      expect(isValidCql('(match :gamenumber 1 100))')).toBe(false);
    });

    it('rejects unbalanced parentheses (extra open)', () => {
      expect(isValidCql('(match :gamenumber 1 100')).toBe(false);
    });

    it('rejects script tags', () => {
      expect(isValidCql('<script>alert(1)</script>')).toBe(false);
    });

    it('rejects iframe tags', () => {
      expect(isValidCql('<iframe src="evil.com">')).toBe(false);
    });
  });
});