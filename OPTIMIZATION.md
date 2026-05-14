# Chessing Optimization Handbook

A practical checklist tailored to **Flutter (Provider) + Bun/Elysia + MongoDB Atlas + WebSocket**. Audit against this before merging anything substantial.

---

## 1. Flutter — Rendering & State

### Rebuild discipline
- [ ] **No `Consumer` higher than necessary** — wrap the smallest widget that depends on the provider, not the whole `Scaffold`
- [ ] **Use `Selector` over `Consumer`** when only one field of a provider is needed (avoids rebuilding on unrelated state changes)
- [ ] **`const` constructors everywhere possible** — every static widget should be `const`
- [ ] **Avoid creating new closures inside `build()`** — extract callbacks as methods or final fields
- [ ] **No `setState` for animation tick** — use `AnimationController` + `AnimatedBuilder` instead
- [ ] **`ListView.builder` for long lists**, never `ListView(children: [...])` for >20 items
- [ ] **`ListView` items should be `const` or use `RepaintBoundary`** for complex tiles
- [ ] **Avoid `MediaQuery.of(context).size` inside builders** — pulls a full rebuild on rotation/keyboard
- [ ] **No expensive computation in `build()`** — memoize via fields, dispose-aware caches

### Async & lifecycle
- [ ] **All `Future`-returning calls use `mounted` check** before `setState`
- [ ] **`StreamSubscription`, `AnimationController`, `TextEditingController`, `ScrollController` all disposed**
- [ ] **No `BuildContext` use across `await` gaps** without an explicit `if (!mounted) return`
- [ ] **`Provider.of(context, listen: false)` in event handlers** — never trigger rebuilds from button taps
- [ ] **No `setState` inside `build()` or `initState` synchronously** — wrap in `WidgetsBinding.instance.addPostFrameCallback`

### Images & assets
- [ ] **`SVG`/vector for icons over PNGs** when scalability matters
- [ ] **`cacheWidth`/`cacheHeight`** on raster images
- [ ] **`fadeInDuration: Duration.zero`** for performance-critical images

---

## 2. Backend — Bun/Elysia Performance

### Async/await hygiene
- [ ] **Every `async` function call returning a Promise is `await`ed** when the result is used (the `makeMove` bug pattern)
- [ ] **DB writes are `await`ed** with proper error handling — never fire-and-forget critical writes
- [ ] **Use `Promise.all` for parallel independent operations** (e.g., fetching multiple users)
- [ ] **No blocking I/O inside hot loops** — never `await` inside a `for` if items are independent

### WebSocket
- [ ] **`ws.send()` always uses `JSON.stringify()`** — never raw objects
- [ ] **Message validation at entry** — reject malformed messages early
- [ ] **Rate limit per connection** — currently 60/min, adjust if needed
- [ ] **No message broadcast during DB writes** — use a queue if backpressure

### Memory & state
- [ ] **In-memory state has TTL or cleanup** — Maps shouldn't grow unbounded
- [ ] **Disconnected clients clean up all references** — game manager, user maps, ws subscriptions
- [ ] **Periodic cleanup intervals exist** for stale data (queues, finished games, expired challenges)

---

## 3. MongoDB — Queries & Indexes

### Indexes
- [ ] **Every field used in `find()`/`findOne()` has an index** — check Mongoose schemas
- [ ] **Compound indexes for multi-field queries** — order matters: most selective first
- [ ] **Indexes on sort fields** — `.sort({ field: -1 })` needs that field indexed
- [ ] **No duplicate indexes** — `unique: true` already creates one, don't add `.index()` for the same field

### Query patterns
- [ ] **Use `.lean()` when you don't need Mongoose document features** — much faster, less memory
- [ ] **`.select('field1 field2')` to project only needed fields** — reduce wire transfer
- [ ] **`.limit()` everywhere** — never return unbounded results
- [ ] **Pagination uses `skip + limit`** with reasonable max page size (e.g., 50)
- [ ] **Use `$inc`, `$set`, `$max`, `$min`, `$push` operators** — atomic, no read-modify-write race
- [ ] **Avoid `findOneAndUpdate` with `new: true`** unless you actually need the new doc back
- [ ] **Batch operations with `bulkWrite`** when doing many inserts/updates at once

### Data shape
- [ ] **Denormalize hot read paths** — store rating directly, not computed from games every time
- [ ] **Embed when 1:few ratio** (e.g., user.stats), reference when 1:many (e.g., user.games)
- [ ] **Cap embedded arrays** — use `$slice` operator on `$push` to limit size (rating history capped at 30)

---

## 4. Network & API

### REST
- [ ] **Pagination on all list endpoints** with default + max page size
- [ ] **Selective field projection** — clients shouldn't get fields they don't render
- [ ] **HTTP timeouts on all client calls** (we use 30s default, 60s for analysis)
- [ ] **Retry logic with exponential backoff** for transient failures

### Caching
- [ ] **Cache external API responses** — Lichess opening explorer, puzzles
- [ ] **`Cache-Control` headers on cacheable responses**
- [ ] **In-memory LRU for frequently-fetched user data**

---

## 5. Security (still part of optimization — prevents costly breaches)

- [ ] **JWT_SECRET mandatory env var** — server refuses to start without it
- [ ] **No client-trusted user IDs** — derive from JWT only
- [ ] **Input validation on every WebSocket message + REST endpoint**
- [ ] **MongoDB injection blocked** — operator blacklist + stage whitelist
- [ ] **Rate limit auth endpoints** to prevent brute force
- [ ] **CORS restricted** to known origins
- [ ] **No sensitive data in logs** (passwords, full tokens)

---

## 6. Anti-Patterns to Avoid

| Anti-pattern | Why bad | Fix |
|--------------|---------|-----|
| `setState` in a loop | Each call schedules a rebuild | Batch state updates |
| `Provider.of(context)` in event handlers | Causes rebuild even if state didn't change | Use `listen: false` |
| `Color.withOpacity()` | Deprecated in Flutter 3.27+ | Use `withValues(alpha:)` |
| `print()` in production code | Stays in release builds | Use `debugPrint` (auto-stripped) |
| Empty `catch (e) {}` | Silent failures | At minimum `debugPrint` the error |
| `Map.entries.toList()` for iteration | Allocates a list | Iterate directly |
| `String concatenation` in loops | O(n²) | Use `StringBuffer` or `join` |
| Loading entire collection into memory | OOM risk | Stream with cursor or paginate |
| `findById` then `save` for atomic ops | Race condition | Use `$set`/`$inc`/`$max` operators |
| Unbounded `setInterval` | Memory leak | Always have cleanup conditions |

---

## 7. Performance Budgets

| Metric | Target |
|--------|--------|
| Backend cold start | < 5s |
| `/health` response time | < 50ms |
| API p99 latency | < 500ms |
| WebSocket message round-trip | < 200ms (LAN) |
| Move broadcast latency | < 100ms |
| App cold start (release) | < 3s |
| Frame rate (game screen) | 60fps |
| Memory (idle) | < 150MB |
| Memory (in game) | < 250MB |
| Bundle size (Android release) | < 25MB |

---

## 8. Audit Process

Quarterly or before any major release:

1. Run `flutter analyze --no-fatal-infos` — must show 0 errors
2. Profile with Flutter DevTools — check for jank in main user flows
3. Run backend with profiler — identify slow endpoints
4. Review MongoDB slow query log
5. Check unused imports / dead code
6. Re-validate every item on this checklist

---

## References

- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
- [Bun Documentation](https://bun.sh/docs)
- [Elysia.js Best Practices](https://elysiajs.com/essential/best-practice.html)
- [MongoDB Query Optimization](https://www.mongodb.com/docs/manual/core/query-optimization/)
- Project-specific: `CLAUDE.md`, `PROGRESS.md`
