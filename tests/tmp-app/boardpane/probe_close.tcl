# Probe: close/reopen the board pane and count background errors.
set ::bg {}
set argvCopy $argv
set argv {--single-process}; set argc 1
set ::env(SCIDB_AI_TRIAGE) 0; set ::env(SCIDB_AI_CLASSIFIER) off; set ::env(SCIDB_AI_UNCALIBRATED) 1
source -encoding utf-8 [file join [file dirname [info script]] .. .. .. tcl chesswiz]
set ::scidb::dir::setup 0
proc wait {ms} { set ::w 0; after $ms {set ::w 1}; vwait ::w }
wait 6000
trace add execution ::scidb::bgerror enter {apply {{cmd op} { lappend ::bg [lindex $cmd 1] }}}
set t [::application::twm]
proc state {tag} {
  set t $::application::Vars(board:twm)
  set has [expr {"board" in [$t leaves]}]
  set c $::application::board::Vars(widget:frame)
  puts "STATE $tag: boardleaf=$has canvas=$c exists=[winfo exists $c] bg=[llength $::bg]"
}
state start
set b [$t leaf board]
puts "leaf=$b"
$t close $b
wait 2000
state afterclose
# window resize -> reflow debounce -> updateCollapse
wm geometry .application 1500x900; wait 1500
wm geometry .application 1700x1000; wait 1500
state afterresize
::application::switchTab board
wait 500
state aftersw
::application::openPane board
wait 2000
state afterreopen
foreach e $::bg { puts "BG: [string range $e 0 200]" }
exit 0
