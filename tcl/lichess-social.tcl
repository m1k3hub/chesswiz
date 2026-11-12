# ======================================================================
# Lichess Players & Teams tab (::lichess::social).
# Tab "Lichess players" in the Chesswiz Online window:
# - Look up a user (::lichess::api::user, ::lichess::api::ratingHistory,
#   ::lichess::api::teamsOf) with a rating-history mini chart on a canvas.
# - Challenge a user (real-time or correspondence, variant, colour, rated)
#   via ::lichess::api::challengeUser, cancel outgoing challenge via
#   ::lichess::api::cancelChallenge.
# - Incoming-challenge banner with Accept (::lichess::api::acceptChallenge)
#   and Decline (::lichess::api::declineChallenge with reason), hooked from
#   ::lichess::OnEvent for challenge / challengeCanceled / challengeDeclined.
# - Send a message (::lichess::api::sendMessage).
# - Teams of user list with Join (::lichess::api::joinTeam) and Leave
#   (::lichess::api::leaveTeam).
# ======================================================================

::util::source lichess-social

package require Tcl 8.5
package require Tk 8.5

namespace eval ::lichess::social {
namespace eval mc {
set ChallengesGroup "Challenges"
set RefreshChallenges "Refresh challenges"
set NoIncoming "No incoming challenges."
set NoOutgoing "No outgoing challenges."
set NoTeams "This player has no teams."

set TabTitle				"Lichess players"
set LookupGroup			"Player lookup"
set UsernameLabel			"Username:"
set Lookup					"Look up"
set LookingUp				"Looking up %s…"
set UserNotFound			"Player not found: %s."
set ProfileRatings		"Ratings:"
set RatingChart			"Rating history"
set NoRatingHistory		"No rating history available."
set IncomingChallenge	"Incoming challenge from %s (%s)"
set AcceptChallenge		"Accept"
set DeclineChallenge		"Decline"
set DeclineReason			"Reason:"
set ChallengeAccepted	"Accepted challenge %s."
set ChallengeDeclined	"Declined challenge %s."
set ChallengeCancelled	"Challenge %s was cancelled."
set ChallengeGroup		"Challenge player"
set Minutes					"Minutes:"
set IncrementSeconds		"Increment (seconds):"
set CorrespondenceDays	"Correspondence days:"
set Variant					"Variant:"
set Colour					"Colour:"
set Random					"random"
set White					"white"
set Black					"black"
set RatedGame				"Rated game"
set SendChallenge			"Challenge"
set CancelOutgoing		"Cancel challenge"
set Challenging			"Challenging %s…"
set ChallengeSent			"Challenge sent (%s)."
set OutgoingCancelled	"Outgoing challenge cancelled."
set MessageGroup			"Send message"
set MessageLabel			"Message:"
set SendMessage			"Send message"
set MessageSent			"Message sent to %s."
set TeamsGroup				"Teams"
set TeamIdLabel			"Team ID:"
set JoinMessageLabel		"Join message:"
set JoinTeam				"Join team"
set LeaveTeam				"Leave team"
set TeamJoined				"Joined team %s."
set TeamLeft				"Left team %s."
set EnterUsername			"Enter a Lichess username first."
set EnterTeamId			"Enter or select a team ID first."
set EnterMessage			"Enter a message text first."

} ;# namespace mc

variable Variants {
	standard chess960 crazyhouse antichess atomic
	horde kingOfTheHill racingKings threeCheck fromPosition
}

variable DeclineReasons {
	generic later tooFast tooSlow timeControl
	rated casual standard variant noBot onlyBot
}

array set Priv {
	tab				{}
	statusText		{}
	lookupUser		{}
	profileText		{}
	userData			{}
	ratingHistory	{}
	teams				{}
	selectedPerf	{}
	chMinutes		10
	chIncrement		0
	chDays			{}
	chVariant		standard
	chColor			random
	chRated			0
	outgoingId		{}
	incoming			{}
	incomingId		{}
	declineReason	generic
	messageText		{}
	teamId			{}
	teamMessage		{}
}

} ;# namespace ::lichess::social


proc ::lichess::social::open {{parent .application}} {
	variable Priv
	variable Variants
	variable DeclineReasons
	variable mc

	set tab [::online::window::tab lichess-social $mc::TabTitle]
	::online::window::select lichess-social
	if {[info exists Priv(widget:top)] && [winfo exists $Priv(widget:top)]} {
		return $tab
	}
	set Priv(tab) $tab

	set top [ttk::frame $tab.top]
	pack $top -fill both -expand yes
	set Priv(widget:top) $top

	# Incoming-challenge banner (hidden until a challenge arrives)
	set ib [ttk::labelframe $top.incoming -text "Challenge" -padding 6]
	set Priv(widget:incoming) $ib
	ttk::label $ib.label -anchor w -justify left -wraplength 650
	ttk::label $ib.reasonLabel -text $mc::DeclineReason
	ttk::combobox $ib.reason -state readonly -width 12 -values $DeclineReasons \
		-textvariable [namespace current]::Priv(declineReason)
	ttk::button $ib.accept -text $mc::AcceptChallenge \
		-command [namespace code AcceptIncoming]
	ttk::button $ib.decline -text $mc::DeclineChallenge \
		-command [namespace code DeclineIncoming]
	grid $ib.label -row 0 -column 0 -columnspan 4 -sticky ew -pady {0 4}
	grid $ib.accept -row 1 -column 0 -sticky w -padx {0 4}
	grid $ib.decline -row 1 -column 1 -sticky w -padx {0 8}
	grid $ib.reasonLabel -row 1 -column 2 -sticky w -padx {0 4}
	grid $ib.reason -row 1 -column 3 -sticky w
	grid columnconfigure $ib 3 -weight 1

	# Left column: Lookup + Profile + Rating history canvas + Teams
	set left [ttk::frame $top.left]
	set right [ttk::frame $top.right]
	grid $left -row 1 -column 0 -sticky nsew -padx {0 6}
	grid $right -row 1 -column 1 -sticky nsew
	grid columnconfigure $top 0 -weight 3
	grid columnconfigure $top 1 -weight 2
	grid rowconfigure $top 1 -weight 1

	set lf [ttk::labelframe $left.lookup -text $mc::LookupGroup -padding 6]
	ttk::label $lf.ulabel -text $mc::UsernameLabel
	ttk::entry $lf.uentry -width 22 -textvariable [namespace current]::Priv(lookupUser)
	ttk::button $lf.ubtn -text $mc::Lookup -command [namespace code Lookup]
	bind $lf.uentry <Return> [namespace code Lookup]
	ttk::label $lf.profile -anchor w -justify left -wraplength 420 \
		-textvariable [namespace current]::Priv(profileText)
	grid $lf.ulabel -row 0 -column 0 -sticky w
	grid $lf.uentry -row 0 -column 1 -sticky ew -padx 4
	grid $lf.ubtn -row 0 -column 2 -sticky e
	grid $lf.profile -row 1 -column 0 -columnspan 3 -sticky ew -pady {6 0}
	grid columnconfigure $lf 1 -weight 1
	pack $lf -fill x -pady {0 6}

	set rf [ttk::labelframe $left.chart -text $mc::RatingChart -padding 6]
	canvas $rf.canvas -width 380 -height 150 -background white -highlightthickness 1 \
		-highlightbackground #cccccc
	pack $rf.canvas -fill both -expand yes
	pack $rf -fill both -expand yes -pady {0 6}
	set Priv(widget:canvas) $rf.canvas

	set tf [ttk::labelframe $left.teams -text $mc::TeamsGroup -padding 6]
	set tree [ttk::treeview $tf.tree -height 5 -selectmode browse \
		-columns {id name members} -show headings]
	$tree heading id -text "ID"
	$tree heading name -text "Team"
	$tree heading members -text "Members"
	$tree column id -width 100 -anchor w
	$tree column name -width 180 -stretch 1 -anchor w
	$tree column members -width 70 -anchor e
	bind $tree <<TreeviewSelect>> [namespace code SelectTeam]
	pack $tree -fill both -expand yes -pady {0 4}
	set Priv(widget:teams) $tree

	set tform [ttk::frame $tf.form]
	ttk::label $tform.idl -text $mc::TeamIdLabel
	ttk::entry $tform.ide -width 16 -textvariable [namespace current]::Priv(teamId)
	ttk::label $tform.msgl -text $mc::JoinMessageLabel
	ttk::entry $tform.msge -width 20 -textvariable [namespace current]::Priv(teamMessage)
	ttk::button $tform.join -text $mc::JoinTeam -command [namespace code JoinTeam]
	ttk::button $tform.leave -text $mc::LeaveTeam -command [namespace code LeaveTeam]
	grid $tform.idl -row 0 -column 0 -sticky w
	grid $tform.ide -row 0 -column 1 -sticky ew -padx 4
	grid $tform.msgl -row 1 -column 0 -sticky w -pady {4 0}
	grid $tform.msge -row 1 -column 1 -sticky ew -padx 4 -pady {4 0}
	grid $tform.join -row 2 -column 0 -sticky w -pady {4 0}
	grid $tform.leave -row 2 -column 1 -sticky w -padx 4 -pady {4 0}
	grid columnconfigure $tform 1 -weight 1
	pack $tform -fill x
	pack $tf -fill both -expand yes

	# Right column: Challenge player + Send message
	set cf [ttk::labelframe $right.challenge -text $mc::ChallengeGroup -padding 6]
	ttk::label $cf.minL -text $mc::Minutes
	ttk::spinbox $cf.min -from 0 -to 180 -width 5 \
		-textvariable [namespace current]::Priv(chMinutes)
	ttk::label $cf.incL -text $mc::IncrementSeconds
	ttk::spinbox $cf.inc -from 0 -to 60 -width 5 \
		-textvariable [namespace current]::Priv(chIncrement)
	ttk::label $cf.daysL -text $mc::CorrespondenceDays
	ttk::combobox $cf.days -width 5 -values {{} 1 2 3 5 7 10 14} \
		-textvariable [namespace current]::Priv(chDays)
	ttk::label $cf.varL -text $mc::Variant
	ttk::combobox $cf.var -state readonly -width 14 -values $Variants \
		-textvariable [namespace current]::Priv(chVariant)
	ttk::label $cf.colL -text $mc::Colour
	ttk::combobox $cf.col -state readonly -width 10 \
		-values [list $mc::Random $mc::White $mc::Black] \
		-textvariable [namespace current]::Priv(chColor)
	ttk::checkbutton $cf.rated -text $mc::RatedGame \
		-variable [namespace current]::Priv(chRated)
	ttk::button $cf.send -text $mc::SendChallenge \
		-command [namespace code Challenge]
	ttk::button $cf.cancel -text $mc::CancelOutgoing \
		-command [namespace code CancelChallenge]
	grid $cf.minL -row 0 -column 0 -sticky w
	grid $cf.min -row 0 -column 1 -sticky w -padx 4
	grid $cf.incL -row 1 -column 0 -sticky w -pady {4 0}
	grid $cf.inc -row 1 -column 1 -sticky w -padx 4 -pady {4 0}
	grid $cf.daysL -row 2 -column 0 -sticky w -pady {4 0}
	grid $cf.days -row 2 -column 1 -sticky w -padx 4 -pady {4 0}
	grid $cf.varL -row 3 -column 0 -sticky w -pady {4 0}
	grid $cf.var -row 3 -column 1 -sticky w -padx 4 -pady {4 0}
	grid $cf.colL -row 4 -column 0 -sticky w -pady {4 0}
	grid $cf.col -row 4 -column 1 -sticky w -padx 4 -pady {4 0}
	grid $cf.rated -row 5 -column 0 -columnspan 2 -sticky w -pady {4 0}
	grid $cf.send -row 6 -column 0 -sticky w -pady {6 0}
	grid $cf.cancel -row 6 -column 1 -sticky w -padx 4 -pady {6 0}
	grid columnconfigure $cf 1 -weight 1
	pack $cf -fill x -pady {0 6}

	set mf [ttk::labelframe $right.msg -text $mc::MessageGroup -padding 6]
	ttk::label $mf.lbl -text $mc::MessageLabel
	ttk::entry $mf.entry -width 28 -textvariable [namespace current]::Priv(messageText)
	ttk::button $mf.send -text $mc::SendMessage -command [namespace code SendMessage]
	bind $mf.entry <Return> [namespace code SendMessage]
	grid $mf.lbl -row 0 -column 0 -sticky w
	grid $mf.entry -row 1 -column 0 -sticky ew -pady 4
	grid $mf.send -row 2 -column 0 -sticky w
	grid columnconfigure $mf 0 -weight 1
	pack $mf -fill x

	ttk::label $tab.status -anchor w -justify left -wraplength 700 \
		-textvariable [namespace current]::Priv(statusText)
	pack $tab.status -side bottom -fill x -pady {6 0}
	set Priv(widget:status) $tab.status

	set cl [ttk::labelframe $right.lists -text $mc::ChallengesGroup -padding 6]
	ttk::button $cl.refresh -text $mc::RefreshChallenges -command [namespace code RefreshChallenges]
	pack $cl.refresh -anchor w
	foreach kind {in out} {
		set Priv(challenges:$kind) {}
		ttk::label $cl.$kind -justify left -wraplength 320 -textvariable [namespace current]::Priv(challenges:$kind)
		pack $cl.$kind -fill x
	}
	pack $cl -fill x
	RefreshIncomingBanner
	return $tab
}


proc ::lichess::social::Status {text} {
	variable Priv
	set Priv(statusText) $text
	::online::window::status $text
}


# ======================================================================
# User lookup, profile, rating-history canvas chart, and teams
# ======================================================================

proc ::lichess::social::Lookup {{username ""}} {
	variable Priv
	variable mc
	if {$username ne ""} { set Priv(lookupUser) $username }
	set name [string trim $Priv(lookupUser)]
	if {$name eq ""} {
		Status $mc::EnterUsername
		return 0
	}
	set Priv(userData) {}
	set Priv(profileText) {}
	set Priv(ratingHistory) {}
	set Priv(teams) {}
	set Priv(teamId) {}
	set Priv(missingUser) {}
	set Priv(ratingError) {}
	if {[info exists Priv(widget:teams)]} { ::lichess::ListMessage $Priv(widget:teams) {} 1 }
	DrawRatingChart
	Status [format $mc::LookingUp $name]
	::lichess::api::user $name [namespace code [list OnUser $name]]
	::lichess::api::ratingHistory $name [namespace code [list OnRatingHistory $name]]
	::lichess::api::teamsOf $name [namespace code [list OnTeams $name]]
	return 1
}


proc ::lichess::social::OnUser {name reply} {
	variable Priv
	variable mc
	# an answer for an earlier lookup must not replace the current one
	if {$name ne [string trim $Priv(lookupUser)]} { return }
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		set why [::lichess::ReplyError $reply]
		if {[dict exists $reply status] && [dict get $reply status] == 404} {
			set why [format $mc::UserNotFound $name]
			set Priv(missingUser) $name
			set Priv(userData) {}
			set Priv(ratingHistory) {}
			set Priv(teams) {}
			DrawRatingChart
			if {[info exists Priv(widget:teams)]} { ::lichess::ListMessage $Priv(widget:teams) {} 1 }
		}
		set Priv(profileText) $why
		Status $why
		return
	}
	set d [expr {[dict exists $reply data] ? [dict get $reply data] : $reply}]
	set Priv(userData) $d
	set uname [expr {[dict exists $d username] ? [dict get $d username] : $name}]
	set title [expr {[dict exists $d title] && [dict get $d title] ni {"" null} ? "[dict get $d title] " : ""}]
	set lines [list "${title}${uname}"]
	if {[dict exists $d perfs] && ![catch {dict size [dict get $d perfs]}]} {
		set ratings {}
		dict for {perf pdata} [dict get $d perfs] {
			if {![catch {dict exists $pdata rating}] && [dict exists $pdata rating]} {
				lappend ratings "${perf}: [dict get $pdata rating]"
			}
		}
		if {[llength $ratings]} {
			lappend lines "$mc::ProfileRatings [join $ratings {, }]"
		}
	}
	if {[dict exists $d profile bio] && [dict get $d profile bio] ne ""} {
		lappend lines [dict get $d profile bio]
	}
	set Priv(profileText) [join $lines "\n"]
	Status "${title}${uname}"
}


proc ::lichess::social::OnRatingHistory {name reply} {
	variable Priv
	if {$name ne [string trim $Priv(lookupUser)]} { return }
	if {[info exists Priv(missingUser)] && $Priv(missingUser) eq $name} { return }
	set Priv(ratingError) {}
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		set Priv(ratingHistory) {}
		set Priv(ratingError) [::lichess::ReplyError $reply]
		DrawRatingChart
		return
	}
	set Priv(ratingHistory) [expr {[dict exists $reply data] ? [dict get $reply data] : {}}]
	DrawRatingChart
}


proc ::lichess::social::DrawRatingChart {} {
	variable Priv
	variable mc
	if {![info exists Priv(widget:canvas)] || ![winfo exists $Priv(widget:canvas)]} { return }
	set c $Priv(widget:canvas)
	$c delete all

	set w [winfo width $c]
	set h [winfo height $c]
	if {$w < 50} { set w [$c cget -width] }
	if {$h < 50} { set h [$c cget -height] }

	if {[info exists Priv(ratingError)] && $Priv(ratingError) ne ""} {
		$c create text [expr {$w / 2}] [expr {$h / 2}] -text $Priv(ratingError) -width $w -tags error
		return
	}
	set series {}
	set seriesName ""
	foreach entry $Priv(ratingHistory) {
		if {[catch {dict exists $entry points}]} { continue }
		if {![dict exists $entry points]} { continue }
		set pts [dict get $entry points]
		if {[llength $pts] > [llength $series]} {
			set series $pts
			set seriesName [expr {[dict exists $entry name] ? [dict get $entry name] : ""}]
		}
	}
	if {![llength $series]} {
		$c create text [expr {$w / 2}] [expr {$h / 2}] -text $mc::NoRatingHistory \
			-fill #666666 -tags empty
		return
	}

	set ratings {}
	foreach pt $series {
		set r [lindex $pt 3]
		if {[string is integer -strict $r]} { lappend ratings $r }
	}
	if {![llength $ratings]} {
		$c create text [expr {$w / 2}] [expr {$h / 2}] -text $mc::NoRatingHistory \
			-fill #666666 -tags empty
		return
	}

	set minR [lindex $ratings 0]
	set maxR [lindex $ratings 0]
	foreach r $ratings {
		if {$r < $minR} { set minR $r }
		if {$r > $maxR} { set maxR $r }
	}
	set padL 42
	set padR 14
	set padT 22
	set padB 20
	set plotW [expr {max(20, $w - $padL - $padR)}]
	set plotH [expr {max(20, $h - $padT - $padB)}]
	set span [expr {max(10, $maxR - $minR)}]

	$c create text $padL 10 -anchor w -text "$seriesName ($minR–$maxR)" \
		-fill #222222 -tags title
	$c create line $padL $padT $padL [expr {$padT + $plotH}] \
		[expr {$padL + $plotW}] [expr {$padT + $plotH}] -fill #bbbbbb -tags axis
	$c create text [expr {$padL - 4}] $padT -anchor e -text $maxR -fill #555555 -tags label
	$c create text [expr {$padL - 4}] [expr {$padT + $plotH}] -anchor e -text $minR -fill #555555 -tags label

	set n [llength $ratings]
	set coords {}
	for {set i 0} {$i < $n} {incr i} {
		set r [lindex $ratings $i]
		set x [expr {$n == 1 ? $padL + $plotW / 2.0 : $padL + ($i * double($plotW) / ($n - 1))}]
		set y [expr {$padT + $plotH - (($r - $minR) * double($plotH) / $span)}]
		lappend coords $x $y
		$c create oval [expr {$x - 2}] [expr {$y - 2}] [expr {$x + 2}] [expr {$y + 2}] \
			-fill #1565c0 -outline #1565c0 -tags point
	}
	if {[llength $coords] >= 4} {
		$c create line {*}$coords -fill #1565c0 -width 2 -tags chartLine
	}
}


proc ::lichess::social::OnTeams {name reply} {
	variable mc
	variable Priv
	if {$name ne [string trim $Priv(lookupUser)]} { return }
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		if {[info exists Priv(widget:teams)]} {
			::lichess::ListMessage $Priv(widget:teams) [::lichess::ReplyError $reply] 1
		}
		return
	}
	if {[info exists Priv(missingUser)] && $Priv(missingUser) eq $name} { return }
	set Priv(teams) [expr {[dict exists $reply data] ? [dict get $reply data] : {}}]
	if {![info exists Priv(widget:teams)] || ![winfo exists $Priv(widget:teams)]} { return }
	set tree $Priv(widget:teams)
	$tree delete [$tree children {}]
	foreach team $Priv(teams) {
		if {[catch {dict size $team}]} { continue }
		set id [expr {[dict exists $team id] ? [dict get $team id] : ""}]
		set tname [expr {[dict exists $team name] ? [dict get $team name] : $id}]
		set members [expr {[dict exists $team nbMembers] ? [dict get $team nbMembers] : ""}]
		if {$id ne ""} {
			$tree insert {} end -id $id -values [list $id $tname $members]
		}
	}
	::lichess::ListResult $tree $mc::NoTeams
}


proc ::lichess::social::SelectTeam {} {
	variable Priv
	if {![info exists Priv(widget:teams)] || ![winfo exists $Priv(widget:teams)]} { return }
	set sel [$Priv(widget:teams) selection]
	if {[llength $sel]} {
		set Priv(teamId) [lindex $sel 0]
	}
}


proc ::lichess::social::JoinTeam {{teamId ""} {message ""}} {
	variable Priv
	variable mc
	if {$teamId ne ""} { set Priv(teamId) $teamId }
	if {$message ne ""} { set Priv(teamMessage) $message }
	set id [string trim $Priv(teamId)]
	if {$id eq ""} {
		Status $mc::EnterTeamId
		return 0
	}
	::lichess::api::joinTeam $id $Priv(teamMessage) [namespace code [list OnTeamJoined $id]]
	return 1
}


proc ::lichess::social::OnTeamJoined {id reply} {
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		Status [format $mc::TeamJoined $id]
	} else {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not join team."}]
	}
}


proc ::lichess::social::LeaveTeam {{teamId ""}} {
	variable Priv
	variable mc
	if {$teamId ne ""} { set Priv(teamId) $teamId }
	set id [string trim $Priv(teamId)]
	if {$id eq ""} {
		Status $mc::EnterTeamId
		return 0
	}
	::lichess::api::leaveTeam $id [namespace code [list OnTeamLeft $id]]
	return 1
}


proc ::lichess::social::OnTeamLeft {id reply} {
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		Status [format $mc::TeamLeft $id]
	} else {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not leave team."}]
	}
}


# ======================================================================
# Challenging a user & incoming challenge handling
# ======================================================================

proc ::lichess::social::Challenge {{user ""}} {
	variable Priv
	variable mc
	if {$user ne ""} { set Priv(lookupUser) $user }
	set target [string trim $Priv(lookupUser)]
	if {$target eq ""} {
		Status $mc::EnterUsername
		return 0
	}
	set minutes [expr {[string is integer -strict $Priv(chMinutes)] ? $Priv(chMinutes) : 10}]
	set increment [expr {[string is integer -strict $Priv(chIncrement)] ? $Priv(chIncrement) : 0}]
	set rated [expr {$Priv(chRated) ? 1 : 0}]
	set color [expr {$Priv(chColor) in {white black random} ? $Priv(chColor) : "random"}]
	set variant [expr {$Priv(chVariant) ne "" ? $Priv(chVariant) : "standard"}]
	set days [string trim $Priv(chDays)]
	Status [format $mc::Challenging $target]
	::lichess::api::challengeUser $target $minutes $increment $rated $color $variant $days \
		[namespace code OnChallengeSent]
	return 1
}


proc ::lichess::social::OnChallengeSent {reply} {
	variable Priv
	variable mc
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Challenge failed."}]
		return
	}
	set d [expr {[dict exists $reply data] ? [dict get $reply data] : $reply}]
	if {[dict exists $d challenge] && [dict exists $d challenge id]} {
		set id [dict get $d challenge id]
	} elseif {[dict exists $d id]} {
		set id [dict get $d id]
	} else {
		set id ""
	}
	set Priv(outgoingId) $id
	Status [format $mc::ChallengeSent $id]
}


proc ::lichess::social::CancelChallenge {{id ""}} {
	variable Priv
	variable mc
	if {$id eq ""} { set id $Priv(outgoingId) }
	if {$id eq ""} { return 0 }
	::lichess::api::cancelChallenge $id [namespace code [list OnChallengeCancelled $id]]
	return 1
}


proc ::lichess::social::OnChallengeCancelled {id reply} {
	variable Priv
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		if {$Priv(outgoingId) eq $id} { set Priv(outgoingId) {} }
		Status $mc::OutgoingCancelled
	} else {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not cancel challenge."}]
	}
}


# Hooked from ::lichess::OnEvent for challenge / challengeCanceled / challengeDeclined
proc ::lichess::social::OnEvent {event} {
	variable Priv
	variable mc
	if {![dict exists $event type]} { return }
	set ch [expr {[dict exists $event challenge] ? [dict get $event challenge] : $event}]
	set id [expr {[dict exists $ch id] ? [dict get $ch id] : ""}]
	switch -- [dict get $event type] {
		challenge {
			set Priv(incoming) $ch
			set Priv(incomingId) $id
			RefreshIncomingBanner
			set who [ChallengerName $ch]
			set desc [ChallengeSummary $ch]
			Status [format $mc::IncomingChallenge $who $desc]
		}
		challengeCanceled {
			if {$id eq "" || $id eq $Priv(incomingId)} {
				set Priv(incoming) {}
				set Priv(incomingId) {}
				RefreshIncomingBanner
			}
			Status [format $mc::ChallengeCancelled $id]
		}
		challengeDeclined {
			if {$id eq $Priv(outgoingId)} { set Priv(outgoingId) {} }
			Status [format $mc::ChallengeDeclined $id]
		}
	}
}


proc ::lichess::social::ChallengerName {ch} {
	if {[dict exists $ch challenger name]} { return [dict get $ch challenger name] }
	if {[dict exists $ch challenger id]} { return [dict get $ch challenger id] }
	return "?"
}


proc ::lichess::social::ChallengeSummary {ch} {
	set parts {}
	if {[dict exists $ch variant name]} {
		lappend parts [dict get $ch variant name]
	} elseif {[dict exists $ch variant key]} {
		lappend parts [dict get $ch variant key]
	}
	if {[dict exists $ch timeControl show]} {
		lappend parts [dict get $ch timeControl show]
	} elseif {[dict exists $ch speed]} {
		lappend parts [dict get $ch speed]
	}
	if {[dict exists $ch rated]} {
		lappend parts [expr {[dict get $ch rated] ? "rated" : "casual"}]
	}
	return [expr {[llength $parts] ? [join $parts ", "] : "challenge"}]
}


proc ::lichess::social::RefreshIncomingBanner {} {
	variable Priv
	variable mc
	if {![info exists Priv(widget:incoming)] || ![winfo exists $Priv(widget:incoming)]} { return }
	set ib $Priv(widget:incoming)
	if {$Priv(incomingId) eq ""} {
		grid remove $ib
		return
	}
	set who [ChallengerName $Priv(incoming)]
	set desc [ChallengeSummary $Priv(incoming)]
	$ib.label configure -text [format $mc::IncomingChallenge $who $desc]
	grid $ib -row 0 -column 0 -columnspan 2 -sticky ew -pady {0 6}
}


proc ::lichess::social::AcceptIncoming {{id ""}} {
	variable Priv
	if {$id eq ""} { set id $Priv(incomingId) }
	if {$id eq ""} { return 0 }
	::lichess::api::acceptChallenge $id [namespace code [list OnIncomingAccepted $id]]
	return 1
}


proc ::lichess::social::OnIncomingAccepted {id reply} {
	variable Priv
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		if {$Priv(incomingId) eq $id} {
			set Priv(incoming) {}
			set Priv(incomingId) {}
			RefreshIncomingBanner
		}
		Status [format $mc::ChallengeAccepted $id]
	} else {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not accept challenge."}]
	}
}


proc ::lichess::social::DeclineIncoming {{id ""} {reason ""}} {
	variable Priv
	if {$id eq ""} { set id $Priv(incomingId) }
	if {$id eq ""} { return 0 }
	if {$reason eq ""} { set reason $Priv(declineReason) }
	if {$reason eq ""} { set reason generic }
	::lichess::api::declineChallenge $id $reason [namespace code [list OnIncomingDeclined $id]]
	return 1
}


proc ::lichess::social::OnIncomingDeclined {id reply} {
	variable Priv
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		if {$Priv(incomingId) eq $id} {
			set Priv(incoming) {}
			set Priv(incomingId) {}
			RefreshIncomingBanner
		}
		Status [format $mc::ChallengeDeclined $id]
	} else {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not decline challenge."}]
	}
}


# ======================================================================
# Private messaging
# ======================================================================

proc ::lichess::social::SendMessage {{user ""} {text ""}} {
	variable Priv
	variable mc
	if {$user ne ""} { set Priv(lookupUser) $user }
	if {$text ne ""} { set Priv(messageText) $text }
	set target [string trim $Priv(lookupUser)]
	set msg [string trim $Priv(messageText)]
	if {$target eq ""} {
		Status $mc::EnterUsername
		return 0
	}
	if {$msg eq ""} {
		Status $mc::EnterMessage
		return 0
	}
	set Priv(messageText) {}
	::lichess::api::sendMessage $target $msg [namespace code [list OnMessageSent $target $msg]]
	return 1
}


proc ::lichess::social::OnMessageSent {target msg reply} {
	variable Priv
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		Status [format $mc::MessageSent $target]
	} else {
		# give the unsent text back
		if {$Priv(messageText) eq ""} { set Priv(messageText) $msg }
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not send message."}]
	}
}

# vi:set ts=3 sw=3:

proc ::lichess::social::RefreshChallenges {} {
 ::lichess::api::Request GET /api/challenge {} [namespace code OnChallenges]
}
proc ::lichess::social::OnChallenges {reply} {
 variable Priv
 variable mc
 foreach kind {in out} empty [list $mc::NoIncoming $mc::NoOutgoing] {
  if {![dict exists $reply ok] || ![dict get $reply ok]} {
   set Priv(challenges:$kind) [::lichess::ReplyError $reply]
   continue
  }
  set lines {}
  if {[dict exists $reply data $kind]} {
   foreach challenge [dict get $reply data $kind] {
    if {[dict exists $challenge id]} { lappend lines [dict get $challenge id] }
   }
  }
  set Priv(challenges:$kind) [expr {[llength $lines] ? [join $lines "\n"] : $empty}]
 }
}
