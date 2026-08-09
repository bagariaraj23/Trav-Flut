"use strict";

// Shared chat event bus - must load before Next/chat-ws so API and WS use same instance
require("./lib/chat-events-bus.cjs");

// Next.js expects globalThis.AsyncLocalStorage (set by its CLI). Set it for custom server.
const { AsyncLocalStorage } = require("async_hooks");
globalThis.AsyncLocalStorage = AsyncLocalStorage;

const { createServer } = require("http");
const { parse } = require("url");
const next = require("next");
const { WebSocketServer } = require("ws");
const { attachChatWebSocket } = require("./dist/chat-ws.cjs");

const port = parseInt(process.env.PORT || "3000", 10);
const dev = process.env.NODE_ENV !== "production";
const app = next({ dev });
const handle = app.getRequestHandler();

app.prepare().then(() => {
  const server = createServer((req, res) => {
    const parsedUrl = parse(req.url, true);
    handle(req, res, parsedUrl);
  });

  const wss = new WebSocketServer({ noServer: true });
  attachChatWebSocket(wss);

  server.on("upgrade", (req, socket, head) => {
    const { pathname } = parse(req.url || "", true);
    if (pathname === "/chat") {
      wss.handleUpgrade(req, socket, head, (ws) => {
        wss.emit("connection", ws, req);
      });
    } else {
      socket.destroy();
    }
  });

  const host = process.env.HOST || "0.0.0.0";
  server.listen(port, host, () => {
    console.log(
      `> Server listening at http://${host}:${port} (${dev ? "development" : "production"})`
    );
    console.log("> WebSocket chat endpoint: ws://" + (host === "0.0.0.0" ? "localhost" : host) + ":" + port + "/chat");
  });
});
