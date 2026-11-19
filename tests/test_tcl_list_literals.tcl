# ======================================================================
# List-literal guard
#
# A '#' inside a braced word is data, not a comment.  When such a word
# is an `array set` or `dict create` literal the words become list
# elements, so a comment line makes the list odd (or, worse, adds two
# elements and silently changes the data).  The merged script used to
# delete indented comment lines with a GNU-only sed expression; BSD sed
# kept them and the macOS application died in `array set PaneOptions`.
#
# This guard (a) parses every Tcl source as written, without any comment
# stripping, (b) checks the `array set`/`dict create` literals and
# (c) builds the merged script with comment stripping disabled and
# sources it.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::listlit {
    variable repoRoot [file dirname [file dirname [file normalize [info script]]]]
    variable tclDir [file join $repoRoot tcl]
}

# ----------------------------------------------------------------------
# A Tcl lexer good enough to find command words.  It follows Tcl's
# brace/quote/bracket/backslash rules, so a '#' inside braces is kept
# as data and a '#' at the start of a command is skipped as a comment.
# Each word is {type raw start end bodyStart bodyEnd}; type is braced,
# quoted, bare or concat.
# ----------------------------------------------------------------------
proc ::scidb::test::listlit::skipBrace {t i end} {
    incr i
    set depth 1
    while {$i < $end} {
        set c [string index $t $i]
        if {$c eq "\\"} { incr i 2; continue }
        if {$c eq "\{"} { incr depth; incr i; continue }
        if {$c eq "\}"} {
            incr depth -1
            incr i
            if {$depth == 0} { return $i }
            continue
        }
        incr i
    }
    return $i
}

proc ::scidb::test::listlit::skipQuote {t i end} {
    incr i
    while {$i < $end} {
        set c [string index $t $i]
        if {$c eq "\\"} { incr i 2; continue }
        if {$c eq "\["} { set i [::scidb::test::listlit::skipBracket $t $i $end]; continue }
        if {$c eq "\""} { return [expr {$i + 1}] }
        incr i
    }
    return $i
}

proc ::scidb::test::listlit::skipBracket {t i end} {
    incr i
    set depth 1
    while {$i < $end} {
        set c [string index $t $i]
        if {$c eq "\\"} { incr i 2; continue }
        if {$c eq "\{"} { set i [::scidb::test::listlit::skipBrace $t $i $end]; continue }
        if {$c eq "\""} { set i [::scidb::test::listlit::skipQuote $t $i $end]; continue }
        if {$c eq "\["} { incr depth; incr i; continue }
        if {$c eq "\]"} {
            incr depth -1
            incr i
            if {$depth == 0} { return $i }
            continue
        }
        incr i
    }
    return $i
}

proc ::scidb::test::listlit::parseScript {t start end} {
    set cmds {}
    set brackets {}
    set i $start
    while {$i < $end} {
        # command separators and whitespace
        while {$i < $end} {
            set c [string index $t $i]
            if {$c eq "\\" && [string index $t [expr {$i + 1}]] eq "\n"} { incr i 2; continue }
            if {$c in {" " "\t" "\r" "\n" ";"}} { incr i; continue }
            break
        }
        if {$i >= $end} break
        if {[string index $t $i] eq "#"} {
            while {$i < $end} {
                if {[string index $t $i] eq "\\" && [string index $t [expr {$i + 1}]] eq "\n"} { incr i 2; continue }
                if {[string index $t $i] eq "\n"} break
                incr i
            }
            continue
        }
        set cstart $i
        set words {}
        while {$i < $end} {
            while {$i < $end} {
                set c [string index $t $i]
                if {$c eq "\\" && [string index $t [expr {$i + 1}]] eq "\n"} { incr i 2; continue }
                if {$c in {" " "\t" "\r"}} { incr i; continue }
                break
            }
            if {$i >= $end} break
            set c [string index $t $i]
            if {$c in {"\n" ";"}} break
            set wstart $i
            set segs {}
            while {$i < $end} {
                set c [string index $t $i]
                if {$c in {" " "\t" "\r" "\n" ";"}} break
                if {$c eq "\\" && [string index $t [expr {$i + 1}]] eq "\n"} { incr i 2; continue }
                if {$c eq "\{"} {
                    set bs [expr {$i + 1}]
                    set j [::scidb::test::listlit::skipBrace $t $i $end]
                    lappend segs [list braced $bs [expr {$j - 1}]]
                    set i $j
                } elseif {$c eq "\""} {
                    set j [::scidb::test::listlit::skipQuote $t $i $end]
                    lappend segs [list quoted -1 -1]
                    set i $j
                } elseif {$c eq "\["} {
                    set j [::scidb::test::listlit::skipBracket $t $i $end]
                    lappend brackets [list [expr {$i + 1}] [expr {$j - 1}]]
                    lappend segs [list bare -1 -1]
                    set i $j
                } else {
                    while {$i < $end} {
                        set d [string index $t $i]
                        if {$d in {" " "\t" "\r" "\n" ";"}} break
                        if {$d eq "\\"} { incr i 2; continue }
                        if {$d eq "\["} {
                            set j [::scidb::test::listlit::skipBracket $t $i $end]
                            lappend brackets [list [expr {$i + 1}] [expr {$j - 1}]]
                            set i $j
                            continue
                        }
                        incr i
                    }
                    lappend segs [list bare -1 -1]
                }
            }
            if {[llength $segs] == 1} {
                lassign [lindex $segs 0] type bs be
            } else {
                set type concat
                set bs -1
                set be -1
            }
            lappend words [list $type [string range $t $wstart [expr {$i - 1}]] $wstart $i $bs $be]
        }
        lappend cmds [list $words $cstart $i]
    }
    return [list $cmds $brackets]
}

proc ::scidb::test::listlit::lineOf {t idx} {
    return [expr {[regexp -all "\n" [string range $t 0 [expr {$idx - 1}]]] + 1}]
}

# A comment line inside a braced list literal starts with '#' followed by
# whitespace (or ends there).  A colour value such as #e6edf3 does not
# match, and neither does the '#000000' key in the dark colour map.
proc ::scidb::test::listlit::hasCommentLine {body} {
    return [regexp -line {^[ \t]*#([ \t]|$)} $body]
}

proc ::scidb::test::listlit::checkLiteral {t bs be offset what problemsVar} {
    upvar 1 $problemsVar problems
    set body [string range $t $bs [expr {$be - 1}]]
    if {[::scidb::test::listlit::hasCommentLine $body]} {
        set line [::scidb::test::listlit::lineOf $t $offset]
        lappend problems [format {%s:%d: comment inside the %s literal} $line $line $what]
    }
    if {[catch {llength $body} count]} {
        set line [::scidb::test::listlit::lineOf $t $offset]
        lappend problems [format {%s:%d: %s literal is not a valid list: %s} $line $line $what $count]
    } elseif {$count % 2} {
        set line [::scidb::test::listlit::lineOf $t $offset]
        lappend problems [format {%s:%d: %s literal has an odd number of elements (%d)} $line $line $what $count]
    }
}

# Walk every command, including the bodies of namespaces and procs, and
# check the literal forms of `array set` and `dict create`.
proc ::scidb::test::listlit::checkScript {t start end problemsVar countsVar} {
    upvar 1 $problemsVar problems
    upvar 1 $countsVar counts
    lassign [::scidb::test::listlit::parseScript $t $start $end] cmds brackets
    foreach cmd $cmds {
        lassign $cmd words cstart cend
        set names {}
        foreach w $words { lappend names [lindex $w 1] }
        set sub [lrange $names 0 1]

        if {$sub eq {array set}} {
            for {set k 2} {$k < [llength $words]} {incr k} {
                lassign [lindex $words $k] type raw wstart wend bs be
                if {$type ne "braced"} continue
                incr counts(array)
                ::scidb::test::listlit::checkLiteral $t $bs $be $wstart "array set" problems
                break
            }
        } elseif {$sub eq {dict create}} {
            set args [lrange $words 2 end]
            if {[llength $args] == 1 && [lindex $args 0 0] eq "braced"} {
                lassign [lindex $args 0] type raw wstart wend bs be
                incr counts(dict)
                ::scidb::test::listlit::checkLiteral $t $bs $be $wstart "dict create" problems
            } else {
                # A multi-word `dict create key value ...` needs an even
                # number of words.  Skip it when an expansion can change
                # the static count.
                set expandable 0
                foreach w $args {
                    if {[string range [lindex $w 1] 0 2] eq "{*}"} {
                        set expandable 1
                    }
                }
                if {!$expandable} {
                    incr counts(dict)
                    if {[llength $args] % 2} {
                        set line [::scidb::test::listlit::lineOf $t $cstart]
                        lappend problems [format {%s:%d: dict create has an odd number of words (%d)} \
                            $line $line [llength $args]]
                    }
                }
            }
        }

        # Bodies are scripts too.  Recurse only into a real braced word
        # (a concat word's body is not a script on its own).
        foreach w $words {
            lassign $w type raw wstart wend bs be
            if {$type eq "braced" && $be > $bs} {
                ::scidb::test::listlit::checkScript $t $bs $be problems counts
            }
        }
    }
    foreach range $brackets {
        lassign $range bstart bend
        if {$bend > $bstart} {
            ::scidb::test::listlit::checkScript $t $bstart $bend problems counts
        }
    }
}

proc ::scidb::test::listlit::checkText {text} {
    set problems {}
    set counts(array) 0
    set counts(dict) 0
    ::scidb::test::listlit::checkScript $text 0 [string length $text] problems counts
    return [list $problems [list $counts(array) $counts(dict)]]
}

proc ::scidb::test::listlit::checkFile {path} {
    set f [open $path r]
    fconfigure $f -encoding utf-8
    set text [read $f]
    close $f
    if {![info complete $text]} {
        return [list [list "$path: incomplete Tcl source"] [list 0 0]]
    }
    set problems {}
    set counts(array) 0
    set counts(dict) 0
    ::scidb::test::listlit::checkScript $text 0 [string length $text] problems counts
    set tagged {}
    foreach problem $problems { lappend tagged "$path: $problem" }
    return [list $tagged [list $counts(array) $counts(dict)]]
}

proc ::scidb::test::listlit::tclFiles {dir} {
    set files [glob -nocomplain -directory $dir -types f *.tcl]
    foreach child [glob -nocomplain -directory $dir -types d *] {
        lappend files {*}[::scidb::test::listlit::tclFiles $child]
    }
    return $files
}

proc ::scidb::test::listlit::slurp {path} {
    set f [open $path r]
    fconfigure $f -encoding utf-8
    set text [read $f]
    close $f
    return $text
}

# ----------------------------------------------------------------------
# The guard itself must catch both shapes of the defect.
# ----------------------------------------------------------------------
tcltest::test tcl-list-literal-catches-comment \
    {a comment line inside an array set literal is reported} -body {
    lassign [::scidb::test::listlit::checkText \
        "array set X {\n\ta 1\n\t# a comment\n\tb 2\n}\n"] problems counts
    expr {[llength $problems] > 0}
} -result 1

tcltest::test tcl-list-literal-catches-odd \
    {an odd array set literal without a comment is reported} -body {
    lassign [::scidb::test::listlit::checkText "array set X {a 1 b}\n"] problems counts
    expr {[llength $problems] > 0}
} -result 1

tcltest::test tcl-list-literal-catches-dict-comment \
    {a comment line inside a dict create literal is reported} -body {
    lassign [::scidb::test::listlit::checkText \
        "dict create {\n\ta 1\n\t# a comment\n\tb 2\n}\n"] problems counts
    expr {[llength $problems] > 0}
} -result 1

tcltest::test tcl-list-literal-accepts-clean \
    {even literals without comment lines are accepted} -body {
    lassign [::scidb::test::listlit::checkText \
        "array set X {\n\ta 1\n\tb 2\n}\ndict create { a 1 b 2 }\n"] problems counts
    expr {[llength $problems] == 0}
} -result 1

# ----------------------------------------------------------------------
# Every source as written (no comment stripping), and the whole tree.
# ----------------------------------------------------------------------
tcltest::test tcl-list-literal-sources-parse \
    {every Tcl source is complete and its array/dict literals are valid} -body {
    set problems {}
    array set seenCounts {array 0 dict 0}
    foreach file [lsort [::scidb::test::listlit::tclFiles $::scidb::test::listlit::tclDir]] {
        lassign [::scidb::test::listlit::checkFile $file] found seen
        lappend problems {*}$found
        incr seenCounts(array) [lindex $seen 0]
        incr seenCounts(dict) [lindex $seen 1]
    }
    if {[llength $problems]} {
        return $problems
    }
    if {$seenCounts(array) <= 50 || $seenCounts(dict) <= 50} {
        return [list "scan found too few literals: [array get seenCounts]"]
    }
    return {}
} -result {}

# ----------------------------------------------------------------------
# Build the merged script with comment stripping disabled, then source it.
# A comment that was load-bearing (inside a list literal) fails here.
# ----------------------------------------------------------------------
tcltest::test tcl-list-literal-unstripped-bundle-sources \
    {the bundle that keeps every comment still starts} -setup {
    set ::scidb::test::listlit::tmp [file join $::scidb::test::listlit::repoRoot \
        tests tmp tcl-list-literal-[pid]]
    file delete -force $::scidb::test::listlit::tmp
    file mkdir $::scidb::test::listlit::tmp
} -body {
    set repoRoot $::scidb::test::listlit::repoRoot
    set tclDir $::scidb::test::listlit::tclDir
    set tmp $::scidb::test::listlit::tmp

    set bundle [file join $tmp chesswiz-nostrip]
    set stripped [file join $tmp chesswiz-stripped]
    set rc [catch {
        exec make -C $tclDir bundle SCRIPT=$bundle COMMENT_STRIP=0 2>@1
    } out opts]
    if {$rc} {
        return -code error "no-strip bundle build failed: $out"
    }
    if {![file readable $bundle]} {
        return -code error "no-strip bundle was not created"
    }
    set rc [catch {
        exec make -C $tclDir bundle SCRIPT=$stripped 2>@1
    } out opts]
    if {$rc} {
        return -code error "stripped bundle build failed: $out"
    }
    # Positive control: the no-strip build kept the comment that used to
    # be hidden inside the array literal, and the normal build removes it.
    set marker "# The input row (entry plus Send/Clear/Hide)"
    if {[string first $marker [::scidb::test::listlit::slurp $bundle]] < 0} {
        return -code error "no-strip bundle does not contain $marker"
    }
    if {[string first $marker [::scidb::test::listlit::slurp $stripped]] >= 0} {
        return -code error "stripped bundle still contains $marker"
    }

    set app [file join $repoRoot src tkchesswiz]
    if {[file executable $app]} {
        # A distinct path keeps the child off the single-instance port of
        # the repository binary (the port is derived from argv0).
        set bin [file join $tmp tkchesswiz-check]
        if {[catch {file link -hard $bin $app}]} {
            file copy $app $bin
        }
    } else {
        set bin [auto_execok wish]
        if {$bin eq ""} {
            return -code error "no Tk interpreter to source the bundle"
        }
    }

    set cmd [list $bin [file join $repoRoot tests startup_smoke.tcl] $bundle]
    # Tk's native window server (Aqua, Windows) needs no X display wrapper;
    # only X11 platforms without a DISPLAY need xvfb-run.
    set needsX [expr {[string equal $::tcl_platform(platform) unix]
        && ![string equal $::tcl_platform(os) Darwin]}]
    if {$needsX && (![info exists ::env(DISPLAY)] || $::env(DISPLAY) eq "")} {
        if {[auto_execok xvfb-run] eq ""} {
            return -code error "no DISPLAY and no xvfb-run to source the bundle"
        }
        set cmd [list [auto_execok xvfb-run] -a -s {-screen 0 1920x1080x24} {*}$cmd]
    }
    if {[auto_execok timeout] ne ""} {
        set cmd [linsert $cmd 0 [auto_execok timeout] 120]
    }
    set rc [catch {exec {*}$cmd 2>@1} out opts]
    if {$rc} {
        return -code error "sourcing the no-strip bundle failed: $out"
    }
    if {![regexp {STARTUP-SMOKE: OK} $out] || [string match {*FAIL*} $out]} {
        return -code error "startup smoke did not report OK: $out"
    }
    return ok
} -cleanup {
    catch { file delete -force $::scidb::test::listlit::tmp }
} -result ok

tcltest::cleanupTests
