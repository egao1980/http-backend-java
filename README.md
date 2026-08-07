# http-backend-java

ABCL backends for [`http-protocol`](https://github.com/egao1980/http-protocol) and [`ws-protocol`](https://github.com/egao1980/ws-protocol) over **`java.net.http`** (`HttpClient` + `WebSocket`).

## Why

Java’s HttpClient is full-featured (HTTP/1.1 + HTTP/2, redirects, async `CompletableFuture`, RFC 6455 WebSocket). On ABCL this beats reimplementing HTTP over libuv FDs.

Pair with [`event-backend-nio`](https://github.com/egao1980/event-backend-nio) for the JVM event loop.

## Usage

```lisp
(asdf:load-system "http-backend-java")
(let* ((b (http-backend-java:make-java-backend))
       (c (http-protocol:make-http-client b))
       (r (http-protocol:send b c
            (http-protocol:make-http-request :url "https://example.com/"))))
  (http-protocol:response-status r))
```

WebSocket: same `java-backend` is a `ws-backend` — `ws-protocol:connect` / `send-text` / `on-event`.

## Requirements

- ABCL + JDK 11+ (21+ recommended)
- Optional: `--add-opens=java.base/java.util=ALL-UNNAMED` if header reflection complains
