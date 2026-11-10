#!/bin/sh
# A UCI engine for tests: on "go" it floods its output with info lines (as
# fast as yes(1) writes them) for three seconds. It ends by itself after
# 20 seconds.
( sleep 20; kill $$ ) 2>/dev/null &
while read -r line; do
	case "$line" in
		uci)     printf 'id name FloodEngine 1.0\nid author the Scidb test suite\nuciok\n' ;;
		isready) echo readyok ;;
		go*)     timeout 3 yes 'info depth 1 currmove e2e4 currmovenumber 1 nodes 1 nps 1000' ;;
		stop)    echo 'bestmove d2d4' ;;
		quit)    exit 0 ;;
	esac
done
