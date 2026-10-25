# Contributing to Chesswiz

Thanks for your interest. Chesswiz is maintained by one developer, so small, focused changes are easiest to review.

## Reporting bugs and requesting features

Use the feedback page: https://chesswizapp.com/feedback.html (issues live in [m1k3hub/chesswiz-feedback](https://github.com/m1k3hub/chesswiz-feedback)). Include your Chesswiz version (Help > About Chesswiz), your operating system, the steps that lead to the problem, and the log (Help > Show Log) if you can. Leave out private games and API keys.

## Building

See `README` (Build from Source) and `INSTALL` for requirements and configure flags. In short, on Debian/Ubuntu:

```sh
./configure && make
src/tkchesswiz -encoding utf-8 tcl/chesswiz
```

## Pull requests

- Open an issue first for anything larger than a bug fix, so we can agree on the approach.
- Keep each pull request to one change, and match the style of the surrounding code.
- `tcl/chesswiz` is a generated bundle of `tcl/*.tcl`: edit the sources and rebuild with `make -C tcl`. Never end a `.tcl` file with a top-level `return`.
- After editing a C++ header, delete the affected `.o` files before rebuilding; the build does not track header dependencies.
- Run the tests that cover your change (see `tests/`), headless under Xvfb.

## Licence

Chesswiz is licensed under the GNU General Public License, version 2 or later (see `LICENSE` and `COPYING`). By submitting a contribution you agree that it is licensed under the same terms.

## Conduct

Be kind and constructive; see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
