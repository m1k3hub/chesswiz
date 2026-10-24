# ======================================================================
# Scidb App Test — Lichess study import and export
# (tcl/app-lichess-study.tcl)
# ======================================================================
# Only the pure helpers are exercised here: study link/id parsing, the
# PGN and import endpoints, file names and the multipart request body.
# No network is used and no HTTP command is called.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::lichess::study {}

tcltest::test lichess-study-spec {study links and ids, with or without a chapter} -body {
	list \
		[::application::lichess::study::spec https://lichess.org/study/AbCdEf12] \
		[::application::lichess::study::spec https://lichess.org/study/AbCdEf12/GhIjKl34] \
		[::application::lichess::study::spec lichess.org/study/AbCdEf12] \
		[::application::lichess::study::spec www.lichess.org/study/AbCdEf12/GhIjKl34/] \
		[::application::lichess::study::spec AbCdEf12] \
		[::application::lichess::study::spec AbCdEf12/GhIjKl34] \
		[::application::lichess::study::spec {not a study}] \
		[::application::lichess::study::spec {}]
} -result {{AbCdEf12 {}} {AbCdEf12 GhIjKl34} {AbCdEf12 {}} {AbCdEf12 GhIjKl34} {AbCdEf12 {}} {AbCdEf12 GhIjKl34} {} {}}

tcltest::test lichess-study-specs {many links, deduplicated, one per line or separated} -body {
	set text {
https://lichess.org/study/AbCdEf12
lichess.org/study/GhIjKl34/MnOpQr56
AbCdEf12
GhIjKl34/MnOpQr56, XyZaBcDe; QwErTyUi
not a study
}
	::application::lichess::study::specs $text
} -result {{AbCdEf12 {}} {GhIjKl34 MnOpQr56} {XyZaBcDe {}} {QwErTyUi {}}}

tcltest::test lichess-study-urls {PGN and import endpoints} -body {
	list \
		[::application::lichess::study::pgnUrl AbCdEf12] \
		[::application::lichess::study::pgnUrl AbCdEf12 GhIjKl34] \
		[::application::lichess::study::importUrl AbCdEf12] \
		[::application::lichess::study::fileName AbCdEf12] \
		[::application::lichess::study::fileName AbCdEf12 GhIjKl34] \
		[::application::lichess::study::label AbCdEf12] \
		[::application::lichess::study::label AbCdEf12 GhIjKl34]
} -result {https://lichess.org/api/study/AbCdEf12.pgn https://lichess.org/api/study/AbCdEf12/GhIjKl34.pgn https://lichess.org/api/study/AbCdEf12/import-pgn lichess-study-AbCdEf12.pgn lichess-study-AbCdEf12-GhIjKl34.pgn lichess.org/study/AbCdEf12 lichess.org/study/AbCdEf12/GhIjKl34}

tcltest::test lichess-study-request {a multipart import request with token and chapter name} -body {
	set r [::application::lichess::study::importRequest \
		AbCdEf12 "1. e4 e5 2. Nf3" secret "Chapter 1" BOUNDARY]
	list \
		[dict get $r url] \
		[dict get $r method] \
		[dict get $r contentType] \
		[dict get $r headers] \
		[string match "*name=\"name\"*Chapter 1*" [dict get $r body]] \
		[string match "*name=\"pgn\"; filename=\"import.pgn\"*" [dict get $r body]] \
		[string match "*Content-Type: application/x-chess-pgn*" [dict get $r body]] \
		[string match "*1. e4 e5 2. Nf3*" [dict get $r body]] \
		[string match "*--BOUNDARY--*" [dict get $r body]] \
		[string match "*\r\n*" [dict get $r body]]
} -result {https://lichess.org/api/study/AbCdEf12/import-pgn POST {multipart/form-data; boundary=BOUNDARY} {Accept application/json Authorization {Bearer secret}} 1 1 1 1 1 1}

tcltest::test lichess-study-request-no-token {no Authorization header without a token} -body {
	set r [::application::lichess::study::importRequest AbCdEf12 "1. d4" {} {} B]
	list [dict get $r headers] [string match "*Authorization*" [dict get $r body]] \
		[string match "*name=\"name\"*" [dict get $r body]]
} -result {{Accept application/json} 0 0}

tcltest::test lichess-study-errors {upload failures get a useful message} -body {
	list \
		[string match *study:write* [::application::lichess::study::errorText 401]] \
		[string match *study:write* [::application::lichess::study::errorText 403]] \
		[string match *not*found* [::application::lichess::study::errorText 404]] \
		[::application::lichess::study::errorText 400 {{"error":"Invalid PGN"}}] \
		[string match *500* [::application::lichess::study::errorText 500]]
} -result {1 1 1 {Lichess rejected the PGN: Invalid PGN} 1}

tcltest::test lichess-study-response {the chapter id is read from the import response} -body {
	list \
		[::application::lichess::study::responseChapter {{"id":"GhIjKl34","name":"Chapter 1"}}] \
		[::application::lichess::study::responseChapter {{"name":"no id"}}] \
		[::application::lichess::study::responseChapter {not json}]
} -result {GhIjKl34 {} {}}

tcltest::cleanupTests
