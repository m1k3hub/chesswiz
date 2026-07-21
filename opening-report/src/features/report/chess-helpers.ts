/**
 * chess-helpers.ts — Pure and chess.js-dependent helpers for the opening report.
 *
 * Ported from public/js/chess-utils.js to TypeScript using the npm chess.js
 * package (v1.4.0). Pure helpers (formatWDL, parsePGNHeaders, fashion index)
 * have no external dependencies; chess-dependent helpers use chess.js for
 * position analysis.
 */

import { Chess } from 'chess.js';
import type { Move } from 'chess.js';
import type {
  MoveEntry,
  CharacterTrait,
  TacticPosition,
  Transposition,
  Maneuver,
  GameWithPgn,
  YearlyData,
} from '@/types';

// ===== Pure helpers (no chess.js needed) =====

const PIECE_UNICODE: Record<string, string> = {
  wK: '♔', wQ: '♕', wR: '♖', wB: '♗', wN: '♘', wP: '♙',
  bK: '♚', bQ: '♛', bR: '♜', bB: '♝', bN: '♞', bP: '♟',
};

export interface WDLResult {
  whitePct: string;
  drawPct: string;
  blackPct: string;
  total: number;
}

export function formatWDL(white: number, draws: number, black: number): WDLResult {
  const total = white + draws + black;
  if (total === 0) return { whitePct: '0', drawPct: '0', blackPct: '0', total: 0 };
  return {
    whitePct: ((white / total) * 100).toFixed(1),
    drawPct: ((draws / total) * 100).toFixed(1),
    blackPct: ((black / total) * 100).toFixed(1),
    total,
  };
}

export function calculateScore(white: number, draws: number, black: number, sideToMove: string): number {
  const total = white + draws + black;
  if (total === 0) return 0;
  return sideToMove === 'w'
    ? ((white + 0.5 * draws) / total) * 100
    : ((black + 0.5 * draws) / total) * 100;
}

export function getPieceSymbol(piece: string, color: string): string {
  const key = (color === 'w' ? 'w' : 'b') + piece.toUpperCase();
  return PIECE_UNICODE[key] || '?';
}

export function parsePGNHeaders(pgn: string): Record<string, string> {
  const headers: Record<string, string> = {};
  const lines = pgn.split('\n');
  for (const line of lines) {
    const match = line.match(/\[(\w+)\s+"(.+)"\]/);
    if (match) {
      headers[match[1]] = match[2];
    }
  }
  return headers;
}

export function calculateFashionIndex(yearlyData: YearlyData[]): number {
  const recentGames = yearlyData.filter((y) => y.year >= new Date().getFullYear() - 5);
  const recentCount = recentGames.reduce((sum, y) => sum + y.count, 0);
  const totalTopGames = yearlyData.reduce((sum, y) => sum + y.count, 0);
  return totalTopGames > 0 ? Math.round((recentCount / totalTopGames) * 100) : 0;
}

export interface FashionLabel {
  label: string;
  color: string;
}

export function getFashionLabel(fashionIndex: number): FashionLabel {
  if (fashionIndex > 60) return { label: 'Very Fashionable', color: 'badge-green' };
  if (fashionIndex > 40) return { label: 'Fashionable', color: 'badge-blue' };
  if (fashionIndex < 20) return { label: 'Declining', color: 'badge-red' };
  if (fashionIndex < 35) return { label: 'Less Popular', color: 'badge-yellow' };
  return { label: 'Stable', color: 'badge-gray' };
}

export function deduplicateTactics(tactics: TacticPosition[]): TacticPosition[] {
  const seen = new Set<string>();
  return tactics.filter((t) => {
    const key = t.fen.split(' ')[0];
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// ===== Chess-dependent helpers =====

const PIECE_VALUES: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 100 };

function pieceValue(type: string): number {
  return PIECE_VALUES[type] || 0;
}

function findKing(chess: Chess, color: string): string | null {
  const board = chess.board();
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const p = board[r][f];
      if (p && p.type === 'k' && p.color === color) {
        return 'abcdefgh'[f] + (8 - r);
      }
    }
  }
  return null;
}

function isSquareAttacked(chess: Chess, square: string, byColor: string): boolean {
  const tempChess = new Chess(chess.fen());
  if (tempChess.turn() !== byColor) {
    try { tempChess.move(null); } catch { return false; }
  }
  if (tempChess.turn() !== byColor) return false;
  const moves = tempChess.moves({ verbose: true });
  return moves.some((m) => m.to === square && m.isCapture());
}

function isSquareDefended(chess: Chess, square: string, byColor: string): boolean {
  const tempChess = new Chess(chess.fen());
  const piece = tempChess.get(square as Parameters<typeof tempChess.get>[0]);
  if (!piece) return false;
  tempChess.remove(square as Parameters<typeof tempChess.remove>[0]);
  tempChess.put({ type: 'p', color: byColor === 'w' ? 'b' : 'w' }, square as Parameters<typeof tempChess.put>[1]);
  if (tempChess.turn() !== byColor) {
    try { tempChess.move(null); } catch { return false; }
  }
  if (tempChess.turn() !== byColor) return false;
  const moves = tempChess.moves({ verbose: true });
  const canRecapture = moves.some((m) => m.to === square && m.color === byColor);
  tempChess.remove(square as Parameters<typeof tempChess.remove>[0]);
  if (piece) tempChess.put(piece, square as Parameters<typeof tempChess.put>[1]);
  return canRecapture;
}

function getMinAttackerValue(chess: Chess, square: string, byColor: string): number {
  const tempChess = new Chess(chess.fen());
  if (tempChess.turn() !== byColor) {
    try { tempChess.move(null); } catch { return 99; }
  }
  if (tempChess.turn() !== byColor) return 99;
  const moves = tempChess.moves({ verbose: true }).filter((m) => m.to === square);
  if (moves.length === 0) return 99;
  return Math.min(...moves.map((m) => pieceValue(m.piece)));
}

function checkForHangingPieces(chess: Chess): boolean {
  const board = chess.board();
  const turn = chess.turn();
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const piece = board[r][f];
      if (piece && piece.color === turn && piece.type !== 'k') {
        const square = 'abcdefgh'[f] + (8 - r);
        const oppColor = turn === 'w' ? 'b' : 'w';
        if (isSquareAttacked(chess, square, oppColor)) {
          const attackerVal = getMinAttackerValue(chess, square, oppColor);
          const pVal = pieceValue(piece.type);
          if (attackerVal < pVal || !isSquareDefended(chess, square, turn)) {
            return true;
          }
        }
      }
    }
  }
  return false;
}

function countDevelopedPieces(chess: Chess, color: string): number {
  let count = 0;
  const knightSquares = color === 'w' ? ['b1', 'g1'] : ['b8', 'g8'];
  const bishopSquares = color === 'w' ? ['c1', 'f1'] : ['c8', 'f8'];
  for (const sq of knightSquares) {
    const p = chess.get(sq as Parameters<typeof chess.get>[0]);
    if (!p || p.type !== 'n' || p.color !== color) count++;
  }
  for (const sq of bishopSquares) {
    const p = chess.get(sq as Parameters<typeof chess.get>[0]);
    if (!p || p.type !== 'b' || p.color !== color) count++;
  }
  return count;
}

function countPiece(chess: Chess, type: string, color: string): number {
  const board = chess.board();
  let count = 0;
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const p = board[r][f];
      if (p && p.type === type && p.color === color) count++;
    }
  }
  return count;
}

function countAdvancedPawns(pawns: string[], color: string): number {
  let count = 0;
  for (const sq of pawns) {
    const rank = parseInt(sq[1]);
    if (color === 'w' && rank >= 4) count++;
    if (color === 'b' && rank <= 5) count++;
  }
  return count;
}

function analyzePawnStructure(whitePawns: string[], blackPawns: string[]): { description: string } {
  const files = 'abcdefgh';
  const whiteFiles = whitePawns.map((p) => p[0]);
  const blackFiles = blackPawns.map((p) => p[0]);
  const whiteDoubled = whiteFiles.filter((f, i) => whiteFiles.indexOf(f) !== i);
  const blackDoubled = blackFiles.filter((f, i) => blackFiles.indexOf(f) !== i);
  const whiteIsolated = whiteFiles.filter((f) => {
    const idx = files.indexOf(f);
    const left = idx > 0 ? files[idx - 1] : null;
    const right = idx < 7 ? files[idx + 1] : null;
    return !whiteFiles.includes(left as string) && !whiteFiles.includes(right as string);
  });
  const blackIsolated = blackFiles.filter((f) => {
    const idx = files.indexOf(f);
    const left = idx > 0 ? files[idx - 1] : null;
    const right = idx < 7 ? files[idx + 1] : null;
    return !blackFiles.includes(left as string) && !blackFiles.includes(right as string);
  });
  let description = '';
  if (whiteDoubled.length > 0 || blackDoubled.length > 0) {
    description += `Doubled pawns: White ${whiteDoubled.length}, Black ${blackDoubled.length}. `;
  }
  if (whiteIsolated.length > 0 || blackIsolated.length > 0) {
    description += `Isolated pawns: White ${whiteIsolated.length}, Black ${blackIsolated.length}. `;
  }
  if (!description) {
    description = 'No significant pawn weaknesses. Structure is solid for both sides.';
  }
  return { description };
}

function analyzeOpenFiles(chess: Chess): { white: number; black: number } {
  const board = chess.board();
  let whiteOpen = 0;
  let blackOpen = 0;
  for (let f = 0; f < 8; f++) {
    let hasPawn = false;
    let whiteRook = false;
    let blackRook = false;
    for (let r = 0; r < 8; r++) {
      const p = board[r][f];
      if (p && p.type === 'p') hasPawn = true;
      if (p && p.type === 'r') {
        if (p.color === 'w') whiteRook = true;
        else blackRook = true;
      }
    }
    if (!hasPawn) {
      if (whiteRook) whiteOpen++;
      if (blackRook) blackOpen++;
    }
  }
  return { white: whiteOpen, black: blackOpen };
}

export function characterizePosition(fen: string): CharacterTrait[] {
  const chess = new Chess(fen);
  const traits: CharacterTrait[] = [];
  const board = chess.board();

  const whitePawns: string[] = [];
  const blackPawns: string[] = [];
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const p = board[r][f];
      if (p && p.type === 'p') {
        const sq = 'abcdefgh'[f] + (8 - r);
        if (p.color === 'w') whitePawns.push(sq);
        else blackPawns.push(sq);
      }
    }
  }

  const centerSquares = ['e4', 'd4', 'e5', 'd5'];
  let whiteCenter = 0;
  let blackCenter = 0;
  for (const sq of centerSquares) {
    const p = chess.get(sq as Parameters<typeof chess.get>[0]);
    if (p) {
      if (p.color === 'w') whiteCenter++;
      else blackCenter++;
    }
  }

  const whiteKing = findKing(chess, 'w');
  const blackKing = findKing(chess, 'b');
  const whiteCastled = whiteKing && (whiteKing[0] === 'g' || whiteKing[0] === 'c');
  const blackCastled = blackKing && (blackKing[0] === 'g' || blackKing[0] === 'c');

  const pawnStructure = analyzePawnStructure(whitePawns, blackPawns);
  const whiteDev = countDevelopedPieces(chess, 'w');
  const blackDev = countDevelopedPieces(chess, 'b');

  traits.push({
    icon: '🏰',
    title: 'King Safety',
    desc: whiteCastled && blackCastled
      ? 'Both kings have castled to safety. Typical maneuvering phase ahead.'
      : whiteCastled && !blackCastled
      ? 'White has castled; Black should prioritize king safety.'
      : !whiteCastled && blackCastled
      ? 'Black has castled; White should prioritize king safety.'
      : 'Neither king has castled yet. King safety is a priority for both sides.',
  });

  traits.push({ icon: '♟', title: 'Pawn Structure', desc: pawnStructure.description });

  traits.push({
    icon: '🎯',
    title: 'Center Control',
    desc: whiteCenter > blackCenter
      ? `White has better central control (${whiteCenter} vs ${blackCenter} central pawns).`
      : blackCenter > whiteCenter
      ? `Black has better central control (${blackCenter} vs ${whiteCenter} central pawns).`
      : 'Central control is balanced.',
  });

  traits.push({
    icon: '♞',
    title: 'Piece Development',
    desc: whiteDev > blackDev
      ? `White is better developed (${whiteDev} vs ${blackDev} pieces developed).`
      : blackDev > whiteDev
      ? `Black is better developed (${blackDev} vs ${whiteDev} pieces developed).`
      : 'Both sides are equally developed.',
  });

  const whiteSpace = countAdvancedPawns(whitePawns, 'w');
  const blackSpace = countAdvancedPawns(blackPawns, 'b');
  traits.push({
    icon: '📐',
    title: 'Space',
    desc: whiteSpace > blackSpace
      ? 'White has a spatial advantage with more advanced pawns.'
      : blackSpace > whiteSpace
      ? 'Black has a spatial advantage with more advanced pawns.'
      : 'Space is roughly equal.',
  });

  const whiteBishops = countPiece(chess, 'b', 'w');
  const blackBishops = countPiece(chess, 'b', 'b');
  if (whiteBishops === 2 && blackBishops < 2) {
    traits.push({ icon: '♗', title: 'Bishop Pair', desc: 'White has the bishop pair — a slight long-term advantage.' });
  } else if (blackBishops === 2 && whiteBishops < 2) {
    traits.push({ icon: '♝', title: 'Bishop Pair', desc: 'Black has the bishop pair — a slight long-term advantage.' });
  }

  const openFiles = analyzeOpenFiles(chess);
  if (openFiles.white > 0 || openFiles.black > 0) {
    traits.push({
      icon: '♖',
      title: 'Open Files',
      desc: openFiles.white > openFiles.black
        ? `White controls more open files (${openFiles.white} vs ${openFiles.black}).`
        : openFiles.black > openFiles.white
        ? `Black controls more open files (${openFiles.black} vs ${openFiles.white}).`
        : 'Open file control is balanced.',
    });
  }

  return traits;
}

export function findTranspositions(moves: MoveEntry[], _fen: string): Transposition[] {
  const transpositions: Transposition[] = [];
  if (moves.length < 2) return transpositions;

  const tempChess = new Chess();
  for (const m of moves) {
    try { tempChess.move(m.san); } catch { return transpositions; }
  }
  const targetFen = tempChess.fen().split(' ').slice(0, 4).join(' ');

  const altChess = new Chess();
  for (let i = 0; i < moves.length - 2; i++) {
    try { altChess.move(moves[i].san); } catch { return transpositions; }
  }

  const tryChess = new Chess(altChess.fen());
  const moveA = moves[moves.length - 2];
  const moveB = moves[moves.length - 1];

  const legalMoves = tryChess.moves({ verbose: true });
  const altMoveB = legalMoves.find((m) => m.from + m.to === moveB.uci.substring(0, 4));
  if (altMoveB) {
    try { tryChess.move(altMoveB.san); } catch { return transpositions; }
    const altLegalMoves = tryChess.moves({ verbose: true });
    const altMoveA = altLegalMoves.find((m) => m.from + m.to === moveA.uci.substring(0, 4));
    if (altMoveA) {
      try { tryChess.move(altMoveA.san); } catch { return transpositions; }
      const altFen = tryChess.fen().split(' ').slice(0, 4).join(' ');
      if (altFen === targetFen) {
        const altMoves = moves.slice(0, -2).map((m) => m.san);
        altMoves.push(altMoveB.san, altMoveA.san);
        transpositions.push({
          moves: altMoves.join(' '),
          description: 'Same position reached via different move order',
        });
      }
    }
  }

  return transpositions;
}

export function extractTacticalPositions(pgn: string, maxPositions = 15): TacticPosition[] {
  const chess = new Chess();
  const positions: TacticPosition[] = [];

  try {
    chess.loadPgn(pgn);
  } catch {
    return positions;
  }

  const history = chess.history({ verbose: true }) as Move[];

  for (let i = 0; i < history.length - 1 && positions.length < maxPositions; i++) {
    if (i < 6) continue;

    const tempChess = new Chess();
    for (let j = 0; j <= i; j++) {
      try { tempChess.move(history[j].san); } catch { break; }
    }

    const fen = tempChess.fen();
    const turn = tempChess.turn();
    const nextMove = history[i + 1];

    const isTactical = nextMove.isCapture() || nextMove.isEnPassant() ||
      nextMove.san.includes('+') || nextMove.san.includes('#');
    const hasHanging = checkForHangingPieces(tempChess);

    if (isTactical || hasHanging) {
      let motif = 'Find the best move';
      if (nextMove.san.includes('#')) motif = 'Mate';
      else if (nextMove.san.includes('+')) motif = 'Check / Attack';
      else if (nextMove.isEnPassant()) motif = 'En passant';
      else if (nextMove.isCapture() && nextMove.captured) motif = `Capture (${nextMove.captured.toUpperCase()})`;
      else if (hasHanging) motif = 'Win material';

      positions.push({
        fen,
        solution: nextMove.san,
        solutionUci: nextMove.from + nextMove.to + (nextMove.promotion || ''),
        motif,
        turn,
        moveNum: Math.floor((i + 1) / 2) + 1,
        gamePgn: pgn,
      });
    }
  }

  return positions;
}

export function extractManeuversFromGames(games: GameWithPgn[]): Maneuver[] {
  const allManeuvers: Record<string, { piece: string; color: string; paths: Record<string, { destinations: Record<string, number>; count: number }> }> = {};

  for (const game of games) {
    if (!game.pgn) continue;
    const chess = new Chess();
    try { chess.loadPgn(game.pgn); } catch { continue; }

    const history = chess.history({ verbose: true }) as Move[];
    const moveCount = Math.min(history.length, 25);

    for (let i = 0; i < moveCount; i++) {
      const m = history[i];
      const key = m.color + m.piece.toUpperCase();
      if (!allManeuvers[key]) {
        allManeuvers[key] = { piece: m.piece, color: m.color, paths: {} };
      }
    }

    const tempChess = new Chess();
    for (let i = 0; i < moveCount; i++) {
      const m = history[i];
      try { tempChess.move(m.san); } catch { break; }
      const pieceKey = m.color + m.piece.toUpperCase();

      if (!allManeuvers[pieceKey].paths[m.from]) {
        allManeuvers[pieceKey].paths[m.from] = { destinations: {}, count: 0 };
      }
      allManeuvers[pieceKey].paths[m.from].count++;
      allManeuvers[pieceKey].paths[m.from].destinations[m.to] =
        (allManeuvers[pieceKey].paths[m.from].destinations[m.to] || 0) + 1;
    }
  }

  const result: Maneuver[] = [];
  for (const [key, data] of Object.entries(allManeuvers)) {
    const totalMoves = Object.values(data.paths).reduce((sum, p) => sum + p.count, 0);
    if (totalMoves < 2) continue;

    let bestPath: { from: string; destinations: Record<string, number> } | null = null;
    let bestCount = 0;
    for (const [from, pathData] of Object.entries(data.paths)) {
      if (pathData.count > bestCount) {
        bestCount = pathData.count;
        bestPath = { from, destinations: pathData.destinations };
      }
    }

    if (bestPath) {
      const sortedDests = Object.entries(bestPath.destinations).sort((a, b) => b[1] - a[1]);
      const topDest = sortedDests[0];
      const pathStr = `${bestPath.from} → ${topDest[0]}`;
      const frequency = topDest[1] / bestCount;

      result.push({
        key,
        piece: data.piece,
        color: data.color,
        pathStr,
        games: bestCount,
        frequency: (frequency * 100).toFixed(0),
        successLabel: frequency > 0.4 ? 'good' : 'neutral',
      });
    }
  }

  return result.sort((a, b) => b.games - a.games).slice(0, 12);
}