import { lazy, Suspense } from 'react';
import Header from './Header';
import DatabaseRail from './DatabaseRail';
import BoardPanel from './BoardPanel';
import ReportPanel from './ReportPanel';
import ShellFallback from './ShellFallback';

// Feature modals are lazy-loaded so they only enter the bundle when first opened.
// This keeps the initial JS payload small while the rarely-used panels stream in on demand.
const DatabaseModal = lazy(() => import('@/features/database/DatabaseModal'));
const GameSwitcherModal = lazy(() => import('@/features/games/GameSwitcherModal'));
const SearchCenterModal = lazy(() => import('@/features/search/SearchCenterModal'));
const OpeningTreeModal = lazy(() => import('@/features/tree/OpeningTreeModal'));
const WorkingSetsModal = lazy(() => import('@/features/working-sets/WorkingSetsModal'));
const IndexBrowserModal = lazy(() => import('@/features/indexes/IndexBrowserModal'));
const RepertoireStudio = lazy(() => import('@/features/repertoire/RepertoireStudio'));
const PlayerCenter = lazy(() => import('@/features/players/PlayerCenter'));
const MaintenanceCenter = lazy(() => import('@/features/maintenance/MaintenanceCenter'));
const CrosstableModal = lazy(() => import('@/features/crosstable/CrosstableModal'));
const GameEditorModal = lazy(() => import('@/features/games/GameEditorModal'));
const TacticsModal = lazy(() => import('@/features/tactics/TacticsModal'));
const GameViewerModal = lazy(() => import('@/features/games/GameViewerModal'));
const JobCenter = lazy(() => import('@/features/jobs/JobCenter'));
const PlayCenter = lazy(() => import('@/features/play/PlayCenter'));

/**
 * Shell — full workspace layout rendered by React.
 *
 * Header, DatabaseRail, BoardPanel, and ReportPanel are eagerly loaded because
 * they are visible on first paint. All feature modals are lazy-loaded behind
 * Suspense so they only consume bundle budget when first opened.
 */
export default function Shell() {
  return (
    <>
      <Header />
      <div id="main-layout">
        <DatabaseRail />
        <BoardPanel />
        <ReportPanel />
      </div>
      <Suspense fallback={<ShellFallback />}>
        <DatabaseModal />
        <GameSwitcherModal />
        <SearchCenterModal />
        <OpeningTreeModal />
        <WorkingSetsModal />
        <IndexBrowserModal />
        <RepertoireStudio />
        <PlayerCenter />
        <MaintenanceCenter />
        <CrosstableModal />
        <GameEditorModal />
        <TacticsModal />
        <GameViewerModal />
        <JobCenter />
        <PlayCenter />
      </Suspense>
    </>
  );
}