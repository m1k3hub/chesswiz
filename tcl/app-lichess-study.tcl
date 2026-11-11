# ======================================================================
# ::application::lichess::study -- import from and export to Lichess studies.
#
# A Lichess study is a collection of chapters (annotated games or
# positions) at lichess.org/study/<study-id>[/<chapter-id>]. The public
# PGN endpoint is the same source the Download Games dialog uses:
#
#   https://lichess.org/api/study/<study-id>.pgn
#   https://lichess.org/api/study/<study-id>/<chapter-id>.pgn
#
# Import is a source in the Download Games dialog (app-download-games);
# the helpers here parse the links/ids and build the request URLs. The
# dialog's existing Lichess token handling sends the Bearer header.
#
# Export uploads a PGN (a database view or the current game) to a study
# the user owns:
#
#   POST https://lichess.org/api/study/<study-id>/import-pgn
#
# The upload is multipart/form-data with the PGN as the "pgn" file field
# (and an optional "name" chapter name). It needs a personal API token
# with the study:write scope, because it writes to the user's account.
# The same token option as the download dialog is used, so a token only
# has to be entered once.
#
#   ::application::lichess::study::open $parent ?-base B? ?-variant V?
#       ?-view N? ?-kind database|game?
#
# The pure helpers (spec, specs, pgnUrl, importUrl, fileName, label,
# importRequest, errorText, responseChapter) are UI-free and covered by
# tests/test_app_lichess_study.tcl.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-lichess-study
}

package require Tcl 8.5
package require Tk 8.5

namespace eval application {
namespace eval lichess {
namespace eval study {
namespace eval mc {

set Title					"Upload to Lichess study"
set TitleGame				"Upload Game to Lichess Study"
set TitleDatabase			"Upload Database to Lichess Study"
set Source					"Source"
set Study					"Study:"
set StudyDetail				"Study link or id (lichess.org/study/<id>), optionally with a chapter id:"
set OptionalName			"Chapter name (optional):"
set Token					"Lichess API token (study:write):"
set Upload					"Upload"
set Close					"Close"
set Cancel					"Cancel"
set Uploading				"Uploading to Lichess..."
set Uploaded				"Uploaded: %s"
set NoStudy					"no valid Lichess study link or id given"
set NoGame					"no game is loaded"
set NoGames					"no games in this database"
set NeedToken				"A Lichess API token with the study:write scope is needed. Create one at lichess.org/account/oauth/token and enter it here."
set NeedScope				"Lichess refused the upload. The token needs the study:write scope (lichess.org/account/oauth/token)."
set NotFound				"The study was not found, or the token is not allowed to write to it."
set Rejected				"Lichess rejected the PGN: %s"
set Failed					"Upload failed (%s)"
set GameSource				"Current game"
set DatabaseSource			"Database '%s'"
set UserStudies				"My Lichess studies"
set UserLabel				"Lichess username:"
set LoadStudies				"Load studies"
set NewStudyGroup			"Create new study"
set NewStudyName			"Study name:"
set VisibilityLabel			"Visibility:"
set CreateStudy				"Create study"
set StudyCreated			"Created study %s (%s)."
set OrientationLabel		"Orientation:"
set VariantLabel			"Variant:"

} ;# namespace mc

array set Options {
	token	""
}

variable Timeout 120000

array set Priv {
	dialog			{}
	parent			{}
	base			""
	variant			"Normal"
	view			0
	kind			"database"
	running			0
	user			""
	studies			{}
	study			""
	name			""
	orientation		"white"
	studyVariant	"standard"
	newStudyName	""
	visibility		"unlisted"
	statusText		""
}

} ;# namespace study
} ;# namespace lichess
} ;# namespace application


# ----------------------------------------------------------------------
# Pure helpers (UI-free; covered by tests/test_app_lichess_study.tcl).
# ----------------------------------------------------------------------

# One study link or id as {id chapter}. A chapter may be empty.
proc ::application::lichess::study::spec {text} {
	set text [string trim $text]
	if {$text eq ""} { return {} }
	if {[regexp {(?:https?://)?(?:www\.)?lichess\.org/(?:api/)?study/([A-Za-z0-9]{8})(?:/([A-Za-z0-9]{8}))?} $text _ id chapter]} {
		return [list $id $chapter]
	}
	if {[regexp {^(?:study/)?([A-Za-z0-9]{8})(?:/([A-Za-z0-9]{8}))?$} $text _ id chapter]} {
		return [list $id $chapter]
	}
	return {}
}


# Study specs out of free text, one per line, also space, comma or
# semicolon separated; duplicates are removed.
proc ::application::lichess::study::specs {text} {
	set specs {}
	foreach chunk [split $text "\n, \t;"] {
		set chunk [string trim $chunk]
		if {$chunk eq ""} { continue }
		set entry [spec $chunk]
		if {[llength $entry] && $entry ni $specs} {
			lappend specs $entry
		}
	}
	return $specs
}


proc ::application::lichess::study::pgnUrl {id {chapter ""}} {
	if {$chapter eq ""} {
		return "https://lichess.org/api/study/$id.pgn"
	}
	return "https://lichess.org/api/study/$id/$chapter.pgn"
}


proc ::application::lichess::study::importUrl {id} {
	return "https://lichess.org/api/study/$id/import-pgn"
}


proc ::application::lichess::study::fileName {id {chapter ""}} {
	if {$chapter eq ""} {
		return "lichess-study-$id.pgn"
	}
	return "lichess-study-$id-$chapter.pgn"
}


proc ::application::lichess::study::label {id {chapter ""}} {
	set label "lichess.org/study/$id"
	if {$chapter ne ""} { append label "/$chapter" }
	return $label
}


# A POST-ready multipart/form-data request as a dict:
#   url method headers contentType body
# The boundary can be given for deterministic tests.
proc ::application::lichess::study::importRequest {id pgn {token ""} {name ""} {boundary ""}} {
	if {$boundary eq ""} {
		set boundary "----chesswiz-[pid]-[clock microseconds]"
	}
	set eol "\r\n"
	set body ""

	if {$name ne ""} {
		append body "--$boundary$eol"
		append body "Content-Disposition: form-data; name=\"name\"$eol$eol"
		append body "$name$eol"
	}

	append body "--$boundary$eol"
	append body "Content-Disposition: form-data; name=\"pgn\"; filename=\"import.pgn\"$eol"
	append body "Content-Type: application/x-chess-pgn$eol$eol"
	append body $pgn
	append body $eol
	append body "--$boundary--$eol"

	set headers [list Accept application/json]
	if {$token ne ""} {
		lappend headers Authorization "Bearer $token"
	}
	# http writes -query to a binary socket, so send UTF-8 bytes.
	return [dict create \
		url         [importUrl $id] \
		method      POST \
		headers     $headers \
		contentType "multipart/form-data; boundary=$boundary" \
		body        [encoding convertto utf-8 $body] \
	]
}


# The error message for a failed upload response. The body is parsed for
# Lichess's JSON {"error": "..."} when possible.
proc ::application::lichess::study::errorText {code {body ""}} {
	variable mc
	switch -- $code {
		401 - 403 { return $mc::NeedScope }
		404       { return $mc::NotFound }
		400 {
			set detail [ErrorDetail $body]
			if {$detail ne ""} { return [format $mc::Rejected $detail] }
		}
	}
	return [format $mc::Failed $code]
}


proc ::application::lichess::study::ErrorDetail {body} {
	if {$body eq ""} { return "" }
	if {[catch { package require json }]} { return "" }
	if {[catch { set data [json::json2dict $body] }]} { return "" }
	if {[dict exists $data error]} { return [dict get $data error] }
	return ""
}


# The chapter id in a successful import response, or "".
proc ::application::lichess::study::responseChapter {body} {
	if {$body eq ""} { return "" }
	if {[catch { package require json }]} { return "" }
	if {[catch { set data [json::json2dict $body] }]} { return "" }
	if {[dict exists $data id]} { return [dict get $data id] }
	return ""
}


# ----------------------------------------------------------------------
# The upload dialog.
# ----------------------------------------------------------------------

proc ::application::lichess::study::open {parent args} {
	variable Priv
	variable mc

	set base ""
	set variant "Normal"
	set view 0
	set kind "database"

	foreach {option value} $args {
		switch -- $option {
			-base    { set base $value }
			-variant { set variant $value }
			-view    { set view $value }
			-kind    { set kind $value }
			default  { error "unknown option '$option'" }
		}
	}

	set dlg $parent.__lichess_study__
	if {[winfo exists $dlg]} {
		raise $dlg
		return $dlg
	}

	set Priv(parent)  $parent
	set Priv(base)    $base
	set Priv(variant) $variant
	set Priv(view)    $view
	set Priv(kind)    $kind
	set Priv(dialog)  $dlg
	set Priv(running) 0

	toplevel $dlg -class Scidb
	wm title $dlg [expr {$kind eq "game" ? $mc::TitleGame : $mc::TitleDatabase}]
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code Close]
	bind $dlg <Escape> [namespace code Close]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	set source [ttk::labelframe $top.source -text " $mc::Source " -padding $::theme::padx]
	if {$kind eq "game"} {
		set sourceName $mc::GameSource
	} else {
		set sourceName [format $mc::DatabaseSource [::util::databaseName $base no]]
	}
	ttk::label $source.value -text $sourceName
	pack $source.value -anchor w
	pack $source -fill x

	set target [ttk::labelframe $top.target -text " $mc::Study " -padding $::theme::padx]

	# User studies browser (studiesOf)
	set uframe [ttk::frame $target.uframe]
	ttk::label $uframe.ulbl -text $mc::UserLabel
	ttk::entry $uframe.uentry -width 18 -textvariable [namespace current]::Priv(user)
	ttk::button $uframe.load -text $mc::LoadStudies -command [namespace code LoadStudies]
	pack $uframe.ulbl -side left
	pack $uframe.uentry -side left -padx 4
	pack $uframe.load -side left
	pack $uframe -fill x -pady [list 0 $::theme::pady]

	set stree [ttk::treeview $target.studies -height 4 -selectmode browse \
		-columns {id name} -show headings]
	$stree heading id -text "ID"
	$stree heading name -text "Study"
	$stree column id -width 95 -anchor w
	$stree column name -width 260 -stretch 1 -anchor w
	bind $stree <<TreeviewSelect>> [namespace code OnSelectStudy]
	pack $stree -fill both -expand yes -pady [list 0 $::theme::pady]
	set Priv(widget:studies) $stree

	# Create new study section (studyCreate)
	set cframe [ttk::labelframe $target.create -text " $mc::NewStudyGroup " -padding 4]
	ttk::label $cframe.nlbl -text $mc::NewStudyName
	ttk::entry $cframe.nentry -width 20 -textvariable [namespace current]::Priv(newStudyName)
	ttk::label $cframe.vlbl -text $mc::VisibilityLabel
	ttk::combobox $cframe.vcombo -state readonly -width 10 \
		-values {public unlisted private} \
		-textvariable [namespace current]::Priv(visibility)
	ttk::button $cframe.btn -text $mc::CreateStudy -command [namespace code CreateStudy]
	grid $cframe.nlbl -row 0 -column 0 -sticky w
	grid $cframe.nentry -row 0 -column 1 -sticky ew -padx 4
	grid $cframe.vlbl -row 0 -column 2 -sticky w -padx {4 0}
	grid $cframe.vcombo -row 0 -column 3 -sticky w -padx 4
	grid $cframe.btn -row 0 -column 4 -sticky e
	grid columnconfigure $cframe 1 -weight 1
	pack $cframe -fill x -pady [list 0 $::theme::pady]

	ttk::label $target.detail -text $mc::StudyDetail -wraplength 420 -justify left
	ttk::entry $target.entry -textvariable [namespace current]::Priv(study)
	ttk::label $target.lname -text $mc::OptionalName
	ttk::entry $target.name -textvariable [namespace current]::Priv(name)

	set opts [ttk::frame $target.opts]
	ttk::label $opts.olbl -text $mc::OrientationLabel
	ttk::combobox $opts.ocombo -state readonly -width 8 \
		-values {white black} \
		-textvariable [namespace current]::Priv(orientation)
	ttk::label $opts.vlbl -text $mc::VariantLabel
	ttk::combobox $opts.vcombo -state readonly -width 14 \
		-values {standard chess960 crazyhouse antichess atomic horde kingOfTheHill racingKings threeCheck fromPosition} \
		-textvariable [namespace current]::Priv(studyVariant)
	pack $opts.olbl -side left
	pack $opts.ocombo -side left -padx 4
	pack $opts.vlbl -side left -padx {8 0}
	pack $opts.vcombo -side left -padx 4

	ttk::label $target.ltoken -text $mc::Token
	ttk::entry $target.token -show * -width 40 -textvariable [TokenVar]
	pack $target.detail -anchor w -pady [list 0 $::theme::pady]
	pack $target.entry -fill x
	pack $target.lname -anchor w -pady [list $::theme::pady 0]
	pack $target.name -fill x
	pack $opts -fill x -pady [list $::theme::pady 0]
	pack $target.ltoken -anchor w -pady [list $::theme::pady 0]
	pack $target.token -fill x
	pack $target -fill x -pady [list $::theme::pady 0]

	if {$Priv(user) eq "" && [info exists ::lichess::Priv(username)] && $::lichess::Priv(username) ne ""} {
		set Priv(user) $::lichess::Priv(username)
	}
	if {$Priv(user) ne "" && [llength [info commands ::lichess::api::studiesOf]]} {
		LoadStudies
	}

	ttk::label $top.status -wraplength 440 -justify left
	pack $top.status -fill x
	set Priv(status) $top.status

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -text $mc::Upload -command [namespace code Upload]
	$dlg.cancel configure -text $mc::Cancel -command [namespace code Close]

	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	focus $target.entry
	return $dlg
}


proc ::application::lichess::study::Close {} {
	variable Priv

	if {[string length $Priv(dialog)] && [winfo exists $Priv(dialog)]} {
		destroy $Priv(dialog)
	}
	set Priv(dialog) {}
	return
}


proc ::application::lichess::study::DialogExists {} {
	variable Priv
	return [expr {[string length $Priv(dialog)] && [winfo exists $Priv(dialog)]}]
}


proc ::application::lichess::study::Status {text} {
	variable Priv
	set Priv(statusText) $text
	if {[DialogExists]} {
		$Priv(status) configure -text $text
	}
	return
}


# ----------------------------------------------------------------------
# Study list (studiesOf), creation (studyCreate), and import (studyImportPgn)
# ----------------------------------------------------------------------

proc ::application::lichess::study::LoadStudies {{user ""}} {
	variable Priv
	if {$user ne ""} { set Priv(user) $user }
	set u [string trim $Priv(user)]
	if {$u eq "" || ![llength [info commands ::lichess::api::studiesOf]]} { return 0 }
	::lichess::api::studiesOf $u [namespace code OnStudiesLoaded]
	return 1
}


proc ::application::lichess::study::OnStudiesLoaded {reply} {
	variable Priv
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not load studies."}]
		return
	}
	set items [expr {[dict exists $reply data] ? [dict get $reply data] : {}}]
	set Priv(studies) $items
	if {[info exists Priv(widget:studies)] && [winfo exists $Priv(widget:studies)]} {
		set tree $Priv(widget:studies)
		$tree delete [$tree children {}]
		foreach item $items {
			if {[catch {dict size $item}]} { continue }
			set id [expr {[dict exists $item id] ? [dict get $item id] : ""}]
			if {$id eq ""} { continue }
			set name [expr {[dict exists $item name] ? [dict get $item name] : $id}]
			if {![$tree exists $id]} {
				$tree insert {} end -id $id -values [list $id $name]
			}
			if {$Priv(study) eq ""} { set Priv(study) $id }
		}
	}
}


proc ::application::lichess::study::OnSelectStudy {} {
	variable Priv
	if {![info exists Priv(widget:studies)] || ![winfo exists $Priv(widget:studies)]} { return }
	set sel [$Priv(widget:studies) selection]
	if {[llength $sel]} {
		set Priv(study) [lindex $sel 0]
	}
}


proc ::application::lichess::study::CreateStudy {{name ""} {visibility ""}} {
	variable Priv
	if {$name ne ""} { set Priv(newStudyName) $name }
	if {$visibility ne ""} { set Priv(visibility) $visibility }
	set sname [string trim $Priv(newStudyName)]
	set vis [expr {$Priv(visibility) in {public unlisted private} ? $Priv(visibility) : "unlisted"}]
	if {$sname eq "" || ![llength [info commands ::lichess::api::studyCreate]]} { return 0 }
	::lichess::api::studyCreate $sname $vis [namespace code [list OnStudyCreated $sname]]
	return 1
}


proc ::application::lichess::study::OnStudyCreated {fallbackName reply} {
	variable Priv
	variable mc
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not create study."}]
		return
	}
	set d [expr {[dict exists $reply data] ? [dict get $reply data] : $reply}]
	set id [expr {[dict exists $d id] ? [dict get $d id] : ""}]
	set name [expr {[dict exists $d name] && [dict get $d name] ne "" ? [dict get $d name] : $fallbackName}]
	if {$id ne ""} {
		set Priv(study) $id
		lappend Priv(studies) [dict create id $id name $name]
		if {[info exists Priv(widget:studies)] && [winfo exists $Priv(widget:studies)]} {
			set tree $Priv(widget:studies)
			if {![$tree exists $id]} {
				$tree insert {} end -id $id -values [list $id $name]
			}
		}
	}
	Status [format $mc::StudyCreated $name $id]
}


proc ::application::lichess::study::SendPgnToStudy {studyId name pgn {orientation white} {variant standard} {token {}}} {
	variable Priv
	variable mc
	set Priv(running) 1
	Status $mc::Uploading
	::lichess::api::studyImportPgn $studyId $name $pgn $orientation $variant \
		[namespace code [list OnApiUploaded $studyId]] $token
	return 1
}


proc ::application::lichess::study::OnApiUploaded {id reply} {
	variable Priv
	variable mc
	set Priv(running) 0
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		set msg [expr {[dict exists $reply error] && [dict get $reply error] ne "" ? \
			[dict get $reply error] : [errorText [expr {[dict exists $reply status] ? [dict get $reply status] : 0}] ""]}]
		Status $msg
		if {[DialogExists]} {
			$Priv(dialog).ok configure -state normal
			$Priv(dialog).cancel configure -state normal
		}
		return
	}
	set d [expr {[dict exists $reply data] ? [dict get $reply data] : $reply}]
	set chapter ""
	if {![catch {dict size $d}]} {
		if {[dict exists $d chapters] && [llength [dict get $d chapters]]} {
			set first [lindex [dict get $d chapters] 0]
			if {![catch {dict exists $first id}] && [dict exists $first id]} {
				set chapter [dict get $first id]
			}
		} elseif {[dict exists $d id]} {
			set chapter [dict get $d id]
		}
	}
	set url "https://lichess.org/study/$id"
	if {$chapter ne ""} { append url "/$chapter" }
	Status [format $mc::Uploaded $url]
	if {[DialogExists]} {
		$Priv(dialog).ok configure -text $mc::Close -command [namespace code Close] -state normal
		$Priv(dialog).cancel configure -state disabled
	}
}


# The token is stored with the download dialog's Lichess token, so one
# token works for both (the upload needs the extra study:write scope).
proc ::application::lichess::study::TokenVar {} {
	if {[info exists ::application::download::Options(lichess:token)]} {
		return ::application::download::Options(lichess:token)
	}
	return [namespace current]::Options(token)
}


proc ::application::lichess::study::Token {} {
	set var [TokenVar]
	if {[catch { set token [string trim [set $var]] }]} { return "" }
	return $token
}


proc ::application::lichess::study::Upload {} {
	variable Priv
	variable mc

	if {$Priv(running)} { return }

	set entry [spec $Priv(study)]
	if {![llength $entry]} {
		Status $mc::NoStudy
		return
	}
	lassign $entry id chapter

	set useApi [llength [info commands ::lichess::api::studyImportPgn]]
	set token [Token]
	# the dialog's own token, else the Lichess sign-in; one of them is needed
	if {$token eq "" && !($useApi && [::lichess::api::signedIn?])} {
		Status $mc::NeedToken
		return
	}

	if {[catch { set pgn [BuildPgn] } err]} {
		Status $err
		return
	}
	if {[string trim $pgn] eq ""} {
		Status [expr {$Priv(kind) eq "game" ? $mc::NoGame : $mc::NoGames}]
		return
	}

	set Priv(running) 1
	Status $mc::Uploading
	if {[DialogExists]} {
		$Priv(dialog).ok configure -state disabled
		$Priv(dialog).cancel configure -state disabled
	}

	if {$useApi} {
		set orient [expr {$Priv(orientation) in {white black} ? $Priv(orientation) : "white"}]
		set svar [expr {$Priv(studyVariant) ne "" ? $Priv(studyVariant) : "standard"}]
		SendPgnToStudy $id [string trim $Priv(name)] $pgn $orient $svar $token
		return
	}

	set request [importRequest $id $pgn $token [string trim $Priv(name)]]
	Post $request [namespace code [list OnUploaded $id]]
	return
}


proc ::application::lichess::study::BuildPgn {} {
	variable Priv
	variable mc

	if {$Priv(kind) eq "game"} {
		if {[catch { set modified [::scidb::game::query modified?] }]} {
			error $mc::NoGame
		}
		set source [expr {$modified ? "modified" : "original"}]
		return [::scidb::game::toPGN $source]
	}

	set file [TempFile]
	set flags 0
	if {[llength [info commands ::export::getPgnFlags]]} {
		catch { set flags [::export::getPgnFlags] }
	}
	set ok [catch {
		set result [::scidb::view::export \
			$Priv(base) $Priv(variant) $Priv(view) $file \
			$flags 0 utf-8 0 {} {} \
			[namespace code Noop] {} [namespace code NoopLog] {} \
		]
		lassign $result count illegal
		if {$count < 0} { set count [expr {-$count - 2}] }
		if {$count == 0} { error $mc::NoGames }
		set chan [::open $file r]
		fconfigure $chan -encoding utf-8
		set pgn [read $chan]
		close $chan
	} pgn]
	catch { file delete $file }
	if {$ok} { error $pgn }
	return $pgn
}


proc ::application::lichess::study::TempFile {} {
	if {[info exists ::scidb::dir::temp] && $::scidb::dir::temp ne ""} {
		set dir [file join $::scidb::dir::temp lichess-study]
	} else {
		set dir [file join $::scidb::dir::home lichess-study]
	}
	file mkdir $dir
	return [file join $dir "upload-[pid]-[clock microseconds].pgn"]
}


proc ::application::lichess::study::Noop {args} { return }
proc ::application::lichess::study::NoopLog {args} { return }


proc ::application::lichess::study::OnUploaded {id result} {
	variable Priv
	variable mc

	set Priv(running) 0

	if {![dict get $result ok]} {
		if {[DialogExists]} {
			$Priv(status) configure -text [errorText [dict get $result code] [dict get $result data]]
			$Priv(dialog).ok configure -state normal
			$Priv(dialog).cancel configure -state normal
		}
		return
	}

	set chapter [responseChapter [dict get $result data]]
	set url "https://lichess.org/study/$id"
	if {$chapter ne ""} { append url "/$chapter" }

	if {[DialogExists]} {
		$Priv(status) configure -text [format $mc::Uploaded $url]
		$Priv(dialog).ok configure -text $mc::Close -command [namespace code Close] -state normal
		$Priv(dialog).cancel configure -state disabled
	}
	return
}


# ----------------------------------------------------------------------
# HTTP POST (UI-free).
# ----------------------------------------------------------------------

proc ::application::lichess::study::Post {request done} {
	variable Timeout

	if {[catch { package require http 2.7 } err]} {
		after 0 [list {*}$done [list ok 0 error $err code 0 data ""]]
		return
	}

	set url [dict get $request url]
	if {[regexp {^https://([^/:]+)} $url _ host]} {
		if {[llength [info commands ::application::download::Tls]] == 0
		 || ![::application::download::Tls $host]} {
			set error "the tls package is needed for https uploads"
			after 0 [list {*}$done [list ok 0 error $error code 0 data ""]]
			return
		}
	}

	set headers [dict get $request headers]
	lappend headers Content-Type [dict get $request contentType]
	set agent "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
	if {[llength [info commands ::application::download::UserAgent]]} {
		set agent [::application::download::UserAgent]
	}
	set headers [linsert $headers 0 User-Agent $agent]

	if {[catch { ::http::geturl $url \
		-method POST \
		-headers $headers \
		-query [dict get $request body] \
		-timeout $Timeout -binary 1 \
		-command [namespace code [list OnPost $done]] \
	} token]} {
		after 0 [list {*}$done [list ok 0 error $token code 0 data ""]]
	}
	return
}


proc ::application::lichess::study::OnPost {done token} {
	set status [::http::status $token]
	set code [::http::ncode $token]
	set error [::http::error $token]
	set data [::http::data $token]
	::http::cleanup $token

	if {$status eq "ok" && $code >= 200 && $code < 300} {
		set result [list ok 1 data $data code $code]
	} else {
		if {![string length $error]} { set error $status }
		set result [list ok 0 error $error code $code data $data]
	}
	uplevel #0 [list {*}$done $result]
	return
}


# vi:set ts=3 sw=3:
