# ======================================================================
# VAL-AI-009: every user-reachable feature maps to an assistant action.
#
# Walks the built drop-down, the C1-C12 context menus, the toolbar
# buttons and the key-editor bindings, maps each row to its registry id,
# and prints the unmapped rows (must be empty) and the exempt list. The
# INVENTORY-2026-10-18 feature list is checked row by row against the
# explicit committed inventory map; missing ids fail the same coverage gate.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::kcover {
    variable root [file dirname [file dirname [file normalize [info script]]]]

    proc ready {} {
        set deadline [expr {[clock milliseconds] + 20000}]
        while {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} {
            update
            if {[clock milliseconds] > $deadline} { error {startup timed out} }
            after 10
        }
        update
        catch { destroy .tipoftheday }
        update
        ::knowledge::Ensure
    }

    proc WalkMenu {menu rowsVar surface} {
        upvar $rowsVar rows
        set post [$menu cget -postcommand]
        if {$post ne ""} { uplevel #0 $post }
        set n [$menu index end]
        if {$n eq "" || $n eq "none"} { return }
        for {set i 0} {$i <= $n} {incr i} {
            set type [$menu type $i]
            if {$type eq "separator"} { continue }
            if {$type eq "cascade"} {
                set sub ""
                catch { set sub [$menu entrycget $i -menu] }
                if {$sub ne "" && [winfo exists $sub]} { WalkMenu $sub rows $surface }
                continue
            }
            set cmd ""
            catch { set cmd [$menu entrycget $i -command] }
            set label ""
            catch { set label [string trim [$menu entrycget $i -label]] }
            set state normal
            catch { set state [$menu entrycget $i -state] }
            lappend rows [list $surface $type $state $label $cmd]
        }
    }

    proc ContextRows {} {
        catch { destroy .kcov }
        ::table::table .kcov
        ::table::addcol .kcov date -text Date
        set objects [dict create \
            C1 [dict create square e4 fen {8/8/8/8/4P3/8/8/8 w - - 0 1}] \
            C2 [dict create base b variant Normal index 5 ply 10 san Nf3] \
            C3 [dict create base b variant Normal index 1 column number sortable 1 path .kcov view 0] \
            C4 [dict create base testbase] \
            C5 [dict create kind player name {Carlsen, Magnus} base b] \
            C6 [dict create engine SF lineId 1 pv {e4 e5 Nf3}] \
            C7 [dict create base b mediaId m1 path /tmp/clip.mp4] \
            C8 [dict create fen {8/8/8/8/4P3/8/8/8 w - - 0 1} move e4 table .kcov] \
            C9 [dict create paneUid board frame .kcov] \
            C10 [dict create table .kcov column date] \
            C11 [dict create base b index 5 ply 10 widget .kcov] \
            C12 [dict create gameSlot 1 history {G1 G2}] \
        ]
        foreach kind {event site} {
            dict set objects C5.$kind [dict create kind $kind name {Generated Object} base b]
        }
        foreach uid {editor games players tree analysis:1 media report assistant explorer} {
            dict set objects C9.$uid [dict create paneUid $uid frame .kcov table .kcov]
        }
        set rows {}
        set n 0
        foreach key [dict keys $objects] {
            set cid [lindex [split $key .] 0]
            set menu .kcovctx[incr n]
            catch { destroy $menu }
            menu $menu -tearoff 0
            ::context::Build $cid $menu [dict get $objects $key]
            WalkMenu $menu rows $key
            catch { destroy $menu }
        }
        destroy .kcov
        return $rows
    }

    proc ToolbarRows {w rowsVar} {
        upvar $rowsVar rows
        if {[winfo class $w] eq "Toolbar"} {
            foreach child [winfo children $w] {
                set cls [winfo class $child]
                if {$cls ni {Button DropdownButton Checkbutton Radiobutton}} { continue }
                set cmd ""
                catch { set cmd [$child cget -command] }
                set state normal
                catch { set state [$child cget -state] }
                set label ""
                catch { set label [string trim [$child cget -text] ] }
                if {$label eq ""} { catch { set label [string trim [$child cget -tooltip]] } }
                lappend rows [list toolbar $cls $state $label $cmd]
            }
        }
        foreach child [winfo children $w] { ToolbarRows $child rows }
    }

    proc ExemptFile {} {
        variable root
        set path [file join $root tests fixtures ai-exempt.txt]
        set map [dict create]
        if {![file isfile $path]} { return $map }
        set f [open $path r]
        foreach line [split [read $f] \n] {
            set line [string trim $line]
            if {$line eq "" || [string match #* $line]} { continue }
            lassign [split $line |] id reason
            dict set map [string trim $id] [string trim $reason]
        }
        close $f
        return $map
    }

    proc CheckAction {id} {
        if {[catch {::action::get $id} rec]} { return {no registry record} }
        if {![dict get $rec operator] && [dict get $rec ai] ne "1"} {
            return {not assistant exposed}
        }
        if {[string trim [dict get $rec doc]] eq ""} { return {no description} }
        set raw [dict get $rec schema]
        if {$raw eq ""} { set raw [::action::schemaJson [dict get $rec args]] }
        if {[catch {::json::json2dict $raw} schema]} { return {invalid schema JSON} }
        if {![dict exists $schema type] || [dict get $schema type] ne "object"
            || ![dict exists $schema properties]} { return {no argument object schema} }
        return ""
    }

    proc ReadFile {path} {
        set f [open $path]; set body [read $f]; close $f
        return $body
    }

    proc BaselineSource {source} {
        variable root
        variable baseline
        if {![info exists baseline($source)]} {
            set baseline($source) [exec git -C $root show 4454fe3:$source]
        }
        return $baseline($source)
    }

    # Inspect literal namespace/proc declarations without evaluating app code.
    # Used only on files containing a candidate declaration of the missing proc.
    proc DeclaredProcs {body {ns ::}} {
        set command ""
        set names {}
        foreach line [split $body \n] {
            if {$command eq "" && [string match #* [string trimleft $line]]} {continue}
            append command $line \n
            if {![info complete $command]} {continue}
            if {![regexp {^\s*(proc\s|namespace\s+eval\s)} $command]} {set command ""; continue}
            if {[catch {lindex $command 0} head]} {error {cannot inspect source declaration}}
            if {$head eq "proc"} {
                set name [lindex $command 1]
                if {[string match ::* $name]} {lappend names $name} else {
                    lappend names [string trimright $ns :]::$name
                }
            } elseif {$head eq "namespace" && [lindex $command 1] eq "eval"} {
                set child [lindex $command 2]
                if {![string match ::* $child]} {set child [string trimright $ns :]::$child}
                set names [concat $names [DeclaredProcs [lindex $command 3] $child]]
            }
            set command ""
        }
        if {[string trim $command] ne ""} {error {incomplete source declaration}}
        return $names
    }

    proc BundleSources {} {
        variable root
        # Ask make for the expanded, platform-specific source list. Do not
        # maintain a second list which could silently miss a bundled script.
        return [exec make -s --no-print-directory -C [file join $root tcl] \
            --eval {.PHONY: inventory-coverage-sources
inventory-coverage-sources: ; @echo $(SOURCES)} inventory-coverage-sources]
    }

    proc NotReachable {source oldLine note} {
        variable root
        set historical [BaselineSource $source]
        set cited [lindex [split $historical \n] [expr {$oldLine - 1}]]
        if {[string match {comment:*} $note]} {
            if {![string match #* [string trimleft $cited]]} {return {cited line is not a comment}}
            return ""
        }
        if {[regexp {^missing-proc: (::[[:alnum:]_:]+);} $note -> missing]} {
            if {[llength [info commands $missing]]} {return {claimed missing proc exists live}}
            # The cited menu calls InstallUpdate, whose actual leaf operation
            # must be the missing proc; do not accept an unrelated absent name.
            if {$source ne "tcl/application.tcl" || $oldLine != 1547
                || ![string match *InstallUpdate* $cited]
                || [string trim [lindex [split $historical \n] 1578]] ne "$missing .application"} {
                return {missing proc is not the cited operation}
            }
            set short [namespace tail $missing]
            foreach file [split [exec git -C $root ls-tree -r --name-only 4454fe3 -- tcl] \n] {
                if {[file extension $file] ne ".tcl"} {continue}
                set body [BaselineSource $file]
                if {![regexp [format {proc\s+(::[[:alnum:]_:]+::)?%s\s} $short] $body]} {continue}
                if {$missing in [DeclaredProcs $body]} {return {claimed missing proc exists in baseline}}
            }
            return ""
        }
        if {[string match {standalone:*} $note]} {
            set relative [string range $source 4 end]
            set sources [BundleSources]
            if {$relative in $sources} {return {standalone source is bundled}}
            set body [ReadFile [file join $root $source]]
            if {![regexp -line {^exec .*tkchesswiz} $body]} {return {missing standalone executable header}}
            set bundle [ReadFile [file join $root tcl chesswiz]]
            set procs [DeclaredProcs $body]
            # The tool installs compatibility stubs for app utilities too.
            # Check the defining procs of its menu operations, not those stubs.
            set operations [regexp -all -inline -line {^\s*\$menu add command [^\n]*-command ([[:alnum:]_]+)\s*$} $body]
            if {![llength $operations]} {return {standalone has no inspectable menu operations}}
            set citedName ""
            if {![regexp -- {-command ([[:alnum:]_]+)\s*$} $cited -> citedName]} {return {unrecognized standalone operation}}
            set checked {}
            foreach {declaration short} $operations {
                set name ::$short
                if {$name ni $procs} {return "standalone operation has no definition: $name"}
                if {[llength [info commands $name]]} {return "standalone proc exists live: $name"}
                # Match both global spellings in the built bundle. Include
                # namespace-local declarations conservatively by short name.
                if {[regexp -line [format {^\s*proc\s+(::[[:alnum:]_:]*)?%s\s} $short] $bundle]} {
                    return "standalone proc exists in bundle: $name"
                }
                lappend checked $short
            }
            if {$citedName ni $checked} {return {cited standalone operation was not checked}}
            foreach app [split [exec git -C $root ls-files -- tcl] \n] {
                if {[file extension $app] ne ".tcl" || [string match tcl/tools/* $app]} {continue}
                set text [ReadFile [file join $root $app]]
                # Accept neither a direct path nor the list-form path spelling.
                if {[string first $relative $text] >= 0
                    || [regexp {tools[ /]+board(?:\.tcl)?} $text]} {
                    return "application source references standalone script: $app"
                }
            }
            return ""
        }
        return {missing automatic not-reachable evidence}
    }

    proc InventoryCoverage {unmappedVar exempts} {
        upvar 1 $unmappedVar unmapped
        variable root
        set path [file join $root tests fixtures inventory-map.tsv]
        set f [open $path]; set body [read $f]; close $f
        set expected 1
        set literalRows {}
        set mapped 0
        set unreachable 0
        foreach line [split $body \n] {
            if {$line eq "" || [string match #* $line] || [string match row\t* $line]} { continue }
            lassign [split $line \t] row source oldLine id note feature
            if {$row ne "$expected"} { lappend unmapped [list inventory $row {missing, duplicate or reordered row}] }
            incr expected
            if {![regexp {^\|\s+`(tcl/[^`:]+):(\d+)`\s*\|} $feature -> featureSource featureLine]
                || $source ne $featureSource || $oldLine ne $featureLine} {
                lappend unmapped [list inventory $row {source identity drift}]
            }
            lappend literalRows $feature
            if {$id eq ""} {
                lappend unmapped [list inventory $row $source:$oldLine $feature]
            } elseif {$id eq "not-reachable"} {
                if {[catch {NotReachable $source $oldLine $note} error] || $error ne ""} {
                    lappend unmapped [list inventory $row not-reachable $error]
                } else {
                    incr unreachable
                    puts "AI-009 not-reachable: $row $source:$oldLine | $note"
                }
            } elseif {[dict exists $exempts $id]} {
                if {[dict get $exempts $id] eq ""} { lappend unmapped [list inventory $row {empty exemption reason}] }
            } elseif {[set error [CheckAction $id]] ne ""} {
                lappend unmapped [list inventory $row $id $error]
            } else { incr mapped }
        }
        # The committed map includes the literal historical feature list so the
        # check also runs from a clean checkout. When the authoritative Markdown
        # is installed, require byte-for-byte row identity and order with it.
        set original [file join $root tests tmp-app menu-redesign INVENTORY-2026-10-18.md]
        if {[file exists $original]} {
            set f [open $original];set originalBody [read $f];close $f
            set originalRows {}
            foreach line [split $originalBody \n] {
                if {[regexp {^\|\s+`(tcl/[^`:]+):(\d+)`\s*\|} $line]} { lappend originalRows $line }
            }
            if {$originalRows ne $literalRows} { lappend unmapped {inventory original-list-drift} }
        }
        if {[llength $literalRows] != 847} { lappend unmapped {inventory incomplete-source-list} }
        puts "AI-009 INVENTORY: [llength $literalRows] literal feature references, $mapped mapped registry ids, $unreachable automatically verified not-reachable"
    }

}

tcltest::test knowledge-coverage-surfaces {every posted row maps to a registry id} -body {
    ::scidb::test::kcover::ready
    set rows {}
    catch { destroy .kcovdd }
    menu .kcovdd -tearoff 0
    ::menu::BuildDropdown .kcovdd
    ::menu::Dump .kcovdd
    ::scidb::test::kcover::WalkMenu .kcovdd rows dropdown
    destroy .kcovdd
    set ctx [::scidb::test::kcover::ContextRows]
    set rows [concat $rows $ctx]
    set tb {}
    ::scidb::test::kcover::ToolbarRows . tb
    set rows [concat $rows $tb]

    ::knowledge::FillAll
    set exempts [::scidb::test::kcover::ExemptFile]
    set unmapped {}
    set mapped 0
    set dynamic 0
    set exempt 0
    foreach row $rows {
        set cmd [string trim [lindex $row 4]]
        if {[regexp {^::action::run\s+(\S+)} $cmd -> id]} {
            if {[dict exists $exempts $id]} { incr exempt; continue }
            if {[set error [::scidb::test::kcover::CheckAction $id]] ne ""} {
                lappend unmapped [list [lindex $row 0] [lindex $row 3] $id $error]
            } else { incr mapped }
        } elseif {$cmd eq ""} {
            # A disabled placeholder has no operation. Dynamic commands must
            # prove their exposure by the same rule as static commands.
            incr dynamic
        } else {
            lappend unmapped [list [lindex $row 0] [lindex $row 3] $cmd]
        }
    }

    # Key bindings: every key-editor id is a registry id and is exposed.
    set keys 0
    foreach entry $::application::keyEditor::Actions {
        set id [lindex $entry 0]
        incr keys
        if {[dict exists $exempts $id]} { continue }
        if {[set error [::scidb::test::kcover::CheckAction $id]] ne ""} {
            lappend unmapped [list keyboard $id $error]
        }
    }

    ::scidb::test::kcover::InventoryCoverage unmapped $exempts

    set inventory [file join $::scidb::test::kcover::root tests tmp-app ai-operation-inventory-[pid].tsv]
    set out [open $inventory w]
    puts $out "id\tsurfaces\texposed\targument-schema"
    foreach id [lsort [::action::list]] {
        set rec [::action::get $id]
        set exposure [expr {[dict get $rec operator] || [dict get $rec ai] eq "1"}]
        puts $out [join [list $id [::knowledge::Surface $id $rec] $exposure [::action::schemaOf $id]] \t]
    }
    close $out
    puts "AI-009 operation inventory: $inventory"

    set exposed 0
    foreach id [::action::list] {
        set rec [::action::get $id]
        if {[dict get $rec ai] eq "1" || [dict get $rec ai] eq "debug"} { incr exposed }
    }
    set operators 0
    foreach id [::action::list] {
        if {[dict get [::action::get $id] operator]} { incr operators }
    }
    puts "AI-009 coverage: [llength $rows] posted rows, $mapped mapped, $dynamic empty placeholders, $exempt exempt, [llength $unmapped] unmapped, $keys key bindings"
    puts "AI-009 exposed: before 87, after $exposed ai-tools ($operators operator-exposed registry actions)"
    puts "AI-009 exempt list:"
    dict for {id reason} $exempts { puts "  $id | $reason" }
    foreach u $unmapped { puts "  unmapped: $u" }
    set unmapped
} -result {}

tcltest::test knowledge-coverage-exempt-short {the exempt list stays short and every entry has a reason} -body {
    set exempts [::scidb::test::kcover::ExemptFile]
    set bad {}
    dict for {id reason} $exempts {
        if {[string trim $reason] eq ""} { lappend bad $id }
    }
    puts "AI-009 exempt: [dict size $exempts] entries, [llength $bad] without a reason"
    list [expr {[dict size $exempts] <= 3}] $bad
} -result {1 {}}

tcltest::test knowledge-unreachable-comment-guard {an active line cannot be disposed as a comment} -body {
    ::scidb::test::kcover::NotReachable tcl/tools/board.tcl 156 {comment: false claim}
} -result {cited line is not a comment}

tcltest::test knowledge-unreachable-missing-guard {a proc restored to the live app invalidates a missing-proc disposition} -setup {
    proc ::util::photos::openDialog {args} {}
} -body {
    ::scidb::test::kcover::NotReachable tcl/application.tcl 1547 {missing-proc: ::util::photos::openDialog; regression probe}
} -cleanup {rename ::util::photos::openDialog {}} -result {claimed missing proc exists live}

tcltest::test knowledge-unreachable-standalone-guard {loading a standalone menu operation invalidates the disposition} -setup {
    proc ::SelectTheme {} {}
} -body {
    ::scidb::test::kcover::NotReachable tcl/tools/board.tcl 156 {standalone: regression probe}
} -cleanup {rename ::SelectTheme {}} -result {standalone proc exists live: ::SelectTheme}

tcltest::test knowledge-unreachable-bundle-guard {a bundled source cannot be disposed as standalone} -body {
    ::scidb::test::kcover::NotReachable tcl/application.tcl 1547 {standalone: false claim}
} -result {standalone source is bundled}

tcltest::cleanupTests
