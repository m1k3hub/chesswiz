# ======================================================================
# Scidb App Test Suite - private player cards (tcl/player-card.tcl)
# ======================================================================
# What the user knows about a player that no database has: their own card
# above all. Kept in the user directory, never in a database; shown on the
# player card and in the info tooltip; "This is me" tells the assistant
# whose games "my games" are.
# ======================================================================
package require Tcl 8.6
package require tcltest 2.5
namespace eval ::scidb::test::pcard {
	variable Fixture [file join [file dirname [file normalize [info script]]] tmp-app pcard-[pid].pgn]
	variable SavedFile ""
	variable SavedMe ""
}
proc ::scidb::test::pcard::nop {args} { return 0 }
proc ::scidb::test::pcard::setup {} {
	variable SavedFile
	variable SavedMe
	set file [::playercard::PrivateFile]
	if {[file exists $file]} { set SavedFile [file join [file dirname $file] pcard-saved-[pid]]; file rename -force $file $SavedFile }
	unset -nocomplain ::playercard::Private
	catch { set SavedMe $::application::ai::Settings(me) }
	set ::application::ai::Settings(me) ""
}
proc ::scidb::test::pcard::cleanup {} {
	variable SavedFile
	variable SavedMe
	catch { destroy .application.setupPrivateCard }
	catch { file delete [::playercard::PrivateFile] }
	foreach name {{Tester, Tom} {Club, Carl}} { catch { file delete [::playercard::PhotoPath $name] } }
	if {$SavedFile ne ""} { file rename -force $SavedFile [::playercard::PrivateFile]; set SavedFile "" }
	unset -nocomplain ::playercard::Private
	set ::application::ai::Settings(me) $SavedMe
}
# Fill the dialog as a user would and press Save.
proc ::scidb::test::pcard::enter {fields {photo ""}} {
	::playercard::NewPlayer .application.setupPrivateCard.top.select
	foreach {k v} $fields { set ::playercard::Var($k) $v }
	if {$photo ne ""} { set ::playercard::PhotoSource $photo }
	if {[dict exists $fields Birthday]} {
		.application.setupPrivateCard.top.data.bbirthday set [dict get $fields Birthday]
	}
	::playercard::SavePlayer .application.setupPrivateCard.top.select
}

tcltest::test pcard-save {cards are saved, read back, and only one is "me"} -setup {
	::scidb::test::pcard::setup
	::playercard::setupPrivateCard .application
} -body {
	::scidb::test::pcard::enter {Name {Tester, Tom} FideID 4100001 Nation GER Title1 FM Rating1 Elo Score1 2310 Birthday 1990.05.17 Me 1}
	::scidb::test::pcard::enter {Name {Club, Carl} DsbID 12345-678 Me 0}
	set me1 [::playercard::myCard]
	set ai $::application::ai::Settings(me)
	::scidb::test::pcard::enter {Name {Club, Carl} DsbID 12345-678 Me 1}
	unset -nocomplain ::playercard::Private
	set tom [::playercard::privateCard {Tester, Tom}]
	list $me1 $ai [::playercard::myCard] [lsort [dict keys [::playercard::privateCards]]] \
		[dict get $tom FideID] [dict get $tom Birthday] [dict get $tom Me] \
		[::application::assistant::MePrompt]
} -cleanup {
	::scidb::test::pcard::cleanup
} -result {{Tester, Tom} {Tester, Tom} {Club, Carl} {{Club, Carl} {Tester, Tom}} 4100001 1990.05.17 0 {The user is Club, Carl. When the user says I, me or my games, use the player name Club, Carl in tool arguments.}}

tcltest::test pcard-me-prompt {without a remembered name the assistant takes the card marked "me"} -setup {
	::scidb::test::pcard::setup
	::playercard::setupPrivateCard .application
} -body {
	::scidb::test::pcard::enter {Name {Tester, Tom} Me 1}
	set ::application::ai::Settings(me) ""
	::application::assistant::MePrompt
} -cleanup {
	::scidb::test::pcard::cleanup
} -result {The user is Tester, Tom. When the user says I, me or my games, use the player name Tester, Tom in tool arguments.}

tcltest::test pcard-photo {a chosen photo is copied where the photo lookup finds it} -setup {
	::scidb::test::pcard::setup
	::playercard::setupPrivateCard .application
	set png [file join [file dirname $::scidb::test::pcard::Fixture] pcard-[pid].png]
	set img [image create photo -width 4 -height 4]
	$img put red -to 0 0 4 4
	$img write $png -format png
	image delete $img
} -body {
	::scidb::test::pcard::enter {Name {Tester, Tom}} $png
	set found [::util::photos::findPhotoFile {Tester, Tom}]
	list [expr {$found eq [::playercard::PhotoPath {Tester, Tom}]}] [file exists $found] \
		[expr {[string length [::util::photos::get {Tester, Tom}]] > 0}]
} -cleanup {
	catch { file delete $png }
	::scidb::test::pcard::cleanup
} -result {1 1 1}

tcltest::test pcard-overlay {the tooltip fills in what the database lacks; the card shows a private section} -setup {
	::scidb::test::pcard::setup
	::playercard::setupPrivateCard .application
	set fh [open $::scidb::test::pcard::Fixture w]
	puts $fh "\[Event \"PC\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"1\"\]\n\[White \"Tester, Tom\"\]\n\[Black \"Other, Olga\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 1-0\n"
	close $fh
	::scidb::db::open $::scidb::test::pcard::Fixture ::scidb::test::pcard::nop {} ::scidb::test::pcard::nop {}
} -body {
	::scidb::test::pcard::enter {Name {Tester, Tom} FideID 4100001 Nation GER Title1 FM Rating1 Elo Score1 2310}
	set info [::scidb::db::playerInfo $::scidb::test::pcard::Fixture Normal 0 white]
	set merged [::playercard::WithPrivate $info]
	set other [::playercard::WithPrivate [::scidb::db::playerInfo $::scidb::test::pcard::Fixture Normal 0 black]]
	set dlg [::playercard::show $::scidb::test::pcard::Fixture Normal 0 white]
	set html ""
	foreach key [array names ::playercard::Vars output:html] { set html $::playercard::Vars($key) }
	catch { destroy $dlg }
	list [lindex $merged 0] [lindex $merged 1] [lindex $merged 7] [lindex $merged 8] \
		[expr {[lindex $other 1] eq [lindex [::scidb::db::playerInfo $::scidb::test::pcard::Fixture Normal 0 black] 1]}] \
		[string match "*Private card*4100001*2310*" $html] [expr {[string first "Private card" $html] < [string last "</body>" $html] || [string last "</body>" $html] < 0}]
} -cleanup {
	catch { ::scidb::db::close $::scidb::test::pcard::Fixture }
	catch { file delete $::scidb::test::pcard::Fixture }
	::scidb::test::pcard::cleanup
} -result {{Tester, Tom} 4100001 GER FM 1 1 1}

tcltest::test pcard-delete {a deleted card is gone, and "me" with it} -setup {
	::scidb::test::pcard::setup
	::playercard::setupPrivateCard .application
} -body {
	::scidb::test::pcard::enter {Name {Tester, Tom} Me 1}
	set before $::application::ai::Settings(me)
	::playercard::DeletePlayer .application.setupPrivateCard.top.select
	unset -nocomplain ::playercard::Private
	list $before [dict size [::playercard::privateCards]] [::playercard::myCard] $::application::ai::Settings(me) \
		[catch { ::playercard::SavePlayer .application.setupPrivateCard.top.select }]
} -cleanup {
	::scidb::test::pcard::cleanup
} -result {{Tester, Tom} 0 {} {} 0}

tcltest::cleanupTests
