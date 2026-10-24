# ======================================================================
# Author : $Author$
# Version: $Revision$
# Date   : $Date$
# Url    : $URL$
# ======================================================================

# ======================================================================
# Dark ttk theme for Scidb / ChessWiz
# ======================================================================
# Make sure that this file will be encoded in UTF-8.

namespace eval ::ttk::theme::dark {

variable version 1.0

array set colors {
	-frame			"#23272e"
	-lighter			"#2c313a"
	-dark				"#181b20"
	-darker			"#13161b"
	-darkest			"#0d0f13"
	-Control			"#2b303b"
	-activebg		"#353c4a"
	-disabledbg		"#1f2329"
	-disabledfg		"#6e7681"
	-field			"#1b1f27"
	-foreground		"#e6edf3"
	-selectbg		"#2f6feb"
	-selectfg		"#ffffff"
	-tabbg			"#1a1d24"
	-tabborder		"#30363d"
	-focuscolor		"#58a6ff"
	-checklight		"#388bfd"
}

ttk::style theme create dark -parent clam -settings {
	ttk::style configure "." \
		-background $colors(-frame) \
		-foreground $colors(-foreground) \
		-bordercolor $colors(-darkest) \
		-darkcolor $colors(-dark) \
		-lightcolor $colors(-lighter) \
		-troughcolor $colors(-darker) \
		-selectbackground $colors(-selectbg) \
		-selectforeground $colors(-selectfg) \
		-selectborderwidth 0 \
		-font TkDefaultFont \
		;

	ttk::style map "." \
		-background [list disabled $colors(-disabledbg) active $colors(-activebg)] \
		-foreground [list disabled $colors(-disabledfg)] \
		-selectbackground [list !focus $colors(-activebg)] \
		-selectforeground [list !focus $colors(-foreground)] \
		;

	# Buttons
	ttk::style configure TButton \
		-anchor center \
		-width -11 \
		-padding 5 \
		-relief raised \
		-background $colors(-Control) \
		-foreground $colors(-foreground) \
		-bordercolor $colors(-tabborder) \
		-lightcolor $colors(-lighter) \
		-darkcolor $colors(-dark) \
		;
	ttk::style map TButton \
		-background [list \
			disabled $colors(-disabledbg) \
			pressed $colors(-darker) \
			active $colors(-activebg) \
		] \
		-foreground [list \
			disabled $colors(-disabledfg) \
			active $colors(-foreground) \
		] \
		-lightcolor [list pressed $colors(-darker)] \
		-darkcolor [list pressed $colors(-lighter)] \
		-bordercolor [list alternate "#58a6ff" focus $colors(-focuscolor)] \
		;

	ttk::style configure Toolbutton \
		-anchor center \
		-padding 2 \
		-relief flat \
		-background $colors(-frame) \
		-foreground $colors(-foreground) \
		;
	ttk::style map Toolbutton \
		-relief [list \
			disabled flat \
			selected sunken \
			pressed sunken \
			active raised \
		] \
		-background [list \
			disabled $colors(-frame) \
			pressed $colors(-darker) \
			selected $colors(-darker) \
			active $colors(-activebg) \
		] \
		-foreground [list \
			disabled $colors(-disabledfg) \
			active $colors(-foreground) \
		] \
		-lightcolor [list pressed $colors(-darker) selected $colors(-darker)] \
		-darkcolor [list pressed $colors(-lighter) selected $colors(-lighter)] \
		;

	# Checkbuttons & Radiobuttons
	ttk::style configure TCheckbutton \
		-indicatorbackground $colors(-field) \
		-indicatorforeground $colors(-foreground) \
		-indicatormargin {1 1 4 1} \
		-padding 2 \
		-background $colors(-frame) \
		-foreground $colors(-foreground) \
		;
	ttk::style configure TRadiobutton \
		-indicatorbackground $colors(-field) \
		-indicatorforeground $colors(-foreground) \
		-indicatormargin {1 1 4 1} \
		-padding 2 \
		-background $colors(-frame) \
		-foreground $colors(-foreground) \
		;
	ttk::style map TCheckbutton \
		-background [list disabled $colors(-frame) active $colors(-activebg)] \
		-foreground [list disabled $colors(-disabledfg) active $colors(-foreground)] \
		-indicatorbackground [list \
			pressed $colors(-Control) \
			{!disabled alternate} $colors(-checklight) \
			{disabled alternate} $colors(-disabledbg) \
			disabled $colors(-disabledbg) \
		] \
		-indicatorforeground [list \
			disabled $colors(-disabledfg) \
			selected $colors(-focuscolor) \
		] \
		;
	ttk::style map TRadiobutton \
		-background [list disabled $colors(-frame) active $colors(-activebg)] \
		-foreground [list disabled $colors(-disabledfg) active $colors(-foreground)] \
		-indicatorbackground [list \
			pressed $colors(-Control) \
			{!disabled alternate} $colors(-checklight) \
			{disabled alternate} $colors(-disabledbg) \
			disabled $colors(-disabledbg) \
		] \
		-indicatorforeground [list \
			disabled $colors(-disabledfg) \
			selected $colors(-focuscolor) \
		] \
		;

	# Menubutton
	ttk::style configure TMenubutton \
		-width -11 \
		-padding 5 \
		-relief raised \
		-background $colors(-Control) \
		-foreground $colors(-foreground) \
		-arrowcolor $colors(-foreground) \
		;
	ttk::style map TMenubutton \
		-background [list \
			disabled $colors(-disabledbg) \
			pressed $colors(-darker) \
			active $colors(-activebg) \
		] \
		-foreground [list disabled $colors(-disabledfg)] \
		-arrowcolor [list disabled $colors(-disabledfg)] \
		;

	# Entry, Combobox, Spinbox
	ttk::style configure TEntry \
		-padding 1 \
		-insertwidth 1 \
		-fieldbackground $colors(-field) \
		-foreground $colors(-foreground) \
		-insertcolor $colors(-foreground) \
		-bordercolor $colors(-tabborder) \
		-lightcolor $colors(-dark) \
		-darkcolor $colors(-darkest) \
		;
	ttk::style map TEntry \
		-fieldbackground [list readonly $colors(-frame) disabled $colors(-disabledbg)] \
		-foreground [list disabled $colors(-disabledfg)] \
		-bordercolor [list focus $colors(-focuscolor)] \
		-lightcolor [list focus $colors(-selectbg)] \
		-darkcolor [list focus $colors(-selectbg)] \
		;

	ttk::style configure TCombobox \
		-padding 1 \
		-insertwidth 1 \
		-fieldbackground $colors(-field) \
		-background $colors(-Control) \
		-foreground $colors(-foreground) \
		-arrowcolor $colors(-foreground) \
		-insertcolor $colors(-foreground) \
		-bordercolor $colors(-tabborder) \
		;
	ttk::style map TCombobox \
		-fieldbackground [list \
			{readonly focus} $colors(-Control) \
			readonly $colors(-Control) \
			disabled $colors(-disabledbg) \
		] \
		-background [list \
			active $colors(-activebg) \
			pressed $colors(-darker) \
			disabled $colors(-disabledbg) \
		] \
		-foreground [list disabled $colors(-disabledfg)] \
		-arrowcolor [list disabled $colors(-disabledfg)] \
		-bordercolor [list focus $colors(-focuscolor)] \
		;
	ttk::style configure ComboboxPopdownFrame \
		-relief solid \
		-borderwidth 1 \
		-background $colors(-field) \
		-bordercolor $colors(-tabborder) \
		;

	ttk::style configure TSpinbox \
		-arrowsize 10 \
		-padding {2 0 10 0} \
		-fieldbackground $colors(-field) \
		-background $colors(-Control) \
		-foreground $colors(-foreground) \
		-arrowcolor $colors(-foreground) \
		-insertcolor $colors(-foreground) \
		-bordercolor $colors(-tabborder) \
		;
	ttk::style map TSpinbox \
		-fieldbackground [list readonly $colors(-frame) disabled $colors(-disabledbg)] \
		-background [list active $colors(-activebg) disabled $colors(-disabledbg)] \
		-foreground [list disabled $colors(-disabledfg)] \
		-arrowcolor [list disabled $colors(-disabledfg)] \
		-bordercolor [list focus $colors(-focuscolor)] \
		;

	# Notebook
	ttk::style configure TNotebook \
		-tabmargins {0 2 0 0} \
		-background $colors(-frame) \
		-bordercolor $colors(-tabborder) \
		-lightcolor $colors(-lighter) \
		-darkcolor $colors(-dark) \
		;
	ttk::style configure TNotebook.Tab \
		-padding {6 2 6 2} \
		-expand {0 0 2} \
		-background $colors(-tabbg) \
		-foreground "#b1bac4" \
		-bordercolor $colors(-tabborder) \
		-lightcolor $colors(-lighter) \
		-darkcolor $colors(-dark) \
		;
	ttk::style map TNotebook.Tab \
		-padding [list selected {6 4 6 2}] \
		-background [list \
			selected $colors(-frame) \
			active $colors(-activebg) \
			disabled $colors(-disabledbg) \
		] \
		-foreground [list \
			selected $colors(-foreground) \
			active $colors(-foreground) \
			disabled $colors(-disabledfg) \
		] \
		-lightcolor [list selected $colors(-lighter)] \
		-bordercolor [list selected $colors(-focuscolor)] \
		;

	# Labelframe
	ttk::style configure TLabelframe \
		-labelmargins {0 0 0 4} \
		-borderwidth 2 \
		-relief groove \
		-background $colors(-frame) \
		-foreground $colors(-foreground) \
		-bordercolor $colors(-tabborder) \
		-lightcolor $colors(-lighter) \
		-darkcolor $colors(-dark) \
		;
	ttk::style configure TLabelframe.Label \
		-background $colors(-frame) \
		-foreground $colors(-foreground) \
		;
	ttk::style map TLabelframe.Label \
		-foreground [list disabled $colors(-disabledfg)] \
		;

	# Scrollbar, Scale, Progressbar
	ttk::style configure TScrollbar \
		-background $colors(-Control) \
		-troughcolor $colors(-darker) \
		-bordercolor $colors(-darkest) \
		-lightcolor $colors(-lighter) \
		-darkcolor $colors(-dark) \
		-arrowcolor $colors(-foreground) \
		-gripcount 0 \
		;
	ttk::style map TScrollbar \
		-background [list \
			disabled $colors(-disabledbg) \
			pressed $colors(-activebg) \
			active $colors(-activebg) \
		] \
		-arrowcolor [list disabled $colors(-disabledfg)] \
		;

	ttk::style configure TScale \
		-background $colors(-Control) \
		-troughcolor $colors(-darker) \
		-bordercolor $colors(-tabborder) \
		-lightcolor $colors(-lighter) \
		-darkcolor $colors(-dark) \
		-sliderlength 24 \
		;
	ttk::style map TScale \
		-background [list disabled $colors(-disabledbg) active $colors(-activebg)] \
		-troughcolor [list disabled $colors(-disabledbg)] \
		;

	ttk::style configure TProgressbar \
		-background $colors(-selectbg) \
		-troughcolor $colors(-darker) \
		-bordercolor $colors(-tabborder) \
		-lightcolor $colors(-checklight) \
		-darkcolor $colors(-selectbg) \
		;

	# Treeview
	ttk::style configure Heading \
		-font TkHeadingFont \
		-relief raised \
		-padding {3} \
		-background $colors(-Control) \
		-foreground $colors(-foreground) \
		-bordercolor $colors(-tabborder) \
		-lightcolor $colors(-lighter) \
		-darkcolor $colors(-dark) \
		;
	ttk::style map Heading \
		-background [list active $colors(-activebg) pressed $colors(-darker)] \
		-foreground [list disabled $colors(-disabledfg)] \
		;
	ttk::style configure Treeview \
		-background $colors(-field) \
		-fieldbackground $colors(-field) \
		-foreground $colors(-foreground) \
		-bordercolor $colors(-tabborder) \
		;
	ttk::style map Treeview \
		-background [list \
			disabled $colors(-disabledbg) \
			selected $colors(-selectbg) \
		] \
		-foreground [list \
			disabled $colors(-disabledfg) \
			selected $colors(-selectfg) \
		] \
		;
	foreach style {Treeview Row Item Cell} {
		ttk::style configure $style \
			-background $colors(-field) \
			-fieldbackground $colors(-field) \
			-foreground $colors(-foreground) \
			;
		ttk::style map $style \
			-background [list \
				disabled $colors(-disabledbg) \
				selected $colors(-selectbg) \
			] \
			-foreground [list \
				disabled $colors(-disabledfg) \
				selected $colors(-selectfg) \
			] \
			;
	}

	# Panedwindow, Separator, Sizegrip, Frame, Label
	ttk::style configure TFrame \
		-background $colors(-frame) \
		;
	ttk::style configure TLabel \
		-background $colors(-frame) \
		-foreground $colors(-foreground) \
		;
	ttk::style map TLabel \
		-foreground [list disabled $colors(-disabledfg)] \
		;
	ttk::style configure TPanedwindow \
		-background $colors(-frame) \
		;
	ttk::style configure Sash \
		-sashthickness 6 \
		-gripcount 10 \
		-background $colors(-frame) \
		-lightcolor $colors(-lighter) \
		-darkcolor $colors(-dark) \
		-handlepad 4 \
		-handlesize 6 \
		;
	ttk::style configure TSeparator \
		-background $colors(-tabborder) \
		;
	ttk::style configure TSizegrip \
		-background $colors(-frame) \
		;
}

} ;# namespace ::ttk::theme::dark

# vi:set ts=3 sw=3:
