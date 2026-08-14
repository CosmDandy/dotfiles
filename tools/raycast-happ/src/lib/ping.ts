import { connect } from "node:net";

/**
 * Time to complete a TCP handshake with the server.
 *
 * This is not the tunnel's latency — it measures the path to the endpoint,
 * which is the only thing measurable without connecting through it. Happ's own
 * Ping action covers the live connection and nothing else, so this is what
 * makes the other servers comparable at all.
 *
 * Hysteria2 is UDP-only, so a TCP probe to its port says nothing about whether
 * the server answers — callers decide what to do with that.
 */
export function tcpPing(
  host: string,
  port: number,
  timeoutMs = 3000,
): Promise<number | undefined> {
  return new Promise((resolve) => {
    const started = Date.now();
    const socket = connect({ host, port });

    const done = (value?: number) => {
      socket.removeAllListeners();
      socket.destroy();
      resolve(value);
    };

    socket.setTimeout(timeoutMs);
    socket.once("connect", () => done(Date.now() - started));
    socket.once("timeout", () => done(undefined));
    socket.once("error", () => done(undefined));
  });
}

/** Probe several servers at once, keeping the fan-out modest. */
export async function pingAll<T extends { host: string; port: number }>(
  targets: T[],
  concurrency = 8,
): Promise<Map<string, number | undefined>> {
  const results = new Map<string, number | undefined>();
  const queue = [...targets];

  const workers = Array.from(
    { length: Math.min(concurrency, queue.length) },
    async () => {
      for (;;) {
        const target = queue.shift();
        if (!target) return;
        const key = `${target.host}:${target.port}`;
        if (results.has(key)) continue;
        results.set(key, await tcpPing(target.host, target.port));
      }
    },
  );

  await Promise.all(workers);
  return results;
}
