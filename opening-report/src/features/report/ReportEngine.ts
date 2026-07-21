/**
 * ReportEngine — Typed TypeScript port of the opening report generator.
 *
 * Orchestrates data fetching via the typed API client (createApiClient) and
 * chess analysis via chess-helpers. Returns a ReportData object that the
 * OpeningReport React component renders.
 */

import { createApiClient } from '@/api/client';
import type { ScidbApiClient } from '@/api/client';
import type {
  MoveEntry,
  OpeningInfo,
  ExplorerData,
  EloSegment,
  HistoricalData,
  GameWithPgn,
  TopGame,
  CharacterTrait,
  TacticPosition,
  Transposition,
  Maneuver,
  ReportOptions,
  ReportData,
  ExplorerOpts,
} from '@/types';
import {
  characterizePosition,
  findTranspositions,
  extractTacticalPositions,
  extractManeuversFromGames,
  deduplicateTactics,
} from './chess-helpers';

export interface ReportProgress {
  step: string;
  message: string;
}

export type ProgressCallback = (progress: ReportProgress) => void;

export class ReportEngine {
  private readonly api: ScidbApiClient;

  constructor(api?: ScidbApiClient) {
    this.api = api ?? createApiClient();
  }

  async generate(
    moves: MoveEntry[],
    fen: string,
    options: ReportOptions,
    onProgress?: ProgressCallback
  ): Promise<ReportData> {
    const { source, speed, ratingRange } = options;
    const explorerOpts = this.buildExplorerOpts(source, speed, ratingRange);

    // Step 1: Opening identification
    onProgress?.({ step: 'opening', message: 'Identifying opening…' });
    const openingInfo: OpeningInfo = await this.api.getOpeningInfo(moves);

    // Step 2: Main explorer data
    onProgress?.({ step: 'stats', message: 'Gathering statistics…' });
    const mainData: ExplorerData = await this.api.getExplorerData(moves, explorerOpts);

    // Step 3: Elo-segmented data
    onProgress?.({ step: 'elo', message: 'Computing Elo-segmented statistics…' });
    const eloData: EloSegment[] = await this.api.getEloSegmentedData(moves, { source, speed });

    // Step 4: Historical data
    onProgress?.({ step: 'history', message: 'Analyzing historical development…' });
    const historicalData: HistoricalData = await this.api.getHistoricalData(moves, explorerOpts);

    // Step 5: Top games
    const topGames: TopGame[] = historicalData.topGames || [];

    // Step 6: Fetch game PGNs
    onProgress?.({ step: 'pgn', message: 'Fetching game data for analysis…' });
    const gamePgnPromises = topGames.slice(0, 10).map(async (g, i) => {
      try {
        const pgn = await this.api.getGamePGN(g.id);
        return { ...g, pgn, index: i } as GameWithPgn;
      } catch {
        return { ...g, pgn: null, index: i } as GameWithPgn;
      }
    });
    const gamesWithPgn: GameWithPgn[] = await Promise.all(gamePgnPromises);

    // Step 7: Extract tactical positions
    onProgress?.({ step: 'tactics', message: 'Extracting tactical training positions…' });
    let collectedTactics: TacticPosition[] = [];
    for (const game of gamesWithPgn) {
      if (game.pgn) {
        const tactics = extractTacticalPositions(game.pgn, 5);
        collectedTactics.push(...tactics);
      }
    }
    collectedTactics = deduplicateTactics(collectedTactics).slice(0, 20);

    // Step 8: Characterize position
    onProgress?.({ step: 'character', message: 'Characterizing variation…' });
    const characterization: CharacterTrait[] = characterizePosition(fen);

    // Step 9: Find transpositions
    onProgress?.({ step: 'transp', message: 'Finding transpositions…' });
    const transpositions: Transposition[] = findTranspositions(moves, fen);

    // Step 10: Extract piece maneuvers
    onProgress?.({ step: 'maneuvers', message: 'Analyzing piece maneuvers…' });
    const maneuvers: Maneuver[] = extractManeuversFromGames(gamesWithPgn);

    return {
      moves,
      fen,
      openingInfo,
      mainData,
      eloData,
      historicalData,
      topGames,
      gamesWithPgn,
      characterization,
      transpositions,
      maneuvers,
      tactics: collectedTactics,
      options: { source, speed, ratingRange },
    };
  }

  private buildExplorerOpts(source: string, speed: string, ratingRange: string): ExplorerOpts {
    const opts: ExplorerOpts = { source };
    if (source === 'lichess') {
      opts.speed = speed;
      if (ratingRange && ratingRange !== 'all' && ratingRange !== 'elo') {
        const rangeMap: Record<string, number[]> = {
          low: [400, 600, 800, 1000, 1200, 1400],
          club: [1600, 1800, 2000],
          high: [2200],
          top: [2500],
        };
        opts.ratings = rangeMap[ratingRange] || [];
      }
    }
    return opts;
  }
}