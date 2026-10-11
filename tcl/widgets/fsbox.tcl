# ======================================================================
# Author : $Author$
# Version: $Revision: 1525 $
# Date   : $Date: 2018-09-18 06:54:18 -0400 (Tue, 18 Sep 2018) $
# Url    : $URL$
# ======================================================================

# ======================================================================
# Copyright: (C) 2011-2018 Gregor Cramer
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

package require Tk 8.5
package require tktreectrl 2.2
package require toolbar
package require choosedir
package require tcombobox
package require entrybuttonbox
package require messagebox
catch { package require tkDND 2.3 }
if {[catch { package require tkpng }]} { package require Img }
package provide fxbox 1.0


proc fsbox {w type args} { return [fsbox::fsbox $w $type {*}$args] }


namespace eval fsbox {
namespace eval mc {

set Name								"Name"
set Size								"Size"
set Modified						"Modified"

set Forward							"Forward to '%s'"
set Backward						"Backward to '%s'"
set Delete							"Delete"
set MoveToTrash					"Move to Trash"
set Restore							"Restore"
set Duplicate						"Duplicate"
set CopyOf							"Copy of %s"
set NewFolder						"New Folder"
set Layout							"Layout"
set ListLayout						"List Layout"
set DetailedLayout				"Detailed Layout"
set ShowHiddenDirs				"Show Hidden Directories"
set ShowHiddenFiles				"Show Hidden Files and Directories"
set AppendToExisitingFile		"&Append to an existing file"
set Cancel							"&Cancel"
set Save								"&Save"
set Open								"&Open"
set Overwrite						"&Overwrite"
set Rename							"&Rename"
set Move								"Move"

set AddBookmark					"Add Bookmark '%s'"
set RemoveBookmark				"Remove Bookmark '%s'"
set RenameBookmark				"Rename Bookmark '%s'"

set Filename						"File &name:"
set Filenames						"File &names:"
set Directory						"Directory:"
set FilesType						"Files of &type:"
set FileEncoding					"File &encoding:"

set Favorites						"Favorites"
set LastVisited					"Last Visited"
set FileSystem						"File System"
set Desktop							"Desktop"
set Trash							"Trash"
set Download						"Download"
set Home								"Home"

set SelectEncoding				"Select the encoding of the database (opens a dialog)"
set SelectWhichType				"Select which type of file are shown"
set TimeFormat						"%d/%m/%y %I:%M %p"

set CannotChangeDir				"Cannot change to the directory \"%s\".\nPermission denied."
set DirectoryRemoved				"Cannot change to the directory \"%s\".\nDirectory is removed."
set DeleteFailed					"Deletion of '%s' failed."
set RstoreFailed					"Restoring '%s' failed."
set CopyFailed						"Copying of file '%s' failed: permission denied."
set CannotCopy						"Cannot create a copy because file '%s' is already existing."
set CannotDuplicate				"Cannot duplicate file '%s' due to the lack of read permission."
set ReallyDuplicateFile			"Really duplicate this file?"
set ReallyDuplicateDetail		"This file has about %s. Duplicating this file may take some time."
set InvalidFileExt				"Operation failed: '%s' has an invalid file extension."
set CannotRename					"Cannot rename to '%s' because this folder/file already exists."
set CannotCreate					"Cannot create folder '%s' because this folder/file already exists."
set ErrorCreate					"Error creating folder: permission denied."
set FilenameNotAllowed			"Filename '%s' is not allowed."
set ContainsTwoDots				"Contains two consecutive dots."
set ContainsReservedChars		"Contains reserved characters: %s, or a control character (ASCII 0-31)."
set InvalidFileName				"A filename cannot start with a hyphen, and cannot end with a space or a period."
set IsReservedName				"On some operating systems this is an reserved name."
set FilenameTooLong				"A file name should have less than 256 characters."
set InvalidFileExtension		"Invalid file extension in '%s'."
set MissingFileExtension		"Missing file extension in '%s'."
set FileAlreadyExists			"File \"%s\" already exists.\n\nDo you want to overwrite it?"
set CannotOverwriteDirectory	"Cannot overwite directory '%s'."
set FileDoesNotExist				"File \"%s\" does not exist."
set DirectoryDoesNotExist		"Directory \"%s\" does not exist."
set CannotOpenOrCreate			"Cannot open/create '%s'. Please choose a directory."
set WaitWhileDuplicating		"Wait while duplicating file..."
set FileHasDisappeared			"File '%s' has disappeared."
set CurrentlyInUse				"This file is currently in use."
set PermissionDenied				"Permission denied for directory '%s'."
set CannotOpenUri					"Cannot open the following URI:"
set InvalidUri						"Drop content is not a valid URI list."
set CannotOpenTrashFiles			"Cannot open trashed files."
set UriRejected					"The following files are rejected:"
set UriRejectedDetail			"Only the listed file types can be handled."
set CannotOpenRemoteFiles		"Cannot open remote files:"
set CannotCopyFolders			"Cannot copy folders, thus these folders will be rejected:"
set OperationAborted				"Operation aborted."
set ApplyOnDirectories			"Are you sure that you want to apply the selected operation on (the following) directories?"
set EntryAlreadyExists			"Entry already exists"
set AnEntryAlreadyExists		"An entry '%s' already exists."
set SourceDirectoryIs			"The source directories is '%s'."
set NewName							"New name"
set BookmarkAlreadyExists		"A bookmark for this folder is already existing: '%s'."
set AddBookmarkAnyway			"Add bookmark anyway?"
set OriginalPathDoesNotExist	"The original directory '%s' of this item does not exist anymore. Create this directory and continue with operation?"
set DragItemAnywhere				"An alternative may be to drag the item anywhere else to restore it."

set ReallyMove(file,w)			"Really move file '%s' to trash?"
set ReallyMove(file,r)			"Really move write-protected file '%s' to trash?"
set ReallyMove(folder,w)		"Really move folder '%s' to trash?"
set ReallyMove(folder,r)		"Really move write-protected folder '%s' to trash?"
set ReallyDelete(file,w)		"Really delete file '%s'? You cannot undo this operation."
set ReallyDelete(file,r)		"Really delete write-protected file '%s'? You cannot undo this operation."
set ReallyDelete(link,w)		"Really delete link to '%s'?"
set ReallyDelete(link,r)		"Really delete link to '%s'?"
set ReallyDelete(folder,w)		"Really delete folder '%s'? You cannot undo this operation."
set ReallyDelete(folder,r)		"Really delete write-protected folder '%s'? You cannot undo this operation."
set ReallyDelete(empty,w)		"Really delete empty folder '%s'? You cannot undo this operation."
set ReallyDelete(empty,r)		"Really delete empty write-protected folder '%s'? You cannot undo this operation."

set ErrorRenaming(folder)		"Error renaming folder '%old' to '%new': permission denied."
set ErrorRenaming(file)			"Error renaming file '%old' to '%new': permission denied."

set Cannot(delete)				"Cannot delete file '%s'."
set Cannot(rename)				"Cannot rename file '%s'."
set Cannot(move)					"Cannot move file '%s'."
set Cannot(overwrite)			"Cannot overwrite file '%s'."

set DropAction(move)				"Move Here"
set DropAction(copy)				"Copy Here"
set DropAction(link)				"Link Here"
set DropAction(restore)			"Restore Here"

}

namespace import ::tcl::mathfunc::max

set HaveFAM 1
set DuplicateFileSizeLimit 5000000
set CurrentPath ""

# possibly we should avoid "{}[]+=,;%", too - especially ';' should be avoided!?
set reservedChars	{\" \\ / : * < > ? |}
set controlMask	4 ;# default
set shiftMask		1 ;# default

array set Options {
	show:hidden					0
	show:layout					details
	show:filetypeicons		1
	pane:favorites				0
	menu:headerbackground	fsbox,menu:headerbackground
	menu:headerforeground	fsbox,menu:headerforeground
	drop:background			fsbox,drop:background
	tooltip:shorten-paths	0
}

array set Colors {
	-selectionbackground		fsbox,selectionbackground
	-selectionforeground		fsbox,selectionforeground
	-inactivebackground		fsbox,inactivebackground
	-inactiveforeground		fsbox,inactiveforeground
	-activebackground			fsbox,activebackground
	-activeforeground			fsbox,activeforeground
	-emphasizebackground		fsbox,emphasizebackground
}

array set ColorLookup {
	fsbox,menu:headerbackground	#ffdd76
	fsbox,menu:headerforeground	black
	fsbox,drop:background			LemonChiffon
	fsbox,selectionbackground		#ebf4f5
	fsbox,selectionforeground		black
	fsbox,inactivebackground		#f2f2f2
	fsbox,inactiveforeground		black
	fsbox,activebackground			#ebf4f5
	fsbox,activeforeground			black
	fsbox,emphasizebackground		BlanchedAlmond
}


proc fsbox {w type args} {
	variable Options
	variable Colors
	variable CurrentPath
	variable icon::16x16::filesystem

	if {![namespace exists [namespace current]::${w}]} {
		namespace eval [namespace current]::${w} {}
	}
	variable ${w}::Vars

	array set opts {
		-background					white
		-foreground					black
		-bookmarkswidth			120
		-borderwidth				1
		-relief						sunken
		-doublebuffer				window
		-savemode					0
		-multiple					0
		-checkexistence			1
		-initialdir					{}
		-initialfile				{}
		-directory					{}
		-showhidden					{}
		-defaultextension			{}
		-defaultencoding			{}
		-filetypes					{}
		-fileicons					{}
		-filecursors				{}
		-sizecommand				{}
		-validatecommand			{}
		-selectencodingcommand	{}
		-fileencodings				{}
		-deletecommand				{}
		-renamecommand				{}
		-duplicatecommand			{}
		-okcommand					{}
		-cancelcommand				{}
		-inspectcommand			{}
		-filetypecommand			{}
		-mapextcommand				{}
		-customcommand				{}
		-customfiletypes			{}
		-customicon					{}
		-customtooltip				{}
		-helpcommand				{}
		-helpicon					{}
		-helplabel					{}
		-isusedcommand				{}
		-formattimecmd				{}
		-actions						{delete rename copy new}
	}
	set opts(-font) TkTextFont
	array set opts [array get Colors]

	array set opts $args
	if {$opts(-multiple)} { set opts(-selectmode) extended } else { set opts(-selectmode) single }

	foreach option {	selectionbackground selectionforeground font multiple savemode
							activebackground activeforeground emphasizebackground defaultextension
							defaultencoding inactivebackground inactiveforeground filetypes fileencodings
							fileicons filecursors showhidden directory sizecommand selectencodingcommand
							validatecommand deletecommand renamecommand duplicatecommand okcommand
							cancelcommand inspectcommand filetypecommand initialfile bookmarkswidth
							customcommand customicon customtooltip customfiletypes helpcommand helpicon
							helplabel isusedcommand actions mapextcommand formattimecmd checkexistence} {
		set Vars($option) $opts(-$option)
		array unset opts -$option
	}

	if {$Options(pane:favorites) == 0} {
		set Options(pane:favorites) $Vars(bookmarkswidth)
	}
	if {[llength $Vars(showhidden)] == 0} {
		set Vars(showhidden) $Options(show:hidden)
	}
	if {[llength $Vars(sizecommand)] == 0} {
		set Vars(sizecommand) [namespace code GetFileSize]
	}
	if {[llength $Vars(validatecommand)] == 0} {
		set Vars(validatecommand) [namespace code ValidateFile]
	}

	set Vars(delete:action) delete
	set filesystem $::choosedir::icon::16x16::fileSystem

	set Vars(type) $type
	set Vars(glob) Files
	set Vars(fam) {}
	set Vars(folder:home) [file nativename ~]
	set Vars(folder:desktop) [desktop::directory]
	set Vars(folder:trash) ""
	set Vars(folder:download) [file join $Vars(folder:home) Downloads]
	set Vars(folder:filesystem) [fileSeparator]
	set Vars(bookmark:folder) ""
	set Vars(edit:active) 0
	set Vars(lookup:$Vars(folder:home)) home
	set Vars(lookup:$Vars(folder:filesystem)) filesystem
	set Vars(history:folder) ""
	set Vars(drag:active) 0
	set Vars(drag:private) 0
	set Vars(drag:trash) 0
	set Vars(startup) 1
	set Vars(extensions) {}
	set Vars(onlyexecutables) 0
	set Vars(usb-devices) {}

	if {$type ne "save"} { set Vars(folder:trash) [::trash::directory] }
	if {[llength $Vars(folder:desktop)]} { set Vars(lookup:$Vars(folder:desktop)) desktop }
	if {![file isdirectory $Vars(folder:download)]} { set Vars(folder:download) "" }

	set Vars(icon:lastvisited) $icon::16x16::visited
	set Vars(icon:favorites) $icon::16x16::star
	set Vars(icon:desktop) $icon::16x16::desktop
	set Vars(icon:download) $icon::16x16::download
	set Vars(icon:filesystem) $icon::16x16::filesystem
	set Vars(icon:trash) $icon::16x16::trash
	set Vars(icon:home) $icon::16x16::home

	set initialdir $opts(-initialdir)
	array unset opts -initialdir
	set Vars(folder) $initialdir
	set Vars(prevFolder) ""
	set Vars(prevGlob) ""
	if {[string length $Vars(folder)] == 0 || ![file isdirectory $Vars(folder)]} {
		set Vars(folder) [pwd]
		set Vars(lastFolder) ""
	} else {
		set Vars(lastFolder) $Vars(folder)
	}

	set Vars(widget:main) $w
	tk::frame $w -takefocus 0
	set top [ttk::frame $w.top -takefocus 0]
	pack $top -fill both -expand yes
	set Vars(choosedir) \
		[choosedir $top.folder -initialdir $Vars(folder) -showlabel 1 -showhidden $Vars(showhidden)]
	bind $Vars(choosedir) <<SetDirectory>> [namespace code [list ChangeDir $w %d]]
	bind $Vars(choosedir) <<SetFolder>>    [namespace code [list ChangeDir $w %d]]
	bind $Vars(choosedir) <<GetStartMenu>> [namespace code [list GetStartMenu $w]]

	tk::panedwindow $top.main -sashwidth 7 -sashrelief flat
	set Vars(widget:panedwindow) $top.main

	if {$Vars(type) eq "dir"} {
		set Vars(multiple) 0
		set lbl [Tr Directory]
		set Vars(initialfile) $Vars(folder)
	} elseif {$Vars(multiple)} {
		set lbl [Tr Filenames]
	} else {
		set lbl [Tr Filename]
	}
	::tk::AmpWidget ttk::label $top.lbl_filename -text $lbl
	set Vars(widget:filename) [ttk::entry $top.ent_filename \
		-cursor xterm \
		-textvariable [namespace current]::${w}::Vars(initialfile) \
	]
	$top.ent_filename icursor end
	bind $top.lbl_filename <<AltUnderlined>> [list focus $top.ent_filename]
	bind $top.ent_filename <FocusIn> [namespace code { FocusIn %W }]
	bind $top.ent_filename <FocusOut> [namespace code { FocusOut %W }]
	bind $top.ent_filename <Return> [namespace code [list Activate $w yes]]
	bind $top.ent_filename <Return> {+ break }
	bind $top.ent_filename <Any-KeyRelease> [namespace code [list CheckFileEncoding $w]]

	set Vars(widget:encoding:label) [::tk::AmpWidget ttk::label $top.lbl_encoding -text [Tr FileEncoding]]
	set Vars(widget:encoding:entry) [ttk::entrybuttonbox $top.ent_encoding \
		-width 14 \
		-textvar [namespace current]::${w}::Vars(encodingVar) \
		-command [namespace code [list SelectEncoding $w]] \
	]
	bind $Vars(widget:encoding:label) <<AltUnderlined>> [list $Vars(widget:encoding:entry) invoke]
	bind $Vars(widget:encoding:entry) <Any-ButtonPress> {+ ::tooltip::tooltip hide }
	tooltip $top.ent_encoding [Tr SelectEncoding]

	if {[llength $Vars(selectencodingcommand)]} {
		set Vars(encodingVar) $Vars(defaultencoding)
		set Vars(encodingDefault) ""
		set Vars(encodingUser) ""
	}

	::tk::AmpWidget ttk::label $top.lbl_filetype -text [Tr FilesType]
	ttk::tcombobox $top.ent_filetype  \
		-state readonly                \
		-format "%1 (%2)"              \
		-padding 1                     \
		;
	bind $top.ent_filetype <<ComboboxSelected>> [namespace code [list SelectFileTypes $w %W]]
	bind $top.lbl_filetype <<AltUnderlined>> [list ::ttk::combobox::Post $top.ent_filetype]
	set Vars(widget:filetypes:combobox) $top.ent_filetype
	tooltip $top.ent_filetype [Tr SelectWhichType]

	if {$Options(show:filetypeicons)} {
		tk::canvas $top.cnv_filetype -width 1 -height 1 -relief sunken -borderwidth 1 -takefocus 0
		bind $top.cnv_filetype <Configure> [namespace code [list SetFileTypes $w]]
#		bind $top.cnv_filetype <ButtonPress-1> [list $top.ent_filetype post]
		set Vars(widget:filetypes:canvas) $top.cnv_filetype
#		tooltip $top.cnv_filetype [Tr SelectWhichType]
	}

	grid columnconfigure $top {3} -weight 1
	grid columnconfigure $top {0 2 8} -minsize 5
	grid rowconfigure $top {3} -weight 1
	grid rowconfigure $top {0 2 4 6} -minsize 5

	grid $top.folder 			-row 1 -column 1 -sticky ew -columnspan 7
	grid $top.main				-row 3 -column 1 -sticky nsew -columnspan 7
	grid $top.lbl_filename	-row 5 -column 1 -sticky w
	grid $top.ent_filename	-row 5 -column 3 -sticky ew

	if {[llength $Vars(selectencodingcommand)]} {
		grid $top.lbl_encoding -row 5 -column 5
		grid $top.ent_encoding -row 5 -column 7
		grid columnconfigure $top {4} -minsize 10
		grid columnconfigure $top {6} -minsize 5
		grid columnconfigure $top {7} -minsize 0
	} else { ;#if {[llength $Vars(filetypes)]}
		grid $top.ent_filename -columnspan 5
		grid columnconfigure $top {7} -minsize 92
	}

	set buttons [tk::frame $w.buttons -takefocus 0]
	pack [ttk::separator $w.sep] -fill x
	pack $buttons -fill x -expand no
	ttk::style configure fsbox.TButton -anchor w
	if {$type eq "save"} {
		set Vars(button:mode) [tk::AmpWidget ttk::checkbutton $buttons.mode  \
			-variable [namespace current]::${w}::Vars(savemode:value) \
			-text [Tr AppendToExisitingFile] \
			-command [namespace code [list SetupSaveMode $w]] \
			-onvalue append \
			-offvalue overwrite \
		]
	}
	set Vars(button:ok) [tk::AmpWidget ttk::button $buttons.ok \
		-class TButton \
		-default active \
		-compound left \
		-command [namespace code [list Activate $w yes]] \
	]
	set Vars(button:cancel) [tk::AmpWidget ttk::button $buttons.cancel  \
		-class TButton \
		-default normal \
		-compound left \
		-image $icon::16x16::cancel \
		-command [namespace code [list Cancel $w]] \
	]
	if {[llength $Vars(helpcommand)]} {
		tk::AmpWidget ttk::button $buttons.help  \
			-class TButton \
			-default normal \
			-compound left \
			-image $Vars(helpicon) \
			-command [list $Vars(helpcommand) $w] \
			;
	}
	set utype [string toupper $Vars(type) 0 0]
	if {$utype eq "Dir"} { set utype Open }
	tk::SetAmpText $buttons.cancel " [Tr Cancel]"
	tk::SetAmpText $buttons.ok " [Tr $utype]"
	if {[llength $Vars(helpcommand)]} {
		tk::SetAmpText $buttons.help " $Vars(helplabel)"
	}
	changeFileDialogType $w $type

	bind $Vars(button:ok) <Return> [namespace code { InvokeOk %W }]
	bind $Vars(button:ok) <Return> {+ break }
	bind $Vars(button:cancel) <Return> [namespace code [list Cancel $w]]
	bind $Vars(button:cancel) <Return> {+ break }

	if {$type eq "save"} { useSaveMode $w $Vars(savemode) }
	if {[llength $Vars(helpcommand)]} { pack $buttons.help -pady 5 -padx 5 -fill x -side left }
	pack $Vars(button:cancel) -pady 5 -padx 5 -fill x -side right
	pack $Vars(button:ok) -pady 5 -padx 5 -fill x -side right

	bind $top.main <<ThemeChanged>> [namespace code [list ThemeChanged $w]]

	set tl [winfo toplevel $top]
#	bind $tl <Escape>		[list $Vars(button:cancel) invoke]
	bind $tl <Return>		[list $Vars(button:ok) invoke]
	bind $tl <Return>		{+ break }
	bind $tl <Alt-Key>	[namespace code [list AltKeyInDialog $top $tl %A]]
	bind $tl <Alt-Left>	[namespace code [list Undo $top $w]]
	bind $tl <Alt-Right>	[namespace code [list Redo $top $w]]
	if {[llength $Vars(helpcommand)]} {
		bind $tl <F1>		[list $Vars(helpcommand) $w]
	}

	array unset Vars widget:list:file
	setFileTypes $w $Vars(filetypes) $Vars(defaultextension)

	bookmarks::Build $w $top.main.fav {*}[array get opts]
	filelist::Build $w $top.main.list {*}[array get opts]
	set Vars(widget:favorites) $top.main.fav

	$top.main add $top.main.fav  -minsize 0 -sticky nsew -stretch last
	$top.main add $top.main.list -minsize 300 -sticky nsew -stretch always

	bind $top.main.fav <Configure> [namespace code { ConfigurePane %w }]

	if {![file isdirectory $initialdir]} { set initialdir [pwd] }

	set CurrentPath $w
	CheckInitialFile $w
	ChangeDir $w $initialdir
	DirChanged $w 1
	SelectInitialFile $w
	focus $top.ent_filename

	return $w
}


proc reset {w type args} {
	variable ${w}::Vars
	variable Options
	variable CurrentPath

	array set opts {
		-multiple					0 
		-checkexistence			1
		-initialdir					""
		-initialfile				""
		-filetypes					{}
		-fileicons					{}
		-filecursors				{}
		-defaultextension			{}
		-defaultencoding			{}
		-sizecommand				{}
		-validatecommand			{}
		-selectencodingcommand	{}
		-deletecommand				{}
		-renamecommand				{}
		-duplicatecommand			{}
		-okcommand					{}
		-cancelcommand				{}
		-inspectcommand			{}
		-filetypecommand			{}
		-mapextcommand				{}
		-customcommand				{}
		-customfiletypes			{}
		-customicon					{}
		-customtooltip				{}
		-showhidden					{}
	}
	array set opts $args

	if {$opts(-multiple)} { set mode extended } else { set mode single }
	$Vars(widget:list:file) configure -selectmode $mode
	set Vars(selectencodingcommand) {}
	set Vars(fileencodings) {}
	set Vars(initialfile) ""
	set Vars(prevFolder) ""
	set Vars(prevGlob) ""

	set trash $Vars(folder:trash)
	set Vars(folder:trash) ""
	if {$type ne "save"} { set Vars(folder:trash) [::trash::directory] }
	bookmarks::BuildBookmarks $w

	foreach option {	multiple defaultextension defaultencoding filetypes fileicons
							filecursors fileencodings showhidden sizecommand validatecommand
							selectencodingcommand deletecommand renamecommand duplicatecommand
							okcommand cancelcommand inspectcommand filetypecommand mapextcommand
							initialfile checkexistence customcommand customfiletypes customicon
							customtooltip} {
		if {[info exists opts(-$option)]} {
			set Vars($option) $opts(-$option)
		}
	}

	if {[llength $Vars(showhidden)] == 0} {
		set Vars(showhidden) $Options(show:hidden)
	}

	set t $Vars(widget:list:file)
	if {[llength $Vars(inspectcommand)]} {
		bind $t <ButtonPress-2>		[namespace code [list filelist::Inspect $w show %x %y]]
		bind $t <ButtonRelease-2>	[namespace code [list filelist::Inspect $w hide]]
	} else {
		bind $t <ButtonPress-2> {#}
		bind $t <ButtonRelease-2> {#}
	}
	if {[llength $Vars(sizecommand)] == 0} {
		set Vars(sizecommand) [namespace code GetFileSize]
	}
	if {[llength $Vars(validatecommand)] == 0} {
		set Vars(validatecommand) [namespace code ValidateFile]
	}

	# Enable these lines if you want to reset the column ordering
#	$Vars(widget:list:file) column configure $Vars(sort-column) -arrow none
#	set Vars(sort-column) name
#	set Vars(sort-order) increasing

	set Vars(type) $type
	set utype [string toupper $Vars(type) 0 0]
	if {$utype eq "Dir"} { set utype Open }
	tk::SetAmpText $Vars(button:ok) " [Tr $utype]"

	$Vars(widget:list:bookmark) selection clear
	$Vars(widget:list:file) selection clear

	::toolbar::childconfigure $Vars(button:forward) -state disabled
	::toolbar::childconfigure $Vars(button:backward) -state disabled

	if {[llength $Vars(selectencodingcommand)]} {
		set Vars(encodingVar) $Vars(defaultencoding)
		set Vars(encodingDefault) ""
		set Vars(encodingUser) ""
	}

	set Vars(undo:history) {}
	set Vars(undo:current) -1
	set Vars(tip:forward) ""
	set Vars(tip:backward) ""
	set Vars(startup) 1
	if {$type eq "dir"} { set Vars(initialfile) $Vars(folder) }

	filelist::Rebuild $w
	CheckInitialFile $w
	if {[string length $opts(-initialdir)] && $opts(-initialdir) ne $Vars(folder)} {
		if {![file isdirectory $opts(-initialdir)]} { set opts(-initialdir) [pwd] }
		ChangeDir $w $opts(-initialdir)
	} else {
		DirChanged $w 1
	}
	set CurrentPath $w
	SelectInitialFile $w
	changeFileDialogType $w $type
	setFileTypes $w $Vars(filetypes) $Vars(defaultextension)
#	filelist::RefreshFileList $w
	focus $Vars(widget:filename)
}


proc cleanup {w} {
	variable ${w}::Vars

	if {[llength $Vars(fam)]} {
		::fam::close $Vars(fam)
		set Vars(fam) {}
	}
}


proc lookupColor {color} {
	variable ColorLookup

	if {[info exists ColorLookup($color)]} { return $ColorLookup($color) }
	return $color
}

namespace export lookupColor


proc countRows {w} {
	variable ${w}::Vars
	return $Vars(rows:computed)
}


proc useSaveMode {w {flag 1}} {
	variable ${w}::Vars

	set Vars(savemode:value) overwrite

	if {$flag} {
		pack $Vars(button:mode) -pady 5 -padx 5 -fill x -side left
	} else {
		pack forget $Vars(button:mode)
	}

	SetupSaveMode $w
}


proc saveMode {w} {
	return [set [namespace current]::${w}::Vars(savemode:value)]
}


proc changeFileDialogType {w type} {
	variable ${w}::Vars

	set Vars(type) $type

	switch $type {
		dir - open	{ set icon folder }
		save			{ set icon disk }
	}

	$Vars(button:ok) configure -image [set icon::16x16::$icon]
}


proc setFileTypes {w filetypes {defaultextension ""}} {
	variable ${w}::Vars
	variable Options

	set list {}
	set filetypeList {}
	set Vars(onlyexecutables) 0

	foreach entry $filetypes {
		if {[lindex $entry 1] eq "x"} {
			set Vars(onlyexecutables) 1
			set onlyexecutables [lindex $entry 0]
		} else {
			lappend list $entry
			set filetypeList [concat $filetypeList [lindex $entry 1] [lindex $entry 2]]
		}
	}
	set filetypes $list
	set filetypeList [lsort -unique $filetypeList]

	set Vars(defaultextension) $defaultextension
	set Vars(filetypes) $filetypes
	set Vars(extensions) [concat [lindex $filetypes 0 1] [lindex $filetypes 0 2]]

	if {[llength $filetypes] && [string length $Vars(defaultextension)] == 0} {
		set Vars(defaultextension) [lindex $filetypes 0 1 0]
	}

	set fileIconTypes {}
	foreach {extensions name} $Vars(fileicons) {
		foreach ext $extensions {
			if {$ext in $filetypeList && $ext ni $fileIconTypes} {
				lappend fileIconTypes $ext
				set Vars(fti:$ext) $name
			}
		}
	}

	set filetypeCount 0
	set Vars(file:type:list) {}

	foreach entry $filetypes {
		set uppercaseExtensions {}
		lassign $entry name extensions uppercaseExtensions
		set Vars(file:type:list) [concat $Vars(file:type:list) $extensions $uppercaseExtensions]
		set iconList {}
		foreach ext $extensions {
			if {$ext in $fileIconTypes} {
				if {$Vars(fti:$ext) ni $iconList} {
					lappend iconList $Vars(fti:$ext)
				}
			}
		}
		set filetypeCount [max $filetypeCount [llength $iconList]]
	}

	set Vars(file:type:list) [lsort -unique $Vars(file:type:list)]

	set cb $Vars(widget:filetypes:combobox)
	set top [winfo parent $cb]

	$cb showcolumns [list 0 [expr {$filetypeCount + 1}]]
	$cb columns clear

	$cb configure -state readonly
	$cb addcol text -id name -type text
	for {set i 0} {$i < $filetypeCount} {incr i} {
		$cb addcol image -id icon$i -type image
	}
	$cb addcol text -id extensions -type text
	$cb clear

	foreach entry $filetypes {
		lassign $entry name extensions
		set types {}
		set icons {}

		foreach ext $extensions {
			if {[info exists Vars(fti:$ext)]} {
				set img $Vars(fti:$ext)
				if {$img ni $icons} {
					lappend icons $img
				}
			}
			if {[string length $types] > 0} { append types ", " }
			append types "$ext"
		}

		while {[llength $icons] < $filetypeCount} {
			lappend icons {}
		}
		$cb listinsert [list $name {*}$icons $types]
	}
	if {$Vars(onlyexecutables)} {
		$cb listinsert [list $onlyexecutables {} {}]
	}

	if {[llength $filetypes] || $Vars(onlyexecutables)} {
		$cb resize
		SetFileTypes $w 0
	}

	grid $top.lbl_filetype	-row 7 -column 1 -sticky w
	grid $top.ent_filetype	-row 7 -column 3 -sticky ew -columnspan 5
	grid rowconfigure $top {8} -minsize 5
	if {$Options(show:filetypeicons) && [llength $fileIconTypes] > 0} {
		grid $top.ent_filetype -columnspan 3
		grid $top.cnv_filetype -row 7 -column 7 -sticky nsew
		grid columnconfigure $top {6} -minsize 5
	} else {
		grid forget $top.cnv_filetype
		grid configure $top.ent_filetype -columnspan 5
	}

	if {[llength $filetypes] == 0 && !$Vars(onlyexecutables)} {
		$cb configure -state disabled
		grid forget $top.cnv_filetype
		grid configure $top.ent_filetype -columnspan 5
	}

	UpdateFileTypesState $w

	if {[info exists Vars(widget:list:file)]} {
		filelist::RefreshFileList $w
	}
}


proc lastFolder {w} {
	variable ${w}::Vars

	if {[info exists Vars(lastFolder)]} { return $Vars(lastFolder) }
	return ""
}


proc fileSeparator {} {
	if {$::tcl_platform(platform) == "windows"} { return "\\" }
	return "/"
}


proc dirIsEmpty {dir} {
	if {![file isdirectory $dir]} { return 0 }
	return [expr {[llength [glob -nocomplain -tails -dir $dir * .*]] <= 2}]
}


proc validateCharacters {path} {
	variable reservedChars

	if {[string length $path] == 0} { return 1 }
	foreach c [list $path] {
		# windows forbids the use of characters in range 1-31
		if {[string is control $c]} { return 0 }
	}
	# windows forbids the use of some characters
	set pattern *\[[join $reservedChars ""]\]*
	if {[string match $pattern $path]} { return 0 }
	return 1
}


proc validatePath {path} {
	if {[string length $path] == 0} { return 1 }
	# hyphen must not be the first character
	if {[string index $path 0] eq "-"} { return 0 }
	# in windows the space and the period are not allowed as the final character of a filename
	if {[string is space [string index $path end]] || [string index $path end] eq "."} { return 0 }
	return 1
}


proc verifyPath {path} {
	if {$path eq "."} {
		return oneDot
	}
	# we do not allow two or more consecutive dots in filename
	if {[string first ".." $path] >= 0} {
		return twoDots
	}
	if {[string length $path] > 255} { return tooLong }
	# be sure filename is portable (since we support unix, windows and mac)
	if {![validateCharacters $path]} { return reservedChar }
	if {![validatePath $path]} { return invalidName }
	if {[string toupper $path] in { CON PRN AUX CLOCK\$ NUL
			COM0 COM1 COM2 COM3 COM4 COM5 COM6 COM7 COM8 COM9
			LPT0 LPT1 LPT2 LPT3 LPT4 LPT5 LPT6 LPT7 LPT8 LPT9
			\$MFT \$MFTMIRR \$LOGFILE \$VOLUME \$ATTRDEF \$BITMAP
			\$BOOT \$BADCLUS \$SECURE \$UPCASE \$EXTEND \$QUOTA
			\$OBJID \$REPARSE A.OUT CORE .PROFILE .HISTORY .CSHRC}} {
		return reservedName
	}
	return {}
}


proc checkPath {parent path} {
	set message ""
	set detail ""

	switch [verifyPath $path] {
		oneDot {
			set message [format [Tr FilenameNotAllowed] $path]
		}

		twoDots {
			set message [format [Tr FilenameNotAllowed] $path]
			set detail [Tr ContainsTwoDots]
		}

		tooLong {
			set message [format [Tr FilenameNotAllowed] $path]
			set detail [Tr FilenameTooLong]
		}

		reservedChar {
			variable reservedChars
			set message [format [Tr FilenameNotAllowed] $path]
			set detail [format [Tr ContainsReservedChars] [join $reservedChars " "]]
		}

		invalidName {
			set message [format [Tr FilenameNotAllowed] $path]
			set detail [Tr InvalidFileName]
		}

		reservedName {
			set message [format [Tr FilenameNotAllowed] $path]
			set detail [Tr IsReservedName]
		}
	}

	if {[string length $message] == 0} { return 1 }
	::dialog::error -parent $parent -message $message -detail $detail
	return 0
}


proc isWindowsExecutable {path} {
	global tcl_platform

	if {![file executable $path]} { return 0 }
	if {$tcl_platform(platform) eq "windows"} { return 1 }

	set ch [open $path r]
	set magicNumber [read $ch 2]
	close $ch
	if {$magicNumber eq "MZ"} { return 1 }
	return 0
}


proc toUriList {files} {
	set result {}

	foreach file $files {
		if {[::trash::isTrash? $file]} {
			lappend result "trash:///[file tail $file]"
		} else {
			lappend result "file://localhost$file"
		}
	}

	return $result
}


proc parseUriList {uriFiles} {
	set result {}

	# dropped text arrives as it is: one URI per line, not a Tcl list
	if {![string is list $uriFiles]} {
		set uriFiles [split [string map {\r ""} $uriFiles] \n]
	}

	foreach file $uriFiles {
		# according to RFC2-483 lines starting with a '#' are comment lines.
		# should we really discard these lines?
		if {[string length $file]} {
			set uri $file
			if {[string equal -length 5 $file "file:"]} {
				if {[string equal -length 17 $file "file://localhost/"]} {
					# correct implementation
					set file [string range $file 16 end]
				} elseif {[string equal -length 8 $file "file:///"]} {
					# no hostname, but three slashes - nearly correct
					set file [string range $file 7 end]
				} elseif {[string index $file 5] eq "/"} {
					# theoretically, the hostname should be the first, but no one implements it
					set file [string range $uri 5 end]
					for {set n 1} {$n < 5} {incr n} { if {[string index $file $n] eq "/"} { break } }
					set file [string range $uri [expr {$n - 1}] end]
					
					if {![file exists $file]} {
						# perhaps a correct implementation with hostname?
						set i [string first "/" $file 1]
						if {$i >= 0} {
							set f [string range $file $i end]
							if {[file exists $f]} {
								# it seems so
								set file $f
							}
						}
					}
				} else {
					# no slash after "file:" - what is that for a crappy program?
					set file [string range $file 5 end]
				}
				set file [file normalize $file]
			} elseif {[string equal -length 9 $file "trash:/0-"]} {
				# KDE style
				set file [file normalize [file join [::trash::directory] [string range $file 9 end]]]
			} elseif {[string equal -length 8 $file "trash://"]} {
				if {[string equal -length 18 $file "trash://localhost/"]} {
					set file [string range $file 17 end]
				} elseif {[string equal -length 9 $file "trash:///"]} {
					set file [string range $file 9 end]
				} else {
					set file [string range $file 8 end]
				}
				set file [file normalize [file join [::trash::directory] $file]]
			}
			lappend result $uri $file
		}
	}

	return $result
}


proc tooltip {args} {}
proc mc {msg args} { return [::msgcat::mc [set $msg] {*}$args] }
proc busy {w} {}
proc unbusy {w} {}
proc configureRadioEntry {m} { return $m }
proc configureCheckEntry {m} { return $m }
proc mySort {args} { return [lsort {*}$args] }


proc makeStateSpecificIcons {img} {
	return $img ;# XXX how to do?
}


switch [tk windowingsystem] {
	x11	{ proc makeFrameless {w} { ;# XXX how to do this?  } }
	win32	{ proc makeFrameless {w} { wm attributes $w -toolwindow } }
	aqua	{ proc makeFrameless {w} { ::tk::unsupported::MacWindowStyle style $w plain {} } }
}


namespace eval desktop {

switch [tk windowingsystem] {
	x11 {
		proc directory {} {
			set dir [file join [file nativename ~] Desktop]
			if {[file isdirectory $dir]} { return $dir }
			return ""
		}
	}
}

} ;# namespace desktop


proc Tr {tok {args {}}} {
	return [mc [namespace current]::mc::$tok {*}$args]
}

namespace export Tr


proc GetFileSize {file mtime} {
	return [MakeFileSize [file size $file]]
}


proc SetupSaveMode {w} {
	variable ${w}::Vars

	if {$Vars(savemode:value) eq "append"} { set type open } else { set type save }
	changeFileDialogType $w $type
}


proc ValidateFile {file {size {}}} {
	return 1
}


proc CheckInitialFile {w} {
	variable ${w}::Vars

	if {$Vars(type) eq "dir"} {
		if {[string length $Vars(initialfile)] == 0} {
			set Vars(initialfile) [fileSeparator]
		}
	}
}


proc SelectInitialFile {w} {
	variable ${w}::Vars

	if {$Vars(type) eq "dir"} { return }
	if {[string length $Vars(initialfile)] == 0} { return }

	set t $Vars(widget:list:file)
	set i [expr {[llength $Vars(list:folder)] + 1}]
	set sel 0
	foreach entry $Vars(list:file) {
		set file [file tail [lindex $entry 0]]
		if {[EqualPaths $file $Vars(initialfile)]} { set sel $i }
		incr i
	}
	$t selection clear
	$t selection add $sel
	$t activate $sel
	$t see $sel
	filelist::SelectFiles $w [list $sel]
}


proc CheckEncoding {w file} {
	variable ${w}::Vars

	if {[llength $Vars(selectencodingcommand)]} {
		if {[string length $Vars(encodingUser)] == 0} {
			set Vars(encodingVar) $Vars(defaultencoding)
			set file [string tolower $file]

			foreach {ext enable encoding} $Vars(fileencodings) {
				if {[string match *$ext $file]} {
					if {[string length $Vars(encodingVar)] == 0} {
						set Vars(encodingVar) $encoding
					}
					set Vars(encodingDefault) $encoding
				}
			}
		}
	}
}


proc CheckFileEncoding {w} {
	variable ${w}::Vars

	set file $Vars(initialfile)

	if {[llength $file]} {
		if {[string length [file extension $file]] == 0 && [string length $Vars(defaultextension)]} {
			append file $Vars(defaultextension)
		}
		CheckEncoding $w $file
	}
}


proc UpdateFileTypesState {w} {
	variable ${w}::Vars

	set top [winfo parent $Vars(widget:encoding:label)]

	if {[llength $Vars(selectencodingcommand)]} {
		set state disabled
		foreach {ext enable encoding} $Vars(fileencodings) {
			if {$ext in $Vars(extensions) && $enable} { set state normal }
		}
		$Vars(widget:encoding:entry) configure -state $state
		grid $Vars(widget:encoding:label) -row 5 -column 5
		grid $Vars(widget:encoding:entry) -row 5 -column 7
		grid $Vars(widget:filename) -columnspan 1
		grid columnconfigure $top {4} -minsize 10
		grid columnconfigure $top {6} -minsize 5
		grid columnconfigure $top {7} -minsize 0
	} else {
		grid remove $Vars(widget:encoding:label) $Vars(widget:encoding:entry)
		grid $Vars(widget:filename) -columnspan 5
		grid columnconfigure $top {7} -minsize 92
	}
}


proc SelectFileTypes {w combo} {
	variable ${w}::Vars

	set selection [$combo get]
	set i [string last " (" $selection]
	set selection [string range $selection 0 [expr {$i - 1}]]
	set i [lsearch -index 0 -exact $Vars(filetypes) $selection]
	set Vars(extensions) [concat [lindex $Vars(filetypes) $i 1] [lindex $Vars(filetypes) $i 2]]

	UpdateFileTypesState $w
	SetFileTypes $w
	filelist::RefreshFileList $w
}


proc SetFileTypes {w {index -1}} {
	variable ${w}::Vars
	variable Options

	if {$index >= 0} {
		$Vars(widget:filetypes:combobox) current $index
	} else {
		set index [$Vars(widget:filetypes:combobox) current]
	}

	set Vars(defaultextension) [lindex $Vars(filetypes) $index 1 0]

	if {$Options(show:filetypeicons) && [llength $Vars(filetypes)]} {
		set icons {}
		set x 2
		set i 0
		set t $Vars(widget:filetypes:canvas)
		set y -1000

		foreach ext [lindex $Vars(filetypes) $index 1] {
			if {[info exists Vars(fti:$ext)]} {
				set img $Vars(fti:$ext)
				if {$img ni $icons} {
					incr x 2
					if {[llength [$t gettags ft:$i]] == 0} {
						$t create image 0 0 -anchor nw -tag ft:$i
					}
					if {$y == -1000} {
						set y [expr {(([winfo height $t] + 1) - [image height $img])/2}]
					}
					$t coords ft:$i $x $y
					$t itemconfigure ft:$i -image $img -state normal
					if {[llength $Vars(filetypecommand)]} {
						::tooltip::tooltip $t -item ft:$i [{*}$Vars(filetypecommand) $ext]
					}
					lappend icons $img
					incr x [image width $img]
					incr i
				}
			}
		}

		while {[llength [$t gettags ft:$i]] > 0} {
			$t itemconfigure ft:$i -state hidden
			incr i
		}
	}
}


proc SelectEncoding {w} {
	variable ${w}::Vars

	set current $Vars(encodingVar)
	if {[string length $current] == 0} { set current iso8859-1 }
	set encoding [{*}$Vars(selectencodingcommand) $w $current $Vars(encodingDefault)]

	if {[string length $encoding]} {
		set Vars(encodingVar) $encoding
		set Vars(encodingUser) $encoding
	}
}


proc GetHeaderBackground {w} {
	set background [ttk::style lookup $::ttk::currentTheme -background]
	set activebg [ttk::style lookup $::ttk::currentTheme -activebackground]
	if {[llength $activebg] == 0} { set activebg [$w cget -background] }
	set background [list $background {!active} $activebg {active}]
}


proc ThemeChanged {w} {
	variable ${w}::Vars

	set background [ttk::style lookup $::ttk::currentTheme -background]
	set activebg [ttk::style lookup $::ttk::currentTheme -activebackground]
	if {[llength $activebg]== 0} { set activebg [$w cget -background] }

	foreach n {bookmark file} {
		set t $Vars(widget:list:$n)
		foreach id [$t column list] {
			$t column configure $id -background [GetHeaderBackground $w]
		}
	}

	$Vars(widget:panedwindow) configure -background $background
}


proc ConfigurePane {width} {
	variable Options

	set Options(pane:favorites) $width
}


proc VisitItem {w t mode item} {
	if {![winfo exists $w]} { return }
	variable ${w}::Vars

	if {![winfo exists $w]} { return }
	if {$Vars(edit:active)} { return }

	# Note: this function may be invoked with non-existing items
	if {[string length $item]} {
		switch $mode {
			enter {
				foreach i [$t item children root] { $t item state set $i {!hilite} }
				catch { $t item state set $item {hilite} }
			}

			leave { catch { $t item state set $item {!hilite} } }
		}
	}
}


proc SetActiveItem {w item state} {
	variable ::TreeCtrl::Priv
	variable controlMask
	variable shiftMask

	if {[string length $item] == 0} { return  }

	if {[$w cget -selectmode] eq "extended"} {
		if {[expr {$state & $controlMask}]} { ;# Ctrl is held down
			$w activate $item
			$w selection anchor $item
			$w see $item
			if {$item in [$w selection get]} {
				$w selection clear $item
			} else {
				$w selection add $item
			}
			set Priv(selection) ""
			set Priv(prev) ""
		} elseif {[expr {$state & $shiftMask}] && [llength [$w selection get]]} { ;# Shift is held down
			TreeCtrl::DataExtend $w $item
		} else {
			set Priv(prev) ""
			set Priv(selection) ""
			TreeCtrl::SetActiveItem $w $item
		}
	} else {
		set Priv(prev) ""
		set Priv(selection) ""
		TreeCtrl::SetActiveItem $w $item
	}
}


proc ScrollPage {w units} {
	set pages $units
	set active [$w item id active]

	if {$active > 0} {
		if {$pages > 0} {
			if {[lindex [$w yview] 0] == 0} {
				set last [$w item id [list nearest 0 [expr {[winfo height $w] - 1}]]]
				if {$active < $last} { set pages 0 }
			}
		} else {
			if {[lindex [$w yview] 1] == 1} {
				set first [$w item id {nearest 0 0}]
				if {$first < $active} { set pages 0 }
			}
		}
	}

	$w yview scroll $pages pages

	if {$active > 0} {
		if {$units > 0} {
			set activate [$w item id [list nearest 0 [expr {[winfo height $w] - 1}]]]
		} else {
			set activate [$w item id {nearest 0 0}]
		}
		$w activate $activate

		if {[$w cget -selectmode] eq "single"} {
			set selection [$w selection get]

			if {[llength $selection] == 1} {
				set sel [lindex $selection 0]

				if {$active eq $sel} {
					$w selection clear
					$w selection add $activate
				}
			}
		}
	}
}


proc HasFocus {w focus} {
	if {[llength $focus] > 0} {
		while {$focus ne "."} {
			if {$w eq $focus} { return 1 }
			set focus [winfo parent $focus]
		}
	}
	return 0
}


proc AltKeyInDialog {tl path key} {
	if {[HasFocus $tl [focus]]} { tk::AltKeyInDialog $path $key }
}


proc Undo {tl w} {
	if {[HasFocus $tl [focus]]} { filelist::Undo $w }
}


proc Redo {tl w} {
	if {[HasFocus $tl [focus]]} { filelist::Redo $w }
}


proc SbSet {sb first last} {
	if {$first <= 0 && $last >= 1} {
		grid remove $sb
	} elseif {$sb ni [grid slaves [winfo parent $sb]]} {
		grid $sb
	}
	$sb set $first $last
}


proc AddToHistory {w folder} {
	variable ${w}::Vars
	variable bookmarks::Bookmarks
	variable bookmarks::BookmarkSize

	if {[string length $folder] == 0} { return }

	set i [lsearch -exact $Bookmarks(lastvisited) $folder]
	if {$i >= 0} {
		set Bookmarks(lastvisited) [lreplace $Bookmarks(lastvisited) $i $i]
	}
	if {[llength $Bookmarks(lastvisited)] >= $BookmarkSize} {
		set erange [expr {$BookmarkSize - 2}]
		set Bookmarks(lastvisited) [lrange $Bookmarks(lastvisited) 0 $erange]
	}
	set Bookmarks(lastvisited) [linsert $Bookmarks(lastvisited) 0 $folder]

	set i [lsearch -exact -index 0 $Bookmarks(favorites) $folder]
	if {$i == -1} {
		if {[llength $Bookmarks(favorites)] >= $BookmarkSize} {
			set erange [expr {$BookmarkSize - 2}]
			set Bookmarks(favorites) [lrange $Bookmarks(favorites) 0 $erange]
		}
		lappend Bookmarks(favorites) [list $folder 1]
	} else {
		set count [lindex $Bookmarks(favorites) $i 1]
		set Bookmarks(favorites) [lreplace $Bookmarks(favorites) $i $i]
		lappend Bookmarks(favorites) [list $folder [incr count]]
	}
	set Bookmarks(favorites) [lsort -index 1 -decreasing -integer $Bookmarks(favorites)]
}


proc DirChanged {w {useHistory 1}} {
	variable ${w}::Vars
	variable bookmarks::Bookmarks
	variable HaveFAM

	if {$HaveFAM && [llength $Vars(fam)] == 0} {
		set Vars(fam) [namespace current]::FAMHandler
		set Vars(fam:lastid) 0
		set Vars(fam:currentid) 0
		if {[catch { ::fam::open $Vars(fam) } Vars(fam) err]} {
			array set opts $err
			puts stderr "'fam::open failed: $opts(-errorinfo)"
			set HaveFAM 0
		} elseif {[string length $Vars(fam)] == 0} {
			set HaveFAM 0
		} elseif {$::tcl_platform(platform) eq "unix" && [file isdirectory /media]} {
			catch { ::fam::add $Vars(fam) /media }
		}
		if {!$HaveFAM} { set Vars(fam) {} }
	}
	if {[llength $Vars(fam)] && [string length $Vars(prevFolder)]} {
		if {[catch { ::fam::remove $Vars(fam) [file normalize $Vars(prevFolder)] } _ err]} {
			array set opts $err
			puts stderr "'fam::remove' failed: $opts(-errorinfo)"
		}
	}
	if {[llength $Vars(fam)] && [string length $Vars(folder)]} {
		if {[file isdirectory $Vars(folder)]} {
			if {[catch { ::fam::add $Vars(fam) [file normalize $Vars(folder)] } _ err]} {
				array set opts $err
				puts stderr "'fam::add' failed: $opts(-errorinfo)"
			}
		}
	}

	set Vars(history:folder) ""
	if {$Vars(glob) eq "Files"} { set folder $Vars(folder) } else { set folder $Vars(glob) }

	if {$useHistory} {
		set Vars(undo:history) [lrange $Vars(undo:history) 0 $Vars(undo:current)]
		set Vars(undo:current) [llength $Vars(undo:history)]
		lappend Vars(undo:history) $folder
		if {[llength $Vars(undo:history)] > 1} {
			filelist::SetTooltip $w Backward [lindex $Vars(undo:history) [expr {$Vars(undo:current) - 1}]]
			::toolbar::childconfigure $Vars(button:backward) -state normal -tooltip $Vars(tip:backward)
		}
		::toolbar::childconfigure $Vars(button:forward) -state disabled
		set Vars(tip:forward) ""
		if {$Vars(glob) eq "Files" && $folder ne [fileSeparator]} {
			set Vars(history:folder) $folder
		}
	}

	bookmarks::UpdateButtons $w
	if {$Vars(glob) eq "Trash"} { set action restore } else { set action delete }
	filelist::SetDeleteAction $w $action
	filelist::ConfigureButtons $w

	if {[namespace exists ::tkdnd]} {
		if {[string length $Vars(folder)]} {
			RegisterDndEvents $w
		} else {
			UnregisterDndEvents $w
		}
	}
}


proc FAMHandler {id action path} {
	set w [set [namespace current]::CurrentPath]
	if {![winfo exists $w]} { return }
	variable ${w}::Vars

	set Vars(fam:currentid) $id

	if {[string match /media/* $path]} {
		if {$action ne "deleted"} {
			after 1000 [namespace code [list bookmarks::BuildBookmarks $w]]
		}

		if {$action eq "umount" && [string match $path* $Vars(folder)]} {
			after idle [namespace code [list ChangeDir $w $Vars(folder:home) no]]
			return
		}
	}

	# deletion events are triggered twice (bug in libfam?)
	if {$id ne $Vars(fam:lastid)} {
		set Vars(fam:lastid) $id
		if {[string match $Vars(folder)* $path]} {
			after idle [namespace code [list filelist::RefreshFileList $w]]
		}
	}
}


proc GetStartMenu {w} {
	variable ${w}::Vars
	variable bookmarks::Bookmarks

	foreach folder {Favorites LastVisited} {
		lappend start $Vars(icon:[string tolower $folder]) [Tr $folder] $folder
	}
	lappend start "" "" ""
	foreach folder [GetFolders $w] {
		set id [string tolower $folder]
		if {[llength $Vars(folder:$id)]} {
			set text $folder
			catch { set text [Tr $folder] }
			lappend start $Vars(icon:$id) $text $Vars(folder:$id)
		}
	}
	if {[llength $Bookmarks(user)]} {
		lappend start "" "" ""
		foreach entry $Bookmarks(user) {
			lassign $entry folder name
			if {[file isdirectory $folder]} {
				lappend start $icon::16x16::folder $name $folder
			}
		}
	}
	$Vars(choosedir) setstartmenu $start
}


proc GetFolders {w} {
	variable ${w}::Vars

	lappend folders FileSystem
	set Vars(usb-devices) {}

	switch [tk windowingsystem] {
		x11 {
			set gdbus [auto_execok gdbus]
			if {[string length $gdbus] > 0} {
				set result ""
				catch {
					set result [exec -ignorestderr $gdbus introspect \
						--system \
						--dest org.freedesktop.UDisks \
						--object-path /org/freedesktop/UDisks/devices \
						--recurse \
						--only-properties \
					]}
				lassign {0 0 "" {}} usb fs id paths
				foreach line [split $result \n] {
					set line [string trim $line]
					if {[string index $line 0] eq "\}"} {
						if {$usb && $fs && [string length $id] > 0 && [llength $paths] > 0} {
							set path ""
							foreach p $paths {
								set p [string range $p 1 end-1]
								if {[file readable $p]} {
									if {[string match {/media/*} $p] || [string length $path] == 0} {
										set path $p
									}
								}
							}
							if {[string length $path] > 0} {
								lappend folders $id
								lappend Vars(usb-devices) $id
								set id [string tolower $id]
								set Vars(folder:$id) $path
								set Vars(icon:$id) $icon::16x16::usb
								set Vars(lookup:$path) usb
								lappend Vars(folders) $path
							}
						}
						lassign {0 0 "" {}} usb fs id paths
					} elseif {[string match {* DriveConnectionInterface = 'usb';} $line]} {
						set usb 1
					} elseif {[string match {* IdUsage = 'filesystem';} $line]} {
						set fs 1
					} elseif {[string match {* IdLabel *} $line]} {
						set id [string range [lindex $line 4] 1 end-2]
					} elseif {[string match {* DeviceMountPaths *} $line]} {
						set paths [string range [lindex $line 4] 1 end-2]
					}
				}
			}
		}
		win32 {
			foreach drive [file volumes] {
				if {![string match c:* $drive]} {
					set name [string range $drive 0 1]
					set id [string tolower $name]
					set Vars(folder:$id) $drive
					set Vars(icon:$id) $Vars(folder:filesystem) 
					lappend folders $name
				}
			}
		}
		aqua {
			# TODO
		}
	}

	lappend folders Desktop Trash Download Home
	return $folders
}


proc ChooseDir {w folder path} {
	variable ${w}::Vars

	set sep [fileSeparator]
	if {[string match $Vars(folder:home)$sep* $folder$sep]} {
		set basename [Tr Home]
		set where home
	} else {
		set basename [Tr FileSystem]
		if {[info exists Vars(lookup:$path)]} { set where $path } else { set where filesystem }
		foreach name $Vars(usb-devices) {
			set id [string tolower $name]
			if {[string match $Vars(folder:$id)$sep* "$path$sep"]} {
				set basename $name
				set where $id
				break
			}
		}
	}

	if {![info exists Vars(folder:$where)]} { set where filesystem }
	set prefix $Vars(folder:$where)
	set icon [set icon::16x16::$Vars(lookup:$prefix)]
	$Vars(choosedir) set $Vars(folder) $basename $icon $prefix
}


proc ChangeDir {w path {useHistory 1}} {
	variable ${w}::Vars

	if {[file pathtype $path] eq "absolute"} {
		if {[catch {glob -nocomplain -directory $path -types d .*} result err]} {
			set msg [format [Tr PermissionDenied] $path]
			::dialog::error -parent $Vars(widget:main) -message $msg
			return
		}
	}

	set Vars(prevFolder) $Vars(folder)
	set Vars(prevGlob) $Vars(glob)

	foreach f {Desktop Trash Download} {
		if {$Vars(folder:[string tolower $f]) eq $path} {
			set path $f
		}
	}

	$Vars(choosedir) tooltip ""

	switch $path {
		Favorites - LastVisited {
			set Vars(glob) $path
			set Vars(folder) {}
			$Vars(choosedir) setfolder $path [Tr $path] $Vars(icon:[string tolower $path])
		}

		Desktop - Trash - Download {
			set Vars(glob) $path
			set Vars(folder) $Vars(folder:[string tolower $path])
			$Vars(choosedir) setfolder $path [Tr $path] $Vars(icon:[string tolower $path])
		}

		default {
			set Vars(glob) Files
			set appPWD [pwd]
			if {[string length $path] == 0} { set path $appPWD }

			if {[catch {cd $path}]} {
				if {[file isdirectory $path]} {
					set message [Tr CannotChangeDir $path]
				} else {
					set message [Tr DirectoryRemoved $path]
				}
				set Vars(folder) $appPWD
				ChooseDir $w $Vars(folder) $path
				::dialog::warning -parent $Vars(widget:main) -message $message -buttons {ok}
				if {![file isdirectory $path]} { filelist::RefreshFileList $w }
				return
			}

			set pwd [pwd]
			if {[file normalize $path] eq $pwd} { set Vars(folder) $path } else { set Vars(folder) $pwd }
			cd $appPWD
			ChooseDir $w $Vars(folder) $path
			set Vars(lastFolder) $Vars(folder)
		}
	}

	if {$Vars(type) eq "dir" && [EqualPaths $Vars(initialfile) $path]} {
		set Vars(initialfile) $path
	}

	$Vars(widget:list:file) item delete all
	filelist::Glob $w yes
	if {$Vars(prevFolder) ne $Vars(folder) || $Vars(prevGlob) ne $Vars(glob)} {
		DirChanged $w $useHistory
	}
}


proc EqualPaths {dir1 dir2} {
	if {$dir1 ne "Favorites" && $dir1 ne "LastVisited"} {
		set dir1 [file normalize $dir1]
	}
	if {$dir2 ne "Favorites" && $dir2 ne "LastVisited"} {
		set dir2 [file normalize $dir2]
	}
	return [expr {$dir1 eq $dir2}]
}


proc FocusIn {w} {
	if {[string length [$w get]] > 0} {
		$w selection range 0 end
		$w icursor end
	} else {
		$w selection clear
	}
}


proc FocusOut {w} {
	$w selection clear
}


proc InvokeOk {w} {
	if {[$w cget -state] eq "normal"} {
		$w invoke
	}
}


proc Cancel {w} {
	variable ${w}::Vars

	if {[llength $Vars(cancelcommand)]} {
		{*}$Vars(cancelcommand)
	}
}


proc Activate {w {exit no}} {
	variable ${w}::Vars

	switch $Vars(glob) {
		Desktop - Trash - Files { set complete Join }
		Favorites	{ set complete SearchFavorite }
		LastVisited	{ set complete SearchLastVisited }
	}

	set files {}
	set selected {}

	if {$Vars(multiple)} {
		set even 0
		foreach list [string trim [split $Vars(initialfile) \"]] {
			if {$even} { set list [list $list] }
			set even [expr {1 - $even}]
			foreach file $list {
				if {[string length $file]} {
					if {$Vars(type) eq "save"} {
						set fullname $file
						if {[string length $Vars(defaultextension)]} {
							append fullname $Vars(defaultextension)
						}
						if {![CheckPath $w $fullname]} { return }
					}
					lappend selected [[namespace current]::$complete $w $file]
				}
			}
		}
	} else {
		set file [string trim $Vars(initialfile)]
		if {[string length $file]} {
			if {$Vars(type) eq "save"} {
				set fullname $file
				if {[string length $Vars(defaultextension)]} { append fullname $Vars(defaultextension) }
				if {![CheckPath $w $fullname]} { return }
			}
			lappend selected [[namespace current]::$complete $w $file]
		}
	}

	if {[llength $selected] == 0} { return }
	AddToHistory $w $Vars(history:folder)

	foreach file $selected {
		if {[lindex [file split $file] 0] ne [fileSeparator]} {
			set msg [format [Tr CannotOpenOrCreate] $file]
			::dialog::error -parent $Vars(widget:main) -message $msg
			return
		}
	}

	foreach file $selected {
		if {[llength $Vars(filetypes)]} {
			if {[string length [file extension $file]]} {
				if {$Vars(type) eq "save"} {
					set found 0
					foreach entry $Vars(filetypes) {
						foreach ext [lindex $entry 1] {
							if {[string match *$ext $file]} {
								set found 1
							}
						}
					}
					if {!$found} {
						set msg [format [Tr InvalidFileExtension] [file tail $file]]
						::dialog::error -parent $Vars(widget:main) -message $msg
						return
					}
				}
			} elseif {[string length $Vars(defaultextension)]} {
				append file $Vars(defaultextension)
			} else {
				set msg [format [Tr MissingFileExtension] [file tail $file]]
				::dialog::error -parent $Vars(widget:main) -message $msg
				return
			}
		}
		lappend files $file
	}

	switch $Vars(type) {
		dir {
			if {$Vars(checkexistence)} {
				foreach dir $files {
					if {![file isdirectory $dir]} {
						set msg [format [Tr DirectoryDoesNotExist] [file tail $file]]
						::dialog::error -parent $Vars(widget:main) -message $msg
						return
					}
				}
			}
		}

		open {
			if {$Vars(checkexistence)} {
				foreach file $files {
					if {![file exists $file]} {
						set msg [format [Tr FileDoesNotExist] [file tail $file]]
						::dialog::error -parent $Vars(widget:main) -message $msg
						filelist::RefreshFileList $w
						return
					}
				}
			}
		}

		save {
			foreach file $files {
				if {[file isdirectory $file]} {
					set msg [format [Tr CannotOverwriteDirectory] [file tail $file]]
					::dialog::error -parent $Vars(widget:main) -message $msg
					return
				}
				if {[CheckIfInUse $w $file overwrite]} { return }
				if {$Vars(checkexistence)} {
					if {[file exists $file]} {
						set msg [format [Tr FileAlreadyExists] [file tail $file]]
						set reply [::dialog::question -parent $Vars(widget:main) -message $msg]
						if {$reply ne "yes"} { return }
					}
				}
			}
		}
	}

	if {$exit} {
		if {[llength $Vars(okcommand)]} {
			if {!$Vars(multiple)} { set files [lindex $files 0] }
			if {[llength $Vars(selectencodingcommand)]} {
				{*}$Vars(okcommand) $files $Vars(encodingVar)
			} else {
				{*}$Vars(okcommand) $files
			}
		}
	} elseif {$Vars(type) eq "dir" && [llength $files]} {
		ChangeDir $w [lindex $files 0]
	}
}


proc Join {w filename} {
	variable ${w}::Vars
	return [file join $Vars(folder) $filename]
}


proc SearchFavorite {w dir} {
	variable bookmarks::Bookmarks

	foreach entry $Bookmarks(favorites) {
		set d [lindex $entry 0]
		if {[file tail $d] eq $dir} {
			return $d
		}
	}

	return $dir
}


proc SearchLastVisited {w dir} {
	variable bookmarks::Bookmarks

	foreach entry $Bookmarks(lastvisited) {
		set d [lindex $entry 0]
		if {[file tail $d] eq $dir} {
			return $d
		}
	}

	return $dir
}


proc CheckPath {w path} {
	variable ${w}::Vars
	return [checkPath $Vars(widget:main) $path]
}


proc Stimulate {w} {
	if {![winfo exists $w]} { return }
	variable ${w}::Vars

	if {![winfo exists $w]} { return }
	set Vars(edit:active) 0

	foreach type {bookmark file} {
		set t $Vars(widget:list:$type)
		foreach item [$t item children root] { $t item state set $item {!hilite} }
		set x [expr {[winfo pointerx .] - [winfo rootx $t]}]
		set y [expr {[winfo pointery .] - [winfo rooty $t]}]
		set id [$t identify $x $y]
		if {[llength $id] == 0} { return }
		lassign $id what item

		if {$what eq "item"} {
			$t item state set $item {hilite}
		}
	}
}


proc CheckIfInUse {w file mode {deferDialog 0}} {
	variable ${w}::Vars

	if {[llength $Vars(isusedcommand)] > 0 && [$Vars(isusedcommand) [file normalize $file]]} {
		set msg [format [Tr Cannot($mode)] [file tail $file]]
		set detail [Tr CurrentlyInUse]
		set cmd [list ::dialog::info -parent $Vars(widget:main) -message $msg -detail $detail]
		if {$deferDialog} { after idle $cmd } else { {*}$cmd }
		return 1
	}
	return 0
}


proc MakeFileSize {size} {
	set unit Byte
	if {$size >= 1000000000} {
		set size [expr {($size + 500000000)/1000000000}]
		set unit GB
	} elseif {$size >= 1000000} {
		set size [expr {($size + 500000)/1000000}]
		set unit MB
	} elseif {$size >= 1000} {
		set size [expr {($size + 500)/1000}]
		set unit KB
	}
	return "$size $unit"
}


proc RegisterDndEvents {w} {
	variable ${w}::Vars

	if {![winfo ismapped $w]} {
		return [bind $w <Map> [namespace code [list DoRegisterDndEvents $w]]]
	}

	set t $Vars(widget:list:file)

	::tkdnd::drop_target register $t DND_Files
	::tkdnd::drag_source register $t DND_Files
	bind $t <<DropEnter>> [namespace code [list filelist::HandleDropEvent $w enter %t %a]]
	bind $t <<DropLeave>> [namespace code [list filelist::HandleDropEvent $w leave %t %a]]
	bind $t <<Drop>> [namespace code [list filelist::HandleDropEvent $w %D %t %a]]
	bind $t <<DragInitCmd>> [namespace code [list filelist::HandleDragEvent $w %W %t %X %Y]]
	bind $t <<DragDropCmd>> [namespace code [list filelist::HandleDragDropgEvent $w %W %A]]
	bind $t <<DragEndCmd>> [namespace code [list filelist::FinishDragEvent $w %W %A]]

	set t $Vars(widget:list:bookmark)

	::tkdnd::drop_target register $t DND_Files
	bind $t <<DropEnter>> [namespace code [list bookmarks::HandleDropEvent $w enter %t %a %X %Y]]
	bind $t <<DropPosition>> [namespace code [list bookmarks::HandleDropEvent $w position %t %a %X %Y]]
	bind $t <<DropLeave>> [namespace code [list bookmarks::HandleDropEvent $w leave %t %a]]
	bind $t <<Drop>> [namespace code [list bookmarks::HandleDropEvent $w %D %t %a]]
}


proc DoRegisterDndEvents {w} {
	bind $w <Map> {#}
	RegisterDndEvents $w
}


proc UnregisterDndEvents {w} {
	variable ${w}::Vars

	set t $Vars(widget:list:file)
	::tkdnd::drop_target unregister $t DND_Files
	::tkdnd::drag_source unregister $t DND_Files

	set t $Vars(widget:list:file)
	::tkdnd::drop_target unregister $t DND_Files
}


proc AskAboutAction {w destination uriFiles actions} {
	variable ${w}::Vars

	set m $w.askAboutAction
	catch { destroy $m }
	menu $m -tearoff 0

	set trash 0
	set dir 0
	set normal 0
	foreach uri $uriFiles {
		if {[string match trash:* $uri]} { incr trash } else { incr normal }
	}

	if {$trash > 0 && $normal > 0} {
		set myActions {copy}
	} elseif {$trash > 0} {
		set myActions {restore copy}
	} else {
		foreach action {move copy link} {
			if {$action in $actions} { lappend myActions $action }
		}
		if {[llength $myActions] == 0} {
			set myActions {copy link}
		}
	}

	foreach action $myActions {
		if {$action in $myActions} {
			$m add command \
				-label " [Tr DropAction($action)]" \
				-image $icon::16x16::action($action) \
				-compound left \
				-command [list set [namespace current]::action_ $action] \
				;
		}
	}
	$m add separator
	$m add command \
		-label " [string map {& {}} [Tr Cancel]]" \
		-image $filelist::icon::16x16::delete \
		-compound left \
			-command [list set [namespace current]::action_ refuse_drop] \
		;

	variable action_
	set action_ ""
	bind $m <<MenuUnpost>> [list set [namespace current]::action_ refuse_drop]
	tk_popup $m {*}[winfo pointerxy $w]
	vwait [namespace current]::action_

	if {$action_ ne "refuse_drop"} {
		# It is important that HandleDropEvent is returning as fast as possible.
		if {$Vars(drag:active) && $Vars(drag:trash)} { set trash 1 } else { set trash 0 }
		after idle [namespace code [list DoFileOperations $w $action_ $uriFiles $destination $trash]]
	}

	return $action_
}


proc DoFileOperations {w action uriFiles destination trash} {
	if {![winfo exists $w]} { return }
	variable ${w}::Vars

	if {![winfo exists $w]} { return }

	set errorList {}
	set rejectList {}
	set acceptList {}
	set remoteList {}
	set trashList {}
	set dirList {}

	foreach {uri file} [parseUriList $uriFiles] {
		if {[string equal -length 6 $uri "trash:"]} {
			if {$action ni {copy restore}} {
				lappend trashList $uri
			} elseif {![file exists $file]} {
				# This shouldn't happen.
				lappend errorList $uri
			} else {
				lappend acceptList $file
			}
		} elseif {[file isdirectory $file]} {
			lappend dirList $file
		} elseif {[file exists $file]} {
			lappend acceptList $file
		} elseif {	[string equal -length 5 $uri "http:"]
					|| [string equal -length 4 $uri "https:"]
					|| [string equal -length 4 $uri "ftp:"]} {
			lappend remoteList $uri
		} elseif {$uri ni $errorList} {
			# This shouldn't happen.
			lappend errorList $uri
		}
	}

	set databaseList {}

	foreach file $acceptList {
		set origExt [file extension $file]
		set mappedExt $origExt

		if {[string length $Vars(mapextcommand)]} {
			set mappedExt [$Vars(mapextcommand) $origExt]
		}

		set valid 0
		if {$mappedExt in $Vars(file:type:list)} {
			set valid 1
		} else {
			foreach ext $Vars(file:type:list) {
				if {[string match *$ext $file]} { set valid 1 }
			}
		}

		if {$valid} {
			if {$origExt ne $mappedExt} {
				set f [file rootname $file]
				append f $mappedExt
				if {[file exists $f]} {
					set file $f
				} else {
					set valid 0
					if {$file ni $rejectList} { lappend rejectList $file }
				}
			}
			if {$valid && $file ni $databaseList} {
				lappend databaseList $file
			}
		} elseif {$file ni $rejectList} {
			lappend rejectList $file
		}
	}

	if {[llength $errorList]} {
		set options {}
		if {[string match file:* $uriFiles] && [llength $databaseList] == 0} {
			set message [Tr CannotOpenUri]
			append message <embed>
			lappend options -embed [namespace code [list EmbedFileList $errorList no]]
		} else {
			set message [Tr InvalidUri]
			append message "\n\n"
		}
		append message [Tr OperationAborted]
		return [::dialog::error -parent $w -message $message {*}$options]
	}

#  ###### This cannot happen ##################
#	if {[llength $trashList]} {
#		set message [Tr OperationNotPermitted]
#		append message <embed>
#		append message [Tr OperationAborted]
#		return [::dialog::error \
#			-parent $w \
#			-message $message \
#			-embed [namespace code [list EmbedFileList $trashList no]]
#		]
#	}

	if {[llength $rejectList]} {
		set message [Tr UriRejected]
		append message <embed>
		append message [Tr OperationAborted]
		return [::dialog::error \
			-parent $w \
			-message $message \
			-detail [Tr UriRejectedDetail] \
			-embed [namespace code [list EmbedFileList $rejectList no]]
		]
	}

	if {[llength $remoteList]} {
		set message [Tr UriRejected]
		append message <embed>
		append message [Tr OperationAborted]
		return [::dialog::error \
			-parent $w \
			-message $message \
			-detail [Tr CannotOpenRemoteFiles] \
			-embed [namespace code [list EmbedFileList $remoteList no]]
		]
	}

	if {[llength $dirList]} {
		switch $action {
			copy {
				set message [Tr CannotCopyFolders]
				append message <embed>
				append message [Tr OperationAborted]
				return [::dialog::error \
					-parent $w \
					-message $message \
					-embed [namespace code [list EmbedFileList $dirList no]]
				]
			}
			default {
				set message [Tr ApplyOnDirectories]
				append message <embed>
				set reply [dialog::question \
					-parent $w \
					-message $message \
					-embed [namespace code [list EmbedFileList $dirList yes]]
				]
				if {$reply eq "no"} { set dirList {} }
			}
		}
	}

	set fileList {}

	foreach file [concat $databaseList $dirList] {
		if {$trash} {
			set i [lsearch -index 0 $Vars(list:file) $file]
			set dst [file join $destination [file tail [lindex $Vars(list:file) $i 1]]]
		} elseif {[::trash::isTrash? $file]} {
			set dst [::trash::originalPath [file tail $file]]
			set dst [file join $Vars(folder) [file tail $dst]]
		} else {
			set dst [file join $destination [file tail $file]]
		}

		if {[string length $dst] > 0} {
			set dst [file normalize $dst]

			if {$dst ne $file} {
				set op overwrite
				if {[file exists $dst]} { lassign [AskFileAction $w $file $dst] op newName }
				if {$op ne "cancel"} {
					if {$op eq "rename"} { set dst $newName }
					lappend fileList $file $dst
				}
			}
		}
	}

	if {[llength $fileList] == 0} { return }
	set refresh 0

	foreach {src dst} $fileList {
		set deletionList {}
		if {[file exists $dst]} {
			if {[llength $Vars(deletecommand)]} {
				foreach f [{*}$Vars(deletecommand) $w $dst] { lappend deletionList $f }
			} else {
				lappend deletionList $f
			}
		}
		if {[llength $Vars(duplicatecommand)]} {
			set list [$Vars(duplicatecommand) $src $dst]
		} else {
			set list [list $src $dst]
		}
		foreach {src dst} $list {
			if {[file exists $src]} {
				set i [lsearch $deletionList $dst]
				if {$i >= 0} {
					catch { file delete $dst }
					set deletionList [lreplace $deletionList $i $i]
				}
				set permissionDenied 0
				switch $action {
					move {
						if {[catch { file rename -force $src $dst }]} {
							set permissionDenied 1
						}
					}
					copy {
						while {[file type $src] eq "link"} { set src [file readlink $src] }
						if {[catch { file copy -force $src $dst }]} {
							set permissionDenied 1
						} else {
							catch { ::platform::sys::touch $dst }
						}
					}
					link {
						if {[catch { file link -symbolic $dst $src }]} {
							set permissionDenied 1
						}
					}
					restore {
						switch [::trash::restore $src $dst -force 1] {
							nopermission { set permissionDenied 1 }
						}
					}
				}
				if {$permissionDenied} {
					set msg [format [Tr PermissionDenied] [file dirname $dst]]
					::dialog::error -parent $Vars(widget:main) -message $msg
					return
				}
				set refresh 1
			}
		}
		foreach f $deletionList { catch { file delete $f } }
	}

	if {$refresh} { filelist::RefreshFileList $w }
}


proc EmbedFileList {fileList isdir w infoFont alertFont} {
	set row 0
	foreach file $fileList {
		if {$isdir} {
			append file [file separator]
		} else {
			set file [file tail $file]
		}
		set font TkFixedFont
		grid [tk::label $w.l$row -text $file -font $font] -column 1 -row $row -sticky w
		if {[incr row] == 10} {
			grid [tk::label $w.l$row -text "..." -font $font] -column 1 -row $row -sticky w
			break
		}
	}
	grid columnconfigure $w {0} -minsize 15
}


proc AskFileAction {w old new} {
	variable ${w}::Vars
	variable action_
	variable newName_

	set rootname [file tail $new]
	set extension ""
	foreach ext $Vars(file:type:list) {
		if {[string match *$ext $rootname]} { set extension $ext }
	}

	set action_ ""
	set newName_ [string range $rootname 0 end-[string length $extension]]

	set srcDir [file dirname $old]
	if {[string length $srcDir] > 40} {
		append f [string range $srcDir 0 8] "..." [string range $srcDir end-32 end]
		set srcDir $f
	}

	if {[file isdirectory $old]} {
		set icon $icon::16x16::folder
	} else {
		set ext [::util::fileExtension $new]
		if {[info exists Vars(fti:$ext)]} {
			set icon $Vars(fti:$ext)
		} else {
			set icon $icon::16x16::document
		}
	}

	set oldTime [file mtime $old]
	set newTime [file mtime $new]
	if {[string length $Vars(formattimecmd)]} {
		set oldTime [$Vars(formattimecmd) $oldTime]
		set newTime [$Vars(formattimecmd) $newTime]
	} else {
		set oldTime [clock format $oldTime]
		set newTime [clock format $newTime]
	}

	append oldInfo "[Tr Size]: [MakeFileSize [file size $old]]"
	append oldInfo " - "
	append oldInfo "[Tr Modified]: $oldTime"

	append newInfo "[Tr Size] [MakeFileSize [file size $new]]"
	append newInfo " - "
	append newInfo "[Tr Modified]: $newTime"

	set dlg [tk::toplevel $w.askFileAction -class FSBoxDialog]
	set top [ttk::frame $dlg.top -borderwidth 0 -takefocus 0]
	bind $dlg <Alt-Key> [namespace code [list tk::AltKeyInDialog $dlg %A]]
	wm withdraw $dlg

	ttk::label $top.oldName -text [format [Tr AnEntryAlreadyExists] [file tail $new]]
	ttk::label $top.oldAttrs -image $icon -compound left -text $oldInfo
	ttk::label $top.newName -text [format [Tr SourceDirectoryIs] $srcDir]
	ttk::label $top.newAttrs -image $icon -compound left -text $newInfo
	set ren [ttk::frame $top.rename -takefocus 0 -borderwidth 0]
	ttk::label $ren.label -text "[Tr NewName]:"
	ttk::entry $ren.entry -textvar [namespace current]::newName_
	bind $ren.entry <FocusIn> [list $ren.entry selection range 0 end]
	bind $ren.entry <FocusOut> [list $ren.entry selection clear]
	grid $ren.label -row 0 -column 1 -sticky w
	grid $ren.entry -row 0 -column 3 -sticky we
	grid columnconfigure $ren {2} -minsize 5
	grid columnconfigure $ren {3} -weight 1

	grid $top.oldName  -row 1 -column 1 -sticky w -columnspan 2
	grid $top.oldAttrs -row 3 -column 1 -sticky w
	grid $top.newName  -row 5 -column 1 -sticky w -columnspan 2
	grid $top.newAttrs -row 7 -column 1 -sticky w
	grid $top.rename   -row 9 -column 1 -sticky ew -columnspan 2
	grid columnconfigure $top {0 3} -minsize 5
	grid columnconfigure $top {1} -minsize 10
	grid rowconfigure $top {0 2 6 10} -minsize 5
	grid rowconfigure $top {4 8} -minsize 15

	ttk::separator $dlg.sep
	set buttons [tk::frame $dlg.buttons -takefocus 0]

	tk::AmpWidget ttk::button $buttons.rename  \
		-class TButton \
		-default normal \
		-compound left \
		-text " [Tr Rename]" \
		-command [namespace code [list ActionRename $w [file dirname $new] $extension]] \
		;
	if {[llength $Vars(isusedcommand)] > 0 && ![$Vars(isusedcommand) $new]} {
		tk::AmpWidget ttk::button $buttons.overwrite  \
			-class TButton \
			-default normal \
			-compound left \
			-text " [Tr Overwrite]" \
			-command [namespace code [list ActionOverwrite $w $new]] \
			;
	}
	tk::AmpWidget ttk::button $buttons.cancel  \
		-class TButton \
		-default normal \
		-compound left \
		-text " [Tr Cancel]" \
		-command [list set [namespace current]::action_ cancel] \
		;

	pack $buttons.rename -pady 5 -padx 5 -side left
	if {[winfo exists $buttons.overwrite]} {
		pack $buttons.overwrite -pady 5 -padx 5 -side left
	}
	pack $buttons.cancel -pady 5 -padx 5 -side left

	pack $top -fill x
	pack $dlg.sep -fill x -side bottom -before $top
	pack $buttons -side bottom -before $dlg.sep

	wm protocol $dlg WM_DELETE_WINDOW [list set [namespace current]::action_ cancel]
	wm title $dlg [Tr EntryAlreadyExists]
	wm transient $dlg [winfo toplevel $w]
	::ttk::grabWindow $dlg
	::util::place $dlg -parent $w -position center
	wm deiconify $dlg
	focus -force $ren.entry
	vwait [namespace current]::action_
	::ttk::releaseGrab $dlg
	destroy $dlg
	return [list $action_ [file join [file dirname $new] ${newName_}${extension}]]
}


proc ActionRename {w dstDir extension} {
	variable action_
	variable newName_

	set newName [file join $dstDir ${newName_}${extension}]

	if {[file exists $newName]} {
		::dialog::error -parent $w -message [format [Tr CannotRename] [file tail $newName]]
	} else {
		set action_ rename
	}
}


proc ActionOverwrite {w file} {
	variable action_
	if {![CheckIfInUse $w $file overwrite]} { set action_ overwrite }
}

###### B O O K M A R K S ######################################################

namespace eval bookmarks {

array set Bookmarks {
	favorites	{}
	lastvisited	{}
	user			{}
}

set BookmarkSize 15

namespace import [namespace parent]::Tr
namespace import [namespace parent]::lookupColor


proc Build {w path args} {
	variable [namespace parent]::${w}::Vars
	variable [namespace parent]::Options
	variable Bookmarks

	if {![info exists [namespace current]::icon::16x16::iconAdd]} {
		foreach {icon img} {Add plus Minus minus Modify modify} {
			set [namespace current]::icon::16x16::icon$icon \
				[list [[namespace parent]::makeStateSpecificIcons \
					[set [namespace current]::icon::16x16::$img]]]
		}
	}

	set opts(-selectmode) single
	array set opts $args
	array unset opts -rows

	set linespace [font metrics $Vars(font) -linespace]
	if {$linespace < 20} { set linespace 20 }

	::tk::frame $path -borderwidth 0 -takefocus 0 -width $Options(pane:favorites)
	pack propagate $path 0

	::toolbar::setup $path -id fsbox-bookmarks
	set tb [::toolbar::toolbar $path -id fsbox:bookmarks -hide 0 -side bottom]

	set Vars(button:add) [::toolbar::add $tb button    \
		-image $icon::16x16::iconAdd                    \
		-command [namespace code [list AddBookmark $w]] \
		-state disabled                                 \
	]
	set Vars(button:minus) [::toolbar::add $tb button     \
		-image $icon::16x16::iconMinus                     \
		-command [namespace code [list RemoveBookmark $w]] \
		-state disabled                                    \
	]
	::toolbar::add $tb separator
	set Vars(button:modify) [::toolbar::add $tb button    \
		-image $icon::16x16::iconModify                    \
		-command [namespace code [list RenameBookmark $w]] \
		-state disabled                                    \
	]
	
	tk::frame $path.f -borderwidth 0 -takefocus 0
	pack $path.f -fill both -expand yes

	set t $path.f.list
	set sb $path.f.vscroll
	set Vars(widget:list:bookmark) $t
	set Vars(bookmark:target:id) {}
	set Vars(bookmark:target:folder) ""
	set Vars(bookmark:target:path) ""
	set Vars(bookmark:background) white
	set yscrollcmd [list [namespace parent]::SbSet $sb]

	treectrl $t {*}[array get opts] \
		-class FSBox                 \
		-highlightthickness 0        \
		-showroot no                 \
		-showheader no               \
		-showbuttons no              \
		-showlines no                \
		-takefocus 1                 \
		-itemheight $linespace       \
		-yscrollcommand $yscrollcmd  \
		;

	ttk::scrollbar $sb          \
		-orient vertical         \
		-takefocus 0             \
		-command [list $t yview] \
		;
	bind $sb <ButtonPress-1> [list focus $t]

	grid $t -row 0 -column 0 -sticky nsew
	grid $sb -row 0 -column 1 -sticky ns
	grid columnconfigure $path.f {0} -weight 1
	grid rowconfigure $path.f {0} -weight 1

	$t state define hilite
	$t state define target
	$t state define edit

	$t column create -tags root
	$t configure -treecolumn root

	$t element create elemImg image
	$t element create elemTxt text                                   \
		-fill [list                                                   \
			[lookupColor $Vars(selectionforeground)] {selected focus}  \
			[lookupColor $Vars(selectionforeground)] {selected hilite} \
			[lookupColor $Vars(inactiveforeground)]  {selected !focus} \
			[lookupColor $Vars(activeforeground)]    {hilite}          \
		]                                                             \
		-lines 1                                                      \
		;
	$t element create elemSel rect                                   \
		-fill [list                                                   \
			[lookupColor $Options(drop:background)]  {target}          \
			[lookupColor $Vars(selectionbackground)] {selected focus}  \
			[lookupColor $Vars(selectionbackground)] {selected hilite} \
			[lookupColor $Vars(inactivebackground)]  {selected !focus} \
			[lookupColor $Vars(activebackground)]    {hilite}          \
		]
	$t element create elemBrd border                           \
		-filled no                                              \
		-relief raised                                          \
		-thickness 1                                            \
		-background {#e5e5e5 {selected} #e5e5e5 {target} {} {}} \
		;

	set s [$t style create style]
	$t style elements $s {elemSel elemImg elemBrd elemTxt}
	$t style layout $s elemImg -expand ns -padx {4 0}
	$t style layout $s elemTxt -padx {6 4} -expand ns -squeeze x
	$t style layout $s elemSel -union {elemTxt} -iexpand nsew
	$t style layout $s elemBrd -iexpand xy -detach yes

	$t element create elemDiv rect -fill black -height 1
	$t style create styLine
	$t style elements styLine {elemDiv}
	$t style layout styLine elemDiv -pady {3 2} -padx {4 4} -iexpand x -expand ns

	TreeCtrl::SetEditable $t { {root style elemTxt} }

	$t notify install <Edit-begin>
	$t notify install <Edit-accept>
	$t notify install <Edit-end>
	$t notify install <Item-enter>
	$t notify install <Item-leave>

	$t notify bind $t <Item-enter> [list [namespace parent]::VisitItem $w $t enter %I]
	$t notify bind $t <Item-leave> [list [namespace parent]::VisitItem $w $t leave %I]

	$t style layout style elemTxt -draw {no edit}
	$t style layout style elemSel -draw {no edit}
	$t notify bind $t <Edit-begin> { %T item state set %I ~edit }
	$t notify bind $t <Edit-accept> { %T item element configure %I %C %E -text %t }
	$t notify bind $t <Edit-accept> +[namespace code [list EditAccept $w]]
	$t notify bind $t <Edit-end> { %T item state set %I ~edit }
	$t notify bind $t <Edit-end> +[namespace code [list FinishEdit $w]]

	bind $t <Double-Button-1> [namespace code [list InvokeBookmark $w %x %y]]
	bind $t <Double-Button-1> {+ break }
	bind $t <ButtonPress-3> [namespace code [list PopupMenu $w %x %y]]
	bind $t <Key-space> [namespace code [list InvokeBookmark $w]]
	bind $t <Return> [namespace code [list InvokeBookmark $w]]
	bind $t <Return> {+ break }

	if {[llength $Vars(inspectcommand)]} {
		bind $t <ButtonPress-2> [namespace code [list InspectBookmark $w show %x %y]]
		bind $t <ButtonRelease-2> [namespace code [list InspectBookmark $w hide]]
	}

	BuildBookmarks $w

	$t activate 0
	$t notify bind $t <Selection> [namespace code [list Selected $w %S]]

	Selected $w {}
}


proc BuildBookmarks {w} {
	if {![winfo exists $w]} { return }
	variable [namespace parent]::${w}::Vars

	set Vars(bookmarks) {
		{ star			Favorites	}
		{ visited		LastVisited	}
		{ divider		""				}
	}
	foreach folder [[namespace parent]::GetFolders $w] {
		set icon ""
		switch $folder {
			Desktop - Trash - Download {
				if {[string length $Vars(folder:[string tolower $folder])] == 0} { continue }
				set icon [string tolower $folder]
			}
			Home - FileSystem {
				set icon [string tolower $folder]
			}
		}
		lappend Vars(bookmarks) [list $icon $folder]
	}
	lappend Vars(bookmarks) { divider "" }
	LayoutBookmarks $w
}


proc InspectBookmark {w mode args} {
	variable [namespace parent]::${w}::Vars

	set tl [winfo toplevel $w]

	if {$mode eq "show"} {
		variable Bookmarks
		set t $Vars(widget:list:bookmark)
		lassign $args x y
		set id [$t identify $x $y]
		if {[llength $id] > 0 && [lindex $id 0] eq "header"} { return }
		set index [lindex $id 1]
		if {$index < [llength $Vars(bookmarks)]} {
			set attr [string tolower [lindex $Vars(bookmarks) [expr {$index - 1}] 1]]
			if {![info exists Vars(folder:$attr)]} { return }
			set path $Vars(folder:$attr)
			if {[string length $path] == 1} { set path " $path " }
		} else {
			set path [lindex [lindex $Bookmarks(user) [expr {$index - [llength $Vars(bookmarks)] - 1}]] 0]
		}
		{*}$Vars(inspectcommand) $tl $path
	} else {
		{*}$Vars(inspectcommand) $tl
	}
}


proc LayoutBookmarks {w} {
	variable [namespace parent]::${w}::Vars
	variable Bookmarks

	set t $Vars(widget:list:bookmark)
	$t item delete all
	$t xview moveto 0.0
	$t yview moveto 0.0

	foreach entry $Vars(bookmarks) {
		lassign $entry icon text
		set item [$t item create]
		if {$icon eq "divider"} {
			$t item style set $item root styLine
			$t item enabled $item false
		} else {
			if {[string length $icon] > 0} { set text [Tr $text] } else { set icon usb }
			set icon [set [namespace parent]::icon::16x16::$icon]
			$t item style set $item root style
			$t item element configure $item root \
				elemImg -image $icon + \
				elemTxt -text $text \
				;
		}
		$t item lastchild root $item
	}

	set bookmarks {}
	foreach entry $Bookmarks(user) {
		lassign $entry folder name
		if {[file isdirectory $folder]} {
			if {[string length $name] == 0} { set name [file tail $folder] } ;# support old format
			lappend bookmarks [list $folder $name]
		}
	}
	set Bookmarks(user) $bookmarks
	array unset Vars bookmark:tooltip:*

	set index 0
	foreach entry $Bookmarks(user) {
		lassign $entry folder name
		set icon [set [namespace parent]::icon::16x16::folder]
		set item [$t item create]
		$t item style set $item root style
		$t item element configure $item root elemImg -image $icon + elemTxt -text $name
		$t item lastchild root $item
		set Vars(bookmark:tooltip:$item) $index
		incr index
	}
}


proc AddBookmark {w {folder ""}} {
	if {![winfo exists $w]} { return }
	variable [namespace parent]::${w}::Vars
	variable Bookmarks

	if {[string length $folder] == 0} { set folder $Vars(folder) }

	set i [lsearch -exact -index 0 $Bookmarks(user) $folder]
	if {$i >= 0} {
		set name [lindex $Bookmarks(user) $i 1]
		set msg [format [Tr BookmarkAlreadyExists] $name]
		if {$name eq [file tail $folder]} {
			return [::dialog::info -parent $w -message $msg]
		}
		append msg "\n\n" [Tr AddBookmarkAnyway]
		set reply [::dialog::question -parent $w -message $msg -default yes]
		if {$reply eq "no"} { return }
	}
	
	lappend Bookmarks(user) [list [file normalize $folder] [file tail $folder]]
	set list {}
	set index -1
	foreach entry $Bookmarks(user) {
		lappend list [list [incr index] [string tolower [lindex $entry 1]]]
	}
	set list [[namespace parent]::mySort -nocase -index 1 $list]
	set bookmarks {}
	foreach entry $list { lappend bookmarks [lindex $Bookmarks(user) [lindex $entry 0]] }
	set Bookmarks(user) $bookmarks
	LayoutBookmarks $w
	$Vars(widget:list:bookmark) see end
	[namespace parent]::DirChanged $w 0
}


proc RemoveBookmark {w} {
	variable [namespace parent]::${w}::Vars
	variable Bookmarks

	set t $Vars(widget:list:bookmark)
	set sel [expr {[$t item id active] - 1}]
	set sel [expr {$sel - [llength $Vars(bookmarks)]}]
	set Bookmarks(user) [lreplace $Bookmarks(user) $sel $sel]
	LayoutBookmarks $w
	UpdateButtons $w
	[namespace parent]::DirChanged $w 0
}


proc RenameBookmark {w} {
	variable [namespace parent]::${w}::Vars
	variable Bookmarks

	set t $Vars(widget:list:bookmark)
	set sel [$t item id active]
	OpenEdit $w $sel rename
}


proc UpdateButtons {w} {
	variable [namespace parent]::${w}::Vars
	variable Bookmarks

	if {$Vars(glob) eq "Files"} { set folder $Vars(folder) } else { set folder $Vars(glob) }
	set Vars(bookmark:folder) ""
	::toolbar::childconfigure $Vars(button:add) -state normal

	foreach f {home filesystem} {
		if {$Vars(folder) eq $Vars(folder:$f)} {
			::toolbar::childconfigure $Vars(button:add) -state disabled
		}
	}

	if {$Vars(glob) ne "Files"} {
		::toolbar::childconfigure $Vars(button:add) -state disabled
	} else {
		foreach f $Bookmarks(user) {
			lassign $f _ name
			if {$Vars(folder) eq [lindex $f 0] && [file tail $Vars(folder)] eq $name} {
				::toolbar::childconfigure $Vars(button:add) -state disabled
			}
		}
	}

	set Vars(bookmark:folder) $folder
	set tip [format [Tr AddBookmark] [file tail $folder]]
	::toolbar::childconfigure $Vars(button:add) -tooltip $tip
}


proc OpenEdit {w sel mode} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:bookmark)
	$t selection clear
	foreach item [$t item children root] { $t item state set $item {!hilite} }
	$t see $sel
	set index [expr {$sel - [llength $Vars(bookmarks)] - 1}]

	set e [::TreeCtrl::EntryExpanderOpen $t $sel 0 elemTxt 0]
	set Vars(edit:active) 1
	set Vars(edit:sel) $sel
	set Vars(edit:index) $index
	set Vars(edit:accept) 0
	::TreeCtrl::TryEvent $t Edit begin [list I $sel C 0 E elemTxt]
}


proc EditAccept {w} {
	variable [namespace parent]::${w}::Vars
	set Vars(edit:accept) 1
}


proc FinishEdit {w} {
	variable [namespace parent]::${w}::Vars
	variable Bookmarks

	set t $Vars(widget:list:bookmark)
	set sel $Vars(edit:sel)
	set Vars(edit:active) 0

	if {$Vars(edit:accept)} {
		$t selection clear
		set newName [string trim [$t item element cget $sel 0 elemTxt -text]]
		set oldName [lindex $Bookmarks(user) $Vars(edit:index) 1]
		if {[string length $newName] == 0} { return $oldName }
		if {$oldName eq $newName} { return $oldName }
		lset Bookmarks(user) $Vars(edit:index) 1 $newName
		Selected $w $Vars(edit:sel)
	}

	$t selection clear
	$t selection add $sel
	$t activate $sel
	$t see $sel

	UpdateButtons $w
	after idle [list [namespace parent]::Stimulate $w]
}


proc Selected {w sel} {
	variable [namespace parent]::${w}::Vars
	variable Bookmarks

	if {[string is integer -strict $sel] && $sel > [llength $Vars(bookmarks)]} {
		set name [lindex $Bookmarks(user) [expr {$sel - [llength $Vars(bookmarks)] - 1}] 1]
		set tip [format [Tr RemoveBookmark] [file tail $name]]
		::toolbar::childconfigure $Vars(button:minus) -state normal -tooltip $tip
		set tip [format [Tr RenameBookmark] [file tail $name]]
		::toolbar::childconfigure $Vars(button:modify) -state normal -tooltip $tip
	} else {
		::toolbar::childconfigure $Vars(button:minus) -state disabled
		::toolbar::childconfigure $Vars(button:modify) -state disabled
	}
}


proc InvokeBookmark {w args} {
	variable [namespace parent]::${w}::Vars
	variable Bookmarks

	set t $Vars(widget:list:bookmark)

	if {[llength $args] == 2} {
		lassign $args x y
		set id [$t identify $x $y]
		if {[llength $id] == 0 || [lindex $id 0] eq "header"} { return }
		set sel [$t item order [lindex $id 1] -visible]
	} else {
		set sel [expr {[$t item id active] - 1}]
	}

	if {$sel < [llength $Vars(bookmarks)]} {
		set folder [lindex $Vars(bookmarks) $sel 1]
		if {[string length $folder] == 0} { return }
		set id [string tolower $folder]
		switch $folder {
			Favorites - LastVisited - Desktop - Trash - Download { set dir $folder }
			default { set dir $Vars(folder:$id) }
		}
		[namespace parent]::ChangeDir $w $dir
	} else {
		set i [expr {$sel - [llength $Vars(bookmarks)]}]
		if {$i < [llength $Bookmarks(user)]} {
			[namespace parent]::ChangeDir $w [lindex $Bookmarks(user) $i 0]
		}
	}
}


proc PopupMenu {w x y} {
	variable [namespace parent]::${w}::Vars
	variable Bookmarks

	set t $Vars(widget:list:bookmark)
	set id [$t identify $x $y]
	if {[llength $id] > 0 && [lindex $id 0] eq "header"} { return }
	foreach item [$t item children root] { $t item state set $item {!hilite} }

	set m $w.menu
	if {[winfo exists $m]} { destroy $m }
	menu $m -tearoff false
	set count 0

	if {[string length $Vars(folder)] && [::toolbar::childcget $Vars(button:add) -state] eq "normal"} {
		if {[string length $Vars(bookmark:folder)]} { set state normal } else { set state disabled }
		set text [format [Tr AddBookmark] [file tail $Vars(folder)]]
		$m add command \
			-compound left \
			-image $icon::16x16::plus \
			-label " $text" \
			-command [namespace code [list AddBookmark $w]] \
			-state $state \
			;
		incr count
	}

	if {[::toolbar::childcget $Vars(button:minus) -state] eq "normal"} {
		set sel [expr {[$t item id active] - [llength $Vars(bookmarks)] - 1}]
		if {$sel >= 0} {
			set name [lindex $Bookmarks(user) $sel 1]
			set text [format [Tr RemoveBookmark] $name]
			$m add command                                        \
				-compound left                                     \
				-image $icon::16x16::minus                         \
				-label " $text"                                    \
				-command [namespace code [list RemoveBookmark $w]] \
				;
			set text [format [Tr RenameBookmark] $name]
			$m add command                                        \
				-compound left                                     \
				-image $icon::16x16::modify                        \
				-label " $text"                                    \
				-command [namespace code [list RenameBookmark $w]] \
				;
			incr count
		}
	}

	if {$count > 0} {
		set Vars(edit:active) 1
		tk_popup $m {*}[winfo pointerxy $w]
		bind $m <<MenuUnpost>> [list [namespace parent]::Stimulate $w]
	}
}


proc HandleDropEvent {w action types actions {x -1} {y -1}} {
	variable [namespace parent]::${w}::Vars
	variable [namespace parent]::Options
	variable Bookmarks

	if {$action ne "leave" && !$Vars(drag:active)} { return refuse_drop }

	set t $Vars(widget:list:bookmark)
	set result refuse_drop

	switch $action {
		enter {
			if {$Vars(drag:private)} {
				$Vars(widget:list:bookmark) configure -background [lookupColor $Options(drop:background)]
				set Vars(bookmark:background) [lookupColor $Options(drop:background)]
			}
			set Vars(bookmark:target:id) {}
		}

		leave {
			if {$Vars(bookmark:background) ne "white"}  {
				$Vars(widget:list:bookmark) configure -background white
				set Vars(bookmark:background) white
			}
		}

		position {
			if {$Vars(drag:private)} { return private }
			set x [expr {$x - [winfo rootx $t]}]
			set y [expr {$y - [winfo rooty $t]}]
			set id [$t identify $x $y]
			if {[llength $Vars(bookmark:target:id)] > 0} {
				if {$Vars(bookmark:target:id) eq $id} { return ask }
				$t item state set [lindex $Vars(bookmark:target:id) 1] !target
			}
			set Vars(bookmark:target:id) {}
			if {[llength $id] > 0 && [lindex $id 0] ne "header"} {
				set sel [expr {[lindex $id 1] - 1}]
				set folder ""
				set path ""
				if {$sel < [llength $Vars(bookmarks)]} {
					set folder [lindex $Vars(bookmarks) $sel 1]
					if {[string length $folder] > 0} {
						switch $folder {
							Favorites - LastVisited {}
							default {
								if {$folder eq "Trash" || !$Vars(drag:active) || !$Vars(drag:trash)} {
									set path $Vars(folder:[string tolower $folder])
								}
							}
						}
					}
				} else {
					set i [expr {$sel - [llength $Vars(bookmarks)]}]
					if {$i < [llength $Bookmarks(user)]} {
						set folder [lindex $Bookmarks(user) $i 0]
						set path $folder
					}
				}
				if {[string length $path]} {
					set Vars(bookmark:target:id) $id
					set Vars(bookmark:target:folder) $folder
					set Vars(bookmark:target:path) $path
					$t item state set [lindex $id 1] target
					if {$Vars(drag:private)} { return private }
					return ask
				}
			}
		}

		default {
			if {$Vars(drag:private)} {
				set dir [lindex [[namespace parent]::parseUriList $action] 1]
				after idle [namespace code [list AddBookmark $w $dir]]
				set result private
			} elseif {[llength $Vars(bookmark:target:id)] > 0} {
				if {$Vars(bookmark:target:folder) eq "Trash"} {
					after idle [namespace code [list DoHandleDropEvent $w $action]]
					set result move
				} else {
					set result [[namespace parent]::AskAboutAction \
						$w $Vars(bookmark:target:path) $action $actions]
				}
			}
			if {$Vars(bookmark:background) ne "white"}  {
				$Vars(widget:list:bookmark) configure -background white
				set Vars(bookmark:background) white
			}
		}
	}

	if {[llength $Vars(bookmark:target:id)] > 0} {
		$t item state set [lindex $Vars(bookmark:target:id) 1] !target
	}
	set Vars(bookmark:target:id) {}

	return $result
}


proc DoHandleDropEvent {w uriFiles} {
	if {![winfo exists $w]} { return }
	variable [namespace parent]::${w}::Vars

	if {[llength $uriFiles] > 0} {
		set file ""
		set extensions {}
		foreach {uri f} [[namespace parent]::parseUriList $uriFiles] {
			if {[string length $file] == 0} { set file [file rootname $f] }
			set ext [::util::fileExtension $f]
			if {$ext in $Vars(extensions)} {
				if {[[namespace parent]::CheckIfInUse $w $f delete]} { return }
			}
			lappend extensions $ext
		}
		::trash::move $file $extensions
		[namespace parent]::filelist::RefreshFileList $w
	}
}

namespace eval icon {
namespace eval 16x16 {

set minus [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAAWUlEQVR4nGNg
	GAUUA0ZkdmhoKBMxmlavXv2PgYHhP3VcUF9fz9TY2PjPwClUi4WJqev/378sqA5DBv8ZGJmZ//z5
	96/swr7V1+rr65mIcjJNwcAH4ihgYAAAhgQchcjL71cAAAAASUVORK5CYII=
}]

set plus [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAAyUlEQVR4nLWT
	MY7CQAxF3zi5AhegTBUp4gBJub2vsq2Vlop7pERCVFyAhopyL8AVyHgbkEYRhCnIq6yvked7/Afm
	MBPMZPbMUgSAutOq7rRKtSkv7amqAIizE2eXalPKDzZiltVnndxSAOPfjQPAesXPUwMYhiEC/qk5
	Tav7ptX9rAMzk77vY91pVYpsfRxLPAQC0Z0NQAiccYTgHorifo/x93IarmYmy+44a4S0/tojqmrx
	cHBsWj2m2pTZHPiboOWQHeWFyfjO/6v3R3F0+cfxAAAAAElFTkSuQmCC
}]

set modify [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACC0lEQVR4nJWT
	T28SQRiHfzO7yy4SQ0zUgz00MZw2EViFpgZ0FiGReqhSQiwe7LmJ32HTL2H8AD2VRCXRizUte6Dl
	ALHcemy4eNDEi7L/2BkPQmkETP2dJpM877zv+2QILhWLMtaiAGDbJgd2+OU4ALAsOueWzBzmpVar
	SY1GIzQKG8sSjWwLITg8/qbXbgzGrFhYgDEm27Y9Mlg1IyvKexFygCAGQvyQBytfDt8OYFlkXnvn
	cPLhuiFJcluSlSURuNXuwd41CKgEdBuAYK0WlRfB6UIlpcjRtghH+4HvhUSLHabNZ2tCcI+I6cPy
	XDhXSSly9FhwftQ92FsHIO4Vak1NvdoKfPf7SPivARDbNDn9Gzby1aQS1Y4F50fDr+ETAJwxJlFK
	wTn/wTlf69vNM1gWwc5E51hVOldJZUsvhpni5udEoqwCgK7rkeyjzf1sqe7eeVC5O7Ez7XsMZ4pV
	Y6VU/zUDF59/ypbqToo9TU86vTg2AUCWGVOv05sDIkmn8s+zx51Ox9F1PRK7lfwIkHzguKsn7Xf9
	yZgXC8gAxFIQV3yN3AgD72W303ES5bIa8+MfQEg+GC2Gzy14V1SKUIASZcMwa3HJp69Aacb3h/f7
	dnMhDAB/LGhOACH6hJItSskugNuu5+b6dvPkX/BkB2ONW5oTHUUAIPx26vR6vQCWRaeq/jfzf+FM
	fgOW4PDbfiIv5QAAAABJRU5ErkJggg==
}]

} ;# namespace 16x16
} ;# namespace icon
} ;# namespace bookmarks

######  F I L E  L I S T ######################################################

namespace eval filelist {

namespace import ::tcl::mathfunc::max
namespace import [namespace parent]::Tr
namespace import [namespace parent]::lookupColor


proc Build {w path args} {
	variable [namespace parent]::${w}::Vars
	variable [namespace parent]::Options

	if {![info exists [namespace current]::icon::16x16::iconAdd]} {
		foreach {icon img} {	Delete delete Restore restore Modify modify Duplicate duplicate
									Add folder_add Backward backward Forward forward} {
			set [namespace current]::icon::16x16::icon$icon \
				[list [[namespace parent]::makeStateSpecificIcons \
					[set [namespace current]::icon::16x16::$img]]]
		}
	}

	if {[llength $Vars(customcommand)] && [llength $Vars(customicon)]} {
		set Vars(customicon) [list [[namespace parent]::makeStateSpecificIcons $Vars(customicon)]]
	}

	array set opts {
		-scrollmargin	16
		-selectmode		single
		-fullstripes	yes
		-stripes			{}
		-yscrolldelay	{500 50}
		-textpadx		{6 6}
		-textpady		{0 0}
	}

	array set opts $args

	foreach option {borderwidth textpadx textpady stripes} {
		set Vars($option) $opts(-$option)
		array unset opts -$option
	}

	if {[info exists opts(-rows)]} {
		set Vars(rows) $opts(-rows)
		array unset opts -rows
	}

	set Vars(sort-column) name
	set Vars(sort-order) increasing
	set Vars(selected:folders) {}
	set Vars(selected:files) {}
	set Vars(lock:selection) 0
	set Vars(undo:history) {}
	set Vars(undo:current) -1
	set Vars(tip:forward) ""
	set Vars(tip:backward) ""
	set Vars(lock:refresh) 0

	tk::frame $path -borderwidth 0 -takefocus 0
	tk::frame $path.f -borderwidth 0 -takefocus 0
	pack $path.f -fill both -expand yes

	set sv $path.f.vscroll
	set sh $path.f.hscroll
	set t  $path.f.files
	::toolbar::setup $path -id fsbox-files
	set tb [::toolbar::toolbar $path -id fsbox:files -hide 0 -side left]

	set Vars(toolbar:filelist) $tb

	set Vars(button:backward) [::toolbar::add $tb button \
		-image $icon::16x16::iconBackward                 \
		-command [namespace code [list Undo $w]]          \
		-state disabled                                   \
	]
	set Vars(button:forward) [::toolbar::add $tb button \
		-image $icon::16x16::iconForward                 \
		-command [namespace code [list Redo $w]]         \
		-state disabled                                  \
	]

	::toolbar::add $tb separator
	set count 0

	if {"delete" in $Vars(actions)} {
		if {[::trash::usable?]} { set tip MoveToTrash } else { set tip Delete }
		set Vars(button:delete) [::toolbar::add $tb button \
			-image $icon::16x16::iconDelete                 \
			-command [namespace code [list DeleteFile $w]]  \
			-tooltip [Tr $tip]                              \
			-state disabled                                 \
		]
		incr count
	}
	if {"rename" in $Vars(actions)} {
		set Vars(button:rename) [::toolbar::add $tb button \
			-image $icon::16x16::iconModify                 \
			-command [namespace code [list RenameFile $w]]  \
			-tooltip [string map {& {}} [Tr Rename]]        \
			-state disabled                                 \
		]
		incr count
	}
	if {"copy" in $Vars(actions) && $Vars(type) ne "dir"} {
		set Vars(button:copy) [::toolbar::add $tb button     \
			-image $icon::16x16::iconDuplicate                \
			-command [namespace code [list DuplicateFile $w]] \
			-tooltip [Tr Duplicate]                           \
			-state disabled                                   \
		]
		incr count
	}
	if {[llength $Vars(customcommand)] && [llength $Vars(customicon)]} {
		set Vars(button:custom) [::toolbar::add $tb button       \
			-image $Vars(customicon)                              \
			-command [namespace code [list CallCustomCommand $w]] \
			-tooltip $Vars(customtooltip)                         \
			-state disabled                                       \
		]
		incr count
	}
	if {"new" in $Vars(actions)} {
		set Vars(button:new) [::toolbar::add $tb button  \
			-image $icon::16x16::iconAdd                  \
			-command [namespace code [list NewFolder $w]] \
			-tooltip [Tr NewFolder]                       \
		]
		incr count
	}

	if {$count > 0} { ::toolbar::add $tb separator }

	if {$Options(show:layout) eq "list"} {
		set tooltip ListLayout
		set Vars(layout:list) 0
		set layout details
	} else {
		set tooltip DetailedLayout
		set Vars(layout:list) 1
		set layout list
	}
	set Vars(widget:layout) [::toolbar::add $tb button       \
		-image [set icon::16x16::$layout]                     \
		-command [namespace code [list SwitchLayout $w]]      \
		-tooltip [Tr $tooltip]                                \
		-variable [namespace parent]::${w}::Vars(layout:list) \
	]
	if {$::tcl_platform(platform) eq "unix"} {
		if {$Vars(showhidden)} { set ipref "" } else { set ipref "un" }
		if {$Vars(type) eq "dir"} { set var ShowHiddenDirs } else { set var ShowHiddenFiles }
		set Vars(widget:hidden) [::toolbar::add $tb checkbutton \
			-image [set icon::16x16::${ipref}locked]             \
			-tooltip [Tr $var]                                   \
			-command [namespace code [list SwitchHidden $w]]     \
			-variable [namespace parent]::${w}::Vars(showhidden) \
			-padx 1                                              \
		]
	}

	set Vars(widget:list:file) $t
	set Vars(xscrollcmd) [list [namespace parent]::SbSet $sh]
	set Vars(yscrollcmd) [list $sv set]
	set Vars(widget:xscrollbar) $sh
	set Vars(widget:yscrollbar) $sv

	treectrl $t {*}[array get opts] \
		-class FSBox                 \
		-takefocus 1                 \
		-highlightthickness 0        \
		-showheader yes              \
		-showbuttons no              \
		-showroot no                 \
		-showlines no                \
		-showrootlines no            \
		-columnresizemode realtime   \
		-xscrollincrement 1          \
		-keepuserwidth no            \
		-orient vertical             \
		;

	ttk::scrollbar $sv          \
		-orient vertical         \
		-takefocus 0             \
		-command [list $t yview] \
		;
	ttk::scrollbar $sh          \
		-orient horizontal       \
		-takefocus 0             \
		-command [list $t xview] \
		;

	grid $t  -row 0 -column 0 -sticky nsew
	grid $sh -row 1 -column 0 -sticky ew
	grid $sv -row 0 -column 1 -sticky ns
	grid columnconfigure $path.f {0} -weight 1
	grid rowconfigure $path.f {0} -weight 1

	bind $sh <ButtonPress-1> [list focus $t]
	bind $sv <ButtonPress-1> [list focus $t]
	SetColumnBackground $t tail $Vars(stripes) $opts(-background)

	set linespace [max 20 [font metrics [$t cget -font] -linespace]]
	set Vars(charwidth) [font measure [$t cget -font] "0"]
	$t configure -itemheight $linespace
	$t state define hilite

	SwitchLayout $w

	TreeCtrl::SetEditable  $t { {name styName txtName} }
#	TreeCtrl::SetSensitive $t { {name styName elemImg txtName} }
#	TreeCtrl::SetDragImage $t { {name styName elemImg txtName} }

	$t notify install <Edit-begin>
	$t notify install <Edit-accept>
	$t notify install <Edit-end>
	$t notify install <Item-enter>
	$t notify install <Item-leave>
	$t notify install <Header-invoke>
	$t notify install <Column-resized>

	$t state define edit
	$t style layout styName txtName -draw {no edit}
	$t style layout styName elemSel -draw {no edit}
	$t notify bind $t <Edit-begin> { %T item state set %I ~edit }
	$t notify bind $t <Edit-accept> { %T item element configure %I %C %E -text %t }
	$t notify bind $t <Edit-accept> +[namespace code [list EditAccept $w]]
	$t notify bind $t <Edit-end> { %T item state set %I ~edit }
	$t notify bind $t <Edit-end> +[namespace code [list FinishEdit $w]]

	$t notify bind $t <Item-enter> [list [namespace parent]::VisitItem $w $t enter %I]
	$t notify bind $t <Item-leave> [list [namespace parent]::VisitItem $w $t leave %I]
	$t notify bind $t <Column-resized> [namespace code [list ColumnResized $w %C]]

	$t notify bind $t <Header-invoke> [namespace code [list SortColumn $w %C]]
	$t notify bind $t <Selection> [namespace code [list SelectFiles $w %S]]

	bind $t <Double-Button-1> [namespace code [list InvokeFile $w %x %y]]
	bind $t <Double-Button-1> {+ break }
	bind $t <ButtonPress-3> [namespace code [list PopupMenu $w %x %y]]
	bind $t <Control-a> [namespace code [list SelectAllFiles $w]]
	bind $t <Control-A> [namespace code [list SelectAllFiles $w]]
	bind $t <Key-space> [namespace code [list InvokeFile $w]]
	bind $t <Return> [namespace code [list InvokeFile $w]]
	bind $t <Return> {+ break }

	if {[llength $Vars(inspectcommand)]} {
		bind $t <ButtonPress-2>		[namespace code [list Inspect $w show %x %y]]
		bind $t <ButtonRelease-2>	[namespace code [list Inspect $w hide]]
	}

	CheckDir $t

	if {[info exists Vars(rows)]} {
		update idletasks
		set minh [expr {[::toolbar::requestedHeight $path] - [$t headerheight]}]
		set Vars(rows:computed) [expr {max($Vars(rows), ($minh + $linespace - 1)/$linespace)}]
		set h [expr {[$t headerheight] + max($Vars(rows:computed), 1)*$linespace}]
		$t configure -height $h
	}
}


proc Rebuild {w} {
	variable [namespace parent]::${w}::Vars

	set tb $Vars(toolbar:filelist)

	if {[llength $Vars(customcommand)] && [llength $Vars(customicon)]} {
		if {![info exists Vars(button:custom)]} {
			set Vars(customicon) [list [[namespace parent]::makeStateSpecificIcons $Vars(customicon)]]

			set Vars(button:custom) [::toolbar::add $tb button       \
				-image $Vars(customicon)                              \
				-command [namespace code [list CallCustomCommand $w]] \
				-tooltip $Vars(customtooltip)                         \
				-state disabled                                       \
				-after $Vars(button:copy)                             \
			]
		}
	} elseif {[info exists Vars(button:custom)]} {
		::toolbar::remove $Vars(button:custom)
		array unset Vars button:custom
	}
}


proc SwitchHidden {w} {
	variable [namespace parent]::${w}::Vars

	if {$Vars(showhidden)} { set ipref "" } else { set ipref "un" }
	toolbar::childconfigure $Vars(widget:hidden) -image [set icon::16x16::${ipref}locked]
	$Vars(choosedir) showhidden $Vars(showhidden)
	RefreshFileList $w
}


proc DetailedLayout {w} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)

	$t configure -itemwidthequal no
	$t configure -wrap {}
	$t configure -showheader yes
	$t configure -yscrollcommand $Vars(yscrollcmd)
	$t configure -xscrollcommand $Vars(xscrollcmd)
	grid remove $Vars(widget:xscrollbar)
	grid $Vars(widget:yscrollbar)

	catch { $t item delete 1 end }
	foreach col [$t column list] { $t column delete $col }
	foreach sty [$t style names] { $t style delete $sty }
	$t element delete {*}[$t element names]

	if {[info exists Vars(column:name)]} {
		set copts(name) [list -width $Vars(column:name)]
		set copts(size) [list -width $Vars(column:size)]
		set copts(modified) [list -width $Vars(column:modified)]
	} else {
		set copts(name) {}
		set copts(size) {}
		set copts(modified) {}
	}

	set background [[namespace parent]::GetHeaderBackground $w]

	$t column create                          \
		-background $background                \
		-text [Tr Name]                        \
		-tags name                             \
		-minwidth [expr {10*$Vars(charwidth)}] \
		-arrow up                              \
		-borderwidth $Vars(borderwidth)        \
		-steady yes                            \
		-textpadx $Vars(textpadx)              \
		-textpady $Vars(textpady)              \
		-font $Vars(font)                      \
		-expand yes                            \
		-squeeze yes                           \
		{*}$copts(name)                        \
		;
	if {$Vars(type) ne "dir"} {
		set bg [lookupColor $Vars(emphasizebackground)]
		$t column create                         \
			-background $background               \
			-itembackground $bg                   \
			-text [Tr Size]                       \
			-tags size                            \
			-justify right                        \
			-width [expr {11*$Vars(charwidth)}]   \
			-minwidth [expr {6*$Vars(charwidth)}] \
			-arrowside left                       \
			-arrowgravity right                   \
			-borderwidth $Vars(borderwidth)       \
			-steady yes                           \
			-textpadx $Vars(textpadx)             \
			-textpady $Vars(textpady)             \
			-font $Vars(font)                     \
			{*}$copts(size)                       \
			;
	}
	$t column create                          \
		-background $background                \
		-text [Tr Modified]                    \
		-tags modified                         \
		-width [expr {18*$Vars(charwidth)}]    \
		-minwidth [expr {10*$Vars(charwidth)}] \
		-borderwidth $Vars(borderwidth)        \
		-steady yes                            \
		-textpadx $Vars(textpadx)              \
		-textpady $Vars(textpady)              \
		-font $Vars(font)                      \
		{*}$copts(modified)                    \
		;
	
	$t element create elemImg image ;# -image [set [namespace parent]::icon::16x16::folder]
	$t element create txtName text                                   \
		-fill [list                                                   \
			[lookupColor $Vars(selectionforeground)] {selected focus}  \
			[lookupColor $Vars(selectionforeground)] {selected hilite} \
			[lookupColor $Vars(inactiveforeground)]  {selected !focus} \
			[lookupColor $Vars(activeforeground)] {hilite}             \
		]                                                             \
		-lines 1                                                      \
		;
	$t element create txtSize text                                   \
		-fill [list                                                   \
			[lookupColor $Vars(selectionforeground)] {selected focus}  \
			[lookupColor $Vars(selectionforeground)] {selected hilite} \
			[lookupColor $Vars(inactiveforeground)]  {selected !focus} \
			[lookupColor $Vars(activeforeground)]    {hilite}          \
		]                                                             \
		-lines 1                                                      \
		;
	$t element create txtDate text                                   \
		-fill [list                                                   \
			[lookupColor $Vars(selectionforeground)] {selected focus}  \
			[lookupColor $Vars(selectionforeground)] {selected hilite} \
			[lookupColor $Vars(inactiveforeground)]  {selected !focus} \
			[lookupColor $Vars(activeforeground)]    {hilite}          \
		]                                                             \
		-datatype time                                                \
		-format [Tr TimeFormat]                                       \
		-lines 1                                                      \
		;
	$t element create elemSel rect                                   \
		-fill [list                                                   \
			[lookupColor $Vars(selectionbackground)] {selected focus}  \
			[lookupColor $Vars(selectionbackground)] {selected hilite} \
			[lookupColor $Vars(inactivebackground)] {selected !focus}  \
			[lookupColor $Vars(activebackground)] {hilite}             \
		] 
	$t element create elemBrd border          \
		-filled no                             \
		-relief raised                         \
		-thickness 1                           \
		-background {#e5e5e5 {selected} {} {}} \
		;
	
	# column 0: icon + text
	set s [$t style create styName -orient horizontal]
	$t style elements $s {elemSel elemImg elemBrd txtName}
	$t style layout $s elemImg -padx {2 0} -expand ns
	$t style layout $s txtName -squeeze x -expand ns -padx {4 0}
	$t style layout $s elemSel -union {txtName} -ipadx 2 -iexpand nsew
	$t style layout $s elemBrd -iexpand xy -detach yes

	# column 1: text
	set s [$t style create stySize]
	$t style elements $s {elemSel elemBrd txtSize}
	$t style layout $s txtSize -padx {4 4} -squeeze x -expand ns
	$t style layout $s elemSel -union {txtSize} -ipadx 2 -iexpand nsew
	$t style layout $s elemBrd -iexpand xy -detach yes

	# column 2: text
	set s [$t style create styDate]
	$t style elements $s {elemSel elemBrd txtDate}
	$t style layout $s txtDate -padx {4 4} -squeeze x -expand ns
	$t style layout $s elemSel -union {txtDate} -ipadx 2 -iexpand nsew
	$t style layout $s elemBrd -iexpand xy -detach yes

	if {$Vars(type) eq "dir"} {
		set Vars(scriptDir) {
			set item [$t item create -open no]
			if {[llength $icon] == 0} { set icon $::fsbox::icon::16x16::folder }
			if {[llength $folder] == 0} { set folder [file tail $path] }
			$t item style set $item name styName modified styDate
			$t item element configure $item \
				name elemImg -image $icon , \
				name txtName -text $folder , \
				modified txtDate -data [file mtime $path]
			$t item lastchild root $item
		}

		set Vars(scriptNewDir) {
			set item [$t item create -open no]
			if {[llength $folder] == 0} { set folder [file tail $path] }
			$t item style set $item name styName modified styDate
			$t item element configure $item \
				name elemImg -image $icon , \
				name txtName -text $folder
			$t item lastchild root $item
		}
	} else {
		set Vars(scriptDir) {
			set item [$t item create -open no]
			if {[llength $icon] == 0} { set icon $::fsbox::icon::16x16::folder }
			if {[llength $folder] == 0} { set folder [file tail $path] }
			$t item style set $item name styName size stySize modified styDate
			$t item element configure $item \
				name elemImg -image $icon , \
				name txtName -text $folder , \
				modified txtDate -data [file mtime $path]
			$t item lastchild root $item
		}

		set Vars(scriptNewDir) {
			set item [$t item create -open no]
			if {[llength $folder] == 0} { set folder [file tail $path] }
			$t item style set $item name styName size stySize modified styDate
			$t item element configure $item \
				name elemImg -image $icon , \
				name txtName -text $folder
			$t item lastchild root $item
		}

		set Vars(scriptFile) {
			set mtime [file mtime $file]
			set size [{*}$Vars(sizecommand) $file $mtime]
			set valid [{*}$Vars(validatecommand) $file $size]
			if {$valid} {
				set valid 1
				set item [$t item create -open no]
				$t item style set $item name styName size stySize modified styDate
				set icon [GetFileIcon $w $file]
				$t item element configure $item \
					name elemImg -image $icon , \
					name txtName -text [file tail $path] , \
					size txtSize -text $size , \
					modified txtDate -data $mtime
				$t item lastchild root $item
			}
		}

		set Vars(scriptNewFile) {
			set item [$t item create -open no]
			$t item style set $item name styName size stySize modified styDate
			set icon [GetFileIcon $w $file]
			$t item element configure $item \
				name elemImg -image $icon , \
				name txtName -text [file tail $path]
			$t item lastchild root $item
		}
	}
}


proc ListLayout {w} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)

	$t configure -itemwidthequal no
	$t configure -wrap window
	$t configure -showheader no
	$t configure -yscrollcommand {}
	$t configure -xscrollcommand $Vars(xscrollcmd)
	grid remove $Vars(widget:yscrollbar)

	catch { $t item delete 1 end }
	foreach col [$t column list] { $t column delete $col }
	foreach sty [$t style names] { $t style delete $sty }
	foreach elm [$t element names] { $t element delete $elm }

	$t column create -tags name -steady yes

	$t element create elemImg image -image [set [namespace parent]::icon::16x16::folder]
	$t element create txtName text                                   \
		-fill [list                                                   \
			[lookupColor $Vars(selectionforeground)] {selected focus}  \
			[lookupColor $Vars(selectionforeground)] {selected hilite} \
			[lookupColor $Vars(inactiveforeground)]  {selected !focus} \
			[lookupColor $Vars(activeforeground)]    {hilite}          \
		]                                                             \
		-lines 1                                                      \
		;
	$t element create elemSel rect                                   \
		-fill [list                                                   \
			[lookupColor $Vars(selectionbackground)] {selected focus}  \
			[lookupColor $Vars(selectionbackground)] {selected hilite} \
			[lookupColor $Vars(inactivebackground)] {selected !focus}  \
			[lookupColor $Vars(activebackground)] {hilite}             \
		] 
	$t element create elemBrd border          \
		-filled no                             \
		-relief raised                         \
		-thickness 1                           \
		-background {#e5e5e5 {selected} {} {}} \
		;
	
	set s [$t style create styName]
	$t style elements $s {elemSel elemImg elemBrd txtName}
	$t style layout $s elemImg -expand ns -padx {3 0}
	$t style layout $s txtName -squeeze x -expand ns -padx {2 3}
	$t style layout $s elemSel -iexpand xy -detach yes
	$t style layout $s elemBrd -iexpand xy -detach yes

	set Vars(scriptDir) {
		set item [$t item create -open no]
		if {[llength $icon] == 0} { set icon $::fsbox::icon::16x16::folder }
		if {[llength $folder] == 0} { set folder [file tail $path] }
		$t item style set $item name styName
		$t item element configure $item name \
			elemImg -image $icon + \
			txtName -text $folder
		$t item lastchild root $item
	}

	set Vars(scriptNewDir) $Vars(scriptDir)

	set Vars(scriptFile) {
		set valid [{*}$Vars(validatecommand) $file]
		if {$valid} {
			set valid 1
			set item [$t item create -open no]
			$t item style set $item name styName
			set icon [GetFileIcon $w $file]
			$t item element configure $item name \
				elemImg -image $icon + \
				txtName -text [file tail $path]
			$t item lastchild root $item
		}
	}

	set Vars(scriptNewFile) $Vars(scriptFile)
}


proc SwitchLayout {w {layout {}}} {
	variable [namespace parent]::${w}::Vars
	variable [namespace parent]::Options

	if {[llength $layout] == 0} {
		set Vars(layout:list) [expr {!$Vars(layout:list)}]
		if {$Vars(layout:list)} {
			set tooltip DetailedLayout
			set Options(show:layout) list
			set layout details
		} else {
			set tooltip ListLayout
			set Options(show:layout) details
			set layout list
		}
		::toolbar::childconfigure $Vars(widget:layout) \
			-image [set icon::16x16::$layout] \
			-tooltip [Tr $tooltip] \
			;
	} elseif {$layout eq $Options(show:layout)} {
		return
	}
	
	[namespace parent]::busy [winfo toplevel $w]
	set t $Vars(widget:list:file)
	set selection [$t selection get]
	$t selection clear

	switch $Options(show:layout) {
		details {
			DetailedLayout $w
			$t xview moveto 0.0
			# TODO: expand columns
		}
		list {
			ListLayout $w
		}
	}

	Glob $w no
	catch { $t see 1 }
	$t activate 0
	foreach sel $selection {
		$t selection add $sel
		$t activate $sel
		$t see $sel
	}
	[namespace parent]::unbusy [winfo toplevel $w]
}


proc ColumnResized {w col} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)

	foreach id {name size modified} {
		set Vars(column:$id) [$t column width $id]
	}
}


proc GetFileIcon {w filename} {
	variable [namespace parent]::${w}::Vars

	if {$Vars(onlyexecutables)} {
		return [set [namespace parent]::icon::16x16::executable]
	}

	foreach {ext icon} $Vars(fileicons) {
		if {[string match *$ext $filename]} {
			return $icon
		}
	}

	return [set [namespace parent]::icon::16x16::document]
}


proc SortColumn {w {column ""}} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)

	if {[string length $column] == 0} {
		set column $Vars(sort-column)
		if {[$t column cget $column -arrow] eq "none"} { return }
	} else {
		set column [lindex [$t column tag names $column] 0]
		set arrow [$t column cget $column -arrow]
		if {$column eq $Vars(sort-column) || $arrow eq "none"} {
			if {$arrow eq "up"} { set order decreasing } else { set order increasing }
		} else {
			if {$arrow eq "up"} { set order increasing } else { set order decreasing }
		}
		$t column configure $Vars(sort-column) -arrow none
		set Vars(sort-column) $column
		set Vars(sort-order) $order
		switch $order {
			increasing { set arrow up }
			decreasing { set arrow down }
		}
		$t column configure $column -arrow $arrow
	}

	set dirCount [llength $Vars(list:folder)]
	set fileCount [expr {[$t item count] - 1 - $dirCount}]
	set totalCount [expr {$dirCount + $fileCount}]
	set lastDir [expr {$dirCount - 1}]

	switch [$t column cget $column -tags] {
		name {
			if {$dirCount} {
				$t item sort root -$Vars(sort-order) \
					-last [list root child $lastDir]  \
					-column $column                   \
					-nocase                           \
					;
			}
			if {$fileCount} {
				$t item sort root -$Vars(sort-order)                \
					-first [list root child [expr {$lastDir + 1}]]   \
					-last [list root child [expr {$totalCount - 1}]] \
					-column $column                                  \
					-nocase                                          \
					;
			}
		}

		size {
			if {$fileCount} {
				$t item sort root -$Vars(sort-order)                                 \
					-first [list root child [expr {$lastDir + 1}]]                    \
					-last [list root child [expr {$totalCount - 1}]]                  \
					-column $column                                                   \
					-command [namespace code [list CompSize $Vars(widget:list:file)]] \
					-column name                                                      \
					-nocase                                                           \
					;
			}
		}

		modified {
			if {$dirCount} {
				$t item sort root -$Vars(sort-order) \
					-last [list root child $lastDir]  \
					-column $column                   \
					-integer                          \
					-column name                      \
					-nocase                           \
					;
			}
			if {$fileCount} {
				$t item sort root -$Vars(sort-order)                \
					-first [list root child [expr {$lastDir + 1}]]   \
					-last [list root child [expr {$totalCount - 1}]] \
					-column $column                                  \
					-integer                                         \
					-column name                                     \
					-nocase                                          \
					;
			}
		}
	}

	if {!$Vars(multiple)} {
		foreach sel [$t selection get] {
			$t see $sel
		}
	}
}


proc CompSize {t lhs rhs} {
	set lsize [regsub -all {[^0-9]} [$t item element cget $lhs 1 txtSize -text] ""]
	set rsize [regsub -all {[^0-9]} [$t item element cget $rhs 1 txtSize -text] ""]
	return [expr {int($lsize) - int($rsize)}]
}


proc SetColumnBackground {t id stripes background} {
	if {[llength $stripes]} {
		$t column configure $id -itembackground [list $stripes $background]
	} else {
		$t column configure $id -itembackground $background
	}
}


proc FilterFiles {w files} {
	variable [namespace parent]::${w}::Vars

	set filelist {}

	# NOTE: we don't want -dictionary
	foreach entry [[namespace parent]::mySort -nocase -index 0 $files] {
		set match 0

		if {[llength $Vars(extensions)] == 0} {
			set match 1
		} else {
			set file [lindex $entry 1]

			foreach ext $Vars(extensions) {
				if {[string match *$ext $file]} {
					set match 1
				}
			}
		}

		if {$match} {
			lappend filelist $entry
		}
	}

	return $filelist
}


proc Glob {w refresh} {
	variable [namespace parent]::${w}::Vars

	if {$Vars(startup) && !$refresh} { return }
	set Vars(startup) 0
	set lookupFolder 0

	if {$refresh || ![info exists Vars(list:folder)]} {
		[namespace parent]::busy [winfo toplevel $w]

		switch $Vars(sort-order) {
			increasing { set arrow up }
			decreasing { set arrow down }
		}

		set folders {}

		switch $Vars(glob) {
			Files - Desktop {
				set filter *
				if {$Vars(showhidden)} { lappend filter .* }
				if {[catch { glob -nocomplain -directory $Vars(folder) -types d {*}$filter } folders]} {
					[namespace parent]::unbusy [winfo toplevel $w]
					return ;# may happen after umount of USB device
				}
				set folders [[namespace parent]::mySort -nocase $folders]
			}

			LastVisited - Favorites {
				variable [namespace parent]::bookmarks::Bookmarks

				set lookupFolder 1
				set attr [string tolower $Vars(glob)]
				set arrow none
				set bookmarks {}
				foreach entry $Bookmarks($attr) {
					if {$attr eq "favorites"} { set folder [lindex $entry 0] } else { set folder $entry }
					if {[file isdirectory $folder]} {
						lappend bookmarks $entry
					}
				}
				set Bookmarks($attr) $bookmarks
				foreach entry $Bookmarks($attr) {
					if {$attr eq "favorites"} { set folder [lindex $entry 0] } else { set folder $entry }
					if {[string index $folder 0] ne "." || $Vars(showhidden)} { 
						lappend folders $folder
					}
				}
			}
		}

		$Vars(widget:list:file) column configure $Vars(sort-column) -arrow $arrow

		if {[info exists Vars(button:new)]} {
			if {$Vars(glob) eq "Files"} { set state normal } else { set state disabled }
			::toolbar::childconfigure $Vars(button:new) -state $state
		}

		set Vars(list:folder) {}
		set filelist {}

		foreach folder $folders {
			set d [file tail $folder]
			if {$d ne "." && $d ne ".."} {
				lappend Vars(list:folder) $folder
			}
		}

		switch $Vars(glob) {
			Files - Desktop {
				if {$Vars(type) ne "dir"} {
					set filter *
					if {$Vars(showhidden)} { lappend filter .* }
					if {$Vars(onlyexecutables)} { set types {f x} } else { set types f }
					set files {}
					foreach file [glob -nocomplain -directory $Vars(folder) -types $types {*}$filter] {
						lappend files [list $file $file ""]
					}
					set filelist [FilterFiles $w $files]
				}
			}

			Trash {
				set filter *
				if {$Vars(showhidden)} { lappend filter .* }
				set filelist [FilterFiles $w [::trash::content $filter]]
			}
		}

		[namespace parent]::unbusy [winfo toplevel $w]
	} else {
		set filelist {}
		foreach entry $Vars(list:file) {
			set file [lindex $entry 0]
			if {[file exists $file] && [file isfile $file]} {
				lappend filelist $entry
			}
		}
	}

	set t $Vars(widget:list:file)
	foreach path $Vars(list:folder) {
		set icon {}
		set folder {}
		if {$lookupFolder} {
			if {[info exists Vars(lookup:$path)]} {
				set attr $Vars(lookup:$path)
				set icon [set [namespace parent]::icon::16x16::$attr]
				set folder [Tr [string toupper $attr 0 0]]
			} elseif {[::trash::isTrash? $path]} {
				set icon [set [namespace parent]::icon::16x16::trash]
				set folder [Tr Trash]
				if {$path ne $Vars(folder:trash)} { append folder ": " [file tail $path] }
			}
		}
		eval $Vars(scriptDir)
	}
	if {[$t item count] == 1} { set item root } else { set item "root children" }
	$Vars(widget:list:file) item tag add $item directory

	set Vars(list:file) {}
	foreach entry $filelist {
		lassign $entry file path deletion
		eval $Vars(scriptFile)
		if {$valid} { lappend Vars(list:file) $entry }
	}

	switch $Vars(glob) {
		LastVisited - Favorites {}

		default {
			if {($Vars(sort-column) ne "name" || $Vars(sort-order) ne "increasing")} {
				SortColumn $w
			}
		}
	}
}


proc InvokeFile {w args} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)

	if {[llength $args] == 2} {
		lassign $args x y
		set id [$t identify $x $y]
		if {[llength $id] == 0 || [lindex $id 0] eq "header"} { return }
		set id [lindex $id 1]
	} else {
		set id [$t item id active]
	}

	if {$id < 1} { return }
	set index [expr {$id - 1}]
	set sel [$t item order $id -visible]

	if {$sel >= [llength $Vars(list:folder)]} {
		SelectFiles $w [expr {$sel - [llength $Vars(list:folder)]}]]
		if {!$Vars(multiple) || [llength $Vars(selected:files)] == 1} {
			[namespace parent]::Activate $w yes
		}
	} elseif {$Vars(type) ne "dir"} {
		[namespace parent]::busy [winfo toplevel $w]
		[namespace parent]::VisitItem $w $t leave [expr {$sel + 1}]
		set folder [lindex $Vars(list:folder) $index]
		[namespace parent]::ChangeDir $w $folder
		[namespace parent]::unbusy [winfo toplevel $w]
		after idle [list [namespace parent]::VisitItem $w $t enter [expr {$sel + 1}]]
	} else {
		SelectFiles $w $sel
		if {!$Vars(multiple)} { [namespace parent]::Activate $w }
	}
}


proc RefreshFileList {w} {
	if {![winfo exists $w]} { return }
	variable [namespace parent]::${w}::Vars

	if {![winfo exists $w]} { return }	;# may happen due to FAM service
	if {$Vars(lock:refresh)} { return }	;# may happen due to FAM service

	set Vars(lock:refresh) 1
	set Vars(lock:selection) 1
	set t $Vars(widget:list:file)
	set item [$t item id {nearest 0 0}]
	$t item delete all
	Glob $w yes
	set n "root"
	$t xview moveto 0.0
	$t yview moveto 0.0
	set folders $Vars(selected:folders)
	set files $Vars(selected:files)
	set Vars(selected:folders) {}
	set Vars(selected:files) {}

	foreach folder $folders {
		set i [lsearch -exact $Vars(list:folder) $folder]
		if {$i >= 0} {
			set n [expr {$i + 1}]
			$t selection clear
			$t selection add $n
			lappend Vars(selected:folders) $folder
		}
	}

	foreach file $files {
		set i [lsearch -exact -index 0 $Vars(list:file) $file]
		if {$i >= 0} {
			set n [expr {$i + 1 + [llength $Vars(list:folder)]}]
			$t selection clear
			$t selection add $n
			$t activate $n
			lappend Vars(selected:files) $file
		}
	}

	set Vars(lock:selection) 0
	$t activate $n

	if {[string length $item]} { $t yview scroll [expr {$item - 1}] units }
	if {[string is integer $n]} { $t see $n }

	ConfigureButtons $w
	set Vars(lock:refresh) 0
}


#proc CurrentFileIsUsed {w} {
#	variable [namespace parent]::${w}::Vars
#
#	if {$Vars(glob) ne "Files"} { return 0 }
#	if {[llength $Vars(selected:files)] > 1} { return 0 }
#	if {[llength $Vars(isusedcommand)] == 0} { return 0 }
#	return [$Vars(isusedcommand) [file join $Vars(folder) $Vars(initialfile)]]
#}


proc ConfigureButtons {w} {
	variable [namespace parent]::${w}::Vars

	if {[llength $Vars(selected:folders)] + [llength $Vars(selected:files)] > 1} {
		set st disabled
	} elseif {	[llength $Vars(selected:folders)] + [llength $Vars(selected:files)] == 0
				|| $Vars(glob) ne "Files"} {
		set st disabled
	} else {
		set st normal
	}

	foreach what {delete rename copy} { set Vars(state:$what) $st }

	if {[llength $Vars(selected:folders)] > 0} {
		set Vars(state:copy) disabled

		if {![[namespace parent]::dirIsEmpty [lindex $Vars(selected:folders) 0]]} {
			set Vars(state:delete) disabled
		}
	}

	if {$Vars(glob) eq "Files"} { set Vars(state:new) normal } else { set Vars(state:new) disabled }
	if {$Vars(glob) eq "Trash" && [llength $Vars(selected:files)] == 1} { set Vars(state:delete) normal }

#	if {[CurrentFileIsUsed $w]} {
#		set Vars(state:delete) disabled
#		set Vars(state:rename) disabled
#	}

	foreach action {delete rename copy new} {
		if {$action ni $Vars(actions)} { set Vars(state:$action) disabled }
	}

	foreach action {delete rename copy new} {
		if {[info exists Vars(button:$action)]} {
			::toolbar::childconfigure $Vars(button:$action) -state $Vars(state:$action)
		}
	}

	if {[info exists Vars(button:custom)]} {
		if {	[llength $Vars(selected:files)] == 1
			&& [::util::fileExtension $Vars(initialfile)] in $Vars(customfiletypes)} {
			if {$Vars(glob) eq "Files"} {
				set Vars(state:custom) normal
			} else {
				set Vars(state:custom) disabled
			}
		} else {
			set Vars(state:custom) disabled
		}
		::toolbar::childconfigure $Vars(button:custom) -state $Vars(state:custom)
	}
}


proc SelectAllFiles {w} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)

	if {[$t cget -selectmode] eq "extended" && [llength $Vars(list:file)] > 0} {
		if {$Vars(type) eq "dir"} {
			if {[llength $Vars(selected:folders)] == [llength $Vars(list:folder)]} {
				set Vars(selected:folders) {}
				$t selection clear
				set Vars(initialfile) {}
				ConfigureButtons $w
			} else {
				set first 0
				set last [llength $Vars(list:folder)]
				for {set i $first} {$i < $last} {incr i} {
					if {![$t selection includes $i]} {
						lappend selection $i
						$t selection add $i
					}
				}
				SelectFiles $w $selection
			}
		} else {
			if {[llength $Vars(selected:files)] == [llength $Vars(list:file)]} {
				set Vars(selected:files) {}
				$t selection clear
				set Vars(initialfile) {}
				ConfigureButtons $w
			} else {
				set first [expr {[llength $Vars(list:folder)] + 1}]
				set last [expr {$first + [llength $Vars(list:file)]}]
				for {set i $first} {$i < $last} {incr i} {
					if {![$t selection includes $i]} {
						lappend selection $i
						$t selection add $i
					}
				}
				SelectFiles $w $selection
			}
		}
	}
}


proc SelectFiles {w selection} {
	variable [namespace parent]::${w}::Vars

	if {$Vars(lock:selection)} { return }

	set Vars(selected:folders) {}
	set Vars(selected:files) {}

	set selection [lsort -integer -unique [$Vars(widget:list:file) selection get]]

	foreach n $selection {
		if {$n <= [llength $Vars(list:folder)]} {
			set folder [lindex $Vars(list:folder) [expr {$n - 1}]]
			lappend Vars(selected:folders) $folder
			CheckDir $w $folder
			CheckFile $w
		} else {
			set file [lindex $Vars(list:file) [expr {$n - [llength $Vars(list:folder)] - 1}] 0]
			lappend Vars(selected:files) $file
			CheckDir $w
			CheckFile $w $file
		}
	}

	if {$Vars(type) eq "dir"} {
		if {[llength $Vars(selected:folders)]} {
			set Vars(initialfile) [lindex $Vars(selected:folders) 0]
		}
	} else {
		set filenames ""
		foreach file $Vars(selected:files) {
			if {$Vars(multiple) && ([llength $Vars(selected:files)] > 1 || [string first " " $file] >= 0)} {
				set delim "\""
			} else {
				set delim ""
			}
			if {[string length $filenames]} { append filenames " " }
			append filenames $delim
			append filenames [file tail $file]
			append filenames $delim
		}
		if {[string length $filenames]} {
			set Vars(initialfile) $filenames
		}
	}

	ConfigureButtons $w
}


proc CheckFile {w {file ""}} {
	if {[llength $file]} { [namespace parent]::CheckEncoding $w $file }
}


proc CheckDir {w {folder  ""}} {
	# nothing to do
}


proc TraverseFiles {w} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)
	set list $Vars(list:file)
	set Vars(list:file) {}

	foreach entry $list {
		lassign $entry file path deletion
		if {[file isfile $file]} {
			lappend Vars(list:file) $entry
			eval $Vars(scriptFile)
		}
	}
}


proc TraverseFolders {w} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)
	set list $Vars(list:folder)
	set Vars(list:folder) {}
	set icon {}

	foreach path $list {
		if {[file isdirectory $path]} {
			lappend Vars(list:folder) $path
			set folder {}
			eval $Vars(scriptDir)
		}
	}
}


proc DeleteFile {w} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)
	set sel [expr {[$t item id active] - 1}]

	if {$sel < [llength $Vars(list:folder)]} {
		set file [lindex $Vars(list:folder) $sel]
		set type folder
		set ltype folder
	} else {
		set sel [expr {$sel - [llength $Vars(list:folder)]}]
		set file [lindex $Vars(list:file) $sel 0]
		switch [file type $file] {
			link		{ set type link }
			default	{ set type file }
		}
		set ltype file
		if {[[namespace parent]::CheckIfInUse $w $file delete]} { return }
	}

	if {$Vars(delete:action) eq "restore"} {
		set i [lsearch -index 0 $Vars(list:file) $file]
		set dst [file dirname [lindex $Vars(list:file) $i 1]]
		if {![file isdirectory $dst]} {
			set reply [::dialog::question \
				-parent $w \
				-message [format [Tr OriginalPathDoesNotExist] $dst] \
				-detail [Tr DragItemAnywhere] \
				-default yes \
			]
			if {$reply eq "no"} { return }
			if {[catch { file mkdir $dst }]} {
				return [::dialog::error -parent $w -message [Tr ErrorCreate]]
			}
		}
		[namespace parent]::DoFileOperations $w restore "file://localhost/$file" $dst 1
		return
	}

	[namespace parent]::busy [winfo toplevel $w]

	if {$type eq "link"} {
		set trashIsUsable 0
		set dest [file link $file]
	} else {
		set trashIsUsable [::trash::usable?]
		if {$type eq "folder"} { set trashIsUsable 0 }
		set dest $file
	}

	set extensions {}
	if {$type eq "folder"} {
		set leader $file
	} else {
		set leader ""
		if {[llength $Vars(deletecommand)] > 0} {
			set files {}
			foreach f [{*}$Vars(deletecommand) $w $file] {
				if {[file exists $f]} {
					if {[string length $leader] == 0} { set leader [file rootname $f] }
					lappend extensions [file extension $f]
					lappend files $f
				}
			}
		} else {
			set files [list $file]
			set leader $file
		}
	}
	incr Vars(fam:lastid)

	if {[file writable $file]} { set mode w } else { set mode r }
	if {$trashIsUsable} { set which ReallyMove } else { set which ReallyDelete }
	if {$type eq "folder"} { set type empty }
	set fmt [Tr ${which}($type,$mode)]
	set msg [format $fmt [file tail $dest]]
	foreach item [$t item children root] { $t item state set $item {!hilite} }
	set reply [::dialog::question -parent $Vars(widget:main) -message $msg -default no]
	after idle [list [namespace parent]::Stimulate $w]

	if {$reply ne "yes" } {
		[namespace parent]::unbusy [winfo toplevel $w]
		return
	}

	if {$trashIsUsable} {
		set cmd [list ::trash::move $leader $extensions]
	} elseif {$ltype eq "file"} {
		set cmd [list file delete -force {*}$files]
	} else {
		set cmd [list file delete -force $file]
	}

	catch $cmd
	RefreshFileList $w
	[namespace parent]::bookmarks::LayoutBookmarks $w
	after idle [namespace code [list ResetFamId $w]]
	[namespace parent]::unbusy [winfo toplevel $w]

	if {$file in $Vars(list:$ltype)} {
		set action [string toupper $Vars(delete:action) 0 0]
		set msg [format [Tr ${action}Failed] $file]
		::dialog::error -parent $Vars(widget:main) -message $msg
	}
}


proc ResetFamId {w} {
	if {![winfo exists $w]} { return }
	variable [namespace parent]::${w}::Vars
	set Vars(fam:lastid) $Vars(fam:currentid)
}


proc SetDeleteAction {w action} {
	variable [namespace parent]::${w}::Vars

	if {![info exists Vars(button:delete)]} { return }

	set Vars(delete:action) $action

	set name [string toupper $action 0 0]
	::toolbar::childconfigure $Vars(button:delete) \
		-image [set icon::16x16::icon$name] \
		-tooltip [Tr $name] \
		;
}


proc GetCurrentSelection {w} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)
	set sel [$t item id active]
	set i [expr {$sel - 1}]
	if {$i < [llength $Vars(list:folder)]} {
		return [list folder $sel [lindex $Vars(list:folder) $i]]
	}
	set i [expr {$i - [llength $Vars(list:folder)]}]
	return [list file $sel [lindex $Vars(list:file) $i 0]]
}


# proc MoveFile {w m} {
# 	variable [namespace parent]::${w}::Vars
# 
# 	lassign [GetCurrentSelection $w] type _ file
# 	if {$type eq "file" && [[namespace parent]::CheckIfInUse $w $file move]} { return }
# 	set filter *
# 	if {$::tcl_platform(platform) eq "unix" && $Vars(showhidden)} { lappend filter .* }
# 	set dir [file dirname $file]
# 	set subdirs [glob -nocomplain -tails -dir $dir -types d {*}$filter]
# 	foreach dir $subdirs {
# 		if {$dir ne "."} {
# 		}
# 	}
# }


proc RenameFile {w} {
	variable [namespace parent]::${w}::Vars

	lassign [GetCurrentSelection $w] type sel Vars(edit:file)
	if {$type eq "folder" || ![[namespace parent]::CheckIfInUse $w $Vars(edit:file) rename]} {
		OpenEdit $w $sel rename
	}
}


proc DuplicateFile {w} {
	variable [namespace parent]::DuplicateFileSizeLimit
	variable [namespace parent]::${w}::Vars

	lassign [GetCurrentSelection $w] type _ file
	if {$type eq "folder"} { return }
	if {![file exists $file]} {
		set msg [format [Tr FileHasDisappeared] [file tail $file]]
		::dialog::error -parent $Vars(widget:main) -message $msg
		return
	}
	set Vars(edit:file) $file
	set dir [file dirname $file]
	set newFile [file join $dir [format [Tr CopyOf] [file tail $file]]]
	while {[file exists $newFile]} {
		set newFile [file join $dir [format [Tr CopyOf] [file tail $newFile]]]
	}
	if {[llength $Vars(duplicatecommand)]} {
		set files [{*}$Vars(duplicatecommand) $file $newFile]
	} else {
		set files [list $file $newFile]
	}
	set size 0
	foreach {f g} $files {
		if {[file exists $f]} {
			if {[file exists $g]} {
				set msg [format [Tr CannotCopy] [file tail $g]]
				::dialog::error -parent $Vars(widget:main) -message $msg
				return
			}
			incr size [file size $f]
		}
	}
	if {$size > $DuplicateFileSizeLimit} {
		set msg [Tr ReallyDuplicateFile]
		set detail [format [Tr ReallyDuplicateDetail] [[namespace parent]::MakeFileSize $size]]
		set reply [::dialog::question -parent $Vars(widget:main) -message $msg -detail $detail]
		if {$reply ne "yes"} { return }
	}

	set t $Vars(widget:list:file)
	$t item delete all
	TraverseFolders $w
	if {[$t item count] == 1} { set item root } else { set item "root children" }
	$t item tag add $item directory
	TraverseFiles $w
	set path $file
	eval $Vars(scriptNewFile)
	OpenEdit $w [expr {[llength $Vars(list:folder)] + [llength $Vars(list:file)] + 1}] duplicate
}


proc NewFolder {w} {
	variable [namespace parent]::${w}::Vars

	lassign [GetCurrentSelection $w] _ _ Vars(edit:file)
	set t $Vars(widget:list:file)
	$t item delete all
	TraverseFolders $w
	set icon [set [namespace parent]::icon::16x16::folder]
	foreach folder [list [Tr NewFolder]] $Vars(scriptNewDir)
	$t item tag add "root children" directory
	TraverseFiles $w
	OpenEdit $w [expr {[llength $Vars(list:folder)] + 1}] new
}


proc CallCustomCommand {w} {
	variable [namespace parent]::${w}::Vars

	lassign [GetCurrentSelection $w] _ _ file
	{*}$Vars(customcommand) [winfo toplevel $w] $file
	RefreshFileList $w
	[namespace parent]::bookmarks::LayoutBookmarks $w
}


proc OpenEdit {w sel mode} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)
	$t selection clear
	foreach item [$t item children root] { $t item state set $item {!hilite} }
	$t see $sel

	set e [::TreeCtrl::EntryExpanderOpen $t $sel 0 txtName 0 [namespace code [list SelectFileName $w]]]
	set vcmd { return [::fsbox::validateCharacters %P] }
	$e configure                \
		-validate key            \
		-validatecommand $vcmd   \
		-invalidcommand { bell } \
		;
	set Vars(edit:active) 1
	set Vars(edit:sel) $sel
	set Vars(edit:mode) $mode
	set Vars(edit:accept) 0
	::TreeCtrl::TryEvent $t Edit begin [list I $sel C 0 E txtName]
}


proc SelectFileName {w e file} {
	variable [namespace parent]::${w}::Vars

	set end -1

	foreach ext $Vars(extensions) {
		if {[string match *$ext $file]} {
			set end [max $end [expr {[string length $file] - [string length $ext]}]]
		}
	}

	if {$end == -1} { set end end }
	$e selection range 0 $end
	$e icursor $end
}


proc EditAccept {w} {
	variable [namespace parent]::${w}::Vars
	set Vars(edit:accept) 1
}


proc FinishEdit {w} {
	variable [namespace parent]::${w}::Vars

	set t $Vars(widget:list:file)
	set sel $Vars(edit:sel)
	set Vars(edit:active) 0

	if {$Vars(edit:accept)} {
		set name [string trim [$t item element cget $sel 0 txtName -text]]
		incr Vars(fam:lastid)

		switch $Vars(edit:mode) {
			rename		{ set selFile [FinishRenameFile $w $sel $name] }
			duplicate	{ set selFile [FinishDuplicateFile $w $sel $name] }
			new			{ set selFile [FinishNewFolder $w $sel $name] }
		}
	} else {
		set selFile $Vars(edit:file)
	}

	RefreshFileList $w
	if {[llength $Vars(fam)]} {
		set Vars(fam:lastid) $Vars(fam:currentid)
	}

	if {[string length $selFile]} {
		set k [lsearch -exact $Vars(list:folder) $selFile]
		if {$k == -1} {
			set k [lsearch -exact -index 0 $Vars(list:file) $selFile]
			if {$k >= 0} { set k [expr {[llength $Vars(list:folder)] + $k}] }
		}
		if {$k >= 0} {
			incr k
			set t $Vars(widget:list:file)
			$t selection clear
			$t selection add $k
			$t activate $k
			$t see $k
		}
	}

	after idle [list [namespace parent]::Stimulate $w]
}


proc FinishRenameFile {w sel name} {
	variable [namespace parent]::${w}::Vars

	set name [string trim $name]
	set t $Vars(widget:list:file)
	$t selection clear
	set i [expr {$sel - 1}]
	if {$i < [llength $Vars(list:folder)]} {
		set type folder
	} else {
		set i [expr {$i - [llength $Vars(list:folder)]}]
		set type file
	}
	set oldName [lindex $Vars(list:$type) $i 0]
	if {[string length $name] == 0} { return $oldName }
	set newName [file join $Vars(folder) $name]
	if {$oldName eq $newName} { return $oldName }
	if {![[namespace parent]::CheckPath $w $name]} { return $oldName }

	if {[file exists $newName]} {
		::dialog::error -parent $Vars(widget:main) -message [format [Tr CannotRename] $name]
		return $oldName
	}

	set ok 1
	set files {}
	if {$type eq "file" && [llength $Vars(renamecommand)] > 0} {
		set files [{*}$Vars(renamecommand) $w $oldName $newName]
		if {[llength $files] == 0} {
			set ok 0
			set new $newName
		} else {
			set undoList {}
			foreach {old new} $files {
				if {[file exists $old]} {
					if {[catch {file rename $old $new}]} {
						foreach {f g} $undoList { catch { file rename $g $f } }
						set ok 0
						break
					} else {
						lappend undoList $old $new
					}
				}
			}
		}
	} elseif {[catch {file rename $oldName $newName}]} {
		set old [file tail $oldName]
		set new [file tail $newName]
		set ok 0
	}
	if {$ok} {
		lset Vars(list:$type) $i $newName
	} else {
		if {$type eq "file" && [llength $files] == 0} {
			set msg [format [Tr InvalidFileExt] [file tail $new]]
		} else {
			set msg [Tr ErrorRenaming($type)]
			set msg [string map [list %old [file tail $old] %new [file tail $new]] $msg]
		}
		::dialog::error -parent $Vars(widget:main) -message $msg
		return $oldName
	}

	return $newName
}


proc FinishDuplicateFile {w sel name} {
	variable [namespace parent]::${w}::Vars

	set name [string trim $name]
	set srcFile $Vars(edit:file)
	set dir [file dirname $srcFile]
	set dstFile [file join $dir $name]

	if {![[namespace parent]::CheckPath $w $name]} { return $srcFile }

	if {[llength $Vars(duplicatecommand)]} {
		set fileList [{*}$Vars(duplicatecommand) $srcFile $dstFile]
	} else {
		set fileList [list $srcFile $dstFile]
	}

	set files {}
	foreach {f g} $fileList {
		if {[file exists $f]} {
			while {[file type $f] eq "link"} {
				set f [file readlink $f]
			}
		}
		lappend files $f $g
	}

	if {[llength $files] == 0} {
		set msg [format [Tr InvalidFileExt] $name]
		::dialog::error -parent $Vars(widget:main) -message $msg
		return $srcFile
	}

	foreach {_ f} $files {
		if {[file exists $f]} {
			::dialog::error -parent $Vars(widget:main) -message [format [Tr CannotCopy] [file tail $f]]
			return $srcFile
		}
	}

	set dlg [tk::toplevel $w.wait]
	wm withdraw $dlg
	set top [tk::frame $dlg.top -border 2 -relief raised]
	pack $top
	tk::message $top.msg -aspect 250 -text [Tr WaitWhileDuplicating]
	pack $top.msg -padx 5 -pady 5
	wm resizable $dlg no no
	wm transient $dlg [winfo toplevel $w]
	::util::place $dlg -parent [winfo toplevel $w] -position center
	update idletasks
	[namespace parent]::makeFrameless $dlg
	wm deiconify $dlg
	::ttk::grabWindow $dlg
	[namespace parent]::busy $dlg

	set newFiles {}
	foreach {f g} $files {
		if {[file exists $f]} {
			if {[catch { file copy $f $g }]} {
				::ttk::releaseGrab $dlg
				destroy $dlg
				set msg [format [Tr CopyFailed] [file tail $f]]
				foreach f $newFiles { catch { file delete -force $f } }
				::dialog::error -parent $Vars(widget:main) -message $msg
				[namespace parent]::unbusy $dlg
				return $srcFile
			} else {
				catch { ::platform::sys::touch $g }
				lappend newFiles $g
			}
		}
	}

	::ttk::releaseGrab $dlg
	[namespace parent]::unbusy $dlg
	destroy $dlg

	return $dstFile
}


proc FinishNewFolder {w sel name} {
	variable [namespace parent]::${w}::Vars

	set name [string trim $name]
	if {[string length $name] == 0} { return "" }

	set folder [file join $Vars(folder) $name]
	if {[file exists $folder]} {
		::dialog::error -parent $Vars(widget:main) -message [format [Tr CannotCreate] $name]
	} elseif {[catch {file mkdir $folder}]} {
		::dialog::error -parent $Vars(widget:main) -message [Tr ErrorCreate]
		RefreshFileList $w
	} else {
		$Vars(widget:list:file) item element configure $sel 0 txtName -text $name
		lappend Vars(list:folder) $folder
		set t $Vars(widget:list:file)
		$t selection clear
		$t selection add $sel
		$t see $sel
	}

	return ""
}


proc SetTooltip {w which folder} {
	variable [namespace parent]::${w}::Vars
	variable [namespace parent]::Options

	switch $folder {
		Favorites - LastVisited - Desktop - Trash - Download {
			set folder [Tr $folder]
		}

		default {
			if {$Options(tooltip:shorten-paths)} {
				# NOTE: We are shortening the (display of) file path. This is a bit experimental.
				set parts [file split $folder]
				set k [expr {[llength $parts] - 1}]
				set length 0
				set count 0

				while {$k >= 0 && $length + [string length [lindex $parts $k]] < 30} {
					incr length [string length [lindex $parts $k]]
					incr length 1
					incr count
				}
				set count [expr {max(1, $count)}]

				if {$count + 2 < [llength $parts]} {
					set parts [lrange $parts [expr {[llength $parts] - $count - 1}] end]
					set folder "\u2026[file join {*}$parts]"
				}
			}
		}
	}

	set Vars(tip:[string tolower $which]) [format [Tr $which] $folder]
}


proc Undo {w} {
	variable [namespace parent]::${w}::Vars

	if {$Vars(undo:current) >= 1} {
		set folder [lindex $Vars(undo:history) $Vars(undo:current)]
		incr Vars(undo:current) -1
		[namespace parent]::ChangeDir $w [lindex $Vars(undo:history) $Vars(undo:current)] 0
		if {$Vars(undo:current) == 0} {
			::toolbar::childconfigure $Vars(button:backward) -state disabled
			set Vars(tip:backward) ""
		} else {
			SetTooltip $w Backward [lindex $Vars(undo:history) [expr {$Vars(undo:current) - 1}]]
			::toolbar::childconfigure $Vars(button:backward) -tooltip $Vars(tip:backward)
			after idle [[namespace parent]::tooltip show $Vars(button:backward) $Vars(tip:backward)]
		}
		SetTooltip $w Forward $folder
		::toolbar::childconfigure $Vars(button:forward) -state normal -tooltip $Vars(tip:forward)
	}
}


proc Redo {w} {
	variable [namespace parent]::${w}::Vars

	if {$Vars(undo:current) < [llength $Vars(undo:history)] - 1} {
		set folder [lindex $Vars(undo:history) $Vars(undo:current)]
		incr Vars(undo:current)
		[namespace parent]::ChangeDir $w [lindex $Vars(undo:history) $Vars(undo:current)] 0
		if {$Vars(undo:current) == [llength $Vars(undo:history)] - 1} {
			::toolbar::childconfigure $Vars(button:forward) -state disabled
			set Vars(tip:forward) ""
		} else {
			SetTooltip $w Forward [lindex $Vars(undo:history) [expr {$Vars(undo:current) + 1}]]
			::toolbar::childconfigure $Vars(button:forward) -tooltip $Vars(tip:forward)
			after idle [[namespace parent]::tooltip show $Vars(button:forward) $Vars(tip:forward)]
		}
		SetTooltip $w Backward $folder
		::toolbar::childconfigure $Vars(button:backward) -state normal -tooltip $Vars(tip:backward)
	}
}


proc PopupMenu {w x y} {
	variable [namespace parent]::${w}::Vars
	variable [namespace parent]::Options

	set t $Vars(widget:list:file)
	set id [$t identify $x $y]
	if {[llength $id] > 0 && [lindex $id 0] eq "header"} { return }
	foreach item [$t item children root] { $t item state set $item {!hilite} }

	set m $w.menu
	if {[winfo exists $m]} { destroy $m }
	menu $m -tearoff false -disabledforeground black

	set count 0

	if {$Vars(glob) eq "Files" || $Vars(glob) eq "Trash"} {
		set sel [$t item id active]
		if {$sel in [$t selection get]} {
			incr sel -1
			if {$sel >= [llength $Vars(list:folder)]} {
				set file [lindex $Vars(list:file) [expr {$sel - [llength $Vars(list:folder)]}] 0]
			} else {
				set file [lindex $Vars(list:folder) $sel]
			}
			$m add command                                                     \
				-label [file tail $file]                                        \
				-background [lookupColor $Options(menu:headerbackground)]       \
				-foreground [lookupColor $Options(menu:headerforeground)]       \
				-activebackground [lookupColor $Options(menu:headerbackground)] \
				-activeforeground [lookupColor $Options(menu:headerforeground)] \
				-font TkHeadingFont                                             \
				-state disabled                                                 \
				;
			$m add separator

			if {$Vars(state:delete) eq "normal"} {
				incr count
				if {$Vars(delete:action) eq "restore"} {
					set name Restore
				} elseif {[::trash::usable?]} {
					set name MoveToTrash
				} else {
					set name Delete
				}
				$m add command                                    \
					-compound left                                 \
					-image [set icon::16x16::$Vars(delete:action)] \
					-label " [Tr $name]"                           \
					-command [namespace code [list DeleteFile $w]] \
					;
			}
		}
	}

	if {$Vars(glob) eq "Files"} {
		set sel [$t item id active]
		if {$sel in [$t selection get]} {
#			if {![CurrentFileIsUsed $w]} {
				if {$Vars(state:rename) eq "normal"} {
					incr count
					$m add command                                    \
						-compound left                                 \
						-image $icon::16x16::modify                    \
						-label " [string map {& {}} [Tr Rename]]"      \
						-command [namespace code [list RenameFile $w]] \
						;
				}
#				incr count
#				$m add cascade                                                \
#					-compound left                                             \
#					-image [set [namespace parent]::icon::16x16::action(move)] \
#					-label " [Tr Move]"                                        \
#					-command [namespace code [list MoveFile $w $m]]            \
#					;
#			}
			if {$Vars(state:copy) eq "normal"} {
				incr count
				$m add command                                       \
					-compound left                                    \
					-image $icon::16x16::duplicate                    \
					-label " [Tr Duplicate]"                          \
					-command [namespace code [list DuplicateFile $w]] \
					;
			}
			if {	[llength $Vars(customcommand)]
				&& [llength $Vars(customtooltip)]
				&& $Vars(state:custom) eq "normal"
				&& [::util::fileExtension $file] in $Vars(customfiletypes)} {
				incr count
				$m add command                                           \
					-compound left                                        \
					-image [lindex $Vars(customicon) 0 0]                 \
					-label " $Vars(customtooltip)"                        \
					-command [namespace code [list CallCustomCommand $w]] \
					;
			}
		}
		if {$Vars(state:new) eq "normal"} {
			incr count
			$m add command                                   \
				-compound left                                \
				-image $icon::16x16::folder_add               \
				-label " [Tr NewFolder]"                      \
				-command [namespace code [list NewFolder $w]] \
				;
		}
	}

	if {$count > 0} { $m add separator }

	set count 0
	if {[string length $Vars(tip:backward)]} {
		$m add command                              \
			-compound left                           \
			-image $icon::16x16::backward            \
			-label " $Vars(tip:backward)"            \
			-command [namespace code [list Undo $w]] \
			;
		incr count
	}
	if {[string length $Vars(tip:forward)]} {
		$m add command                              \
			-compound left                           \
			-image $icon::16x16::forward             \
			-label " $Vars(tip:forward)"             \
			-command [namespace code [list Redo $w]] \
			;
		incr count
	}
	if {$count} { $m add separator }
	set sub [menu $m.layout -tearoff false]
	$m add cascade -menu $sub -label " [Tr Layout]"
	set text " [Tr DetailedLayout]"
	$sub add radiobutton                                     \
		-compound left                                        \
		-image $icon::16x16::list                             \
		-label $text                                          \
		-variable [namespace parent]::Options(show:layout)    \
		-command [namespace code [list SwitchLayout $w list]] \
		-value details                                        \
		;
	[namespace parent]::configureRadioEntry $sub
	set text " [Tr ListLayout]"
	$sub add radiobutton                                        \
		-compound left                                           \
		-image $icon::16x16::details                             \
		-label $text                                             \
		-variable [namespace parent]::Options(show:layout)       \
		-command [namespace code [list SwitchLayout $w details]] \
		-value list                                              \
		;
	[namespace parent]::configureRadioEntry $sub
	if {$::tcl_platform(platform) eq "unix"} {
		if {$Vars(showhidden)} { set ipref "" } else { set ipref "un" }
		if {$Vars(type) eq "dir"} { set var ShowHiddenDirs } else { set var ShowHiddenFiles }
		$m add checkbutton                                      \
			-compound left                                       \
			-image [set icon::16x16::${ipref}locked]             \
			-label [Tr $var]                                     \
			-command [namespace code [list SwitchHidden $w]]     \
			-variable [namespace parent]::${w}::Vars(showhidden) \
			;
		[namespace parent]::configureCheckEntry $m
	}

	set Vars(edit:active) 1
	tk_popup $m {*}[winfo pointerxy $w]
	bind $m <<MenuUnpost>> [list [namespace parent]::Stimulate $w]
}


proc Inspect {w mode args} {
	variable [namespace parent]::${w}::Vars

	set tl [winfo toplevel $w]

	if {$mode eq "show"} {
		set t $Vars(widget:list:file)
		lassign $args x y
		set id [$t identify $x $y]
		if {[llength $id] == 0} { return }
		if {[lindex $id 0] eq "header"} { return }
		set index [expr {[lindex $id 1] - 1}]
		switch $Vars(glob) {
			LastVisited - Favorites {
				set path [lindex $Vars(list:folder) $index]
				{*}$Vars(inspectcommand) $tl $path
			}
			Trash {
				if {$index >= [llength $Vars(list:folder)]} {
					set index [expr {$index - [llength $Vars(list:folder)]}]
					lassign [lindex $Vars(list:file) $index] file path date
				} else {
					set file [lindex $Vars(list:folder) $index]
					set path ""
					set date ""
				}
				{*}$Vars(inspectcommand) $tl $Vars(folder) $file $path $date
			}
			default {
				if {$index >= [llength $Vars(list:folder)]} {
					set index [expr {$index - [llength $Vars(list:folder)]}]
					set file [lindex $Vars(list:file) $index 0]
				} else {
					set file [lindex $Vars(list:folder) $index]
				}
				{*}$Vars(inspectcommand) $tl $Vars(folder) $file
			}
		}
	} else {
		{*}$Vars(inspectcommand) $tl
	}
}


proc HandleDropEvent {w action types actions} {
	variable [namespace parent]::${w}::Vars

	if {[string length $Vars(folder)] == 0} { return refuse_drop }
	if {"ask" ni $actions || "copy" ni $actions} { return refuse_drop }
	if {$Vars(drag:active)} { return refuse_drop }

	switch $action {
		enter		{ return ask }
		leave		{ return ask }
		default	{ return [[namespace parent]::AskAboutAction $w $Vars(folder) $action $actions] }
	}
}


proc HandleDragEvent {w src types x y} {
	variable [namespace parent]::${w}::Vars

	set Vars(drag:active) 1
	set Vars(drag:private) 0
	set Vars(drag:trash) 0
	set cursor {}
	set allowedActions {copy move link ask private}
	lassign [GetCurrentSelection $w] type _ file

	if {$type eq "folder"} {
		set Vars(drag:private) 1
		set files [list $file]
		set actions {private}
		foreach {extensionList cursors} $Vars(filecursors) {
			if {"folder" in $extensionList} { set cursor $cursors }
		}
	} else {
		if {$Vars(glob) eq "Trash"} {
			set Vars(drag:trash) 1
			set actions {private}
		} else {
			set actions {copy move link ask}
		}
		set files {}
		set ext [::util::fileExtension $file]

		if {[string length $Vars(deletecommand)]} {
			foreach f [{*}$Vars(deletecommand) $w $file] {
				if {[file exists $f]} { lappend files $f }
			}
		} else {
			lappend files $file
		}

		foreach {extensionList cursors} $Vars(filecursors) {
			if {$ext in $extensionList} { set cursor $cursors; break; }
		}
	}

	if {[llength $cursor] == 2} {
		::tkdnd::set_drag_cursors $src \
			{copy move link ask private} [lindex $cursors 0] \
			refuse_drop [lindex $cursors 1] \
			;
	}

	if {[llength $Vars(isusedcommand)] > 0 && [$Vars(isusedcommand) $file]} {
		set i [lsearch $actions move]
		if {$i >= 0} { set actions [lreplace $actions $i $i] }
	}

	return [list $actions DND_Files [[namespace parent]::toUriList $files]]
}


proc HandleDragDropgEvent {w src currentAction} {
	return $currentAction
}


proc FinishDragEvent {w src currentAction} {
	variable [namespace parent]::${w}::Vars

	set Vars(drag:active) 0
	set Vars(drag:private) 0
	::tkdnd::set_drag_cursors $src
}


namespace eval icon {
namespace eval 16x16 {

set forward [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABAUlEQVR4nLWT
	u0oDURCG/5lzRNA+D2FhIiExTTwYxVZBptCXGba1z0PIImJl6yGdoChCWvv10oiY4O4eC6MsgZD7
	X00xfPPPDVi2RMRAlecnTQmhv+rVXWlXm0d1AHDO2eHE0dRBRQLKZnWtU3aHFe99OgyhYiwi/8Ak
	SQgAXkolXn/nayJufvV7jafO5b2ImDiOs2laQn3v5Ly2f/q2uXO8NbD461BVOYqivNKSDct8FrLM
	AgQEEAghBDBRyEMOy4ZbAH2EPD24u7m4VVVawHrmbaGQM9MQi4CiCKok3S49v8KzWan1vz+3H/3V
	g3POeu/TcY4nPqTJNes/LO6ZRugHVSxqCLgLn+MAAAAASUVORK5CYII=
}]

set backward [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABBElEQVR4nLVT
	sUoDQRB9s3ucRrD0GjvLFCbh8BqJq6BFOiVskR+xXfYj/Ir5A4vAIYIIgpVfIWiXwr0dC43JgQfx
	Dl+1xcx7b97MAv8G55S1VrftVq2FjTEJAOTjyyI/szdrLui3+pqSMSYpyzIMj68GemvnDoLRl6Fm
	Rz+s1lrNzNXhyXS0naYPArl/S94n+4tFBQBZlsmylpkjAFnRfCsMjB0WF7PXo/MZbzoyOeeU917y
	02lBKrkFZDdWcU4KQYQUESIEBIIAAtI6hBivn+f84pxT7dOuocsIy0fbEGu7XV9j2us9VuHj6WAP
	Y+73Bd4Lask34K+H1IAOp7zi6PSZNscn2K1vEEjXrzIAAAAASUVORK5CYII=
}]

set delete [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAA6klEQVR4nK1T
	223CQBCc8OgEZi3tpwtwFfRg+MB2UmAaoAJzDl9JCUgYieUDr2TicHEU5sva8c7N7N4Bz4QBEwOm
	EX5qwGSU0JjagGzIdRApAOA9y2bO+/eHyLYm1wNBtx1EilbV9uQrAFiWzXZpOgeAmqzOqhbIEgBs
	tbqP6opBpDiqWtOJeHNXq6Jx3Gogy9OtYXMQydue4ODk73DLYbHIP5PEvpLEGnLT5/p4ONkL8NLZ
	HQ+PUJPVSdUOt63krartl8u3aITYEANZRofoa6zJsu39uEvT+ag1/vsiPYrzW+3Hxqc8pr/gCoUk
	g/Z3di5DAAAAAElFTkSuQmCC
}]

set restore [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACgklEQVR4nI2T
	T0gUYRjGn/ebmZ1m2bWs3IQQzEu04UFHcNmUKfqD4PbPmlNE4EHoEHjoUHQQw6hTBB0CCYOg05Jg
	ZCyF0JCKiFuEtNEhDaRILTR3ct2Z2Xk7uMpKgj6n73sPv+993+d7gKJM05QAEAAyDEMunte0WW1r
	6YlEUNcTwY3VLlF6Wyfqxy8c/eWFxqrxzbNF5XUivsLMNWAwSHwFcV/uJz/MZJLOKqTbXwfE4+3h
	vLq0CB9dkESbJMl1nus+BWGEmAlEzUJIl0CYXM7nWj+9G5hZgxAA1Da1liuy9lmSlL0++yOS/ef0
	+HhqqbTVhqa2GtoReMPMK/Jfv2FsLJkHwDIACElmIooIWSbfWdG8YLhHTyRuhLJZBwBs+yBNDPdO
	1cXPNMtacMbRuBPAXcMwZAIAXe9Q/PDCHYlwgEEhBn+npfKr6XSvWxyTo1EzkMkknXrDfEyEc2kj
	GkF3N2/blqhpBirm5nxb7DsF8IMKNVubSqXyBAAtLS3qfD48CVBnyJ99PR+JiEwy6WwHLAOgVGOj
	q1uZPUDhvGVZr6JRM1BiM+t6h8JlC48ItJ/AdoExLbLlt9LpXpcMw5Aty/Lqj128KQm5x8stV30Y
	ffFD1zuUUOgLA4AdDgfY1u4RUVwJqLrrrLDnO7s/WgOLVHyFYjFT9YKUJiFUZufkxFD/VGmr+glz
	JxXoJUlSrOC5v10vd2hyeHChuMTVT3G4+WxVUNUGAar1C94z+P4wiBigI5KiXPY9932BC/2CxG01
	X7ZrdLQvW+LCKiQaNQNaJV0Dox3gGjCIBE0z8CRUmL0PVMu2bMfSQ8/fbrLTjUGJxUzt/zBtra3i
	TMXoAwD+Ae4CAvW2gNWkAAAAAElFTkSuQmCC
}]

set modify $::fsbox::bookmarks::icon::16x16::modify

set duplicate [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB8ElEQVR4nKWS
	v2sUQRTHP2929hALLeTOzkZttNHbP+AuUQhqpTixsxG0CYj+AyKCTRprEUEEBZeQRlBBxLUK4pEu
	IBJBtAqRNCdJuN35WuydLoEI6oM3zZv3/THfgf8sAyyE4FbXueHMTUlREq5xR+ZIDPdRlbszKJ58
	r9cQgAO0us7NNG3NE2Mq0QI8SHVjimxjzGGju2AKIaRj8vrI+uEVwOBtPrOb1Gz6fBfn96ZDBktL
	+WbTAtnU7HNJrcNtznze4BjRPQKdRLWC2oh+yKxyzrUkPd48oLmVPB/5eiYHkOd51e1ffOqc0kq6
	bFIEMDNFs8RBFavY9ml6b8/66BMw7xtvNQJwzh2PZXVp+d3Cs93sdPvhnBmndgCMYSTJaPV6Pd/p
	dBxQNcbJ2tpaHBoRrJykMInEJm1mKoqiBKo8z381UBVFUSJMkjUBUqGtMdBflaOm/eJ9On3i9IWj
	QlvOzP1pSWOVAB4gUXlb+EM+pkekuC2LZQghAZIQQnM3gVuCldEkOQ/wvlj8Bsz0ej0/dJ39iPbE
	8w7yCsDc7EGkr2P1AFiWXfWDwf1Rdyo88D69Upaj1yaiwKz+02ZGhVnb+zSryq2zH94svLAGuoHI
	smte+zauO7N+jNF+cwgwc4kbVmV8uFzkLxsC/qkM4CdBquXi2ej5wgAAAABJRU5ErkJggg==
}]

set folder_add [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACdUlEQVR4nI1T
	TUhUYRQ9537vjeHgmFZWSJSLCinUZmwZb4ykiCACJyKqpauKlu0eLoP2kSvbubCCilb9Tct0HJAw
	WoRGO/EHZ6Rm3nvfd1voyCAJ3c1dfPcczrnnfkCjwlDwv9U0y6auAHD2wo1Ba22eyl5A9289Lyv1
	mzHm0/S7yZlmDMMwlLGxMTcwdL3fE3kmYvqTOKoQugBgdWu2U4Eez/czztk5q8nt8ofnc2EYCgEw
	lxv10La6SGN+WU1GM3Z5vlgsJs2qgyDw1qXzlCepp2rtEVQ7j5VK44kAUHSstSrZpU5rhjC7Wfek
	RdRpTckudKy1AlAPAJI4oid+FeQZwp+tSlcllx9ZALiyCdV9VbLHABklqlRUkjgiAHgA0PKn7mw6
	1a7O3VFn58U3l9TxBKAHNgmkTMPJxMVvReU0gIl0rHabwPNSakGhoj7zeaoMoLybjWxQyHop30e9
	vkkNAEkmokJrMHw4mC8EudyV1n+BC4WCcQZfbBw97u5u+b19B/3B1b2epBYIEsJ2dbqu6hYJrihg
	jecdti6emv0wNdaIvUEqALDlp806vYs4yVLwiJQyiD8k6gRLVJkOAXldnJ/P5q9fbCjyGkwkjUOy
	Uf78Ytcd+OcL3QZy0tmkp2/4Vhqo1wiAQRCYDXb9oDFr1kX3JR3NlN68+d0A9g3fSvtJfYZijqtL
	HEgSTBS4vPOUJ0RkwMbxOogFUCpw9vv6no17mVomL4ZH1donCoxT+N5GKHKnzOzQzRyZ5FW1V8hD
	qvoTlY4HpdJ4DAC5/Ih1tNfKH1++2k4BwOYXbdruvyJcWlrihjl4zkb6td0srRWLn+xf2Colj6l8
	erUAAAAASUVORK5CYII=
}]

set details [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACP0lEQVR4nJ2T
	P0hWURjGf+85936aqZliQVANWYGDkR9BtKhIS0RBeCMaLYiGaAqCBHNoaoimarCghqT7NSRtIfYt
	FcaXOdhQS7Mhn4VZ3733nLfhqphJUM90/vA+73Oe57wCAMMGRjy/IT+LosjOzc0J61Au93oY8asX
	XV1HN9fv2GYB3JevWaXyfGl90UYQgGJPNGDD8E7m0haAwNoFl3KxUh4rFftOHRMptKo6r6oiImrC
	QEiT928nn84GACoMOnXz6vUSgDN6HePPAyWwt0XoUCWvhkxUTIa9CVwNAETEq3Mfp8ulMYDu3oGz
	IiYEqEzGe9erPnJisHFqfOd3gAAA1VDE2AM9J1tyQtMAuafFvugeyC5Fa9YGBe/SsVfj9x+iCAIG
	QA1TYV19vzWFeWsK82Ghrl+RNzm3BgghSgEkRCUEJDodmVUFTW5uZKm2/YUgjQAuqS3Kt62vAd69
	LJ1b73wURTbu7NRVgsXF/SJNVUH+iHtDxHHsVtZ5Cs3V4bBu07Wk9sMD2EK9cc3VG8BQd+/AqBiz
	G/WZqhggs0EYZC55PD1ZemAARDmU1n5OOJ+0OZ+0pUltQtDDywllKCkqqQgJoGvV5CmIpKq+NlN+
	trAc49KaGC/87TnBstNGrO042DNwBkCs3Yd3nwGKfdEnY2yH91lqg0KYpcmtPe1yZRbshzhOcgLc
	aCD2rhp5BGDEVL33Q3kPd1nVtoI69WqMmpk4fuJY/iirtheLxxts+5YA/mOY/mWcV8Z4Zf8LypIB
	yW+EiKkAAAAASUVORK5CYII=
}]

set list [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAApUlEQVR4nGNg
	oBAwIrNDQ0OZVq9e/Zehvp4p9No1Rpy6GBgYVq9e/ZdSyyG21tfXMzU2Nv4zsQs2/MfEnHPuwKpk
	Q8eQRBZm1si/f/78YWRkYIKr/s/wn4GRiYWB4d89hk+COWfPzvrNgjCLlYGR4S+ms/+jePM/VZxN
	VUA4DBgYmJHU/0MPA0QAMbAyMDL8xxt1gxNQHAaE0wEjUtzTIhUMfGYCAC9DXhyKKN+6AAAAAElF
	TkSuQmCC
}]

set locked [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACTElEQVR4nI1T
	v08UQRh938zu7QkUF0wMCR0Sm9MYWYGOXU7sNJrIYkgsDaXR3kjEP8DeaGwMzcUCsdICzhBiwZEI
	SCUXSmMhmIPjbnfm+yzu9nIIJL5kksm8982878cAp4P+8+xMoQwF925p7T4AGNbad+ul9x9TrlOs
	joXOzioA4oeTc5ls96IVO2BFBjLZrkU/iJ4DkJbmFLSIa0E0ODIxLcNh9CilrhemHo9MTIs/fv9i
	p/aYg2B5WQEgIhm11rAbN976/ozr+zNupl5/Y61hgEcBULS93U7dSTcHBwfN/NjWoDSvrn6odvhL
	/HCShe0RAKlUKgqA7SwiAZCrwZ2cq71nAJ4Iy0MQjgAAgnOk6DWAl4ltzH0rLeynMdRchOEbd3tZ
	MiUiyovl34DkQNRMUYQB2ietekXku+vI2NdPxT1AoIIg1ACEjVPQSueNcD427qAXx7nyUpHKS0Xy
	4jgXG3eQ2FxWSueTBgoAJAhC3S4iQzxjEtOXqe5srszvue6fo6EweuGHU3P9/V5tc2V+77x3+MOa
	xDA4e6KISimGiNpNsj0A4qpcuJ3t7nkKCCq/ausAFnaTbE83oEgpPtFGESGAxDNioyhSpJONRr22
	1agfbpFjNqIoUp4RC5A0tf84ECJFgLq0vFAtNlu0A+BKyq8BiIBqZTxSwtR+2AnDkEulEhzwupCD
	SmFqzRf5KRCHWr0WQBPIVIj6CARXcxkAwjDk1IoCwP5YdFO5asZa7uqYj9YdgNaqxgm/Kn8pfk5j
	Oobt9O96Btrav7D4CZ90+p/ZAAAAAElFTkSuQmCC
}]

set unlocked [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACaElEQVR4nIWT
	v2tTURTHP+fe95KghcZapOCm4mDwB0bX5ll1FAV5XXWQzuIsFPUPcNdZoWSQbqKFNiIopRG0Cjo0
	OnSQCsaYNL/effc4tIm2Cp7pC/f7PXzPOd8r7C5VQUSLF+JRvL0IKTTqz6vVhQaogOifdLNTPWsQ
	0WLpaiRqPqHpHMqc5Mc/noqulLbEszs0shufLF0eDW3us4i86rreDEA2zDzE6xmTCQ8vP33UHHjd
	4SCOYwNoaDKTIpJPeum11cqT9dXKk/Vus309CLPjvte9AOg2F4BgADY2NgQQVb9PnU9HrUuKxZmw
	c6guHur9b537xvMZkGPlsv7VoNVqCaCoNhBLZWn+BwDV4Yi3BuDOP3YggJ4sXc4HJjMrIjfV6w2E
	jqqKiChKiLGbLu0svK3M/xhoZPs0nD1/ZcxrpiIiBU39d9A8ItuzqlfEWxsE3qcfwkAnXz8r10Ex
	pVJkAfUumLLGFpz6Qt+FR7L9fr66WJbqYllavX4+2Mzsl64rGGMLSY8pQEulyA636dGsc4mbyDTX
	Vl8+rodho3M6iu8Vo+m7Jw5m28vLj36OjTTXUpc4j8/9tURjjEfVfElyI0C/qQcu5faO3AalttF+
	A8x/SXIje8GIMX6oGwDVrZhmnaZxHBuxybtet/2+1918L4F7F8exyTpNQXSLu8uBihgBc3RpvlmG
	FFgDjg/eV4AYmrVzsVEvv4MURZGvVCoE+DcqAbWp6ZWi6ldFA9lqhIIVxNVEJgQhtL4KEEWRH1gx
	gC9OxhdNaGbS1O/ZlRMFsNa0feIfVF+Unw80f2Rqx8f6Xw25vwDk8x7gbq99TwAAAABJRU5ErkJg
	gg==
}]

} ;# namespace 16x16
} ;# namespace icon
} ;# namespace filelist

namespace eval icon {
namespace eval 16x16 {

set star [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACh0lEQVR4nI2T
	PUwUQRTH/2/24zgxlmfExGii4TgKhaWAhuWQQAExRhmwsSBRWmOisTHZXGdnLMWPhPIcjB+J8SvC
	LZ2QRQoFP2qKu1gKt+zs7rMQ9ARM/HUzk9/MP2/eA/aGAOBUvyx09I63Ne7tROztewTPEwbzjBCp
	AjwBz/u/C1zXNYESd81/PGuYdpthWe1O/+oZlEr862x3VHJd18jlcqyUSgEwADjFsa9gfIBgAuNk
	MKdatx0ppajVauT7frIrVne3zOosSdOyp2P943iaWmRn7G9RHF08kOyb8f3p8K8EzoA8wikug5EH
	0EmMg1amqVlHYTmYUxcAwOkbLVuZ7JjeDNeZUAWwRESrEHzfZE0tlm3dZGZore+Qgc9ab35Bc/39
	78rvDyeidbpLhFZK0WrY1hWAkOjwBQFAlzs2ICzzGXMytfiufHXvn/mFc3r8tiGMyWhTn12eV29J
	SmkopRKneH7QtLKvEx3NbKQ80Z5DfauokFKKTzVk95nioWFYMtb1oWDu8RsppUEA4DiTVhBM6c6+
	c0N20/5XOqyPBJXCSylXTABQqhB39K8OZ+ym53qjPhjMq7fbjgkAwcihBCOeEJXVtTgKOUmpBpRS
	pRD9aRhZjaOQExNr8DwRAAkCwAQAt1IRvu/HaVH2UIpoeV4tdvSOtwmTbxEgYvCNYFYtOEWpDUYP
	SqUV13VNH0h3dmIeRN+dvtEpK2OuAGhNUz5hG9Ynp39sCqDvEJxvFAQA5HI53lp3ZrLNh4nECMfR
	ZDD7KL9UUXkkySViDGeyzS1IqbPREQCgCgUGAGI80eH6tY0qH12cU/e2X1mYLT/YqPKxqP7jOoif
	Njr/pHFw9hqibX4CGr0c2NYqY10AAAAASUVORK5CYII=
}]

set home [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACLklEQVR4nJVS
	TU8TURQ99830ywI/QRey0Jpo0qkNLsy8kiB1TV9dEIIbPxI0NiBLnXRJdKcrt8iquJ/ExDqGDROK
	0TV/AjBlZjrzrovaZkBM8Kxu3r3nnHvvu8C/4Dji3PgisG3bBICyXFgpS7UCAEop47/Ilmyszcwv
	8cz8Epdr6mU6l4Y4S/Y8L67MNlu5wsTbQRg+jaLgSb5QfGNJtep5XnyeyCnnymyzdef+MltSrY5y
	5TNvf4mM255trqULSyWVLZVUNi1Sqan1MzsZBmW70arOLXLFbrQAwLIeZ0YGo7gs1Yvq3GKqO0fQ
	0Fk9yxcm3wX945+9bufWiFitL04BgO9uHY3Fao0f+UtTN4OT4+e9L533JgAixmEUBj6Yb1Sr9Skx
	MTkZQ2wn4eD2cC8PfBNa6V/Z44TDq1EY+MQ4BEDCtm1jr9vZjKP+BoiKvu8eDRiviXCNWS9rnTwk
	oBQxXvn+1hGIinHU39jrdjZt2zaG3+g4AkammNrr5ThJdva/bm999z59jJN4h4ArAAgAYGSKo+sc
	CrTbmpg1AAYcASAhpsJ0vZ6brtdzBJEHkAAOAWBi1mi39alDYiJBRAS0NYMDIpwcuG544LohEU4Y
	HABtTUTETGOeKaXUnufBhN4HmVypNXcZfJ2BrFVruADADEmgqFJr7hIRZwzuAYCUUtMfIQFAW3cX
	7oms+SjROkPMzEAWw8EjJiJDiIEe6A+9b53PI076IAkXx7j2N2k58g2u0LzcAAAAAElFTkSuQmCC
}]

set visited [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABAUlEQVR4nLWT
	u0oDURCG/5lzRNA+D2FhIiExTTwYxVZBptCXGba1z0PIImJl6yGdoChCWvv10oiY4O4eC6MsgZD7
	X00xfPPPDVi2RMRAlecnTQmhv+rVXWlXm0d1AHDO2eHE0dRBRQLKZnWtU3aHFe99OgyhYiwi/8Ak
	SQgAXkolXn/nayJufvV7jafO5b2ImDiOs2laQn3v5Ly2f/q2uXO8NbD461BVOYqivNKSDct8FrLM
	AgQEEAghBDBRyEMOy4ZbAH2EPD24u7m4VVVawHrmbaGQM9MQi4CiCKok3S49v8KzWan1vz+3H/3V
	g3POeu/TcY4nPqTJNes/LO6ZRugHVSxqCLgLn+MAAAAASUVORK5CYII=
}]

set desktop [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB2ElEQVR4nJ2R
	PWtUURCGnznnfqxmVzcELEStrFNkuzSbFEIqK29po43gHxAUBAPiP/A/eNFGkViZ2wY2djZqozZu
	ErIxS7L345yx2A8T3RV1msNh5n2YeV8A4KHhn2uokfF3cfHaXO3iBRt8P9Q/yapzDXE7B1Wn8+po
	Ami1kxs2DJ9WrmyKqkFEpqpVVUV8YG2vrIo77zZfPA8AVLjlvNsD7oqRSBU/TS9GjCqFU30k2NvA
	EAAo3n/Y3kyf/c31rZXkJmAAxgAU4iRJLGABN0NrAfdphxgoTwEENE1TlyQJaZpOBYx7rZVEx04H
	v8xIt9sVTqRzsqb1AgARUfAKaJZl1Yz1mfREVTD6cwPVEBGzvHy9EYZieyNBfFz3APmZvgFoAmWp
	LkcsqjIBqGErDGsPctjNIQqgD+DmivpwKOoD9KFOTBFEcVTlg/UJYLDAutnLtwSaiNn16h+LqniV
	ewBG9ImKqCD3BV1wZdE77sqbCeB9mhbAS4Cl1aQlYkTxyshqFVERI6r+W+dt+vqU6+O33W7b/ehy
	HJSDbWPtJfXegTRGiEMxxnrnvlZhbWm++JJnWeYA/S2uq2tr8fnqSg32iY/yoYlnYwPzHASfBx83
	NvJZKf1X/QA26Mz40bSUUQAAAABJRU5ErkJggg==
}]

set usb [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB9klEQVR4nK2S
	MWgUQRiF3z8zuytGUZDzBJtAhMAVCdyChESYRFC0UTCMlY0gkkoLsV4PAmkFOy0tUkwXCy1Ebptw
	wkUhkBVBUARFIV08L7mbmd/CnJyXS7DwVTMD7/vfmxlgX2Vi+PpflP02pHp+IdXzC/1ng6LBfcWY
	qLC2W529dlGq5AUAeOcvjZX45QYgC1txQC3sB/gTuTpbfJVKlncB39/U7amDEhAA1lqrlixf9uzW
	JctRED1iZibgDgsSSsblTmen+Ta3H3oeAQDGGAEAWygtxodGVgTE82bd5gz+zMCnZt3mCOGZjKJl
	IbDY7/nrYoiIvXOemVhrrcCIiBBXjIlBaHvXdQC43yMAwFobAED+jJd8d5uI+UGe5w6EhJlDYW0H
	wGMOXgUKS7se3pNg+xh5Bguh1M1JffU4gzcFydF07vpTIdV977rvzpwQG73+/QAGQOvTY20EMiCq
	RjL5SKAJCBonYDJ4vhvFdK43uQfY8w8A8Pj0laNHkiRTUXLPdXZW1+p2ZvhzD1QAwGl6O3q/urIF
	oBW865KUZ9M589AYI7XWahAwNMHEhRsjCfsfwblbYCah1BPZ8ocbDdvu7z8ckGWEoqB0E68F0UkG
	EYfwba2EKVQqjFqNDwIAYAKIp86b046oBgCKOWu8sl8Gp/8X/QJcPNVSzMFP0QAAAABJRU5ErkJg
	gg==
}]

set download [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB40lEQVR4nLWS
	wWoTURSGvzN3JiSaduEiG5cilILWMIgtlUxbKChCocrtyncpeYm+guIQ3dWVtJMKVsi0FcGVdOcm
	FBeVUpOZucdF2hDbaHHhD3dxD//9+c45F/6nrLXGWmv+5vH+9BDg8IiNwyM2RmsX5V8BcfsqyksE
	1lrT7XZlcJPe4EC325VxFJcI4jguVBERBPQsCNneTgoR9CoCCZfWFqfmV6qAKhgFA+jU/Eo1XFpb
	BGRcgAAybW2AutZkubIJgGof1T7ARLmyibrWtLXBuZ/RtDAMgzRN8/uRnaHkf3B58VZxkygqnhwb
	L3jitDfXedc6CMPQT9M0+y1gVHcbz+ol338PXANVRX6S9R+mO2/2LnqHAfXFtUae+Z9vmG8/kiTJ
	ZyJ7LzDeDgJkeaPTbu1HUeR/L25O+EF+Z3/rVXs4g+Xl59eNkJSC7HGtVtNZayufkvjAqVtwzi10
	2q39WWsrtVpNS0H2yAhJFNnqcI0nJ8ce5TJOiyKOXxfAKcDeVpyeE+7G8ekuUF946oz4ZFnvbIjr
	6x5A2P7yUTzvlivcLuALKMLg4yiFDtrNPePNqXNf08b0g0ELTaDZdMblq4i8FEFE6CvkqvRU6Snk
	IvRFEEReGJev0mw6muNW8I/6BaKMxB/1qmTYAAAAAElFTkSuQmCC
}]

set trash [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACQ0lEQVR4nKWT
	zUtUYRTGf+e81xm1DyERdREmM3NHcWELaTsYtHRTzKKgfyGCoKCNELQoaFH/QjuHVvYBQci0DCQ3
	ITmjItlikEESHWfmzn1PC+dOUrTywIGzeJ7nfc7HC2cMSQoDKYEWwW9NTeX6zR4fez8KkFattVSf
	ZtbXqwlGwACCU0oGxADVOH5iIjeBDwBidsfiOC1wO8H842Ajm02PBsH5WqcTKbyJRZr5SmUB4Hsu
	t+xE+r33t0aDoK/W6RyG1WorEZDtiYl0J5X60q96ueX9YL9qKhDhyHsAzqnSMaPpfTut2mh6/yNo
	t69N7uy0ZAncN7C7udyDAeeeN+L4npnVRbUBpLsGW+b9oDg3PCjy6jiOH76uVF7MgLAEDqCSycxs
	5/N+a3p6omv7atJeUm9NT09s5/O+ksnMACyBC4rdaQItBWm325MrhcLPi7Xa141sdgHggnPLK4VC
	X7y7O5kKAgFaAEUwpSuQiqJ6ZGaiemm+XO40zUxFvIr4ppnNl8sdExmOzCwVRfVk+5rY3BsZOcTs
	SETGeqchcpLdR0R1DLOjvZGRw4TXE5hbXY0MDrzZGMCAiIr3gXgfDIic4MxGDQ7mVlejnoCALf4R
	qguMG7iG95uo7qO63/B+08AJjAN1gMUut+u1u4kw/FwJw3f8JzZyuffVMCyf5pyccrEIpRICb4ec
	e1YNw4+YxSbiAMQsRsQNOXfjVxw/+ouTTAyhWNSttbX7ger1tlmvLw+kRPBmn67Mzr6kVOp9pjPH
	b+f0BrC9LS8lAAAAAElFTkSuQmCC
}]

set arrow [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABAUlEQVR4nLWT
	u0oDURCG/5lzRNA+D2FhIiExTTwYxVZBptCXGba1z0PIImJl6yGdoChCWvv10oiY4O4eC6MsgZD7
	X00xfPPPDVi2RMRAlecnTQmhv+rVXWlXm0d1AHDO2eHE0dRBRQLKZnWtU3aHFe99OgyhYiwi/8Ak
	SQgAXkolXn/nayJufvV7jafO5b2ImDiOs2laQn3v5Ly2f/q2uXO8NbD461BVOYqivNKSDct8FrLM
	AgQEEAghBDBRyEMOy4ZbAH2EPD24u7m4VVVawHrmbaGQM9MQi4CiCKok3S49v8KzWan1vz+3H/3V
	g3POeu/TcY4nPqTJNes/LO6ZRugHVSxqCLgLn+MAAAAASUVORK5CYII=
}]

set folder [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB60lEQVR4nJVT
	MWtTURg9576b19ga62KmUkfBoVoSQUIxEcQxYPVRnIQO/gQ3feQ3qD/BQaLgonbMa7fSWiddSkBx
	CgjSDJqXd+9xSJM+a1P0wB3u9/Gd7zvnuxcYgTgZ0+Ino9ZcL9VqzVKtuV6aBOPYHBLlzx8dWL29
	toBMbQHXIO+MCazk3//42l/d398YnDKdLABp6J8YYy65zD8whs55f9bQPD2/OP9u6cKd+4U5Owhs
	KHvQV3auxO2NFwcANNFYuRltSEo/dF41x/TVG3eXYe0WiDnvfUbJiPQESXIbQ6ztbL38Zg+nyQAU
	6/W6LZfLptvtamfz9V51ZXWJxeJ1wkuAgQQv0AZ85gt6DOChBQBJJKAkSbIoioLd3V2HODY7rVYX
	QPe4+OXGvTVDLgKAnbqSVssDsYmiT3nXg16v5/vgDMD0dIIRi2+3j25RFCFJEldpRJLECQHJcYC9
	Xu+vXY8xzgkgSU0IJBkSKQ59mDbPOEcilWTyEoYgLlZuRfPZMOXMz4G3NlS+OMtSDs7MGFsIBY8F
	CF9yEvxzsvBWzn8PGMLNFuiOtw9DBKDgCBojcPgIOHrburrSvBwWZ6845zg26DhIKggCDdNfH/c2
	33zOe/V/vy5Xc1QYx6be6Zh/qUwaDT96J8BvmHLSqj9OHEMAAAAASUVORK5CYII=
}]

set document [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACLElEQVR4nJ1T
	PWsUURQ9987bWTebXUEJaJVCK4UUO35UOhPJxyILFstaqGBjUqRIl3qYUv+AkM6QQkhA0WVBVNwR
	3MoRC7GS2IhCBMHEZHcy8961SLLJJILiKR68xz33nnO4D9gD4e84VLP7wACMc6k+wXl7SqfpACAg
	IgEIEPN1UIqzYfigB99nBIHZbcC+7zMAc360fpZy6pnR+hQRGEQ2IEogw3ZhcGqDN1vDrnsEQWCw
	zQEAqHa7zQBMCq6wGKm9WjoXAP0JFbdeS+LuQwGNDFknHueq1WufgiDeUS/9TiRiIMa8GWuUMh6J
	jwNSNJBFK2dPluPy0zMTjWPwfQJAKpsIW0myuuF4jdvKzt/QSTzLJn2pYX+wgDtJ3F2184Vx6fWu
	IggWXddV2QY70CSiILE20G/DR18AjDhj02WVfC8lW73PRCL9DDJMEZMkRwvvO8sLABZOV6v5C9Wb
	ZbW2Lp0X8z9d141/yRDvp2QuIOJO58m64zXuXZy8JeW4tJn2tn7owdJaZbR+NwzDGEQZziEFjlMb
	sDTui05DJmO210CzSvmj49QKEDH7KVkF/4GDFiiKml1tyQyxaopwS4RbxKqpLZmJomYXRJl17lsQ
	IiYAPkBBe3kOwNzBaQ3AWgEgspeD8jzPhGEIBfNOSKF55XpUMfINEGDnAEAAYYXpJIGQs0wEAJ7n
	mexnutwY5xxPa22Kf/JrWbxhEjMfvV56vsvJJPAPmR2q/Q3SuOkJHKBXawAAAABJRU5ErkJggg==
}]

set executable [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACIklEQVR4nKVT
	MUhVYRg957v/63ew3nYHhxYbXXwSmINXKRAcxMgbRKsuLg0J4XS5kwQ2tLjo2uIdlApBCHrXQWy5
	LtKUS0HQ3V69odv77/81PASLBKuzHr7D+TjnEOcQx3FQliXDMNQsy+rLcMQFaE3HT51xzwDAOPO4
	eJs9OUcTgJ4XIABtRXfHA9MY9rUOGGu33I/qOQCYK/aRq6pFCfi9dr3TIt85OrthHMdBlmV+9HY8
	HkAO1WsNKAHtKHi1r67fADYBKsnA13qryLffxXEspizLvh3nh1XgfVVdv9bolHmeK4CzX4Moivi1
	1wzF2k8KfwPAUVmWNACAJBHJ31uo4vjw5eex6P78zTsPHtauZwEgMI2q26tfHB9u745NLUAoFkki
	aLcheZ671sHJmrF2C0QHqlT6JVWdB2gAGlWdV/olqBJEx1i71To4Wcvz3EmSJKLQDe/cOoBBkEqi
	VtfbL9rZbNHOZtX19knUIBXAoHduXaEbSZKIXBTjZSFpmnqCy2LMCoAuVKmKgKYx05qK91pT8R5N
	Y0YVAVQJoCvGrBBcTtPUSxRFppgcWXVVtQhFE6RSZZPkLqAOUEdylyqbIBWKpquqxWJyZDWKItNP
	IU29j+5VIoLRibmhQXx5nb/JX/0e4+jE3BBIeO8rpKlHFIkJw1D7XZFTiojYgY9dWI5NL/xSpC7Y
	FEslKQQ/AGAYhvr/Vf7TQIC/HxOAf5vzTzNvNJztU3r0AAAAAElFTkSuQmCC
}]

# set ok [image create photo -data {
# iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
# ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
# ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
# MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
# Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
# IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
# YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
# cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
# aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
# b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
# b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
# d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
# b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
# IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
# c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
# REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
# TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
# SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
# SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
# RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
# V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
# SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
# RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABFElEQVR4nGNg
# GCDASL7WegYmyjXX27PAhIg3rd6ehaGR4Z9og3WlGOPfGwz1WmyoCv4zMEJNxvQf1EaxBptCyX7n
# /2L1NlUQ9bgdwIip2QqmuQjFOwz19UwMDAwMojXW+mKt9hMZ0oxZGRgYGBhCQ5kxbG6wKUQPAxiD
# kZmZ8fd/xv/Z4nLc2i9DtbwYVq3+zcDI8F+swaaQmZ+97+/Hn0WvGo70Q8Li4B80P0JcIVZjoSvW
# bv9NrNl2H0OuCrtYg3W+5ARkZyNsxvTrqlBmhrDVf0WrrAwYuZiPMDIwvmRgZlT69/Nf2euGw93Y
# bcYV2vXmemLt9o9E62xLcdmMxxBo6IYyMKPwSQLwFEdJsqUow5AAAKVVVqRyrAO+AAAAAElFTkSu
# QmCC
# }]

set cancel [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABY0lEQVR4nK1T
	MW7CQBAcG4gd4CWUXlFAczaigZpFdEmaKBAp2PAAfhBCkUTiC35EuAc4JS8JCAT2pQCSC5IjkNjq
	dDOz2pnbAy5ao5HJzJk0mJkzGI3MkxqddPeL7UDyuOu43AcAIUT2gB/O5PITedzVNSYAzOdzAwCU
	wpWdL7yQywMp5VYIkSWinJRySx4HVr44UYmydI0+hwkATo37lcaNIpcHB4Q8DiqNG0UeBzoXAP50
	EUJkpZRbp9b2bTs/Xi2/Hg3TSCy78L5eLobRLHxm5kwYhnFqHkT3OQAgwQ/lekeV6x3luK2ejumV
	nqyJY48ptCMLUTTdkMeBdV14S+K4lyRx184XX8ltDaNouvlnT9JDdGptPy1EAPsNA+CIll9t3v4Q
	iShHRLtMPA6qzTvliJava7IAUCqVFAAYprFeLRf+5yyc7F9kc7AmP8IxuRwbprHRNSluzlxlnXSZ
	z3RGfQMtvY4FPM8TaAAAAABJRU5ErkJggg==
}]

set disk [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACZ0lEQVR4nI1T
	T0hUcRD+Zn5v9+2urklhERSBhw7dZOsi1HMh8NZBe9ihWxAUZBDV9bFnuxVCaIcOHvIhEXiwDto7
	FaF7CTwloeSlUnDVXd+/mQ7tyvoH6rvNb37fzMc3M0ATrusa/Auex4efqD1wHMdq5M8VwsYOd8Sa
	AkDSVaSwYXGMerIc+DuAx0BFWhz2mlX7yiNDu9bZ9TSMflqc/R7adi20c7UkjDYM11c6LLNZGnAf
	ARVxHMdqV0Cu62ZWfmODmGdVZI2InqrqCDTdAngQRPcJ9DKTtUejvb0n1cB/1lLCAHR1dTtHxJ0a
	J+OU0hyzAYnq3xakBGSXFqYfxlFj1M7nx1pKANcQAPT33yiGtr2lhGEo1ixjvU/T5CQREUCiIl9N
	Lnvty9xUrTRwc4yMeVxPpLgc+DsHXRUtVBf8JebkYqcUCovz07Q4/8b09qB0oRjtwvNYSD+piHTH
	IQHAkbEAoM8f/M066t2XyyMTpfLIxLf18IzvX1JUKgLhQvv0DhVgANBS6W5GGLNKOgjSQc7a7xzn
	Izct0XaG1R6oKgGAbSe5mE0pkfgOKxMbMxk3TuQBbB+W265AwSDXdU0mc76RSvoim8m/srL2ZJqm
	zzOZrYbrukaZCMC+CgsAkiQi2DarSs33Z9Jm7sGV67deI45RDWYWW4S+slsDwEkSEXBgkfQXsQkk
	lSlDyIqqKEsNAEi4i4k4VUTMdBuiV3t7cNr3/Zg8z+NKpSJ95eEhw9a4qp5SEW7uAO27o6rELES0
	ISr3qvP+W3geH3tMVm37gNMtJF1Fyjd+1IMgSI4k/+ucj/n7B1nAIBVBmM6mAAAAAElFTkSuQmCC
}]

set action(copy) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB8ElEQVR4nKWS
	v2sUQRTHP2929hALLeTOzkZttNHbP+AuUQhqpTixsxG0CYj+AyKCTRprEUEEBZeQRlBBxLUK4pEu
	IBJBtAqRNCdJuN35WuydLoEI6oM3zZv3/THfgf8sAyyE4FbXueHMTUlREq5xR+ZIDPdRlbszKJ58
	r9cQgAO0us7NNG3NE2Mq0QI8SHVjimxjzGGju2AKIaRj8vrI+uEVwOBtPrOb1Gz6fBfn96ZDBktL
	+WbTAtnU7HNJrcNtznze4BjRPQKdRLWC2oh+yKxyzrUkPd48oLmVPB/5eiYHkOd51e1ffOqc0kq6
	bFIEMDNFs8RBFavY9ml6b8/66BMw7xtvNQJwzh2PZXVp+d3Cs93sdPvhnBmndgCMYSTJaPV6Pd/p
	dBxQNcbJ2tpaHBoRrJykMInEJm1mKoqiBKo8z381UBVFUSJMkjUBUqGtMdBflaOm/eJ9On3i9IWj
	QlvOzP1pSWOVAB4gUXlb+EM+pkekuC2LZQghAZIQQnM3gVuCldEkOQ/wvlj8Bsz0ej0/dJ39iPbE
	8w7yCsDc7EGkr2P1AFiWXfWDwf1Rdyo88D69Upaj1yaiwKz+02ZGhVnb+zSryq2zH94svLAGuoHI
	smte+zauO7N+jNF+cwgwc4kbVmV8uFzkLxsC/qkM4CdBquXi2ej5wgAAAABJRU5ErkJggg==
}]

set action(move) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABfElEQVR4nKVT
	PU8CQRB9uyx3xkRL/Q/YsSQ2JtxSWNjKJBZEDTWFoNheaFW0sTaxM1lrS9FoKXbej9BOE/W45dYC
	zpyKCeirdmZ2Pt8M8Bt8n498jwMiygBAXlEzr6iZ1o2BQTbpUWNxuWIXlytWeuXttC0NlhZyRE6Q
	yxl5/VAXztSB6YWPAKxw3HnTe9/pFheOckEgAq17PwP4PkerFQOALFGNWbzGwAoAcODCMkx3L/Xx
	979fepaK6rJEtUSfV3SbV3SbyLJENamonvYRAGW01n3pUUNk3bbpvW0mDhw4+dKwtc8iO3UqvTLX
	WrcBn7NhpmY26+6ZKHyCxQ0XYsb2zdldR58AQEFRlWXEWt+YFwYsCcedi6Jw976j9yfil41WD/sf
	0ia91Y3EUlBULSiqfs5Alde/08oB3SeiTPdKH5oobIDzmcQhBqox8BkAjM2aKGx0r87bgyG24n/T
	+MsiBVvCcdvjLNIITLbKo8eaHFPxT8eUFDLeOX8A5VK34TocvOMAAAAASUVORK5CYII=
}]

set action(link) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACBUlEQVR4nIVT
	TWsTURQ9971JmoTu3OnKhaCpmOgkMNjSmWlcCRWUvKaudFUoKJjJDxiyN7FQ1JV/wMGFe8FJcRGR
	QMUawd+hjU0y77poBmfSD+9m3mPOvZxz7jvAeeX7Qikl46tSSsL3xbk9iaL4YCmVtyyVT0wWJ0Cn
	NHN5RRWNjNhh8CqImUB7E468rx/ffY8xJ+j4M4oVe+N6JmccQOAiM7dYcwtEl7Iy27+52rgWY415
	zWEYCgDTqYA0tN69fEF7QRBEM8TrSq0xFFLvArgzp+Bsc0xHeaarmgBg2g+2Tbc+jj2Jmwho69Ly
	+lLVVmUAKBZVFgBMVzUXCosdMAkAYBYp30Ss2bQfXs0WFvc1YQsADYfB2HRVM5srdI9Gv7xB+LZj
	WSovDOMJQL1+PxglPWDQ9CVr8TPzBy0AXFmrP8ssFLrj0WFrEAYvANAkh44QdAUR7qf0W5bK33LV
	xLTV9rHmeuv23cdsOspLyqnaqlxaXl9KrBqpLWhoPv5F+ujwd2sQBl0AGA6DMQB86QX7iWaebW7m
	gas+VGqNHwljAYCqtc2dsrtRAgDbto35pxwzIB2Jp4YUnytrmwdRFL2SBIYUW0R0Q0p+AwCO4+he
	u62TAyjx5fLKvaLM5J4DcEBMgPyE6cgb7L3/lqJ9ev2jZtuPcunwnJmZ+Rnp+Pq+L/4X37/LOrOb
	0ncJbQAAAABJRU5ErkJggg==
}]

set action(restore) [set [namespace parent [namespace parent]]::filelist::icon::16x16::restore]

} ;# namespace 16x16
} ;# namespace icon
} ;# namespace fsbox


bind FSBox <KeyPress-Up>			{ TreeCtrl::SetActiveItem %W [TreeCtrl::UpDown %W active -1] }
bind FSBox <KeyPress-Down>			{ TreeCtrl::SetActiveItem %W [TreeCtrl::UpDown %W active +1] }
bind FSBox <KeyPress-Left>			{ TreeCtrl::SetActiveItem %W [TreeCtrl::LeftRight %W active -1] }
bind FSBox <KeyPress-Right>		{ TreeCtrl::SetActiveItem %W [TreeCtrl::LeftRight %W active +1] }
bind FSBox <KeyPress-Home>			{ TreeCtrl::SetActiveItem %W [%W item id {first visible state enabled}]}
bind FSBox <KeyPress-End>			{ TreeCtrl::SetActiveItem %W [%W item id {last visible state enabled}] }
bind FSBox <KeyPress-space>		{ TreeCtrl::SetActiveItem %W [%W item id active] }
bind FSBox <Shift-KeyPress-Down>	{ TreeCtrl::Extend %W below }
bind FSBox <Shift-KeyPress-Up>	{ TreeCtrl::Extend %W above }
bind FSBox <ButtonPress-1>			{ fsbox::SetActiveItem %W [TreeCtrl::ButtonPress1 %W %x %y] %s }
bind FSBox <ButtonRelease-1>		{ TreeCtrl::Release1 %W %x %y }
bind FSBox <Button1-Motion>		{ TreeCtrl::Motion1 %W %x %y }
bind FSBox <Button1-Leave>			{ TreeCtrl::Leave1 %W %x %y }
bind FSBox <Button1-Enter>			{ TreeCtrl::Enter1 %W %x %y }
bind FSBox <KeyPress-Prior>		{ fsbox::ScrollPage %W -1 }
bind FSBox <KeyPress-Next>			{ fsbox::ScrollPage %W +1 }

bind FSBox <Motion> {
    TreeCtrl::CursorCheck %W %x %y
    TreeCtrl::MotionInHeader %W %x %y
    TreeCtrl::MotionInItems %W %x %y
}

bind FSBox <Leave> {
    TreeCtrl::CursorCancel %W
    TreeCtrl::MotionInHeader %W
    TreeCtrl::MotionInItems %W
}

switch [tk windowingsystem] {
	x11 {
		bind FSBox <4> {
			if {[%W yview] eq {0 1}} { %W xview scroll -40 units } else { %W yview scroll -5 units }
		}
		bind FSBox <5> {
			if {[%W yview] eq {0 1}} { %W xview scroll +40 units } else { %W yview scroll +5 units }
		}
	}
	aqua {
		bind FSBox <MouseWheel> {
			if {[%W yview] eq {0 1}} {
				%W xview scroll -40 units
			} else {
				%W yview scroll [expr {-(%D)}] units
			}
		}
	}
	win32	{
		bind FSBox <MouseWheel> {
			if {[%W yview] eq {0 1}} {
				%W xview scroll -40 units
			} else {
				%W yview scroll [expr {-(%D/120)*4}] units }
			}
	}
}

# Touchpad Binding for Horizontal Scrolling
# see http://wiki.tcl.tk/12696
bind FSBox <Button> {
	if {"%b" eq 6} {
		%W xview scroll -40 units
	} elseif {"%b" eq 7} {
		%W xview scroll +40 units
	}
}

# vi:set ts=3 sw=3:
