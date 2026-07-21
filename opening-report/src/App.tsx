import Shell from './components/Shell';

/**
 * App — React entry point for the scidb-beta web workspace.
 *
 * The Shell component now renders the full workspace layout, replacing the
 * static markup previously in index.html. Legacy vanilla JS modules still
 * drive the board, report, engine inspector, search center, game switcher, and
 * opening tree; they attach to the DOM ids exported by Shell.
 */
export default function App() {
  return <Shell />;
}
