export function OpeningTreeModal() {
  return (
    <div id="opening-tree-modal" className="modal" style={{ display: 'none' }}>
      <div className="modal-content opening-tree-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">REFERENCE DATABASE · MASTER GAMES</span>
            <h3>Opening tree</h3>
          </div>
          <button id="opening-tree-close" className="modal-close">✕</button>
        </div>
        <div className="tree-context">
          <span>Current position</span>
          <strong>Start position</strong>
          <small>Click a move to continue the line</small>
        </div>
        <div className="tree-head">
          <span>MOVE</span>
          <span>GAMES</span>
          <span>WHITE SCORE</span>
          <span>ECO</span>
        </div>
        <div id="opening-tree-list" className="opening-tree-list"></div>
      </div>
    </div>
  );
}

export function GameSwitcherModal() {
  return (
    <div id="game-switcher-modal" className="modal" style={{ display: 'none' }}>
      <div className="modal-content game-switcher-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">MASTER GAMES</span>
            <h3>Game switcher</h3>
          </div>
          <button id="game-switcher-close" className="modal-close">✕</button>
        </div>
        <div className="database-toolbar">
          <input id="game-search" type="search" placeholder="Search players, events, ECO…" />
          <button className="ghost-btn">Advanced filters</button>
        </div>
        <div className="game-table-head">
          <span>GAME</span>
          <span>EVENT / DATE</span>
          <span>ECO</span>
        </div>
        <div id="game-switcher-list" className="game-switcher-list"></div>
      </div>
    </div>
  );
}

export function DatabaseModal() {
  return (
    <div id="database-modal" className="modal" style={{ display: 'none' }}>
      <div className="modal-content database-modal-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">LIBRARY</span>
            <h3>Database manager</h3>
          </div>
          <button id="database-modal-close" className="modal-close">✕</button>
        </div>
        <div className="database-toolbar">
          <input id="database-filter" type="search" placeholder="Filter databases…" />
          <button className="primary-btn" id="database-create">
            ＋ Create database
          </button>
        </div>
        <div id="database-list" className="database-list"></div>
      </div>
    </div>
  );
}

export function SearchCenterModal() {
  return (
    <div id="search-center-modal" className="modal" style={{ display: 'none' }}>
      <div className="modal-content search-center-content">
        <div className="modal-header">
          <div>
            <span className="eyebrow">SEARCH CENTER</span>
            <h3>Find games</h3>
          </div>
          <button id="search-center-close" className="modal-close">✕</button>
        </div>
        <div className="search-center-body">
          <div className="search-tabs">
            <button className="search-tab active" data-tab="advanced">Advanced</button>
            <button className="search-tab" data-tab="material">Material</button>
            <button className="search-tab" data-tab="rating">Rating</button>
            <button className="search-tab" data-tab="cql">CQL</button>
          </div>
          <div className="search-panels">
            <div className="search-tab-panel active" data-panel="advanced">
              <div className="search-form-grid">
                <div className="control-group">
                  <label>White player</label>
                  <input id="search-query-white" type="text" placeholder="e.g. Carlsen" />
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

            <div className="search-tab-panel" data-panel="material">
              <p className="search-hint">
                Match positions by exact piece counts. Leave a field blank to ignore it.
              </p>
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
                    <label>{label}</label>
                    <input id={`search-mat-${id}`} type="number" min={0} max={max} placeholder={`0–${max}`} />
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

            <div className="search-tab-panel" data-panel="rating">
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
                    <label>{label}</label>
                    <input id={`search-rating-${id}`} type="number" placeholder="1600–2900" />
                  </div>
                ))}
              </div>
            </div>

            <div className="search-tab-panel" data-panel="cql">
              <p className="search-hint">Write a Chess Query Language expression. The backend will validate and execute it.</p>
              <div className="control-group full-width">
                <label>CQL query</label>
                <textarea
                  id="search-cql-text"
                  rows={8}
                  placeholder="(match\n  :gamenumber 1 100\n)\n"
                />
              </div>
            </div>
          </div>

          <div className="search-actions">
            <span id="search-status" className="search-status">Ready</span>
            <div className="search-actions-right">
              <button id="search-center-clear" className="ghost-btn">Clear</button>
              <button id="search-center-run" className="primary-btn">Run search</button>
            </div>
          </div>

          <div className="search-results-header">
            <span>Working set</span>
            <button id="search-center-promote" className="ghost-btn">Promote to switcher</button>
          </div>
          <div id="search-results" className="search-results-list">
            <div className="database-empty">Run a search to populate the working set.</div>
          </div>
        </div>
      </div>
    </div>
  );
}

// TacticsModal and GameViewerModal have been ported to React feature modules:
//   src/features/tactics/TacticsModal.tsx
//   src/features/games/GameViewerModal.tsx
