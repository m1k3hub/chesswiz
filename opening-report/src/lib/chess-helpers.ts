/**
 * chess-helpers.ts — Typed port of the chess utility functions from
 * public/js/chess-utils.js. Uses the npm chess.js package (v1.0.0-beta)
 * instead of the global CDN script.
 */

import { Chess, type Move, type Color, type PieceSymbol, type Square } from 'chess.js';

// ─── Types ────────────────────────────────────────────────

export interface WDLResult {
  whitePct: string;
  drawPct: string;
  blackPct: string;
  total: number;
}

export interface UciSan {
  uci: string;
  san: string;
}

export interface TacticPosition {
  fen: string;
  solution: string;
  solutionUci: string;
  motif: string;
  turn: Color;
  moveNum: number;
  gamePgn: string;
}

export interface PositionTrait {
  icon: string;
  title: string;
  desc: string;
}

export interface Transposition {
  moves: string;
  description: string;
}

export interface Maneuver {
  key: string;
  piece: PieceSymbol;
  color: Color;
  path: string;
  pathStr: string;
  moveCount: number;
  moves: { from: string; to: string; san: string; moveNum: number }[];
}

interface PawnStructureResult {
  description: string;
  whiteDoubled: string[];
  blackDoubled: string[];
  whiteIsolated: string[];
  blackIsolated: string[];
}

// ─── Constants ────────────────────────────────────────────

const PIECE_UNICODE: Record<string, string> = {
  wK: '♔', wQ: '♕', wR: '♖', wB: '♗', wN: '♘', wP: '♙',
  bK: '♚', bQ: '♛', bR: '♜', bB: '♝', bN: '♞', bP: '♟',
};

const PIECE_VALUES: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 100 };

const FILES = 'abcdefgh';

// ─── Public Functions ─────────────────────────────────────

/**
 * Format win/draw/loss as percentage strings.
 */
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

/**
 * Calculate performance score from the perspective of the side to move.
 */
export function calculateScore(white: number, draws: number, black: number, sideToMove: Color): number {
  const total = white + draws + black;
  if (total === 0) return 0;
  return sideToMove === 'w'
    ? ((white + 0.5 * draws) / total) * 100
    : ((black + 0.5 * draws) / total) * 100;
}

/**
 * Classify a move based on score and sample size.
 */
export function classifyMove(
  white: number,
  draws: number,
  black: number,
  sideToMove: Color,
  totalGames: number,
): 'good' | 'solid' | 'risky' | 'rare' | 'neutral' {
  const score = calculateScore(white, draws, black, sideToMove);
  const sampleSize = white + draws + black;
  const frequency = totalGames > 0 ? sampleSize / totalGames : 0;

  if (score >= 55 && frequency >= 0.05) return 'good';
  if (score >= 50 && frequency >= 0.03) return 'solid';
  if (score < 45 && frequency >= 0.02) return 'risky';
  if (frequency < 0.01) return 'rare';
  return 'neutral';
}

/**
 * Get the Unicode chess piece symbol.
 */
export function getPieceSymbol(piece: PieceSymbol, color: Color): string {
  const key = (color === 'w' ? 'w' : 'b') + piece.toUpperCase();
  return PIECE_UNICODE[key] || '?';
}

/**
 * Get the numeric value of a piece type.
 */
export function pieceValue(type: PieceSymbol): number {
  return PIECE_VALUES[type] || 0;
}

/**
 * Convert an array of SAN moves to {uci, san} objects.
 */
export function sanToUci(sanMoves: string[]): UciSan[] {
  const chess = new Chess();
  const result: UciSan[] = [];
  for (const san of sanMoves) {
    try {
      const move = chess.move(san);
      if (!move) break;
      result.push({
        uci: move.from + move.to + (move.promotion || ''),
        san: move.san,
      });
    } catch {
      break;
    }
  }
  return result;
}

/**
 * Parse PGN header tags into a key/value record.
 */
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

/**
 * Load a PGN and return the verbose move history.
 */
export function pgnToMoveArray(pgn: string): Move[] {
  const chess = new Chess();
  try {
    chess.loadPgn(pgn);
  } catch {
    return [];
  }
  return chess.history({ verbose: true });
}

/**
 * Extract tactical training positions from a game PGN.
 * Looks for positions with captures, checks, or hanging pieces.
 */
export function extractTacticalPositions(pgn: string, maxPositions = 15): TacticPosition[] {
  const chess = new Chess();
  const positions: TacticPosition[] = [];

  try {
    chess.loadPgn(pgn);
  } catch {
    return positions;
  }

  const history = chess.history({ verbose: true });

  for (let i = 0; i < history.length - 1 && positions.length < maxPositions; i++) {
    if (i < 6) continue;

    // Replay to position i
    const tempChess = new Chess();
    for (let j = 0; j <= i; j++) {
      tempChess.move(history[j]);
    }

    const fen = tempChess.fen();
    const turn = tempChess.turn();
    const nextMove = history[i + 1];

    const isTactical =
      nextMove.flags.includes('c') ||
      nextMove.flags.includes('e') ||
      nextMove.san.includes('+') ||
      nextMove.san.includes('#');

    const hasHanging = checkForHangingPieces(tempChess);

    if (isTactical || hasHanging) {
      let motif = 'Find the best move';
      if (nextMove.san.includes('#')) motif = 'Mate';
      else if (nextMove.san.includes('+')) motif = 'Check / Attack';
      else if (nextMove.flags.includes('e')) motif = 'En passant';
      else if (nextMove.flags.includes('c') && nextMove.captured) motif = `Capture (${nextMove.captured.toUpperCase()})`;
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

/**
 * Analyze the positional character of a position (king safety, pawn structure, etc.).
 */
export function characterizePosition(fen: string): PositionTrait[] {
  const chess = new Chess(fen);
  const traits: PositionTrait[] = [];
  const board = chess.board();

  // Collect pawn squares
  const whitePawns: string[] = [];
  const blackPawns: string[] = [];
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const p = board[r][f];
      if (p && p.type === 'p') {
        const sq = FILES[f] + (8 - r);
        if (p.color === 'w') whitePawns.push(sq);
        else blackPawns.push(sq);
      }
    }
  }

  // Center control
  const centerSquares = ['e4', 'd4', 'e5', 'd5'];
  let whiteCenter = 0;
  let blackCenter = 0;
  for (const sq of centerSquares) {
    const p = chess.get(sq as Square);
    if (p) {
      if (p.color === 'w') whiteCenter++;
      else blackCenter++;
    }
  }

  // King safety
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
    desc:
      whiteCastled && blackCastled
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
    desc:
      whiteCenter > blackCenter
        ? `White has better central control (${whiteCenter} vs ${blackCenter} central pawns).`
        : blackCenter > whiteCenter
          ? `Black has better central control (${blackCenter} vs ${whiteCenter} central pawns).`
          : 'Central control is balanced.',
  });

  traits.push({
    icon: '♞',
    title: 'Piece Development',
    desc:
      whiteDev > blackDev
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
    desc:
      whiteSpace > blackSpace
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
      desc:
        openFiles.white > openFiles.black
          ? `White controls more open files (${openFiles.white} vs ${openFiles.black}).`
          : openFiles.black > openFiles.white
            ? `Black controls more open files (${openFiles.black} vs ${openFiles.white}).`
            : 'Open file control is balanced.',
    });
  }

  return traits;
}

/**
 * Find transpositions by checking if the same position can be reached via
 * different move orders (swaps the last two moves).
 */
export function findTranspositions(moves: UciSan[], _fen: string): Transposition[] {
  const transpositions: Transposition[] = [];

  // Replay moves to get the target position
  const tempChess = new Chess();
  for (const m of moves) {
    tempChess.move(m.san);
  }
  const targetFen = tempChess.fen().split(' ').slice(0, 4).join(' ');

  if (moves.length >= 2) {
    const altChess = new Chess();
    for (let i = 0; i < moves.length - 2; i++) {
      altChess.move(moves[i].san);
    }

    const tryChess = new Chess(altChess.fen());
    const moveA = moves[moves.length - 2];
    const moveB = moves[moves.length - 1];

    // Try moveB before moveA
    const legalMoves = tryChess.moves({ verbose: true });
    const altMoveB = legalMoves.find((m) => m.from + m.to === moveB.uci.substring(0, 4));

    if (altMoveB) {
      tryChess.move(altMoveB);
      const altLegalMoves = tryChess.moves({ verbose: true });
      const altMoveA = altLegalMoves.find((m) => m.from + m.to === moveA.uci.substring(0, 4));

      if (altMoveA) {
        tryChess.move(altMoveA);
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
  }

  return transpositions;
}

/**
 * Extract piece maneuvers from a Chess instance's move history.
 */
export function extractManeuvers(chess: Chess, maxMoves = 20): Maneuver[] {
  const maneuvers: Record<string, { piece: PieceSymbol; color: Color; squares: string[]; moves: { from: string; to: string; san: string; moveNum: number }[] }> = {};
  const history = chess.history({ verbose: true });
  const moveCount = Math.min(history.length, maxMoves);

  for (let i = 0; i < moveCount; i++) {
    const m = history[i];
    const key = m.color + m.piece.toUpperCase();

    if (!maneuvers[key]) {
      maneuvers[key] = { piece: m.piece, color: m.color, squares: [m.from], moves: [] };
    }
    maneuvers[key].squares.push(m.to);
    maneuvers[key].moves.push({ from: m.from, to: m.to, san: m.san, moveNum: Math.floor(i / 2) + 1 });
  }

  const result: Maneuver[] = [];
  for (const [key, data] of Object.entries(maneuvers)) {
    if (data.squares.length > 1) {
      result.push({
        key,
        piece: data.piece,
        color: data.color,
        path: data.squares.join('→'),
        pathStr: data.squares.join(' → '),
        moveCount: data.moves.length,
        moves: data.moves,
      });
    }
  }

  return result.sort((a, b) => b.moveCount - a.moveCount);
}

// ─── Internal Helpers ─────────────────────────────────────

function findKing(chess: Chess, color: Color): string | null {
  const board = chess.board();
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const p = board[r][f];
      if (p && p.type === 'k' && p.color === color) {
        return FILES[f] + (8 - r);
      }
    }
  }
  return null;
}

function isSquareAttacked(chess: Chess, square: string, byColor: Color): boolean {
  const tempChess = new Chess(chess.fen());
  if (tempChess.turn() !== byColor) {
    try {
      tempChess.move(null);
    } catch {
      return false;
    }
  }
  if (tempChess.turn() !== byColor) return false;
  const moves = tempChess.moves({ verbose: true });
  return moves.some((m) => m.to === square && m.flags.includes('c'));
}

function isSquareDefended(chess: Chess, square: string, byColor: Color): boolean {
  const tempChess = new Chess(chess.fen());
  const piece = tempChess.get(square as Square);
  if (!piece) return false;
  tempChess.remove(square as Square);
  tempChess.put({ type: 'p', color: byColor === 'w' ? 'b' : 'w' }, square as Square);
  if (tempChess.turn() !== byColor) {
    try {
      tempChess.move(null);
    } catch {
      return false;
    }
  }
  if (tempChess.turn() !== byColor) return false;
  const moves = tempChess.moves({ verbose: true });
  const canRecapture = moves.some((m) => m.to === square && m.color === byColor);
  tempChess.remove(square as Square);
  if (piece) tempChess.put(piece, square as Square);
  return canRecapture;
}

function checkForHangingPieces(chess: Chess): boolean {
  const board = chess.board();
  const turn = chess.turn();
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const piece = board[r][f];
      if (piece && piece.color === turn && piece.type !== 'k') {
        const square = FILES[f] + (8 - r);
        const oppColor: Color = turn === 'w' ? 'b' : 'w';
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

function getMinAttackerValue(chess: Chess, square: string, byColor: Color): number {
  const tempChess = new Chess(chess.fen());
  if (tempChess.turn() !== byColor) {
    try {
      tempChess.move(null);
    } catch {
      return 99;
    }
  }
  if (tempChess.turn() !== byColor) return 99;
  const moves = tempChess.moves({ verbose: true }).filter((m) => m.to === square);
  if (moves.length === 0) return 99;
  return Math.min(...moves.map((m) => pieceValue(m.piece)));
}

function countDevelopedPieces(chess: Chess, color: Color): number {
  let count = 0;
  const knightSquares = color === 'w' ? ['b1', 'g1'] : ['b8', 'g8'];
  const bishopSquares = color === 'w' ? ['c1', 'f1'] : ['c8', 'f8'];

  for (const sq of knightSquares) {
    const p = chess.get(sq as Square);
    if (!p || p.type !== 'n' || p.color !== color) count++;
  }
  for (const sq of bishopSquares) {
    const p = chess.get(sq as Square);
    if (!p || p.type !== 'b' || p.color !== color) count++;
  }
  return count;
}

function countPiece(chess: Chess, type: PieceSymbol, color: Color): number {
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

function countAdvancedPawns(pawns: string[], color: Color): number {
  let count = 0;
  for (const sq of pawns) {
    const rank = parseInt(sq[1]);
    if (color === 'w' && rank >= 4) count++;
    if (color === 'b' && rank <= 5) count++;
  }
  return count;
}

function analyzePawnStructure(whitePawns: string[], blackPawns: string[]): PawnStructureResult {
  const whiteFiles = whitePawns.map((p) => p[0]);
  const blackFiles = blackPawns.map((p) => p[0]);

  const whiteDoubled = whiteFiles.filter((f, i) => whiteFiles.indexOf(f) !== i);
  const blackDoubled = blackFiles.filter((f, i) => blackFiles.indexOf(f) !== i);

  const whiteIsolated = whiteFiles.filter((f) => {
    const idx = FILES.indexOf(f);
    const left = idx > 0 ? FILES[idx - 1] : null;
    const right = idx < 7 ? FILES[idx + 1] : null;
    return !whiteFiles.includes(left || '') && !whiteFiles.includes(right || '');
  });

  const blackIsolated = blackFiles.filter((f) => {
    const idx = FILES.indexOf(f);
    const left = idx > 0 ? FILES[idx - 1] : null;
    const right = idx < 7 ? FILES[idx + 1] : null;
    return !blackFiles.includes(left || '') && !blackFiles.includes(right || '');
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

  return { description, whiteDoubled, blackDoubled, whiteIsolated, blackIsolated };
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