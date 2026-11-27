package require tcltest 2.5
proc J {s} {
	set s [string map [list \\ \\\\ \" \\\" \n \\n \r \\r \t \\t] $s]
	regsub -all {[\x00-\x1f]} $s {} s
	return "\"$s\""
}
proc Walk {m prefix} {
	global Paths
	set pc [$m cget -postcommand]
	if {$pc ne ""} { catch { uplevel #0 $pc } }
	set last [$m index end]
	if {$last in {"" none}} return
	for {set i 0} {$i <= $last} {incr i} {
		set t [$m type $i]
		if {$t in {separator tearoff}} continue
		set label [string trim [$m entrycget $i -label]]
		if {$t eq "cascade"} {
			set sm [$m entrycget $i -menu]
			Walk $sm [concat $prefix [list $label]]
			continue
		}
		set cmd [$m entrycget $i -command]
		foreach w $cmd { if {[dict exists $::action::Registry $w] && ![info exists Paths($w)]} { set Paths($w) [join [concat $prefix [list $label]] " > "] } }
	}
}
set top [menu .zzdump]
::menu::build $top
catch { ::menu::RefreshTopStates $top }
Walk $top {}
set out [open $::env(DUMP_OUT) w]
fconfigure $out -encoding utf-8
foreach id [lsort [dict keys $::action::Registry]] {
	set r [::action::get $id]
	set parts [list "[J id]:[J $id]"]
	foreach k {label what doc effect ai dropdown context keys confirm} {
		if {[dict exists $r $k]} { lappend parts "[J $k]:[J [dict get $r $k]]" }
	}
	set shown ""; catch { set shown [::action::plainText [::action::markupLabel [dict get $r label]]] }
	if {[string match menu.* $id]} { catch { set shown [::context::L $id] } }
	catch { set l [::menu::Label $id]; if {$l ne ""} { set shown $l } }
	lappend parts "[J shown]:[J $shown]"
	if {[info exists ::knowledge::Explicit] && [dict exists $::knowledge::Explicit $id]} {
		set k [dict get $::knowledge::Explicit $id]
		foreach f {purpose when} { if {[dict exists $k $f]} { lappend parts "[J $f]:[J [dict get $k $f]]" } }
	}
	set path [expr {[info exists Paths($id)] ? $Paths($id) : ""}]
	lappend parts "[J path]:[J $path]"
	puts $out "\{[join $parts ,]\}"
}
close $out
tcltest::test dump {} -body {return ok} -result ok
tcltest::cleanupTests
