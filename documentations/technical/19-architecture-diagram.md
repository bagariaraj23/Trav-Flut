# Architecture diagram

This is the whole application on one page: who talks to whom, which process owns which data, and how a trip moves through the system. The diagrams are [Mermaid](https://mermaid.js.org/). Miro can import them (board menu, **Import**, or paste into a Mermaid frame, depending on your Miro plan). Each fenced block is one frame. Import them as separate frames on one board, left to right, in the order below.

Nothing here is a new runtime. It is the structure in `server.cjs`, `src/`, `mobile/`, `scheduler/`, and `prisma/schema.prisma`.

## 1. System context

Who is outside the codebase, and who is inside.

```mermaid
flowchart TB
  traveler["Traveler on iOS, Android, or the Docker web UI"]
  subgraph tripThread ["TripThread"]
    app["Flutter app"]
    api["API and chat process"]
    cron["Trip status script"]
    db["PostgreSQL"]
  end
  cloudinary["Cloudinary"]
  mapbox["Mapbox"]
  sendgrid["SendGrid"]
  google["Google sign-in"]
  upstash["Upstash Redis"]

  traveler --> app
  app --> api
  app --> cloudinary
  app --> mapbox
  api --> db
  api --> upstash
  api --> cloudinary
  api --> mapbox
  api --> sendgrid
  api --> google
  cron --> db
```

The phone uploads bytes to Cloudinary and draws Mapbox tiles itself. The API only signs uploads, confirms them, and geocodes search text. The status script never calls Redis, Cloudinary, or Mapbox.

## 2. Containers and processes

```mermaid
flowchart LR
  subgraph client ["Client"]
    flutter["Flutter\nProvider, GoRouter, Dio\nsecure storage or web local storage"]
  end

  subgraph edge ["Local web edge"]
    nginx["nginx :8080\nproxies /api /chat /share\npassword reset pages"]
  end

  subgraph process ["Node server.cjs :3000"]
    next["Next.js App Router\nREST /api"]
    socket["ws on /chat\nJWT in first frame\nheartbeat 30s"]
    bus["global.chatEventBus\nin-process only"]
  end

  subgraph jobs ["Scheduler"]
    tick["updateTripStatuses\nonce, then exit"]
  end

  subgraph stores ["Stores"]
    pg[("PostgreSQL\nPrisma")]
    redis[("Upstash Redis REST\ncache, locks, rate limits")]
  end

  flutter -->|"phone: direct"| next
  flutter -->|"phone: ws"| socket
  flutter -->|"Docker web"| nginx
  nginx --> next
  nginx --> socket
  next --> pg
  next --> redis
  next --> bus
  socket --> bus
  tick --> pg
```

Production on Railway runs `node server.cjs` from Railpack. The nginx box is the Docker web image, not a production edge you have to deploy separately for the native apps.

## 3. API domains inside the one process

Every box is a folder of route handlers plus a service module. They share one Prisma client and one Redis client pair. They are not network services.

```mermaid
flowchart TB
  dio["Dio Bearer access token"]
  mw["withAuth\nrate limit\nZod"]

  subgraph domains ["Domains"]
    auth["Auth\nsignup login Google\nrefresh logout"]
    reset["Password reset\nhash, FOR UPDATE, email"]
    users["Profile privacy\nsearch delete"]
    follow["Follow\npublic edge or request"]
    trips["Trips\nschedule members invites"]
    thread["Thread and final post"]
    money["Expenses and settlements"]
    media["Media signature and confirm"]
    places["Places search and resolve"]
    feed["Home, live, discover"]
    engage["Likes comments shares"]
    notes["Notifications"]
    chat["Chat REST"]
  end

  dio --> mw
  mw --> auth
  mw --> reset
  mw --> users
  mw --> follow
  mw --> trips
  mw --> thread
  mw --> money
  mw --> media
  mw --> places
  mw --> feed
  mw --> engage
  mw --> notes
  mw --> chat
```

Rate presets sit on the middleware, not inside each domain. Auth routes use the small auth windows. Feed, profile, and notifications use `read_hot` at 240 per minute. Chat send uses `chat_message` at 30 per minute. The numbers are in [Redis](./09-redis-cache-and-queues.md).

## 4. Full runtime diagram

This is the board to pin as the large frame. Solid arrows are request paths. The scheduler and the chat bus are called out so they are not mistaken for Redis jobs.

```mermaid
flowchart TB
  subgraph clients ["Clients"]
    phone["Flutter iOS and Android\nflutter_secure_storage"]
    web["Flutter web\nshared_preferences"]
    resetPage["Browser reset page\ncurrent password required"]
  end

  subgraph edge ["nginx :8080 Docker only"]
    proxy["Proxy /api /chat /share\n/.well-known and reset pages"]
  end

  subgraph api ["server.cjs"]
    rest["REST /api"]
    ws["WebSocket /chat"]
    bus["In-process event bus"]
  end

  subgraph logic ["Domain logic"]
    auth["Auth and users"]
    social["Follow"]
    trip["Trip lifecycle"]
    post["Thread and final post"]
    ledger["Expense ledger"]
    cdn["Media"]
    geo["Places"]
    home["Feed and discover"]
    act["Engagement"]
    inbox["Notifications"]
    rooms["Chat service"]
  end

  subgraph data ["Data"]
    pg[("PostgreSQL")]
    mem["Process LRU"]
    redis[("Upstash Redis")]
  end

  subgraph outside ["External"]
    cld["Cloudinary"]
    mb["Mapbox Geocoding v6\nand map tiles"]
    mail["SendGrid"]
    gid["Google ID tokens"]
  end

  cron["Scheduler\nno Redis"]

  phone --> rest
  phone --> ws
  phone -->|"bytes"| cld
  phone -->|"tiles and static map"| mb
  web --> proxy
  resetPage --> proxy
  proxy --> rest
  proxy --> ws

  rest --> auth
  rest --> social
  rest --> trip
  rest --> post
  rest --> ledger
  rest --> cdn
  rest --> geo
  rest --> home
  rest --> act
  rest --> inbox
  rest --> rooms

  auth --> pg
  social --> pg
  trip --> pg
  post --> pg
  ledger --> pg
  cdn --> pg
  geo --> pg
  home --> pg
  act --> pg
  inbox --> pg
  rooms --> pg

  auth --> mail
  auth --> gid
  cdn --> cld
  geo --> mb
  geo --> mem
  geo --> redis
  inbox --> redis
  act --> redis
  rest --> redis

  rooms --> bus
  bus --> ws
  cron --> pg
```

Read this frame with three rules:

1. Redis is beside the API, not beside the scheduler, and not on the chat bus.
2. Cloudinary is reached by the phone for bytes and by the API for signatures, magic-number reads, and deletes.
3. Mapbox is reached by the phone for tiles and by the API for place search.

## 5. Session and password

```mermaid
sequenceDiagram
  participant App as Flutter
  participant API as Auth routes
  participant DB as Postgres
  participant Mail as SendGrid

  App->>API: POST /auth/login email or username
  API->>DB: find user, bcrypt compare
  API->>DB: insert refresh row 30 days
  API-->>App: access 24h and refresh
  Note over App: 401 on a normal route
  App->>API: POST /auth/refresh-token one in flight
  API->>DB: rotate refresh row
  App->>API: POST /auth/forgot-password
  API->>DB: SHA-256 token, invalidate older unused
  API->>Mail: reset link TTL 15 min
  App->>API: POST /auth/reset-password
  Note over API: Web sends currentPassword. Mobile currently does not.
  API->>DB: FOR UPDATE, set usedAt, then new hash
  API->>DB: delete every refresh token
```

## 6. Trip life, from create to the feed

```mermaid
flowchart TD
  create["POST /trips\none owned active trip\nor replaceExisting ends the old one"]
  upcoming["UPCOMING\nstart in the future"]
  ongoing["ONGOING\nthread is writable"]
  ended["ENDED"]
  draft["TripFinalPost\nunpublished DRAFT\nper member"]
  published["isPublished\nhome feed index"]

  create -->|"start <= now"| ongoing
  create -->|"start > now"| upcoming
  upcoming -->|"start reached\ncron or read-path sync"| ongoing
  upcoming -->|"end passed"| ended
  ongoing -->|"end passed or POST /end"| ended
  ended -->|"PATCH dates extend\nonly if no final post"| ongoing
  ended --> draft
  draft -->|"PUT edits\nPOST /publish\nsummary >= 50 chars and media"| published

  ongoing --> text["TEXT entry"]
  ongoing --> media["MEDIA entry\nCloudinary then confirm"]
  ongoing --> loc["LOCATION entry\nresolve Place"]
  ongoing --> expense["Expense\nsplit into minor units"]
  expense --> settle["Payee marks a simplify-debts edge PAID"]
  settle --> leave["Leave, remove, or delete account\nblocked while net != 0"]
```

Members are the owner (`trips.userId`) plus `trip_participants`. The owner is not inserted into the participant table. Invites are `trip_join_requests`. A private owner can only invite people who already follow them.

Chat: create ensures a `TRIP` conversation. Leaving that room does not leave the trip. The next participant sync does not undo a chat leave.

## 7. Social and privacy

```mermaid
flowchart TD
  viewer["Signed-in viewer"]
  target{"Target isPrivate?"}
  followNow["Insert Follow\nnotify FOLLOW"]
  request["Insert FollowRequest PENDING"]
  accept["Accept inserts Follow\nno FOLLOW notification"]
  profile["Profile\nfollower sees a reduced private profile"]
  feed["Home feed\nself, follows, and all public final posts"]
  discover["Discover\nfollowed owners or public owners\nnot my own trips"]
  invite["Trip invite\nprivate owner requires the invitee already follows"]

  viewer --> target
  target -->|no| followNow
  target -->|yes| request
  request --> accept
  followNow --> profile
  accept --> profile
  followNow --> feed
  accept --> feed
  followNow --> discover
  accept --> invite
```

Unfollow deletes the follow edge and every request between the pair. Restrict and Block live on `user_safety_relations`, not on `follows`. Block also deletes the target's follow of the actor.

## 8. Media and places

```mermaid
sequenceDiagram
  participant App as Flutter
  participant API as API
  participant C as Cloudinary
  participant M as Mapbox
  participant DB as Postgres
  participant R as Redis

  App->>API: POST /media/cloudinary-signature
  API->>DB: daily cap and per-trip cap
  API-->>App: signed folder and public_id
  App->>C: multipart auto/upload
  App->>API: POST /media/confirm
  API->>C: first 512 bytes
  API->>DB: quota, insert Media

  App->>API: GET /places/search?q=
  API->>R: plc:srch 15 min
  alt miss
    API->>DB: name contains
    API->>M: Geocoding v6 forward 2s timeout
    API->>DB: dedupe and upsert
  end
  App->>API: POST /places/resolve
  API->>R: lock external id or spatial key
  API->>DB: one Place row
```

Pin labels on the map do not use this sequence. The device geocoder names the pin, then resolve stores the coordinates. Location permission is while-in-use only.

## 9. Feed, engagement, inbox

```mermaid
flowchart LR
  publish["Published final post"]
  home["GET /feed/home\nkeyset cursor\nentryCount participantCount\nbatch like status"]
  live["GET /feed/live-trips\none ONGOING trip per person\ncap 60"]
  disc["GET /discover/trips\nSQL rank then one findMany\nspend hidden unless opted in"]

  like["Like transaction\nunique user entity\nincrement likeCount"]
  comment["Comment\ndepth 1\nmentions TAG"]
  share["Share token\nSYSTEM_SHEET does not bump shareCount"]
  note["Notification row\nor pending follow request"]
  badge["Unread count\nRedis 20s\nfollow requests excluded"]

  publish --> home
  publish --> disc
  home --> like
  like --> note
  comment --> note
  note --> badge
  live --> disc
```

`GET /posts/TRIP_FINAL_POST/:id` is the deeplink. Thread entries are not opened on that route. They use the thread context window.

## 10. Money

```mermaid
flowchart TD
  add["POST expense\nEQUAL EXACT PERCENT or SHARES\nintegers only"]
  shares["trip_expense_shares\nsum equals amountMinor"]
  net["net = paid - owed + settledOut - settledIn"]
  sim["simplifyDebts\nlargest creditor to largest debtor\nstable userId tie-break"]
  paid["POST settlement\npayee only\nFOR UPDATE\nmust match an open edge"]
  lock["Expense delete locked\nafter any PAID settlement"]
  gate["409 UNSETTLED_BALANCE\non leave, kick, or account delete"]

  add --> shares --> net --> sim --> paid --> lock
  net --> gate
```

No payment provider is called. `PAID` means the payee tapped Mark as paid.

## 11. Chat delivery

```mermaid
sequenceDiagram
  participant A as Sender
  participant API as POST /chat/.../messages
  participant DB as Postgres
  participant Bus as chatEventBus
  participant B as Other sockets on this process

  A->>API: content, reply, media ids
  API->>DB: insert message, link media
  API-->>A: message
  API--)Bus: message.new
  Bus--)B: fan-out by cached participant ids
  Note over Bus: A second API replica would not see this event.\nUpstash REST cannot SUBSCRIBE.
```

History on reconnect is REST, cursor `before` message id. Unread counts for the room list are one `GROUP BY`, not one count per room.

## 12. Data stores by domain

Paste this as a table frame next to the large diagram.

| Store | Holds | Does not hold |
| --- | --- | --- |
| PostgreSQL | Users, sessions, resets, follows, trips, entries, final posts, places, media rows, expenses, settlements, likes, comments, shares, notifications, conversations, messages | File bytes, map tiles, email |
| Upstash Redis | Place search and identity, unread badge, share token, rate-limit windows, resolve locks, cache locks | Jobs, chat pub/sub, scheduler state |
| Process memory | LRU in front of Redis, chat participant LRU, chat event bus, performance timings, last 1000 errors | Anything that must survive a restart |
| Cloudinary | Image and video bytes, `public_id` under `tripthread_uploads/{userId}` | The `Media` row. That is Postgres |
| Mapbox | Geocoding responses and, on device, tiles | Canonical places. Those are Postgres after resolve |
| Phone secure store | Access and refresh tokens on iOS and Android | The web Docker build, which uses local storage |

## 13. Hot indexes on the same board

These are the indexes a reader should be able to point at from the feed, thread, inbox, and scheduler frames. The full why is [Optimizations](./18-optimizations.md).

| Index | Frame it belongs to |
| --- | --- |
| `trip_final_posts (isPublished, createdAt DESC, id DESC)` | Home feed |
| `trip_thread_entries (tripId, createdAt DESC, id DESC)` | Thread |
| `trips (status, endDate)` and `(status, startDate)` | Scheduler |
| `trips (userId, status)` | One active owned trip |
| `notifications (recipientId, createdAt DESC, id DESC)` | Inbox |
| `follow_requests (followeeId, status, createdAt DESC)` | Private follow |
| `places (lat, lng)` btree `coordinate_spatial_idx` | Place resolve |
| `chat_messages (conversationId, createdAt DESC)` | Chat history and unread |
| `likes (userId, entityType, entityId)` unique | Like idempotency |

## How to lay the Miro board

Suggested columns, left to right:

1. Clients and nginx.
2. `server.cjs` with REST, WebSocket, and the in-process bus.
3. The domain row from section 3.
4. PostgreSQL in the center bottom, Redis to its right, external systems above Redis.
5. The scheduler as its own sticky, with an arrow only into PostgreSQL.
6. Under the domain row, the four sequence frames: session, trip life, media and places, chat.
7. The index table as a legend along the bottom.

Color is optional. If you color anything, use one color for "writes Postgres", one for "calls an external API", and leave Redis and the scheduler uncolored except for their own borders, so the two common misconceptions stay visible: Redis is not the queue, and the scheduler is not part of the API process.
