# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================
# Makefile for Scidb for Unix operating systems
# ======================================================================

# ======================================================================
#    _/|            __
#   // o\         /    )           ,        /    /
#   || ._)    ----\---------__----------__-/----/__-
#   //__\          \      /   '  /    /   /    /   )
#   )___(     _(____/____(___ __/____(___/____(___/_
# ======================================================================

include ../Makefile.in

# the per-user directory is named after the installation, not after the program file
USERDIRNAME ?= .$(notdir $(DATADIR))
# the binary the launcher script starts, whatever the script is called
TKPROGRAM ?= tk$(PROGRAM)$(SUFFIX)

SCRIPT = $(PROGRAM)$(SUFFIX)
# All platform scripts go into every bundle and pick themselves at run
# time, so a bundle built without the target set still works everywhere.
# The macOS adapters reuse the generic Unix routines, so Unix comes first.
DND_SCRIPTS = dnd/tkdnd_unix.tcl dnd/tkdnd_macosx.tcl dnd/tkdnd_windows.tcl
ARCH = arch-chesswiz

# NOTE that the ordering is important!
SOURCES = \
	exec.tcl \
	sys-platform.tcl \
	utils/place.tcl \
	debuglog.tcl \
	start.tcl \
	options.tcl \
	colors.tcl \
	utils/tcl_bugs.tcl \
	splash.tcl \
	utils/shadow.tcl \
	widgets/theme.tcl \
	widgets/misc.tcl \
	log.tcl \
	utils/archive.tcl \
	contrib/tkmenu.tcl \
	contrib/treectrl.tcl \
	contrib/filelist-bindings.tcl \
	contrib/http.tcl \
	dialogs/messagebox.tcl \
	dialogs/notice.tcl \
	dialogs/progressbar.tcl \
	dialogs/choosecolor.tcl \
	dialogs/choosecolor-cube.tcl \
	dialogs/choosefont.tcl \
	board-basic.tcl \
	load.tcl \
	i18n.tcl \
	fonts.tcl \
	icons.tcl \
	encoding.tcl \
	utils/locale.tcl \
	utils/countries.tcl \
	utils/web.tcl \
	utils/xcursor.tcl \
	utils/player-photos.tcl \
	utils/emoticons.tcl \
	utils/clipboard.tcl \
	utils/trash.tcl \
	dnd/tkdnd.tcl \
	$(DND_SCRIPTS) \
	dialogs/fileselectionbox.tcl \
	dialogs/help.tcl \
	dialogs/tip-of-the-day.tcl \
	widgets/tooltip.tcl \
	widgets/toolbar.tcl \
	widgets/validate.tcl \
	widgets/tlistbox.tcl \
	widgets/tcombobox.tcl \
	widgets/colormenu.tcl \
	widgets/table.tcl \
	widgets/treetable.tcl \
	widgets/scrolledframe.tcl \
	widgets/gamebar.tcl \
	widgets/corrclock.tcl \
	widgets/gamehistory.tcl \
	widgets/scrolledtable.tcl \
	widgets/panedwindow.tcl \
	widgets/calendar.tcl \
	widgets/datebox.tcl \
	widgets/rangebox.tcl \
	widgets/entrybox.tcl \
	widgets/entrybuttonbox.tcl \
	widgets/roundbox.tcl \
	widgets/countrybox.tcl \
	widgets/languagebox.tcl \
	widgets/eventmodebox.tcl \
	widgets/eventtypebox.tcl \
	widgets/fideidbox.tcl \
	widgets/timemodebox.tcl \
	widgets/titlebox.tcl \
	widgets/resultbox.tcl \
	widgets/genderbox.tcl \
	widgets/ratingbox.tcl \
	widgets/scorebox.tcl \
	widgets/terminationbox.tcl \
	widgets/ecobox.tcl \
	widgets/organizationbox.tcl \
	widgets/labelbar.tcl \
	widgets/keybar.tcl \
	widgets/html.tcl \
	widgets/choosedir.tcl \
	widgets/fsbox.tcl \
	widgets/figurines.tcl \
	widgets/notation.tcl \
	widgets/twm.tcl \
	widgets/database-switcher.tcl \
	widgets/registerbutton.tcl \
	widgets/dropdownbutton.tcl \
	widgets/sliding-varlist.tcl \
	widgets/searchentry.tcl \
	gametable.tcl \
	playertable.tcl \
	eventtable.tcl \
	sitetable.tcl \
	ecotable.tcl \
	progress.tcl \
	board-texture.tcl \
	board-pieceset.tcl \
	board-piece.tcl \
	board-square.tcl \
	board-stuff.tcl \
	board-holding.tcl \
	board-options.tcl \
	web3d-server.tcl \
	board-3d.tcl \
	tablebase.tcl \
	endgame-trainer.tcl \
	media-inset.tcl \
	book.tcl \
	guess-move.tcl \
	repertoire-trainer.tcl \
	annotation.tcl \
	comment.tcl \
	marks.tcl \
	engine.tcl \
	player-dict.tcl \
	application.tcl \
	app-key-editor.tcl \
	app-information.tcl \
	app-board.tcl \
	app-database.tcl \
	app-database-search.tcl \
	app-database-search-material.tcl \
	app-database-search-rating.tcl \
	app-database-search-advanced.tcl \
	app-database-search-nl.tcl \
	app-database-search-cql6.tcl \
	app-database-openingprep.tcl \
	app-database-repertoire.tcl \
	app-database-maintenance.tcl \
	app-database-discover.tcl \
	app-download-games.tcl \
	app-explorer.tcl \
	app-db-icons.tcl \
	app-db-annotators.tcl \
	app-db-positions.tcl \
	app-db-games.tcl \
	app-corr-games.tcl \
	app-board-games.tcl \
	app-report.tcl \
	iccf-xfcc.tcl \
	app-db-players.tcl \
	app-db-events.tcl \
	app-db-sites.tcl \
	app-pgn.tcl \
	app-tree.tcl \
	app-tree-games.tcl \
	app-variation.tcl \
	app-analysis.tcl \
	play-engine.tcl \
	engine-match.tcl \
	ai-claims.tcl \
	ai-rhetoric.tcl \
	ai-annotate.tcl \
	ai-studyplan.tcl \
	ai-factcheck.tcl \
	ai-brief.tcl \
	ai-engine.tcl \
	tactics-trainer.tcl \
	ai-provider.tcl \
	ai-systemone.tcl \
	ai-batch.tcl \
	ai-calibrate.tcl \
	ai-journal.tcl \
	ai-search.tcl \
	ai-cql.tcl \
	ai-positions.tcl \
	ai-pattern-index.tcl \
	ai-cql-reference.tcl \
	ai-similar-positions.tcl \
	ai-setup-position.tcl \
	ai-event.tcl \
	ai-language.tcl \
	ai-import.tcl \
	ai-comment.tcl \
	ai-novelty.tcl \
	ai-narrate.tcl \
	ai-prompt.tcl \
	ai-precedent.tcl \
	ai-annotations.tcl \
	game-review.tcl \
	ai-generate.tcl \
	ai-trend.tcl \
	ai-openingprep.tcl \
	ai-eventreport.tcl \
	ai-duplicate.tcl \
	ai-similar.tcl \
	ai-simindex.tcl \
	ai-egress.tcl \
	ai-tier.tcl \
	ai-modelfit.tcl \
	ai-transcript.tcl \
	ai-diagram.tcl \
	app-ai.tcl \
	app-ai-models.tcl \
	actions.tcl \
	app-assistant.tcl \
	app-assistant-route.tcl \
	app-assistant-args.tcl \
	app-assistant-offers.tcl \
	app-assistant-jobs.tcl \
	app-diagnose.tcl \
	app-voice.tcl \
	app-error-triage.tcl \
	app-media-decode.tcl \
	app-media-lesson.tcl \
	app-media-sync.tcl \
	app-media-mpv.tcl \
	app-media.tcl \
	app-twm.tcl \
	manage-layouts.tcl \
	pgn-setup.tcl \
	save-replace.tcl \
	export.tcl \
	print.tcl \
	import.tcl \
	merge.tcl \
	browser.tcl \
	overview.tcl \
	player-card.tcl \
	insights.tcl \
	player-data.tcl \
	setup-board.tcl \
	setup-position.tcl \
	crosstable.tcl \
	info.tcl \
	move.tcl \
	game.tcl \
	menu.tcl \
	end.tcl \

ifneq ($(USE_INLINE_TEXT),)
SOURCES += contrib/tktext.tcl
endif

SCRIPTS = $(SCRIPT)

all: $(SCRIPTS)

clean:
	@echo "Clean `pwd`"
	@rm -f $(SCRIPT)

depend:
	@# nothing to do

build-install-help: build-help install-help

build-help:
	@for lang in `ls -d help/[a-z][a-z]`; do           \
		(cd $$lang; if [ -f Makefile ]; then make; fi); \
	done

install-config:
	@echo "Install configuration files"
	@install -m 755 -d $(SHAREDIR)/engines
	@install -m 644 -p engines/*.dat $(SHAREDIR)/engines

uninstall-config:
	@echo "Uninstall configuration files"
	@if [ -d $(SHAREDIR)/engines ]; then                                                        \
		for f in `ls engines/*.dat`; do rm -f $(SHAREDIR)/$$f; done;                             \
		if [ "`find $(SHAREDIR)/engines -type d -empty`" = "`ls -d $(SHAREDIR)/engines`" ]; then \
			rmdir $(SHAREDIR)/engines;                                                            \
		fi;                                                                                      \
	fi

install-scripts: $(SCRIPTS)
	@echo "Install Tcl scripts"
	@install -m 755 -d $(BINDIR)
	@install -m 755 -p $(SCRIPT) $(BINDIR)
	@install -m 755 -d $(SHAREDIR)/scripts
	@install -m 644 -p ../scripts/stt-transcribe.py $(SHAREDIR)/scripts
	@install -m 644 -p ai-thresholds.tsv $(SHAREDIR)

uninstall-scripts:
	@echo "Uninstall Tcl scripts"
	@rm -f $(BINDIR)/$(SCRIPT)
	@rm -f $(SHAREDIR)/scripts/stt-transcribe.py
	@rm -f $(SHAREDIR)/ai-thresholds.tsv

install-pieces:
	@echo "Install piece sets"
	@install -m 755 -d $(SHAREDIR)/pieces
	@install -m 644 -p pieces/*.tcl $(SHAREDIR)/pieces

uninstall-pieces:
	@echo "Uninstall piece sets"
	@if [ -d $(SHAREDIR)/pieces ]; then                                                       \
		for f in `ls pieces/*.tcl`; do rm -f $(SHAREDIR)/$$f; done;                            \
		if [ "`find $(SHAREDIR)/pieces -type d -empty`" = "`ls -d $(SHAREDIR)/pieces`" ]; then \
			rmdir $(SHAREDIR)/pieces;                                                           \
		fi;                                                                                    \
	fi

install-cursors:
	@echo "Install cursors"
	@install -m 755 -d $(SHAREDIR)/cursor
	@install -m 644 -p cursor/*.xbm $(SHAREDIR)/cursor
	@install -m 644 -p cursor/*.xcur $(SHAREDIR)/cursor

uninstall-cursors:
	@echo "Uninstall cursors"
	@if [ -d $(SHAREDIR)/cursor ]; then                                                       \
		for f in `ls cursor/*.xbm`; do rm -f $(SHAREDIR)/$$f; done;                            \
		for f in `ls cursor/*.cur`; do rm -f $(SHAREDIR)/$$f; done;                            \
		for f in `ls cursor/*.xcur`; do rm -f $(SHAREDIR)/$$f; done;                           \
		if [ "`find $(SHAREDIR)/cursor -type d -empty`" = "`ls -d $(SHAREDIR)/cursor`" ]; then \
			rmdir $(SHAREDIR)/cursor;                                                           \
		fi;                                                                                    \
	fi

install-flags:
	@echo "Install flags"
	@install -m 755 -d $(SHAREDIR)/flags
	@install -m 644 -p flags/*.png $(SHAREDIR)/flags

uninstall-flags:
	@echo "Uninstall flags"
	@if [ -d $(SHAREDIR)/flags ]; then                                                      \
		for f in `ls flags/*.png`; do rm -f $(SHAREDIR)/$$f; done;                           \
		if [ "`find $(SHAREDIR)/flags -type d -empty`" = "`ls -d $(SHAREDIR)/flags`" ]; then \
			rmdir $(SHAREDIR)/flags;                                                          \
		fi;                                                                                  \
	fi

install-localizations:
	@echo "Install localizations"
	@install -m 755 -d $(SHAREDIR)/lang/eco
	@install -m 755 -d $(SHAREDIR)/lang/nag
	@install -m 644 -p lang/*.tcl $(SHAREDIR)/lang
	@install -m 644 -p lang/eco/*.tcl $(SHAREDIR)/lang/eco
	@install -m 644 -p lang/nag/*.tcl $(SHAREDIR)/lang/nag

uninstall-localizations:
	@echo "Uninstall localizations"
	@if [ -d $(SHAREDIR)/lang ]; then                                                     \
		for f in `ls lang/*.tcl`; do rm -f $(SHAREDIR)/$$f; done;                          \
		eco=$(SHAREDIR)/lang/eco;                                                          \
		if [ -d $$eco ]; then                                                              \
			for f in `ls lang/eco/*.tcl`; do rm -f $(SHAREDIR)/$$f; done;                   \
			if [ "`find $$eco -type d -empty`" = "`ls -d $$eco`" ]; then                    \
				rm -rf $$eco;                                                                \
			fi;                                                                             \
		fi;                                                                                \
		nag=$(SHAREDIR)/lang/nag;                                                          \
		if [ -d $$nag ]; then                                                              \
			for f in `ls lang/nag/*.tcl`; do rm -f $(SHAREDIR)/$$f; done;                   \
			if [ "`find $$nag -type d -empty`" = "`ls -d $$nag`" ]; then                    \
				rm -rf $$nag;                                                                \
			fi;                                                                             \
		fi;                                                                                \
		if [ "`find $(SHAREDIR)/lang -type d -empty`" = "`ls -d $(SHAREDIR)/lang`" ]; then \
			rmdir $(SHAREDIR)/lang;                                                         \
		fi;                                                                                \
	fi

install-lang: install-localizations
uninstall-lang: uninstall-localizations

install-textures:
	@echo "Install textures"
	@install -m 755 -d $(SHAREDIR)/textures
	@for i in dark lite tile; do                                             \
		for k in marble misc wood; do                                         \
			install -m 755 -d $(SHAREDIR)/textures/$$i/$$k;                    \
			install -m 644 -p textures/$$i/$$k/* $(SHAREDIR)/textures/$$i/$$k; \
		done;                                                                 \
	done

uninstall-textures:
	@echo "Uninstall textures"
	@if [ -d $(SHAREDIR)/textures ]; then                                                 \
		for i in dark lite tile; do                                                        \
			if [ -d $(SHAREDIR)/textures/$$i ]; then                                        \
				for k in marble misc wood; do                                                \
					kdir=$(SHAREDIR)/textures/$$i/$$k;                                        \
					if [ -d $$kdir ]; then                                                    \
						for f in `ls textures/$$i/$$k/*`; do                                   \
							rm -f $(SHAREDIR)/$$f;                                              \
						done;                                                                  \
						if [ "`find $$kdir -type d -empty`" = "`ls -d $$kdir`" ]; then         \
							rmdir $$kdir;                                                       \
						fi;                                                                    \
					fi;                                                                       \
				done;                                                                        \
				idir=$(SHAREDIR)/textures/$$i;                                               \
				if [ "`find $$idir -type d -empty`" = "`ls -d $$idir`" ]; then               \
					rmdir $$idir;                                                             \
				fi;                                                                          \
			fi;                                                                             \
		done;                                                                              \
		if [ "`find $(SHAREDIR)/textures -type d -empty`" = "$(SHAREDIR)/textures" ]; then \
			rmdir $(SHAREDIR)/textures;                                                     \
		fi;                                                                                \
	fi

install-ttk-themes:
	@echo "Install Ttk themes"
	@install -m 755 -d $(SHAREDIR)/themes/ttk
	@install -m 644 -p themes/ttk/*.tcl $(SHAREDIR)/themes/ttk

uninstall-ttk-themes:
	@echo "Uninstall Ttk themes"
	@if [ -d $(SHAREDIR)/themes/ttk ]; then                            \
		for f in `ls themes/ttk/*.tcl`; do rm -f $(SHAREDIR)/$$f; done; \
		dir=$(SHAREDIR)/themes/ttk;                                     \
		if [ "`find $$dir -type d -empty`" = "`ls -d $$dir`" ]; then    \
			rmdir $$dir;                                                 \
		fi;                                                             \
	fi

install-themes:
	@echo "Install board themes"
	@install -m 755 -d $(SHAREDIR)/themes/square
	@install -m 755 -d $(SHAREDIR)/themes/piece
	@install -m 644 -p themes/*.dat $(SHAREDIR)/themes
	@install -m 644 -p themes/piece/*.dat $(SHAREDIR)/themes/piece
	@install -m 644 -p themes/square/*.dat $(SHAREDIR)/themes/square

uninstall-themes:
	@echo "Uninstall board themes"
	@if [ -d $(SHAREDIR)/themes ]; then                                               \
		for f in `ls themes/*.dat`; do rm -f $(SHAREDIR)/$$f; done;                    \
		dir=$(SHAREDIR)/themes/piece;                                                  \
		if [ -d $$dir ]; then                                                          \
			for f in `ls themes/piece/*.dat`; do rm -f $(SHAREDIR)/$$f; done;           \
			if [ "`find $$dir -type d -empty`" = "`ls -d $$dir`" ]; then                \
				rmdir $$dir;                                                             \
			fi;                                                                         \
		fi;                                                                            \
		dir=$(SHAREDIR)/themes/square;                                                 \
		if [ -d $$dir ]; then                                                          \
			for f in `ls themes/square/*.dat`; do rm -f $(SHAREDIR)/$$f; done;          \
			if [ "`find $$dir -type d -empty`" = "`ls -d $$dir`" ]; then                \
				rmdir $$dir;                                                             \
			fi;                                                                         \
		fi;                                                                            \
		if [ "`find $(SHAREDIR)/themes -type d -empty`" = "$(SHAREDIR)/themes" ]; then \
			rmdir $(SHAREDIR)/themes;                                                   \
		fi;                                                                            \
	fi

install-text-scripts:
	@echo "Install additional TeXt scripts"
	@install -m 755 -d $(SHAREDIR)/scripts
	@install -m 644 -p scripts/*.eXt $(SHAREDIR)/scripts
	@install -m 644 -p scripts/*.css $(SHAREDIR)/scripts

uninstall-text-scripts:
	@echo "Uninstall TeXt scripts"
	@if [ -d $(SHAREDIR)/scripts ]; then                                                        \
		for f in `ls scripts/*.eXt scripts/*.css`; do rm -f $(SHAREDIR)/$$f; done;               \
		if [ "`find $(SHAREDIR)/scripts -type d -empty`" = "`ls -d $(SHAREDIR)/scripts`" ]; then \
			rmdir $(SHAREDIR)/scripts;                                                            \
		fi;                                                                                      \
	fi

install-images:
	@echo "Install images"
	@install -m 755 -d $(SHAREDIR)/images
	@install -m 644 -p images/*.png $(SHAREDIR)/images
	@install -m 755 -d $(SHAREDIR)/pdf
	@install -m 755 -d $(SHAREDIR)/pdf/sets
	@for i in `ls pdf/sets/`; do                                       \
		ip=pdf/sets/$$i;                                                \
		install -m 755 -d $(SHAREDIR)/$$ip;                             \
		for k in `ls $$ip`; do                                          \
			kp=$$ip/$$k;                                                 \
			install -m 755 -d $(SHAREDIR)/$$kp;                          \
			install -m 644 -p $$kp/*.png $$kp/*.jpg $(SHAREDIR)/$$kp;    \
			for j in `ls $$kp/pieces`; do                                \
				jp=$$kp/pieces/$$j;                                       \
				install -m 755 -d $(SHAREDIR)/$$jp;                       \
				install -m 644 -p $$jp/*.png $$jp/*.jpg $(SHAREDIR)/$$jp; \
			done;                                                        \
		done;                                                           \
	done
	@install -m 755 -d $(SHAREDIR)/img/pieces_3d $(SHAREDIR)/web3d
	@install -m 644 -p ../img/pieces_3d/*.png $(SHAREDIR)/img/pieces_3d
	@install -m 644 -p ../web3d/index.html ../web3d/*.js $(SHAREDIR)/web3d

uninstall-images:
	@echo "Uninstall images"
	@rm -rf $(SHAREDIR)/img/pieces_3d $(SHAREDIR)/web3d
	@if [ -d $(SHAREDIR)/img ]; then rmdir $(SHAREDIR)/img 2>/dev/null || true; fi
	@if [ -d $(SHAREDIR)/images ]; then                                                       \
		for i in `ls images/*.*`; do                                                           \
			rm -f $(SHAREDIR)/$$i;                                                              \
		done;                                                                                  \
		if [ "`find $(SHAREDIR)/images -type d -empty`" = "`ls -d $(SHAREDIR)/images`" ]; then \
			rmdir $(SHAREDIR)/images;                                                           \
		fi;                                                                                    \
	fi
	@if [ -d $(SHAREDIR)/pdf ]; then                                                                  \
		if [ -d $(SHAREDIR)/pdf/sets ]; then                                                           \
			for i in `ls pdf/sets/`; do                                                                 \
				idir=$(SHAREDIR)/pdf/sets/$$i;                                                           \
				if [ -d $$idir ]; then                                                                   \
					ip=pdf/sets/$$i;                                                                      \
					for k in `ls $$ip`; do                                                                \
						kdir=$$idir/$$k;                                                                   \
						if [ -d $$kdir ]; then                                                             \
							kp=$$ip/$$k;                                                                    \
							rm -f $$kdir/*.png $$kdir/*.jpg;                                                \
							if [ -d $$kdir/pieces ]; then                                                   \
								for j in `ls $$kp/pieces`; do                                                \
									jdir=$(SHAREDIR)/$$kp/pieces/$$j;                                         \
									if [ -d $$jdir ]; then                                                    \
										rm -f $$jdir/*.png $$jdir/*.jpg;                                       \
										if [ "`find $$jdir -type d -empty`" = "`ls -d $$jdir`" ]; then         \
											rmdir $$jdir;                                                       \
										fi;                                                                    \
									fi;                                                                       \
								done;                                                                        \
								if [ "`find $$kdir/pieces -type d -empty`" = "`ls -d $$kdir/pieces`" ]; then \
									rmdir $$kdir/pieces;                                                      \
								fi;                                                                          \
							fi;                                                                             \
							if [ "`find $$kdir -type d -empty`" = "`ls -d $$kdir`" ]; then                  \
								rmdir $$kdir;                                                                \
							fi;                                                                             \
						fi;                                                                                \
					done;                                                                                 \
					if [ "`find $$idir -type d -empty`" = "`ls -d $$idir`" ]; then                        \
						rmdir $$idir;                                                                      \
					fi;                                                                                   \
				fi;                                                                                      \
			done;                                                                                       \
			if [ "`find $(SHAREDIR)/pdf/sets -type d -empty`" = "`ls -d $(SHAREDIR)/pdf/sets`" ]; then  \
				rmdir $(SHAREDIR)/pdf/sets;                                                              \
			fi;                                                                                         \
		fi;                                                                                            \
		if [ "`find $(SHAREDIR)/pdf -type d -empty`" = "`ls -d $(SHAREDIR)/pdf`" ]; then               \
			rmdir $(SHAREDIR)/pdf;                                                                      \
		fi;                                                                                            \
	fi

install-help:
	@echo "Install help files"
	@install -m 755 -d $(SHAREDIR)/help
	@install -m 755 -d $(SHAREDIR)/help/images
	@install -m 755 -d $(SHAREDIR)/help/styles
	@install -m 644 -p help/images/*.* $(SHAREDIR)/help/images
	@install -m 644 -p help/styles/*.css $(SHAREDIR)/help/styles
	@for lang in `ls -d help/[a-z][a-z]`; do                                \
		if [ -f $$lang/Contents.dat ]; then                                  \
			install -m 755 -d $(SHAREDIR)/$$lang;                             \
			install -m 644 -p $$lang/*.dat $(SHAREDIR)/$$lang;                \
			install -m 644 -p $$lang/*.html $(SHAREDIR)/$$lang;               \
			if [ -d $$lang/images ]; then                                     \
				install -m 755 -d $(SHAREDIR)/$$lang/images;                   \
				install -m 644 -p $$lang/images/*.* $(SHAREDIR)/$$lang/images; \
			fi;                                                               \
		fi;                                                                  \
	done

uninstall-help:
	@echo "Uninstall help files"
	@if [ -d $(SHAREDIR)/help ]; then                                                            \
		dir=$(SHAREDIR)/help/images;                                                              \
		if [ -d $$dir ]; then                                                                     \
			for f in `ls help/images/*.*`; do rm -f $(SHAREDIR)/$$f; done;                         \
			if [ "`find $$dir -type d -empty`" = "`ls -d $$dir`" ]; then rmdir $$dir; fi;          \
		fi;                                                                                       \
		dir=$(SHAREDIR)/help/styles;                                                              \
		if [ -d $$dir ]; then                                                                     \
			for f in `ls help/styles/*.css`; do rm -f $(SHAREDIR)/$$f; done;                       \
			if [ "`find $$dir -type d -empty`" = "`ls -d $$dir`" ]; then rmdir $$dir; fi;          \
		fi;                                                                                       \
		for lang in `ls -d help/[a-z][a-z]`; do                                                   \
			dir=$(SHAREDIR)/$$lang;                                                                \
			if [ -d $$dir ]; then                                                                  \
				for f in `ls $$lang/*.dat`; do rm -f $(SHAREDIR)/$$f; done;                         \
				for f in `ls $$lang/*.html`; do rm -f $(SHAREDIR)/$$f; done;                        \
				idir=$$dir/images;                                                                  \
				if [ -d $$idir ]; then                                                              \
					for f in `ls $$lang/images/*.*`; do rm -f $(SHAREDIR)/$$f; done;                 \
					if [ "`find $$idir -type d -empty`" = "`ls -d $$idir`" ]; then rmdir $$idir; fi; \
				fi;                                                                                 \
				if [ "`find $$dir -type d -empty`" = "`ls -d $$dir`" ]; then rmdir $$dir; fi;       \
			fi;                                                                                    \
		done;                                                                                     \
		if [ "`find $(SHAREDIR)/help -type d -empty`" = "`ls -d $(SHAREDIR)/help`" ]; then        \
			rmdir $(SHAREDIR)/help;                                                                \
		fi;                                                                                       \
	fi

install-fonts:
	@echo "Install fonts"
	@if [ 1 ]; then                                                                   \
		if [ "`id -u`" -eq 0 ]; then                                                   \
			fontdir="$(FONTDIR)";                                                       \
		else                                                                           \
			if [ "`uname -s`" = "Darwin" ]; then                                        \
				fontdir="$(HOME)/Library/Fonts";                                         \
			else                                                                        \
				fontdir="$(HOME)/.fonts";                                                \
			fi;                                                                         \
		fi;                                                                            \
		install -m 755 -d $$fontdir;                                                   \
		install -m 644 -p fonts/*.ttf $$fontdir;                                       \
	fi

setup-fonts:
	@if [ -z "$(XDGDIR)" ]; then                                                      \
	   echo "Setup fonts";                                                            \
		if [ "`id -u`" -eq 0 ]; then                                                   \
			fontdir="$(FONTDIR)";                                                       \
		else                                                                           \
			if [ "`uname -s`" = "Darwin" ]; then                                        \
				fontdir="$(HOME)/Library/Fonts";                                         \
			else                                                                        \
				fontdir="$(HOME)/.fonts";                                                \
			fi;                                                                         \
		fi;                                                                            \
		if [ ! -z "`which fc-cache`" ]; then                                           \
			fc-cache -f $$fontdir;                                                      \
		else                                                                           \
			if [ "`uname -s`" != "Darwin" ]; then                                       \
				echo "Don't know how to setup truetype fonts (fc-cache not available)."; \
				echo "Please contact your system administrator.";                        \
			fi;                                                                         \
		fi;                                                                            \
	else                                                                              \
		echo "SKIP - Setup fonts";                                                     \
	fi

uninstall-fonts:
	@if [ -z "$(XDGDIR)" ]; then                                    \
	   echo "Uninstall fonts";                                      \
		if [ "`id -u`" -eq 0 ]; then                                 \
			fontdir="$(FONTDIR)";                                     \
		else                                                         \
			if [ "`uname -s`" = "Darwin" ]; then                      \
				fontdir="$(HOME)/Library/Fonts";                       \
			else                                                      \
				fontdir="$(HOME)/.fonts";                              \
			fi;                                                       \
		fi;                                                          \
		recache=0;                                                   \
		for f in `ls fonts/*.ttf`; do                                \
			if [ -f $$fontdir/`basename $$f` ]; then                  \
				recache=1;                                             \
				rm -f $$fontdir/`basename $$f`;                        \
			fi;                                                       \
		done;                                                        \
		if [ $$recache = 1 ]; then                                   \
			if [ ! -z "`which fc-cache`" ]; then                      \
				fc-cache -f $$fontdir;                                 \
			fi;                                                       \
		fi;                                                          \
		if [ "`find $$fontdir -type d -empty`" = "$$fontdir" ]; then \
			rmdir $$fontdir;                                          \
		fi;                                                          \
	else                                                            \
	   echo "SKIP - Uninstall fonts";                               \
	fi

install-photos:
	@echo "Install player photos"
	@install -m 755 -d $(SHAREDIR)/photos
	@for f in `ls engines/photos/*`; do             \
		base=`basename $$f`;                         \
		dir=`echo $$base | cut -b 1`;                \
		install -m 755 -d $(SHAREDIR)/photos/$$dir;  \
		install -m 644 $$f $(SHAREDIR)/photos/$$dir; \
	done

uninstall-photos:
	@echo "Uninstall player photos"
	@if [ -d $(SHAREDIR) ]; then                                                         \
		if [ -d $(SHAREDIR)/photos ]; then                                                \
			rm -rf $(SHAREDIR)/photos;                                                     \
		fi;                                                                               \
		if [ "`find $(SHAREDIR) -type d -empty`" = "`ls -d $(SHAREDIR)`" ]; then          \
			rmdir $(SHAREDIR);                                                             \
		fi;                                                                               \
	fi

install: install-scripts install-pieces install-cursors install-flags install-localizations \
				install-textures install-themes install-ttk-themes install-text-scripts install-images \
				install-help install-config install-photos install-fonts

uninstall: uninstall-scripts uninstall-pieces uninstall-cursors uninstall-flags uninstall-localizations \
				uninstall-ttk-themes uninstall-themes uninstall-text-scripts uninstall-textures \
				uninstall-images uninstall-help uninstall-config uninstall-fonts
	@if [ -d $(SHAREDIR) ]; then                                                             \
		if [ -n "$(XDGDIR)" ]; then                                                           \
			rm -rf $(SHAREDIR)/photos;                                                         \
		fi;                                                                                   \
		if [ "`find $(SHAREDIR) -type d -empty`" = "`ls -d $(SHAREDIR)`" ]; then              \
			rmdir $(SHAREDIR);                                                                 \
		fi;                                                                                   \
		if [ -d $(SHAREDIR)/photos ]; then                                                    \
			echo "Type 'make uninstall-photos' if you want to uninstall all player photos";    \
		fi;                                                                                   \
	fi

$(SCRIPT): $(SOURCES) Makefile ../Makefile.in
	@echo "Checking trailing newlines in sources"
	@err=; for f in $(SOURCES); do \
		if [ -n "`tail -c 1 "$$f"`" ]; then echo "ERROR: $$f does not end with a newline"; err=1; fi; \
	done; if [ -n "$$err" ]; then exit 1; fi
	@echo "Building $(SCRIPT)"
	@tmp="$(SCRIPT).tmp.$$$$"; \
	trap 'rm -f "$$tmp"' EXIT INT TERM HUP; \
	for f in $(SOURCES); do cat "$$f"; echo; done | LC_ALL=C sed                  \
		-e 's/# vi:set ts=3 sw=3:/update idletasks/'        \
		-e 's#%SHAREDIR%#$(DATADIR)#g'                      \
		-e 's#%ENGINESDIR%#$(ENGINESDIR)#g'                 \
		-e 's#%USERDIRNAME%#$(USERDIRNAME)#g'               \
		-e 's#%TKPROGRAM%#$(TKPROGRAM)#g'                   \
		-e '/^##/d'                                         \
		-e '/^#$$/d'                                        \
		-e '/^[ 	]*#[ 	]\+/d'                               \
		> "$$tmp"; \
	if [ -x /usr/bin/tclsh ]; then TCLSH=/usr/bin/tclsh; else TCLSH=tclsh; fi; \
	printf '%s' "set fp [open \"$$tmp\" r]; set b [read \$$fp]; close \$$fp; \
		if {![info complete \$$b]} { puts stderr \"ERROR: merged script is syntactically incomplete\"; exit 1 }" \
		| $$TCLSH \
		|| { echo "ERROR: $(SCRIPT) failed the syntax check"; exit 1; }; \
	chmod 0555 "$$tmp"; \
	mv -f "$$tmp" $(SCRIPT)

$(ARCH): utils/archive.tcl
	@echo "Building $(ARCH)"
	@tmp="$(ARCH).tmp.$$$$"; \
	trap 'rm -f "$$tmp"' EXIT INT TERM HUP; \
	cat utils/archive.tcl | sed            \
		-e 's/%PROGRAM%/tcl$(PROGRAM)$(SUFFIX)/g' \
		-e 's#%SHAREDIR%#$(DATADIR)#g'       \
		-e 's/%ARCH%/$(ARCH)/g'              \
		> "$$tmp"; \
	chmod 0555 "$$tmp"; \
	mv -f "$$tmp" $(ARCH)

# vi:set ts=3 sw=3:
