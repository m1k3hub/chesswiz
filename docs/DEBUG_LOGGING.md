# Capturing VM bugs

Set `CHESSWIZ_LOG=debug` (or `trace`) before starting Chesswiz. Both currently
capture the same diagnostics; unset it to disable all logging hooks. Reproduce
the bug and collect `debug.log` and `debug.log.1`:

| Platform | Default debug log |
| --- | --- |
| Linux | `~/.chesswiz/log/debug.log` |
| Windows | `%APPDATA%\Chesswiz\log\debug.log` |
| macOS | `~/.chesswiz/log/debug.log` |

The actual directory follows `::scidb::dir::user`: `SCIDB_USERDIR` overrides it,
and Unix installation names can change `.chesswiz`. Logs append across sessions;
at 5 MiB the next write replaces `debug.log.1`. Each session begins with an ISO
UTC wall time; subsequent lines use milliseconds since logger startup. Newlines
and backslashes in messages are escaped so each record occupies one line.

Categories: `startup` records platform, Tcl/Tk, screen/scaling, paths, app version
and git SHA; `bgerror` records background errors and full Tcl errorInfo; `engine`
records UCI/WinBoard input (`<`), output (`>`), errors (`!`) and fatal errors (`@`),
including engine probing; `twm` records pane zoom/restore, docking, undocking and
closing; `dialog` records Tcl/Tk toplevel creation and time to first Map, including
custom dialog classes. Native OS dialogs do not expose these Tk events.
`slow` is omitted: Tcl has no cheap general hook for timing every event callback.

Other diagnostic switches:

- `SCIDB_AI_DEBUG=1`: enables assistant developer tools (also `--ai-debug`).
- `SCIDB_PGN_TRACE`: when present, prints PGN handling diagnostics to stdout.
- `SCIDB_ERROR_LOG`: overrides the assistant error log path; an empty value disables
  it. Default: `<user dir>/log/errors.log`, with an `errors.log.1` backup.

Stderr normally goes to the launching terminal on Linux. Windows GUI launches
also capture stdout/stderr in `%LOCALAPPDATA%\Chesswiz\chesswiz.log`. The macOS
bundle launcher captures stderr in `~/Library/Logs/Chesswiz/stderr.log` (stdout
in `stdout.log`; `CW_LOGDIR` overrides the directory). These captures are separate
from `CHESSWIZ_LOG`. Engine logging can include position data and engine commands.
