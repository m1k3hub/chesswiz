# Chesswiz documentation

Project documents, grouped by topic. READMEs that describe one directory stay
beside its code: `tests/README.md`, `opening-report/`, `media-console/`,
`src/cql6/` (vendored CQL notes) and `engines/stockfish/`.

- [UPSTREAM.md](UPSTREAM.md) — what comes from Scidb and what Chesswiz adds
- [CHANGELOG.md](CHANGELOG.md) — release history
- [plans/](plans/) — roadmap and long-range plans; start with
  [ROADMAP_SCIDB_VS_CHESSBASE.md](plans/ROADMAP_SCIDB_VS_CHESSBASE.md)
- [features/](features/) — designs and specs of application features
- [ai/](ai/) — assistant, LLM, plain-language search and classifier work
- [cql6/](cql6/) — the embedded CQL 6.2 engine: plan, tasks, profiling
- [formats/](formats/) — database and media formats; [formats/re/](formats/re/) holds
  reverse-engineering notes
- [dev/](dev/) — ports, packaging, debug logging, harness setup
- [legal/](legal/) — asset licences, font permissions, patent review

## plans

- [LONG_RANGE_PLAN.md](plans/LONG_RANGE_PLAN.md) — scidb-beta Long-Range Plan — Revised for Workstreams 6-8
- [ONLINE_PLAY_PLAN.md](plans/ONLINE_PLAY_PLAN.md) — Online Play — Implementation Plan (scidb-beta Web Frontend)
- [PERFORMANCE_BASELINE.md](plans/PERFORMANCE_BASELINE.md) — SCIDb Performance Baseline Measurements
- [PERFORMANCE_PLAN.md](plans/PERFORMANCE_PLAN.md) — SCIDb Performance Validation & Optimization Plan
- [ROADMAP_SCIDB_VS_CHESSBASE.md](plans/ROADMAP_SCIDB_VS_CHESSBASE.md) — SCIDb Feature Gap Roadmap
- [WEB_FRONTEND_IMPLEMENTATION_PLAN.md](plans/WEB_FRONTEND_IMPLEMENTATION_PLAN.md) — scidb-beta Web Frontend — Implementation Plan

## features

- [annotated-game-display-plan.md](features/annotated-game-display-plan.md) — Plan: Display Annotated Chess Games
- [BOARD_3D_DESIGN.md](features/BOARD_3D_DESIGN.md) — 3D Chessboard — Design and Plan
- [CHESSBASE_SHORTCUTS.md](features/CHESSBASE_SHORTCUTS.md) — ChessBase shortcut research and Chesswiz mapping
- [CORRESPONDENCE_CHESS.md](features/CORRESPONDENCE_CHESS.md) — Correspondence Chess in Scidb-beta
- [DATABASE_DISCOVERY.md](features/DATABASE_DISCOVERY.md) — Database Discovery (tcl/app-database-discover.tcl)
- [FEATURE_PANE_ZOOM.md](features/FEATURE_PANE_ZOOM.md) — Pane zoom and focus-follows-size — feature spec
- [ICCF_XFCC_DESIGN.md](features/ICCF_XFCC_DESIGN.md) — ICCF XFCC Server Integration — Design
- [MEDIA_LESSON_V2_PLAN.md](features/MEDIA_LESSON_V2_PLAN.md) — Media Lesson v2 — Implementation Plan
- [MEDIA_PANEL_DESIGN.md](features/MEDIA_PANEL_DESIGN.md) — Media Panel Design (tcl/app-media*.tcl)
- [MEDIA_PLAYBACK_DESIGN.md](features/MEDIA_PLAYBACK_DESIGN.md) — Media Playback Library Design for Scidb
- [PLAY_AGAINST_ENGINE_RESEARCH.md](features/PLAY_AGAINST_ENGINE_RESEARCH.md) — Play against an engine — research notes (Scid and ScidvsPC)
- [player-startup-cache.md](features/player-startup-cache.md) — Player/site startup cache

## ai

- [AI_AUTOMATION_AUDIT.md](ai/AI_AUTOMATION_AUDIT.md) — AI Automation Audit — what System One / LLMs can reliably automate
- [AI_PRODUCTS_PLAN.md](ai/AI_PRODUCTS_PLAN.md) — AI Products Plan — from infrastructure to features
- [ASSISTANT_COVERAGE_MAP.md](ai/ASSISTANT_COVERAGE_MAP.md) — Ask Scidb — coverage map and plan
- [assistant-features-plan.md](ai/assistant-features-plan.md) — Assistant features: implementation plan
- [JEV_USE_CASES.md](ai/JEV_USE_CASES.md) — Jev-type Models in Scidb — Use-Case Research
- [LLM_FEATURES_RESEARCH.md](ai/LLM_FEATURES_RESEARCH.md) — LLM Features for Scidb — Research & Proposal
- [LLM_REACH_PLAN.md](ai/LLM_REACH_PLAN.md) — LLM Reach Wave — Implementation Plan
- [PATTERN_INDEX_PLAN.md](ai/PATTERN_INDEX_PLAN.md) — Pattern Index — plan and design
- [PLAIN_LANGUAGE_SEARCH.md](ai/PLAIN_LANGUAGE_SEARCH.md) — Plain-Language Search — plan and design
- [SYSTEM_ONE_FEATURES.md](ai/SYSTEM_ONE_FEATURES.md) — System One Features — what the classifier integration makes possible
- [SYSTEM_ONE_RESEARCH.md](ai/SYSTEM_ONE_RESEARCH.md) — System One Models: programmatic/algorithmic use cases, and what they imply for Scidb
- [TYPESAFE_API_EXPERIMENT.md](ai/TYPESAFE_API_EXPERIMENT.md) — TypeSafe API experiment — hosted Jev vs local plumb
- [TYPESAFE_COOKBOOK_REVIEW.md](ai/TYPESAFE_COOKBOOK_REVIEW.md) — TypeSafe cookbook review — applicable refactors for Scidb

## cql6

- [CQL6_INTEGRATION_PLAN.md](cql6/CQL6_INTEGRATION_PLAN.md) — CQL 6.2 in Scidb — integration plan
- [CQL6_TASK1.md](cql6/CQL6_TASK1.md) — Task 1: make CQL 6.2 embeddable (library + structured game feed)
- [CQL6_TASK2B.md](cql6/CQL6_TASK2B.md) — Task 2b: stop the CQL 6 glue from starving the GUI event loop (prefetch buffer)
- [CQL6_TASK2.md](cql6/CQL6_TASK2.md) — Task 2: the Scidb side of the CQL 6.2 engine (`::scidb::cql6::*`), against a stub engine
- [CQL6_TASK3.md](cql6/CQL6_TASK3.md) — Task 3: harden the embedded CQL 6.2 engine (sanitizers, file lockdown, feed robustness)
- [CQL_FEATURES.md](cql6/CQL_FEATURES.md) — CQL-Powered Features — plan and design
- [NATIVE_API.md](cql6/NATIVE_API.md) — Native CQL 6.2 searches
- [NATIVE_PROFILING.md](cql6/NATIVE_PROFILING.md) — Native pipeline profiling
- [REPORT_P1_thread_scaling.md](cql6/REPORT_P1_thread_scaling.md) — REPORT_P1 — CQL6 multi-thread scaling analysis
- [REPORT_P2_profile_matrix_crosscheck.md](cql6/REPORT_P2_profile_matrix_crosscheck.md) — REPORT_P2 — cql6 performance analysis
- [REPORT_P3_profile_matrix.md](cql6/REPORT_P3_profile_matrix.md) — REPORT_P2 — Where does the time go, per kind of CQL script?
- [RESUME_STATUS.md](cql6/RESUME_STATUS.md) — CQL 6.2 completion status — 2026-10-01

## formats

- [2CBH_FORMAT_DESIGN.md](formats/2CBH_FORMAT_DESIGN.md) — 2CBH Format Reverse Engineering — Design for Scidb
- [CBM_FORMAT_DESIGN.md](formats/CBM_FORMAT_DESIGN.md) — CBM File Format Handling — Design for Scidb
- [CBV_FORMAT_SPECIFICATION.md](formats/CBV_FORMAT_SPECIFICATION.md) — CBV Archive Format Specification
- [CBV_STATUS.md](formats/CBV_STATUS.md) — CBV Archive Format Support — Status Assessment
- [CCG_FORMAT_DESIGN.md](formats/CCG_FORMAT_DESIGN.md) — CCG — Correspondence Chess Game Format
- [CHESS960_CBG_REVERSE_ENGINEERING.md](formats/CHESS960_CBG_REVERSE_ENGINEERING.md) — Chess960/Fischer Random CBG Encoding — Reverse Engineering Status
- [CHESS960_STATUS.md](formats/CHESS960_STATUS.md) — Chess960 CBG/CBH Decoding Status — Assessment Report
- [CHESSBASE_FORMAT_REFERENCES.md](formats/CHESSBASE_FORMAT_REFERENCES.md) — ChessBase Format References — Research Notes
- [CHESSBASE_MEDIA_RE.md](formats/CHESSBASE_MEDIA_RE.md) — ChessBase WMV/WMA Synchronization RE Notes
- [GRENKE_CHESS960_FIXTURES.md](formats/GRENKE_CHESS960_FIXTURES.md) — Grenke Freestyle Chess960 Fixtures
- [SCI_CORRESPONDENCE_FORMAT.md](formats/SCI_CORRESPONDENCE_FORMAT.md) — SCI correspondence-duration format (v4, joint final draft)
- [SCIDB_HTML_PROFILE.md](formats/SCIDB_HTML_PROFILE.md) — SCIDB HTML Profile
- [SCM_FORMAT_DESIGN.md](formats/SCM_FORMAT_DESIGN.md) — SCM — a scidb-native Media Format + Playback Design

## formats/re

- [cba-annotation-coverage.md](formats/re/cba-annotation-coverage.md) — .cba annotation coverage — census and decoder status
- [cba-display-annotations.md](formats/re/cba-display-annotations.md) — Classic CBH display annotations: 0x22 / 0x23 / 0x14 / 0x15
- [cba-quotation-format.md](formats/re/cba-quotation-format.md) — .cba annotation type 0x13 (game quotation) — header and move blob solved
- [cba-training-annotation-format.md](formats/re/cba-training-annotation-format.md) — .cba annotation type 0x09 (training question / quiz) — solved
- [cbh-bit31-unencoded.md](formats/re/cbh-bit31-unencoded.md) — Classic CBH: the bit-31 "unencoded" game flag
- [cbtt-format.md](formats/re/cbtt-format.md) — .cbtt (ChessBase tournament extras) — format notes
- [reader14-binary-scan-notes.md](formats/re/reader14-binary-scan-notes.md) — Static binary scan — annotation-color tractability (2026-09-07)
- [reader14-vm-oracle-notes.md](formats/re/reader14-vm-oracle-notes.md) — VM visual-oracle session — working notes (2026-09-07)

## dev

- [DEBUG_LOGGING.md](dev/DEBUG_LOGGING.md) — Capturing VM bugs
- [MACOS_PACKAGING.md](dev/MACOS_PACKAGING.md) — macOS distribution
- [PI_HARNESS_SETUP.md](dev/PI_HARNESS_SETUP.md) — Pi harness setup — isolation + code intelligence
- [PORT_WINDOWS_MAC_SPEC.md](dev/PORT_WINDOWS_MAC_SPEC.md) — Windows / macOS port and rename — design decisions

## legal

- [ASSET_LICENSE_AUDIT.md](legal/ASSET_LICENSE_AUDIT.md) — Asset licence audit (Chesswiz)
- [FONT_PERMISSION_REQUESTS.md](legal/FONT_PERMISSION_REQUESTS.md) — Permission requests for the freeware piece sets
- [PATENT_REVIEW.md](legal/PATENT_REVIEW.md) — Patent review (2026-10-10)
