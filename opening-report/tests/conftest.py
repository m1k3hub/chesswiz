import os
import sys

# Make runtime_adapter importable when running pytest from the project root.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# The test suite exercises the development dummy-JWT auth path (see
# tests/test_runtime_adapter.py). That path is only reachable when insecure
# dev auth is explicitly allowed. setdefault() lets CI override it; tests
# that verify the lockdown delete/override this via monkeypatch.
os.environ.setdefault("SCIDB_ALLOW_INSECURE_DEV_AUTH", "1")
