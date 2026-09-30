# ======================================================================
# Non-blocking notices -- errors that are still seen, without a modal dialog.
#
# A dialog with only an OK button tells the user something and asks for
# nothing; making the whole program wait for a click (and, worse, hiding the
# rest of the work behind it) is the wrong answer for that. ::dialog::alert
# (messagebox.tcl) hands such messages to ::dialog::notice::post instead:
#
#   - a coloured card appears at the top right of the main window and the
#     caller carries on at once (it gets "ok" back);
#   - errors stay until they are dismissed, warnings fade after 15 s, plain
#     information after 7 s; hovering the card holds it;
#   - the same message arriving again only raises a counter on its card;
#   - at most 4 cards are shown; the oldest non-error goes first;
#   - every message is also written to the log window (without opening it);
#     the card's Details button opens the log.
#
# Decisions (yes/no, overwrite?, anything with another button than OK) are
# still modal: the program needs the answer.
#
#   ::dialog::notice::post <error|warning|info> <message> ?<detail>?
#   ::dialog::notice::enable <bool>     (SCIDB_MODAL_DIALOGS=1 switches it off)
#   ::dialog::notice::available         is there a main window to show cards in?
# ======================================================================

namespace eval dialog {
namespace eval notice {

variable Enabled 1
if {[::info exists ::env(SCIDB_MODAL_DIALOGS)] && [string is true -strict $::env(SCIDB_MODAL_DIALOGS)]} {
	set Enabled 0
}

variable Max 4
variable Life		;# ms on screen, 0 = until dismissed
array set Life {error 0 warning 15000 info 7000}
variable Colour
array set Colour {error #c62828 warning #ef6c00 info #1565c0}
variable Holder .application.__notices__
variable Next 0
variable Cards {}	;# {id kind message count} in order of arrival
variable Timer
array set Timer {}


proc enable {args} {
	variable Enabled
	if {[llength $args]} { set Enabled [string is true -strict [lindex $args 0]] }
	return $Enabled
}


proc available {} {
	variable Enabled
	return [expr {$Enabled && [winfo exists .application]}]
}


# Show a card and record the message. Returns at once.
proc post {kind message {detail ""}} {
	variable Cards
	variable Next
	variable Max
	variable Holder

	if {$kind ni {error warning info}} { set kind info }
	set message [string trim $message]
	Record $kind $message $detail

	# the same message again: count it instead of stacking another card
	for {set i 0} {$i < [llength $Cards]} {incr i} {
		lassign [lindex $Cards $i] id k m n
		if {$k eq $kind && $m eq $message && [winfo exists $Holder.$id]} {
			lset Cards $i 3 [incr n]
			$Holder.$id.text configure -text [CardText $message $n]
			Arm $id $kind
			return
		}
	}

	Make
	set id n[incr Next]
	Card $id $kind $message
	lappend Cards [list $id $kind $message 1]
	while {[llength $Cards] > $Max} { Drop }
	Arm $id $kind
	Layout
	return
}


# to the log window, which stays closed
proc Record {kind message detail} {
	set text $message
	if {[string length [string trim $detail]]} { append text "\n" [string trim $detail] }
	set type [dict get {error Error warning Warning info Information} $kind]
	# ::log::Print opens the log window on the first error (its "show" flag)
	# and arms "force" for later log sessions; neither is wanted for a quiet
	# record, so both flags are put back afterwards
	set keepShow 0; set keepForce 0
	catch { set keepShow $::log::Priv(show); set keepForce $::log::Priv(force) }
	catch { set ::log::Priv(show) 0 }
	catch { ::log::Print $type 0 $text }
	catch { set ::log::Priv(show) $keepShow; set ::log::Priv(force) $keepForce }
	catch { puts stderr "scidb $kind: [lindex [split $message \n] 0]" }
}


proc Make {} {
	variable Holder
	if {[winfo exists $Holder]} { return }
	tk::frame $Holder -borderwidth 0 -highlightthickness 0
}


proc Card {id kind message} {
	variable Holder
	variable Colour

	set bg [ttk::style lookup TFrame -background]
	set fg [ttk::style lookup TLabel -foreground]
	if {$bg eq ""} { set bg #f4f4f4 }
	if {$fg eq ""} { set fg #202020 }

	set f $Holder.$id
	tk::frame $f -background $bg -highlightthickness 1 -highlightbackground $Colour($kind)
	tk::frame $f.bar -background $Colour($kind) -width 6
	tk::label $f.text -text [CardText $message 1] -background $bg -foreground $fg \
		-justify left -anchor w -wraplength 380 -padx 8 -pady 6
	tk::button $f.details -text "Details" -relief flat -borderwidth 0 -background $bg -foreground $Colour($kind) \
		-activebackground $bg -cursor hand2 -command [list ::log::show -force]
	tk::button $f.close -text "✕" -relief flat -borderwidth 0 -background $bg -foreground $fg \
		-activebackground $bg -cursor hand2 -command [list [namespace current]::Dismiss $id]
	pack $f.bar -side left -fill y
	pack $f.close -side right -padx 4 -anchor n
	pack $f.details -side right -padx 2 -anchor n
	pack $f.text -side left -fill both -expand yes
	bind $f <Enter> [list [namespace current]::Hold $id]
	bind $f <Leave> [list [namespace current]::Release $id $kind]
	foreach w [list $f.text $f.bar] {
		bind $w <Enter> [list [namespace current]::Hold $id]
		bind $w <Leave> [list [namespace current]::Release $id $kind]
	}
}


proc CardText {message count} {
	if {$count > 1} { return "$message  (×$count)" }
	return $message
}


proc Layout {} {
	variable Holder
	variable Cards

	if {![winfo exists $Holder]} { return }
	if {![llength $Cards]} {
		place forget $Holder
		return
	}
	foreach w [pack slaves $Holder] { pack forget $w }
	foreach c $Cards {
		set f $Holder.[lindex $c 0]
		if {[winfo exists $f]} { pack $f -side top -fill x -pady {0 6} }
	}
	place $Holder -in .application -relx 1.0 -rely 0.0 -anchor ne -x -14 -y 48
	raise $Holder
}


proc Arm {id kind} {
	variable Life
	variable Timer

	if {[::info exists Timer($id)]} { after cancel $Timer($id); unset Timer($id) }
	if {$Life($kind) > 0} {
		set Timer($id) [after $Life($kind) [list [namespace current]::Dismiss $id]]
	}
}


proc Hold {id} {
	variable Timer
	if {[::info exists Timer($id)]} { after cancel $Timer($id); unset Timer($id) }
}


proc Release {id kind} {
	Arm $id $kind
}


proc Dismiss {id} {
	variable Cards
	variable Holder
	variable Timer

	if {[::info exists Timer($id)]} { after cancel $Timer($id); unset Timer($id) }
	catch { destroy $Holder.$id }
	set keep {}
	foreach c $Cards { if {[lindex $c 0] ne $id} { lappend keep $c } }
	set Cards $keep
	Layout
}


# the card to make room for a new one: the oldest that is not an error
proc Drop {} {
	variable Cards

	set victim 0
	for {set i 0} {$i < [llength $Cards]} {incr i} {
		if {[lindex $Cards $i 1] ne "error"} { set victim $i; break }
	}
	Dismiss [lindex $Cards $victim 0]
}


# how many cards are on screen (for the tests)
proc count {} {
	variable Cards
	return [llength $Cards]
}

} ;# namespace notice
} ;# namespace dialog

# vi:set ts=3 sw=3:
