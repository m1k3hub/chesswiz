/**
 * game-editor.test.ts — unit tests for the mock API game endpoints
 * and the move-tree builder helpers.
 */

import { describe, it, expect } from 'vitest';
import { MockScidbApiClient } from '@/api/client';
import {
  buildMoveTreeFromSan,
  extractSanFromPgn,
  fenAtPly,
  editorMovesToMoveEntries,
} from './game-helpers';

describe('MockScidbApiClient game editor endpoints', () => {
  const client = new MockScidbApiClient();

  it('loads a game with headers, moves, and pgn', async () => {
    const game = await client.getGame('g-001');
    expect(game.id).toBe('g-001');
    expect(game.headers.White).toBe('Carlsen, Magnus');
    expect(game.headers.Black).toBe('Nepomniachtchi, Ian');
    expect(game.headers.Event).toBe('WCh 2021');
    expect(game.moves.length).toBeGreaterThan(0);
    expect(game.pgn).toContain('[Event "WCh 2021"]');
  });

  it('loads a different game', async () => {
    const game = await client.getGame('g-002');
    expect(game.headers.White).toBe('Kasparov, Garry');
    expect(game.moves.length).toBeGreaterThan(0);
  });

  it('updates game headers', async () => {
    const updated = await client.updateGame('g-001', {
      headers: { Event: 'Updated Event' },
    });
    expect(updated.headers.Event).toBe('Updated Event');
    expect(updated.headers.White).toBe('Carlsen, Magnus');
  });

  it('adds a variation to a move', async () => {
    const game = await client.getGame('g-001');
    const firstMove = game.moves[0];
    expect(firstMove).toBeDefined();

    const updated = await client.addVariation('g-001', {
      parentMoveId: firstMove.id,
      moves: [{ san: 'd4' }],
    });
    const updatedMove = updated.moves[0];
    expect(updatedMove.variations.length).toBe(1);
    expect(updatedMove.variations[0].moves.length).toBe(1);
  });

  it('sets a comment on a move', async () => {
    const game = await client.getGame('g-001');
    const moveId = game.moves[0].id;
    const updated = await client.setMoveComment('g-001', moveId, {
      comment: { text: 'A good opening move' },
    });
    expect(updated.moves[0].comment?.text).toBe('A good opening move');
  });
});

describe('buildMoveTreeFromSan', () => {
  it('builds moves from a simple SAN sequence', () => {
    const moves = buildMoveTreeFromSan(['e4', 'e5', 'Nf3', 'Nc6']);
    expect(moves).toHaveLength(4);
    expect(moves[0].san).toBe('e4');
    expect(moves[0].color).toBe('w');
    expect(moves[0].ply).toBe(1);
    expect(moves[0].uci).toBe('e2e4');
    expect(moves[0].fen).toBeTruthy();
    expect(moves[1].san).toBe('e5');
    expect(moves[1].color).toBe('b');
    expect(moves[2].san).toBe('Nf3');
    expect(moves[3].san).toBe('Nc6');
  });

  it('stops at an illegal move', () => {
    // After 1.e4 e5 2.Qh5, Ke7 is actually legal (e7 is vacated).
    // Use Be7 which blocks the king but is actually legal too.
    // Use an obviously illegal move: Ra5 after e4 e5 (rook can't reach a5)
    const moves = buildMoveTreeFromSan(['e4', 'e5', 'Ra5']);
    // Ra5 is illegal (rook can't jump pawn), so the sequence stops at 2
    expect(moves.length).toBe(2);
  });

  it('initialises empty nags, annotations, variations', () => {
    const moves = buildMoveTreeFromSan(['d4']);
    expect(moves[0].nags).toEqual([]);
    expect(moves[0].annotations).toEqual([]);
    expect(moves[0].variations).toEqual([]);
  });
});

describe('extractSanFromPgn', () => {
  it('extracts SAN moves from a PGN string', () => {
    const pgn = '[Event "Test"]\n[White "A"]\n[Black "B"]\n1. e4 e5 2. Nf3 Nc6 1-0';
    const sans = extractSanFromPgn(pgn);
    expect(sans).toEqual(['e4', 'e5', 'Nf3', 'Nc6']);
  });

  it('strips comments and variations', () => {
    const pgn = '[Event "Test"]\n1. e4 {good move} e5 (1...c5 2. Nf3) 2. Nf3 *';
    const sans = extractSanFromPgn(pgn);
    expect(sans).toEqual(['e4', 'e5', 'Nf3']);
  });
});

describe('fenAtPly', () => {
  const moves = buildMoveTreeFromSan(['e4', 'e5']);

  it('returns start position at ply 0', () => {
    const fen = fenAtPly(moves, 0);
    expect(fen).toBe('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
  });

  it('returns the correct FEN at ply 1', () => {
    const fen = fenAtPly(moves, 1);
    // After 1. e4, white pawn on e4
    expect(fen).toContain('4P3/8/PPPP1PPP');
  });

  it('returns the last FEN at ply beyond length', () => {
    const fen = fenAtPly(moves, 10);
    expect(fen).toBe(moves[moves.length - 1].fen);
  });
});

describe('editorMovesToMoveEntries', () => {
  it('converts EditorMove[] to MoveEntry[]', () => {
    const moves = buildMoveTreeFromSan(['e4', 'e5']);
    const entries = editorMovesToMoveEntries(moves);
    expect(entries).toHaveLength(2);
    expect(entries[0]).toEqual({ san: 'e4', uci: 'e2e4' });
    expect(entries[1]).toEqual({ san: 'e5', uci: 'e7e5' });
  });
});