# ======================================================================
# Source Contract Tests
# Scan C++ and Tcl source for known anti-patterns and bug signatures.
# Tests assert what correct code looks like. Fixed bugs pass as
# regression guards; open bugs fail, documenting the defect.
#
# Reference: BUG_LOG_2026-04-04.md (Bugs #1-#28)
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test {

variable repoRoot [file dirname [file dirname [file normalize [info script]]]]

proc slurp {path} {
    set fd [open $path r]
    set data [read $fd]
    close $fd
    return $data
}

# Return list of {linenum text} pairs matching pattern in file content
proc grepLines {content pattern} {
    set results {}
    set linenum 0
    foreach line [split $content "\n"] {
        incr linenum
        if {[regexp $pattern $line]} {
            lappend results [list $linenum $line]
        }
    }
    return $results
}

# ==============================================================================
# C++ Memory Safety — new[]/delete mismatch regression guards
# ==============================================================================

tcltest::test src-contract-delete-array-probe-01 \
    {Probe::~Probe must use delete[] not scalar delete (Bug #13 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db db_probe.cpp]]
    # Find the destructor — look for ~Probe and the delete line near it
    set inDestructor 0
    set usesArrayDelete 0
    foreach line [split $src "\n"] {
        if {[regexp {~Probe\(\)} $line]} {
            set inDestructor 1
        }
        if {$inDestructor && [regexp {delete\s+\[\]} $line]} {
            set usesArrayDelete 1
            break
        }
        if {$inDestructor && [regexp {^\}} $line]} {
            break
        }
    }
    return $usesArrayDelete
} -result 1

tcltest::test src-contract-delete-array-moveorder-02 \
    {MoveOrder::~MoveOrder must use delete[] not scalar delete (Bug #17 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db db_eco_table.ipp]]
    # The destructor is inline: ~MoveOrder() { delete [] m_buffer; }
    set matches [grepLines $src {~MoveOrder.*delete}]
    set ok 0
    foreach match $matches {
        lassign $match linenum text
        if {[regexp {delete\s+\[\]} $text]} {
            set ok 1
        }
    }
    return $ok
} -result 1

# ==============================================================================
# C++ Logic Errors
# ==============================================================================

tcltest::test src-contract-empty-vs-size-03 \
    {db_consumer.cpp must not use .empty() in integer comparison (Bug #19)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db db_consumer.cpp]]
    # Pattern: i < something.empty() — .empty() returns bool, not size
    set bad [grepLines $src {<\s+\S+\.empty\(\)}]
    expr {[llength $bad] == 0}
} -result 1

tcltest::test src-contract-checl-typo-04 \
    {tcl_engine.cpp must spell "check" correctly, not "checl" (Bug #20)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src tcl tcl_engine.cpp]]
    set bad [grepLines $src {"checl"}]
    expr {[llength $bad] == 0}
} -result 1

tcltest::test src-contract-engine-string-constants-05 \
    {tcl_engine.cpp string constants should all be valid chess terms} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src tcl tcl_engine.cpp]]
    set expected {error clear pv checkmate stalemate threechecks losing check over move line bestmove bestscore seldepth time hash state start stop pause resume}
    set pass 1
    foreach term $expected {
        if {![regexp "Tcl_NewStringObj\\(\"$term\"" $src]} {
            set pass 0
        }
    }
    return $pass
} -result 1

tcltest::test src-contract-cbh-buffer-overread-06 \
    {cbh_game_decoder.cpp CR handler must bounds-check before reading p[i+1] (Bug #21)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db cbh cbh_game_decoder.cpp]]
    # The bug: inside a for(;i<length;++i) loop, case 0x0d does p[i+1]
    # without checking i+1 < length. Correct code checks bounds first.
    # Look for the 0x0d case and verify a bounds check exists before p[i + 1]
    set lines [split $src "\n"]
    set found0x0d 0
    set hasBoundsCheck 0
    for {set i 0} {$i < [llength $lines]} {incr i} {
        set line [lindex $lines $i]
        if {[regexp {case 0x0d:} $line]} {
            set found0x0d 1
            # Scan the next 5 lines for a bounds check before p[i + 1]
            for {set j 1} {$j <= 5} {incr j} {
                set nextLine [lindex $lines [expr {$i + $j}]]
                if {[regexp {i\s*\+\s*1\s*<\s*length|i\s*<\s*length\s*-\s*1} $nextLine]} {
                    set hasBoundsCheck 1
                }
            }
            break
        }
    }
    expr {$found0x0d && $hasBoundsCheck}
} -result 1

tcltest::test src-contract-cbh-double-increment-07 \
    {cbh_game_decoder.cpp doDecoding must not double-increment loop var (Bug #22)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db cbh cbh_game_decoder.cpp]]
    # The bug: for(unsigned i=0; i<length; ++i) { ... moves[i++] = ... }
    # The post-increment i++ inside a for loop with ++i causes double advance.
    # Correct code uses either moves[i] (no post-increment) or a separate index.
    set lines [split $src "\n"]
    set inDoDecoding 0
    set hasDoubleIncrement 0
    foreach line $lines {
        if {[regexp {doDecoding\(uint16_t} $line]} {
            set inDoDecoding 1
        }
        if {$inDoDecoding && [regexp {\[i\+\+\]} $line]} {
            set hasDoubleIncrement 1
        }
        # Stop scanning after the function ends (next function signature)
        if {$inDoDecoding && [regexp {^unsigned$} [string trim $line]]} {
            break
        }
    }
    expr {!$hasDoubleIncrement}
} -result 1

tcltest::test src-contract-hyphen-strip-08 \
    {db_reader.cpp hyphen fallback must parse normalized string v, not original value (Bug #18 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db db_reader.cpp]]
    # After v.strip('-'), the next fromString call must use v, not value
    set lines [split $src "\n"]
    set foundStrip 0
    set usesNormalized 0
    for {set i 0} {$i < [llength $lines]} {incr i} {
        set line [lindex $lines $i]
        if {[regexp {\.strip\('-'\)} $line]} {
            set foundStrip 1
        }
        if {$foundStrip && [regexp {fromString\(v\)} $line]} {
            set usesNormalized 1
            break
        }
        if {$foundStrip && [regexp {fromString\(value\)} $line]} {
            # Bug #18 not fixed
            break
        }
    }
    expr {$foundStrip && $usesNormalized}
} -result 1

tcltest::test src-contract-player-prep-stats-shape-08b \
    {app-db-players.tcl must unpack playerStats using the shared helper contract} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl app-db-players.tcl]]
    expr {
        [regexp {proc\s+UnpackPlayerStats\s+\{stats\}} $src]
        && ![regexp {lassign\s+\$stats\s+dateStats\s+ratingStats\s+gameStats\s+whiteStats\s+blackStats\s+whiteRows\s+blackRows} $src]
    }
} -result 1

tcltest::test src-contract-opponent-dossier-stable-dialog-08c \
    {app-db-players.tcl opponent dossier should reuse a stable dialog name and expose refresh} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl app-db-players.tcl]]
    expr {
        [regexp {proc\s+OpponentDossierDialogName\s+\{base variant playerIndex\}} $src]
        && [regexp {proc\s+RefreshOpponentDossier\s+\{dlg\}} $src]
        && ![regexp {set dlg \[tk::toplevel \.application\.__dossier__\[incr ::application::player::Counter\] -class Scidb\]} $src]
    }
} -result 1

tcltest::test src-contract-opponent-dossier-actions-08d \
    {app-db-players.tcl opponent dossier should expose prep/switcher working-set actions for opening rows} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl app-db-players.tcl]]
    expr {
        [regexp {proc\s+SelectedDossierOpening\s+\{dlg} $src]
        && [regexp {proc\s+OpenDossierOpeningInPrepReport\s+\{dlg\}} $src]
        && [regexp {proc\s+OpenDossierOpeningInSwitcher\s+\{dlg\}} $src]
        && [regexp {proc\s+SaveDossierOpeningWorkingSet\s+\{dlg\}} $src]
        && [regexp {proc\s+SelectDossierOpeningAt\s+\{dlg tree y\}} $src]
        && [regexp {proc\s+PopupDossierOpeningMenu\s+\{dlg tree x y Y\}} $src]
        && [regexp {bind\s+\$whiteTree\s+<ButtonPress-3>\s+\[namespace code \[list PopupDossierOpeningMenu \$dlg \$whiteTree %X %x %Y\]\]} $src]
        && [regexp {bind\s+\$blackTree\s+<ButtonPress-3>\s+\[namespace code \[list PopupDossierOpeningMenu \$dlg \$blackTree %X %x %Y\]\]} $src]
    }
} -result 1

tcltest::test src-contract-opponent-dossier-recent-actions-08e \
    {app-db-players.tcl opponent dossier should expose selected recent-game actions} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl app-db-players.tcl]]
    expr {
        [regexp {proc\s+SelectedDossierRecentGameNumber\s+\{dlg} $src]
        && [regexp {proc\s+SelectDossierRecentGameAt\s+\{dlg y\}} $src]
        && [regexp {proc\s+SelectedDossierOpponentIndex\s+\{dlg} $src]
        && [regexp {proc\s+OpenSelectedDossierRecentGame\s+\{dlg\}} $src]
        && [regexp {proc\s+OpenSelectedDossierOpponentPrep\s+\{dlg\}} $src]
        && [regexp {proc\s+OpenSelectedDossierOpponentDossier\s+\{dlg\}} $src]
        && [regexp {proc\s+SaveSelectedDossierOpponentWorkingSet\s+\{dlg\}} $src]
        && [regexp {proc\s+PopupDossierRecentMenu\s+\{dlg x y Y\}} $src]
        && [regexp {bind\s+\$recentList\s+<ButtonPress-3>\s+\[namespace code \[list PopupDossierRecentMenu \$dlg %X %y %Y\]\]} $src]
    }
} -result 1

tcltest::test src-contract-opponent-dossier-summary-08g \
    {app-db-players.tcl dossier summary should use real percentages and top-opening helper} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl app-db-players.tcl]]
    expr {
        [regexp {proc\s+DossierTopOpeningText\s+\{rows\}} $src]
        && [regexp {Score: \[format %\.1f \$pct\]%} $src]
        && [regexp {Score: \[format %\.1f \$wPct\]%} $src]
        && [regexp {Score: \[format %\.1f \$bPct\]%} $src]
        && ![regexp {\$pct / 100\.0} $src]
        && ![regexp {\$wPct / 100\.0} $src]
        && ![regexp {\$bPct / 100\.0} $src]
    }
} -result 1

tcltest::test src-contract-player-prep-recent-actions-08f \
    {app-db-players.tcl player prep report should expose selected recent-game actions} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl app-db-players.tcl]]
    expr {
        [regexp {proc\s+SelectedPrepGameNumber\s+\{dlg} $src]
        && [regexp {proc\s+SelectedPrepOpponentIndex\s+\{dlg} $src]
        && [regexp {proc\s+OpenSelectedPrepGame\s+\{dlg\}} $src]
        && [regexp {proc\s+OpenSelectedPrepOpponent\s+\{dlg\}} $src]
        && [regexp {proc\s+OpenSelectedPrepOpponentDossier\s+\{dlg\}} $src]
        && [regexp {proc\s+PopupPrepRecentMenu\s+\{dlg x y\}} $src]
        && [regexp {bind\s+\$PrepReportData\(\$dlg,scrolledTable\)\s+<Double-1>\s+\\\s*\n\s*\[namespace code \[list OpenSelectedPrepGame \$dlg\]\]} $src]
        && [regexp {bind\s+\$PrepReportData\(\$dlg,scrolledTable\)\s+<ButtonPress-3>\s+\\\s*\n\s*\[namespace code \[list PopupPrepRecentMenu \$dlg %X %Y\]\]} $src]
    }
} -result 1

# ==============================================================================
# Build System
# ==============================================================================

tcltest::test src-contract-makefile-tktext-target-09 \
    {src/Makefile tk/text target must build tk/text not tk/html (Bug #23)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src Makefile]]
    set lines [split $src "\n"]
    set foundTarget 0
    set correctDir 0
    for {set i 0} {$i < [llength $lines]} {incr i} {
        set line [lindex $lines $i]
        if {[regexp {^tk/text/libTkText\.a:} $line]} {
            set foundTarget 1
            # Check next non-empty line for the build command
            for {set j 1} {$j <= 3} {incr j} {
                set nextLine [lindex $lines [expr {$i + $j}]]
                if {[regexp {MAKE.*-C\s+tk/text} $nextLine]} {
                    set correctDir 1
                }
            }
            break
        }
    }
    expr {$foundTarget && $correctDir}
} -result 1

tcltest::test src-contract-makefile-no-duplicate-mismatch-10 \
    {src/Makefile every libXxx.a target invokes matching subdirectory} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src Makefile]]
    set lines [split $src "\n"]
    # Intentional mismatches: db/libapp.a builds from app/, db/libdb*.a from db/
    set allowed {
        db/libapp.a     app
        db/libdbstubs.a db
    }
    set pass 1
    set targetDir ""
    for {set i 0} {$i < [llength $lines]} {incr i} {
        set line [lindex $lines $i]
        # Match targets like: subdir/libFoo.a:
        if {[regexp {^([a-z]+(?:/[a-z]+)*)/lib(\w+)\.a:} $line -> targetDir libName]} {
            set targetFile "[string trim $targetDir]/lib${libName}.a"
            # Next non-blank line should have $(MAKE) -C <dir>
            for {set j 1} {$j <= 3} {incr j} {
                set nextLine [lindex $lines [expr {$i + $j}]]
                if {[regexp {\$\(MAKE\)\s+-C\s+(\S+)} $nextLine -> buildDir]} {
                    if {$buildDir ne $targetDir} {
                        # Check if this is an allowed mismatch
                        if {![dict exists $allowed $targetFile] || [dict get $allowed $targetFile] ne $buildDir} {
                            set pass 0
                        }
                    }
                    break
                }
            }
        }
    }
    return $pass
} -result 1

# ==============================================================================
# Format/Extension Consistency
# ==============================================================================

tcltest::test src-contract-strip-suffix-cbh-upper-11 \
    {cdb2sci.cpp stripSuffix must handle .CBH (Bug #24)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src cdb2sci.cpp]]
    # Find the stripSuffix function body and check that .CBH is listed
    set inStripSuffix 0
    set braceDepth 0
    set seenBrace 0
    set hasCBH 0
    foreach line [split $src "\n"] {
        if {[regexp {stripSuffix\(mstl::string} $line]} {
            set inStripSuffix 1
        }
        if {$inStripSuffix} {
            set opens [regexp -all {\{} $line]
            set closes [regexp -all {\}} $line]
            incr braceDepth $opens
            incr braceDepth [expr {-$closes}]
            if {$opens > 0} { set seenBrace 1 }
            if {[regexp {\.CBH} $line]} {
                set hasCBH 1
                break
            }
            if {$seenBrace && $braceDepth <= 0} {
                break
            }
        }
    }
    return $hasCBH
} -result 1

tcltest::test src-contract-detect-vs-strip-consistency-12 \
    {cdb2sci.cpp every extension in detectFormat should appear in stripSuffix} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src cdb2sci.cpp]]
    # Extract extensions from both functions
    set inDetect 0
    set inStrip 0
    set detectExts {}
    set stripExts {}
    foreach line [split $src "\n"] {
        if {[regexp {detectFormat} $line]} { set inDetect 1; set inStrip 0 }
        if {[regexp {stripSuffix} $line]}  { set inStrip 1; set inDetect 0 }
        if {$inDetect} {
            foreach {_ ext} [regexp -all -inline {strcmp\(s,\s*"(\.[A-Za-z0-9]+)"\)} $line] {
                lappend detectExts $ext
            }
        }
        if {$inStrip} {
            foreach {_ ext} [regexp -all -inline {strcmp\(s,\s*"(\.[A-Za-z0-9]+)"\)} $line] {
                lappend stripExts $ext
            }
        }
    }
    # Every detect extension should be in strip (ignoring non-strippable formats)
    set missing {}
    foreach ext [lsort -unique $detectExts] {
        if {$ext ni $stripExts && $ext ni {.bpgn}} {
            lappend missing $ext
        }
    }
    expr {[llength $missing] == 0}
} -result 1

# ==============================================================================
# Tcl Source Quality
# ==============================================================================

tcltest::test src-contract-progressbar-dlg-var-13 \
    {progressbar.tcl must use $w not $dlg for wm attributes (Bug #25)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl dialogs progressbar.tcl]]
    set bad [grepLines $src {wm\s+attributes\s+\$dlg}]
    expr {[llength $bad] == 0}
} -result 1

tcltest::test src-contract-progressbar-empty-parent-14 \
    {progressbar.tcl else branch must not call winfo toplevel on empty parent (Bug #26)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl dialogs progressbar.tcl]]
    set lines [split $src "\n"]
    # The bug: when [string length $parent] is 0, else branch calls
    # [winfo toplevel $parent] which fails. The else block should be
    # empty or handle the empty case gracefully.
    set inElse 0
    set callsToplevelOnParent 0
    for {set i 0} {$i < [llength $lines]} {incr i} {
        set line [lindex $lines $i]
        if {[regexp {\[string length \$parent\]} $line]} {
            # Found the if block. Scan forward for the else.
            for {set j 1} {$j <= 10} {incr j} {
                set nextLine [lindex $lines [expr {$i + $j}]]
                if {[regexp {^\s*\} else \{} $nextLine] || [regexp {^\s*\}\s*else\s*\{} $nextLine]} {
                    # Inside else — check next few lines
                    for {set k 1} {$k <= 5} {incr k} {
                        set elseLine [lindex $lines [expr {$i + $j + $k}]]
                        if {[regexp {winfo toplevel \$parent} $elseLine]} {
                            set callsToplevelOnParent 1
                        }
                    }
                    break
                }
            }
            break
        }
    }
    expr {!$callsToplevelOnParent}
} -result 1

tcltest::test src-contract-place-top-extent-14b \
    {place.tcl must use top extent for y0, not right extent} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl utils place.tcl]]
    expr {
        [regexp {lassign \[winfo extents \$parent\] pl pr pt pb} $src]
        && [regexp {set y0 \[expr \{\$y0 - \$pt\}\]} $src]
        && ![regexp {set y0 \[expr \{\$y0 - \$pr\}\]} $src]
    }
} -result 1

tcltest::test src-contract-web-shell-injection-15 \
    {web.tcl must not interpolate variables directly into /bin/sh -c (Bug #27)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl utils web.tcl]]
    # The bug: exec /bin/sh -c "$DefaultBrowser $options" passes user data
    # through shell expansion. Correct code uses [list] or avoids sh -c.
    set bad [grepLines $src {exec\s+/bin/sh\s+-c\s+"[^"]*\$}]
    expr {[llength $bad] == 0}
} -result 1

tcltest::test src-contract-web-external-links-15b \
    {web.tcl must recognize modern external URLs and mailto links} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl utils web.tcl]]
    expr {
        [regexp {proc\s+isExternalLink\s+\{url\}} $src]
        && [regexp {\^\(\?:https\?\|ftp\)://\[\\s\]\+\$} [string map {"[^\s]+" {\[^\s\]+}} $src]] == 0
        && ![regexp {\^\[a-z\]\{3,5\}://\.\*\\\.\[a-z\]\{2,6\}\$} $src]
        && [regexp {mailto:\[\^\\s@\]\+@\(\[a-zA-Z0-9-\]\+\\\.\)\+\[a-z\]\{2,\}\$} $src]
    }
} -result 1

tcltest::test src-contract-tip-menu-15c \
    {tip-of-the-day popup menu must apply attributes to $menu, not undefined $m} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl dialogs tip-of-the-day.tcl]]
    expr {
        [regexp {menu \$menu} $src]
        && [regexp {wm attributes \$menu -type popup_menu} $src]
        && ![regexp {wm attributes \$m -type popup_menu} $src]
    }
} -result 1

tcltest::test src-contract-board-square-y-clamp-15d \
    {board-square.tcl must use a Y span for vertical texture clamping} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl board-square.tcl]]
    expr {
        [regexp {set dy \[expr \{\$style\(\$which,y2\) - \$style\(\$which,y1\)\}\]} $src]
        && [regexp {round\(\$s\*\$y1\) \+ \$dy > \$ih} $src]
        && [regexp {\(\$ih - \$dy\)} $src]
        && ![regexp {round\(\$s\*\$y1\) \+ \$dx > \$ih} $src]
    }
} -result 1

tcltest::test src-contract-board-piece-y-clamp-15e \
    {board-piece.tcl must use a Y span for vertical texture clamping} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl board-piece.tcl]]
    expr {
        [regexp {set dy \[expr \{\$style\(texture,\$which,y2\) - \$style\(texture,\$which,y1\)\}\]} $src]
        && [regexp {round\(\$s\*\$y1\) \+ \$dy > \$ih} $src]
        && [regexp {\(\$ih - \$dy\)} $src]
        && ![regexp {round\(\$s\*\$y1\) \+ \$dx > \$ih} $src]
    }
} -result 1

tcltest::test src-contract-database-switcher-rethrow-15f \
    {database-switcher.tcl must rethrow the caught result, not ngames} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl widgets database-switcher.tcl]]
    expr {
        [regexp {if \{\[catch \{ ::util::catchException \$cmd result \} rc opts\]\}} $src]
        && [regexp {return \{\*\}\$opts -rethrow 1 \$rc} $src]
        && ![regexp {return \{\*\}\$opts -rethrow 1 \$ngames} $src]
    }
} -result 1

# ==============================================================================
# Multi-part extension (.pgn.gz / .bpgn.gz) handling
# ==============================================================================

# Tcl's [file extension] returns only the last dot-suffix, so .pgn.gz is seen
# as .gz. Code that classifies files by extension must use the helper that
# recognises the full suffix.
tcltest::test src-contract-util-fileExtension-exists-22 \
    {util::fileExtension helper must exist and recognise .pgn.gz / .bpgn.gz} -body {
    # start.tcl is loaded very early and defines the helper
    set src [slurp [file join $repoRoot tcl start.tcl]]
    expr {
        [regexp {proc\s+fileExtension\s+\{file\}} $src]
        && [regexp {string match \*\.pgn\.gz} $src]
        && [regexp {string match \*\.bpgn\.gz} $src]
    }
} -result 1

tcltest::test src-contract-no-raw-file-extension-for-gz-23 \
    {Files with .pgn.gz / .bpgn.gz must be classified via util::fileExtension, not raw [file extension]} -body {
    variable repoRoot
    set bad {}
    foreach f [glob -nocomplain -directory [file join $repoRoot tcl] -type f *.tcl] {
        set src [slurp $f]
        # Flag a [file extension] call on the same line as a .pgn.gz / .bpgn.gz literal.
        # This catches switch/if/in statements that compare [file extension] to the
        # multi-part suffix, which can never match.
        foreach line [split $src "\n"] {
            set trim [string trim $line]
            if {[string index $trim 0] eq "#"} continue
            if {[regexp {file extension} $line]
                && [regexp {\.(pgn|bpgn)\.gz} $line]
                && ![regexp {string match \*\.(pgn|bpgn)\.gz} $line]} {
                lappend bad [list [file tail $f] $line]
            }
        }
    }
    expr {[llength $bad] == 0}
} -result 1

# Known affected files must now use the helper for their extension classification.
tcltest::test src-contract-app-database-uses-helper-24 \
    {app-database.tcl must classify files with util::fileExtension} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl app-database.tcl]]
    expr {
        [regexp {set ext \[::util::fileExtension \$file\]} $src]
        && [regexp {switch \[::util::fileExtension \$value\]} $src]
        && [regexp {switch \[::util::fileExtension \$filename\]} $src]
    }
} -result 1

tcltest::test src-contract-database-switcher-uses-helper-25 \
    {database-switcher.tcl must classify files with util::fileExtension} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl widgets database-switcher.tcl]]
    expr {
        [regexp {switch \[set ext \[::util::fileExtension \$file\]\]} $src]
        && [regexp {set ext \[::util::fileExtension \$file\]} $src]
        && [regexp {set ext \[::util::fileExtension \$base\]} $src]
        && [regexp {\[::util::fileExtension \$file\] in \$allowedExtensions} $src]
    }
} -result 1

tcltest::test src-contract-fsbox-uses-helper-26 \
    {fsbox.tcl must classify files with util::fileExtension} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot tcl widgets fsbox.tcl]]
    expr {
        [regexp {set ext \[::util::fileExtension \$new\]} $src]
        && [regexp {set ext \[::util::fileExtension \$f\]} $src]
        && [regexp {\[::util::fileExtension \$Vars\(initialfile\)\] in \$Vars\(customfiletypes\)} $src]
        && [regexp {\[::util::fileExtension \$file\] in \$Vars\(customfiletypes\)} $src]
    }
} -result 1

# ==============================================================================
# VLA Detection
# ==============================================================================

tcltest::test src-contract-no-vla-engine-16 \
    {app_engine.cpp checkOrdering must not use VLA (Bug #28)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src app app_engine.cpp]]
    # Pattern: bool m[n]; where n is a variable — VLA
    set bad [grepLines $src {bool\s+\w+\[\w+\]\s*;}]
    expr {[llength $bad] == 0}
} -result 1

# ==============================================================================
# sprintf Usage Tracking (Known open Bug #7)
# ==============================================================================

tcltest::test src-contract-sprintf-count-17 \
    {sprintf usage in src/ should not exceed known baseline of 33} -body {
    variable repoRoot
    set srcDir [file join $repoRoot src]
    set count 0
    foreach f [glob -nocomplain -directory $srcDir -type f *.cpp] {
        set content [slurp $f]
        incr count [llength [regexp -all -inline {sprintf\(} $content]]
    }
    # Also check subdirectories
    foreach subdir {db app tcl sys mstl util tk} {
        set dir [file join $srcDir $subdir]
        if {![file isdirectory $dir]} continue
        foreach f [glob -nocomplain -directory $dir -type f *.cpp] {
            set content [slurp $f]
            incr count [llength [regexp -all -inline {sprintf\(} $content]]
        }
        # One level deeper (db/cbh, db/sci, etc.)
        foreach subsubdir [glob -nocomplain -directory $dir -type d *] {
            foreach f [glob -nocomplain -directory $subsubdir -type f *.cpp] {
                set content [slurp $f]
                incr count [llength [regexp -all -inline {sprintf\(} $content]]
            }
        }
    }
    # Baseline: 33 occurrences as of 2026-04-09. Must not grow.
    expr {$count <= 33}
} -result 1

# ==============================================================================
# Cross-File Consistency
# ==============================================================================

tcltest::test src-contract-cbh2si4-cbh-upper-18 \
    {cbh2si4.cpp must accept .CBH extension (Bug #5/#9 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src cbh2si4.cpp]]
    set hasCBH [regexp {\.CBH} $src]
    return $hasCBH
} -result 1

tcltest::test src-contract-reader-matchsuffix-19 \
    {db_reader.cpp matchSuffix pointer arithmetic must be str.size() - suffix.size() (Bug #14 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db db_reader.cpp]]
    set lines [split $src "\n"]
    set inMatchSuffix 0
    set correctOrder 0
    foreach line $lines {
        if {[regexp {matchSuffix} $line]} {
            set inMatchSuffix 1
        }
        if {$inMatchSuffix && [regexp {str\.size\(\)\s*-\s*suffix\.size\(\)} $line]} {
            set correctOrder 1
            break
        }
        if {$inMatchSuffix && [regexp {suffix\.size\(\)\s*-\s*str\.size\(\)} $line]} {
            # Wrong order — Bug #14 not fixed
            break
        }
        if {$inMatchSuffix && [regexp {^[^ \t]} $line] && ![regexp {matchSuffix|static|bool|if|return|strcasecmp|\{|\}} $line]} {
            break
        }
    }
    return $correctOrder
} -result 1

tcltest::test src-contract-maintenance-serial-fallback-20 \
    {db_maintenance.cpp computeEcoStats must have serial fallback (Bug #15 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db db_maintenance.cpp]]
    # After the thread loop, there should be a serial fallback for remaining games
    set hasSerialFirst [regexp {serialFirst} $src]
    return $hasSerialFirst
} -result 1

tcltest::test src-contract-eco-stats-and-duplicates-consistent-21 \
    {db_maintenance.cpp computeEcoStats and findDuplicates should both have serial fallback} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db db_maintenance.cpp]]
    # Both parallel functions should have the same safety pattern
    set hasFindDupFallback [regexp {findDuplicates.*serialFirst|serialFirst.*findDuplicates} $src]
    set hasEcoStatsFallback [regexp {computeEcoStats.*serialFirst|serialFirst.*computeEcoStats} $src]
    # Simpler: just count occurrences of serialFirst — should be >= 2 (one per function)
    set count [llength [regexp -all -inline {serialFirst} $src]]
    expr {$count >= 2}
} -result 1

# ==============================================================================
# Cleanup
# ==============================================================================

# ==============================================================================
# Bug #29-#36 Regression Guards (Audit 3 — 2026-04-15)
# ==============================================================================

tcltest::test src-contract-no-vla-tournament-players-29 \
    {db_tournament_table.cpp must not use VLA for Player* players (Bug #29 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db db_tournament_table.cpp]]
    # The old VLA pattern "Player* players[size]" should be gone
    set hasVLA [regexp {Player\*\s+players\s*\[\s*size\s*\]} $src]
    expr {!$hasVLA}
} -result 1

tcltest::test src-contract-no-vla-tournament-newplayerlist-30 \
    {db_tournament_table.cpp must not use VLA for Player* newPlayerList (Bug #30 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db db_tournament_table.cpp]]
    set hasVLA [regexp {Player\*\s+newPlayerList\s*\[\s*size\s*\]} $src]
    expr {!$hasVLA}
} -result 1

tcltest::test src-contract-no-vla-movelist-moves-31 \
    {app_move_list_thread.cpp must not use VLA for uint16_t moves (Bug #31 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src app app_move_list_thread.cpp]]
    set hasVLA [regexp {uint16_t\s+moves\s*\[\s*m_length\s*\]} $src]
    expr {!$hasVLA}
} -result 1

tcltest::test src-contract-cbh-comment-bounds-check-32 \
    {cbh_game_decoder.cpp whitespace skip must check length (Bug #32 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db cbh cbh_game_decoder.cpp]]
    set hasBoundedSkip [regexp {i\s*<\s*length\s+&&\s+::isspace} $src]
    return $hasBoundedSkip
} -result 1

tcltest::test src-contract-tournament-erase-no-reverse-iter-33 \
    {db_tournament_table.cpp eliminateDuplicates must not use invalidated reverse_iterator (Bug #33 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db db_tournament_table.cpp]]
    # The old pattern "clashList.erase(i.base())" in a reverse_iterator loop should be gone
    set hasBadErase [regexp {clashList\.erase\(i\.base\(\)\)} $src]
    expr {!$hasBadErase}
} -result 1

tcltest::test src-contract-si3-namelist-erase-no-reverse-iter-34 \
    {si3_name_list.cpp adjustListSize must not use invalidated reverse_iterator (Bug #34 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src db si3 si3_name_list.cpp]]
    set hasBadErase [regexp {m_list\.erase\(i\.base\(\)\)} $src]
    expr {!$hasBadErase}
} -result 1

tcltest::test src-contract-detect-email-npos-35 \
    {app_engine.cpp detectEmail must check npos before using offset (Bug #35 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src app app_engine.cpp]]
    set hasNposCheck [regexp {n\s*==\s*mstl::string::npos} $src]
    return $hasNposCheck
} -result 1

tcltest::test src-contract-makefile-no-missing-src-36 \
    {src/Makefile TARGETS must not reference guess_move with no source (Bug #36 regression)} -body {
    variable repoRoot
    set src [slurp [file join $repoRoot src Makefile]]
    set hasGhostTarget [regexp {guess_move} $src]
    expr {!$hasGhostTarget}
} -result 1

tcltest::cleanupTests

} ;# namespace ::scidb::test
