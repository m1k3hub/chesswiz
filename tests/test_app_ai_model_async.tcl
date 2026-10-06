package require tcltest 2.5
namespace eval ::scidb::test::modelasync {
 variable Saved {}
 variable Seq 0
 variable Timers {}
}
proc ::scidb::test::modelasync::stub {name arguments body} {
 variable Saved
 variable Seq
 set backup {}
 if {[llength [info commands $name]]} {
  set backup ${name}.__async[incr Seq]
  rename $name $backup
 }
 lappend Saved [list $name $backup]
 proc $name $arguments $body
}
proc ::scidb::test::modelasync::restore {} {
 variable Saved
 variable Timers
 foreach timer $Timers {after cancel $timer}
 set Timers {}
 foreach pair [lreverse $Saved] {
  lassign $pair name backup
  rename $name {}
  if {$backup ne {}} {rename $backup $name}
 }
 set Saved {}
}

tcltest::test modelasync-open {opening the chooser returns without waiting for model discovery} -setup {
 # discovery is asked for asynchronously and has not answered when the
 # chooser is up; a synchronous lookup would be waiting for it (the time
 # the dialog takes to lay itself out varies with the machine, so it is
 # not measured)
 set ::scidb::test::modelasync::sync 0
 set ::scidb::test::modelasync::async 0
 ::scidb::test::modelasync::stub ::ai::provider::ollamaModels {args} {
  incr ::scidb::test::modelasync::sync; after 350; return {}
 }
 ::scidb::test::modelasync::stub ::ai::provider::ollamaModelsAsync {callback args} {
  incr ::scidb::test::modelasync::async
  lappend ::scidb::test::modelasync::Timers [after 350 [list {*}$callback {ok 1 models {}}]]
 }
} -body {
 set dlg [::application::ai::models::show .application]
 list $::scidb::test::modelasync::sync [expr {$::scidb::test::modelasync::async > 0}] [winfo exists $dlg]
} -cleanup {
 ::application::ai::models::Close
 ::scidb::test::modelasync::restore
} -result {0 1 1}

tcltest::test modelasync-gpu-heartbeat {GPU probing leaves Tcl timers responsive} -body {
 set ::scidb::test::modelasync::heartbeat 0
 set ::scidb::test::modelasync::result {}
 set timer [after 30 {set ::scidb::test::modelasync::heartbeat 1}]
 set began [clock milliseconds]
 ::ai::modelfit::memoryAsync {set ::scidb::test::modelasync::result} \
  -gpu [list sh -c {sleep 0.2; printf '8192\n'}] -timeoutMs 1000
 set returned [expr {[clock milliseconds]-$began < 100}]
 vwait ::scidb::test::modelasync::result
 after cancel $timer
 list $returned $::scidb::test::modelasync::heartbeat [dict get $::scidb::test::modelasync::result vram_mb]
} -result {1 1 8192}


tcltest::test modelasync-stale-discovery {a reply for a closed dialog cannot fill its replacement} -setup {
 set ::scidb::test::modelasync::Callbacks {}
 # Ollama is asked only for a saved local choice
 set ::scidb::test::modelasync::SavedSettings [array get ::application::ai::Settings]
 array set ::application::ai::Settings {provider ollama chosen 1}
 ::scidb::test::modelasync::stub ::ai::provider::ollamaModelsAsync {callback args} {
  lappend ::scidb::test::modelasync::Callbacks $callback
 }
} -body {
 ::application::ai::models::show .application
 ::application::ai::models::Close
 ::application::ai::models::show .application
 {*}[lindex $::scidb::test::modelasync::Callbacks 0] {ok 1 models {{name old:1b remote 0 tools 1 size 1}}}
 set before [$::application::ai::models::Priv(tree) children {}]
 {*}[lindex $::scidb::test::modelasync::Callbacks 1] {ok 1 models {{name new:1b remote 0 tools 1 size 1}}}
 list $before [$::application::ai::models::Priv(tree) children {}]
} -cleanup {
 ::application::ai::models::Close
 ::scidb::test::modelasync::restore
 array set ::application::ai::Settings $::scidb::test::modelasync::SavedSettings
} -result {{} new:1b}

tcltest::test modelasync-gpu-timeout {a stuck GPU command times out and releases its probe} -body {
 set ::scidb::test::modelasync::result {}
 set began [clock milliseconds]
 set id [::ai::modelfit::memoryAsync {set ::scidb::test::modelasync::result} \
  -gpu [list sleep 2] -timeoutMs 60]
 vwait ::scidb::test::modelasync::result
 list [expr {[clock milliseconds]-$began < 500}] \
  [dict get $::scidb::test::modelasync::result vram_mb] [info exists ::ai::modelfit::Probes($id)]
} -result {1 0 0}

tcltest::test modelasync-cancel-probe {closing a chooser cancels its GPU query without delivering a stale callback} -body {
 set ::scidb::test::modelasync::result {}
 set id [::ai::modelfit::memoryAsync {set ::scidb::test::modelasync::result} -gpu [list sleep 2]]
 ::ai::modelfit::cancelMemory $id
 list $::scidb::test::modelasync::result [info exists ::ai::modelfit::Probes($id)]
} -result {{} 0}

# Real local HTTP server; no external service or synchronous provider stub.
proc ::scidb::test::modelasync::accept {chan address port} {
 fconfigure $chan -blocking 0 -buffering line -translation auto
 fileevent $chan readable [list ::scidb::test::modelasync::readRequest $chan]
}
proc ::scidb::test::modelasync::readRequest {chan} {
 while {[gets $chan line] >= 0} {
  if {$line ne {}} {continue}
  fileevent $chan readable {}
  after 150 [list ::scidb::test::modelasync::respond $chan]
  return
 }
 if {[eof $chan]} {close $chan}
}
proc ::scidb::test::modelasync::respond {chan} {
 set data {{"models":[{"name":"tiny:1b","details":{"parameter_size":"1B"}}]}}
 fconfigure $chan -translation binary
 puts -nonewline $chan "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: [string length $data]\r\nConnection: close\r\n\r\n$data"
 close $chan
}
tcltest::test modelasync-http-heartbeat {the real asynchronous HTTP path remains responsive while awaiting /api/tags} -setup {
 set server [socket -server ::scidb::test::modelasync::accept -myaddr 127.0.0.1 0]
 set port [lindex [fconfigure $server -sockname] end]
} -body {
 set ::scidb::test::modelasync::result {}
 set ::scidb::test::modelasync::heartbeat 0
 after 30 {set ::scidb::test::modelasync::heartbeat 1}
 set began [clock milliseconds]
 ::ai::provider::ollamaModelsAsync {set ::scidb::test::modelasync::result} http://127.0.0.1:$port 1000
 set returned [expr {[clock milliseconds]-$began < 100}]
 vwait ::scidb::test::modelasync::result
 list $returned $::scidb::test::modelasync::heartbeat \
  [dict get $::scidb::test::modelasync::result ok] \
  [dict get [lindex [dict get $::scidb::test::modelasync::result models] 0] name]
} -cleanup {close $server} -result {1 1 1 tiny:1b}

::tcltest::cleanupTests
