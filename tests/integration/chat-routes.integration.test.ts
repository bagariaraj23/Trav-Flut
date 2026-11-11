import { beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { cleanDb, createUser, getAuthToken } from "../testUtils";
import { GET as listConversationsRoute, POST as createConversationRoute } from "../../src/app/api/chat/conversations/route";
import { GET as getConversationRoute, PATCH as patchConversationRoute } from "../../src/app/api/chat/conversations/[id]/route";
import {
  GET as getMessagesRoute,
  POST as postMessageRoute,
} from "../../src/app/api/chat/conversations/[id]/messages/route";
import {
  PATCH as patchMessageRoute,
  DELETE as deleteMessageRoute,
} from "../../src/app/api/chat/conversations/[id]/messages/[messageId]/route";
import { PATCH as markReadRoute } from "../../src/app/api/chat/conversations/[id]/read/route";

function request(
  url: string,
  options: {
    method?: string;
    body?: unknown;
    token?: string;
  } = {}
): NextRequest {
  const headers = new Headers();
  headers.set("Content-Type", "application/json");
  if (options.token) headers.set("authorization", `Bearer ${options.token}`);
  return new NextRequest(url, {
    method: options.method ?? "GET",
    headers,
    body:
      options.body !== undefined ? JSON.stringify(options.body) : undefined,
  });
}

async function json(response: Response) {
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

describe("Chat API routes", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("returns 401 when listing conversations without auth", async () => {
    const response = await listConversationsRoute(
      request("http://localhost/api/chat/conversations")
    );
    expect(response.status).toBe(401);
  });

  it("creates a DM, sends messages, lists them, and marks read via HTTP handlers", async () => {
    const u1 = await createUser({ email: "route-u1@test.com" });
    const u2 = await createUser({ email: "route-u2@test.com" });
    const token1 = await getAuthToken(u1);
    const token2 = await getAuthToken(u2);

    const createResponse = await createConversationRoute(
      request("http://localhost/api/chat/conversations", {
        method: "POST",
        token: token1,
        body: { type: "DM", participantIds: [u2.id] },
      })
    );
    const createData = await json(createResponse);

    expect(createResponse.status).toBe(201);
    expect(createData.success).toBe(true);
    expect(createData.data.type).toBe("DM");
    const conversationId = createData.data.id as string;

    const listResponse = await listConversationsRoute(
      request("http://localhost/api/chat/conversations", { token: token2 })
    );
    const listData = await json(listResponse);

    expect(listResponse.status).toBe(200);
    expect(listData.success).toBe(true);
    expect(listData.data.conversations).toHaveLength(1);
    expect(listData.data.conversations[0].unreadCount).toBe(0);

    const sendResponse = await postMessageRoute(
      request(`http://localhost/api/chat/conversations/${conversationId}/messages`, {
        method: "POST",
        token: token1,
        body: { content: "Hello from route test" },
      }),
      { params: Promise.resolve({ id: conversationId }) }
    );
    const sendData = await json(sendResponse);

    expect(sendResponse.status).toBe(201);
    expect(sendData.success).toBe(true);
    expect(sendData.data.content).toBe("Hello from route test");
    const messageId = sendData.data.id as string;

    const messagesResponse = await getMessagesRoute(
      request(`http://localhost/api/chat/conversations/${conversationId}/messages`, {
        token: token2,
      }),
      { params: Promise.resolve({ id: conversationId }) }
    );
    const messagesData = await json(messagesResponse);

    expect(messagesResponse.status).toBe(200);
    expect(messagesData.success).toBe(true);
    expect(messagesData.data.messages).toHaveLength(1);
    expect(messagesData.data.messages[0].content).toBe("Hello from route test");

    const listAfterSend = await listConversationsRoute(
      request("http://localhost/api/chat/conversations", { token: token2 })
    );
    const listAfterSendData = await json(listAfterSend);
    expect(listAfterSendData.data.conversations[0].unreadCount).toBe(1);

    const readResponse = await markReadRoute(
      request(`http://localhost/api/chat/conversations/${conversationId}/read`, {
        method: "PATCH",
        token: token2,
      }),
      { params: Promise.resolve({ id: conversationId }) }
    );
    expect(readResponse.status).toBe(200);
    expect((await json(readResponse)).success).toBe(true);

    const editResponse = await patchMessageRoute(
      request(
        `http://localhost/api/chat/conversations/${conversationId}/messages/${messageId}`,
        {
          method: "PATCH",
          token: token1,
          body: { content: "Edited via route" },
        }
      ),
      { params: Promise.resolve({ id: conversationId, messageId }) }
    );
    const editData = await json(editResponse);
    expect(editResponse.status).toBe(200);
    expect(editData.data.content).toBe("Edited via route");

    const deleteResponse = await deleteMessageRoute(
      request(
        `http://localhost/api/chat/conversations/${conversationId}/messages/${messageId}`,
        {
          method: "DELETE",
          token: token1,
        }
      ),
      { params: Promise.resolve({ id: conversationId, messageId }) }
    );
    const deleteData = await json(deleteResponse);
    expect(deleteResponse.status).toBe(200);
    expect(deleteData.data.content).toBe("");
    expect(deleteData.data.deletedAt).toBeTruthy();
  });

  it("creates a group and updates details via PATCH conversation route", async () => {
    const admin = await createUser({ email: "route-admin@test.com" });
    const member = await createUser({ email: "route-member@test.com" });
    const token = await getAuthToken(admin);

    const createResponse = await createConversationRoute(
      request("http://localhost/api/chat/conversations", {
        method: "POST",
        token,
        body: {
          type: "GROUP",
          name: "Route Group",
          participantIds: [member.id],
        },
      })
    );
    const createData = await json(createResponse);
    const conversationId = createData.data.id as string;

    const patchResponse = await patchConversationRoute(
      request(`http://localhost/api/chat/conversations/${conversationId}`, {
        method: "PATCH",
        token,
        body: {
          name: "Renamed Route Group",
          avatarUrl: "https://example.com/group.png",
        },
      }),
      { params: Promise.resolve({ id: conversationId }) }
    );
    const patchData = await json(patchResponse);

    expect(patchResponse.status).toBe(200);
    expect(patchData.data.name).toBe("Renamed Route Group");
    expect(patchData.data.avatarUrl).toBe("https://example.com/group.png");

    const getResponse = await getConversationRoute(
      request(`http://localhost/api/chat/conversations/${conversationId}`, {
        token,
      }),
      { params: Promise.resolve({ id: conversationId }) }
    );
    const getData = await json(getResponse);
    expect(getResponse.status).toBe(200);
    expect(getData.data.name).toBe("Renamed Route Group");
  });

  it("rejects oversized message content at the route validation layer", async () => {
    const u1 = await createUser({ email: "route-long@test.com" });
    const u2 = await createUser({ email: "route-long2@test.com" });
    const token = await getAuthToken(u1);

    const createResponse = await createConversationRoute(
      request("http://localhost/api/chat/conversations", {
        method: "POST",
        token,
        body: { type: "DM", participantIds: [u2.id] },
      })
    );
    const conversationId = (await json(createResponse)).data.id as string;

    const sendResponse = await postMessageRoute(
      request(`http://localhost/api/chat/conversations/${conversationId}/messages`, {
        method: "POST",
        token,
        body: { content: "a".repeat(513) },
      }),
      { params: Promise.resolve({ id: conversationId }) }
    );

    expect(sendResponse.status).toBe(400);
    expect((await json(sendResponse)).success).toBe(false);
  });

  it("rejects non-participant access to conversation details", async () => {
    const u1 = await createUser({ email: "route-priv1@test.com" });
    const u2 = await createUser({ email: "route-priv2@test.com" });
    const outsider = await createUser({ email: "route-outsider@test.com" });
    const token1 = await getAuthToken(u1);
    const outsiderToken = await getAuthToken(outsider);

    const createResponse = await createConversationRoute(
      request("http://localhost/api/chat/conversations", {
        method: "POST",
        token: token1,
        body: { type: "DM", participantIds: [u2.id] },
      })
    );
    const conversationId = (await json(createResponse)).data.id as string;

    const getResponse = await getConversationRoute(
      request(`http://localhost/api/chat/conversations/${conversationId}`, {
        token: outsiderToken,
      }),
      { params: Promise.resolve({ id: conversationId }) }
    );

    expect(getResponse.status).toBe(403);
  });
});
