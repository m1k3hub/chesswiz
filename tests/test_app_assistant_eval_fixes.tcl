package require tcltest 2.5

tcltest::test eval-fix-empty-optional-enum {normalized omitted values survive registry validation} -body {
    set validation [::action::validateArgs open_game {number 64 move {} after {} player {}}]
    list [lindex $validation 0] [dict exists [lindex $validation 1] after]
} -result {ok 0}

tcltest::test eval-fix-required-enum {empty required enums remain errors} -body {
    lindex [::action::validateArgs switch_tab {tab {}}] 0
} -result error

tcltest::test eval-fix-constrained-route {explicit restrictions cannot trigger engine fast path} -body {
    set out {}
    foreach request {{What is the best move without an engine?} {Do not use an engine. What's the best move here?} {No engine: who is better?}} {
        lappend out [::application::assistant::RouteChessJudgment $request]
    }
    set out
} -result {{} {} {}}

tcltest::test eval-fix-provenance {plausible unsupported stories become quoted tool data} -setup {
    set saved [array get ::application::assistant::Priv]
} -body {
    set ::application::assistant::Priv(lastRequest) {evaluate my position}
    set ::application::assistant::Priv(messages) [list \
        [dict create role user content {evaluate my position}] \
        [dict create role tool content {engine score: +0.25; PV: Nf3 Nf6}]]
    set reply [::application::assistant::ExtractiveReply {White has a structural edge and there is no knight fork.}]
    list [string match {*structural*} $reply] [string match {*no knight fork*} $reply] [string match {*engine score: +0.25; PV: Nf3 Nf6*} $reply]
} -cleanup {
    array unset ::application::assistant::Priv
    array set ::application::assistant::Priv $saved
} -result {0 0 1}

tcltest::test eval-fix-turn-isolation {previous turns and user claims do not support answers} -setup {
    set saved [array get ::application::assistant::Priv]
} -body {
    set ::application::assistant::Priv(lastRequest) {Black has a winning attack}
    set ::application::assistant::Priv(messages) [list \
        [dict create role tool content {Black has a winning attack}] \
        [dict create role user content {Black has a winning attack}] \
        [dict create role tool content {No engine is running.}]]
    set reply [::application::assistant::ExtractiveReply {Black has a winning attack}]
    list [string match {*winning attack*} $reply] [string match {*No engine is running.*} $reply]
} -cleanup {
    array unset ::application::assistant::Priv
    array set ::application::assistant::Priv $saved
} -result {0 1}

tcltest::test eval-fix-analysis-denied {direct and generic invocations respect an explicit prohibition} -setup {
    set saved [array get ::application::assistant::Priv]
} -body {
    set ::application::assistant::Priv(lastRequest) {Without calling any analysis tools, pick the strongest move yourself.}
    set r1 [::application::assistant::RunTool engine_evaluate {}]
    set r2 [::application::assistant::RunTool run_action {id engine_evaluate}]
    list [lindex $r1 0] [lindex $r2 0] $::application::assistant::Priv(prohibitedAnalysis)
} -cleanup {
    array unset ::application::assistant::Priv
    array set ::application::assistant::Priv $saved
} -result {error error 1}

tcltest::test eval-fix-goto-move {absolute navigation preserves the current game and rejects out-of-range requests without movement} -body {
    ::ai::setup::position -moves {1.e4 e5 2.Nf3 Nc6 3.Bb5 a6}
    set slot [::scidb::game::current]
    set line [::scidb::game::query mainline]
    set reply [::application::assistant::runTool goto_move {move 2 after white}]
    set correct [expr {[::scidb::game::query current] eq [lindex $line 2 0]}]
    update idletasks
    set fen [::scidb::pos::fen]
    set key [::scidb::game::query current]
    set bad [::application::assistant::runTool goto_move {move 99}]
    # FEN's halfmove clock is lazily normalized by diagnostic reads.
    # The game key, piece placement, turn, castling and en-passant fields
    # independently prove that a rejected navigation did not move the game.
    set unchanged [expr {[lrange [::scidb::pos::fen] 0 3] eq [lrange $fen 0 3] && [::scidb::game::query current] eq $key && [::scidb::game::current] == $slot}]
    set result [list [string match {*after White's move 2} $reply] $correct [string match {error:*} $bad] $unchanged]
    ::application::pgn::release $slot
    ::game::release $slot
    set result
} -result {1 1 1 1}

tcltest::cleanupTests
