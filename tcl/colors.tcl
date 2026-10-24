# ======================================================================
# Author : $Author: gcramer $
# Version: $Revision: 1517 $
# Date   : $Date: 2018-09-06 04:47:10 -0400 (Thu, 06 Sep 2018) $
# Url    : $URL: https://svn.code.sf.net/p/scidb/code/trunk/tcl/colors.tcl $
# ======================================================================

# ======================================================================
#    _/|            __
#   // o\         /    )           ,        /    /
#   || ._)    ----\---------__----------__-/----/__-
#   //__\          \      /   '  /    /   /    /   )
#   )___(     _(____/____(___ __/____(___/____(___/_
# ======================================================================

# ======================================================================
# Copyright: (C) 2014-2018 Gregor Cramer
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

namespace eval colors {

array set Colors {
	lite:pgn,background						#ffffff
	lite:pgn,foreground:main				#000000
	lite:pgn,foreground:variation			#0000ee
	lite:pgn,foreground:bracket			#0000ee
	lite:pgn,foreground:numbering			#aa0acd
	lite:pgn,foreground:nag					#ee0000
	lite:pgn,foreground:nagtext			#912a2a
	lite:pgn,foreground:comment			#006300
	lite:pgn,foreground:info				#8b4513
	lite:pgn,foreground:result				#000000
	lite:pgn,foreground:illegal			#ee0000
	lite:pgn,foreground:marks				#6300c6
	lite:pgn,foreground:empty				#666666
	lite:pgn,foreground:opening			#000000
	lite:pgn,foreground:result				#000000
	lite:pgn,background:current			#ffdd76
	lite:pgn,background:nextmove			#eeff00
	lite:pgn,background:merge				#f0f0f0
	lite:pgn,hilite:comment					#7a5807
	lite:pgn,hilite:info						#b22222
	lite:pgn,hilite:move						#dce4e5

	lite:analysis,background				#ffffee
	lite:analysis,info:background			#f5f5e4
	lite:analysis,info:foreground			darkgreen
	lite:analysis,best:foreground			darkgreen
	lite:analysis,error:foreground		darkred
	lite:analysis,active:background		#f5f5e4
	lite:analysis,layout:background		#ffee75

	lite:layout,background					#0170cc

	lite:database,selected					#ffdd76

	lite:information,html:hover			#ebf4f5
	lite:information,html:color			white
	lite:information,html:header			yellow
	lite:information,html:link				yellow
	lite:information,html:visited			#ffb432
	lite:information,html:menu				#ffdd76
	lite:information,background:news		orange
	lite:information,background:html		#014b72

	lite:tree,background						white
	lite:tree,emphasize						linen
	lite:tree,stripes							#ebf4f5
	lite:tree,ratio:color					darkgreen
	lite:tree,score:color					darkred
	lite:tree,draws:color					darkgreen
	lite:tree,progress:color				darkred
	lite:tree,progress:finished			forestgreen
	lite:tree,result:mono:white			white
	lite:tree,result:mono:black			black
	lite:tree,result:mono:remis			#808080
	lite:tree,result:color:white			darkred
	lite:tree,result:color:black			darkgreen
	lite:tree,result:color:remis			white

	lite:variation,background				white
	lite:variation,emphasize				linen
	lite:variation,stripes					#ebf4f5

	lite:board,modifiedForeground			white
	lite:board,modifiedBackground			brown
	lite:board,fixedBackground				#fff5d6

	lite:browser,background:header		#ebf4f5
	lite:browser,background:hilite		cornflowerblue
	lite:browser,background:modified		linen
	lite:browser,foreground:hilite		white

	lite:overview,background:normal		#ebf4f5
	lite:overview,background:modified	linen

	lite:crosstable,background				#ffffff
	lite:crosstable,highlighted			#ebf4f5
	lite:crosstable,mark						#ffdd76

	lite:export,shadow						#999999
	lite:export,text							#c0c0c0

	lite:import,background					#ebf4f5
	lite:import,background:select			#ffdd76
	lite:import,background:hilite			linen

	lite:switcher,background				#ebf4f5
	lite:switcher,selected:background	#ffdd76
	lite:switcher,modified:foreground	darkred
	lite:switcher,normal:background		LemonChiffon
	lite:switcher,normal:foreground		black
	lite:switcher,hidden:background		#ebf4f5
	lite:switcher,hidden:foreground		black
	lite:switcher,emph:foreground			darkgreen
	lite:switcher,drop:background			#98c187
	lite:switcher,prop:background			#aee239

	lite:fsbox,menu:headerbackground		#ffdd76
	lite:fsbox,menu:headerforeground		black
	lite:fsbox,drop:background				LemonChiffon
	lite:fsbox,selectionbackground		#ebf4f5
	lite:fsbox,selectionforeground		black
	lite:fsbox,inactivebackground			#f2f2f2
	lite:fsbox,inactiveforeground			black
	lite:fsbox,activebackground			#ebf4f5
	lite:fsbox,activeforeground			black

	lite:gamebar,background:normal		#d9d9d9
	lite:gamebar,foreground:normal		black
	lite:gamebar,background:selected		#dce4e5
	lite:gamebar,background:emphasize	linen
	lite:gamebar,background:active		#efefef
	lite:gamebar,background:darker		#828282
	lite:gamebar,background:shadow		#e6e6e6
	lite:gamebar,background:lighter		white
	lite:gamebar,background:hilite		cornflowerblue
	lite:gamebar,foreground:hilite		white
	lite:gamebar,background:hilite2		cornflowerblue
	lite:gamebar,foreground:hilite2		white
	lite:gamebar,foreground:elo			darkblue

	lite:scrolledtable,background			white
	lite:scrolledtable,stripes				#ebf4f5
	lite:scrolledtable,highlight			#f4f4f4
	lite:scrolledtable,separatorcolor	darkgrey

	lite:tlistbox,background				white
	lite:tlistbox,foreground				black
	lite:tlistbox,selectbackground		#ffdd76
	lite:tlistbox,selectforeground		black
	lite:tlistbox,disabledbackground		#ebf4f5
	lite:tlistbox,disabledforeground		black
	lite:tlistbox,highlightbackground	darkblue
	lite:tlistbox,highlightforeground	white
	lite:tlistbox,dropbackground			#dce4e5
	lite:tlistbox,dropforeground			black

	lite:treetable,background				white
	lite:treetable,disabledforeground	#999999

	lite:help,foreground:gray				#999999
	lite:help,foreground:litegray			#696969
	lite:help,background:gray				#f5f5f5
	lite:help,background:emphasize		LightGoldenrod

	lite:table,background					white
	lite:table,foreground					black
	lite:table,selectionbackground		#ffdd76
	lite:table,selectionforeground		black
	lite:table,disabledforeground			#555555
	lite:table,activebackground			#e5e5e5
	lite:table,labelforeground				black
	lite:table,labelbackground				#d9d9d9

	lite:fsbox,emphasizebackground		BlanchedAlmond

	lite:save,number							darkred
	lite:save,frequency						darkgreen
	lite:save,title							darkgreen
	lite:save,federation						darkblue
	lite:save,score							darkgreen
	lite:save,ratingType						darkblue
	lite:save,date								darkblue
	lite:save,eventDate						darkblue
	lite:save,eventCountry					darkblue
	lite:save,taglistOutline				gray
	lite:save,taglistBackground			LightYellow
	lite:save,taglistHighlighting			#ebf4f5
	lite:save,taglistCurrent				blue
	lite:save,matchlistBackground			#ebf4f5
	lite:save,matchlistHeaderForeground	#727272
	lite:save,matchlistHeaderBackground	#dfe7e8

	lite:encoding,selection					#ffdd76
	lite:encoding,active						#ebf4f5
	lite:encoding,normal						linen
	lite:encoding,description				#efefef

	lite:engine,selectbackground:dict	#ebf4f5
	lite:engine,selectbackground:setup	lightgray
	lite:engine,selectforeground:setup	black
	lite:engine,stripes						linen

	lite:default,disabledbackground		#ebf4f5
	lite:default,disabledforeground		black
	lite:default,foreground:gray			#999999

	lite:treetable,selected:focus			#ffdd76
	lite:treetable,selected!focus			#ffdd76
	lite:treetable,active:focus			#ebf4f5
	lite:treetable,hilite!selected		#ebf4f5

	lite:gamehistory,selected:focus		#ebf4f5
	lite:gamehistory,selected:hilite		#ebf4f5
	lite:gamehistory,selected!focus		#f2f2f2
	lite:gamehistory,hilite					#ebf4f5

	lite:playerdict,stripes					linen

	lite:varslider,background				#ffdd76
	lite:varslider,hilite					#ffc618

	lite:comment,label:altered				#555555
	lite:comment,label:foreground			white

	lite:eco,stripes							linen

	lite:layout-manager:normal				black
	lite:layout-manager:current			darkgreen
	lite:layout-manager:changed			darkred
}
# mapped from #ebf4f5
array set Colors {
	dark:tree,stripes							#dce4e5
	dark:variation,stripes					#dce4e5
	dark:import,background					#dce4e5
	dark:browser,background:header		#dce4e5
	dark:information,hover					#dce4e5
	dark:overview,background:normal		#dce4e5
	dark:crosstable,highlighted			#dce4e5
	dark:fsbox,selectionbackground		#dce4e5
	dark:scrolledtable,stripes				#dce4e5
	dark:tlistbox,disabledbackground		#dce4e5
	dark:tlistbox,dropbackground			#dce4e5
	dark:save,taglistHighlighting			#dce4e5
	dark:save,matchlistBackground			#dce4e5
	dark:encoding,active						#dce4e5
	dark:engine,selectbackground:dict	#dce4e5
	dark:default,disabledbackground		#dce4e5
	dark:treetable,active:focus			#dce4e5
	dark:treetable,hilite!selected		#dce4e5
	dark:gamehistory,selected:focus		#dce4e5
	dark:gamehistory,selected:hilite		#dce4e5
	dark:gamehistory,hilite					#dce4e5
	dark:fsbox,activebackground			#dce4e5
	dark:switcher,background				#dce4e5
	dark:switcher,hidden:background		#dce4e5
}
# mapped from #dce4e5
array set Colors {
	dark:pgn,hilite:move						#cddddf
}
# mapped from #f0f0f0
array set Colors {
	dark:pgn,background:merge				#e9e9e9
}
# mapped from #efefef
array set Colors {
	dark:gamebar,background:active		#e4e4e4
	dark:encoding,description				#e4e4e4
}
# mapped from linen
array set Colors {
	dark:tree,emphasize						#ecded0
	dark:variation,emphasize				#ecded0
	dark:browser,background:modified		#ecded0
	dark:overview,background:modified	#ecded0
	dark:import,background:hilite			#ecded0
	dark:gamebar,background:emphasize	#ecded0
	dark:encoding,normal						#ecded0
	dark:playerdict,stripes					#ecded0
	dark:engine,stripes						#ecded0
	dark:eco,stripes							#ecded0
}
# mapped from #f5f5e4
array set Colors {
	dark:analysis,info:background			#d9d9ca
	dark:analysis,active:background		#d9d9ca
}
# mapped from #dfe7e8
array set Colors {
	dark:save,matchlistHeaderBackground	#d1d8d9
}
# mapped from #999999
array set Colors {
	dark:default,foreground:gray			#777777
}

# Full dark UI theme palette (used when [::theme::isDark] is true)
array set Colors {
	darktheme:pgn,background				#1b1f27
	darktheme:pgn,foreground:main			#e6edf3
	darktheme:pgn,foreground:variation	#79c0ff
	darktheme:pgn,foreground:bracket		#79c0ff
	darktheme:pgn,foreground:numbering	#d2a8ff
	darktheme:pgn,foreground:nag			#ff7b72
	darktheme:pgn,foreground:nagtext		#ffa198
	darktheme:pgn,foreground:comment		#56d364
	darktheme:pgn,foreground:info			#ffa657
	darktheme:pgn,foreground:result		#e6edf3
	darktheme:pgn,foreground:illegal		#ff7b72
	darktheme:pgn,foreground:marks		#d2a8ff
	darktheme:pgn,foreground:empty		#8b949e
	darktheme:pgn,foreground:opening		#e6edf3
	darktheme:pgn,background:current		#2f6feb
	darktheme:pgn,foreground:current		#ffffff
	darktheme:pgn,background:nextmove	#4d4214
	darktheme:pgn,background:merge		#282e38
	darktheme:pgn,hilite:comment			#f2cc60
	darktheme:pgn,hilite:info				#ff7b72
	darktheme:pgn,hilite:move				#2c3340

	darktheme:analysis,background			#1b1f27
	darktheme:analysis,info:background	#242a34
	darktheme:analysis,info:foreground	#56d364
	darktheme:analysis,best:foreground	#56d364
	darktheme:analysis,error:foreground	#ff7b72
	darktheme:analysis,active:background #283040
	darktheme:analysis,layout:background #3b3518

	darktheme:layout,background			#1f4d7a

	darktheme:database,selected			#2f6feb

	darktheme:information,html:hover		#2c3340
	darktheme:information,hover			#2c3340
	darktheme:information,html:color		#e6edf3
	darktheme:information,html:header	#f2cc60
	darktheme:information,html:link		#79c0ff
	darktheme:information,html:visited	#d2a8ff
	darktheme:information,html:menu		#2f6feb
	darktheme:information,background:news #9e6a03
	darktheme:information,background:html #162436

	darktheme:tree,background				#1b1f27
	darktheme:tree,emphasize				#283040
	darktheme:tree,stripes					#232832
	darktheme:tree,ratio:color				#56d364
	darktheme:tree,score:color				#ff7b72
	darktheme:tree,draws:color				#56d364
	darktheme:tree,progress:color			#ff7b72
	darktheme:tree,progress:finished		#56d364
	darktheme:tree,result:mono:white		#e6edf3
	darktheme:tree,result:mono:black		#1b1f27
	darktheme:tree,result:mono:remis		#808080
	darktheme:tree,result:color:white	#ff7b72
	darktheme:tree,result:color:black	#56d364
	darktheme:tree,result:color:remis	#e6edf3

	darktheme:variation,background		#1b1f27
	darktheme:variation,emphasize			#283040
	darktheme:variation,stripes			#232832

	darktheme:board,modifiedForeground	#ffffff
	darktheme:board,modifiedBackground	#8b4513
	darktheme:board,fixedBackground		#2d3548

	darktheme:browser,background:header	#282e38
	darktheme:browser,background:hilite	#2f6feb
	darktheme:browser,background:modified #283040
	darktheme:browser,foreground:hilite	#ffffff

	darktheme:overview,background:normal #232832
	darktheme:overview,background:modified #283040

	darktheme:crosstable,background		#1b1f27
	darktheme:crosstable,highlighted		#283040
	darktheme:crosstable,mark				#2f6feb

	darktheme:export,shadow					#484f58
	darktheme:export,text					#8b949e

	darktheme:import,background			#232832
	darktheme:import,background:select	#2f6feb
	darktheme:import,background:hilite	#283040

	darktheme:switcher,background			#181b20
	darktheme:switcher,selected:background #28354a
	darktheme:switcher,modified:foreground #ff7b72
	darktheme:switcher,normal:background #23272e
	darktheme:switcher,normal:foreground #e6edf3
	darktheme:switcher,hidden:background #1e2228
	darktheme:switcher,hidden:foreground #9ca3af
	darktheme:switcher,emph:foreground	#56d364
	darktheme:switcher,drop:background	#23482c
	darktheme:switcher,prop:background	#2d5927

	darktheme:fsbox,menu:headerbackground #28354a
	darktheme:fsbox,menu:headerforeground #e6edf3
	darktheme:fsbox,drop:background		#2d3548
	darktheme:fsbox,selectionbackground	#2f6feb
	darktheme:fsbox,selectionforeground	#ffffff
	darktheme:fsbox,inactivebackground	#2c323d
	darktheme:fsbox,inactiveforeground	#e6edf3
	darktheme:fsbox,activebackground		#283040
	darktheme:fsbox,activeforeground		#e6edf3
	darktheme:fsbox,emphasizebackground	#2d3548
	darktheme:fsbox,background				#1b1f27
	darktheme:fsbox,foreground				#e6edf3
	darktheme:fsbox,stripes					#232832
	darktheme:fsbox,disabledforeground	#8b949e

	darktheme:gamebar,background:normal	#23272e
	darktheme:gamebar,foreground:normal	#e6edf3
	darktheme:gamebar,background:selected #2b3548
	darktheme:gamebar,background:emphasize #283040
	darktheme:gamebar,background:active	#303642
	darktheme:gamebar,background:darker	#14171c
	darktheme:gamebar,background:shadow	#1a1d24
	darktheme:gamebar,background:lighter #383f4d
	darktheme:gamebar,background:hilite	#2f6feb
	darktheme:gamebar,foreground:hilite	#ffffff
	darktheme:gamebar,background:hilite2 #2f6feb
	darktheme:gamebar,foreground:hilite2 #ffffff
	darktheme:gamebar,foreground:elo		#79c0ff

	darktheme:scrolledtable,background	#1b1f27
	darktheme:scrolledtable,stripes		#232832
	darktheme:scrolledtable,highlight	#2d3548
	darktheme:scrolledtable,separatorcolor #3d444d

	darktheme:tlistbox,background			#1b1f27
	darktheme:tlistbox,foreground			#e6edf3
	darktheme:tlistbox,selectbackground	#2f6feb
	darktheme:tlistbox,selectforeground	#ffffff
	darktheme:tlistbox,disabledbackground #232832
	darktheme:tlistbox,disabledforeground #8b949e
	darktheme:tlistbox,highlightbackground #388bfd
	darktheme:tlistbox,highlightforeground #ffffff
	darktheme:tlistbox,dropbackground	#283040
	darktheme:tlistbox,dropforeground	#e6edf3

	darktheme:treetable,background		#1b1f27
	darktheme:treetable,foreground		#e6edf3
	darktheme:treetable,disabledforeground #8b949e
	darktheme:treetable,selected:focus	#2f6feb
	darktheme:treetable,selected!focus	#28354a
	darktheme:treetable,active:focus		#283040
	darktheme:treetable,hilite!selected	#283040

	darktheme:help,foreground:gray		#8b949e
	darktheme:help,foreground:litegray	#9ca3af
	darktheme:help,background:gray		#282e38
	darktheme:help,background:emphasize	#2d3548

	darktheme:table,background				#1b1f27
	darktheme:table,foreground				#e6edf3
	darktheme:table,selectionbackground	#2f6feb
	darktheme:table,selectionforeground	#ffffff
	darktheme:table,disabledforeground	#8b949e
	darktheme:table,activebackground		#283040
	darktheme:table,labelforeground		#e6edf3
	darktheme:table,labelbackground		#2b303b
	darktheme:table,stripes					#232832
	darktheme:table,highlightcolor		#58a6ff
	darktheme:table,menu:headerbackground #28354a
	darktheme:table,menu:headerforeground #e6edf3

	darktheme:save,number					#ff7b72
	darktheme:save,frequency				#56d364
	darktheme:save,title						#56d364
	darktheme:save,federation				#79c0ff
	darktheme:save,score						#56d364
	darktheme:save,ratingType				#79c0ff
	darktheme:save,date						#79c0ff
	darktheme:save,eventDate				#79c0ff
	darktheme:save,eventCountry			#79c0ff
	darktheme:save,taglistOutline			#484f58
	darktheme:save,taglistBackground		#232832
	darktheme:save,taglistHighlighting	#283040
	darktheme:save,taglistCurrent			#58a6ff
	darktheme:save,matchlistBackground	#1b1f27
	darktheme:save,matchlistHeaderForeground #9ca3af
	darktheme:save,matchlistHeaderBackground #282e38

	darktheme:encoding,selection			#2f6feb
	darktheme:encoding,active				#283040
	darktheme:encoding,normal				#232832
	darktheme:encoding,description		#282e38

	darktheme:engine,selectbackground:dict #283040
	darktheme:engine,selectbackground:setup #2f6feb
	darktheme:engine,selectforeground:setup #ffffff
	darktheme:engine,stripes				#232832

	darktheme:default,disabledbackground #232832
	darktheme:default,disabledforeground #8b949e
	darktheme:default,foreground:gray	#9ca3af

	darktheme:gamehistory,selected:focus #2f6feb
	darktheme:gamehistory,selected:hilite #388bfd
	darktheme:gamehistory,selected!focus #28354a
	darktheme:gamehistory,hilite			#283040

	darktheme:playerdict,stripes			#232832

	darktheme:varslider,background		#2f6feb
	darktheme:varslider,hilite				#388bfd

	darktheme:comment,label:altered		#3b4252
	darktheme:comment,label:foreground	#e6edf3

	darktheme:eco,stripes					#232832

	darktheme:layout-manager:normal		#e6edf3
	darktheme:layout-manager:current		#56d364
	darktheme:layout-manager:changed		#ff7b72
}

# Mapping for literal / named colors passed through ::colors::lookup when dark theme is active
array set DarkColorMap {
	black					#e6edf3
	#000000				#e6edf3
	white					#1b1f27
	#ffffff				#1b1f27
	darkblue				#79c0ff
	darkBlue				#79c0ff
	steelblue4			#79c0ff
	blue					#58a6ff
	blue2					#58a6ff
	blue3					#58a6ff
	#0000ee				#58a6ff
	darkgreen			#56d364
	darkGreen			#56d364
	forestgreen			#56d364
	#008b00				#56d364
	#006300				#56d364
	darkred				#ff7b72
	darkRed				#ff7b72
	red					#ff7b72
	red2					#ff7b72
	red3					#ff7b72
	red4					#ff7b72
	#ee0000				#ff7b72
	#912a2a				#ffa198
	#b22222				#ff7b72
	darkviolet			#d2a8ff
	magenta4				#d2a8ff
	purple				#d2a8ff
	#aa0acd				#d2a8ff
	#6300c6				#d2a8ff
	brown					#ffa657
	#68480a				#ffa657
	#8b4513				#ffa657
	#7a5807				#f2cc60
	gray50				#9ca3af
	gray30				#9ca3af
	gray25				#9ca3af
	darkslategray		#9ca3af
	#555555				#9ca3af
	#666666				#9ca3af
	#727272				#9ca3af
	linen					#283040
	LemonChiffon		#2d3548
	LightYellow			#2d3548
	BlanchedAlmond		#2d3548
	LightGoldenrod		#2d3548
	#ebf4f5				#232832
	#dce4e5				#282e38
	#f0f0f0				#282e38
	#efefef				#282e38
	#e5e5e5				#283040
	#d9d9d9				#2b303b
}

# Defaults for lite mode if new keys are looked up
array set Colors {
	lite:pgn,foreground:current			#000000
	lite:treetable,foreground				#000000
	lite:table,stripes						#ebf4f5
	lite:table,highlightcolor				darkblue
	lite:table,menu:headerbackground		#d3d3d3
	lite:table,menu:headerforeground		#000000
	lite:fsbox,background					#ffffff
	lite:fsbox,foreground					#000000
	lite:fsbox,stripes						#ebf4f5
	lite:fsbox,disabledforeground			#555555
}

set Scheme dark

proc lookup {color} {
	variable Colors
	variable DarkColorMap
	variable Scheme

	if {[string match theme,* $color]} {
		return [::theme::getColor [string range $color 6 end]]
	}

	if {[namespace exists ::theme] && [info procs ::theme::isDark] ne "" && [::theme::isDark]} {
		if {[info exists Colors(darktheme:$color)]} { return $Colors(darktheme:$color) }
		if {[info exists DarkColorMap($color)]} { return $DarkColorMap($color) }
	}

	if {[info exists Colors($Scheme:$color)]} { return $Colors($Scheme:$color) }
	if {[info exists Colors(lite:$color)]} { return $Colors(lite:$color) }

	return $color
}


proc hsv2rgb {h s v} { return [::dialog::choosecolor::hsv2rgb $h $s $v] }
proc rgb2hsv {r g b} { return [::dialog::choosecolor::rgb2hsv $r $g $b] }
proc getActualColor {color} { return [::dialog::choosecolor::getActualColor $color] }


proc makeActiveColor {color} {
	scan [getActualColor $color] "\#%2x%2x%2x" r g b
	lassign [rgb2hsv $r $g $b] h s v
	return [format "#%02x%02x%02x" {*}[hsv2rgb $h $s [expr {min(1.0, $v + 0.1)}]]]
}


proc makeHiliteColor {color} {
	scan [getActualColor $color] "\#%2x%2x%2x" r g b
	lassign [rgb2hsv $r $g $b] h s v
	return [format "#%02x%02x%02x" {*}[hsv2rgb $h 1.0 1.0]]
}

} ;# namespace colors

# vi:set ts=3 sw=3:
