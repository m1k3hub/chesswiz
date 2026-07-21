import { useState } from 'react';
import EngineInspector from '@/features/engine/EngineInspector';
import OpeningReport from '@/features/report/OpeningReport';

/**
 * ReportPanel — React shell around the opening report output and engine inspector.
 *
 * The report content is rendered by the OpeningReport React component, which
 * listens for `scidb:generate-report` events from the BoardPanel. The engine
 * inspector is a fully React component. Tab switching between Overview and
 * Engine is managed in React state.
 */
export default function ReportPanel() {
  const [activeTab, setActiveTab] = useState<'overview' | 'engine'>('overview');

  return (
    <div id="report-panel">
      <div className="inspector-header">
        <div className="inspector-tabs">
          <button
            className={`inspector-tab ${activeTab === 'overview' ? 'active' : ''}`}
            id="tab-overview"
            onClick={() => setActiveTab('overview')}
          >
            Overview
          </button>
          <button
            className={`inspector-tab ${activeTab === 'engine' ? 'active' : ''}`}
            id="engine-toggle-btn"
            onClick={() => setActiveTab('engine')}
          >
            Engine
          </button>
        </div>
        <button className="icon-action">⋯</button>
      </div>

      <div id="overview-panel" style={{ display: activeTab === 'overview' ? 'block' : 'none' }}>
        <div className="insight-grid">
          <div onClick={() => window.ScidbWorkspace?.toast('Metric drill-down will open in the inspector')}>
            <span className="metric-label">ECO CODE</span>
            <strong>A45</strong>
            <small>Queen's pawn game</small>
          </div>
          <div onClick={() => window.ScidbWorkspace?.toast('Metric drill-down will open in the inspector')}>
            <span className="metric-label">DATABASE</span>
            <strong>2.4M</strong>
            <small>indexed games</small>
          </div>
          <div onClick={() => window.ScidbWorkspace?.toast('Metric drill-down will open in the inspector')}>
            <span className="metric-label">TOP MOVE</span>
            <strong>1. d4</strong>
            <small>52.8% frequency</small>
          </div>
        </div>

        <div className="trend-section">
          <div className="section-heading">
            <div>
              <span className="eyebrow">POPULARITY</span>
              <h3>Opening activity</h3>
            </div>
            <span className="trend-up">↗ 14.2%</span>
          </div>
          <div className="bars">
            <i style={{ height: '34%' }}></i>
            <i style={{ height: '46%' }}></i>
            <i style={{ height: '42%' }}></i>
            <i style={{ height: '64%' }}></i>
            <i style={{ height: '58%' }}></i>
            <i style={{ height: '77%' }}></i>
            <i style={{ height: '69%' }}></i>
            <i style={{ height: '91%' }}></i>
            <i style={{ height: '84%' }}></i>
            <i style={{ height: '100%' }}></i>
          </div>
          <div className="bar-labels">
            <span>2016</span>
            <span>2020</span>
            <span>2025</span>
          </div>
        </div>

        <div id="report-placeholder">
          <div className="placeholder-icon">📊</div>
          <h2>Ready to explore</h2>
          <p>Make a move on the board or load a FEN to unlock the full opening report.</p>
          <p>The report will include:</p>
          <ul>
            <li>📋 Opening identification & ECO classification</li>
            <li>📈 Historical development & Fashion Index</li>
            <li>👑 Pioneers & notable players</li>
            <li>📊 Elo-segmented performance statistics</li>
            <li>🎭 Variation characterization & strategic themes</li>
            <li>🟢 Main lines & critical variations</li>
            <li>♟ Typical piece maneuvers & pawn advances</li>
            <li>🎓 Instructive study games</li>
            <li>⚡ Tactical training positions</li>
            <li>🔀 Transpositions</li>
            <li>📚 Repertoire suggestions</li>
          </ul>
        </div>
        <OpeningReport />
      </div>

      <EngineInspector visible={activeTab === 'engine'} />
    </div>
  );
}