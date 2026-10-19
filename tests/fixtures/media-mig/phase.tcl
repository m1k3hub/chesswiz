# ======================================================================
# VAL-MED-010 startup probe: one fresh app process per phase.
#
# Each phase reads the fixture options file in its own isolated HOME, so the
# real startup path (twm::load -> RemoveLegacyMedia) runs exactly as it does
# after an upgrade. The parent test (tests/test_app_media_fold.tcl) drives the
# phases and checks the lines prefixed "MIG" on stdout.
#
#   phase 1  seed a pre-fold saved layout containing the Media pane and clear
#            the migration marker, then save the options file.
#   phase 2  first start after the upgrade: Media must be gone, the marker set
#            and the other panes intact; then reopen Media from the menu and
#            save the layout.
#   phase 3  restart: the marker keeps the reopened Media pane, no migration.
#
# Environment: MIG_PHASE, MIG_ROOT (repository root).
# ======================================================================

set argv {--single-process}
set argc 1
set ::env(SCIDB_AI_TRIAGE) 0
set ::env(SCIDB_AI_CLASSIFIER) off
set root $::env(MIG_ROOT)
source -encoding utf-8 [file join $root tcl chesswiz]
set ::scidb::dir::setup 0
set ::tips::Options(mode) neverShow

proc bgerror {message} { puts stderr $::errorInfo; exit 1 }

proc migOut {args} { puts "MIG [join $args { }]"; flush stdout }

after 2000 {
    set twm [::application::twm board]
    .application.nb select .application.nb.board
    update
    switch -- $::env(MIG_PHASE) {
        invalid-undock {
            set rc [catch {$twm undock media}]
            migOut invalid-undock rejected $rc board [$twm isdocked board]
        }
        float-save {
            if {![$twm isdocked media]} {::application::twm::ChangeState $twm media; update}
            $twm undock [$twm leaf media]
            update idletasks
            migOut floated [llength [$twm floats]]
            if {![::application::twm::WriteLayout $twm board TestNamed normal]} {error "float save failed"}
            set ::application::twm::Options(board:layout:name) TestNamed
            ::options::startTransaction
            ::options::saveOptionsFile
            ::options::endTransaction
            migOut float-saved docked [$twm isdocked media] floats [llength [$twm floats]]
        }
        corrupt-seed {
            set f [::application::twm::makeFilename board normal TestCorrupt]
            file mkdir [file dirname $f]
            set ch [open $f w]
            puts $ch "::application::twm::setup normal board \{"
            close $ch
            set ::application::twm::Options(board:layout:name) TestCorrupt
            ::options::startTransaction
            ::options::saveOptionsFile
            ::options::endTransaction
        }
        corrupt-check {
            set f [::application::twm::makeFilename board normal TestCorrupt]
            migOut corrupt name [list $::application::twm::Options(board:layout:name)] bad [file exists ${f}.bad] board [$twm isdocked board]
        }
        1 {
            if {[$twm isdocked media]} { ::application::twm::ChangeState $twm media; update }
            set base [::application::twm::inspectLayout $twm]
            set prefold [string map {{frame tree} {frame media {-width 400 -height 300 -minwidth 250 -minheight 200 -expand y} frame tree}} $base]
            set ::application::twm::Options(board:layout:list:normal) $prefold
            
            # Support named layout testing (VAL-MED-010B)
            if {[info exists ::env(MIG_NAMED_TEST)] && $::env(MIG_NAMED_TEST) eq "1"} {
                set ::application::twm::Options(board:layout:name) TestNamed
                # Write the named .layout file
                set nameFile [::application::twm::makeFilename board normal TestNamed]
                file mkdir [file dirname $nameFile]
                set fh [open $nameFile w]
                puts $fh "::application::twm::setup normal board {$prefold}"
                close $fh
            } else {
                set ::application::twm::Options(board:layout:name) ""
            }
            
            array unset ::application::twm::Options board:layout:media:folded
            ::options::startTransaction
            ::options::saveOptionsFile
            ::options::endTransaction
            migOut P1 prefold [regexp {frame media} $prefold] \
                marker [info exists ::application::twm::Options(board:layout:media:folded)] \
                name $::application::twm::Options(board:layout:name) \
                leaves [lsort [$twm leaves]]
        }
        2 {
            set after [::application::twm::inspectLayout $twm]
            migOut P2 media [regexp {frame media} $after] \
                marker [info exists ::application::twm::Options(board:layout:media:folded)] \
                name $::application::twm::Options(board:layout:name) \
                leaves [lsort [$twm leaves]] \
                tree [$twm isdocked tree] analysis [$twm isdocked analysis:1] board [$twm isdocked board] \
                editor [$twm isdocked editor] games [$twm isdocked games] dbgames [$twm isdocked dbgames]
            
            # Check if named .layout file was rewritten (for named test)
            if {[info exists ::env(MIG_NAMED_TEST)] && $::env(MIG_NAMED_TEST) eq "1"} {
                set nameFile [::application::twm::makeFilename board normal TestNamed]
                if {[file exists $nameFile]} {
                    set fh [open $nameFile r]
                    set content [read $fh]
                    close $fh
                    migOut P2 namedFileHasMedia [regexp {frame media} $content]
                } else {
                    migOut P2 namedFileExists 0
                }
            }
            
            # reopen the Media library from the pane menu and save the layout
            ::application::twm::ChangeState $twm media
            update
            migOut P2 reopened [$twm isdocked media] mapped [winfo ismapped .application.mediaBackend]
            set ::application::twm::Options(board:layout:list:normal) [::application::twm::inspectLayout $twm]
            if {[info exists ::env(MIG_NAMED_TEST)] && $::env(MIG_NAMED_TEST)} {
                if {![::application::twm::WriteLayout $twm board TestNamed normal]} {error "named save failed"}
            }
            ::options::startTransaction
            ::options::saveOptionsFile
            ::options::endTransaction
        }
        3 {
            set after [::application::twm::inspectLayout $twm]
            migOut P3 media [regexp {frame media} $after] docked [$twm isdocked media] \
                marker [info exists ::application::twm::Options(board:layout:media:folded)] \
                name $::application::twm::Options(board:layout:name) \
                leaves [lsort [$twm leaves]]
        }
    }
    exit 0
}
vwait migNever
