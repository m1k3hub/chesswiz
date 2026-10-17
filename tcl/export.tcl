# ======================================================================
# Author : $Author$
# Version: $Revision: 1523 $
# Date   : $Date: 2018-09-17 08:11:58 -0400 (Mon, 17 Sep 2018) $
# Url    : $URL$
# ======================================================================

# ======================================================================
#    _/|            __
#   // o\         /    )           ,        /    /
#   || ._)    ----\---------__----------__-/----/__-
#   //__\          \      /   '  /    /   /    /   )
#   )___(     _(____/____(___ __/____(___/____(___/_
# ======================================================================

# ======================================================================
# Copyright: (C) 2009-2018 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source export-dialog

namespace eval export {
namespace eval mc {

set FileSelection				"&File Selection"
set OptionsSetup				"&Options"
set PageSetup					"&Page Setup"
set DiagramSetup				"&Diagram Setup"
set StyleSetup					"Sty&le"
set EncodingSetup				"&Encoding"
set TagsSetup					"&Tags"
set NotationSetup				"&Notation"
set AnnotationSetup			"&Annotation"
set CommentsSetup				"&Comments"

set Visibility					"Visibility"
set HideDiagrams				"Hide Diagrams"
set AllFromWhitePersp		"All From White's Perspective"
set AllFromBlackPersp		"All From Black's Perspective"
set ShowCoordinates			"Show Coordinates"
set ShowSideToMove			"Show Side to Move"
set ShowArrows					"Show Arrows"
set ShowMarkers				"Show Markers"
set Layout						"Layout"
set PostscriptSpecials		"Postscript Specialities"
set BoardSize					"Board Size"

set Hyphenation				"Hyphenation"
set None							"(none)"
set Graphic						"Graphic"
set Short						"Short"
set Long							"Long"
set Algebraic					"Algebraic"
set Correspondence			"Correspondence"
set Telegraphic				"Telegraphic"
set FontHandling				"Font handling"
set DiagramStyle				"Diagram Style"
set UseImagesForDiagram		"Use images for diagram generation"
set EmebedTruetypeFonts		"Embed TrueType fonts"
set UseBuiltinFonts			"Use built-in fonts"
set SelectExportedTags		"Selection of exported tags"
set ExcludeAllTags			"Exclude all tags"
set IncludeAllTags			"Include all tags"
set ExtraTags					"All other extra tags"
set NoComments					"No comments"
set AllLanguages				"All languages"
set SelectLanguages			"Selected languages"
set LanguageSelection		"Language selection"
set MapTo						"Map to"
set MapNagsToComment			"Map annotations to comments"
set UnusualAnnotation		"Unusual annotations"
set AllAnnotation				"All annotations"
set UseColumnStyle			"Use column style"
set MainlineStyle				"Main Line Style"
set HideVariations			"Hide variations"
set GameDoesNotHaveComments "This game does not contain comments."
set ManyGamesWarning			"Exporting %s games will produce a large document and may take a while.\n\nContinue?"
set ManyGamesWarningTitle		"Many games"

set LanguageSelectionDescr	"The checkbox (right side from combo box) has the meaning 'significant'.\n\nLanguages marked as 'significant' will always be exported.\n\nIf the game includes none of the languages marked as 'significant' then the first available language will be exported."

set PdfFiles					"PDF Files"
set HtmlFiles					"HTML Files"
set TeXFiles					"LaTeX Files"

set ExportDatabase			"Export database"
set ExportDatabaseVariant	"Export database - variant %s"
set ExportDatabaseTitle		"Export Database '%s'"
set ExportCurrentGameTitle	"Export Current Game"
set ExportingDatabase		"Exporting %s to file %s"
set Export						"Export"
set NoGamesExported			"No games exported."
set ExportedGames				"%s game(s) exported"
set NoGamesForExport			"No games for export."
set ResetDefaults				"Reset to defaults"
set UnsupportedEncoding		"Cannot use encoding %s for PDF documents. You have to choose an alternative encoding."
set DatabaseIsOpen			"The destination database '%s' is open, this means that the destination database will be emptied before the export is starting. Export anyway?"
set DatabaseIsOpenDetail	"If you want to append instead you should use a Drag&Drop operation inside the database switcher."
set DatabaseIsReadonly		"The destination database '%s' is already existing, and you don't have permissions for overwriting."
set ExportGamesFromTo		"Export games from '%src' to '%dst'"
set IllegalRejected			"%s game(s) rejected due to illegal moves"

set BasicStyle					"Basic Style"
set GameInfo					"Game Info"
set GameText					"Game Text"
set Moves						"Moves"
set MainLine					"Main Line"
set Variation					"Variation"
set Figurines					"Figurines"
set Subvariation				"Subvariation"
set Symbols						"Symbols"
set Comments					"Comments"
set Result						"Result"
set Diagram						"Diagram"
set ColumnStyle				"Column Style"

set Paper						"Paper"
set Orientation				"Orientation"
set Margin						"Margin"
set Format						"Format"
set Size							"Size"
set Custom						"Custom"
set Potrait						"Potrait"
set Landscape					"Landscape"
set Justification				"Justification"
set Even							"Even"
set Columns						"Columns"
set One							"One"
set Two							"Two"

set DocumentStyle				"Document Style"
set Article						"Article"
set Report						"Report"
set Book							"Book"

set FormatName(scidb)		"Scidb"
set FormatName(scid)			"Scid"
set FormatName(pgn)			"PGN"
set FormatName(pdf)			"PDF"
set FormatName(html)			"HTML"
set FormatName(tex)			"LaTeX"
set FormatName(ps)			"Postscript"

set Option(pgn,include_varations)						"Export variations"
set Option(pgn,include_comments)							"Export comments"
set Option(pgn,include_moveinfo)							"Export move information (as comments)"
set Option(pgn,include_marks)								"Export marks (as comments)"
set Option(pgn,use_scidb_import_format)				"Use Scidb import format"
set Option(pgn,use_chessbase_format)					"Use ChessBase format"
set Option(pgn,use_strict_pgn_standard)				"Use strict PGN standard"
set Option(pgn,include_ply_count_tag)					"Write tag 'PlyCount'"
#set Option(pgn,include_termination_tag)				"Write tag 'Termination'"
#set Option(pgn,include_mode_tag)						"Write tag 'Mode'"
set Option(pgn,include_opening_tag)						"Write tags 'Opening', 'Variation', 'Subvariation'"
set Option(pgn,include_setup_tag)						"Write tag 'Setup' (if needed)"
set Option(pgn,include_variant_tag)						"Write tag 'Variant' (if needed)"
set Option(pgn,include_position_tag)					"Write tag 'Position' (if needed)"
#set Option(pgn,include_time_mode_tag)					"Write tag 'TimeMode' (if needed)"
set Option(pgn,exclude_extra_tags)						"Exclude extraneous tags"
set Option(pgn,indent_variations)						"Indent variations"
set Option(pgn,indent_comments)							"Indent comments"
set Option(pgn,column_style)								"Column style (one move per line)"
set Option(pgn,symbolic_annotation_style)				"Symbolic annotation style (!, !?)"
set Option(pgn,extended_symbolic_style)				"Extended symbolic annotation style (+=, +/-)"
set Option(pgn,convert_null_moves)						"Convert null moves to comments"
set Option(pgn,space_after_move_number)				"Add space after move numbers"
set Option(pgn,shredder_fen)								"Write Shredder-FEN (default is X-FEN)"
set Option(pgn,convert_lost_result_to_comment)		"Write comment for result '0-0'"
set Option(pgn,write_any_rating_as_elo)				"Write any rating as ELO"
set Option(pgn,append_mode_to_event_type)				"Add mode after event type"
set Option(pgn,comment_to_html)							"Write comment in HTML style"
set Option(pgn,exclude_games_with_illegal_moves)	"Exclude games with illegal moves"
set Option(pgn,use_utf8_encoding)						"Use UTF-8 encoding"

} ;# namespace mc

#set Random {}
#while {[llength $Random] < 30} { lappend Random [expr {min(1.0, rand() + 0.15)}] }
set Random {
	0.75 1.00 1.00 0.97 0.31 0.21 1.00 1.00 0.52 0.17 0.89 1.00 0.18 1.00 0.78
	1.00 0.69 0.26 0.95 0.65 0.65 0.19 1.00 0.75 0.54 0.67 0.93 0.59 0.84 0.77
}

array set PdfEncodingMap {
	iso8859-1	StandardEncoding
	iso8859-2	ISO8859-2
	iso8859-3	ISO8859-3
	iso8859-4	ISO8859-4
	iso8859-5	ISO8859-5
	iso8859-6	ISO8859-6
	iso8859-7	ISO8859-7
	iso8859-8	ISO8859-8
	iso8859-9	ISO8859-9
	iso8859-10	ISO8859-10
	iso8859-11	ISO8859-11
	iso8859-12	ISO8859-12
	iso8859-13	ISO8859-13
	iso8859-14	ISO8859-14
	iso8859-15	ISO8859-15
	iso8859-16	ISO8859-16
	cp1250		CP1250
	cp1251		CP1251
	cp1252		CP1252
	cp1253		CP1253
	cp1254		CP1254
	cp1255		CP1255
	cp1256		CP1256
	cp1257		CP1257
	cp1258		CP1258
	utf-8			UTF-8
}
# cannot handle multi-byte encodings (will be implemented later)
#	koi8-r		KOI8-R
#	cp932			90msp-RKSJ-H
#	cp936			GBK-EUC-H
#	cp949			KSCms-UHC-H
#	cp950			ETen-B5-H
#	euc-cn		GB-EUC-H
#	euc-jp		EUC-H
#	euc-kr		KSC-EUC-H

set PdfEncodingList {}
foreach key [array names PdfEncodingMap] { lappend PdfEncodingList $key }
set PdfEncodingList [lsort -dictionary $PdfEncodingList]
set Figurines {}

set Paper(tex) {
	{ A4 210 297 mm }
	{ A5 148 210 mm }
	{ B5 176 250 mm }
	{ Letter 8.5 11 in }
	{ Legal 8.5 14 in }
}

set Paper(pdf) {
	{ A2 420 594 mm }
	{ A3 297 420 mm }
	{ A4 210 297 mm }
	{ A5 148 210 mm }
	{ A6 105 148 mm }
	{ B3 353 500 mm }
	{ B4 250 353 mm }
	{ B5 176 250 mm }
	{ Letter 8.5 11 in }
	{ Legal 8.5 14 in }
	{ Executive 7.25 10.5 in }
	{ {Half Letter} 5.5 8.5 in }
	{ {US B} 11 17 in }
	{ {US C} 17 22 in }
	{ {US 4x6} 4 6 in }
	{ {US 4x8} 4 8 in }
	{ {US 5x7} 5 7 in }
	{ {COMM 10} 4.125 9.5 in }
}

set StyleLayout(tex) {
	{ 0 BasicStyle }
		{ 1 GameInfo }
		{ 1 GameText }
			{ 2 Moves }
				{ 3 MainLine }
					{ 4 ColumnStyle }
				{ 3 Variation }
				{ 3 Subvariation }
			{ 2 Comments }
				{ 3 MainLine }
				{ 3 Variation }
				{ 3 Subvariation }
			{ 2 Result }
}

set StyleLayout(pdf) {
	{ 0 BasicStyle }
		{ 1 GameInfo }
		{ 1 GameText }
			{ 2 Moves }
				{ 3 MainLine }
					{ 4 ColumnStyle }
				{ 3 Variation }
				{ 3 Subvariation }
				{ 3 Figurines }
				{ 3 Symbols }
			{ 2 Comments }
				{ 3 MainLine }
				{ 3 Variation }
				{ 3 Subvariation }
			{ 2 Result }
		{ 1 Diagram }
}

set StyleLayout(html) $StyleLayout(pdf)

array set Styles {
	tex,BasicStyle														{Helvetica 12 normal roman #000000}
	tex,BasicStyle,GameInfo											{{} {} bold {} {}}
	tex,BasicStyle,GameText											{{} {} {} {} {}}
	tex,BasicStyle,GameText,Moves									{{} {} {} {} {}}
	tex,BasicStyle,GameText,Moves,MainLine						{{} {} bold {} {}}
	tex,BasicStyle,GameText,Moves,MainLine,ColumnStyle		{1}
	tex,BasicStyle,GameText,Moves,Variation					{{} {} {} {} {}}
	tex,BasicStyle,GameText,Moves,Subvariation				{{} 10 {} {} {}}
	tex,BasicStyle,GameText,Comments								{{} {} {} {} {}}
	tex,BasicStyle,GameText,Comments,MainLine					{{} {} {} {} {}}
	tex,BasicStyle,GameText,Comments,Variation				{{} {} {} {} {}}
	tex,BasicStyle,GameText,Comments,Subvariation			{{} 10 {} {} {}}
	tex,BasicStyle,GameText,Result								{{} {} bold {} {}}

	pdf,BasicStyle														{Helvetica 12 normal roman #000000}
	pdf,BasicStyle,GameInfo											{{} {} bold {} {}}
	pdf,BasicStyle,GameText											{{} {} {} {} {}}
	pdf,BasicStyle,GameText,Moves									{{} {} {} {} {}}
	pdf,BasicStyle,GameText,Moves,MainLine						{{} {} bold {} {}}
	pdf,BasicStyle,GameText,Moves,MainLine,ColumnStyle		{1}
	pdf,BasicStyle,GameText,Moves,Variation					{{} {} {} {} {}}
	pdf,BasicStyle,GameText,Moves,Subvariation				{{} 10 {} {} {}}
	pdf,BasicStyle,GameText,Moves,Figurines					{{Scidb Chess Merida} {} {} {} {}}
	pdf,BasicStyle,GameText,Moves,Symbols						{{Scidb Symbol T1} {} {} {} {}}
	pdf,BasicStyle,GameText,Comments								{{} {} {} {} #000099}
	pdf,BasicStyle,GameText,Comments,MainLine					{{} {} {} {} {}}
	pdf,BasicStyle,GameText,Comments,Variation				{{} {} {} {} {}}
	pdf,BasicStyle,GameText,Comments,Subvariation			{{} 10 {} {} {}}
	pdf,BasicStyle,GameText,Result								{{} {} bold {} {}}
	pdf,BasicStyle,Diagram											{{Scidb Diagram Merida} 20 normal roman {}}

	html,BasicStyle													{Helvetica 12 normal roman #000000}
	html,BasicStyle,GameInfo										{{} {} bold {} {}}
	html,BasicStyle,GameText										{{} {} {} {} {}}
	html,BasicStyle,GameText,Moves								{{} {} {} {} {}}
	html,BasicStyle,GameText,Moves,MainLine					{{} {} bold {} {}}
	html,BasicStyle,GameText,Moves,MainLine,ColumnStyle	{1}
	html,BasicStyle,GameText,Moves,Variation					{{} {} {} {} {}}
	html,BasicStyle,GameText,Moves,Subvariation				{{} 10 {} {} {}}
	html,BasicStyle,GameText,Moves,Figurines					{{Scidb Chess Merida} {} {} {} {}}
	html,BasicStyle,GameText,Moves,Symbols						{{Scidb Symbol T1} {} {} {} {}}
	html,BasicStyle,GameText,Comments							{{} {} {} {} #000099}
	html,BasicStyle,GameText,Comments,MainLine				{{} {} {} {} {}}
	html,BasicStyle,GameText,Comments,Variation				{{} {} {} {} {}}
	html,BasicStyle,GameText,Comments,Subvariation			{{} 10 {} {} {}}
	html,BasicStyle,GameText,Result								{{} {} bold {} {}}
	html,BasicStyle,Diagram											{{Scidb Diagram Merida} 20 normal roman {}}
}

set DocumentStyle {
	Article
	Report
	Book
}

set Languages {
	bg br ca cs cy da de de+ dsb el en eo es et eu fi fr ga gd gl he hr
	hsb hu ia is it ku la ms nl no pl pt ro ru se sk sl sq sr sv tr uk
}

array set Colors {
	shadow	export,shadow
	text		export,text
}

namespace eval si3 {
	array set DefaultTags {
		Board					1
		EventCountry		1
		EventType			1
		FICSGamesDBGameNo	1
		Mode					1
		Remark				1
		Source				1
		TimeControl			1
		TimeMode				1
		Variant				1
		Termination			1
		White/BlackClock	1
		White/BlackFideId	1
		White/BlackTitle	1
	}
}
namespace eval sci {
	# TODO: add White/BlackRatingDiff?
	array set DefaultTags {
		Board							1
		BughouseDBGameNo			1
		EventCategory				1
		EventRounds					1
		FICSGamesDBGameNo			1
		Remark						1
		Source						1
		SourceDate					1
		TimeControl					1
		White/BlackClock			1
		White/BlackTeam			1
		White/BlackTeamCountry	1
	}
}

array set NagMapping {
	skak {
		{   8   0 { 7 }				{} }
		{  10   0 { 11 12 }			{} }
		{  13   0 {}					{} }
		{  14   0 {}					{} }
		{  15   0 {}					{} }
		{  16   0 {}					{} }
		{  17   0 {}					{} }
		{  18   0 {}					{} }
		{  19   0 {}					{} }
		{ 140   0 {}					{} }
		{ 142   0 {}					{} }
		{ 145   0 {}					{} }
		{ 146   0 {}					{} }
		{ 147   0 {}					{} }
		{ 148   0 {}					{} }
		{ 150   0 {}					{} }
		{ 153   0 {}					{} }
		{ 154   0 {}					{} }
		{ 157   0 {}					{} }
		{ 158   0 {}					{} }
		{ 159   0 {}					{} }
		{ 160   0 {}					{} }
		{ 163   0 {}					{} }
		{ 164 165 { 24 26 28 }		{} }
		{ 165   0 { 25 27 29 }		{} }
		{ 166   0 {}					{} }
		{ 167 168 { 48 50 52 }		{} }
		{ 168   0 { 49 51 53 }		{} }
		{ 170   0 {}					{} }
		{ 171   0 {}					{} }
		{ 172   0 {}					{} }
		{ 175   0 { 30 32 34 }		{ 31 33 35 } }
		{ 176   0 { 22 }				{ 23 } }
		{ 178   0 { 40 }				{ 41 } }
		{ 179   0 { 36  38 }			{ 37 39 } }
		{ 180   0 { 130 132 134 }	{ 131 133 135 } }
		{ 181   0 { 44 }				{ 45 } }
		{ 182   0 { 151 }				{ 152 } }
		{ 183 184 { 54 56 58 }		{ 55 57 59 } }
		{ 184   0 { 60 62 64 }		{ 61 63 65 } }
	}
}

namespace eval si3 { array set Tags [array get DefaultTags] }
namespace eval sci { array set Tags [array get DefaultTags] }

variable Info
variable ManyGamesThreshold 500

# NOTE: order must coincide with flags in db::DocumentWriter
array set Options {
	diagram_from_whites_perspective	0
	diagram_from_blacks_perspective	1
	diagram_hide							2
	diagram_show_mover					3
	diagram_show_coordinates			4

	moves_notation_short					5
	moves_notation_long					6
	moves_notation_algebraic			7
	moves_notation_correspondence		8
	moves_notation_telegraphic			9

	annotation_map_unusual				10
	annotation_map_all					11
}

# NOTE: order must coincide with flags in db::Writer/db::PgnWriter.
array set Flags {
	pgn,include_varations						 0
	pgn,include_comments							 1
	pgn,include_annotation						 2
	pgn,include_moveinfo							 3
	pgn,include_marks								 4
	pgn,include_termination_tag				 5
	pgn,include_mode_tag							 6
	pgn,include_opening_tag						 7
	pgn,include_setup_tag						10
	pgn,include_variant_tag						11
	pgn,include_position_tag					12
	pgn,include_time_mode_tag					13
	pgn,exclude_extra_tags						14
	pgn,indent_variations						15
	pgn,indent_comments							16
	pgn,column_style								17
	pgn,symbolic_annotation_style				18
	pgn,extended_symbolic_style				29
	pgn,convert_null_moves						20
	pgn,space_after_move_number				21
	pgn,shredder_fen								22
	pgn,convert_lost_result_to_comment		23
	pgn,append_mode_to_event_type				24
	pgn,comment_to_html							25
	pgn,use_chessbase_format					26
	pgn,use_scidb_import_format				27
	pgn,use_utf8_encoding						28
	pgn,use_strict_pgn_standard				29
	pgn,write_any_rating_as_elo				30
	pgn,exclude_games_with_illegal_moves	31
}

array set Defaults {
	scid,comments,languages							{{*} {} {} {} {} {} {}}
	scidb,comments,languages						{{*} {} {} {} {} {} {}}

	pgn,flag,include_varations						1
	pgn,flag,include_comments						1
	pgn,flag,include_annotation					1
	pgn,flag,include_moveinfo						1
	pgn,flag,include_marks							1
	pgn,flag,include_termination_tag				1
	pgn,flag,include_mode_tag						1
	pgn,flag,include_opening_tag					1
	pgn,flag,include_setup_tag						1
	pgn,flag,include_variant_tag					1
	pgn,flag,include_position_tag					1
	pgn,flag,include_time_mode_tag				1
	pgn,flag,exclude_extra_tags					0
	pgn,flag,indent_variations						1
	pgn,flag,indent_comments						0
	pgn,flag,column_style							0
	pgn,flag,symbolic_annotation_style			1
	pgn,flag,extended_symbolic_style				0
	pgn,flag,convert_null_moves					0
	pgn,flag,space_after_move_number				0
	pgn,flag,shredder_fen							0
	pgn,flag,convert_lost_result_to_comment	1
	pgn,flag,map_lost_result_to_unknown			1
	pgn,flag,append_mode_to_event_type			0
	pgn,flag,use_chessbase_format					0
	pgn,flag,comment_to_html						0
	pgn,flag,use_scidb_import_format				0
	pgn,flag,use_utf8_encoding						0
	pgn,flag,use_strict_pgn_standard				0
	pgn,flag,write_any_rating_as_elo				0
	pgn,flag,exclude_games_with_illegal_moves	0

	pgn,comments,languages							{{*} {} {} {} {} {} {}}

	pdf,fonts,embed									1
	pdf,fonts,builtin									0

	pdf,moves,notation								san
	pdf,moves,figurines								graphic
	pdf,moves,hide-variations						0

	pdf,diagram,board-size							160
	pdf,diagram,hide									0
	pdf,diagram,perspective							{}
	pdf,diagram,show-coordinates					1
	pdf,diagram,show-movers							0
	pdf,diagram,show-arrows							0
	pdf,diagram,show-markers						0
	pdf,diagram,use-images							0
	pdf,diagram,image-style							{Default Merida}
	pdf,diagram,image-size							200

	pdf,comments,languages							{{*} {} {} {} {} {} {}}
	pdf,comments,hyphenation						en

	pdf,paper,format									A4
	pdf,paper,custom									{ 210 297 mm }
	pdf,paper,orientation							Potrait
	pdf,paper,columns									2
	pdf,paper,justification							0
	pdf,paper,top										0
	pdf,paper,bottom									0
	pdf,paper,left										0
	pdf,paper,right									0

	pdf,margins,A2										{ 40    53     44    44    }
	pdf,margins,A3										{ 38    44     31    31    }
	pdf,margins,A4										{ 20    27     22    22    }
	pdf,margins,A5										{ 14    19     15    15    }
	pdf,margins,A6										{ 10    13     11    11    }
	pdf,margins,B3										{ 33    45     37    37    }
	pdf,margins,B4										{ 23    32     26    26    }
	pdf,margins,B5										{ 17    22     18    18    }
	pdf,margins,Letter								{  0.74  1.00   0.89  0.89 }
	pdf,margins,Legal									{  0.94  1.26   0.89  0.89 }
	pdf,margins,Executive							{  0.70  0.95   0.76  0.76 }
	{pdf,margins,Half Letter}						{  0.57  0.76   0.57  0.57 }
	{pdf,margins,US B}								{  1.14  1.53   1.15  1.15 }
	{pdf,margins,US C}								{  1.47  1.98   1.78  1.78 }
	{pdf,margins,US 4x6}								{  0.40  0.54   0.42  0.42 }
	{pdf,margins,US 4x8}								{  0.54  0.72   0.42  0.42 }
	{pdf,margins,US 5x7}								{  0.50  0.63   0.52  0.52 }
	{pdf,margins,COMM 10}							{  0.64  0.85   0.43  0.43 }

	tex,moves,notation								san
	tex,moves,figurines								graphic
	tex,moves,hide-variations						0

	tex,nag,mapping									{}
	tex,nag,lang										{}
	tex,nag,all											0

	tex,comments,languages							{{*} {} {} {} {} {} {}}
	tex,comments,hyphenation						en

	tex,paper,document								Article
	tex,paper,format									A4
	tex,paper,orientation							Potrait
	tex,paper,columns									2
	tex,paper,justification							1

	tex,diagram,board-size							160
	tex,diagram,hide									0
	tex,diagram,perspective							{}
	tex,diagram,show-coordinates					1
	tex,diagram,show-movers							0
	tex,diagram,show-arrows							0
	tex,diagram,show-markers						0
	tex,diagram,use-images							0
	tex,diagram,image-style							{Default Merida}
	tex,diagram,image-size							200

	html,moves,notation								san
	html,moves,figurines								graphic
	html,moves,hide-variations						0

	html,comments,languages							{{*} {} {} {} {} {} {}}
	html,comments,hyphenation						en
}

array set Values [array get Defaults]

set Values(Type)					pgn
set Values(Types)					{pgn pdf html tex}

set Values(pgn,encoding)		iso8859-1
set Values(scid,encoding)		utf-8
set Values(scidb,encoding)		utf-8
set Values(pdf,encoding)		iso8859-1

#if {$::tcl_platform(platform) eq "windows"} { set Values(pdf,fonts,embed) 0 }

array set Fields {
	pgn	{	include_varations include_comments include_moveinfo include_marks indent_variations
				indent_comments convert_lost_result_to_comment use_scidb_import_format
				use_chessbase_format use_strict_pgn_standard append_mode_to_event_type
				symbolic_annotation_style extended_symbolic_style shredder_fen column_style
				convert_null_moves write_any_rating_as_elo comment_to_html space_after_move_number
				include_opening_tag include_setup_tag include_variant_tag include_position_tag
				exclude_extra_tags exclude_games_with_illegal_moves use_utf8_encoding
			}
	scid	{}
}


proc open {parent args} {
	variable icon::32x32::IconPDF
	variable icon::32x32::IconHtml
	variable icon::32x32::IconPGN
	variable icon::32x32::IconTeX
	variable ::scidb::clipbaseName
	variable PdfEncodingList
	variable Icons
	variable Info
	variable Values

	array set opts $args
	array unset Info
	set Info(base) $opts(-base)
	set Info(variant) $opts(-variant)
	set Info(extension) $opts(-extension)
	if {[info exists opts(-view)]} { set Info(view) $opts(-view) }
	if {[info exists opts(-name)]} { set Info(name) $opts(-name) }
	if {[info exists opts(-index)]} { set Info(index) $opts(-index) }
	if {[info exists opts(-title)]} { set Info(title) $opts(-title) }
	if {[info exists opts(-languages)]} { set Info(languages) $opts(-languages) }
	if {[info exists opts(-preferred)]} { set Info(preferred) $opts(-preferred) }
	if {[info exists opts(-type)]} { set Info(type) $opts(-type) }
	if {[info exists Info(languages)] && ![info exists Info(preferred)]} {
		set Info(preferred) {}
	}
	unset opts

	if {	![info exists Info(index)]
		&& [::scidb::view::count games $Info(base) $Info(variant) $Info(view)] == 0} {
		::dialog::info -parent $parent -message $mc::NoGamesForExport
		return
	}

	set Info(after) {}
	set Info(encoding) [::scidb::db::get encoding $Info(base)]
	set Info(pdf-encoding) 0
	set Info(fonts) {}

	switch $Info(extension) {
		sci - pgn - tex {}
		default { if {$Info(encoding) ni $PdfEncodingList} { set Info(pdf-encoding) 1 } }
	}

	set dlg [tk::toplevel $parent.export -class Dialog]
	bind $dlg <Alt-Key> [list tk::AltKeyInDialog $dlg %A]
#	if {$closeViewAfterExit} { bind $dlg <Destroy> [namespace code CloseView] }
	wm withdraw $dlg
	set top [ttk::frame $dlg.top]
	pack $top

	array set icons [list          \
		scidb	$::icon::32x32::logo  \
		scid	$::icon::32x32::scid3 \
		pgn	$IconPGN              \
		tex	$IconTeX              \
		html	$IconHtml             \
		pdf	$IconPDF              \
	]
	set bwd 2

	if {[info exists Info(index)]} {
		set Values(Types) {pgn pdf html tex}
		set Values(Type) pgn
		set tabs {	options OptionsSetup
						style StyleSetup
						page_pdf PageSetup
						page_tex PageSetup
						notation NotationSetup
						diagram DiagramSetup
						comment CommentsSetup
						annotation AnnotationSetup
						encoding EncodingSetup}
		if {[info exists Info(title)]} {
			set initialfile "$mc::Game-$Info(title)"
		} else {
			set initialfile "$mc::Game-$Info(index)"
		}
	} else {
		set Values(Type) scidb
		set Values(Types) {scidb scid pgn pdf html tex}
		set tabs {	options OptionsSetup
						tags_si3 TagsSetup
						tags_sci TagsSetup
						style StyleSetup
						page_pdf PageSetup
						page_tex PageSetup
						notation NotationSetup
						diagram DiagramSetup
						comment CommentsSetup
						annotation AnnotationSetup
						encoding EncodingSetup}
		set initialfile [file rootname [file tail $Info(base)]]
		if {$initialfile eq $clipbaseName} { set initialfile $::util::clipbaseName }
	}
	if {[info exists Info(type)] && $Info(type) in $Values(Types)} {
		set Values(Type) $Info(type)
	}

	set height [llength $Values(Types)]
	set list [::tlistbox $top.list -height $height -usescroll no -padx 10 -pady 7 -ipady 4]
	pack $list -expand yes -fill both
	$list addcol combined -id item
	foreach type $Values(Types) {
		$list insert [list [list $icons($type) $mc::FormatName($type)]]
		set Info($type,flags) 0
	}
	$list resize

	set nb [ttk::notebook $top.nb -takefocus 1]
	bind $list <<ListboxSelect>> [namespace code [list Select $nb %d]]
	bind $nb <ButtonPress-1> [list focus $nb]
	ttk::notebook::enableTraversal $nb
	lappend opts -okcommand [namespace code [list DoExport $parent $dlg]]
	lappend opts -cancelcommand [list destroy $dlg]
	lappend opts -parent $nb
	lappend opts -embed 1
	# XXX verifymcd needed?
	lappend opts -initialfile $initialfile
	lappend opts -filetypes {{dummy .___}}
	lappend opts -width 720
	lappend opts -class export
	set Info(fsbox) [::dialog::saveFile {*}$opts]
	$nb add $Info(fsbox) -sticky nsew
	::widget::notebookTextvarHook $nb $Info(fsbox) [namespace current]::mc::FileSelection

	foreach {tab var} $tabs {
		set f [ttk::frame $nb.$tab]
		$nb add $f -sticky nsew
		::widget::notebookTextvarHook $nb $f [namespace current]::mc::$var
		set Info(build-$tab) 1
	}
	set Info(build-encoding-pgn) 1
	set Info(build-encoding-pdf) 1

	grid [options::BuildFrame $nb.options.f] -row 1 -column 1 -sticky nsew
	grid rowconfigure $nb.options 1 -weight 1

	grid $list	-row 1 -column 1 -sticky ns
	grid $nb		-row 1 -column 3 -sticky nsew
	
	grid columnconfigure $top {0 2 4} -minsize $::theme::padding
	grid rowconfigure $top {0 2} -minsize $::theme::padding

	set index [lsearch -exact $Values(Types) $Values(Type)]
	Select $nb $index
	$list select $index

	wm withdraw $dlg
	if {[info exists Info(index)]} {
		set title "$mc::ExportCurrentGameTitle (#$Info(index))"
	} else {
		set title [format $mc::ExportDatabaseTitle $Info(name)]
	}
	wm title $dlg $title
	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
	wm resizable $dlg false false
	wm transient $dlg $parent
	::util::place $dlg -parent [winfo toplevel $parent] -position center
	wm deiconify $dlg

	ttk::grabWindow $dlg
	tkwait window $dlg
	ttk::releaseGrab $dlg
}


proc buildPgnOptionsFrame {parent} {
	return [options::BuildFrame $parent.options]
}


proc getPgnFlags {} {
	variable Flags
	variable Values

	set flags 0
	foreach attr [array names Flags] {
		if {$Values(pgn,flag,[lindex [split $attr ,] 1])} {
			set flags [expr {$flags | [Pow2 $Flags($attr)]}]
		}
	}
	return $flags
}


proc testUTF8Flag {} {
	variable Values
	return $Values(pgn,flag,use_utf8_encoding)
}


proc Pow2 {x} { return [expr {1 << $x}] }
namespace export Pow2


namespace eval options {

namespace import [namespace parent]::Pow2


proc Exclude {type flag} {
	variable [namespace parent]::Info
	variable [namespace parent]::Flags

	set Info($type,flags) [expr {$Info($type,flags) & ~[Pow2 $Flags($type,$flag)]}]
}


proc BuildFrame {w} {
	variable [namespace parent]::Flags
	variable [namespace parent]::Values
	variable [namespace parent]::Fields
	variable [namespace parent]::Info

	ttk::frame $w -takefocus 0
	set flags [Pow2 $Flags(pgn,include_annotation)]
	set count 0
	set nrows [expr {([llength $Fields(pgn)] + 1)/2}]

	foreach field $Fields(pgn) {
		ttk::checkbutton $w.$field \
			-variable [namespace parent]::Values(pgn,flag,$field) \
			-text [set [namespace parent]::mc::Option(pgn,$field)] \
			-command [namespace code [list SetupFlags $w pgn]] \
			;
		set row [expr {2*($count % $nrows) + 3}]
		set col [expr {2*($count / $nrows) + 1}]
		grid $w.$field -row $row -column $col -sticky we
		incr count
	}
	set Info(options:nrows) $nrows
	set parent [winfo parent $w]

	if {[winfo toplevel $parent] eq $parent} {
		::widget::dialogButtons $parent reset
		$parent.reset configure -command [namespace code [list ResetFlags $w pgn]]
		::tooltip::tooltip $parent.reset [namespace parent]::mc::ResetDefaults
		incr count 2
		grid rowconfigure $w $count -minsize $::theme::padding
		bind $w <FocusIn> { focus [tk_focusNext %W] }
	} else {
		set var [namespace parent]::mc::ResetDefaults
		set b [ttk::frame $w.buttons]
		ttk::button $b.reset -text [set $var] -command [namespace code [list ResetFlags $w pgn]]
		if {$count % 2} { incr count }
		incr count 2
		grid $b.reset -row 0 -column 0 -sticky w
		grid columnconfigure $b 1 -minsize $::theme::padding
		grid $b -row [expr {$count + 1}] -column 1 -columnspan 3 -sticky w
		grid rowconfigure $w $count -minsize [expr {2*$::theme::padding}]
	}

	for {set i 0} {$i < $count} {incr i 2} { lappend rows $i }
	grid rowconfigure $w $rows -minsize $::theme::padding
	grid rowconfigure $w [expr {$count + 2}] -minsize $::theme::padding
	grid columnconfigure $w {0 4} -minsize $::theme::padding
	grid columnconfigure $w 2 -minsize [expr {2*$::theme::padding}]
	SetupFlags $w pgn

	return $w
}


proc ResetFlags {w type} {
	variable [namespace parent]::Defaults
	variable [namespace parent]::Values

	foreach field [array names Defaults -glob $type,flag,*] {
		set Values($field) $Defaults($field)
	}

	if {$type eq"pgn"} {
		SetupFlags $w $type
	}
}


proc SetupFlags {w type} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info
	variable [namespace parent]::Flags
	variable [namespace parent]::Fields

	set flags 0
	foreach field $Fields($type) {
		if {$Values($type,flag,$field)} {
			set flags [expr {$flags | [Pow2 $Flags($type,$field)]}]
		}
	}
	set Info($type,flags) $flags

	switch $type {
		pgn {
			if {$Values(pgn,flag,use_chessbase_format) || $Values(pgn,flag,use_scidb_import_format)} {
				if {$Values(pgn,flag,use_scidb_import_format)} {
					$w.use_chessbase_format configure -state disabled
					$w.use_scidb_import_format configure -state normal
					$w.use_strict_pgn_standard configure -state disabled
					$w.write_any_rating_as_elo configure -state disabled
				} else {
					$w.use_chessbase_format configure -state normal
					$w.use_scidb_import_format configure -state disabled
					$w.use_strict_pgn_standard configure -state disabled
				}
				foreach field $Fields(pgn) {
					switch $field {
						use_chessbase_format -
						use_scidb_import_format -
						use_strict_pgn_standard -
						exclude_games_with_illegal_moves -
						column_style -
						indent_comments -
						indent_variations -
						space_after_move_number -
						include_opening_tag -
						write_any_rating_as_elo {}
						default { $w.$field configure -state disabled }
					}
				}
			} elseif {$Values(pgn,flag,use_strict_pgn_standard)} {
				$w.use_strict_pgn_standard configure -state normal
				foreach field $Fields(pgn) {
					switch $field {
						include_varations -
						include_comments -
						include_moveinfo -
						include_marks -
						include_variant_tag -
						append_mode_to_event_type -
						symbolic_annotation_style -
						use_strict_pgn_standard -
						exclude_games_with_illegal_moves -
						column_style -
						indent_comments -
						indent_variations -
						space_after_move_number -
						include_opening_tag -
						write_any_rating_as_elo {}
						default { $w.$field configure -state disabled }
					}
				}
			} else {
				foreach field $Fields(pgn) { $w.$field configure -state normal }
				if {$Values(pgn,flag,symbolic_annotation_style)} {
					$w.extended_symbolic_style configure -state normal
				} else {
					$w.extended_symbolic_style configure -state disabled
					Exclude pgn extended_symbolic_style
				}
				if {$Values(pgn,flag,exclude_games_with_illegal_moves)} {
					set flags [expr {$flags & ~[Pow2 $Flags($type,$field)]}]
				}
			}
		}
	}
}

} ;# namespace options


namespace eval tags_si3 { proc BuildFrame {w} { [namespace parent]::tags::BuildFrame $w } }
namespace eval tags_sci { proc BuildFrame {w} { [namespace parent]::tags::BuildFrame $w } }


namespace eval tags {

proc BuildFrame {w} {
	variable [namespace parent]::Values

	switch $Values(Type) {
		scid	{ set type si3 }
		scidb	{ set type sci }
	}

	variable [namespace parent]::${type}::Tags

	set extraTags [lsort [::scidb::misc::extraTags $type]]
	set tagList {}

	foreach tag $extraTags {
		if {[string match White* $tag]} {
			set blackTag "Black[string range $tag 5 end]"
			if {$blackTag in $extraTags} {
				lappend tagList "White/$blackTag"
			} else {
				lappend tagList $tag
			}
		} elseif {[string match Black* $tag]} {
			set whiteTag "White[string range $tag 5 end]"
			if {$whiteTag ni $extraTags} { lappend tagList $tag }
		} else {
			lappend tagList $tag
		}
	}
	set tagList [lsort -ascii $tagList]
	lappend tagList ExtraTag

	ttk::label $w.header -textvar [namespace parent]::mc::SelectExportedTags
	set font [$w.header cget -font]
	if {[llength $font] == 0} { set font TkDefaultFont }
	set bold [list [font configure $font -family]  [font configure $font -size] bold]
	$w.header configure -font $bold
	grid $w.header -row 1 -column 1 -columnspan 5 -sticky w

	set nrows [expr {([llength $tagList] + 2)/3}]
	set lastRow [expr {2*$nrows + 3}]
	set count 0

	foreach tag $tagList {
		if {![info exists Tags($tag)]} { set Tags($tag) 0 }
		set btn $w.[string tolower $tag 0 0]
		if {$tag eq "ExtraTag"} {
			set text [set [namespace parent]::mc::ExtraTags]
			set row [expr {$lastRow - 2}]
		} else {
			set text $tag
			set row [expr {2*($count % $nrows) + 3}]
		}
		ttk::checkbutton $btn \
			-text $text \
			-variable [namespace parent]::${type}::Tags($tag) \
			;
		set col [expr {2*($count/$nrows) + 1}]
		grid $btn -row $row -column $col -sticky w
		incr count
	}

	foreach tag [array names Tags] {
		if {$tag ni $tagList} { array unset Tags $tag }
	}

	ttk::frame $w.buttons
	grid $w.buttons -row $lastRow -column 1 -columnspan 5 -sticky w

	ttk::button $w.buttons.include \
		-textvar [namespace parent]::mc::IncludeAllTags \
		-command [namespace code [list ResetTags $type 1]] \
		;
	ttk::button $w.buttons.exclude \
		-textvar [namespace parent]::mc::ExcludeAllTags \
		-command [namespace code [list ResetTags $type 0]] \
		;
	ttk::button $w.buttons.reset \
		-textvar [namespace parent]::mc::ResetDefaults \
		-command [namespace code [list ResetTags $type -1]] \
		;
	grid $w.buttons.include -row 0 -column 0
	grid $w.buttons.exclude -row 0 -column 2
	grid $w.buttons.reset   -row 0 -column 4
	grid columnconfigure $w.buttons {1 3} -minsize $::theme::padding

	for {set i 2} {$i <= $lastRow} {incr i 2} { lappend rows $i }
	grid rowconfigure $w $rows -minsize $::theme::padding
	set rows [list 0 2 [expr {$lastRow - 1}] [expr {$lastRow + 1}]]
	grid rowconfigure $w $rows -minsize [expr {2*$::theme::padding}]
	grid columnconfigure $w {0 6} -minsize $::theme::padding
	grid columnconfigure $w {2 4} -minsize [expr {4*$::theme::padding}]

	return $w
}


proc ResetTags {type value} {
	variable [namespace parent]::${type}::Tags
	variable [namespace parent]::${type}::DefaultTags

	if {$value == -1} {
		foreach tag [array names Tags] { set Tags($tag) 0 }
		array set Tags [array get DefaultTags]
	} else {
		foreach tag [array names Tags] { set Tags($tag) $value }
	}
}

} ;# namespace tags


namespace eval notation {

proc BuildFrame {w} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	::figurines::listbox $w.figurines -width 165 -variable [namespace parent]::Figurines
	::notation::listbox $w.notation -width 180
	$w.figurines connect $w.notation

	bind $w.figurines <<ListboxSelect>> [namespace code [list SetFigurines %d]]
	bind $w.notation <<ListboxSelect>> [namespace code [list SetNotation %d]]

	### Style ################################################################################
	ttk::labelframe $w.style -text [set [namespace parent]::mc::MainlineStyle]
	ttk::checkbutton $w.style.format \
		-text [set [namespace parent]::mc::UseColumnStyle] \
		-variable [namespace parent]::Info(column-style) \
		;
	grid $w.style.format -row 1 -column 1
	grid rowconfigure $w.style {0 2} -minsize $::theme::padding
	grid rowconfigure $w.style {2} -weight 1
	grid columnconfigure $w.style {0 2} -minsize $::theme::padding
	trace add variable [namespace parent]::Info(column-style) write [namespace code UpdateColumnStyle]

	ttk::labelframe $w.options -text [::mc::stripAmpersand [set [namespace parent]::mc::OptionsSetup]]
	ttk::checkbutton $w.options.hide \
		-text [set [namespace parent]::mc::HideVariations] \
		-variable [namespace parent]::Info(hide-variations) \
		-command [namespace code UpdateVariationFlag] \
		;
	grid $w.options.hide -row 1 -column 1
	grid rowconfigure $w.options {0 2} -minsize $::theme::padding
	grid rowconfigure $w.options {2} -weight 1
	grid columnconfigure $w.options {0 2} -minsize $::theme::padding

	### Layout ##############################################################################
	grid $w.figurines -row 1 -column 1 -sticky ns -rowspan 3
	grid $w.notation  -row 1 -column 3 -sticky ns -rowspan 3
	grid $w.style     -row 1 -column 5 -sticky nswe
	grid $w.options   -row 3 -column 5 -sticky nswe
	grid rowconfigure $w {0 2 4} -minsize $::theme::padding
	grid rowconfigure $w {1 3} -weight 1
	grid columnconfigure $w {0 2 4 6} -minsize $::theme::padding

	return $w
}


proc SetFigurines {lang} {
	variable [namespace parent]::Values
	set Values($Values(Type),moves,figurines) $lang
}


proc SetNotation {form} {
	variable [namespace parent]::Values
	set Values($Values(Type),moves,notation) $form
}


proc UpdateColumnStyle {args} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info
	variable [namespace parent]::Styles

	set Styles($Values(Type),BasicStyle,GameText,Moves,MainLine,ColumnStyle) $Info(column-style)
}


proc UpdateVariationFlag {} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set Values($Values(Type),moves,hide-variations) $Info(hide-variations)
}


proc Setup {pane} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info
	variable [namespace parent]::Styles

	set type $Values(Type)

	$pane.notation select $Values($type,moves,notation)
	$pane.figurines select $Values($type,moves,figurines)

	set Info(column-style) $Styles($type,BasicStyle,GameText,Moves,MainLine,ColumnStyle)
	set Info(hide-variations) $Values($type,moves,hide-variations)
}

} ;# namespace notation


namespace eval diagram {

proc BuildFrame {w} {
	variable [namespace parent]::DiagramStyles
	variable [namespace parent]::DiagramSizes
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set type $Values(Type)

	set lt [ttk::frame $w.lt -borderwidth 0]
	set rt [ttk::labelframe $w.rt -text [set [namespace parent]::mc::PostscriptSpecials]]

	### Layout ##################################################################
	ttk::labelframe $lt.layout -text [set [namespace parent]::mc::Layout]
	ttk::checkbutton $lt.layout.coords \
		-text [set [namespace parent]::mc::ShowCoordinates] \
		-variable [namespace parent]::Values($type,diagram,show-coordinates) \
		;
	ttk::checkbutton $lt.layout.white \
		-text [set [namespace parent]::mc::AllFromWhitePersp] \
		-variable [namespace parent]::Info(diagram,white-perspective) \
		-command [namespace code [list SetPerspective white]] \
		;
	ttk::checkbutton $lt.layout.black \
		-text [set [namespace parent]::mc::AllFromBlackPersp] \
		-variable [namespace parent]::Info(diagram,black-perspective) \
		-command [namespace code [list SetPerspective black]] \
		;
	grid $lt.layout.coords -row 1 -column 1 -sticky w
	grid $lt.layout.white  -row 3 -column 1 -sticky w
	grid $lt.layout.black  -row 5 -column 1 -sticky w
	grid rowconfigure $lt.layout {0 2 4 6} -minsize $::theme::padding
	grid rowconfigure $lt.layout {6} -weight 1
	grid columnconfigure $lt.layout {0 2} -minsize $::theme::padding

	### Board Size ##############################################################
	ttk::labelframe $lt.size -text "[set [namespace parent]::mc::BoardSize] (pt)"
	set col 1
	foreach size {80 120 160 240} {
		ttk::radiobutton $lt.size.$size \
			-text $size \
			-value $size \
			-variable [namespace parent]::Values($type,diagram,board-size) \
			;
		grid $lt.size.$size -row 1 -column $col -sticky w
		incr col 2
	}
	grid rowconfigure $lt.size {0 2} -minsize $::theme::padding
	grid rowconfigure $lt.size {2} -weight 1
	grid columnconfigure $lt.size {0 2 4 6 8} -minsize $::theme::padding

	### Visibility ##############################################################
	ttk::labelframe $lt.vis -text [set [namespace parent]::mc::Visibility]
	ttk::checkbutton $lt.vis.hide \
		-text [set [namespace parent]::mc::HideDiagrams] \
		-variable [namespace parent]::Values($type,diagram,hide)
		;
	grid $lt.vis.hide -row 1 -column 1 -sticky w
	grid rowconfigure $lt.vis {0 2} -minsize $::theme::padding
	grid rowconfigure $lt.vis {2} -weight 1
	grid columnconfigure $lt.vis {0 2} -minsize $::theme::padding

	### Postscript ##############################################################
	ttk::checkbutton $rt.movers \
		-text [set [namespace parent]::mc::ShowSideToMove] \
		-variable [namespace parent]::Values($type,diagram,show-movers) \
		;
	ttk::checkbutton $rt.arrows \
		-text [set [namespace parent]::mc::ShowArrows] \
		-variable [namespace parent]::Values($type,diagram,show-arrows) \
		;
	ttk::checkbutton $rt.markers \
		-text [set [namespace parent]::mc::ShowMarkers] \
		-variable [namespace parent]::Values($type,diagram,show-markers) \
		;

	### Images ##################################################################
	SearchDiagramStyles
	ttk::separator $rt.sep
	ttk::frame $rt.images -borderwidth 0
	ttk::checkbutton $rt.images.use \
		-text [set [namespace parent]::mc::UseImagesForDiagram] \
		-variable [namespace parent]::Values($type,diagram,use-images) \
		;
	set selbox [::tlistbox $rt.images.selection \
		-height [llength $DiagramStyles] \
		-borderwidth 1 \
		-disabledbackground [::colors::lookup theme,background] \
		-disabledforeground [::colors::lookup theme,disabled] \
	]
	$selbox addcol image -id icon
	$selbox addcol text -id text -expand yes
	set Info(diagram:list) {}
	foreach entry $DiagramStyles {
		lassign $entry sample style set sizes
		catch {
			set img [image create photo -file $sample]
			set name "$style - $set"
			$selbox insert [list $img $name]
			lappend Info(diagram:list) [list [list $style $set] $sizes]
		}
	}
	$selbox resize
	set f [ttk::frame $rt.images.sizes -borderwidth 0]
	ttk::label $f.size -text "[set [namespace parent]::mc::BoardSize] (pt):"
	grid $f.size -column 1 -row 1
	set col 2
	foreach size $DiagramSizes {
		ttk::radiobutton $f.$size \
			-text [expr {int(double($size)*0.96 + 0.5)}] \
			-variable [namespace parent]::Values($type,diagram,image-size) \
			-value $size \
			;
		grid columnconfigure $f $col -minsize $::theme::padding
		grid $f.$size -column [incr col] -row 1
		incr col
	}
	ToggleUseImages $selbox $f $lt.size
	$rt.images.use configure -command [namespace code [list ToggleUseImages $selbox $f $lt.size]]
	bind $selbox <<ListboxSelect>> [namespace code [list UseDiagram %d $f]]

	grid $rt.images.use -column 1 -row 1 -sticky w
	grid $rt.images.selection -column 1 -row 3 -sticky ew
	grid $rt.images.sizes -column 1 -row 5 -sticky w
	grid rowconfigure $rt.images {2 4} -minsize $::theme::padding

	### Gridding ################################################################
	grid $lt.layout -row 1 -column 1 -sticky nsew
	grid $lt.size   -row 3 -column 1 -sticky nsew
	grid $lt.vis    -row 5 -column 1 -sticky nsew
	grid rowconfigure $lt {2 4} -minsize $::theme::padding
	grid rowconfigure $lt {1 3 5} -weight 1

	grid $rt.movers  -row 1 -column 1 -sticky w
	grid $rt.arrows  -row 3 -column 1 -sticky w
	grid $rt.markers -row 5 -column 1 -sticky w
	grid $rt.sep     -row 7 -column 1 -sticky ew
	grid $rt.images  -row 9 -column 1 -sticky nsew
	grid rowconfigure $rt {0 2 4 10} -minsize $::theme::padding
	grid rowconfigure $rt {6 8} -minsize [expr {2*$::theme::padding}]
	grid rowconfigure $rt {6 10} -weight 1
	grid columnconfigure $rt {0 2} -minsize $::theme::padding

	grid $lt -row 1 -column 1 -sticky ns
	grid $rt -row 1 -column 3 -sticky ns
	grid rowconfigure $w {0 2} -minsize $::theme::padding
	grid rowconfigure $w {1} -weight 1
	grid columnconfigure $w {0 4} -minsize $::theme::padding
	grid columnconfigure $w {2} -minsize [expr {2*$::theme::padding}]
}


proc SearchDiagramStyles {} {
	variable [namespace parent]::DiagramStyles
	variable [namespace parent]::DiagramSizes
	variable [namespace parent]::Info

	if {[info exists DiagramStyles]} { return }

	set diagramStyles {}
	set DiagramStyles {}
	set DiagramSizes {}
	set path [file join $scidb::dir::share pdf sets]

	foreach sub1 [glob -directory $path -nocomplain -types d *] {
		foreach sub2 [glob -directory $sub1 -nocomplain -types d *] {
			set size [file tail $sub2]
			if {$size ni $DiagramSizes} { lappend DiagramSizes $size }
			foreach sub3 [glob -directory $sub2 -nocomplain -types d *] {
				foreach sub4 [glob -directory $sub3 -nocomplain -types d *] {
					set style [file tail $sub1]
					set pieces [file tail $sub4]
					set sample [file join $sub4 sample.png]
					if {[file exists $sample]} {
						lappend diagramStyles [list $sample $style $pieces]
					}
					lappend sizes($style,$pieces) $size
				}
			}
		}
	}

	foreach entry $diagramStyles {
		lassign $entry sample style pieces
		lappend DiagramStyles [list $sample $style $pieces $sizes($style,$pieces)]
	}

	set DiagramSizes [lsort -integer $DiagramSizes]
	set DiagramStyles [lsort -dictionary -index 0 $DiagramStyles]
}


proc UseDiagram {index sizes} {
	variable [namespace parent]::Info
	variable [namespace parent]::Values

	set type $Values(Type)
	lassign [lindex $Info(diagram:list) $index] value usedSizes
	set Values($type,diagram,image-style) $value
	CheckSizes $sizes $usedSizes
}


proc ToggleUseImages {selbox sizes {sizeFrame {}}} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set type $Values(Type)
	set index [lsearch -exact -index 0 $Info(diagram:list) $Values($type,diagram,image-style)]
	if {$Values($type,diagram,use-images)} { set state normal } else { set state disabled }
	$selbox configure -state $state
	$selbox select none
	$selbox select $index

	if {$state eq "disabled"} {
		set usedSizes {}
	} else {
		set usedSizes [lindex $Info(diagram:list) $index 1]
	}
	CheckSizes $sizes $usedSizes

	if {[llength $sizeFrame]} {
		if {$state eq "normal"} { set state disabled } else { set state normal }
		foreach w [winfo children $sizeFrame] { $w configure -state $state }
	}
}


proc CheckSizes {sizes usedSizes} {
	variable [namespace parent]::DiagramSizes
	variable [namespace parent]::Values

	set type $Values(Type)

	foreach size $DiagramSizes {
		if {$size in $usedSizes} { set state normal } else { set state disabled }
		$sizes.$size configure -state $state
	}

	if {[llength $usedSizes] && $Values($type,diagram,image-size) ni $usedSizes} {
		$sizes.[lindex $usedSizes end] invoke
	}
}


proc SetPerspective {side} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set type $Values(Type)

	if {$Info(diagram,$side-perspective)} {
		if {$side eq "white"} { set side black } else { set side white }
		set Info(diagram,$side-perspective) 0
	}

	if {$Info(diagram,white-perspective)} {
		set Values($type,diagram,perspective) white
	} elseif {$Info(diagram,black-perspective)} {
		set Values($type,diagram,perspective) black
	} else {
		set Values($type,diagram,perspective) {}
	}
}


proc Setup {pane} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set type $Values(Type)
	set Info(diagram,white-perspective) 0
	set Info(diagram,black-perspective) 0

	switch $Values($type,diagram,perspective) {
		white { set Info(diagram,white-perspective) 1 }
		black { set Info(diagram,black-perspective) 1 }
	}
}

} ;# namespace diagram


namespace eval annotation {

proc BuildFrame {w} {
	variable [namespace parent]::NagMapping
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set languages {}
	foreach code $::mc::languages {
		lappend languages [list $code $::encoding::mc::Lang($code)]
	}
	set languages [lsort -index 1 $languages]

	set f $w.lang
	ttk::checkbutton $w.use \
		-text "[set [namespace parent]::mc::MapNagsToComment]" \
		-command [namespace code ToggleNagsToComments] \
		-variable [namespace parent]::Info(nag,lang,use) \
		;
	ttk::labelframe $f -labelwidget $w.use
	set Info(nag:lang) {}

	set top [ttk::frame $f.top]
	set spacing {0}
	set column 1
	foreach entry $languages {
		lassign $entry lang name
		set flag $::country::icon::flag([set ::mc::langToCountry($lang)])
		ttk::radiobutton $top.$lang \
			-text $name \
			-image [::icon::makeStateSpecificIcons $flag] \
			-compound left \
			-value $lang \
			-variable [namespace parent]::Info(nag,lang) \
			-command [namespace code UpdateLanguage] \
			;
		grid $top.$lang -row 1 -column $column -sticky w
		lappend Info(nag:lang) $top.$lang
		lappend spacing [incr column]
		incr column
	}
	grid columnconfigure $top $spacing -minsize $::theme::padding

	set bot [ttk::frame $f.bot]
	ttk::radiobutton $bot.unusual \
		-text [set [namespace parent]::mc::UnusualAnnotation] \
		-variable [namespace parent]::Info(nag,lang,all) \
		-command [namespace code UpdateLanguage] \
		-value 0 \
		;
	lappend Info(nag:lang) $bot.unusual
	ttk::radiobutton $bot.all \
		-text [set [namespace parent]::mc::AllAnnotation] \
		-variable [namespace parent]::Info(nag,lang,all) \
		-command [namespace code UpdateLanguage] \
		-value 1 \
		;
	lappend Info(nag:lang) $bot.all
	grid $bot.unusual -row 1 -column 1
	grid $bot.all     -row 1 -column 3
	grid columnconfigure $bot {0 2 4} -minsize $::theme::padding

	grid $f.top -row 1 -column 1 -sticky w
	grid $f.bot -row 3 -column 1 -sticky w
	grid rowconfigure $f {0 2 4} -minsize $::theme::padding

	set scrolled [::scrolledframe $w.mapping \
		-background [::colors::lookup theme,background] \
		-borderwidth 1 \
		-relief sunken \
		-expand x \
	]
	set f [ttk::frame $scrolled.f -borderwidth 0]
	grid $f -sticky nsew
	set index 0
	set row 1
	set spacing1 {0}
	set spacing2 {}
	set alliedList {}

	foreach group $NagMapping(skak) {
		lassign $group to allied from related
		if {[llength $from] && $to ni $alliedList} {
			if {$allied} { lappend alliedList $allied }
			ttk::label $f.to$to \
				-text "[set [namespace parent]::mc::MapTo]: $::annotation::mc::Nag($to) (\$$to)"
				;
			if {![info exists bold]} {
				set font [$f.to$to cget -font]
				if {[llength $font] == 0} { set font TkDefaultFont }
				set bold [list [font configure $font -family]  [font configure $font -size] bold]
			}
			$f.to$to configure -font $bold
			grid $f.to$to -row $row -column 1 -sticky ew
			incr row
			foreach nag $from {
				set Info(mapping,$nag) 0
				ttk::checkbutton $f.from$nag \
					-text "$::annotation::mc::Nag($nag) (\$$nag)" \
					-variable [namespace parent]::Info(mapping,$nag) \
					-onvalue $to \
					-offvalue 0 \
					-command [namespace code [list MappingSelected $nag $group]] \
					;
				bind $f.from$nag <FocusIn> [namespace code [list $scrolled see %W]]
				lappend spacing1 $row
				grid $f.from$nag -row [incr row] -column 1 -sticky ew
				incr row
			}
			lappend spacing2 $row
			incr row
			incr index
		}
	}

	lappend spacing1 [lindex $spacing2 end]
	set spacing2 [lreplace $spacing2 end end]
	grid rowconfigure $f $spacing1 -minsize $::theme::padding
	grid rowconfigure $f $spacing2 -minsize [expr {2*$::theme::padding}]
	grid columnconfigure $f {0 2} -minsize $::theme::padding

	grid $w.lang     -row 1 -column 1 -sticky nsew
	grid $w.mapping  -row 3 -column 1 -sticky nsew
	grid rowconfigure $w {0 4} -minsize $::theme::padding
	grid rowconfigure $w {2} -minsize [expr {2*$::theme::padding}]
	grid rowconfigure $w {3} -weight 1
	grid columnconfigure $w {0 2} -minsize $::theme::padding
}


proc ToggleNagsToComments {} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set type $Values(Type)

	if {$Info(nag,lang,use)} {
		set state normal
		set Values($type,nag,lang) $Info(nag,lang)
	} else {
		set state disabled
		set Values($type,nag,lang) {}
	}

	foreach w $Info(nag:lang) { $w configure -state $state }
}


proc UpdateLanguage {} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set type $Values(Type)
	set Values($type,nag,all) $Info(nag,lang,all)
	set Values($type,nag,lang) $Info(nag,lang)
}


proc MappingSelected {nag group} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info
	variable [namespace parent]::NagMapping

	set type $Values(Type)
	lassign $group to allied from related

	if {$allied} {
		set n [lsearch -integer -index 0 $NagMapping(skak) $allied]
		lassign [lindex $NagMapping(skak) $n] toA alliedA fromA relatedA
		set n [lsearch -integer $from $nag]
		set nagA [lindex $fromA $n]
		if {$Info(mapping,$nag) == 0} { set val 0 } else { set val $allied }
		set Info(mapping,$nagA) $val

		if {[llength $relatedA]} {
			set i [lsearch -integer $fromA $nagA]
			set nagR [lindex $relatedA $i]
			if {$Info(mapping,$nagA) == 0} { set val 0 } else { set val $toA }
			set Info(mapping,$nagR) $val
		}
	}

	if {[llength $related]} {
		set i [lsearch -integer $from $nag]
		set nagR [lindex $related $i]
		if {$Info(mapping,$nag) == 0} { set val 0 } else { set val $to }
		set Info(mapping,$nagR) $val
	}

	set type $Values(Type)
	set mapping {}

	foreach key [array names Info mapping,*] {
		if {$Info($key)} {
			lappend mapping [list [lindex [split $key ,] 1] $Info($key)]
		}
	}

	set Values($type,nag,mapping) $mapping
}


proc Setup {pane} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set type $Values(Type)
	foreach key [array names Info mapping,*] { set Info($key) 0 }

	foreach pair $Values($type,nag,mapping) {
		lassign $pair from to
		set Info(mapping,$from) $to
	}

	set Info(nag,lang) $Values($type,nag,lang)
	set Info(nag,lang,use) [expr {[llength $Values($type,nag,lang)] > 0}]
	if {[llength $Info(nag,lang)] == 0} { set Info(nag,lang) $::mc::langID }
	set Info(nag,lang,all) $Values($type,nag,all)

	ToggleNagsToComments
}

} ;# namespace annotation


namespace eval style {

proc BuildFrame {w} {
	variable [namespace parent]::StyleLayout
	variable [namespace parent]::Styles
	variable [namespace parent]::Values
	variable [namespace parent]::Info
	variable [namespace parent]::icon::13x13::checked
	variable [namespace parent]::icon::13x13::unchecked

	if {[winfo exists $w.t]} {
		foreach child [winfo children $w] { destroy $child }
	}

	treectrl $w.t \
		-borderwidth 1 \
		-relief sunken \
		-background white \
		-linestyle solid \
		-showheader 0 \
		-showbuttons no \
		-width 200 \
		-takefocus 1 \
		-xscrollincrement 1 \
		;
	bind $w.t <ButtonPress-1> [namespace code [list SelectStyle %W %x %y]]
	set height [font metrics [$w.t cget -font] -linespace]
	if {$height < 18} { set height 18 }
	$w.t configure -itemheight $height
	$w.t state define CHECK

	$w.t column create -tags item
	$w.t configure -treecolumn item
	$w.t element create elemTxt text -lines 1
	$w.t element create elemSel rect -fill {#ffdd76 selected} -showfocus 1
	$w.t element create elemCheck image -image [list $checked CHECK $unchecked {}]

	$w.t style create styText
	$w.t style elements styText {elemSel elemTxt}
	$w.t style layout styText elemTxt -padx {4 0}
	$w.t style layout styText elemSel -union {elemTxt} -ipadx 2

	$w.t style create styCheck
	$w.t style elements styCheck [list elemSel elemCheck elemTxt]
	$w.t style layout styCheck elemCheck -expand nws -padx {4 0}
	$w.t style layout styCheck elemTxt -padx {4 0}
	$w.t style layout styCheck elemSel -union {elemCheck elemTxt} -ipadx 2

	set parent(0) root
	foreach entry $StyleLayout($Values(Type)) {
		lassign $entry depth name
		if {$depth == 0} {
			$w.t item style set root item styText
			$w.t item element configure root item elemTxt -text [set [namespace parent]::mc::$name]
		} else {
			incr depth -1
			set item [$w.t item create -button 1 -tags $name]
			if {$name eq "ColumnStyle"} { set style styCheck } else { set style styText }
			$w.t item style set $item item $style
			$w.t item element configure $item item elemTxt -text [set [namespace parent]::mc::$name]
			$w.t item lastchild $parent($depth) $item
			incr depth
			set parent($depth) $item
		}
	}
	$w.t notify bind $w.t <Selection> [namespace code [list StyleSelected $w.t %S]]
	bind $w.t <ButtonPress-1> +[namespace code { ToggleCheck %W %x %y }]
	bind $w.t <Key-space> [namespace code { ToggleCheck %W }]

	ttk::scrollbar $w.sh -orient horizontal -command [list $w.t xview]
	$w.t notify bind $w.sh <Scroll-x> { ::scrolledframe::sbset %W %l %u }
	bind $w.sh <ButtonPress-1> [list focus $w.t]
	ttk::scrollbar $w.sv -orient vertical -command [list $w.t yview]
	$w.t notify bind $w.sv <Scroll-y> { ::scrolledframe::sbset %W %l %u }
	bind $w.sv <ButtonPress-1> [list focus $w.t]

	set type $Values(Type)
	set Info(column-style) $Styles($type,BasicStyle,GameText,Moves,MainLine,ColumnStyle)
	set var [namespace parent]::Info(column-style)
	set cmd [namespace code [list UpdateColumnStyle $w.t]]
	trace add variable $var write $cmd
	set Info(style) [lindex $StyleLayout($Values(Type)) 0 1]
	set Info(fontstyle) $Info(style)
	set basic $Styles($type,$Info(style))
	lassign $basic family size weight slant color
	set font [font create -family $family -size $size -weight $weight -slant $slant]
	if {$family eq "Helvetica"} {
		variable ::dialog::choosefont::fontFamilies
		set helvetica $fontFamilies(Helvetica)
		array set attrs [font actual $font]
		set index 0
		# Windows substitutes Arial for every family it lacks, so the first
		# candidates never match: the index must advance or this never ends
		while {$index < [llength $helvetica] && [string compare -nocase $attrs(-family) $family]} {
			set family [lindex $helvetica $index]
			incr index
			font delete $font
			set font [font create -family $family -size $size -weight $weight -slant $slant]
			array set attrs [font actual $font]
		}
		if {[string compare -nocase $attrs(-family) $family] == 0} {
			lset Styles($type,$Info(style)) 0 $family
		}
	}
	::dialog::choosefont::embedFrame $w.fontsel $font -color $color
	bind $w.fontsel <<FontSelected>> [namespace code [list FontSelected %d]]
	bind $w.fontsel <<FontColor>> [namespace code [list FontColor %d]]

	set Info(fontsel) $w.fontsel
	set Info(fonttree) $w.t

	grid $w.t  			-row 1 -column 1 -sticky nsew
	grid $w.sv			-row 1 -column 2 -sticky ns
	grid $w.sh			-row 2 -column 1 -sticky ew
	grid $w.fontsel	-row 1 -column 4 -sticky nsew -rowspan 2

	grid columnconfigure $w 4 -weight 1
	grid columnconfigure $w {0 3 5} -minsize $::theme::padding
	grid columnconfigure $w 3 -minsize [expr {2*$::theme::padding}]
	grid rowconfigure $w 1 -weight 1
	grid rowconfigure $w {0 3} -minsize $::theme::padding
}


proc UpdateColumnStyle {tree args} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info
	variable [namespace parent]::Styles

	if {$Info(column-style)} { set inv {} } { set inv ! }
	$tree item state set [$tree item id ColumnStyle] ${inv}CHECK
	set Styles($Values(Type),BasicStyle,GameText,Moves,MainLine,ColumnStyle) $Info(column-style)
}


proc UpdateCheck {tree item} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info
	variable [namespace parent]::Styles

	if {[$tree item id $item] == [$tree item id ColumnStyle]} {
		set Info(column-style) [expr {!$Info(column-style)}]
	}
}


proc ToggleCheck {tree {x {}} {y {}}} {
	if {[llength $x]} {
		set id [$tree identify $x $y]

		if {[llength $id] && [lindex $id 0] ne "header"} {
			set item [lindex $id 1]
			if {$item == [$tree item id ColumnStyle]} {
				UpdateCheck $tree $item
			}
		}
	} else {
		UpdateCheck $tree active
	}
}


proc StyleSelected {tree index} {
	variable [namespace parent]::StyleLayout
	variable [namespace parent]::Styles
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set type $Values(Type)
	set style ""
	set parent $index
	while {[llength $parent]} {
		set style [join [list [lindex $StyleLayout($Values(Type)) $parent 1] {*}$style] ","]
		set parent [$tree item parent $parent]
	}

	if {[string match *,ColumnStyle $style]} {
		set style [join [lrange [split $style ","] 0 end-1] ","]
	}

	set Info(style) $style
	set Info(fontstyle) $Info(style)
	lassign {{} {} {} {} {}} family size weight slant color
	set style [join [lreplace [split $style ","] end end] ","]
	while {[llength $style]} {
		lassign $Styles($type,$style) f s w l c
		set style [join [lreplace [split $style ","] end end] ","]
		if {[llength $family] == 0} { set family $f }
		if {[llength $size  ] == 0} { set size   $s }
		if {[llength $weight] == 0} { set weight $w }
		if {[llength $slant ] == 0} { set slant  $l }
		if {[llength $color ] == 0} { set color  $c }
	}
	set Info($type,font,family) $family
	set Info($type,font,size)   $size
	set Info($type,font,weight) $weight
	set Info($type,font,slant)  $slant
	set Info($type,font,color)  $color

	lassign $Styles($type,$Info(fontstyle)) f s w l c
	if {[llength $f]} { set family $f }
	if {[llength $s]} { set size   $s }
	if {[llength $w]} { set weight $w }
	if {[llength $l]} { set slant  $l }
	if {[llength $c]} { set color  $c }

	set Info(fontType) [lindex $StyleLayout($Values(Type)) $index 1]

	switch -glob -- $Info(fontType) {
		Figurines	{ set fonts $::font::chessFigurineFonts }
		Diagram		{ set fonts $::font::chessDiagramFonts }
		Symbols		{ set fonts $::font::chessSymbolFonts }

		default		{
			if {$type eq "tex"} {
				set Info(fonts) {{Avant Garde} Bookman Chancery Charter Courier Fixed Fourier \
										Helvetica {Latin Modern} {New Century} Palatino Times}
			} elseif {$Values(pdf,fonts,builtin)} {
				set Info(fonts) {Courier Helvetica Times-Roman}
			} else {
				set Info(fonts) {}
			}
			set fonts $Info(fonts)
		}
	}

	if {$type eq "tex"} {
		set sizes {8 9 10 11 12 14 17 20 25}
		set units pt
	} else {
		set sizes {}
		set units {}
	}

	::dialog::choosefont::setFonts $Info(fontsel) $fonts
	::dialog::choosefont::setSizes $Info(fontsel) $sizes $units
	UpdateSample $family
	::dialog::choosefont::select $Info(fontsel) \
		-family $family \
		-size $size \
		-weight $weight \
		-slant $slant \
		-color $color
}


proc UpdateSample {family} {
	variable [namespace parent]::Info

	set sample ""

	switch $Info(fontType) {
		Diagram {
			upvar 0 ::font::[set ::font::chessDiagramFontsMap([string tolower $family])] encoding
			foreach code {lite,wk lite,wq lite,wr lite,wb lite,wn lite,wp} {
				append sample $encoding($code)
			}
		}

		Symbols {
			set sample ""
			upvar 0 ::font::[set ::font::chessSymbolFontsMap([string tolower $family])] encoding
			foreach nag {7 13 14 16 40 140 142 149 151 156} {
				if {[info exists encoding($nag)]} {
					if {[llength $sample]} { append sample " " }
					append sample $encoding($nag)
				}
			}
			set i [expr {[string length $sample]/2}]
			set sample [string replace $sample $i [expr {$i + 1}] "\n"]
		}

		Figurines {
			variable ::font::chessFigurineFontsMap
			set encoding $chessFigurineFontsMap([string tolower  $family])
			set sample [join $::figurines::langSet(graphic) " "]
			if {[llength $encoding]} { set sample [string map $encoding $sample] }
		}

		default {
			set sample {}
		}
	}

	::dialog::choosefont::setSample $Info(fontsel) $sample
}


proc FontColor {color} {
	variable [namespace parent]::Values
	variable [namespace parent]::Styles
	variable [namespace parent]::Info

	set type $Values(Type)
	set color [::colors::getActualColor $color]
	if {$color eq $Info($type,font,color)} { set color {} }
	lset Styles($type,$Info(fontstyle)) 4 $color
}


proc FontSelected {fontInfo} {
	variable [namespace parent]::StyleLayout
	variable [namespace parent]::Styles
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set type $Values(Type)
	lassign $fontInfo family size weight slant
	set color [lindex $Styles($type,$Info(fontstyle)) 4]

	if {$Info(fontstyle) ne [lindex $StyleLayout($Values(Type)) 0 1]} {
		foreach item {family size weight slant} {
			if {[set $item] eq $Info($type,font,$item)} { set $item {} }
		}
	}

	set Styles($type,$Info(fontstyle)) [list $family $size $weight $slant $color]
	switch $Info(fontType) { Symbols - Diagram - Figurines { UpdateSample $family } }
}


proc SelectStyle {tree x y} {
	set id [$tree identify $x $y]
	if {[string length $id] == 0} { return }
	if {[lindex $id 0] eq "header"} { return }
	set item [lindex $id 1]
	$tree selection anchor $item
	$tree selection modify $item all
}


proc UseBuiltinFonts {} {
	variable Info

	if {[info exists Info(fontsel)]} {
		StyleSelected $Info(fonttree) 0
	}
}


proc Setup {pane} {
	variable [namespace parent]::Info

	$Info(fonttree) activate 0
	$Info(fonttree) select clear
	$Info(fonttree) select add 0
}

} ;# namespace style


namespace eval comment {

proc BuildFrame {pane} {
	variable [namespace parent]::Info
	variable [namespace parent]::Values
	variable [namespace parent]::Languages

	set type $Values(Type)

	set lt [ttk::labelframe $pane.lt -text [set [namespace parent]::mc::LanguageSelection]]

	if {[info exists Info(languages)] && [llength $Info(languages)] == 0} {
		ttk::label $lt.msg -text [set [namespace parent]::mc::GameDoesNotHaveComments]
		grid $lt -row 1 -column 1 -sticky ns
		grid rowconfigure $pane {1} -weight 1
		grid columnconfigure $pane {0 2} -minsize $::theme::padding
		pack $lt.msg -padx $::theme::padding -pady $::theme::padding
		return
	}

	set rt [ttk::labelframe $pane.rt -text [set [namespace parent]::mc::Hyphenation]]

	### Choose Languages ####################################################################
	set sel [ttk::frame $lt.selection -borderwidth 0]
	if {[info exists Info(languages)]} {
		lremove Info(languages) ""
		lremove Info(preferred) ""
		set elem $Values(Type),comments,languages
		set Values($elem) {}
		set row 1
		grid rowconfigure $sel 0 -minsize $::theme::padding
		foreach lang $Info(languages) {
			set country [set ::mc::langToCountry($lang)]
			set flag $::country::icon::flag($country)
			set Info(lang:check:$lang) $sel.lang$lang
			set Info(lang:check:$lang:value) [expr {$lang in $Info(preferred)}]
			if {$Info(lang:check:$lang:value)} { lappend Values($elem) $lang }
			ttk::checkbutton $sel.lang$lang \
				-compound left \
				-text [::encoding::languageName $lang] \
				-image $flag \
				-variable [namespace parent]::Info(lang:check:$lang:value) \
				-command [namespace code [list AddRemoveLang $lang]] \
				;
			grid $sel.lang$lang -row $row -column 1 -sticky ew
			grid rowconfigure $sel [expr {$row + 1}] -minsize $::theme::padding
			incr row 2
		}
		grid columnconfigure $sel {0 2} -minsize $::theme::padding
		if {[llength $Info(preferred)] == 0} {
			set mode none
		} elseif {[llength $Info(languages)] == [llength $Info(preferred)]} {
			set mode all
		} else {
			set mode ""
		}
		set Info(lang,comments,languages) $mode
	} else {
		set row 1
		set n [llength $Values($type,comments,languages)]
		for {set i 1} {$i < $n} {incr i} {
			set Info(lang:box$i) $sel.list$i
			set Info(lang:check$i) $sel.check$i
			set Info(lang:check$i:value) 0
			ttk::label $sel.no$i -text "$i."
			::languagebox $sel.list$i -none [expr {$i > 1}] -width 0
			ttk::checkbutton $sel.check$i -variable [namespace parent]::Info(lang:check$i:value)
			bind $sel.list$i <<ComboboxCurrent>> +[namespace code [list UpdateLanguages $i]]
			grid $sel.no$i    -row $row -column 1 -sticky w
			grid $sel.list$i  -row $row -column 3 -sticky ew
			grid $sel.check$i -row $row -column 5 -sticky ew
			incr row 2
		}
		grid rowconfigure $sel {2 4 6 8 10} -minsize $::theme::padding
		grid columnconfigure $sel {2 4} -minsize $::theme::padding
		grid columnconfigure $sel {3} -weight 1
		set Info(lang,comments,languages) $Values($type,comments,languages)
	}

	ttk::separator $lt.sep
	ttk::radiobutton $lt.none \
		-text [set [namespace parent]::mc::NoComments] \
		-variable [namespace parent]::Info(lang,comments,languages) \
		-command [namespace code ConfigureWidgets] \
		-value none \
		;
	ttk::radiobutton $lt.all \
		-text [set [namespace parent]::mc::AllLanguages] \
		-variable [namespace parent]::Info(lang,comments,languages) \
		-command [namespace code ConfigureWidgets] \
		-value all \
		;
	ttk::radiobutton $lt.select \
		-text [set [namespace parent]::mc::SelectLanguages] \
		-variable [namespace parent]::Info(lang,comments,languages) \
		-command [namespace code ConfigureWidgets] \
		-value {} \
		;

	grid $lt.none   -row 1 -column 1 -sticky we
	grid $lt.all    -row 3 -column 1 -sticky we
	grid $lt.select -row 5 -column 1 -sticky we
	grid $lt.sep    -row 7 -column 1 -sticky we
	grid $sel       -row 9 -column 1 -sticky we

	grid rowconfigure $lt {0 2 4 6 8 10} -minsize $::theme::padding

	if {![info exists Info(languages)]} {
		set Info(lang,descr) [message $lt.descr \
			-relief sunken \
			-borderwidth 1 \
			-justify left \
			-anchor nw \
			-text [set [namespace parent]::mc::LanguageSelectionDescr] \
			-width 240 \
		]
		grid $lt.descr -row 1 -column 3 -sticky nswe -rowspan 9
		grid columnconfigure $lt {0 2 4} -minsize $::theme::padding
	} else {
		grid columnconfigure $lt {0 2} -minsize $::theme::padding
	}

	### Default Language ####################################################################
	if {![info exists Info(languages)]} {
		set Info(languages,hyph) [list [list none [set [namespace parent]::mc::None]]]
		foreach lang $Languages {
			lappend Info(languages,hyph) [list $lang [::encoding::languageName $lang]]
		}
		set Info(languages,hyph) [lsort -dictionary -index 1 $Info(languages,hyph)]
		ttk::frame $rt.list
		set selbox [::tlistbox $rt.list.selection -borderwidth 1 -pady 1 -minwidth 180]
		$selbox addcol image -id icon
		$selbox addcol text -id name -expand yes
		foreach entry $Info(languages,hyph) {
			lassign $entry lang name
			set img $::country::icon::flag([::mc::countryForLang $lang])
			$selbox insert [list $img $name]
		}
		$selbox resize
		pack $selbox -anchor s
		pack $rt.list -padx $::theme::padding -pady $::theme::padding -fill y -expand yes
		bind $rt.list <Configure> [list [namespace parent]::ConfigureTListbox %W %h]
		bind $selbox <<ListboxSelect>> [namespace code [list SetLanguage %d]]
		set Info(lang:primary) $selbox
	}

	### Gridding ############################################################################
	grid $lt -row 1 -column 1 -sticky ns
	grid $rt -row 1 -column 3 -sticky ns
	grid rowconfigure $pane {0 2} -minsize $::theme::padding
	grid rowconfigure $pane {1} -weight 1
	grid columnconfigure $pane {0 4} -minsize $::theme::padding
	grid columnconfigure $pane {2} -minsize [expr {2*$::theme::padding}]
}


proc ShowHyphenation {w enable} {
	if {$enable} {
		grid $w.rt
		Setup
	} else {
		grid remove $w.rt
	}
}


proc SetLanguage {index} {
	variable [namespace parent]::Info
	variable [namespace parent]::Values

	set type $Values(Type)
	set Values($type,comments,hyphenation) [lindex $Info(languages,hyph) $index 0]
}


proc AddRemoveLang {lang} {
	variable [namespace parent]::Info
	variable [namespace parent]::Values

	set elem $Values(Type),comments,languages
	if {$Info(lang:check:$lang:value)} {
		if {$lang ni $Values($elem)} {
			lappend Values($elem) $lang
		}
	} else {
		set i [lsearch -exact $Values($elem) $lang]
		if {$i >= 0} { set Values($elem) [lreplace $Values($elem) $i $i] }
	}
}


proc ConfigureWidgets {} {
	variable [namespace parent]::Info
	variable [namespace parent]::Values

	set type $Values(Type)
	set selection $Info(lang,comments,languages)

	if {[info exists Info(languages)]} {
		switch $selection {
			all	{ set Values($Values(Type),comments,languages) $Info(languages) }
			none	{ set Values($Values(Type),comments,languages) {} }
			default {
				set Values($Values(Type),comments,languages) {}
				foreach lang $Info(languages) {
					if {$Info(lang:check:$lang:value)} {
						lappend Values($Values(Type),comments,languages) $lang
					}
				}
			}
		}
	}

	if {$selection in {all none}} {
		set color gray
		set state disabled
	} else {
		set color black
		set state readonly
	}

	if {[winfo exists $Info(lang,descr)]} {
		$Info(lang,descr) configure -foreground $color

		set n [llength $Values($type,comments,languages)]
		for {set i 1} {$i < $n} {incr i} {
			$Info(lang:box$i) configure -state $state
			$Info(lang:check$i) configure -state $state
		}
	} else {
		foreach lang $Info(languages) {
			$Info(lang:check:$lang) configure -state $state
		}
	}
}


proc Setup {{pane ""}} {
	variable [namespace parent]::Info
	variable [namespace parent]::Values

	if {[info exists Info(languages)]} {
		return
	}

	set type $Values(Type)
	set selection [lindex $Values($type,comments,languages) 0]

	switch $selection {
		* {
			lset Values($type,comments,languages) 1 [list $::mc::langID 1]
			if {$::mc::langID ne "en"} { lset Values($type,comments,languages) 2 {en 0} }
			if {$type eq "scidb"} {
				lset Values($type,comments,languages) 0 all
				set Info(lang,comments,languages) all
			} else {
				set Info(lang,select) {}
				lset Values($type,comments,languages) 0 {}
				set Info(lang,comments,languages) {}
			}
		}

		all - none {
			$Info(lang,descr) configure -foreground gray
			set Info(lang,comments,languages) $selection
			set state disabled
		}

		default {
			set Info(lang,comments,languages) {}
			set state readonly
		}
	}

	set n [llength $Values($type,comments,languages)]
	for {set i 1} {$i < $n} {incr i} {
		lassign {"" 0} lang significant
		lassign [lindex $Values($type,comments,languages) $i] lang significant
		$Info(lang:box$i) set $lang
		set Info(lang:check$i:value) $significant
	}

	if {[info exists Values($type,comments,hyphenation)]} {
		set lang [lsearch -exact -index 0 $Info(languages,hyph) $Values($type,comments,hyphenation)]
		$Info(lang:primary) select $lang
	}

	ConfigureWidgets
}


proc UpdateLanguages {index} {
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	set type $Values(Type)
	set lang [$Info(lang:box$index) value]
	set significant $Info(lang:check$index:value)
	lset Values($type,comments,languages) $index [list $lang $significant]
}

} ;# namespace comment


namespace eval page_pdf { proc BuildFrame {w} { [namespace parent]::page::BuildFrame $w } }
namespace eval page_tex { proc BuildFrame {w} { [namespace parent]::page::BuildFrame $w } }


namespace eval page {

namespace import ::tcl::mathfunc::double
namespace import ::tcl::mathfunc::round
namespace import ::tcl::mathfunc::min

proc BuildFrame {w} {
	variable [namespace parent]::Paper
	variable [namespace parent]::Info
	variable [namespace parent]::Values
	variable [namespace parent]::Colors
	variable [namespace parent]::DocumentStyle

	set type $Values(Type)
	set Info($type,formats) {}
	foreach format $Paper($type) {
		lassign $format id width height units
		lappend Info($type,formats) "$id ($width x $height $units)"
	}
	if {$Info(useCustom)} {
		lassign $Values($type,paper,custom) \
			Info($type,paper,width) Info($type,paper,height) Info($type,paper,units)
		lappend Info($type,formats) [set [namespace parent]::mc::Custom]
		set Info($type,paper,units,textvar) $Info($type,paper,units)
	}
	if {$Values($type,paper,format) eq "_Custom_"} {
		set n [llength $Paper($type)]
	} else {
		set n [lsearch -exact -index 0 $Paper($type) $Values($type,paper,format)]
	}
	set Info($type,paper,textvar) [lindex $Info($type,formats) $n]

	canvas $w.c \
		-borderwidth 1 \
		-relief sunken \
		-width 1 \
		-height 1 \
		-background [::colors::lookup theme,background] \
		;
	set shadowColor [::colors::lookup $Colors(shadow)]
	$w.c xview moveto 0
	$w.c yview moveto 0
	$w.c create rectangle 0 0 0 0 -tag shadow -fill $shadowColor -outline $shadowColor
	$w.c create rectangle 0 0 0 0 -tag paper -fill white -outline black
	$w.c create rectangle 0 0 0 0 -tag left -fill white -outline [::colors::lookup $Colors(text)]
	$w.c create rectangle 0 0 0 0 -tag right -fill white -outline [::colors::lookup $Colors(text)]

	if {$type eq "tex"} {
		set Info(tex,paper,document-styles) {}
		foreach style $DocumentStyle {
			lappend Info(tex,paper,document-styles) [set [namespace parent]::mc::$style]
		}
		set n [lsearch -exact $DocumentStyle $Values(tex,paper,document)]
		set Info(tex,paper,document) [lindex $Info(tex,paper,document-styles) $n]
		ttk::labelframe $w.doc -text [set [namespace parent]::mc::DocumentStyle]
		ttk::combobox $w.doc.style \
			-state readonly \
			-values $Info(tex,paper,document-styles) \
			-textvariable [namespace parent]::Info(tex,paper,document) \
			;
		bind $w.doc.style <<ComboboxSelected>> [namespace code [list SelectDocumentStyle $w]]
		grid $w.doc.style -row 1 -column 1 -sticky ew
		grid rowconfigure $w.doc {0 2} -minsize $::theme::padding
		grid columnconfigure $w.doc {0 2} -minsize $::theme::padding
		grid columnconfigure $w.doc {1} -weight 1
	}
	ttk::labelframe $w.paper -text [set [namespace parent]::mc::Paper]
	if {$Info(useCustom)} {
		ttk::labelframe $w.margins -text [set [namespace parent]::mc::Margin]
	}
	ttk::labelframe $w.orient -text [set [namespace parent]::mc::Orientation]
	ttk::labelframe $w.just -text [set [namespace parent]::mc::Justification]
	ttk::labelframe $w.columns -text [set [namespace parent]::mc::Columns]

	if {$Info(useCustom)} {
		ttk::label $w.paper.lformat -text [set [namespace parent]::mc::Format]
	}
	ttk::combobox $w.paper.cbformat \
		-state readonly \
		-values $Info($type,formats) \
		-textvariable [namespace parent]::Info($type,paper,textvar) \
		;
	bind $w.paper.cbformat <<ComboboxSelected>> [namespace code [list ConfigureWidgets $w paper]]

	if {$Info(useCustom)} {
		grid $w.paper.lformat	-row 1 -column 1 -sticky w
	}
	grid $w.paper.cbformat		-row 1 -column 3 -sticky ew -columnspan 7

	if {$Info(useCustom)} {
		ttk::label $w.paper.lsize -text [set [namespace parent]::mc::Size]
		ttk::entry $w.paper.width -width 5 -textvariable [namespace parent]::Info($type,paper,width)
		::validate::entryDouble $w.paper.width
		$w.paper.width configure -validatecommand [namespace code [list SizeChanged $w %P]]
		ttk::label $w.paper.x -text "x"
		ttk::entry $w.paper.height -width 5 -textvariable [namespace parent]::Info($type,paper,height)
		::validate::entryDouble $w.paper.height
		$w.paper.height configure -validatecommand [namespace code [list SizeChanged $w %P]]
		ttk::combobox $w.paper.units \
			-state readonly \
			-values {mm in pt} \
			-width 3 \
			-textvariable [namespace parent]::Info($type,paper,units,textvar)
		bind $w.paper.units <<ComboboxSelected>> [namespace code [list ConfigureWidgets $w]]

		grid $w.paper.lsize		-row 3 -column 1 -sticky w
		grid $w.paper.width		-row 3 -column 3 -sticky ew
		grid $w.paper.x			-row 3 -column 5 -sticky ew
		grid $w.paper.height		-row 3 -column 7 -sticky ew
		grid $w.paper.units		-row 3 -column 9 -sticky ew

		grid columnconfigure $w.paper {0 2 10} -minsize $::theme::padding
	} else {
		grid columnconfigure $w.paper {0 10} -minsize $::theme::padding
	}

	grid rowconfigure $w.paper {0 2 4} -minsize $::theme::padding
	grid columnconfigure $w.paper {4 6 8} -minsize 2
	grid columnconfigure $w.paper {3 7} -weight 1

	if {$type eq "pdf"} {
		foreach dir {top bottom left right} {
			set Info($type,paper,$dir) $Values($type,paper,$dir)
		}
	}

	if {$Info(useCustom)} {
		if {$Values($type,paper,format) eq "_Custom_"} {
			set units [lindex $Values($type,paper,custom) 2]
		} else {
			set units [lindex $Paper($type) \
				[lsearch -exact -index 0 $Paper($type) $Values($type,paper,format)] 3]
		}
		foreach {dir row col} {top 1 1 bottom 3 1 left 1 5 right 3 5} {
			set text [string toupper $dir 0 0]
			if {$Info($type,paper,$dir) == 0} {
				set Info($type,paper,$dir) [DefaultMargin $dir $type $units]
			}
			ttk::label $w.margins.l$dir -text [set ::mc::$text]
			ttk::entry $w.margins.s$dir -width 5 -textvariable [namespace parent]::Info($type,paper,$dir)
			::validate::entryDouble $w.margins.s$dir
			$w.margins.s$dir configure -validatecommand [namespace code [list MarginChanged $w $dir %P]]
			grid $w.margins.l$dir -row $row -column $col -sticky w
			grid $w.margins.s$dir -row $row -column [expr {$col + 2}] -sticky ew
		}
		
		grid rowconfigure $w.margins {0 3 5} -minsize $::theme::padding
		grid columnconfigure $w.margins {0 2 6 8} -minsize $::theme::padding
		grid columnconfigure $w.margins {3 7} -weight 1
		grid columnconfigure $w.margins 4 -minsize [expr {2*$::theme::padding}]
	}

	ttk::radiobutton $w.orient.potrait \
		-text [set [namespace parent]::mc::Potrait] \
		-value Potrait \
		-command [namespace code [list RefreshPreview $w]] \
		-variable [namespace parent]::Values($type,paper,orientation) \
		;
	ttk::radiobutton $w.orient.landscape \
		-text [set [namespace parent]::mc::Landscape] \
		-value Landscape \
		-command [namespace code [list RefreshPreview $w]] \
		-variable [namespace parent]::Values($type,paper,orientation) \
		;
	grid $w.orient.potrait		-row 1 -column 1 -sticky w
	grid $w.orient.landscape	-row 1 -column 3 -sticky w
	grid rowconfigure $w.orient {0 3} -minsize $::theme::padding
	grid columnconfigure $w.orient {0 4} -minsize $::theme::padding
	grid columnconfigure $w.orient 2 -minsize [expr {2*$::theme::padding}]

	ttk::radiobutton $w.just.left \
		-text [set ::mc::Left] \
		-value 0 \
		-command [namespace code [list RefreshPreview $w]] \
		-variable [namespace parent]::Values($type,paper,justification) \
		;
	ttk::radiobutton $w.just.even \
		-text [set [namespace parent]::mc::Even] \
		-value 1 \
		-command [namespace code [list RefreshPreview $w]] \
		-variable [namespace parent]::Values($type,paper,justification) \
		;
	grid $w.just.left -row 1 -column 1 -sticky w
	grid $w.just.even -row 1 -column 3 -sticky w
	grid rowconfigure $w.just {0 3} -minsize $::theme::padding
	grid columnconfigure $w.just {0 4} -minsize $::theme::padding
	grid columnconfigure $w.just 2 -minsize [expr {2*$::theme::padding}]

	ttk::radiobutton $w.columns.one \
		-text [set [namespace parent]::mc::One] \
		-value 1 \
		-command [namespace code [list RefreshPreview $w]] \
		-variable [namespace parent]::Values($type,paper,columns) \
		;
	ttk::radiobutton $w.columns.two \
		-text [set [namespace parent]::mc::Two] \
		-value 2 \
		-command [namespace code [list RefreshPreview $w]] \
		-variable [namespace parent]::Values($type,paper,columns) \
		;
	grid $w.columns.one -row 1 -column 1 -sticky w
	grid $w.columns.two -row 1 -column 3 -sticky w
	grid rowconfigure $w.columns {0 3} -minsize $::theme::padding
	grid columnconfigure $w.columns {0 4} -minsize $::theme::padding
	grid columnconfigure $w.columns 2 -minsize [expr {2*$::theme::padding}]

	ttk::button $w.reset \
		-text [set [namespace parent]::mc::ResetDefaults] \
		-command [namespace code [list ResetPaper $w]] \
		;

	if {$type eq "tex"} {
		grid $w.doc			-row  1 -column 1 -sticky ew -columnspan 3
	}
	grid $w.paper			-row  3 -column 1 -sticky ew -columnspan 3
	if {$Info(useCustom)} {
		grid $w.margins	-row  5 -column 1 -sticky ew -columnspan 3
	}
	grid $w.orient			-row  7 -column 1 -sticky ew -columnspan 3
	grid $w.just			-row  9 -column 1 -sticky ew
	grid $w.columns		-row  9 -column 3 -sticky ew
	grid $w.reset			-row 11 -column 1 -sticky w -columnspan 3
	grid $w.c				-row  1 -column 5 -sticky nsew -rowspan 12

	if {$type eq "tex"} {
		set rows {0 2 6 8 10 13}
	} elseif {$Info(useCustom)} {
		set rows {0 4 6 8 10 13}
	} else {
		set rows {0 6 8 10 13}
	}
	grid rowconfigure $w $rows -minsize $::theme::padding
	grid rowconfigure $w 10 -minsize [expr {2*$::theme::padding}]
	grid rowconfigure $w 12 -weight 1
	grid columnconfigure $w {0 2 4 6} -minsize $::theme::padding
	grid columnconfigure $w 5 -weight 1

	ConfigureWidgets $w
	bind $w.c <Configure> [namespace code [list RefreshPreview $w]]
}


proc ResetPaper {w} {
	variable [namespace parent]::Paper
	variable [namespace parent]::Info
	variable [namespace parent]::Values
	variable [namespace parent]::Defaults
	variable [namespace parent]::DocumentStyle

	set type $Values(Type)

	array set Values [array get Defaults $type,paper,*]

	set n [lsearch -exact -index 0 $Paper($type) $Values($type,paper,format)]
	set Info($type,paper,textvar) [lindex $Info($type,formats) $n]
	set Info($type,paper,units) [GetUnits]

	if {$type eq "tex"} {
		set n [lsearch -exact $DocumentStyle $Values(tex,paper,document)]
		set Info(tex,paper,document) [lindex $Info(tex,paper,document-styles) $n]
	}

	set wantedUnits [lindex $Paper($type) $n 3]
	foreach dir {top bottom left right} {
		set Values($type,paper,$dir) 0
		set Info($type,paper,$dir) [DefaultMargin $dir $type $wantedUnits]
	}

	ConfigureWidgets $w reset
}


proc MarginChanged {w dir value} {
	variable [namespace parent]::Info
	variable [namespace parent]::Values

	set ok [SizeChanged $w $value]
	set type $Values(Type)

	if {$ok && $Info($type,paper,$dir) != $value} {
		set Values($type,paper,$dir) [string trim $value]
		after cancel $Info(after)
		set Info(after) [after 250 [namespace code [list RefreshPreview $w]]]
	}

	return $ok
}


proc GetUnits {} {
	variable [namespace parent]::Paper
	variable [namespace parent]::Info
	variable [namespace parent]::Values

	set type $Values(Type)

	if {$Values($type,paper,format) eq "_Custom_"} {
		set units $Info($type,paper,units,textvar)
	} else {
		set units [lindex $Paper($type) \
			[lsearch -exact -index 0 $Paper($type) $Values($type,paper,format)]]
	}

	return $units
}


proc SizeChanged {w value} {
	variable [namespace parent]::Info
	variable [namespace parent]::Values

	set units [GetUnits]

	if {$units eq "in"} {
		set ok [::validate::validateDouble $value]
	} else {
		set ok [::validate::validateUnsigned $value 5]
	}

	if {$ok} {
		after cancel $Info(after)
		set Info(after) [after 250 [namespace code [list RefreshPreview $w]]]
	}

	return $ok
}


proc ConfigureWidgets {w {action {}}} {
	variable [namespace parent]::Paper
	variable [namespace parent]::Values
	variable [namespace parent]::Info
	variable [namespace parent]::Defaults

	set type $Values(Type)
	set n [lsearch -exact $Info($type,formats) [$w.paper.cbformat get]]
	if {$n == [llength $Paper($type)]} {
		set Values($type,paper,format) _Custom_
	} else {
		set Values($type,paper,format) [lindex $Paper($type) $n 0]
	}

	if {$Info(useCustom)} {
		if {$Values($type,paper,format) eq "_Custom_"} {
			$w.paper.width configure -state normal
			$w.paper.height configure -state normal
			$w.paper.units configure -state readonly
			set wantedUnits $Info($type,paper,units,textvar)
		} else {
			foreach name {width height units} {
				$w.paper.$name configure -state disabled
			}
			set n [lsearch -exact -index 0 $Paper($type) $Values($type,paper,format)]
			set wantedUnits [lindex $Paper($type) $n 3]
		}

		if {$action ne "reset"} {
			set origUnits $Info($type,paper,units)
			set Info($type,paper,units) $wantedUnits

			if {$action ne "paper" && $Values($type,paper,format) eq "_Custom_"} {
				foreach attr {width height} {
					set Info($type,paper,$attr) [MapUnits $Info($type,paper,$attr) $origUnits $wantedUnits]
				}
			}

			foreach attr {top bottom left right} {
				if {$Values($type,paper,$attr) == 0} {
					set Info($type,paper,$attr) [DefaultMargin $attr $type $wantedUnits]
				} else {
					set Info($type,paper,$attr) [MapUnits $Info($type,paper,$attr) $origUnits $wantedUnits]
					set Values($type,paper,$attr) \
						[MapUnits $Values($type,paper,$attr) $origUnits $wantedUnits]
				}
			}
		}

		$w.margins configure -text "[set [namespace parent]::mc::Margin] ($wantedUnits)"
	} else {
		lassign $Defaults(pdf,margins,$Values($type,paper,format)) \
			Info($type,paper,top) Info($type,paper,bottom) \
			Info($type,paper,left) Info($type,paper,right)
	}

	RefreshPreview $w
}


proc RefreshPreview {w} {
	variable [namespace parent]::Paper
	variable [namespace parent]::Colors
	variable [namespace parent]::Random
	variable [namespace parent]::Values
	variable [namespace parent]::Info

	if {[winfo width $w.c] <= 1} { return }
	bind $w.c <Configure> {}
	after cancel $Info(after)
	set type $Values(Type)

	foreach dir {top bottom left right} {
		if {	[string match {*[0-9]*} $Info($type,paper,$dir)] ||
				[string match {*[0-9].[0-9][0-9]*} $Info($type,paper,$dir)]} {
			set margin($dir) $Info($type,paper,$dir)
		} else {
			set margin($dir) 0
		}
	}

	if {$Values($type,paper,format) eq "_Custom_"} {
		set pw $Info($type,paper,width)
		set ph $Info($type,paper,height)
		set units $Info($type,paper,units)
		set Values($type,paper,custom) [list $pw $ph $units]
	} else {
		set n [lsearch -exact -index 0 $Paper($type) $Values($type,paper,format)]
		lassign [lindex $Paper($type) $n] id pw ph units
	}
	if {[llength $pw] == 0} { set pw 0 }
	if {[llength $ph] == 0} { set ph 0 }
	if {$Values($type,paper,orientation) eq "Landscape"} {
		set tmp $pw; set pw $ph; set ph $tmp
	}

	set width  [expr {[winfo width  $w.c] - 2*[$w.c cget -borderwidth]}]
	set height [expr {[winfo height $w.c] - 2*[$w.c cget -borderwidth]}]

	set cw [double [expr {$width  - 20}]]
	set ch [double [expr {$height - 20}]]

	set pw [double $pw]
	set ph [double $ph]

	set t [double $margin(top)]
	set b [double $margin(bottom)]
	set l [double $margin(left)]
	set r [double $margin(right)]

	if {$pw == 0 || $ph == 0} {
		set u 0
	} else {
		set u [expr {min($cw/$pw, $ch/$ph)}]
	}

	set pw [expr {$u*$pw}]
	set ph [expr {$u*$ph}]

	set t [expr {round($t*$u)}]
	set b [expr {round($b*$u)}]
	set l [expr {round($l*$u)}]
	set r [expr {round($r*$u)}]

	set x0 [expr {round(($width  - $pw)/2.0)}]
	set y0 [expr {round(($height - $ph)/2.0)}]
	set x1 [expr {round($x0 + $pw)}]
	set y1 [expr {round($y0 + $ph)}]

	set lx0 [expr {$x0 + $r}]
	set ly0 [expr {$y0 + $t}]
	set lx1 [expr {max($x0 + $r, $x1 - $l)}]
	set ly1 [expr {max($y0 + $t, $y1 - $b)}]

	if {$lx0 >= $lx1 || $ly0 >= $ly1} { lassign {0 0 0 0} lx0 lx1 ly0 ly1 }
	set tn [expr {min(2, (min($x1 - $x0, $y1 - $y0)*0.05))}]

	if {$Values($type,paper,columns) == 1 || $lx1 == 0} {
		lassign {0 0 0 0 0} rx0 rx1 ry0 ry1
		set dirs {l}
	} else {
#		set gap [expr {min(6, round(0.05*($x1 - $x0)))}]
		set gap [expr {max(6,round(min($l,$r)/2.0))}]
		if {$gap % 2} { incr gap -1 }
		set xm [expr {$x0 + ($x1 - $x0)/2}]
		set rx0 [expr {min($lx1, $xm + $gap/2)}]
		set ry0 $ly0
		set rx1 $lx1
		set ry1 $ly1
		set lx1 [expr {max($lx0, $xm - $gap/2)}]
		if {$lx1 - $lx0 < $rx1 - $rx0} { incr rx0 }
		set dirs {l r}
	}
	set coords [list $lx0 $ly0 $lx1 $ly1]
	if {$Values($type,paper,columns) == 2} { lappend coords $rx0 $ry0 $rx1 $ry1 }

	$w.c coords shadow [expr {$x0 + $tn}] [expr {$y0 + $tn}] [expr {$x1 + $tn}] [expr {$y1 + $tn}]
	$w.c coords paper $x0 $y0 $x1 $y1
	$w.c coords left $lx0 $ly0 $lx1 $ly1
	$w.c coords right $rx0 $ry0 $rx1 $ry1

	set textColor [::colors::lookup $Colors(text)]
	$w.c delete line
	set i 0
	if {$lx1 > $lx0} {
		set n [llength $Random]
		set even $Values($type,paper,justification)
		foreach {x0 y0 x1 y1} $coords {
			set dx [expr {$x1 - $x0}]
			set xt 0.0
			while {$y0 < $y1} {
				set r [lindex $Random [expr {$i % $n}]]
				if {$even && ($r > 0.5 || $xt < $x1)} {
					set xt $x1
				} else {
					set xt [expr {min(max($x0, $x1 - 2), max(5, $x0 + round($r*$dx)))}]
				}
				set yt [expr {min($y1, $y0 + 2)}]
				set tags [list line line:$i]
				$w.c create rectangle $x0 $y0 $xt $yt -fill $textColor -outline {} -tags $tags
				incr y0 4
				incr i
			}
		}
		if {$i % $n == 0} { incr i 10 }
	}
}


proc MapUnits {value from to} {
	switch $from->$to {
		mm->in  { set factor [expr {1.0/25.4}] }
		mm->pt  { set factor [expr {72.0/25.4}] }
		in->mm  { set factor 25.4 }
		in->pt  { set factor 72.0 }
		pt->mm  { set factor [expr {25.4/72.0}] }
		pt->in  { set factor [expr {1.0/72.0}] }
		default { return $value }
	}

	set x [expr {$factor*double($value)}]
	set n [round $x]

	if {$to ne "in"} { return $n }
	if {abs($n - $x) < 0.02} { return $n }
	return [expr {round($x*100.0)/100.0}]
}


proc DefaultMargin {dir type units} {
	variable [namespace parent]::Defaults
	variable [namespace parent]::Values
	variable [namespace parent]::Paper
	variable [namespace parent]::Info

	if {[lsearch -exact -index 0 $Paper($type) $Values($type,paper,format)] == -1} {
		set format A4
	} else {
		set format $Values($type,paper,format)
	}

	lassign $Defaults(pdf,margins,$format) m(top) m(bottom) m(left) m(right)
	return [MapUnits $m($dir) $Info($type,paper,units) $units]
}


proc SelectDocumentStyle {w} {
	variable [namespace parent]::Info
	variable [namespace parent]::Values
	variable [namespace parent]::DocumentStyle

	set n [lsearch -exact $Info(tex,paper,document-styles) $Info(tex,paper,document)]
	set Values(tex,paper,document) [lindex $DocumentStyle $n]
}

} ;# namespace page


namespace eval encoding {

proc BuildFrame {w tab encList} {
	variable [namespace parent]::Info
	variable [namespace parent]::Values
	variable [namespace parent]::Defaults

	if {[winfo exists $w.$tab]} { return }
	set type $Values(Type)

	if {$type eq "pdf" && $Info(pdf-encoding)} {
		set encoding $Info(encoding)
	} else {
		set encoding $Values($type,encoding)
	}

	if {$Values(Type) ne "scidb"} { set currentEncoding $encoding } else { set currentEncoding {} }
	::encoding::build $w.$tab $currentEncoding iso8859-1 [winfo width $w] 0 $encList
	if {$type eq "pdf" && $Info(pdf-encoding)} {
		::encoding::activate $w.$tab iso8859-1
	} else {
		::encoding::select $w.$tab $encoding
	}
	bind $w.$tab <<TreeControlSelect>> [namespace code [list SetEncoding %d]]
	grid $w.$tab -row 0 -column 0 -sticky nsew
	grid columnconfigure $w 0 -weight 1
	grid rowconfigure $w 0 -weight 1
}


proc SetEncoding {encoding} {
	variable Values
	variable Info

	if {[llength $encoding]} {
		if {$Values(Type) eq "pdf" && $Info(pdf-encoding)} {
			set Info(encoding) $encoding
		} else {
			set Values($Values(Type),encoding) $encoding
		}
	}
}

} ;# namespace encoding


proc ConfigureTListbox {list height} {
	set n [$list.selection curselection]
	set linespace [$list.selection cget -linespace]
	set nrows [expr {$height/$linespace}]
	if {$nrows > [$list.selection cget -height]} {
		$list.selection configure -height $nrows
	}
	$list.selection see 0
	after idle [list $list.selection see]
}


proc HideTab {nb tab} {
	if {$tab in [$nb tabs]} {
		$nb tab $tab -state hidden
	}
}


proc ShowTab {nb tab} {
	if {$tab in [$nb tabs]} {
		$nb tab $tab -state normal
	}
}


proc Select {nb index} {
	variable PdfEncodingList
	variable Info
	variable Values

	if {[llength $index] == 0} { return }	;# ignore double click
	::widget::busyCursor $nb on
	set Values(Type) [lindex $Values(Types) $index]
	set savemode 0
	set showHyphenSelection 0

	if {$Info(extension) in {sci pgn}} {
		ShowTab $nb $nb.comment
	} else {
		HideTab $nb $nb.comment
	}

	switch $Values(Type) {
		scidb {
			ShowTab $nb $nb.tags_sci
			HideTab $nb $nb.tags_si3
			HideTab $nb $nb.options
			HideTab $nb $nb.page_pdf
			HideTab $nb $nb.page_tex
			HideTab $nb $nb.style
			HideTab $nb $nb.notation
			HideTab $nb $nb.diagram
			HideTab $nb $nb.annotation
			HideTab $nb $nb.encoding
			set var $::menu::mc::ScidbBases
			set ext .sci
		}

		scid {
			ShowTab $nb $nb.tags_si3
			HideTab $nb $nb.tags_sci
			HideTab $nb $nb.options
			HideTab $nb $nb.page_pdf
			HideTab $nb $nb.page_tex
			HideTab $nb $nb.style
			HideTab $nb $nb.notation
			HideTab $nb $nb.diagram
			HideTab $nb $nb.annotation
			if {$Values(Type) eq "scidb"} {
				ShowTab $nb $nb.encoding
			} else {
				HideTab $nb $nb.encoding
			}
			set var $::menu::mc::ScidBases
			set ext {.si4 .si3}
		}

		pgn {
			ShowTab $nb $nb.options
			HideTab $nb $nb.tags_si3
			HideTab $nb $nb.tags_sci
			HideTab $nb $nb.page_pdf
			HideTab $nb $nb.page_tex
			HideTab $nb $nb.style
			HideTab $nb $nb.notation
			HideTab $nb $nb.diagram
			HideTab $nb $nb.annotation
			if {$Values(Type) eq "scidb"} {
				ShowTab $nb $nb.encoding
			} else {
				HideTab $nb $nb.encoding
			}
			set var $::menu::mc::PGNFiles
			set ext {.pgn .pgn.gz .zip}
			set savemode 1
		}

		pdf {
			ShowTab $nb $nb.style
			ShowTab $nb $nb.page_pdf
			ShowTab $nb $nb.notation
			HideTab $nb $nb.options
			HideTab $nb $nb.tags_si3
			HideTab $nb $nb.tags_sci
			HideTab $nb $nb.page_tex
			HideTab $nb $nb.diagram
			HideTab $nb $nb.annotation
			if {$Values(Type) eq "scidb" || $Info(pdf-encoding)} {
				ShowTab $nb $nb.encoding
			} else {
				HideTab $nb $nb.encoding
			}
			set showHyphenSelection 1
			set Info(useCustom) 1
			set Info(build-style) 1
			set var $mc::PdfFiles
			set ext .pdf
		}

		html {
			ShowTab $nb $nb.style
			ShowTab $nb $nb.notation
			HideTab $nb $nb.options
			HideTab $nb $nb.tags_si3
			HideTab $nb $nb.tags_sci
			HideTab $nb $nb.page_pdf
			HideTab $nb $nb.page_tex
			HideTab $nb $nb.diagram
			HideTab $nb $nb.annotation
			HideTab $nb $nb.encoding
			set showHyphenSelection 1
			set Info(build-style) 1
			set var $mc::HtmlFiles
			if {$::tcl_platform(platform) eq "windows"} { set ext .htm } else { set ext .html }
		}

		tex {
			ShowTab $nb $nb.page_tex
			ShowTab $nb $nb.style
			ShowTab $nb $nb.notation
			ShowTab $nb $nb.diagram
			ShowTab $nb $nb.annotation
			HideTab $nb $nb.options
			HideTab $nb $nb.tags_si3
			HideTab $nb $nb.tags_sci
			HideTab $nb $nb.page_pdf
			HideTab $nb $nb.encoding
			set showHyphenSelection 1
			set Info(build-style) 1
			set Info(useCustom) 0
			set var $mc::TeXFiles
			set ext {.tex .ltx}
		}
	}

	::dialog::fsbox::useSaveMode $Info(fsbox) $savemode

	foreach what {tags_si3 tags_sci page_pdf page_tex style notation diagram comment annotation} {
		if {	[info exists Info(build-$what)]
			&& [$nb tab $nb.$what -state] eq "normal"
			&& $Info(build-$what)} {
			${what}::BuildFrame $nb.$what
			set Info(build-$what) 0
		}
	}

	foreach what {style notation diagram comment annotation} {
		if {[$nb tab $nb.$what -state] eq "normal"} {
			${what}::Setup $nb.$what
		}
	}

	if {[$nb tab $nb.encoding -state] eq "normal"} {
		if {$Values(Type) eq "pdf"} { set encTab pdf } else { set encTab pgn }
		if {$Info(build-encoding-$encTab)} {
			if {$Values(Type) eq "pdf"} { set encList $PdfEncodingList } else { set encList {} }
			bind $nb.encoding <Configure> \
				+[namespace code [list encoding::BuildFrame $nb.encoding $encTab $encList]]
			set Info(build-encoding-$encTab) 0
		} elseif {[winfo exists $nb.encoding.$encTab]} {
			if {$Values(Type) eq "pdf" && $Info(pdf-encoding)} {
				set encoding $Info(encoding)
			} else {
				set encoding $Values($Values(Type),encoding)
			}
			raise $nb.encoding.$encTab
			focus $nb.encoding.$encTab
			::encoding::select $nb.encoding.$encTab $encoding
		}
	}

	catch { comment::ShowHyphenation $nb.comment $showHyphenSelection }

	::dialog::fsbox::setFileTypes $Info(fsbox) [list [list $var $ext]] $ext
	if {$Values(Type) eq "pdf" && $Values(pdf,fonts,builtin)} { style::UseBuiltinFonts }
	::widget::busyCursor $nb off
}


proc DoExport {parent dlg file} {
	variable PdfEncodingList
	variable PdfEncodingMap
	variable NagMapping
	variable Options
	variable Flags
	variable Styles
	variable Info
	variable Values
	variable Trace_
	variable ManyGamesThreshold

	set file [string trim $file]
	if {[string length $file] == 0} { return }
	set file [file normalize $file]

	if {	([file exists $file] && ![file writable $file])
		|| ([scidb::db::get open? $file] && [::scidb::db::get readonly? $file])} {
		return [::dialog::error \
			-parent $dlg \
			-message [format $mc::DatabaseIsReadonly [::util::databaseName $file]] \
			-title $mc::Export \
		]
	}

	# Ask while the dialog still exists; cancellation must leave it usable.
	if {![info exists Info(index)] && $Values(Type) in {pdf tex}} {
		set count [::scidb::view::count games $Info(base) $Info(variant) $Info(view)]
		if {$count > $ManyGamesThreshold} {
			set reply [::dialog::question -parent $dlg \
				-message [format $mc::ManyGamesWarning [::locale::formatNumber $count]] \
				-title $mc::ManyGamesWarningTitle \
				-buttons {cancel continue} -default cancel]
			if {$reply eq "cancel"} { return }
		}
	}

	set useCopyOperation 0
	set options 0
	set flags 0
	set nags {}
	set searchPath {}
	set script {}
	set preamble {}

	if {[info exists Info(languages)]} {
		set languages {}
		foreach lang $Info(languages) { lappend languages [list $lang yes] }
	} elseif {[lindex $Values($Values(Type),comments,languages) 0] eq "all"} {
		set languages {{* yes}}
	} else {
		switch [lindex $Values($Values(Type),comments,languages) 0] {
			all		{ set languages {{* yes}} }
			none		{ set languages {} }
			default	{
				set languages {}
				foreach lang [lrange $Values(tex,comments,languages) 1 end] {
					if {[string length $lang]} { lappend languages [list $lang yes] }
				}
			}
		}
	}

	switch $Values(Type) {
		scid - scidb - pgn {
			if {[::scidb::db::get open? $file]} {
				set reply [::dialog::question \
					-parent $dlg \
					-message [format $mc::DatabaseIsOpen [::util::databaseName $file]] \
					-detail $mc::DatabaseIsOpenDetail \
					-title $mc::Export \
					-buttons {cancel continue} \
					-default continue \
				]
				if {$reply eq "cancel"} { return }
				set useCopyOperation 1
				update idletasks
			}
		}
	}

	switch $Values(Type) {
		pgn {
			if {$Values(pgn,flag,use_utf8_encoding)
					|| $Values(pgn,flag,use_chessbase_format)
					|| $Values(pgn,flag,use_scidb_import_format)} {
				set encoding "utf-8"
			} else {
				set encoding $Values($Values(Type),encoding)
			}
		}
		scidb - tex - html {
			set encoding "utf-8"
		}
		default {
			set encoding $Values($Values(Type),encoding)
		}
	}

	if {$Values(Type) eq "pdf"} {
		if {$encoding ni $PdfEncodingList} {
			$dlg.top.nb select $dlg.top.nb.encoding
			::dialog::info -parent $dlg -message [format $mc::UnsupportedEncoding $encoding]
			return
		}
		set encoding $PdfEncodingMap($encoding)
	}

	if {$Values(Type) eq "pgn" && ![info exists Info(index)]} {
		set excludeGamesWithIllegalMoves $Values(pgn,flag,exclude_games_with_illegal_moves)
	} else {
		set excludeGamesWithIllegalMoves 0
	}

	set tagList {}

	switch $Values(Type) {
		scid - scidb {
			if {$Values(Type) eq "scid"} { variable si3::Tags } else { variable sci::Tags }
			set incomplete 0
			foreach tag [array names Tags] {
				if {$Tags($tag)} {
					if {[string match White/Black* $tag]} {
						set name [string range $tag 11 end]
						lappend tagList White$name
						lappend tagList Black$name
					} else {
						lappend tagList $tag
					}
				} else {
					set incomplete 1
				}
			}
			if {!$incomplete} {
				set tagList {}
			} elseif {[llength $tagList] == 0} {
				set tagList {{}}
			}
		}

		# HTML/PDF exports share the print pipeline below. Do not hard-disable
		# them based on checkout location or developer-only gating.
		html -
		pdf {}
	
		tex {
			set searchPath [file join $::scidb::dir::share scripts]
			set script "latex-skak.eXt"

			append preamble "\
				\\def\\DocumentStyle{scr[string map {Article artcl Report reprt Book book} $Values(tex,paper,document)]}
				\\def\\Hyphenation{$Values(tex,comments,hyphenation)}
				\\def\\FontSize{[lindex $Styles(tex,BasicStyle) 1]}
				\\def\\PageStyle{[string tolower $Values(tex,paper,format)]paper}
				\\def\\ColumnStyle{[expr {$Values(tex,paper,columns) == 1 ? "onecolumn" : "twocolumn"}]}
				\\def\\Orientation{[expr {$Values(tex,paper,orientation) eq "Landscape" ? "landscape" : "portrait"}]}
				\\def\\Justification{$Values(tex,paper,justification)}
				\\def\\NotationStyle{$Values(tex,moves,notation)}
				\\def\\ShowCoordinates{$Values(tex,diagram,show-coordinates)}
				\\def\\ShowMovers{$Values(tex,diagram,show-movers)}
				\\def\\ShowArrows{$Values(tex,diagram,show-arrows)}
				\\def\\ShowMarkers{$Values(tex,diagram,show-markers)}
				\\def\\BoardSize{normal}
			"

			if {$Values(tex,diagram,use-images)} {
				append preamble \
					"\\def\\ImageStyle{$Values(tex,diagram,image-style) $Values(tex,diagram,image-size)}\n"
			}
			if {$Values(tex,moves,figurines) ne "graphic"} {
				append preamble "\\def\\UseLetters{"
				if {$Values(tex,moves,figurines) eq "user"} {
					set set [namespace current]::Figurines
				} else {
					set set $::figurines::langSet($Values(tex,moves,figurines))
				}
				foreach piece $set {
					# convert into UTF-8 sequence; e.g. "\u05d4\u05de" --> \xD7\x94\xd7\x9e
					append preamble "\\utf8{[::scidb::misc::utf8sequence $piece]}"
				}
				append preamble "}\n"
			}

			set flags 0

			switch $Values(tex,diagram,perspective) {
				white	{ set options [expr {$options | [Pow2 $Options(diagram_from_whites_perspective)]}] }
				black	{ set options [expr {$options | [Pow2 $Options(diagram_from_blacks_perspective)]}] }
			}
			if {$Values(tex,diagram,hide)} {
				set options [expr {$options | [Pow2 $Options(diagram_hide)]}]
			}
			if {$Values(tex,diagram,show-movers)} {
				set options [expr {$options | [Pow2 $Options(diagram_show_mover)]}]
			}
			if {$Values(tex,diagram,show-coordinates)} {
				set options [expr {$options | [Pow2 $Options(diagram_show_coordinates)]}]
			}
			if {$Styles(tex,BasicStyle,GameText,Moves,MainLine,ColumnStyle)} {
				set flags [expr {$flags | [Pow2 $Flags(pgn,column_style)]}]
			}
			if {[llength $Values(tex,nag,lang)]} {
				set options [expr {$options | [Pow2 $Options(annotation_map_unusual)]}]
			}
			if {$Values(tex,nag,all)} {
				set options [expr {$options | [Pow2 $Options(annotation_map_all)]}]
			}
			set options [expr {$options | [Pow2 $Options(moves_notation_[string map {san short lan long} $Values(tex,moves,notation)])]}]

			foreach pair $Values(tex,nag,mapping) {
				lassign $pair from to
				lappend map($to) $from
			}
			set nags {}
			foreach group $NagMapping(skak) {
				set nag [lindex $group 0]
				if {[info exists map($nag)]} {
					lappend nags [list $nag $map($nag)]
				} else {
					lappend nags [list $nag $nag]
				}
			}
		}
	}

	destroy $dlg
	set Trace_ {}
	set close 1

	if {[info exists Info(index)]} {
		switch $Values(Type) {
			pgn {
				switch [::dialog::fsbox::saveMode $Info(fsbox)] {
					append		{ set mode append }
					overwrite	{ set mode create }
				}
				::scidb::game::export $file \
					-flags $Info($Values(Type),flags) \
					-mode $mode \
					-encoding $encoding \
					-languages $languages \
					;
			}

			html {
				# native HTML publish path for a single game (see the
				# database branch for the design notes)
				::scidb::game::printHtml $Info(base) $Info(variant) $Info(index) $file $flags
				return 1
			}

			pdf {
				# native PDF publish path for a single game (PdfWriter):
				# embedded figurine font, image diagrams from the pdf/sets.
				# Content flags: variations, comments, annotations, move
				# info, marks, termination tag (engine-level convention).
				::scidb::game::printPdf $Info(base) $Info(variant) $Info(index) $file 63
				return 1
			}

			tex {
				# Export by database index, preserving the game headers.
				::scidb::game::print $Info(base) $Info(variant) $Info(index) $file \
					$searchPath $script $preamble \
					-flags $flags \
					-options $options \
					-nags $nags \
					-languages $languages \
					-trace [namespace current]::Trace_ \
					;
				return 1
			}
		}
	} else {
		switch $Values(Type) {
			scid - scidb - pgn {
				switch [::dialog::fsbox::saveMode $Info(fsbox)] {
					append		{ set append 1 }
					overwrite	{ set append 0 }
				}

				if {$useCopyOperation} {
					set close 0
					::scidb::db::clear $file
					::scidb::db::set variant $file $Info(variant)
					set cmd [list ::scidb::view::copy \
						$Info(base) \
						$Info(view) \
						$file \
						$Info(variant) \
						$tagList \
					]
				} else {
					set cmd [list ::scidb::view::export \
						$Info(base) \
						$Info(variant) \
						$Info(view) \
						$file \
						$Info($Values(Type),flags) \
						$append \
						$encoding \
						$excludeGamesWithIllegalMoves \
						$tagList \
						$languages \
					]
				}
			}

			html {
				# native HTML publish path (no TeXt machinery): standalone
				# UTF-8 file with embedded CSS + SVG diagrams. The progress
				# and log arguments are appended by ::progress::start and
				# the lappend below (same convention as view::print).
				set cmd [list ::scidb::view::printHtml \
					$Info(base) \
					$Info(variant) \
					$Info(view) \
					$file \
					$flags \
					$languages \
				]
			}

			pdf {
				# native PDF publish path (PdfWriter; embedded figurine font,
				# image diagrams from the pdf/sets). The progress and log
				# arguments are appended by ::progress::start (same
				# convention as the html branch above); content flags as in
				# the single-game pdf branch.
				set cmd [list ::scidb::view::printPdf \
					$Info(base) \
					$Info(variant) \
					$Info(view) \
					$file \
					63 \
				]
			}

			tex {
				set cmd [list ::scidb::view::print \
					$Info(base) \
					$Info(variant) \
					$Info(view) \
					$file \
					$searchPath \
					$script \
					$preamble \
					$flags \
					$options \
					$nags \
					$languages \
					[namespace current]::Trace_ \
				]
			}
		}

		set options {}
		if {[llength [::scidb::db::get variants $Info(base)]] > 1} {
			lappend options -message [format $mc::ExportDatabaseVariant $Info(variant)]
		} else {
			lappend options -message $mc::ExportDatabase
		}
		lappend options -interrupt yes
		lappend args [namespace current]::Log {}

		# XXX text widget may overflow (too many messages)
		set parent [winfo toplevel $parent]
		set formatName $mc::FormatName($Values(Type))
		if {$formatName eq "scid"} {
			append formatName " " [string index $file end]
		}
		::log::open "$formatName $mc::Export"
		::log::delay

		if {$useCopyOperation} {
			set dst [::util::databaseName $file]
			set msg [string map [list %src $Info(name) %dst $dst] $mc::ExportGamesFromTo]
		} else {
			set msg [format $mc::ExportingDatabase $Info(name) $file]
		}
		::log::info $msg

		set cmd [list ::progress::start $parent $cmd $args $options $close]
		set count {}
		if {[catch { ::util::catchException $cmd count } rc opts]} {
			::log::error $::import::mc::AbortedDueToInternalError
			::progress::close
			::log::close
			return {*}$opts -rethrow 1 0
		}

		if {[llength $count] == 2} {
			lassign $count count illegal
		} else {
			set illegal 0
		}

		if {$rc == 1} {
			::log::error $::import::mc::AbortedDueToIoError
			::progress::close
			::log::close
			# show error dialog
			return 0
		}

		if {$count < 0} {
			::log::warning $::import::mc::UserHasInterrupted
			set count [expr {-$count - 2}]
			set rc -1
		}

		update idletasks	;# be sure the following will be appended

		if {$illegal} {
			::log::warning [format $mc::IllegalRejected $illegal]
		}
		if {$count == 0} {
			::log::info $mc::NoGamesExported
		} else {
			::log::info	[format $mc::ExportedGames [::locale::formatNumber $count]]
		}

		if {$useCopyOperation} {
			set cmd [list ::scidb::db::save $file]
			set rc [::util::catchException { ::progress::start $parent $cmd {} {} 1 } count]
			if {$rc == 1} { ::log::error $::import::mc::AbortedDueToIoError }
		}

		::progress::close
		::log::close
	}

	if {[string length $Trace_]} { ShowTrace $parent $Trace_ }
	unset Trace_
}


proc ShowTrace {parent trace} {
	set dlg [winfo toplevel $parent].trace
	set txt $dlg.f.text

	if {[winfo exists $dlg]} {
		$txt configure -state normal
		$txt delete 1.0 end
	} else {
		tk::toplevel $dlg -class Scidb
		set f [::ttk::frame $dlg.f]

		tk::text $f.text \
			-width 100 \
			-height 40 \
			-yscrollcommand [list $f.vsb set] \
			-wrap word \
			-setgrid 1 \
			;
		ttk::scrollbar $f.vsb -orient vertical -command [list ::widget::textLineScroll $f.text]
		pack $f -expand yes -fill both
		grid $f.text -row 1 -column 1 -sticky nsew
		grid $f.vsb  -row 1 -column 2 -sticky ns
		grid rowconfigure $f 1 -weight 1
		grid columnconfigure $f 1 -weight 1
		::widget::dialogButtons $dlg close
		$dlg.close configure -command [list destroy $dlg]
		::util::place $dlg -parent $parent -position center
		wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]
		wm deiconify $dlg
	}

	$txt insert end $trace
	$txt configure -state disabled
}


proc Log {unused arguments} {
	lassign $arguments type code gameNo
	set line ""

	append line $::import::mc::GameNumber " " [::locale::formatNumber $gameNo]
	append line ": "

	set arr ::import::mc::[string toupper $type 0]
	if {[info exists ${arr}($code)]} {
		append line [set ${arr}($code)]
	} else {
		append line $code
	}

	if {$type eq "state"} { set type error }
	::log::$type $line
	update idletasks
}


# proc CloseView {} {
# 	variable Info
# 	::scidb::view::close $Info(base) $Info(view)
# }


proc WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Values
	::options::writeItem $chan [namespace current]::Styles
	::options::writeItem $chan [namespace current]::Figurines
	::options::writeItem $chan [namespace current]::si3::Tags no
	::options::writeItem $chan [namespace current]::sci::Tags no
}
::options::hookWriter [namespace current]::WriteOptions

namespace eval icon {
namespace eval 13x13 {

set checked [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA0AAAANCAYAAABy6+R8AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABNUlEQVR4nI3Q
	MUvDQBQH8PcSRaoOgoIFpatKHPwEfgvpWBxqreJQWtDBEl3VsZJAUYvWjM62FWqxk0NwUESoDkVS
	FFGrNWKH/l2aEiXGvOW44/3+d/eYPBQAXiNiIqJ15pYn4CXYDoT22vf6ZQabwLR1Zk9jZv4NektG
	JRnYXzGDufQ5gIDQ7kR/d0+7BwRAYOYWAF+5dhufOVaXq+aLb2pw9JKI3q3UyfRVefvm+SEEoMu6
	4cyoJP27iYaoRLCp57MARjpvv3iqLvkyMYxr8mPtsz4LYKB4f706vBf/EJUItvT8gQU6XwEgLZa0
	AqlhjGWT1aM7PTW0E3sT1Hls6LmsDfwcAgApWjw8IWUOlApDVKPOwGG00sKpVvBnEk1X4AAnjEY9
	9C+wQXbb/1kyZEEGBDfwDalh3HI5T3IGAAAAAElFTkSuQmCC
}]

set unchecked [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA0AAAANCAYAAABy6+R8AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABTUlEQVR4nI1S
	vU4CYRCc/XLHEXgFGxMTwGCBUSsaEaNUvoOJsaOwsNVWCxPpjD/PYCUmAiaG6iRH4eFPQULDI0A4
	Lt5Y8F1CyF3iNlPMzs5udoSkArD73Gpve95UAEAphbCCIAAAWFaC+6XiK4AXIbl3fHJ+bTu9jIgg
	rkhiaz3/c3N1VjXqjXbJdnqZleWl783C2udoNLaUUpxzknQ65b13P1Ztx83WG287huf7IiLcKOS/
	TquHRwA8AAKAc2hd1O7v+oNhxvd/xdDby3g0SQCYiMg4YjVqXgDACAmlhAAUSYlwUpqf9S4OFRFG
	4XyTsSCS0Ikk5jFSFAQUAMHCZOqbAs3PRIEmU+nkFEAy5iZL8wQAwzJNkpRO181d1h5u4/7U6bo5
	kmKaJo1Kudh8fGoe2I6b7Q+GWcRUmIhKudgUnb3yc6td+kf2WgAafytCt6v40XrqAAAAAElFTkSu
	QmCC
}]

} ;# namespace 13x13

namespace eval 32x32 {

set IconPDF [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAHOklEQVR4nKVX
	fXBU1RX/nfu+9oNNyDYxkgRpCGJjAKWCpFNRK7U0YwxYygDj2GnBOsMYpB+WKkKXiKE6Y9EWHAc/
	grbGUmQUBupXwQxxaBumjBDCRCmhtElsELLZzSbZ9/a9d0//yG4Sls1H2zNzZ96793z87rnnnnMu
	MAoxMzGzAEATHAiFQoKZaTSdmSgjMzMTEXHqX9c1gDkTa4ofCdsZkkmX/68BJJUoAMobPm76+uXu
	nhwGsaB0HiJAuj6fL6goonje3Bv/lhsMPk1EA8yMiYBQ04wSEcAM/cxn5x9++rmXftR2oX2q47hj
	KlEUFQPxOObOKf329qc2SGauISKeiCfEyJ8tW7YQQGxZVuUTW5//xYlTrVMHBkyMpYEZsCwTuqa6
	x08085p1m6rD4ciapHGMFxM0rGgQLTMbz+9647Xd9ftXapri3lH+1cZv3F5+rK9/QFEUhYcFmWzb
	ltcVFfr3Hnj/ux81NhX5fB45ELdEyZeLLtft3LoxOHnyq0mdox6HmmEu0NHRNdV2HC68Nrf/V7U/
	3+4x9EMAgVkOIyeCZEYiYecc+tPR+SAqAoh1TcX5C525q6s3b6vbuRXMXEdEcrTjEOkTACDEoEdU
	TZGmaVpWwqaqJUuUhO1QalgJW9i2QwAUO2GT7bgoKsjvu2fxHedsx0bbhY7c1dWbt4XD0TWGoXMq
	JiYEYPhYhnh47969DGBoMHPqG0IQK0IgbprxJx+rfvn7q5Ye83k9su1CR+4P1m2q7eq69GNm1jOB
	GBMAAKiqOt5VYikHQcT6BnzrH99WAebsQMBvG7om2y605z684alnO/998Vlm1gc3NgxiXAAToOj8
	W2afNHSdItFY1uGjx+98tX7/rC8uhQ3bdoTPa8i/njgt3tz37koAxck4GAKQKQgnRETEoVBIEJHD
	zC+Ew+EpHzb85XbHcVUSRNKVUITQLod7PB5d54G4GQNgpuv5nwEAQE1NTSq6W5n5h2tXr5plmqZX
	VVUAsF3XXbBizc82hiOxSf39/V0A+pKiQ8f6fwEABj2RBBEG0DhyzbZt6UrXAVHK6FW3YDQAnFI+
	gSDEiOhOGRAApOM4xoi7n1FPpiAk23ZUZmbHcRTTcZTxAKRAEJEkIglAEpF0AHIcR2Fmtl1HRQYP
	ZAJgXl8y7aJhGDQlPy/qUdVwUnCId8RuCQCFQpzeBxAA8qhqeEp+XtQwdCq+rqgLgDXmLlJKmPmm
	Px8/GWLmZcmm5CpSFAFD16Aq4ip5AFAVAWYWzLys6cTpLcw8N5OeK1wyoiDdfKzpk6qOz7tISujF
	0wq6y+fddFgI0czMYOZb3zvycWWkJ6ZNCnjNRQsXNPt8vgYiihARpJTzPjhyrOpyJKLoqpoI+P0U
	7e2ju+68tSUvGDxARImULTWD8cCOl+trXt9zsEoRg7sTisDXbpl1JpGQP1FVNP5mV/0Tb7x1qAoE
	CCK8WPeH2P3L73mHmTcC6N7xypubf7fnYBURACKwlHBcifc/auzcvXPbvwA0JTef0b2ec23t+ZZl
	seu6bsJOIB6P48OjTWWbap/bAOD61rPnvmRaFjNLxzQttHdeDOx4ac/33tr/wXoAOZ+dPX9N3LTY
	daVrJ+wxjz3TNWTDUG1mUHbWpEjtpvW7t7+wu7L17/+ceerMp7MBzNR1LQ4Iyg4Ewsvuvbthz9vv
	VoQjscDbhw4vWb508R9B1EdEFMzJimz86UOvx/vN3khvn/KtRbc1A/gkZQcYvRYMJmwaZEq7wCSZ
	iVlCVQXWrl5xcHbpjJMMUDgSCQIo9OiG4bgudF3zaqqaFwxm26uWVbyTm5O1j4gSAIYalIyJSEom
	RRCivX3BtY9ufZRZgsGYO7u0GcCnANRkTRYAoGpagoggXXYA5AQCvgIC8MWlbu8jj/3yAYCw8r6K
	cmZ+gIiiI5uTcVOxogjomoHyeXNanny8+hkA7R7D0FhOqOuGIAKDoIihdHwFZQQgBLErGVmBQE/1
	gyvqC/Lz/7Fg/pwGIjrFzLk0nKolADi2rTMzhCIUAD2x2MDnDJTk5QbNRx66/4Bkbq1YtPA9IupN
	b81GrQVSSkzye+i+yrv3E1FDcj6VN5gIcB2JF+t+f+/p1nM3E8DBydk9ADrNhGURETRVNRffddsr
	qiKOuEmPpfeFo9YCKSXbtqP29vZ6AFBLS4uedCFZlqMB4EgsFtz12r4V4Uhvlt/npe9UfvMAgLMC
	5HddlxMJW4n292uuZEo+dK72doY5s6R4WpfX66XCgmsiWVlZ3QC4rKws9Toxp08v6vJ6PUQkVI/H
	wNTCa2PrHlz52+VLF/8aQE/pDdMvej0eKizIj2T7/WEM95JX0dARjKjrMWbeNrNk2pmyG6afBnAy
	ySJHrn+lpLg5HI1qk/x+c9HC+empuHZG8bSWG0tnjJSfWNSmSFHGbhdTxUgZpRiNJz8mhUIhAYBC
	oVD6e/SK9dRIVj3KJD+erf8Ae/fAJzdqg7IAAAAASUVORK5CYII=
}]

set IconHtml [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAH90lEQVR4nKVX
	bXBVxRl+3j17zv0ISTCNmOQml9wkRkG+5KPAOKPoaK3TjkjHoky/CR2nI2r7Q2stGFPlo1NUOpW2
	iohUtC2UDnEs1mAJ4CAFgSoqjDaQQAIJijeE5N6ce3fPvv1xPxLCDaTtzuzM7p73fd5nd5/dfQ8w
	TGFmYmYBgEZYUV9fL5iZhsPMVXIaMzMREWf6jmMDzLlMM/ZIKp31Ger/XxNIg1gAZjW/s++Gs190
	X8EgFjTUhggwXjAYLLIsEZl+/fgDxUVFK4kozswYCQk5JCgRAcxwPv7k+P0rn33hx8fa2iu09i4J
	YlkS8f5+XD9p3FefeeoRw8wNRMQjWQkxuPPEE08QQJxIJL7+8ydXP37wg6MV8biLSyEwA4mEC8eW
	3v6Dh7nugSWLo9FzdenguJwmaAAoxZaZfauf3/jy+le33mvblnfTrKm7b75x1p6+WNyyLIsHHJmU
	UiZcHsrb1Pj3u3fs3lceDPpNvD8hqivLz7703JOPFY0evS6NOex2yBxj+R0dXRVKaw6VFMeeXvbT
	Z/w+5w2AwGwGmBPBMCOZVFe8sX3XDBCVA8SOLXG87VTxwsVLl7/03JNg5peIyAy3HWLoAAAIkVoR
	aVvGdd1EIqnozrlzraTSlKmJpBJKaQJgqaQipT2Ul13V97Xbb2pRWuFYW0fxwsVLl0ejPXU+n8MZ
	TYyIwMC2ZG1406ZNDCBbmTnThhDElhDod93+Xzy6eO33F9y1Jxjwm2NtHcU/eGDJsq6uz3/CzE4u
	EpckAABSyssdJTYmRaK3Lx586GfL7wBzYX5+nvI5tjnW1l58/yNPrTrVeWYVMzupiQ2QuCyBEZSe
	GdMmvu9zHDrX01vw9q79c9a9unXCZ59HfUppEQz4zD8Pfihe+8u2ewFE0jrIEsglwhEVIuL6+npB
	RJqZ10Sj0dKm5r03au1JEkTGM7CEsM9Gu/1+x+F4v9sLwB2K8z8TAICGhoaMuo8y8w9/tHDBBNd1
	A1JKAFCe5828p+7hx6LnekfFYrEuAH1p1+y2/l8EgNRKpElEAewe/E0pZTzjaRBlgl50CoYjwBnw
	EYgQg9SdCSAAGK21b9DZz4mTS4SklJbMzFpry3Vd63IEMiSIyBCRAWCIyGitSSttGcOslJbIsQIC
	yF7DlJ6FW1019ozP56Oy0jHn/X5/NwCaP3/+YGcCQOmcIdse+t3v93eHyq7qCQYDFKms6AKQGHYG
	ljWwGMw8+d39h+q7us7OywA7tkTA70PA74Njy5y+gwhBWgK2LXHiRMf8bU27H2fmKbniyrTjtO3N
	e++6pjbyUThUsgWAsSyLNBsFIHTg0MffaGs/VZlfkBcGgN7zsZORsRWtUydfu7Wto3NGS0vb1Fvn
	zP4rER1K4019q3nvvAm1kcNjx4Y2ae1NfvMf78zt6PysNlRy5VYiSmbeBsnM+b9d99qjL258/e7J
	46tb169Z9tmzv9tw3yub37xn+qRrPl368P3NDz62vE5rIzmtIwJBSqH/9OKq65Y//fyc/f86cs13
	vvnJTGb+FgA8veblX27cvO3WKROubtPai/7qN+sX/Xlr073XT6w9uXZ1QyuA99LbxBJA8NOWk6X9
	bj+fPHW6EED5v4+fuMp1XW4/faawLxbLFwRWKgmREhgMs3BsP/fF4vkn2k8XeVrx5samW267adYi
	D8DmxqZbPE/zifbOQgBlbe0dJbF4nE+dPjPadd0vDd0Ctm1LCSHIdhwPQHJUMKiEECQIYlxt5G9/
	WLNyV9POPXVrX9nyZQC477vz939lzux1kUh5jAh32FKS6yaoYdXvFwGA6yaEtCxIaRkA2pa2FkKQ
	tKUnpTSDCQgAZNsywMYAhoPvf3h0gZtQNVop+Py+UdFozxdVVRUvRMLlO4QQEEIgEi7ZUVVV8cLZ
	s31dtpS2ZwwcW5rWto5Ia1tHxLGlYWYwpzPmtDBzPccSwOi8YF4pgxE91xOse6h+riCCLS22hBWw
	bBEBQN3ne7POX6TaZNtkc1oYxhhBqRsPxpgRP3KXNExHZAAs5YCpFCI7TgQ2nkFNdeWRgoK8eEFB
	XrymuvKIZxhCXHz7JRKJC/4lBIBzsXisk0AoGl0YX/frhsbZM6a0Ku2R9ry4FE57ela5SZJgjxmV
	FWWdG9asWLJhzYollRVlnV7Kni+0Jc7Ly0taQjAReRkCrJTuJyEAQfEpE8f90e+zWywp4XleQmut
	M4EGBx2Ey8wMrb1guLx0bbi8dK3WXjCVTlEqa6J0xhRzzZbXt9+1bfuuBmaeDqQ0QEp5tjGGVTJp
	AXD64nHbGGalPel5ngUASiVlZhWUSkoA8DxPaO1Zxhj2PGMBsFPjxjLGsNbaAiATCWUD4O7e3sIV
	q9c+CBI4fPTYJGb+ngAQr60Jdwb8AQqHynoAdFxdWdEVCPgpVDqmu6ioIAoA42urOwvzR6EwfxTG
	11Z3AkBRUUE0VDamOxgIUE1V+DRSd32ipip8OhAIUDhU2gOgo6qqvDMQ8JMgIYW48G3LHI9pTTvf
	nXfdtVUfhkpKtgCY/PbOvfPGXVtzOFRyZSMRJZi5ZN97H3wbAGbOmLyRiLqY2Xeq6/O5R462TLzt
	5tmNRHQgjTd9e/PeuePHRT5K4015q3nPnT095yUAFBYW6NtvvqGRiA5mmQx+jHL1L1Vy2ebCc2wb
	jm1fbF9fXy8AUCrHy14Y6X7qMA5KOLIvHhFd4Hs5vME1Y/8f2bggvHLHONYAAAAASUVORK5CYII=
}]

set IconPGN $::icon::32x32::filetypePGN

#set IconPS [image create photo -data {
#iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
#ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
#ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
#MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
#Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
#IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
#YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
#cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
#aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
#b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
#b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
#d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
#b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
#IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
#c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
#REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
#TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
#SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
#SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
#RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
#V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
#SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
#RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAG2ElEQVR4nJ2X
#e3DU1RXHv+f+HrvZvDYhCjEPi6m0aqWTKpoZMIUqraBWmSGAU2wFLEUeFcYWhEizmUAqU2vDjGWs
#5aFDaQuT0iD4GrDRhEwJSCtQHokkEEgkkLgJZh+//b1O/9jdJITNZuOZuTO/32/uPfdzzzn3d84B
#hhFmJmYWACjBgbKyMsHMNJzOWBJzMjMTEXH0XVUVgDnW1Oh86IbZv2bo+lEDRJRIAIpq6xsnd3/Z
#k8EgFjR0DhFgWy6XK1OSxPj7C+/+NCsz8xUiCjAzEoGQh2xKRAAz1NNNrcte+cObK1suXs4zTSuu
#EkmSEQgGUTjxrkdf27DaZuZyIuJELCEGv3g8HgKIQ6HQ46UVVb85fuJsXiCgIZ4GZiAU0qAqsnX0
#+EletOLl5V5v76LI5hgpJmhAUZiWmR1Vf/rLWzt21cxTFMn6ftH36qYVFzX4/AFJkiQeWMhkGIad
#n5uTvGffB7P/VdeY63I57UAwJAq+kdu9/fWKdZlu97aIzmHdIcf4ltre3plnmCbnjMvy/37jmtec
#DvUAQGC2B8iJYDND142MAwc/mQSiXIBYVWS0XuzIWrh8feX21yvAzNviuUMM/QAAQoQtIiuSrWla
#KKQb9OMnn5R0w6ToCOmGMAyTAEiGbpBhWsi9baxv5vTiFsM00HKxPWvh8vWV3t7eRQ6HylGIhAAG
#3NI/h/fs2cMA+gczR58hBLEkBIKaFqxYt+LNZ59+qsGV5LRbLrZnLVi+vrKjs2sVM6uxIOICAIAs
#yyNdJbbtMESfL+B6YW3lDDCnp6YmGw5VsVsuXM765eqNr3ZcufoqM6vhgw1AjAiQgFyfdN+9nzkd
#Drr+lS/tUN2xqdt21XznWpfXYRimcCU57CPHT4q/Vr83D8D4SBz0A8QKwoSEiLisrEwQkcnMWzo7
#r936QW3DQwSoqqzIpm2xRELp9vY4narKgaDWB0AbqudrAwCAx+NBeXk5iOgMM//qhSXP3A9A1zTN
#D0BIkvRAyYIX13l7+1L8fn8nAF9kab9bR+0ConDSCT+TzcxJHR2dz5Vt+uPmFS9tXPLGjt0znU6n
#lpSU9JFl0b8t2zJBFN30plswKgtE/mwoLy+3I7lizOctbc+veOm3q7/o7HIBwOEjJ6afPnf+R8z8
#E5+mkSCKe8jRABAzg5llAD/YuvMfs651eb976lxz4eWOK8601GTDoarBPp8/5XDjiTve2LH7p0sW
#zH3XMEyLhs95o7MAM8utbR2/KK3YXNrc2pbt9wegKBILEjyl6L6rvyt/8a0pM+cv7fNp7jPNLXcC
#SLdsy6I42SChGIj8Ri0AxS9vqFp/4nRTdiikccH4PP2WMZkEAs40nXcv+/WGxwzDdAEQWe6MHgBB
#ARF3j0QAokkqf+/+g2tPN7WOdTkdPPepR//z7t+3LFj87Ox3VFWlC21fpNQ2HCvs8wWdebfdqi2a
#P2svgF5FlSU7TjET1wUCJHyapjNz9tad1Vt2Vb/3iCwJ0wZLmq67AbTPmzVzmWla3gMf1k0PBDRn
#9rhbri577um3c3LG7fX5fMWIZ/94AASCxTa7U1Lk9w/WL9y685+PBQIBCEmSBRH27v+oQJGVDZ41
#S2fNL3li6fySJyYCSANwCcB5IrIMw5AiOSPOIYcDIMAwTBNA5qG6I5MDQY3d6amBqo1rPpx4z52X
#iIg/O3X2HgATiShIRI1EdJCImsjjCZdWiFvLxAeIJTaDA8FgmxbSAyT6cztHKmiZmQUzC/Z4MMLB
#RwZgBhRZlgF4H5la1JDiSqKv+nzJays2Lz73+YVvAyQK7737FIBzkQRjE5FNRP1Vi2maI5bowwOA
#IckSurt7jRkPP7T9mbmP12S603WHoiDJ6cDDxQ/8r2zN85uIqBOAGJTlaM6cOdFewRYiflEaMwiZ
#wUTEum6IrCx3qiyJK6ZlL178s5If1tYfm5Cfl/3lhILbDzkc6hlVVQDAHtw3vLOvxnKoCpxOp0PX
#TTl8jWPHQyyAvpycce2KLFNXd49rVemmVTXvf/zg23/bZ7tcTtOdlkZNza0ZjZ+eLNm5e78DwE0F
#p2VZlJLsslaVbprS1e1NVmWZcnOzLwPoGxZgUH4P+TWt+uPDR2c0n29Lr60/Ou1w43+nCRIAGJZt
#QxCBSNxQpN5kRQCGbkA3TEz45u3XlyycXU1Eocge/QtvCJLBjcnZptallVV/Xtly4VL+jY0JIYHb
#FT6dLKFgfP6ldSt/XnXXt+7YQoDOQyw2Umv24Cf1jVM6u3oyJCmxXi8qlsU0duwY79TJkxoANEZy
#yU0SEyCa96OiKl+vcNINc1idcQGA/so14S53BD08nJ7/A4LnbbWZNS87AAAAAElFTkSuQmCC
#}]

set IconTeX [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAGRUlEQVR4nKVX
	fYxU1RX/nfvu+2CYlQU2gu5CizRsBaRRVGhE6jQxqY2pNjHRJo2lEJO6RbpgYlvoujTUKRqK/EFo
	ikFLA8Qum9Q2lNQauysfqYsSA6axfiyussDC7sx+zed7993jH+/N7DLOzsy2J3nJu++d87u/e++5
	v3suMIUxMzGzAEA1PmhvbxfMTFNhlrOyzsxMRMSFtmWZAHM514I/XE8VY0rjp00gBDEArO462XPP
	UGJ4NoNYUKkPEaD9SCQyxzDEojtvX/puw5w5O4kow8yohYQs6ZSIAGZY//nwwk93vri/tbfv4gKl
	/IoghiGRyWZx+4pbv7P7N89oZv41EXEtMyEmN7Zv304AcT6ff3Dbjj3Pnj33wYJMJodKCMxAPp+D
	ZUr/zNnzvOGpX21MJkc2hJ2jWk7QBFDAlpntPX849MdXDr/2mGka/rdW33Eitnb16VQ6YxiGwROB
	TJ7n6YVNjTM7/vqPR/51oqcpEnF0JpsXi7/aNPTy3h1b59TXHwgxp1wOWeZbXX//wAJPKW6c35D+
	3XM/3+3Y1jGAwKwnmBNBM8N1vdnH3njrLhA1AcSWKXGh71LD+o1t8Zf37gAzH6i0HKL0AwAIEcyI
	NA2dy+Xyedej7z30kOF6igpP3vWE5ykCYHiuR57y0XTzvNR371/b6ykPvX39Des3tsWTIyMbbNvi
	AomaCEwsS9GHOzo6GEDxYebCO4QgNoRANpfL7tj61P51P3j4dGSGo3v7+ht+vLEtfmlgcDMzW+VI
	VCQAAFLKaluJtQ5IjKcykZ/9Mv4AmGfV1c30bMvUvZ9ebNj0zHO7Ll25uouZrWBgEySqEriup0Ad
	KQQoKOX46jtvO+c4Do2OpW5488Q79x04/Nrya4NJ2/OUiMyw9dtnz4sjnccfA7AozIMigXJJOJUR
	EelJ7cLMuMz8Yv/lqw3/7P73vay1ZVmW9H0fhhDmUHLYcSyLM9ncOIBcKWjNBIjIZ+YogAgAHY6i
	PvydaH3y8bbWJx+/DQByOTUqJbTv86pHNzy9NTkyHk2n0wMAUiXkqxNQSgkAYOZVe186/Ivevv55
	hjSUJeWMaCRyEwCkspmBdDo77nqKl9yy8Ormlh/tJKJzHjNr1h6ICp1+aRdUJEAg+L7PAPD6m6cf
	/FPH3x/OZrPQDPi+HyRQIN2NUkqQILz3/n+x7OuLLzDz+2NjaQdcOc+qzQApFbwkkglHa19LQ3DD
	3Nnjjm3ZA9cSDgDMv3FuLpd380OJ4TqlFA0lkhYR6ZGRlK4EDlTdBcy2bQAAli9tvjyrLirqolHj
	4L74C1ta1h1lgBigLS3rjh7cF3+hLho1ZtVFxfKlzZcBIIitcI5XmwEGIGXgsmJZ86vxbZsMTyvc
	PP/GV7pPvdtiiIDclatDn8TuvXt//NlNnikkVixrfhVhbDURqWUXMAAQ0RUAu4Agk/78l9cjhbPB
	lDIiiBIc/i+NrWQ1C1FYoBAAoZkJhEknE7QOxEkgECijVtzpCFFR+wFA64nBTXrnUr9qNi0pLhgR
	cTQaKZZJ0WjEr7UG/L8IhGcAM/PK4ZHRmPJ9KN/H8MhojJlXhv+mVRXXooQEAN3d3SIWiylmvmH3
	7w+2H+o4tkYQ+QCwe9/BNdeuJdqZ+YdENNbV1WUA0IXY/5mAEMQIdX97dzcQSqmvfBiGBBAkm8EE
	pYsrMtlXhxjTI8AMJiJ2XSUdx7Fty+S3fxtXtmXCMuWY66m2b6/95vlcNrsEAJwZ9kcrv7HsqGWa
	Y7ZlouDrOI7tukoGhUj5xCxHYLyxcX6/KSUNDg1HNm97fkvn395YVShKmZmOdB536+ujyrGcjwFg
	NJVSRzqPf//Q0WOPEhH7vk/RmRF/87bn1wwOJWdaUlJT000XAYxPSYCIuL29XRBRPp3LdXafOvPA
	R598Nqvr5JnYqZ73YpMXk0hAaw0dCpEgASHEdUUrA/BcD66nsORrXxn9yfpHOokoH/ZRdLwuSSZf
	TD748EJLfM9Lrb2ffr6w/MWkNL++PMNSGli8aOHnW1uf2HNr8y37CHA5HOxUKJPJGABWvXWyZ83A
	4PBsw5jePvd9pnnz5ibvu+eu0wB6KNwx1YYRfAxuNMW2ZU5HMCfM9dSUmBUJAEXRqfmWWwWHp8L5
	Ao0TO6y6nn+zAAAAAElFTkSuQmCC
}]

} ;# namespace 32x32

namespace eval 37x21 {

#set IconTeX [image create photo -data {
#iVBORw0KGgoAAAANSUhEUgAAACUAAAAVCAYAAADB5CeuAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
#ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
#ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
#MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
#Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
#IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
#YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
#cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
#aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
#b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
#b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
#d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
#b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
#IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
#c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
#REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
#TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
#SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
#SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
#RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
#V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
#SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
#RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAEJElEQVR4nK1W
#fWjVVRh+3vP7uL97m7ubs7EPnTYmmFPa0DRTw5TsQwbq2IhWGFlC0gcWQdkftxuJFARJGAYXbWOS
#sHLlxGayNlcuBTV1Na19u7QVmPu8H7+P8/bHvRcnWN7fzefPl3Pe9znPec55X0IaUFUFuqbdFGNm
#hCNRAkBEJJmZiIjTyU+pLmTm5NoHjraceOTayOg0hYhlIi6I2DD02bkzcjKWLSn7gIiOM7NCRI5b
#UmoqiwKBgEicfu1Lb7y3u+N0Z4nt3KhFIEgpQQLweb3YsmljATNXE1E3MwsikneUVOIaJDN7Ptn7
#+abWjjMlxbML+ssWzuuxTFslAdi2I7Oz/N6fznUtvNjdd9euPfVl4xPhD5n5NSLqcatYSkol4Bsc
#Gs4XQvDmmsrG9etWvwtAIG4BCaDo1bd2HugZGLrXY+h2qO7LCkiAmbcRUa8bj7khBSFIEhFNRiJQ
#hBiVfKMGM2eOjU+yogh+feuz50N1DfNC9V9U+LxGNjNvJ6LvUyUm3JACxx+GEAKOlAKBgKiqqlIQ
#V8ueluEzxybCtG//wbnRmGkwA3tqG1Y0Hm7Zzcx5RMRTHsy/wpVSSRARaZoqFck4Ynjg8xoAcO3N
#bS98Fo7GXu4bGJru0bWJObPyje6+y1rXbz2ZG7DGm9wO4D/Vck2KiGBalmVZdsF37Sc3X746nD3d
#7885cqy9QNXUP5/a+MSFTH8GFt9X+lXTN63rtu/4uDoaNQcBjCRS3Pb60lJKIWEDWLnzo9A7w3/9
#LUAEQ9cQicZgWhYK8+6OtB7aVzs2MXlJqCosy7bc5HfnqZuhToajoqgwd2zV8kW/hyMRuXrl/Vfm
#FheNm5bjBZBJRBqYQUQpf9JAmkqxlAqAjuefqfz0oWWLhs+e/2XBsbZTlSuWlp98ZcvTP7f/eCYP
#wA/SkaXp5HdNipmhqoqua2q/adlbAXgavm4OeXQdvQNDseoNj79fUlwU0zVV1h04pDO7b39pXR8T
#sWnZlGgfMZ/PYGaGz2cwgBgRSdOyidNsyP/HUwgEAgJAqaF75puWCUP3zAdQmoinDXebKf6c2XFI
#COJgMCibmttqQvWN5ZZlIlTfWN7U3FYTDAalEMTsOK4MnoQrT0nJgpnZ6/VCSvYj/hEO/NrT33v9
#+mhWdrZ/pOKxVQPMnAWAGw+3gJlZsjtybkiFZ8/M+0NKSXv3H1x/rrNrQdS0FFVVZF7ujNGZhfmO
#7dgTb+/YVWnbTpWha87ZCxdLpJQ0Z1bhVQDhO0aKiDgxT8WYubbrUu+SjtOdJYNXjt9DIDAYpmmB
#WYJIQNc1JOOqouDhBxd3v/jck3VEFEvOZbetmSr7KY106dGWE2unTp5ERMmOxvGpjh1mysnyjz+6
#Zvm3AE4lD5hKrfSMeIsZ/VYwLQu27Xoaxj9kefdJ1PUbvwAAAABJRU5ErkJggg==
#}]

} ;# namespace 37x21
} ;# namespace icon
} ;# namespace export

# vi:set ts=3 sw=3:
