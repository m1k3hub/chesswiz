# ======================================================================
# AI: event-type bucketing (System One)
# ======================================================================
# A game's kind of time control, from its PGN tags: a deterministic rule
# first (parse TimeControl, then the Event/Site/Round words), and the
# bounded classifier only for the games the rule cannot place. The result
# is a count per class over the latest games of the active database (or a
# player's games); nothing is written.
#
# Firewall: this only buckets *time controls*; it never speaks about the
# board. With no classifier the rule alone answers (and anything it cannot
# place is "unclear"), so the feature degrades to a deterministic report.
# ======================================================================

namespace eval ::ai::event {
	variable Classes {classical rapid blitz bullet correspondence simul training unclear}

	# The classifier's answer set (choice criteria name -> description).
	variable Criteria [dict create \
		classical      "a slow game, at least 30 minutes per side" \
		rapid          "about 10 to 30 minutes per side" \
		blitz          "about 3 to 10 minutes per side" \
		bullet         "under 3 minutes per side" \
		correspondence "played over days (ICCF, XFCC, email)" \
		simul          "a simultaneous exhibition" \
		training       "a training or puzzle game" \
		unclear        "the tags do not say"]

	variable Priv
}

# The state string handed to the classifier: the tags that can say what
# kind of game it is. Two games from the same event share it, so the
# classifier is asked once per distinct event, not once per game.
proc ::ai::event::State {tags} {
	set parts {}
	foreach key {Event Site Round TimeControl} {
		if {[dict exists $tags $key] && [string length [dict get $tags $key]]} {
			lappend parts "$key=[dict get $tags $key]"
		}
	}
	if {![llength $parts]} {
		foreach key {White Black Result} {
			if {[dict exists $tags $key]} { lappend parts "$key=[dict get $tags $key]" }
		}
	}
	return [join $parts " "]
}

# The base time of a TimeControl string in seconds, or "".
# "300+0" -> 300, "40/7200:1800" -> 7200, "1800+30" -> 1800.
proc ::ai::event::BaseSeconds {tc} {
	if {$tc eq "" || $tc eq "-"} { return "" }
	set first [lindex [split $tc :] 0]
	if {[regexp {^[0-9]+/([0-9]+)} $first -> secs]} { return $secs }
	if {[regexp {^([0-9]+)} $first -> secs]} { return $secs }
	return ""
}

# The deterministic bucket, or "" when the tags do not decide.
proc ::ai::event::Rule {tags} {
	set tc [expr {[dict exists $tags TimeControl] ? [dict get $tags TimeControl] : ""}]
	set secs [BaseSeconds $tc]
	if {$secs ne ""} {
		if {$secs < 180}  { return bullet }
		if {$secs < 600}  { return blitz }
		if {$secs < 1800} { return rapid }
		return classical
	}

	set text {}
	foreach key {Event Site Round} {
		if {[dict exists $tags $key]} { lappend text [dict get $tags $key] }
	}
	set text [string tolower [join $text " "]]
	if {$text eq ""} { return "" }

	if {[regexp {\ybullet\y} $text]}              { return bullet }
	if {[regexp {\yblitz\y} $text]}               { return blitz }
	if {[regexp {\yrapid\y} $text]}               { return rapid }
	if {[regexp {\y(classical|standard|long)\y} $text]} { return classical }
	if {[regexp {\y(correspondence|iccf|xfcc)\y} $text]} { return correspondence }
	if {[regexp {\ysimul} $text]}                 { return simul }
	if {[regexp {\y(training|puzzle|tactic)\y} $text]} { return training }
	return ""
}

proc ::ai::event::Unknown {} {
	return unclear
}


# The deterministic bucket of each game, as a class -> count dict. Used where
# the caller is synchronous (the study plan report) and no classifier is
# available; games the rule cannot place count as "unclear".
proc ::ai::event::RuleMix {base variant numbers} {
	set classes {}
	foreach c $::ai::event::Classes { dict set classes $c 0 }

	foreach number $numbers {
		set tags {}
		catch { foreach pair [::scidb::db::get tags $number $base $variant] { dict set tags {*}$pair } }
		set class [Rule $tags]
		if {$class eq ""} { set class unclear }
		dict incr classes $class
	}
	return $classes
}


# The tags of the latest games of the active database (or of a player).
# Returns a list of {number tags}.
proc ::ai::event::GamesToProfile {base variant player max} {
	set criteria {}
	if {[string length $player]} {
		lassign [::application::assistant::ResolvePlayer $base $variant $player] _ name
		set criteria [dict create player $name]
		set criteria [dict get [::application::assistant::CheckArgs search_games $criteria] criteria]
	}

	set query {}
	if {[dict size $criteria]} {
		lassign [::application::assistant::BuildQuery $base $variant $criteria] query
	}

	set view [::scidb::view::new $base $variant unused unused unused unused master slave]
	set games {}
	catch {
		# with no query, resetting the view selects every game
		if {[dict size $criteria]} {
			::scidb::view::search $base $variant $view null none $query
		} else {
			::scidb::view::search $base $variant $view reset none
		}
		set count [::scidb::view::count games $base $variant $view]
		for {set row [expr {$count > $max ? $count - $max : 0}]} {$row < $count} {incr row} {
			set number [::scidb::db::get gameNumber $base $variant $row $view]
			set tags {}
			foreach pair [::scidb::db::get tags $number $base $variant] { dict set tags {*}$pair }
			lappend games [list $number $tags]
		}
	}
	catch { ::scidb::view::close $base $variant $view }
	return $games
}


# Run the profile. -done is called with the dict
# {games N classes {class count} classified {state class} source {text/classifier}}
# once the (deduplicated) classifier pass has finished.
proc ::ai::event::profile {base variant args} {
	variable Priv

	array set opts {-player "" -games 500 -done {}}
	array set opts $args

	set games [GamesToProfile $base $variant $opts(-player) $opts(-games)]

	set classes {}
	foreach c $::ai::event::Classes { dict set classes $c 0 }

	set byGame {}
	set unclear {}

	foreach g $games {
		lassign $g number tags
		set state [State $tags]
		set class [Rule $tags]
		if {$class eq ""} { lappend unclear $state }
		lappend byGame [list $number $state $class]
	}

	set unique {}
	foreach s $unclear { if {$s ni $unique} { lappend unique $s } }

	set Priv(classes) $classes
	set Priv(byGame) $byGame
	set Priv(games) [llength $games]

	Classify $unique 0 {} $opts(-done)
	return
}


proc ::ai::event::Classify {states index map done} {
	if {$index >= [llength $states]} {
		# always resolve asynchronously: a caller may have registered -done
		# before it can be called (the assistant resolves a pending token)
		after 0 [list ::ai::event::Finish $map $done]
		return
	}

	set state [lindex $states $index]
	set question [dict create type choice \
		instructions "Which kind of chess game is this, judging only from its PGN tags?" \
		criteria $::ai::event::Criteria]

	::ai::decide event_type $state $question \
		[namespace code [list OnClassified $states $index $map $done]] \
		-fallback [namespace code Unknown]
	return
}


proc ::ai::event::OnClassified {states index map done decision} {
	set state [lindex $states $index]
	set label unclear
	if {[dict get $decision ok]} {
		set label [dict get $decision label]
		if {$label ni $::ai::event::Classes} { set label unclear }
	}
	dict set map $state $label
	Classify $states [expr {$index + 1}] $map $done
	return
}


proc ::ai::event::Finish {map done} {
	variable Priv

	set classes $Priv(classes)
	set classified {}

	foreach g $Priv(byGame) {
		lassign $g number state class
		if {$class eq ""} {
			set class [expr {[dict exists $map $state] ? [dict get $map $state] : "unclear"}]
			lappend classified [list $state $class]
		}
		dict incr classes $class
	}

	set profile [dict create games $Priv(games) classes $classes classified $classified]

	if {[llength $done]} { uplevel #0 [list {*}$done $profile] }
	return $profile
}


# The profile as one line, e.g.
# "Time controls of 500 game(s): classical 120, rapid 40, blitz 330, bullet 10."
proc ::ai::event::ProfileText {profile} {
	set parts {}
	foreach c {classical rapid blitz bullet correspondence simul training unclear} {
		set n [dict get [dict get $profile classes] $c]
		if {$n > 0} { lappend parts "$c $n" }
	}
	if {![llength $parts]} { return "" }
	return "Time controls of [dict get $profile games] game(s): [join $parts {, }]."
}


# ======================================================================
# The report surface: Extras -> AI: Time Controls
# ======================================================================
proc ::ai::event::report {parent args} {
	lassign [::application::assistant::ActiveBase] base variant
	if {$base eq ""} { return "" }

	Show $parent "<p>Reading the games...</p>"
	profile $base $variant {*}$args -done [namespace code [list OnReport $parent]]
	return
}


proc ::ai::event::OnReport {parent profile} {
	Show $parent "<p><b>Time controls</b></p><pre>[::application::ai::escape [ProfileText $profile]]</pre>"
	return
}


proc ::ai::event::Show {parent html} {
	if {[llength [info commands ::application::ai::showReport]]} {
		catch { ::application::ai::showReport $parent "AI: time controls" \
			[::application::ai::htmlData $html] }
	}
	return
}

# vi:set ts=3 sw=3:
