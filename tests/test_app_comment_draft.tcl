# ======================================================================
# Scidb App Test - comment editor: draft a comment (C1, tcl/comment.tcl)
# ======================================================================
# The grounded generation is exercised elsewhere; here we check that its
# observer (::comment::OnDraft) puts the text into the editor for review and
# never saves anything.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::draft {}

proc ::scidb::test::draft::editor {} {
	set f .drafteditor[pid]
	if {![winfo exists $f]} {
		frame $f
		text $f.text
	}
	set ::comment::Vars(lang) xx
	set ::comment::Vars(widget:text:xx) $f
	return $f.text
}

tcltest::test comment-draft-inserts {OnDraft puts the text in the editor} -body {
	set w [::scidb::test::draft::editor]
	::comment::OnDraft . [dict create ok 1 text "A fine move."]
	set text [$w get 1.0 end-1c]
	destroy [winfo parent $w]
	set text
} -result {A fine move.}

tcltest::test comment-draft-appends {OnDraft appends to existing text} -body {
	set w [::scidb::test::draft::editor]
	$w insert end "Existing."
	::comment::OnDraft . [dict create ok 1 text "More."]
	set text [$w get 1.0 end-1c]
	destroy [winfo parent $w]
	set text
} -result "Existing.\nMore."

tcltest::test comment-draft-ignores-failure {OnDraft does nothing when generation failed} -body {
	set w [::scidb::test::draft::editor]
	::comment::OnDraft . [dict create ok 0 error "no model"]
	set text [$w get 1.0 end-1c]
	destroy [winfo parent $w]
	set text
} -result {}

tcltest::test comment-draft-ignores-empty {OnDraft ignores an empty answer} -body {
	set w [::scidb::test::draft::editor]
	::comment::OnDraft . [dict create ok 1 text "   "]
	set text [$w get 1.0 end-1c]
	destroy [winfo parent $w]
	set text
} -result {}

tcltest::test comment-translate-inserts {OnTranslated puts the translation in the target slot} -body {
	set source [::scidb::test::draft::editor]
	set target .drafttarget[pid]
	frame $target
	text $target.text
	set ::comment::Vars(langSet) {xx de}
	set ::comment::Vars(widget:text:de) $target
	set ::comment::Vars(tb:de) dummy
	set ::comment::Vars(lang) de
	::comment::OnTranslated . de [dict create ok 1 text "Der K\u00f6nig."]
	set text [$target.text get 1.0 end-1c]
	destroy $source $target
	set text
} -result {Der König.}

tcltest::test comment-translate-ignores-failure {OnTranslated does nothing when generation failed} -body {
	set target .draftfail[pid]
	frame $target
	text $target.text
	set ::comment::Vars(langSet) {xx de}
	set ::comment::Vars(widget:text:de) $target
	set ::comment::Vars(tb:de) dummy
	set ::comment::Vars(lang) de
	::comment::OnTranslated . de [dict create ok 0 error "no model"]
	set text [$target.text get 1.0 end-1c]
	destroy $target
	set text
} -result {}

::tcltest::cleanupTests
return
