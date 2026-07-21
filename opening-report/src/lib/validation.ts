/**
 * validation.ts — Pure input validation and sanitisation helpers.
 *
 * These functions are used both in the browser (React feature modules) and
 * are mirrored server-side in runtime_adapter.py so the two layers share
 * the same validation contract.
 */

import { Chess } from 'chess.js';

// ─── FEN validation ───────────────────────────────────────

const FEN_FIELD_COUNT = 6;
const FEN_MAX_LENGTH = 4096;

/**
 * Validate a FEN string without throwing.
 *
 * Checks structural correctness (6 whitespace-separated fields, legal piece
 * placement, side-to-move, castling, en-passant, halfmove, fullmove) and
 * delegates to chess.js for board-level legality.
 *
 * @param fen The FEN string to validate.
 * @returns `true` if the FEN is syntactically and semantically valid.
 */
export function isValidFen(fen: string): boolean {
  if (!fen || typeof fen !== 'string') return false;
  if (fen.length > FEN_MAX_LENGTH) return false;

  const parts = fen.trim().split(/\s+/);
  if (parts.length !== FEN_FIELD_COUNT) return false;

  const [placement, turn, castling, enPassant, halfmove, fullmove] = parts;

  // Piece placement: 8 ranks separated by '/'
  const ranks = placement.split('/');
  if (ranks.length !== 8) return false;

  // Validate each rank
  for (const rank of ranks) {
    let squares = 0;
    for (const ch of rank) {
      if (/[1-8]/.test(ch)) {
        squares += parseInt(ch, 10);
      } else if (/[pnbrqkPNBRQK]/.test(ch)) {
        squares += 1;
      } else {
        return false; // illegal character
      }
    }
    if (squares !== 8) return false;
  }

  // Side to move
  if (turn !== 'w' && turn !== 'b') return false;

  // Castling rights
  if (castling !== '-' && !/^K?Q?k?q?$/.test(castling)) return false;

  // En passant square
  if (enPassant !== '-' && !/^[a-h][36]$/.test(enPassant)) return false;

  // Half-move clock
  if (!/^\d+$/.test(halfmove)) return false;

  // Full-move number
  if (!/^[1-9]\d*$/.test(fullmove)) return false;

  // Defer to chess.js for semantic validation (king counts, checks, etc.)
  try {
    new Chess(fen);
    return true;
  } catch {
    return false;
  }
}

// ─── PGN validation ────────────────────────────────────────

const PGN_MAX_LENGTH = 268_435_456; // 256 MB safety cap for client-side checks

/**
 * Perform a basic structural validation of a PGN string.
 *
 * Checks that:
 *   - The string is not empty (after trimming) or absurdly long.
 *   - Header lines (if present) match `[Tag "Value"]` syntax.
 *   - The movetext section contains at least one plausible SAN move
 *     (e.g. `1. e4`, `e4`, `O-O`, `1-0`, `*`).
 *
 * This is **not** a full PGN parser — it is a fast rejection pass to catch
 * obviously malformed input before it reaches the server.
 *
 * @param pgn The PGN string to validate.
 * @returns `true` if the PGN passes basic structural checks.
 */
export function isValidPgn(pgn: string): boolean {
  if (!pgn || typeof pgn !== 'string') return false;
  const trimmed = pgn.trim();
  if (trimmed.length === 0) return false;
  if (trimmed.length > PGN_MAX_LENGTH) return false;

  const lines = trimmed.split('\n');

  // Validate header lines
  let movetextStarted = false;
  for (const line of lines) {
    const stripped = line.trim();
    if (stripped === '') continue;

    if (stripped.startsWith('[')) {
      if (movetextStarted) return false; // headers must precede movetext
      // Header line: [Tag "Value"]
      if (!/^\[\w+\s+"[^"]*"\]$/.test(stripped)) return false;
    } else {
      movetextStarted = true;
    }
  }

  // At least one movetext token or a result marker must be present.
  // Accept game terminations, move numbers, or SAN-like tokens.
  const movetextOnly = lines
    .filter((l) => !l.trim().startsWith('[') && l.trim() !== '')
    .join(' ');

  if (movetextOnly.length === 0) {
    // A PGN with only headers and no moves is valid (empty game).
    return true;
  }

  // Check for at least one result marker or a move-number / SAN token
  const hasResult = /\b(1-0|0-1|1\/2-1\/2|\*)\b/.test(movetextOnly);
  const hasMoveNumber = /\d+\.\s*[a-hNBRQKO]/.test(movetextOnly);
  const hasSanOnly = /\b[NBRQK]?[a-h]?[1-8](?:x[a-h]?[1-8])?(?:=[NBRQ])?[+#]?|O-O(?:-O)?\b/.test(movetextOnly);

  return hasResult || hasMoveNumber || hasSanOnly;
}

// ─── HTML sanitisation ────────────────────────────────────

/**
 * Escape HTML special characters to prevent XSS when rendering user-supplied
 * text (e.g. PGN comments, player names) as HTML.
 *
 * Escapes `<`, `>`, `&`, `"`, and `'`.
 *
 * @param text The raw string to sanitise.
 * @returns The escaped string, safe to insert into HTML.
 */
export function sanitizeHtml(text: string): string {
  if (!text || typeof text !== 'string') return '';
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ─── CQL validation ───────────────────────────────────────

const CQL_MAX_LENGTH = 65_536;

/**
 * Perform a basic structural validation of a CQL query string.
 *
 * Checks that:
 *   - The query is not empty or absurdly long.
 *   - Parentheses are balanced.
 *   - No raw HTML/script tags are present.
 *
 * This is a fast rejection pass; the server performs full validation before
 * execution.
 *
 * @param cql The CQL query string to validate.
 * @returns `true` if the CQL passes basic structural checks.
 */
export function isValidCql(cql: string): boolean {
  if (!cql || typeof cql !== 'string') return false;
  const trimmed = cql.trim();
  if (trimmed.length === 0) return false;
  if (trimmed.length > CQL_MAX_LENGTH) return false;

  // Reject raw HTML/script tags (defence in depth)
  if (/<\s*(script|iframe|object|embed)/i.test(trimmed)) return false;

  // Check balanced parentheses
  let depth = 0;
  for (const ch of trimmed) {
    if (ch === '(') depth++;
    else if (ch === ')') {
      depth--;
      if (depth < 0) return false;
    }
  }
  if (depth !== 0) return false;

  return true;
}