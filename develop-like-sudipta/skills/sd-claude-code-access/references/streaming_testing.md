# Streaming testing — WebSocket, SSE, and HTTP streams

This is a companion to `references/browser_testing.md`. Use it when the feature under test:
- Establishes a WebSocket connection (chat, live data, collaboration)
- Subscribes to Server-Sent Events (live notifications, progress feeds)
- Receives a streaming HTTP response (LLM token-by-token, file uploads with progress)

These flows are invisible to a screenshot-only test. You must observe the network frames + assert on their content.

## WebSocket testing via Claude in Chrome MCP

Chrome DevTools exposes WebSocket frames. The Claude-in-Chrome MCP can observe them via `read_network_requests` (filtered to `ws://` or `wss://`) and via `javascript_tool` to inspect `window.WebSocket` instances.

### Recommended assertions per WebSocket flow

| Intent | How to assert |
|---|---|
| Connection opens | Filter network for `ws://...`, assert `state: 101 Switching Protocols` |
| First message sent (client → server) | `read_network_requests` returns `frames: [{direction: "sent", payload: ...}]` |
| First message received (server → client) | `frames: [{direction: "received", payload: ...}]` — wait for it with a `find`-style poll |
| Ping/pong heartbeat alive | Periodically check `frames` length is increasing |
| Connection closes cleanly | Final frame has `direction: "close"`, code 1000 |

### Pattern: send-and-await

```typescript
// Playwright spec snippet (generated form)
test.step('chat: send + receive', async () => {
  const wsPromise = page.waitForEvent('websocket', { timeout: 5000 });
  await page.getByTestId('chat-input').fill('hello');
  await page.getByTestId('chat-send-button').click();
  const ws = await wsPromise;

  const sent = await new Promise<string>((resolve) => {
    ws.on('framesent', (event) => resolve(event.payload as string));
  });
  expect(JSON.parse(sent)).toMatchObject({ type: 'chat.send', body: 'hello' });

  const received = await new Promise<string>((resolve) => {
    ws.on('framereceived', (event) => resolve(event.payload as string));
  });
  expect(JSON.parse(received)).toMatchObject({ type: 'chat.ack' });
});
```

### Markdown schema for WebSocket assertions in the per-phase test md

Inside `## Network assertions` section, add a WebSocket subsection:

```markdown
**WebSocket frames:**
| Direction | URL pattern | Payload contains | Within (sec) |
|---|---|---|---|
| sent | wss://api/chat | type=chat.send body=hello | 1 |
| received | wss://api/chat | type=chat.ack | 2 |
```

## SSE testing

Server-Sent Events arrive as a long-lived `text/event-stream` response. Chrome MCP's `read_network_requests` shows the request as "pending" with periodic `data:` chunks.

### Pattern: subscribe-and-collect

```typescript
test.step('notifications: subscribe + receive', async () => {
  const messages: string[] = [];

  await page.exposeFunction('captureSSE', (msg: string) => { messages.push(msg); });

  await page.goto('/notifications');
  await page.evaluate(() => {
    const source = new EventSource('/api/notifications');
    source.onmessage = (e) => (window as any).captureSSE(e.data);
  });

  // Wait for at least one event
  await page.waitForFunction(() => (window as any).__captured?.length > 0, { timeout: 5000 });

  expect(messages.length).toBeGreaterThan(0);
  expect(messages[0]).toContain('type=heartbeat');
});
```

### Markdown schema for SSE assertions

```markdown
**SSE streams:**
| URL pattern | First event contains | Within (sec) |
|---|---|---|
| /api/notifications | type=heartbeat | 5 |
| /api/feed | event_id= | 3 |
```

## HTTP streaming (chunked response)

Common for LLM token-by-token output. Less standardized than WebSocket / SSE — depends on the API contract.

### Pattern: chunk-by-chunk

```typescript
test.step('llm: streaming output appears progressively', async () => {
  await page.getByTestId('prompt-input').fill('Write a haiku');
  await page.getByTestId('prompt-submit').click();

  // Wait for first chunk
  await expect(page.getByTestId('llm-output')).not.toBeEmpty({ timeout: 5000 });

  // Capture progressive content
  const intermediate = await page.getByTestId('llm-output').textContent();

  // Wait a moment for more chunks
  await page.waitForTimeout(500);
  const final = await page.getByTestId('llm-output').textContent();

  // Assertion: content GREW (proves streaming, not buffered response)
  expect(final!.length).toBeGreaterThan(intermediate!.length);
});
```

Note: `waitForTimeout` is normally an anti-pattern (per `references/playwright_generation.md`), but for "did content grow" assertions on streaming, a deliberate short wait is unavoidable. Document the wait in the markdown's `## Steps` section so a future maintainer knows it's intentional.

## Anti-patterns

- **Don't assert exact frame counts.** WebSocket protocols use ping/pong, reconnects, retries. Assert presence of expected message types, not totals.
- **Don't sleep then check.** Use `waitForEvent` / `waitForFunction` with timeouts. Sleep-then-check is flaky.
- **Don't capture full SSE history forever.** Long-lived streams accumulate megabytes of data — extract only what you need from the first N events.
- **Don't test that connections stay open for long.** Test that the protocol works correctly for the operations your app actually performs. Connection-stability tests belong in load testing, not e2e.

## When this doesn't apply

If your feature uses streams but the user-visible result is identical to a non-streaming version (e.g., the streamed LLM output is displayed all-at-once after streaming completes), test the OUTCOME, not the streaming mechanism. Save streaming-specific tests for cases where the streaming itself is part of the UX promise.

## See also

- `references/browser_testing.md` — base browser-test loop
- `references/playwright_generation.md` — selector strategy, idempotent emission rules
