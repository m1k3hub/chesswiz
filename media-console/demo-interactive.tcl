#!/usr/bin/env tclsh
# ======================================================================
# demo-interactive — scripted walkthrough of scidb's interactive video
# (position-keyed media, .scm/.smv + board-follow auto-jump).
#
# Shows the complete flow: a scratch game whose position equals the
# [Interactive] Fen of ~/.chesswiz/media/interactive.scm; landing on
# the position auto-jumps the embedded player to the keyed clip.
#
# Run (unique script name! scidb is single-instance per script path):
#   xvfb-run -a -s "-screen 0 1400x900x24" \
#       ./src/tkchesswiz media-console/demo-interactive.tcl
#
# See docs/SCM_FORMAT_DESIGN.md §1.5 for the manifest grammar.
# ======================================================================

namespace eval ::idemo {}
proc ::idemo::log {msg} { puts "IDEMO: $msg"; flush stdout }
proc ::idemo::safe {tag body} { if {[catch {uplevel 1 $body} e]} { ::idemo::log "ERR/$tag: $e" } }
set ::idpgn {[Event "i"]
[White "s"]
[Black "m"]
[Result "*"]
[FEN "r1bq2k1/ppp2r2/3p1n1b/2PPp1pp/4Pn2/2NNBPR1/PP2B2P/2RQ3K w - - 0 1"]

1... Rfe8 *}

after 2500 { ::idemo::safe game {
	::game::new .application -variant Normal
	catch { ::application::switchTab board }
	wm deiconify .application
	raise .application
	::idemo::log "scratch game loaded"
}}
after 6500 { ::idemo::safe import {
	set rc [catch { ::scidb::game::import 0 $::idpgn } m]
	catch { ::scidb::game::go 0 start }
	::idemo::log "import=$rc fen=[string range [::scidb::game::fen 0] 0 40]"
}}
after 9500 { ::idemo::safe hook {
	::application::media::BoardUpdated 0
	::idemo::log "BoardUpdated(0) dispatch"
}}
after 16000 { ::idemo::safe result {
	set st "?"
	catch { set st $::application::media::Priv(statusbar) }
	set inp "?"
	catch { set inp $::application::media::Priv(inprocess) }
	::idemo::log "RESULT inprocess=$inp status=$st"
	catch { exec import -window root /tmp/scidb-interactive-demo.png }
	::idemo::log "shot /tmp/scidb-interactive-demo.png"
}}
after 19500 { ::idemo::log "DEMO-DONE" }

