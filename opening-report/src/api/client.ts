import type {
  Database,
  GameSummary,
  SearchPayload,
  SearchJob,
  AnalysisJob,
  OpeningMove,
  WorkspaceState,
  SearchType,
  MoveEntry,
  OpeningInfo,
  ExplorerOpts,
  ExplorerData,
  EloSegment,
  EloRange,
  HistoricalData,
  GameDetail,
  GameUpdatePayload,
  VariationPayload,
  MoveCommentPayload,
  GameHeaders,
  EditorMove,
  JobProgress,
  ImportPayload,
  ExportPayload,
  PaginatedGames,
  PaginatedGamesRequest,
  OpeningTreeRequest,
  EcoEntry,
  NamebaseEntry,
  IndexType,
  Repertoire,
  OpeningPrepRequest,
  PlayerPrepRequest,
  PlayerSummary,
  PlayerCard,
  PrepReport,
  MaintenanceJobRequest,
  MaintenanceReport,
  CrosstableQuery,
  CrosstableResult,
  EngineInfo,
} from '@/types';
import { authHeaders } from './auth';
import { Chess } from 'chess.js';

export interface ScidbApiClient {
  listDatabases(): Promise<Database[]>;
  getWorkspace(): Promise<Partial<WorkspaceState>>;
  createDatabase(payload: Omit<Database, 'id'>): Promise<Database>;
  getOpeningTree(payload: OpeningTreeRequest): Promise<OpeningMove[]>;
  listGames(payload?: { databaseId?: string }): Promise<GameSummary[]>;
  listGamesPaginated(payload: PaginatedGamesRequest): Promise<PaginatedGames>;
  search(payload: SearchPayload): Promise<Pick<SearchJob, 'jobId' | 'status' | 'total'>>;
  cancelSearch(jobId: string): Promise<void>;
  getSearchResults(jobId: string): Promise<SearchJob>;
  getEngines(): Promise<EngineInfo[]>;
  startAnalysis(payload: { fen?: string; multiPv?: number; depth?: number; engineId?: string }): Promise<Pick<AnalysisJob, 'jobId' | 'status'>>;
  getAnalysis(jobId: string): Promise<AnalysisJob>;
  stopAnalysis(jobId: string): Promise<Pick<AnalysisJob, 'jobId' | 'status'>>;
  getOpeningInfo(moves: MoveEntry[]): Promise<OpeningInfo>;
  getExplorerData(moves: MoveEntry[], opts?: ExplorerOpts): Promise<ExplorerData>;
  getEloSegmentedData(moves: MoveEntry[], opts?: ExplorerOpts): Promise<EloSegment[]>;
  getHistoricalData(moves: MoveEntry[], opts?: ExplorerOpts): Promise<HistoricalData>;
  getGamePGN(gameId: string): Promise<string>;
  getGame(gameId: string): Promise<GameDetail>;
  updateGame(gameId: string, payload: GameUpdatePayload): Promise<GameDetail>;
  addVariation(gameId: string, payload: VariationPayload): Promise<GameDetail>;
  setMoveComment(gameId: string, moveId: string, payload: MoveCommentPayload): Promise<GameDetail>;
  importDatabase(payload: ImportPayload): Promise<JobProgress>;
  exportDatabase(payload: ExportPayload): Promise<JobProgress>;
  getJob(jobId: string): Promise<JobProgress>;
  deleteJob(jobId: string): Promise<void>;
  cancelJob(jobId: string): Promise<JobProgress>;
  getIndexes(type: IndexType): Promise<NamebaseEntry[] | EcoEntry[]>;
  getEcoTable(): Promise<EcoEntry[]>;
  // Preparation (milestone 4)
  listRepertoires(): Promise<Repertoire[]>;
  createOpeningPrepReport(payload: OpeningPrepRequest): Promise<PrepReport>;
  listPlayers(query?: string): Promise<PlayerSummary[]>;
  getPlayerCard(playerId: string): Promise<PlayerCard>;
  createPlayerPrepReport(payload: PlayerPrepRequest): Promise<PrepReport>;
  // Maintenance & crosstables (milestone 5)
  startMaintenance(payload: MaintenanceJobRequest): Promise<JobProgress>;
  getMaintenanceReport(jobId: string): Promise<MaintenanceReport>;
  queryCrosstable(payload: CrosstableQuery): Promise<CrosstableResult>;
}

const defaultHeaders = { Accept: 'application/json' };

async function httpRequest<T>(baseUrl: string, path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${baseUrl}${path}`, {
    headers: {
      ...defaultHeaders,
      ...(await authHeaders()),
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...options,
  });
  if (!response.ok) throw new Error(`scidb API ${response.status}`);
  return response.status === 204 ? (null as T) : (response.json() as Promise<T>);
}

export class HttpScidbApiClient implements ScidbApiClient {
  constructor(private readonly baseUrl: string = '/api') {}

  listDatabases(): Promise<Database[]> {
    return httpRequest<Database[]>(this.baseUrl, '/databases');
  }

  getWorkspace(): Promise<Partial<WorkspaceState>> {
    return httpRequest<Partial<WorkspaceState>>(this.baseUrl, '/workspace');
  }

  createDatabase(payload: Omit<Database, 'id'>): Promise<Database> {
    return httpRequest<Database>(this.baseUrl, '/databases', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  getOpeningTree(payload: OpeningTreeRequest): Promise<OpeningMove[]> {
    return httpRequest<OpeningMove[]>(this.baseUrl, '/tree/query', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  listGames(payload?: { databaseId?: string }): Promise<GameSummary[]> {
    return httpRequest<GameSummary[]>(
      this.baseUrl,
      `/databases/${payload?.databaseId || 'masters'}/games`
    );
  }

  listGamesPaginated(payload: PaginatedGamesRequest): Promise<PaginatedGames> {
    const params = new URLSearchParams();
    if (payload.page) params.set('page', String(payload.page));
    if (payload.limit) params.set('limit', String(payload.limit));
    if (payload.sort) params.set('sort', payload.sort);
    if (payload.order) params.set('order', payload.order);
    if (payload.query) params.set('query', payload.query);
    const qs = params.toString();
    return httpRequest<PaginatedGames>(
      this.baseUrl,
      `/databases/${payload.databaseId || 'masters'}/games${qs ? `?${qs}` : ''}`
    );
  }

  search(payload: SearchPayload): Promise<Pick<SearchJob, 'jobId' | 'status' | 'total'>> {
    return httpRequest<Pick<SearchJob, 'jobId' | 'status' | 'total'>>(this.baseUrl, '/searches', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  getSearchResults(jobId: string): Promise<SearchJob> {
    return httpRequest<SearchJob>(this.baseUrl, `/searches/${jobId}/results`);
  }

  cancelSearch(jobId: string): Promise<void> {
    return httpRequest<void>(this.baseUrl, `/searches/${jobId}`, { method: 'DELETE' });
  }

  getEngines(): Promise<EngineInfo[]> {
    return httpRequest<EngineInfo[]>(this.baseUrl, '/engines');
  }

  startAnalysis(payload: { fen?: string; multiPv?: number; depth?: number; engineId?: string }): Promise<Pick<AnalysisJob, 'jobId' | 'status'>> {
    return httpRequest<Pick<AnalysisJob, 'jobId' | 'status'>>(this.baseUrl, '/analysis/start', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  getAnalysis(jobId: string): Promise<AnalysisJob> {
    return httpRequest<AnalysisJob>(this.baseUrl, `/analysis/${jobId}`);
  }

  stopAnalysis(jobId: string): Promise<Pick<AnalysisJob, 'jobId' | 'status'>> {
    return httpRequest<Pick<AnalysisJob, 'jobId' | 'status'>>(this.baseUrl, `/analysis/${jobId}/stop`, {
      method: 'POST',
    });
  }

  getOpeningInfo(moves: MoveEntry[]): Promise<OpeningInfo> {
    return httpRequest<OpeningInfo>(this.baseUrl, '/opening-info', {
      method: 'POST',
      body: JSON.stringify({ moves }),
    });
  }

  getExplorerData(moves: MoveEntry[], opts?: ExplorerOpts): Promise<ExplorerData> {
    return httpRequest<ExplorerData>(this.baseUrl, '/explorer', {
      method: 'POST',
      body: JSON.stringify({ moves, ...opts }),
    });
  }

  getEloSegmentedData(moves: MoveEntry[], opts?: ExplorerOpts): Promise<EloSegment[]> {
    return httpRequest<EloSegment[]>(this.baseUrl, '/explorer/elo', {
      method: 'POST',
      body: JSON.stringify({ moves, ...opts }),
    });
  }

  getHistoricalData(moves: MoveEntry[], opts?: ExplorerOpts): Promise<HistoricalData> {
    return httpRequest<HistoricalData>(this.baseUrl, '/explorer/historical', {
      method: 'POST',
      body: JSON.stringify({ moves, ...opts }),
    });
  }

  async getGamePGN(gameId: string): Promise<string> {
    const response = await fetch(`${this.baseUrl}/games/${gameId}/pgn`, {
      headers: { ...defaultHeaders, Accept: 'application/x-chess-pgn', ...(await authHeaders()) },
    });
    if (!response.ok) throw new Error(`scidb API ${response.status}`);
    return response.text();
  }

  getGame(gameId: string): Promise<GameDetail> {
    return httpRequest<GameDetail>(this.baseUrl, `/games/${gameId}`);
  }

  updateGame(gameId: string, payload: GameUpdatePayload): Promise<GameDetail> {
    return httpRequest<GameDetail>(this.baseUrl, `/games/${gameId}`, {
      method: 'PATCH',
      body: JSON.stringify(payload),
    });
  }

  addVariation(gameId: string, payload: VariationPayload): Promise<GameDetail> {
    return httpRequest<GameDetail>(this.baseUrl, `/games/${gameId}/variations`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  setMoveComment(gameId: string, moveId: string, payload: MoveCommentPayload): Promise<GameDetail> {
    return httpRequest<GameDetail>(this.baseUrl, `/games/${gameId}/moves/${moveId}/comments`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  importDatabase(payload: ImportPayload): Promise<JobProgress> {
    return httpRequest<JobProgress>(this.baseUrl, `/databases/${payload.databaseId}/import`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  exportDatabase(payload: ExportPayload): Promise<JobProgress> {
    return httpRequest<JobProgress>(this.baseUrl, `/databases/${payload.databaseId}/export`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  getJob(jobId: string): Promise<JobProgress> {
    return httpRequest<JobProgress>(this.baseUrl, `/jobs/${jobId}`);
  }

  deleteJob(jobId: string): Promise<void> {
    return httpRequest<void>(this.baseUrl, `/jobs/${jobId}`, { method: 'DELETE' });
  }

  cancelJob(jobId: string): Promise<JobProgress> {
    return httpRequest<JobProgress>(this.baseUrl, `/jobs/${jobId}/cancel`, { method: 'POST' });
  }

  getIndexes(type: IndexType): Promise<NamebaseEntry[] | EcoEntry[]> {
    return httpRequest<NamebaseEntry[] | EcoEntry[]>(this.baseUrl, `/indexes/${type}`);
  }

  getEcoTable(): Promise<EcoEntry[]> {
    return httpRequest<EcoEntry[]>(this.baseUrl, '/eco');
  }

  // Preparation (milestone 4)
  listRepertoires(): Promise<Repertoire[]> {
    return httpRequest<Repertoire[]>(this.baseUrl, '/repertoires');
  }

  createOpeningPrepReport(payload: OpeningPrepRequest): Promise<PrepReport> {
    return httpRequest<PrepReport>(this.baseUrl, '/prep/reports', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  listPlayers(query?: string): Promise<PlayerSummary[]> {
    const qs = query ? `?q=${encodeURIComponent(query)}` : '';
    return httpRequest<PlayerSummary[]>(this.baseUrl, `/players${qs}`);
  }

  getPlayerCard(playerId: string): Promise<PlayerCard> {
    return httpRequest<PlayerCard>(this.baseUrl, `/players/${playerId}/card`);
  }

  createPlayerPrepReport(payload: PlayerPrepRequest): Promise<PrepReport> {
    return httpRequest<PrepReport>(this.baseUrl, `/players/${payload.playerId}/prep`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  // Maintenance & crosstables (milestone 5)
  startMaintenance(payload: MaintenanceJobRequest): Promise<JobProgress> {
    return httpRequest<JobProgress>(this.baseUrl, '/maintenance/jobs', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }

  getMaintenanceReport(jobId: string): Promise<MaintenanceReport> {
    return httpRequest<MaintenanceReport>(this.baseUrl, `/maintenance/reports/${jobId}`);
  }

  queryCrosstable(payload: CrosstableQuery): Promise<CrosstableResult> {
    return httpRequest<CrosstableResult>(this.baseUrl, '/crosstables/query', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }
}

const MOCK_DATABASES: Database[] = [
  { id: 'masters', name: 'Master Games', format: 'SCI', games: 2_400_000, readOnly: true },
  { id: 'repertoire', name: 'My Repertoire', format: 'PGN', games: 1842, readOnly: false },
];

const MOCK_GAMES: GameSummary[] = [
  { id: 'g-001', white: 'Carlsen, Magnus', whiteElo: 2855, black: 'Nepomniachtchi, Ian', blackElo: 2782, event: 'WCh 2021', site: 'Dubai UAE', date: '2021.12.03', result: '½–½', eco: 'A45' },
  { id: 'g-002', white: 'Kasparov, Garry', whiteElo: 2810, black: 'Karpov, Anatoly', blackElo: 2725, event: 'Linares', site: 'Linares ESP', date: '1993.03.02', result: '1-0', eco: 'D37' },
  { id: 'g-003', white: 'Polgar, Judit', whiteElo: 2735, black: 'Anand, Viswanathan', blackElo: 2774, event: 'Hoogeveen', site: 'Hoogeveen NED', date: '2003.10.16', result: '0-1', eco: 'B90' },
  { id: 'g-004', white: 'Fischer, Robert James', whiteElo: 2785, black: 'Spassky, Boris', blackElo: 2660, event: 'Reykjavik WCh', site: 'Reykjavik ISL', date: '1972.07.23', result: '1-0', eco: 'E56' },
];

const MATERIAL_PROFILES: Record<string, Record<string, number>> = {
  'g-001': { wq: 1, bq: 1, wr: 2, br: 2, wb: 2, bb: 1, wn: 2, bn: 2, wp: 8, bp: 7 },
  'g-002': { wq: 1, bq: 0, wr: 2, br: 1, wb: 2, bb: 2, wn: 2, bn: 2, wp: 7, bp: 6 },
  'g-003': { wq: 1, bq: 1, wr: 2, br: 2, wb: 1, bb: 2, wn: 2, bn: 1, wp: 8, bp: 8 },
  'g-004': { wq: 0, bq: 0, wr: 2, br: 2, wb: 2, bb: 2, wn: 2, bn: 2, wp: 6, bp: 6 },
};

function matchesAdvanced(game: GameSummary, query: Record<string, unknown>): boolean {
  const q = query as { [key: string]: string | number | undefined };
  if (q.white && !game.white.toLowerCase().includes(String(q.white).toLowerCase())) return false;
  if (q.black && !game.black.toLowerCase().includes(String(q.black).toLowerCase())) return false;
  if (q.event && !game.event.toLowerCase().includes(String(q.event).toLowerCase())) return false;
  if (q.site && !game.site.toLowerCase().includes(String(q.site).toLowerCase())) return false;
  if (q.ecoFrom && game.eco < String(q.ecoFrom)) return false;
  if (q.ecoTo && game.eco > String(q.ecoTo)) return false;
  if (q.result && game.result !== q.result) {
    const normalize = (r: string) => r.replace(/½/g, '1/2').replace(/[–—−]/g, '-').replace(/\s+/g, '');
    if (normalize(game.result) !== normalize(String(q.result))) return false;
  }
  if (q.yearFrom && (!game.date || parseInt(game.date.substring(0, 4)) < Number(q.yearFrom))) return false;
  if (q.yearTo && (!game.date || parseInt(game.date.substring(0, 4)) > Number(q.yearTo))) return false;
  return true;
}

function matchesMaterial(game: GameSummary, query: Record<string, unknown>): boolean {
  const q = query as { [key: string]: number | string | undefined };
  const p = MATERIAL_PROFILES[game.id];
  if (!p) return false;
  const check = (key: string, val?: number | string) => val === null || val === undefined || p[key] === Number(val);
  if (!check('wq', q.whiteQ)) return false;
  if (!check('wr', q.whiteR)) return false;
  if (!check('wb', q.whiteB)) return false;
  if (!check('wn', q.whiteN)) return false;
  if (!check('wp', q.whiteP)) return false;
  if (!check('bq', q.blackQ)) return false;
  if (!check('br', q.blackR)) return false;
  if (!check('bb', q.blackB)) return false;
  if (!check('bn', q.blackN)) return false;
  if (!check('bp', q.blackP)) return false;
  if (q.imbalance) {
    const whiteVal = p.wq * 9 + p.wr * 5 + (p.wb + p.wn) * 3 + p.wp;
    const blackVal = p.bq * 9 + p.br * 5 + (p.bb + p.bn) * 3 + p.bp;
    if (q.imbalance === 'up' && whiteVal <= blackVal) return false;
    if (q.imbalance === 'down' && whiteVal >= blackVal) return false;
    if (q.imbalance === 'equal' && whiteVal !== blackVal) return false;
  }
  return true;
}

function matchesRating(game: GameSummary, query: Record<string, unknown>): boolean {
  const q = query as { [key: string]: number | undefined };
  const avg = Math.round((game.whiteElo + game.blackElo) / 2);
  if (q.whiteEloMin && game.whiteElo < q.whiteEloMin) return false;
  if (q.whiteEloMax && game.whiteElo > q.whiteEloMax) return false;
  if (q.blackEloMin && game.blackElo < q.blackEloMin) return false;
  if (q.blackEloMax && game.blackElo > q.blackEloMax) return false;
  if (q.averageEloMin && avg < q.averageEloMin) return false;
  if (q.averageEloMax && avg > q.averageEloMax) return false;
  return true;
}

function matchesCql(game: GameSummary, query: Record<string, unknown>): boolean {
  const text = String((query as { cql?: string }).cql || '').toLowerCase();
  if (!text) return true;
  const haystack = `${game.white} ${game.black} ${game.event} ${game.site} ${game.eco} ${game.result}`.toLowerCase();
  return text.split(/\s+/).some((term) => haystack.includes(term));
}

export class MockScidbApiClient implements ScidbApiClient {
  private searchId = 0;
  private analysisId = 0;
  private jobId = 0;
  private readonly searchStore = new Map<string, SearchJob>();
  private readonly analysisStore = new Map<string, AnalysisJob>();
  private readonly jobStore = new Map<string, JobProgress>();

  async listDatabases(): Promise<Database[]> {
    return [...MOCK_DATABASES];
  }

  async getWorkspace(): Promise<Partial<WorkspaceState>> {
    return { activeDatabaseId: 'masters', currentFen: 'start' };
  }

  async createDatabase(payload: Omit<Database, 'id'>): Promise<Database> {
    const db: Database = { ...payload, id: `db-${Date.now()}` };
    MOCK_DATABASES.push(db);
    return db;
  }

  async getOpeningTree(_: OpeningTreeRequest): Promise<OpeningMove[]> {
    return [
      { san: 'd4', uci: 'd2d4', games: 126_420, score: 52.8, white: 37, draw: 42, black: 21, eco: 'A45' },
      { san: 'Nf3', uci: 'g1f3', games: 84_210, score: 51.2, white: 35, draw: 44, black: 21, eco: 'A06' },
      { san: 'c4', uci: 'c2c4', games: 61_190, score: 50.4, white: 34, draw: 43, black: 23, eco: 'A10' },
      { san: 'e4', uci: 'e2e4', games: 23_880, score: 49.7, white: 33, draw: 40, black: 27, eco: 'B00' },
    ];
  }

  async listGames(_?: { databaseId?: string }): Promise<GameSummary[]> {
    return [...MOCK_GAMES];
  }

  async listGamesPaginated(payload: PaginatedGamesRequest): Promise<PaginatedGames> {
    let games = [...MOCK_GAMES];
    const q = payload.query?.toLowerCase();
    if (q) {
      games = games.filter((g) =>
        `${g.white} ${g.black} ${g.event} ${g.site} ${g.eco}`.toLowerCase().includes(q)
      );
    }
    if (payload.sort) {
      const field = payload.sort;
      const order = payload.order === 'desc' ? -1 : 1;
      games.sort((a, b) => {
        const av = String(a[field] ?? '');
        const bv = String(b[field] ?? '');
        return av < bv ? -order : av > bv ? order : 0;
      });
    }
    const total = games.length;
    const limit = payload.limit || 20;
    const page = payload.page || 1;
    const totalPages = Math.max(1, Math.ceil(total / limit));
    const start = (page - 1) * limit;
    const pageGames = games.slice(start, start + limit);
    return { games: pageGames, page, limit, total, totalPages };
  }

  async search(payload: SearchPayload): Promise<Pick<SearchJob, 'jobId' | 'status' | 'total'>> {
    this.searchId += 1;
    const jobId = `mock-search-${this.searchId}`;
    const matcher: Record<SearchType, (game: GameSummary) => boolean> = {
      advanced: (game) => matchesAdvanced(game, payload.query as Record<string, unknown>),
      material: (game) => matchesMaterial(game, payload.query as Record<string, unknown>),
      rating: (game) => matchesRating(game, payload.query as Record<string, unknown>),
      cql: (game) => matchesCql(game, payload.query as Record<string, unknown>),
    };
    const filtered = MOCK_GAMES.filter(matcher[payload.type] || matcher.advanced);
    const job: SearchJob = {
      jobId,
      status: 'complete',
      total: filtered.length,
      games: filtered,
      query: payload,
    };
    this.searchStore.set(jobId, job);
    return { jobId, status: 'complete', total: filtered.length };
  }

  async getSearchResults(jobId: string): Promise<SearchJob> {
    return this.searchStore.get(jobId) || { jobId, status: 'pending', total: 0, games: [] };
  }

  async cancelSearch(jobId: string): Promise<void> {
    const job = this.searchStore.get(jobId);
    if (job) {
      job.status = 'cancelled';
      job.games = [];
    }
  }

  async getEngines(): Promise<EngineInfo[]> {
    return [
      { engineId: 'stockfish', name: 'Stockfish 16', path: '' },
      { engineId: 'stockfish-15', name: 'Stockfish 15', path: '' },
      { engineId: 'mock', name: 'Mock engine (simulated)', path: '' },
    ];
  }

  async startAnalysis(payload: { fen?: string; multiPv?: number; depth?: number; engineId?: string }): Promise<Pick<AnalysisJob, 'jobId' | 'status'>> {
    this.analysisId += 1;
    const jobId = `mock-analysis-${this.analysisId}`;
    const job: AnalysisJob = {
      jobId,
      status: 'running',
      fen: payload.fen || 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      depth: 0,
      multiPv: payload.multiPv || 3,
      lines: [
        { pv: 'e2e4 e7e5', eval: '+0.35', depth: 18 },
        { pv: 'd2d4 d7d5', eval: '+0.28', depth: 18 },
        { pv: 'c2c4 e7e6', eval: '+0.20', depth: 18 },
      ],
      nodes: 0,
      nps: 0,
      startedAt: Date.now(),
    };
    this.analysisStore.set(jobId, job);
    return { jobId, status: 'running' };
  }

  async getAnalysis(jobId: string): Promise<AnalysisJob> {
    const job = this.analysisStore.get(jobId);
    if (!job) return { jobId, status: 'unknown', fen: '', depth: 0, multiPv: 0, lines: [], nodes: 0, nps: 0 };
    if (job.status === 'running') {
      job.depth = Math.min(job.depth + 1, 28);
      job.nodes = (job.nodes || 0) + Math.floor(Math.random() * 5_000_000);
      job.nps = 1_200_000 + Math.floor(Math.random() * 800_000);
      job.lines = job.lines.map((line, idx) => ({
        ...line,
        depth: job.depth,
        eval: ((Math.random() - 0.5) * (idx + 1) * 0.4).toFixed(2),
        pv: line.pv.split(' ').slice(0, 2 + Math.floor(job.depth / 6)).join(' '),
      }));
      if (job.depth >= 28) job.status = 'complete';
    }
    return { ...job };
  }

  async stopAnalysis(jobId: string): Promise<Pick<AnalysisJob, 'jobId' | 'status'>> {
    const job = this.analysisStore.get(jobId);
    if (job) job.status = 'stopped';
    return { jobId, status: job ? job.status : 'unknown' };
  }

  async getOpeningInfo(moves: MoveEntry[]): Promise<OpeningInfo> {
    if (moves.length === 0) return { eco: 'A00', name: 'Starting position' };
    const ecoCodes: Record<number, OpeningInfo> = {
      0: { eco: 'A00', name: 'Irregular opening' },
      1: { eco: 'A45', name: "Queen's pawn game" },
      2: { eco: 'D02', name: 'Queen\'s pawn game' },
    };
    return ecoCodes[moves.length] || { eco: 'A45', name: 'Queen\'s pawn game' };
  }

  async getExplorerData(moves: MoveEntry[], _opts?: ExplorerOpts): Promise<ExplorerData> {
    const turn = moves.length % 2 === 0 ? 'white' : 'black';
    const totalGames = 2600;
    const white = Math.round(totalGames * 0.42);
    const black = Math.round(totalGames * 0.28);
    const draws = totalGames - white - black;
    return {
      white,
      draws,
      black,
      moves: [
        { uci: 'd2d4', san: 'd4', white: 480, draws: 320, black: 200, averageRating: 2380 },
        { uci: 'g1f3', san: 'Nf3', white: 320, draws: 200, black: 150, averageRating: 2350 },
        { uci: 'c2c4', san: 'c4', white: 250, draws: 170, black: 130, averageRating: 2400 },
        { uci: 'e2e4', san: 'e4', white: 150, draws: 90, black: 100, averageRating: 2320 },
      ],
      turn,
      topGames: [
        { id: 'g-001', month: '202112' },
        { id: 'g-002', month: '199303' },
        { id: 'g-003', month: '200310' },
      ],
      fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    };
  }

  async getEloSegmentedData(moves: MoveEntry[], opts?: ExplorerOpts): Promise<EloSegment[]> {
    const baseData = await this.getExplorerData(moves, opts);
    const ranges: EloRange[] = [
      { label: 'Below 1600', min: 400, max: 1600 },
      { label: '1600–1800', min: 1600, max: 1800 },
      { label: '1800–2000', min: 1800, max: 2000 },
      { label: '2000–2200', min: 2000, max: 2200 },
      { label: '2200–2500', min: 2200, max: 2500 },
      { label: '2500+', min: 2500, max: 9999 },
    ];
    return ranges.map((range) => ({
      range,
      data: { ...baseData, white: Math.round(baseData.white * 0.15), draws: Math.round(baseData.draws * 0.15), black: Math.round(baseData.black * 0.15) },
    }));
  }

  async getHistoricalData(moves: MoveEntry[], opts?: ExplorerOpts): Promise<HistoricalData> {
    const data = await this.getExplorerData(moves, opts);
    const yearlyData = [
      { year: 2016, count: 2 },
      { year: 2017, count: 3 },
      { year: 2018, count: 5 },
      { year: 2019, count: 4 },
      { year: 2020, count: 6 },
      { year: 2021, count: 8 },
      { year: 2022, count: 7 },
      { year: 2023, count: 5 },
      { year: 2024, count: 4 },
    ];
    return {
      yearlyData,
      topGames: data.topGames,
      totalGames: data.white + data.draws + data.black,
    };
  }

  async getGamePGN(gameId: string): Promise<string> {
    const pgns: Record<string, string> = {
      'g-001': '[Event "WCh 2021"]\n[Site "Dubai UAE"]\n[Date "2021.12.03"]\n[White "Carlsen, Magnus"]\n[Black "Nepomniachtchi, Ian"]\n[WhiteElo "2855"]\n[BlackElo "2782"]\n[Result "1/2-1/2"]\n1. d4 Nf6 2. c4 e6 3. Nf3 d5 4. Nc3 Bb4 5. Bg5 h6 6. Bxf6 Qxf6 7. e3 O-O 8. Rc1 c5 9. Be2 cxd4 10. exd4 dxc4 11. Bxc4 Nc6 12. O-O Be7 13. Re1 b6 14. Qd2 Bb7 15. Rad1 Rac8 16. Ba4 Rfd8 17. Qf4 Qxf4 18. Bxf4 Ne7 19. Ce5 Bf6 20. Bxe7 Bxe7 21. Nxe7 Rxd4 22. Rxd4 Bxf3 23. gxf3 Nf5 24. Rd5 g6 25. Rd1 Kg7 26. Bcl Rd8 27. Rxd8 Nxd8 28. b3 f6 29. a4 Kf7 30. f4 Ne6 31. Bb2 Ke7 32. Ke2 Kd6 33. f3 Nd4+ 34. Bxd4 exd4 35. Kd3 f5 36. Kxd4 Kc6 37. b4 Kb5 38. c3 a6 39. a3 Ka4 40. Kb2 b5 41. Ka2 1/2-1/2',
      'g-002': '[Event "Linares"]\n[Site "Linares ESP"]\n[Date "1993.03.02"]\n[White "Kasparov, Garry"]\n[Black "Karpov, Anatoly"]\n[WhiteElo "2810"]\n[BlackElo "2725"]\n[Result "1-0"]\n1. d4 Nf6 2. c4 e6 3. Nf3 d5 4. Nc3 Be7 5. Bg5 O-O 6. e3 h6 7. Bf4 Be7 8. Bd3 c5 9. cxd5 exd5 10. dxc5 Bxc5 11. O-O Nc6 12. Re1 Be7 13. Bg3 Be6 14. Nd2 Nb4 15. Bb1 Rc8 16. Ce4 Na6 17. Nxf6+ Bxf6 18. Bxd5 Bxd5 19. Qxd5 Rc5 20. Qd1 Rc8 21. Qd5 Rc5 22. Qd1 1-0',
      'g-003': '[Event "Hoogeveen"]\n[Site "Hoogeveen NED"]\n[Date "2003.10.16"]\n[White "Polgar, Judit"]\n[Black "Anand, Viswanathan"]\n[WhiteElo "2735"]\n[BlackElo "2774"]\n[Result "0-1"]\n1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be3 e5 7. Nb3 Be7 8. f3 O-O 9. g4 Be6 10. Qd2 Nbd7 11. O-O-O Nb6 12. g5 Nfd7 13. f4 Rc8 14. f5 Bc4 15. Qf2 Nc4 16. Bxc4 Rxc4 17. Qg3 Qc8 18. Nd5 Rc5 19. c3 b5 20. b4 Rc8 21. a4 bxa4 22. Nxa4 Nxa4 23. Rxa4 Qc6 24. Qg2 Rc4 25. Rd2 Qc8 26. Qg3 Rc7 27. Rda2 f6 28. gxf6 gxf6 29. Qg6 Rg7 30. Qh6 Rg8 31. Qg6 Rg7 32. Qh6 Rg8 33. Qg6 0-1',
    };
    return pgns[gameId] || '[Event "?"]\n[White "?"]\n[Black "?"]\n[Result "*"]\n1. d4 Nf6 2. c4 e6 *';
  }

  // ── Game editor mock endpoints ──────────────────────

  private gameStore = new Map<string, GameDetail>();

  private buildGameDetail(gameId: string): GameDetail {
    const cached = this.gameStore.get(gameId);
    if (cached) return cached;
    const pgn = this.getGamePgnSync(gameId);
    const headers = this.parseHeaders(pgn);
    const moves = this.buildMoveTree(pgn);
    const detail: GameDetail = { id: gameId, headers, moves, pgn };
    this.gameStore.set(gameId, detail);
    return detail;
  }

  private getGamePgnSync(gameId: string): string {
    const pgns: Record<string, string> = {
      'g-001': '[Event "WCh 2021"]\n[Site "Dubai UAE"]\n[Date "2021.12.03"]\n[White "Carlsen, Magnus"]\n[Black "Nepomniachtchi, Ian"]\n[WhiteElo "2855"]\n[BlackElo "2782"]\n[Result "1/2-1/2"]\n1. d4 Nf6 2. c4 e6 3. Nf3 d5 4. Nc3 Bb4 5. Bg5 h6 6. Bxf6 Qxf6 7. e3 O-O 8. Rc1 c5 9. Be2 cxd4 10. exd4 dxc4 11. Bxc4 Nc6 12. O-O Be7 13. Re1 b6 14. Qd2 Bb7 15. Rad1 Rac8 16. Ba4 Rfd8 17. Qf4 Qxf4 18. Bxf4 Ne7 19. Ce5 Bf6 20. Bxe7 Bxe7 21. Nxe7 Rxd4 22. Rxd4 Bxf3 23. gxf3 Nf5 24. Rd5 g6 25. Rd1 Kg7 26. Bcl Rd8 27. Rxd8 Nxd8 28. b3 f6 29. a4 Kf7 30. f4 Ne6 31. Bb2 Ke7 32. Ke2 Kd6 33. f3 Nd4+ 34. Bxd4 exd4 35. Kd3 f5 36. Kxd4 Kc6 37. b4 Kb5 38. c3 a6 39. a3 Ka4 40. Kb2 b5 41. Ka2 1/2-1/2',
      'g-002': '[Event "Linares"]\n[Site "Linares ESP"]\n[Date "1993.03.02"]\n[White "Kasparov, Garry"]\n[Black "Karpov, Anatoly"]\n[WhiteElo "2810"]\n[BlackElo "2725"]\n[Result "1-0"]\n1. d4 Nf6 2. c4 e6 3. Nf3 d5 4. Nc3 Be7 5. Bg5 O-O 6. e3 h6 7. Bf4 Be7 8. Bd3 c5 9. cxd5 exd5 10. dxc5 Bxc5 11. O-O Nc6 12. Re1 Be7 13. Bg3 Be6 14. Nd2 Nb4 15. Bb1 Rc8 16. Ce4 Na6 17. Nxf6+ Bxf6 18. Bxd5 Bxd5 19. Qxd5 Rc5 20. Qd1 Rc8 21. Qd5 Rc5 22. Qd1 1-0',
      'g-003': '[Event "Hoogeveen"]\n[Site "Hoogeveen NED"]\n[Date "2003.10.16"]\n[White "Polgar, Judit"]\n[Black "Anand, Viswanathan"]\n[WhiteElo "2735"]\n[BlackElo "2774"]\n[Result "0-1"]\n1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be3 e5 7. Nb3 Be7 8. f3 O-O 9. g4 Be6 10. Qd2 Nbd7 11. O-O-O Nb6 12. g5 Nfd7 13. f4 Rc8 14. f5 Bc4 15. Qf2 Nc4 16. Bxc4 Rxc4 17. Qg3 Qc8 18. Nd5 Rc5 19. c3 b5 20. b4 Rc8 21. a4 bxa4 22. Nxa4 Nxa4 23. Rxa4 Qc6 24. Qg2 Rc4 25. Rd2 Qc8 26. Qg3 Rc7 27. Rda2 f6 28. gxf6 gxf6 29. Qg6 Rg7 30. Qh6 Rg8 31. Qg6 Rg7 32. Qh6 Rg8 33. Qg6 0-1',
    };
    return pgns[gameId] || '[Event "?"]\n[White "?"]\n[Black "?"]\n[Result "*"]\n1. d4 Nf6 2. c4 e6 *';
  }

  private parseHeaders(pgn: string): GameHeaders {
    const headers: GameHeaders = {};
    for (const line of pgn.split('\n')) {
      const m = line.match(/\[(\w+)\s+"(.+)"\]/);
      if (m) headers[m[1]] = m[2];
    }
    return headers;
  }

  private buildMoveTree(pgn: string): EditorMove[] {
    // Extract just the movetext (after the headers)
    const movetext = pgn.split('\n').filter((l) => !l.startsWith('[')).join(' ');
    // Tokenize SAN moves from the movetext
    const tokens = movetext
      .replace(/\{[^}]*}/g, '') // remove comments
      .replace(/\([^)]*\)/g, '') // remove variations
      .replace(/\$\d+/g, '') // remove NAGs
      .split(/\s+/)
      .filter((t) => t && !t.match(/^\d+\.$/) && !['1-0', '0-1', '1/2-1/2', '*'].includes(t));

    const moves: EditorMove[] = [];
    let ply = 0;
    const chess = new Chess();
    for (const san of tokens) {
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

  async getGame(gameId: string): Promise<GameDetail> {
    return this.buildGameDetail(gameId);
  }

  async updateGame(gameId: string, payload: GameUpdatePayload): Promise<GameDetail> {
    const detail = this.buildGameDetail(gameId);
    if (payload.headers) {
      detail.headers = { ...detail.headers, ...payload.headers };
    }
    if (payload.comment) {
      // Attach as a top-level comment (on the first move, or a synthetic move-0)
      if (detail.moves.length > 0) {
        detail.moves[0].comment = payload.comment;
      }
    }
    this.gameStore.set(gameId, detail);
    return { ...detail, moves: detail.moves.map((m) => ({ ...m })) };
  }

  async addVariation(gameId: string, payload: VariationPayload): Promise<GameDetail> {
    const detail = this.buildGameDetail(gameId);
    const parentMove = detail.moves.find((m) => m.id === payload.parentMoveId);
    if (parentMove) {
      const variationMoves: EditorMove[] = payload.moves.map((m, i) => ({
        id: `v-${Date.now()}-${i}`,
        san: m.san,
        uci: '',
        fen: '',
        color: (parentMove.ply + i) % 2 === 0 ? 'w' : 'b',
        ply: parentMove.ply + i + 1,
        nags: [],
        annotations: [],
        variations: [],
      }));
      parentMove.variations.push({
        id: `var-${Date.now()}`,
        moves: variationMoves,
        comment: payload.comment,
      });
    }
    this.gameStore.set(gameId, detail);
    return { ...detail, moves: detail.moves.map((m) => ({ ...m })) };
  }

  async setMoveComment(gameId: string, moveId: string, payload: MoveCommentPayload): Promise<GameDetail> {
    const detail = this.buildGameDetail(gameId);
    const move = detail.moves.find((m) => m.id === moveId);
    if (move) {
      move.comment = payload.comment;
    }
    this.gameStore.set(gameId, detail);
    return { ...detail, moves: detail.moves.map((m) => ({ ...m })) };
  }

  async importDatabase(payload: ImportPayload): Promise<JobProgress> {
    this.jobId += 1;
    const jobId = `mock-import-${this.jobId}`;
    const total = 100;
    const job: JobProgress = {
      jobId,
      type: 'import',
      status: 'running',
      progress: 0,
      total,
      databaseId: payload.databaseId,
      message: `Importing ${payload.filename} (${payload.format})…`,
      startedAt: Date.now(),
    };
    this.jobStore.set(jobId, job);
    return { ...job };
  }

  async exportDatabase(payload: ExportPayload): Promise<JobProgress> {
    this.jobId += 1;
    const jobId = `mock-export-${this.jobId}`;
    const total = 100;
    const gameCount = payload.gameIds?.length || MOCK_GAMES.length;
    const job: JobProgress = {
      jobId,
      type: 'export',
      status: 'running',
      progress: 0,
      total,
      databaseId: payload.databaseId,
      message: `Exporting ${gameCount} games as ${payload.format}…`,
      startedAt: Date.now(),
    };
    this.jobStore.set(jobId, job);
    return { ...job };
  }

  async getJob(jobId: string): Promise<JobProgress> {
    const job = this.jobStore.get(jobId);
    if (!job) return {
      jobId, type: 'search', status: 'error', progress: 0, total: 0, startedAt: 0,
      message: `Unknown job: ${jobId}`,
    };
    // Advance mock progress on each poll
    this._advanceJob(jobId);
    return { ...job };
  }

  async deleteJob(jobId: string): Promise<void> {
    this.jobStore.delete(jobId);
  }

  async cancelJob(jobId: string): Promise<JobProgress> {
    const job = this.jobStore.get(jobId);
    if (!job) return {
      jobId, type: 'search', status: 'error', progress: 0, total: 0, startedAt: 0,
      message: `Unknown job: ${jobId}`,
    };
    job.status = 'cancelled';
    job.finishedAt = Date.now();
    job.message = 'Job cancelled by user';
    return { ...job };
  }

  _advanceJob(jobId: string): void {
    const job = this.jobStore.get(jobId);
    if (!job || job.status !== 'running') return;
    const store = job as unknown as Record<string, unknown>;
    const step = (store.__step as number) || 0;
    const nextStep = step + 20;
    store.__step = nextStep;
    job.progress = Math.min(nextStep, job.total);
    if (job.progress >= job.total) {
      job.status = 'complete';
      job.finishedAt = Date.now();
      job.message = job.type === 'import'
        ? `Import complete: ${job.total} games imported`
        : `Export complete: ${job.total} games exported`;
    }
  }

  // ── Index / ECO mock data ──────────────────────

  private readonly MOCK_NAMEBASES: Record<Exclude<IndexType, 'eco'>, NamebaseEntry[]> = {
    players: [
      { id: 'p-001', name: 'Carlsen, Magnus', games: 1 },
      { id: 'p-002', name: 'Kasparov, Garry', games: 1 },
      { id: 'p-003', name: 'Karpov, Anatoly', games: 1 },
      { id: 'p-004', name: 'Polgar, Judit', games: 1 },
      { id: 'p-005', name: 'Anand, Viswanathan', games: 1 },
      { id: 'p-006', name: 'Nepomniachtchi, Ian', games: 1 },
      { id: 'p-007', name: 'Fischer, Robert James', games: 1 },
      { id: 'p-008', name: 'Spassky, Boris', games: 1 },
    ],
    events: [
      { id: 'e-001', name: 'WCh 2021', games: 1 },
      { id: 'e-002', name: 'Linares', games: 1 },
      { id: 'e-003', name: 'Hoogeveen', games: 1 },
      { id: 'e-004', name: 'Reykjavik WCh', games: 1 },
    ],
    sites: [
      { id: 's-001', name: 'Dubai UAE', games: 1 },
      { id: 's-002', name: 'Linares ESP', games: 1 },
      { id: 's-003', name: 'Hoogeveen NED', games: 1 },
      { id: 's-004', name: 'Reykjavik ISL', games: 1 },
    ],
    annotators: [
      { id: 'a-001', name: 'Kasparov, Garry', games: 2 },
      { id: 'a-002', name: 'Anand, Viswanathan', games: 1 },
    ],
  };

  private readonly MOCK_ECO: EcoEntry[] = [
    { code: 'A00', name: 'Irregular openings', games: 0 },
    { code: 'A45', name: "Queen's pawn game", games: 1 },
    { code: 'A06', name: 'Reti opening', games: 0 },
    { code: 'A10', name: 'English opening', games: 0 },
    { code: 'B00', name: 'King\'s pawn opening', games: 0 },
    { code: 'B90', name: 'Sicilian, Najdorf', games: 1 },
    { code: 'D02', name: 'Queen\'s pawn game', games: 0 },
    { code: 'D37', name: 'Queen\'s gambit declined', games: 1 },
    { code: 'E56', name: 'Nimzo-Indian, Rubinstein', games: 1 },
  ];

  async getIndexes(type: IndexType): Promise<NamebaseEntry[] | EcoEntry[]> {
    if (type === 'eco') return [...this.MOCK_ECO];
    return [...(this.MOCK_NAMEBASES[type] || [])];
  }

  async getEcoTable(): Promise<EcoEntry[]> {
    return [...this.MOCK_ECO];
  }

  // ── Preparation mock endpoints (milestone 4) ─────

  private readonly repertoires: Repertoire[] = [
    {
      id: 'rep-w-italian',
      name: 'Italian Game (White)',
      side: 'white',
      eco: 'C50',
      moves: [
        { san: 'e4', uci: 'e2e4', fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1' },
        { san: 'e5', uci: 'e7e5', fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2', comment: 'Main response' },
        { san: 'Nf3', uci: 'g1f3', fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2' },
        { san: 'Nc6', uci: 'b8c6', fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3' },
        { san: 'Bc4', uci: 'f1c4', fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK1R b KQkq - 3 3', comment: 'Italian Bishop' },
        { san: 'Bc5', uci: 'f8c5', fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK1R b KQkq - 4 4' },
      ],
      updatedAt: '2025-01-15T10:00:00Z',
    },
    {
      id: 'rep-b-sicilian',
      name: 'Sicilian Najdorf (Black)',
      side: 'black',
      eco: 'B90',
      moves: [
        { san: 'e4', uci: 'e2e4', fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1' },
        { san: 'c5', uci: 'c7c5', fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2', comment: 'Sicilian Defence' },
        { san: 'Nf3', uci: 'g1f3', fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2' },
        { san: 'd6', uci: 'd7d6', fen: 'rnbqkbnr/pp2pppp/3p4/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3' },
        { san: 'd4', uci: 'd2d4', fen: 'rnbqkbnr/pp2pppp/3p4/2p5/3PP3/5N2/PPP2PPP/RNBQKB1R b KQkq d3 0 3' },
        { san: 'cxd4', uci: 'c5d4', fen: 'rnbqkbnr/pp2pppp/3p4/8/3pP3/5N2/PPP2PPP/RNBQKB1R w KQkq - 0 4' },
        { san: 'Nxd4', uci: 'f3d4', fen: 'rnbqkbnr/pp2pppp/3p4/8/3NP3/8/PPP2PPP/RNBQKB1R b KQkq - 1 4' },
        { san: 'Nf6', uci: 'g8f6', fen: 'rnbqkb1r/pp2pppp/3p1n2/8/3NP3/8/PPP2PPP/RNBQKB1R w KQkq - 2 5' },
        { san: 'Nc3', uci: 'b1c3', fen: 'rnbqkb1r/pp2pppp/3p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R b KQkq - 3 5' },
        { san: 'a6', uci: 'a7a6', fen: 'rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 6', comment: 'Najdorf Variation' },
      ],
      updatedAt: '2025-02-20T14:30:00Z',
    },
  ];

  async listRepertoires(): Promise<Repertoire[]> {
    return [...this.repertoires];
  }

  private mockPlayers: PlayerSummary[] = [
    { id: 'p-carlsen', name: 'Carlsen, Magnus', elo: 2839, title: 'GM', country: 'NOR', games: 3120 },
    { id: 'p-caruana', name: 'Caruana, Fabiano', elo: 2797, title: 'GM', country: 'USA', games: 2780 },
    { id: 'p-nepo', name: 'Nepomniachtchi, Ian', elo: 2769, title: 'GM', country: 'RUS', games: 2450 },
    { id: 'p-ding', name: 'Ding, Liren', elo: 2778, title: 'GM', country: 'CHN', games: 2210 },
    { id: 'p-firouzja', name: 'Firouzja, Alireza', elo: 2737, title: 'GM', country: 'FRA', games: 1980 },
    { id: 'p-anand', name: 'Anand, Viswanathan', elo: 2754, title: 'GM', country: 'IND', games: 3450 },
    { id: 'p-naka', name: 'Nakamura, Hikaru', elo: 2768, title: 'GM', country: 'USA', games: 3100 },
    { id: 'p-giri', name: 'Giri, Anish', elo: 2748, title: 'GM', country: 'NED', games: 2890 },
  ];

  async listPlayers(query?: string): Promise<PlayerSummary[]> {
    if (!query) return [...this.mockPlayers];
    const q = query.toLowerCase();
    return this.mockPlayers.filter((p) => p.name.toLowerCase().includes(q));
  }

  async getPlayerCard(playerId: string): Promise<PlayerCard> {
    const summary = this.mockPlayers.find((p) => p.id === playerId);
    if (!summary) throw new Error(`Player not found: ${playerId}`);
    const games = await this.listGames();
    const recent = games.filter(
      (g) => g.white.includes(summary.name) || g.black.includes(summary.name)
    );
    return {
      ...summary,
      peakElo: summary.elo + 30,
      winRate: 42,
      drawRate: 38,
      lossRate: 20,
      topOpenings: [
        { eco: 'A45', name: "Queen's pawn game", games: 280, score: 54.2 },
        { eco: 'C50', name: 'Italian Game', games: 210, score: 51.5 },
        { eco: 'B90', name: 'Sicilian Najdorf', games: 195, score: 49.8 },
      ],
      recentGames: recent,
    };
  }

  async createOpeningPrepReport(payload: OpeningPrepRequest): Promise<PrepReport> {
    const rep = this.repertoires.find((r) => r.id === payload.repertoireId);
    if (!rep) throw new Error(`Repertoire not found: ${payload.repertoireId}`);
    return {
      jobId: `prep-opening-${Date.now()}`,
      status: 'complete',
      type: 'opening',
      subject: rep.name,
      databaseId: payload.databaseId || 'masters',
      lines: rep.moves.slice(0, 6).map((m, i) => ({
        san: m.san,
        uci: m.uci,
        games: 500 - i * 60,
        whiteScore: 52 - i * 2,
        blackScore: 48 + i * 2,
        performance: i < 2 ? 'good' : i < 4 ? 'solid' : 'neutral',
        note: i === 0 ? 'Main line — well-tested' : `Move ${i + 1} in the repertoire`,
      })),
      summary: `Opening prep report for ${rep.name} based on ${rep.moves.length} moves.`,
      createdAt: Date.now(),
    };
  }

  async createPlayerPrepReport(payload: PlayerPrepRequest): Promise<PrepReport> {
    const player = this.mockPlayers.find((p) => p.id === payload.playerId);
    if (!player) throw new Error(`Player not found: ${payload.playerId}`);
    return {
      jobId: `prep-opponent-${Date.now()}`,
      status: 'complete',
      type: 'opponent',
      subject: player.name,
      databaseId: payload.databaseId || 'masters',
      lines: [
        { san: 'e4', uci: 'e2e4', games: 1240, whiteScore: 54, blackScore: 46, performance: 'good', note: 'Most common opening choice' },
        { san: 'd4', uci: 'd2d4', games: 880, whiteScore: 51, blackScore: 49, performance: 'solid', note: 'Secondary choice' },
        { san: 'Nf3', uci: 'g1f3', games: 320, whiteScore: 49, blackScore: 51, performance: 'rare', note: 'Occasional transposition' },
      ],
      summary: `Opponent prep for ${player.name} (${player.elo}). ${player.games} games analysed.`,
      createdAt: Date.now(),
    };
  }

  // ── Maintenance & crosstables mock (milestone 5) ──

  private readonly maintenanceReportStore = new Map<string, MaintenanceReport>();

  async startMaintenance(payload: MaintenanceJobRequest): Promise<JobProgress> {
    this.jobId += 1;
    const jobId = `mock-maintenance-${this.jobId}`;
    const total = 100;
    const job: JobProgress = {
      jobId,
      type: 'maintenance',
      status: 'running',
      progress: 0,
      total,
      databaseId: payload.databaseId,
      message: `Running ${payload.operation} on ${payload.databaseId}…`,
      startedAt: Date.now(),
    };
    this.jobStore.set(jobId, job);
    // Pre-generate the report so it's ready when the job completes
    const report = this._generateMaintenanceReport(jobId, payload);
    this.maintenanceReportStore.set(jobId, report);
    return { ...job };
  }

  async getMaintenanceReport(jobId: string): Promise<MaintenanceReport> {
    const job = this.jobStore.get(jobId);
    if (!job) throw new Error(`Maintenance job not found: ${jobId}`);
    // Advance job progress on each poll
    this._advanceJob(jobId);
    const report = this.maintenanceReportStore.get(jobId);
    if (!report) throw new Error(`Report not found for job: ${jobId}`);
    report.status = job.status;
    return { ...report };
  }

  _generateMaintenanceReport(jobId: string, payload: MaintenanceJobRequest): MaintenanceReport {
    const base: MaintenanceReport = {
      jobId,
      operation: payload.operation,
      databaseId: payload.databaseId,
      status: 'running',
    };
    switch (payload.operation) {
      case 'duplicate-detection':
        return {
          ...base,
          duplicates: [
            { gameId: 'g-001', duplicates: ['g-005'], white: 'Carlsen, Magnus', black: 'Nepomniachtchi, Ian', date: '2021.12.03' },
            { gameId: 'g-002', duplicates: ['g-006', 'g-007'], white: 'Kasparov, Garry', black: 'Karpov, Anatoly', date: '1993.03.02' },
          ],
          message: 'Found 2 duplicate groups (3 duplicate games).',
        };
      case 'eco-stats':
        return {
          ...base,
          ecoStats: [
            { eco: 'A45', name: "Queen's pawn game", games: 420_000, whiteScore: 52.8, drawRate: 42.0 },
            { eco: 'D37', name: 'QGD', games: 310_000, whiteScore: 50.5, drawRate: 48.0 },
            { eco: 'B90', name: 'Sicilian Najdorf', games: 280_000, whiteScore: 49.2, drawRate: 38.0 },
            { eco: 'E56', name: 'Nimzo-Indian Rubinstein', games: 190_000, whiteScore: 51.0, drawRate: 45.0 },
            { eco: 'C50', name: 'Italian Game', games: 175_000, whiteScore: 53.1, drawRate: 40.0 },
          ],
          message: 'ECO statistics computed for 5 opening codes.',
        };
      case 'compaction':
        return {
          ...base,
          compaction: {
            bytesBefore: 48_000_000,
            bytesAfter: 41_200_000,
            savedBytes: 6_800_000,
            savedPercent: 14.2,
          },
          message: 'Compaction saved 6.8 MB (14.2%).',
        };
      case 'strip-variants':
        return {
          ...base,
          strip: {
            strippedVariations: 342,
            strippedComments: 1280,
            strippedNags: 95,
          },
          message: 'Stripped 342 variations, 1280 comments, 95 NAGs.',
        };
      default:
        return { ...base, message: 'Unknown maintenance operation.' };
    }
  }

  private readonly MOCK_CROSSTABLE: CrosstableResult = {
    event: 'Tata Steel Masters',
    site: 'Wijk aan Zee NED',
    totalRounds: 13,
    players: [
      { player: 'Carlsen, Magnus', games: 13, points: 9.0, wins: 6, draws: 6, losses: 1, sonnebornBerger: 72.5, rank: 1 },
      { player: 'Caruana, Fabiano', games: 13, points: 8.5, wins: 5, draws: 7, losses: 1, sonnebornBerger: 68.0, rank: 2 },
      { player: 'Ding, Liren', games: 13, points: 8.0, wins: 4, draws: 8, losses: 1, sonnebornBerger: 64.5, rank: 3 },
      { player: 'Nepomniachtchi, Ian', games: 13, points: 7.5, wins: 4, draws: 7, losses: 2, sonnebornBerger: 60.0, rank: 4 },
      { player: 'Anand, Viswanathan', games: 13, points: 7.0, wins: 3, draws: 8, losses: 2, sonnebornBerger: 56.5, rank: 5 },
      { player: 'Giri, Anish', games: 13, points: 6.5, wins: 2, draws: 9, losses: 2, sonnebornBerger: 52.0, rank: 6 },
      { player: 'Nakamura, Hikaru', games: 13, points: 6.0, wins: 2, draws: 8, losses: 3, sonnebornBerger: 48.5, rank: 7 },
      { player: 'Firouzja, Alireza', games: 13, points: 5.5, wins: 2, draws: 7, losses: 4, sonnebornBerger: 44.0, rank: 8 },
    ],
  };

  async queryCrosstable(payload: CrosstableQuery): Promise<CrosstableResult> {
    // Filter by event/site/players if specified
    let result = { ...this.MOCK_CROSSTABLE, players: [...this.MOCK_CROSSTABLE.players] };
    if (payload.event) {
      result = { ...result, event: payload.event };
    }
    if (payload.site) {
      result = { ...result, site: payload.site };
    }
    if (payload.players && payload.players.length > 0) {
      const filterSet = new Set(payload.players.map((p) => p.toLowerCase()));
      result = {
        ...result,
        players: result.players.filter((p) => filterSet.has(p.player.toLowerCase())),
      };
    }
    return result;
  }
}

export function createApiClient(): ScidbApiClient {
  const baseUrl = import.meta.env?.VITE_SCIDB_API_BASE || (typeof window !== 'undefined' ? window.SCIDB_API_BASE || '/api' : '/api');
  const http = new HttpScidbApiClient(baseUrl);
  return new Proxy(http, {
    get(target, prop, receiver) {
      const value = Reflect.get(target, prop, receiver);
      if (typeof value !== 'function') return value;
      return async (...args: unknown[]) => {
        try {
          return await value.apply(target, args);
        } catch (err) {
          console.warn(`HTTP API call ${String(prop)} failed, falling back to mock:`, err);
          const mock = new MockScidbApiClient();
          const fallback = Reflect.get(mock, prop);
          if (typeof fallback === 'function') {
            return fallback.apply(mock, args);
          }
          throw err;
        }
      };
    },
  });
}
