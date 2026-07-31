export type DatabaseFormat = 'SCI' | 'SI3' | 'CBH' | 'CBV' | 'PGN';

export interface Database {
  id: string;
  name: string;
  format: DatabaseFormat;
  games: number;
  readOnly: boolean;
}

export interface GameSummary {
  id: string;
  white: string;
  whiteElo: number;
  black: string;
  blackElo: number;
  event: string;
  site: string;
  date: string;
  result: string;
  eco: string;
}

export type SearchType = 'advanced' | 'material' | 'rating' | 'cql';

export interface AdvancedQuery {
  white?: string;
  black?: string;
  event?: string;
  site?: string;
  ecoFrom?: string;
  ecoTo?: string;
  result?: string;
  yearFrom?: number;
  yearTo?: number;
}

export interface MaterialQuery {
  whiteQ?: number;
  whiteR?: number;
  whiteB?: number;
  whiteN?: number;
  whiteP?: number;
  blackQ?: number;
  blackR?: number;
  blackB?: number;
  blackN?: number;
  blackP?: number;
  imbalance?: 'up' | 'down' | 'equal';
}

export interface RatingQuery {
  whiteEloMin?: number;
  whiteEloMax?: number;
  blackEloMin?: number;
  blackEloMax?: number;
  averageEloMin?: number;
  averageEloMax?: number;
}

export interface CqlQuery {
  cql?: string;
}

export type SearchQuery = AdvancedQuery | MaterialQuery | RatingQuery | CqlQuery;

export interface SearchPayload {
  databaseId?: string;
  type: SearchType;
  query: SearchQuery;
}

export interface SearchJob {
  jobId: string;
  status: 'pending' | 'running' | 'complete' | 'error' | 'cancelled' | 'stopped';
  total: number;
  games?: GameSummary[];
  query?: SearchPayload;
}

export interface EngineInfo {
  engineId: string;
  name: string;
  path: string;
}

export interface AnalysisLine {
  pv: string;
  eval: string;
  depth: number;
}

export interface AnalysisJob {
  jobId: string;
  status: 'pending' | 'running' | 'complete' | 'stopped' | 'unknown';
  fen: string;
  depth: number;
  multiPv: number;
  lines: AnalysisLine[];
  nodes: number;
  nps: number;
  startedAt?: number;
}

export interface OpeningMove {
  san: string;
  uci: string;
  games: number;
  score: number;
  white: number;
  draw: number;
  black: number;
  eco: string;
}

export interface SavedWorkingSet {
  id: string;
  name: string;
  games: GameSummary[];
}

export interface WorkspaceState {
  activeDatabaseId: string;
  activeGameId: string | null;
  activePanel: string;
  currentFen: string;
  pendingJobId: string | null;
  workingSet: GameSummary[];
  savedWorkingSets: SavedWorkingSet[];
  activeSearchJobId: string | null;
  activeEngineJobId: string | null;
}

export type WorkspaceListener = (state: WorkspaceState) => void;

// ===== Search & Tree hardening types (milestone 3) =====

export type GameSortField = 'white' | 'black' | 'event' | 'site' | 'date' | 'eco' | 'result';
export type SortOrder = 'asc' | 'desc';

export interface PaginatedGamesRequest {
  databaseId?: string;
  page?: number;
  limit?: number;
  sort?: GameSortField;
  order?: SortOrder;
  query?: string;
}

export interface PaginatedGames {
  games: GameSummary[];
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

export interface OpeningTreeRequest {
  moves: { uci: string; san: string }[];
  fen?: string;
  source?: string;
}

export interface EcoEntry {
  code: string;
  name: string;
  games: number;
}

export type IndexType = 'players' | 'events' | 'sites' | 'annotators' | 'eco';

export interface NamebaseEntry {
  id: string;
  name: string;
  games: number;
}

// ===== Job types =====

export type JobStatus = 'pending' | 'running' | 'complete' | 'error' | 'cancelled' | 'stopped';
export type JobType = 'search' | 'import' | 'export' | 'report' | 'maintenance' | 'analysis';

export interface JobProgress {
  jobId: string;
  type: JobType;
  status: JobStatus;
  progress: number;
  total: number;
  databaseId?: string;
  message?: string;
  startedAt: number;
  finishedAt?: number;
  result?: unknown;
}

export interface ImportPayload {
  databaseId: string;
  format: DatabaseFormat;
  filename: string;
}

export interface ExportPayload {
  databaseId: string;
  format: DatabaseFormat;
  gameIds?: string[];
}

export interface ImportJob {
  jobId: string;
  type: 'import';
  status: JobStatus;
  progress: number;
  total: number;
  databaseId: string;
  filename: string;
  format: DatabaseFormat;
  message: string;
  startedAt: number;
  finishedAt?: number;
}

export interface ExportJob {
  jobId: string;
  type: 'export';
  status: JobStatus;
  progress: number;
  total: number;
  databaseId: string;
  format: DatabaseFormat;
  gameCount: number;
  downloadUrl?: string;
  message: string;
  startedAt: number;
  finishedAt?: number;
}

// ===== Opening Report types =====

export interface MoveEntry {
  san: string;
  uci: string;
}

export interface OpeningInfo {
  eco: string;
  name: string;
}

export interface ExplorerMove {
  uci: string;
  san: string;
  white: number;
  draws: number;
  black: number;
  averageRating?: number;
}

export interface TopGame {
  id: string;
  month?: string;
}

export interface ExplorerOpts {
  source?: string;
  speed?: string;
  ratings?: number[];
}

export interface ExplorerData {
  white: number;
  draws: number;
  black: number;
  moves: ExplorerMove[];
  opening?: OpeningInfo;
  turn: string;
  topGames: TopGame[];
  fen: string;
}

export interface EloRange {
  label: string;
  min: number;
  max: number;
}

export interface EloSegment {
  range: EloRange;
  data: ExplorerData;
}

export interface YearlyData {
  year: number;
  count: number;
}

export interface HistoricalData {
  yearlyData: YearlyData[];
  topGames: TopGame[];
  totalGames: number;
}

export interface GameWithPgn extends TopGame {
  pgn: string | null;
  index: number;
}

export interface CharacterTrait {
  icon: string;
  title: string;
  desc: string;
}

export interface TacticPosition {
  fen: string;
  solution: string;
  solutionUci: string;
  motif: string;
  turn: string;
  moveNum: number;
  gamePgn: string;
}

export interface Transposition {
  moves: string;
  description: string;
}

export interface Maneuver {
  key: string;
  piece: string;
  color: string;
  pathStr: string;
  games: number;
  frequency: string;
  successLabel: string;
}

export interface ReportOptions {
  source: string;
  speed: string;
  ratingRange: string;
}

export interface ReportData {
  moves: MoveEntry[];
  fen: string;
  openingInfo: OpeningInfo;
  mainData: ExplorerData;
  eloData: EloSegment[];
  historicalData: HistoricalData;
  topGames: TopGame[];
  gamesWithPgn: GameWithPgn[];
  characterization: CharacterTrait[];
  transpositions: Transposition[];
  maneuvers: Maneuver[];
  tactics: TacticPosition[];
  options: ReportOptions;
}

// ===== Game Editor types (milestone 2) =====

/** Numeric annotation glyph, e.g. $1 = "!". */
export interface NAG {
  code: number;
  label: string;
}

/** A text comment attached to a move or position. */
export interface Comment {
  text: string;
  color?: string;
}

/** A non-move annotation such as a clock time or evaluation mark. */
export interface Annotation {
  type: 'clock' | 'eval' | 'arrow' | 'square';
  value: string;
  from?: string;
  to?: string;
  color?: string;
}

/** A sub-line branching from a parent move. */
export interface Variation {
  id: string;
  moves: EditorMove[];
  comment?: Comment;
}

/** A single move inside the game tree (main line or variation). */
export interface EditorMove {
  id: string;
  san: string;
  uci: string;
  fen: string;
  color: 'w' | 'b';
  ply: number;
  comment?: Comment;
  nags: NAG[];
  annotations: Annotation[];
  variations: Variation[];
}

/** Editable PGN-style header tags. */
export interface GameHeaders {
  Event?: string;
  Site?: string;
  Date?: string;
  Round?: string;
  White?: string;
  Black?: string;
  WhiteElo?: string;
  BlackElo?: string;
  Result?: string;
  ECO?: string;
  [key: string]: string | undefined;
}

/** Full game detail returned by GET /games/:id. */
export interface GameDetail {
  id: string;
  headers: GameHeaders;
  moves: EditorMove[];
  pgn: string;
}

/** Payload for PATCH /games/:id — update headers and/or top-level comments. */
export interface GameUpdatePayload {
  headers?: Partial<GameHeaders>;
  comment?: Comment;
}

/** Payload for POST /games/:id/variations — create a new variation at a move. */
export interface VariationPayload {
  parentMoveId: string;
  moves: { san: string }[];
  comment?: Comment;
}

/** Payload for POST /games/:id/moves/:moveId/comments. */
export interface MoveCommentPayload {
  comment: Comment;
}

// ===== Maintenance types (milestone 5) =====

export type MaintenanceOperation =
  | 'duplicate-detection'
  | 'eco-stats'
  | 'compaction'
  | 'strip-variants';

export interface MaintenanceJobRequest {
  databaseId: string;
  operation: MaintenanceOperation;
}

export interface DuplicateGroup {
  gameId: string;
  duplicates: string[];
  white: string;
  black: string;
  date: string;
}

export interface EcoStatRow {
  eco: string;
  name: string;
  games: number;
  whiteScore: number;
  drawRate: number;
}

export interface CompactionResult {
  bytesBefore: number;
  bytesAfter: number;
  savedBytes: number;
  savedPercent: number;
}

export interface StripResult {
  strippedVariations: number;
  strippedComments: number;
  strippedNags: number;
}

export interface MaintenanceReport {
  jobId: string;
  operation: MaintenanceOperation;
  databaseId: string;
  status: JobStatus;
  duplicates?: DuplicateGroup[];
  ecoStats?: EcoStatRow[];
  compaction?: CompactionResult;
  strip?: StripResult;
  message?: string;
}

// ===== Crosstable types (milestone 5) =====

export interface CrosstableQuery {
  event?: string;
  site?: string;
  players?: string[];
}

export interface CrosstablePlayerRow {
  player: string;
  games: number;
  points: number;
  wins: number;
  draws: number;
  losses: number;
  sonnebornBerger: number;
  rank: number;
}

export interface CrosstableResult {
  event: string;
  site: string;
  players: CrosstablePlayerRow[];
  totalRounds: number;
}

// ===== Preparation types (milestone 4) =====

/** A single move entry inside a repertoire line. */
export interface RepertoireEntry {
  san: string;
  uci: string;
  fen: string;
  comment?: string;
}

/** A repertoire line for one side (White or Black). */
export interface Repertoire {
  id: string;
  name: string;
  side: 'white' | 'black';
  eco: string;
  moves: RepertoireEntry[];
  updatedAt: string;
}

/** Request body for POST /prep/reports (opening prep). */
export interface OpeningPrepRequest {
  repertoireId: string;
  databaseId?: string;
}

/** Request body for POST /players/:id/prep (opponent prep). */
export interface PlayerPrepRequest {
  playerId: string;
  databaseId?: string;
  color?: 'white' | 'black';
}

/** A player summary returned by GET /players. */
export interface PlayerSummary {
  id: string;
  name: string;
  elo: number;
  title?: string;
  country?: string;
  games: number;
}

/** A detailed player card returned by GET /players/:id/card. */
export interface PlayerCard {
  id: string;
  name: string;
  elo: number;
  title?: string;
  country?: string;
  peakElo: number;
  games: number;
  winRate: number;
  drawRate: number;
  lossRate: number;
  topOpenings: { eco: string; name: string; games: number; score: number }[];
  recentGames: GameSummary[];
}

/** A prep report (opening or opponent) returned by POST /prep/reports or POST /players/:id/prep. */
export interface PrepReport {
  jobId: string;
  status: JobStatus;
  type: 'opening' | 'opponent';
  subject: string;
  databaseId: string;
  lines: PrepLine[];
  summary: string;
  createdAt: number;
}

/** A single line inside a prep report. */
export interface PrepLine {
  san: string;
  uci: string;
  games: number;
  whiteScore: number;
  blackScore: number;
  performance: 'good' | 'solid' | 'risky' | 'rare' | 'neutral';
  note: string;
}

/* ---------- Online play (Phase 0: types only; backend wired in later phases) ---------- */

export type PlayMode = 'analysis' | 'play';
export type PlayVariant = 'standard' | 'chess960';

export interface PlayTimeControl {
  kind: 'unlimited' | 'rapid' | 'blitz' | 'bullet' | 'correspondence';
  baseSeconds: number;      // initial clock, 0 = unlimited
  incrementSeconds: number;  // per-move increment
}

export interface PlayUser {
  id: string;        // OIDC subject, or 'guest-<random>' for anonymous
  name: string;      // display name; 'Guest-XXXX' for anonymous
  rating: number;    // Glicko-2 rating; provisional default for guests
  title?: string;
}

export interface PlaySeek {
  id: string;
  owner: PlayUser;          // null/anonymous for open seeks
  timeControl: PlayTimeControl;
  variant: PlayVariant;
  rated: boolean;
  color: 'w' | 'b' | 'random';
  ratingRange: [number, number] | null;
  startFen?: string;        // custom/Chess960 start
  createdAt: number;        // epoch ms
}

export type PlayMatchState = 'seeking' | 'paired' | 'playing' | 'finished';

export type PlayResult =
  | { kind: 'mate'; winner: 'w' | 'b' }
  | { kind: 'resign'; winner: 'w' | 'b' }
  | { kind: 'timeout'; winner: 'w' | 'b' }
  | { kind: 'draw'; reason: 'agreement' | 'stalemate' | 'insufficient' | 'threefold' | 'fifty' | 'timeout-both' }
  | { kind: 'aborted' }      // no rated effect, too few plies
  | { kind: 'adjourned' };

export interface PlayMatch {
  id: string;
  variant: PlayVariant;
  timeControl: PlayTimeControl;
  rated: boolean;
  white: PlayUser;
  black: PlayUser;
  startFen: string;
  ply: number;              // moves played (0 = start)
  status: PlayMatchState;
  result: PlayResult | null;
  clocks: { whiteMs: number; blackMs: number };  // server snapshot at last event
  clockUpdatedAt: number;   // epoch ms of clock snapshot
  drawOfferSide: 'w' | 'b' | null;
  rematchOfferSide: 'w' | 'b' | null;
  /** Mock-only: the tab that arbitrates clocks/timeout. Not part of the wire
   *  contract; the real server handles this server-side. */
  arbiterId?: string;
}

export interface PlayMove {
  ply: number;
  san: string;
  uci: string;
  fen: string;
  clockMsAfter: number;
  latencyMs: number;
}

/** Server→client event union for the /api/ws/play channel (and the mock). */
export type PlayEvent =
  | { type: 'seek.created'; seek: PlaySeek }
  | { type: 'seek.cancelled'; seekId: string }
  | { type: 'match.paired'; match: PlayMatch }
  | { type: 'match.move'; matchId: string; move: PlayMove; clocks: PlayMatch['clocks']; clockUpdatedAt: number }
  | { type: 'match.finish'; matchId: string; result: PlayResult; clocks: PlayMatch['clocks'] }
  | { type: 'match.offer'; matchId: string; offer: 'draw' | 'rematch' | 'takeback'; side: 'w' | 'b' }
  | { type: 'match.offer.response'; matchId: string; offer: 'draw' | 'rematch' | 'takeback'; accepted: boolean; side: 'w' | 'b' }
  | { type: 'match.chat'; matchId: string; side: 'w' | 'b'; text: string };
