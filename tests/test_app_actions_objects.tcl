# ======================================================================
# Scidb App Test — Context action object resolution (VAL-REG-007)
# ======================================================================
# Actions that act on an object receive a typed reference from a
# resolver, so the same action works from context menu, palette and
# assistant without widget paths.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::actions_obj {}

if {[llength [info commands ::action::register]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl actions.tcl]
}

tcltest::test obj-resolver-register {resolvers can be registered per object type} -body {
	::action::resolver::register testobj {list resolved testobj}
	set r [::action::resolver::resolve testobj]
	expr {$r eq "resolved testobj"}
} -result 1

tcltest::test obj-resolver-missing {missing resolver returns error} -body {
	catch {::action::resolver::resolve nosuchtype} err
	set err
} -match glob -result {*no resolver*}

tcltest::test obj-context-action-receives-object {context action gets resolved object} -setup {
	variable ::scidb::test::actions_obj::receivedObj {}
	proc ::scidb::test::actions_obj::ctxStub {argsDict} {
		variable ::scidb::test::actions_obj::receivedObj
		set receivedObj [expr {[dict exists $argsDict _object] ? [dict get $argsDict _object] : {}}]
		return ok
	}
	::action::resolver::register game {list GAME_REF_42}
	::action::register test.ctx.game {
		label ::test::mc::CtxGame
		object game
		handler ::scidb::test::actions_obj::ctxStub

		what {}
		doc {}
	}
} -body {
	::action::run test.ctx.game {}
	set ::scidb::test::actions_obj::receivedObj
} -cleanup {
	rename ::scidb::test::actions_obj::ctxStub {}
} -result {GAME_REF_42}

tcltest::test obj-same-effect-via-run-and-direct {invoke via run gives same result as direct handler call} -setup {
	variable ::scidb::test::actions_obj::directResult {}
	variable ::scidb::test::actions_obj::viaRunResult {}
	proc ::scidb::test::actions_obj::sharedStub {argsDict} {
		set obj [expr {[dict exists $argsDict _object] ? [dict get $argsDict _object] : {}}]
		return "handled:$obj"
	}
	::action::resolver::register move {list MOVE_E4E5}
	::action::register test.shared.move {
		label ::test::mc::SharedMove
		object move
		handler ::scidb::test::actions_obj::sharedStub

		what {}
		doc {}
	}
} -body {
	set viaRun [::action::run test.shared.move {}]
	set direct [::scidb::test::actions_obj::sharedStub {_object MOVE_E4E5}]
	expr {$viaRun eq $direct}
} -cleanup {
	rename ::scidb::test::actions_obj::sharedStub {}
} -result 1

tcltest::test obj-multiple-types {different object types resolve independently} -setup {
	::action::resolver::register player {list PLAYER_KASPAROV}
	::action::resolver::register database {list DB_TWIC1600}
	variable ::scidb::test::actions_obj::lastObj {}
	proc ::scidb::test::actions_obj::multiStub {argsDict} {
		variable ::scidb::test::actions_obj::lastObj
		set lastObj [expr {[dict exists $argsDict _object] ? [dict get $argsDict _object] : {}}]
		return ok
	}
	::action::register test.multi.player {
		label ::test::mc::MultiPlayer
		object player
		handler ::scidb::test::actions_obj::multiStub

		what {}
		doc {}
	}
	::action::register test.multi.db {
		label ::test::mc::MultiDb
		object database
		handler ::scidb::test::actions_obj::multiStub

		what {}
		doc {}
	}
} -body {
	::action::run test.multi.player {}
	set p $::scidb::test::actions_obj::lastObj
	::action::run test.multi.db {}
	set d $::scidb::test::actions_obj::lastObj
	list $p $d
} -cleanup {
	rename ::scidb::test::actions_obj::multiStub {}
} -result {PLAYER_KASPAROV DB_TWIC1600}

::tcltest::cleanupTests
return
