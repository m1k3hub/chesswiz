# Withdrawn media panel

The media panel was removed from Scidb on 2026-09-05. These sources and
tests preserve the experimental implementation, including uncommitted work,
for reverse engineering. They are not application modules or supported playback.

No `.cms`/`.cbm` playback integration is to be reintroduced until the formats
are fully understood. Existing format documents record research, including
hypotheses; historical claims of completed playback are not release readiness.

Continue work in the RE tools and fixtures in `media-console/`: establish byte
layouts and semantics with reproducible evidence, document unknowns, and compare
decoded events against the original software before proposing integration.
