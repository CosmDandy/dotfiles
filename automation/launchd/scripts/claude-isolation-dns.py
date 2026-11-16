#!/usr/bin/env python3
"""Local DNS forwarder for the Claude domains (see claude-isolation.sh).

Listens on 127.0.0.1:5354 over UDP and forwards every query to the upstream over
TCP. NOTE: TCP on purpose — through the Happ tunnel plain UDP/53 to any public
resolver times out (measured 2026-11-16), while TCP/53 answers. With the tunnel
down the pf anchor drops the upstream connection, and the client gets SERVFAIL
at once instead of a timeout.
"""

import ipaddress
import socket
import struct
import threading
import time

UPSTREAM = ("1.1.1.1", 53)
LISTEN = ("127.0.0.1", 5354)
TIMEOUT = 4
# The daemon merges this into its table; every answer served for a Claude name
# lands there, so hosts missing from its static list are blocked too.
SEEN_FILE = "/var/db/claude-isolation/ips.seen"
FAKE_IP = ipaddress.ip_network("198.18.0.0/15")


def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("upstream closed")
        buf += chunk
    return buf


def ask_upstream(query):
    with socket.create_connection(UPSTREAM, timeout=TIMEOUT) as s:
        s.sendall(struct.pack(">H", len(query)) + query)
        (n,) = struct.unpack(">H", recv_exact(s, 2))
        return recv_exact(s, n)


def servfail(query):
    # Header with QR/RD/RA and RCODE=2, then only the question section: its end is
    # the root label plus QTYPE and QCLASS. A query never compresses its question.
    i = 12
    while query[i]:
        i += query[i] + 1
    return query[:2] + b"\x81\x82" + query[4:6] + b"\x00" * 6 + query[12 : i + 5]


def skip_name(msg, i):
    while True:
        n = msg[i]
        if n == 0:
            return i + 1
        if n & 0xC0:
            return i + 2
        i += n + 1


def answer_addresses(reply):
    """A and AAAA addresses of a reply; malformed replies yield what parsed so far."""
    found = []
    try:
        qd, an = struct.unpack(">HH", reply[4:8])
        i = 12
        for _ in range(qd):
            i = skip_name(reply, i) + 4
        for _ in range(an):
            i = skip_name(reply, i)
            rtype, _cls, _ttl, rdlen = struct.unpack(">HHIH", reply[i : i + 10])
            i += 10
            rdata = reply[i : i + rdlen]
            i += rdlen
            if rtype == 1 and rdlen == 4:
                found.append(ipaddress.IPv4Address(rdata))
            elif rtype == 28 and rdlen == 16:
                found.append(ipaddress.IPv6Address(rdata))
    except (IndexError, struct.error):
        pass
    return found


def record(reply):
    # NOTE: reopened per write — the daemon takes the file over by renaming it.
    # 198.18/15 is Happ's fake-ip range: no real address to block there.
    lines = [
        f"{a} {int(time.time())}\n"
        for a in answer_addresses(reply)
        if a not in FAKE_IP
    ]
    if lines:
        with open(SEEN_FILE, "a") as f:
            f.writelines(lines)


def handle(sock, data, addr):
    if len(data) < 17:
        return
    try:
        reply = ask_upstream(data)
    except (OSError, struct.error):
        reply = servfail(data)
    else:
        try:
            record(reply)
        except OSError:
            pass
    sock.sendto(reply, addr)


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(LISTEN)
    while True:
        data, addr = sock.recvfrom(4096)
        threading.Thread(target=handle, args=(sock, data, addr), daemon=True).start()


if __name__ == "__main__":
    main()
