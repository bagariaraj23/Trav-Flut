"use strict";

/**
 * Shared in-process event bus for chat real-time events.
 * Loaded by server.cjs before Next.js so API routes and chat-ws use the same instance.
 * Without this, the bundled chat-ws has its own chat-events copy and never receives publishes.
 */
const listeners = new Set();

function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

function publish(payload) {
  listeners.forEach((fn) => {
    try {
      fn(payload);
    } catch (e) {
      console.error("[ChatEventBus] Listener error:", e);
    }
  });
}

global.chatEventBus = { subscribe, publish };
module.exports = global.chatEventBus;
