declare module "ws" {
  import type { IncomingMessage } from "http";
  import type { Duplex } from "stream";
  export class WebSocket extends globalThis.WebSocket {
    constructor(address: string | URL, protocols?: string | string[]);
    readyState: number;
    send(data: string | Buffer | ArrayBufferView): void;
    close(code?: number, reason?: string): void;
    on(event: "message", cb: (data: Buffer | string) => void): this;
    on(event: "close", cb: () => void): this;
    on(event: "error", cb: (err: Error) => void): this;
  }
  export class WebSocketServer {
    constructor(options?: { noServer?: boolean });
    handleUpgrade(
      request: IncomingMessage,
      socket: Duplex,
      head: Buffer,
      callback: (ws: WebSocket) => void
    ): void;
    emit(event: "connection", ws: WebSocket, request: IncomingMessage): void;
    on(event: "connection", callback: (ws: WebSocket, request?: IncomingMessage) => void): this;
  }
}
