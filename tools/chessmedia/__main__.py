"""Allow invoking `python3 -m tools.chessmedia`."""

import sys
from .chessmedia import main

if __name__ == "__main__":
    sys.exit(main())
