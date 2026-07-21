/**
 * game-helpers.ts — helpers for building and navigating the game editor move tree.
 *
 * These pure functions convert SAN move arrays into EditorMove[] with FENs
 * via chess.js, and provide navigation utilities for the game editor.
 */

import { Chess } from 'chess.js';
import type { EditorMove, MoveEntry } from '@/types';

export interface MoveTreeNode {
  move: EditorMove;
  children: MoveTreeNode[];
}

/**
 * Build a flat array of EditorMove objects from a list of SAN moves.
 * Each move gets a unique id, the resulting FEN, and ply/color metadata.
 * Variations, NAGs, annotations, and comments are initialised empty.
 */
export function buildMoveTreeFromSan(sanMoves: string[]): EditorMove[] {
  const chess = new Chess();
  const moves: EditorMove[] = [];
  let ply = 0;

  for (const san of sanMoves) {
    try {
      const move = chess.move(san);
      if (!move) break;
      ply += 1;
      moves.push({
        id: `m-${ply}`,
        san: move.san,
        uci: move.from + move.to + (move.promotion || ''),
        fen: chess.fen(),
        color: move.color,
        ply,
        nags: [],
        annotations: [],
        variations: [],
      });
    } catch {
      break;
    }
  }

  return moves;
}

/**
 * Extract SAN tokens from a PGN movetext string.
 * Removes comments, variations, NAGs, move numbers, and results.
 */
export function extractSanFromPgn(pgn: string): string[] {
  const movetext = pgn
    .split('\n')
    .filter((l) => !l.startsWith('['))
    .join(' ');

  return movetext
    .replace(/\{[^}]*}/g, '')
    .replace(/\([^)]*\)/g, '')
    .replace(/\$\d+/g, '')
    .split(/\s+/)
    .filter((t) => t && !t.match(/^\d+\.$/) && !['1-0', '0-1', '1/2-1/2', '*'].includes(t));
}

/**
 * Convert EditorMove[] to the MoveEntry[] format used by the report engine.
 */
export function editorMovesToMoveEntries(moves: EditorMove[]): MoveEntry[] {
  return moves.map((m) => ({ san: m.san, uci: m.uci }));
}

/**
 * Get the FEN at a given ply in the move list (0 = start position).
 */
export function fenAtPly(moves: EditorMove[], ply: number): string {
  if (ply <= 0 || !moves.length) {
    return 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  }
  const idx = Math.min(ply, moves.length) - 1;
  return moves[idx]?.fen || 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
}