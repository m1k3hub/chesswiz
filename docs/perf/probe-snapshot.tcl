::application::database::openBase .application $::BPGN yes -encoding $::encoding::autoEncoding
update; ::application::switchTab board; update
set t [::application::reflow::boardTwm]
set n 0; set q [winfo children $t]; while {[llength $q]} { set q [lassign $q w]; lappend q {*}[winfo children $w]; incr n }
list widgets=$n snapshot=[time {::application::focuszoom::Snapshot $t} 20] updateCollapse=[time {::application::reflow::updateCollapse} 20] pws=[expr {[llength [::application::focuszoom::Snapshot $t]]/2}]
