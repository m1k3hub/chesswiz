# Stockfish Engine

This directory is where you place a Stockfish (or any UCI-compatible engine)
binary for the runtime adapter to use.

## How to provide Stockfish

1. Download a Stockfish build from <https://stockfishchess.org/download/> or
   build it from source.

2. Place the executable in this directory:

   ```bash
   cp /path/to/stockfish engines/stockfish/stockfish
   chmod +x engines/stockfish/stockfish
   ```

3. Alternatively, set the `STOCKFISH_PATH` environment variable to the full
   path of the engine binary:

   ```bash
   STOCKFISH_PATH=/usr/bin/stockfish python3 runtime_adapter.py
   ```

## Detection order

The runtime adapter searches for Stockfish in this order:

1. `STOCKFISH_PATH` environment variable (if the file exists)
2. `engines/stockfish/` directory (first executable file found)
3. `/usr/bin/stockfish`
4. `/usr/local/bin/stockfish`

If no engine is found, the adapter falls back to a mock simulation that
produces fake analysis data so the UI keeps working during development.

## Multiple engines

Each subdirectory or file in `engines/stockfish/` is scanned. The first
executable file found is used as `stockfish`. To support multiple engine
versions, set `STOCKFISH_PATH` explicitly.