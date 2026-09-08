#!/usr/bin/env python3
# mpv IPC bridge: TCP (for Tcl, which lacks unix sockets) -> mpv's
# --input-ipc-server unix socket.  The bridge binds an OS-picked free
# port and prints "ready <port>" on stdout; the Tcl side parses it.
# One TCP connection = one unix socket connection; bytes are pumped in
# both directions until the TCP side closes.  The bridge exits when its
# stdin closes (i.e. when the spawning application dies).
import os
import select
import socket
import sys


def pump(client, unix_sock):
    fds = [client, unix_sock]
    while True:
        r, _, _ = select.select(fds, [], [], 5.0)
        if not r:
            continue
        for sock in r:
            data = sock.recv(65536)
            if not data:
                return
            try:
                (unix_sock if sock is client else client).sendall(data)
            except (BrokenPipeError, ConnectionResetError, OSError):
                return


def main():
    sockpath = sys.argv[1]
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))			# OS-picked free port
    port = srv.getsockname()[1]
    srv.listen(4)
    # deterministic portfile next to the mpv socket: the Tcl side polls
    # for it instead of parsing the bridge's stdout (a pipe whose own
    # handshake proved fragile)
    with open(sockpath + ".port", "w") as pf:
        pf.write("ready %d\n" % port)
    import sys as _sys
    print("bridge: entered accept loop", file=sys.stderr, flush=True)

    while True:
        r, _, _ = select.select([srv], [], [], 5.0)
        if not r:
            print("bridge: select timeout", file=sys.stderr, flush=True)
        if srv in r:
            print("bridge: accepting", file=sys.stderr, flush=True)
            client, _ = srv.accept()
            print("bridge: client accepted", file=sys.stderr, flush=True)
            try:
                unix_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                unix_sock.connect(sockpath)
                print("bridge: unix connected", file=sys.stderr, flush=True)
            except OSError as e:
                print("bridge: unix connect FAILED: %s" % e, file=sys.stderr, flush=True)
                client.close()
                continue
            print("bridge: pumping", file=sys.stderr, flush=True)
            pump(client, unix_sock)
            print("bridge: pump done", file=sys.stderr, flush=True)
            client.close()
            unix_sock.close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: mpv_ipc_bridge.py <mpv-socket>")
    main()
