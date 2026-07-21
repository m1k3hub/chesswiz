import { useEffect, useState, useRef } from 'react';
import { createApiClient } from '@/api/client';
import { useWorkspaceStore } from '@/state/workspace';
import { isValidCql } from '@/lib/validation';
import type { GameSummary, SearchPayload, SearchQuery, SearchType, SearchJob } from '@/types';

const api = createApiClient();

const TABS: { id: SearchType; label: string }[] = [
  { id: 'advanced', label: 'Advanced' },
  { id: 'material', label: 'Material' },
  { id: 'rating', label: 'Rating' },
  { id: 'cql', label: 'CQL' },
];

export default function SearchCenterModal() {
  const [isOpen, setIsOpen] = useState(false);
  const [activeTab, setActiveTab] = useState<SearchType>('advanced');
  const [status, setStatus] = useState('Ready');
  const [statusClass, setStatusClass] = useState('');
  const [job, setJob] = useState<SearchJob | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const activeDatabaseId = useWorkspaceStore((s) => s.activeDatabaseId);
  const setWorkingSet = useWorkspaceStore((s) => s.setWorkingSet);
  const addWorkingSet = useWorkspaceStore((s) => s.addWorkingSet);
  const toast = window.ScidbWorkspace?.toast || console.log;
  const whiteInputRef = useRef<HTMLInputElement>(null);
  const [workingSetName, setWorkingSetName] = useState('');

  useEffect(() => {
    const handleOpen = () => {
      setIsOpen(true);
      setTimeout(() => whiteInputRef.current?.focus(), 0);
    };
    window.addEventListener('scidb:open-search-center', handleOpen);
    return () => window.removeEventListener('scidb:open-search-center', handleOpen);
  }, []);

  const readAdvancedQuery = () => {
    const get = (id: string) => (document.getElementById(id) as HTMLInputElement | null)?.value?.trim() || undefined;
    return {
      white: get('search-query-white'),
      black: get('search-query-black'),
      event: get('search-query-event'),
      site: get('search-query-site'),
      ecoFrom: get('search-query-eco-from'),
      ecoTo: get('search-query-eco-to'),
      result: (document.getElementById('search-query-result') as HTMLSelectElement | null)?.value,
      yearFrom: parseInt(get('search-query-year-from') || '') || undefined,
      yearTo: parseInt(get('search-query-year-to') || '') || undefined,
    };
  };

  const readMaterialQuery = (): SearchQuery => {
    const getInt = (id: string) => {
      const v = (document.getElementById(id) as HTMLInputElement | null)?.value;
      return v ? parseInt(v, 10) : undefined;
    };
    return {
      whiteQ: getInt('search-mat-wq'),
      whiteR: getInt('search-mat-wr'),
      whiteB: getInt('search-mat-wb'),
      whiteN: getInt('search-mat-wn'),
      whiteP: getInt('search-mat-wp'),
      blackQ: getInt('search-mat-bq'),
      blackR: getInt('search-mat-br'),
      blackB: getInt('search-mat-bb'),
      blackN: getInt('search-mat-bn'),
      blackP: getInt('search-mat-bp'),
      imbalance: (document.getElementById('search-mat-imbalance') as HTMLSelectElement | null)?.value as 'up' | 'down' | 'equal' | undefined,
    };
  };

  const readRatingQuery = () => {
    const getInt = (id: string) => {
      const v = (document.getElementById(id) as HTMLInputElement | null)?.value;
      return v ? parseInt(v, 10) : undefined;
    };
    return {
      whiteEloMin: getInt('search-rating-white-min'),
      whiteEloMax: getInt('search-rating-white-max'),
      blackEloMin: getInt('search-rating-black-min'),
      blackEloMax: getInt('search-rating-black-max'),
      averageEloMin: getInt('search-rating-avg-min'),
      averageEloMax: getInt('search-rating-avg-max'),
    };
  };

  const readCqlQuery = (): SearchQuery => ({
    cql: (document.getElementById('search-cql-text') as HTMLTextAreaElement | null)?.value?.trim() || undefined,
  });

  const buildPayload = (): SearchPayload => {
    const query = {
      advanced: readAdvancedQuery,
      material: readMaterialQuery,
      rating: readRatingQuery,
      cql: readCqlQuery,
    }[activeTab]();
    return { type: activeTab, databaseId: activeDatabaseId, query } as SearchPayload;
  };

  const runSearch = async () => {
    // Validate CQL before submitting if the CQL tab is active.
    if (activeTab === 'cql') {
      const cqlText = (document.getElementById('search-cql-text') as HTMLTextAreaElement | null)?.value?.trim() || '';
      if (cqlText && !isValidCql(cqlText)) {
        setStatus('Invalid CQL: unbalanced parentheses or forbidden content');
        setStatusClass('error');
        return;
      }
    }

    setIsSubmitting(true);
    setStatus('Submitting search…');
    setStatusClass('pending');
    setJob(null);
    try {
      const response = await api.search(buildPayload());
      const currentJobId = response.jobId;
      window.ScidbWorkspace?.setActiveSearchJobId(currentJobId);
      setStatus(`Job ${currentJobId} — ${response.status}`);
      setStatusClass('running');

      for (let attempts = 0; attempts < 40; attempts += 1) {
        const data = await api.getSearchResults(currentJobId);
        setStatus(`Job ${currentJobId} — ${data.status} (${data.total} games)`);
        setStatusClass(data.status);
        if (data.status === 'complete' || data.status === 'stopped' || data.status === 'error' || data.status === 'cancelled') {
          setJob(data);
          setWorkingSet(data.games || []);
          break;
        }
        await new Promise((resolve) => setTimeout(resolve, 250));
      }
    } catch (err) {
      setStatus(`Search failed: ${err instanceof Error ? err.message : String(err)}`);
      setStatusClass('error');
    } finally {
      setIsSubmitting(false);
    }
  };

  const clear = () => {
    document
      .querySelectorAll('.search-tab-panel input, .search-tab-panel select, .search-tab-panel textarea')
      .forEach((el) => {
        const input = el as HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement;
        input.value = '';
      });
    setJob(null);
    setStatus('Ready');
    setStatusClass('');
  };

  const promote = () => {
    const games = job?.games || [];
    if (games.length === 0) {
      toast('Working set is empty — run a search first', 'accent');
      return;
    }
    setWorkingSet(games);
    setIsOpen(false);
    window.dispatchEvent(new CustomEvent('scidb:open-game-switcher'));
  };

  const saveWorkingSet = () => {
    const games = job?.games || [];
    if (games.length === 0) {
      toast('Working set is empty — run a search first', 'accent');
      return;
    }
    addWorkingSet(workingSetName.trim());
    setWorkingSetName('');
    toast(`Saved working set (${games.length} games)`, 'success');
  };

  if (!isOpen) return null;

  return (
    <div id="search-center-modal" className="modal" style={{ display: 'flex' }} onClick={(e) => {
      if (e.target === e.currentTarget) setIsOpen(false);
    }}>
      <div className="modal-content search-center-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">SEARCH CENTER</span>
            <h3>Find games</h3>
          </div>
          <button id="search-center-close" className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
        </div>
        <div className="search-center-body">
          <div className="search-tabs">
            {TABS.map((tab) => (
              <button
                key={tab.id}
                className={`search-tab ${activeTab === tab.id ? 'active' : ''}`}
                onClick={() => setActiveTab(tab.id)}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="search-panels">
            <div className={`search-tab-panel ${activeTab === 'advanced' ? 'active' : ''}`}>
              <div className="search-form-grid">
                <div className="control-group">
                  <label>White player</label>
                  <input id="search-query-white" ref={whiteInputRef} type="text" placeholder="e.g. Carlsen" />
                </div>
                <div className="control-group">
                  <label>Black player</label>
                  <input id="search-query-black" type="text" placeholder="e.g. Anand" />
                </div>
                <div className="control-group">
                  <label>Event</label>
                  <input id="search-query-event" type="text" placeholder="e.g. Wijk aan Zee" />
                </div>
                <div className="control-group">
                  <label>Site</label>
                  <input id="search-query-site" type="text" placeholder="e.g. Moscow" />
                </div>
                <div className="control-group">
                  <label>ECO from</label>
                  <input id="search-query-eco-from" type="text" placeholder="A00" />
                </div>
                <div className="control-group">
                  <label>ECO to</label>
                  <input id="search-query-eco-to" type="text" placeholder="E99" />
                </div>
                <div className="control-group">
                  <label>Result</label>
                  <select id="search-query-result">
                    <option value="any">Any</option>
                    <option value="1-0">1–0</option>
                    <option value="0-1">0–1</option>
                    <option value="1/2-1/2">½–½</option>
                  </select>
                </div>
                <div className="control-group">
                  <label>Year from</label>
                  <input id="search-query-year-from" type="number" placeholder="1900" />
                </div>
                <div className="control-group">
                  <label>Year to</label>
                  <input id="search-query-year-to" type="number" placeholder="2025" />
                </div>
              </div>
            </div>

            <div className={`search-tab-panel ${activeTab === 'material' ? 'active' : ''}`}>
              <p className="search-hint">Match positions by exact piece counts. Leave a field blank to ignore it.</p>
              <div className="search-form-grid">
                {[
                  ['wq', 'White queens', 9],
                  ['bq', 'Black queens', 9],
                  ['wr', 'White rooks', 10],
                  ['br', 'Black rooks', 10],
                  ['wb', 'White bishops', 10],
                  ['bb', 'Black bishops', 10],
                  ['wn', 'White knights', 10],
                  ['bn', 'Black knights', 10],
                  ['wp', 'White pawns', 8],
                  ['bp', 'Black pawns', 8],
                ].map(([id, label, max]) => (
                  <div className="control-group" key={id}>
                    <label>{label as string}</label>
                    <input id={`search-mat-${id}`} type="number" min={0} max={max as number} placeholder={`0–${max}`} />
                  </div>
                ))}
                <div className="control-group full-width">
                  <label>Material imbalance</label>
                  <select id="search-mat-imbalance">
                    <option value="">Any</option>
                    <option value="up">Side to move up material</option>
                    <option value="down">Side to move down material</option>
                    <option value="equal">Equal material</option>
                  </select>
                </div>
              </div>
            </div>

            <div className={`search-tab-panel ${activeTab === 'rating' ? 'active' : ''}`}>
              <p className="search-hint">Filter games by player and average ratings.</p>
              <div className="search-form-grid">
                {[
                  ['white-min', 'White Elo min'],
                  ['white-max', 'White Elo max'],
                  ['black-min', 'Black Elo min'],
                  ['black-max', 'Black Elo max'],
                  ['avg-min', 'Average Elo min'],
                  ['avg-max', 'Average Elo max'],
                ].map(([id, label]) => (
                  <div className="control-group" key={id}>
                    <label>{label as string}</label>
                    <input id={`search-rating-${id}`} type="number" placeholder="1600–2900" />
                  </div>
                ))}
              </div>
            </div>

            <div className={`search-tab-panel ${activeTab === 'cql' ? 'active' : ''}`}>
              <p className="search-hint">Write a Chess Query Language expression. The backend will validate and execute it.</p>
              <div className="control-group full-width">
                <label>CQL query</label>
                <textarea id="search-cql-text" rows={8} placeholder="(match\n  :gamenumber 1 100\n)\n" />
              </div>
            </div>
          </div>

          <div className="search-actions">
            <span id="search-status" className={`search-status ${statusClass}`}>{status}</span>
            <div className="search-actions-right">
              <button id="search-center-clear" className="ghost-btn" onClick={clear}>Clear</button>
              <button id="search-center-run" className="primary-btn" onClick={runSearch} disabled={isSubmitting}>
                {isSubmitting ? 'Running…' : 'Run search'}
              </button>
            </div>
          </div>

          <div className="search-results-header">
            <span>Working set</span>
            <div className="search-actions-right">
              <input
                type="text"
                className="working-set-name-input"
                placeholder="Name this working set…"
                value={workingSetName}
                onChange={(e) => setWorkingSetName(e.target.value)}
              />
              <button className="ghost-btn" onClick={saveWorkingSet}>
                Save working set
              </button>
              <button id="search-center-promote" className="ghost-btn" onClick={promote}>Promote to switcher</button>
            </div>
          </div>
          <div id="search-results" className="search-results-list">
            {!job || !job.games ? (
              <div className="database-empty">Run a search to populate the working set.</div>
            ) : job.games.length === 0 ? (
              <div className="database-empty">No games match this search.</div>
            ) : (
              job.games.map((game: GameSummary) => (
                <button key={game.id} className="game-row" data-game-id={game.id}>
                  <span className="game-players">
                    <strong>{game.white}</strong>
                    <em>vs</em>
                    <strong>{game.black}</strong>
                  </span>
                  <span className="game-event">{game.event}<small>{game.date}</small></span>
                  <span className="game-eco">{game.eco}<small>{game.result}</small></span>
                </button>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
