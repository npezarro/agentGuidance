# Backend Experience Log

---
## 2026-04-02 | groceryGenius API layer
**Task:** Design the recipe import endpoint to accept URLs, parse ingredients, and return structured recipe data.
**What worked:** Contract-first approach: defined the request/response JSON shapes before writing any parsing logic. Input validation at the boundary (URL format, content-type header) caught malformed requests early. Returning partial results with a warnings array (instead of failing the whole request) handled pages with unparseable ingredient lines gracefully.
**What didn't:** Initially built a single monolithic handler that fetched, parsed, and stored in one function. Extracting the parser into a separate service module after the fact required reworking error propagation. Should have separated concerns from the start.
**Learned:** For endpoints that do fetch-parse-store, split into discrete service functions from day one. The error handling strategy differs at each stage (network errors vs parse errors vs DB errors), and mixing them in one function makes retry logic impossible to reason about.

---
## 2026-03-28 | botlink authentication flow
**Task:** Implement OAuth callback handler for BotLink's bot registration, exchanging auth codes for tokens and creating bot profile records.
**What worked:** Stateless JWT for the API layer with short expiry (15min) and refresh tokens stored server-side. The middleware chain (validateToken -> extractUser -> checkBotOwnership) kept route handlers clean. Idempotent bot creation (upsert on external platform ID) prevented duplicate records from double-submitted callbacks.
**What didn't:** Tried using cookie-based sessions for the API initially, thinking it would simplify the OAuth flow. Abandoned it because the bot registration clients are not browsers; they are CLI tools and webhooks that do not send cookies reliably.
**Learned:** Match your auth mechanism to your client type. Cookie sessions work for browser-based web apps. Token-based auth works for APIs consumed by non-browser clients. When the consumer is a mix, offer both but keep the server-side validation identical.

---
## 2026-03-22 | runeval results API
**Task:** Build the endpoint that accepts eval run results, validates them against the registered eval schema, and stores them with proper indexing.
**What worked:** JSON Schema validation at the boundary using ajv, with custom error messages that reference the specific field path. Batch insert with a transaction wrapper so partial uploads do not leave orphaned records. Returning the validation errors in a structured array (field, expected, actual) made debugging failed submissions straightforward.
**What didn't:** Initially returned raw ajv error objects directly, which contained internal schema references and cryptic paths like "/properties/metrics/items/0/type". Had to write a transformer to produce human-readable error messages.
**Learned:** Never expose raw validation library errors to API consumers. Always transform them into a consistent, human-readable format with field paths that match the consumer's mental model of the request body.

---
## 2026-03-19 | pezantTools upload middleware
**Task:** Refactor the file upload endpoint to support chunked uploads with progress tracking and resumability.
**What worked:** Middleware chain: multer for parsing multipart, then a custom chunk-tracking middleware that checks for existing partial uploads before accepting new chunks, then the storage handler. The chunk metadata (offset, total size, hash) stored in a simple JSON file per upload session kept the implementation stateless across requests.
**What didn't:** Tried using streaming directly to disk without buffering, but the hash verification step required reading the full chunk into memory anyway. The streaming approach added complexity without the expected memory savings for chunks under 5MB.
**Learned:** Streaming is not always the right choice for file uploads. If you need to verify integrity (hash check) before persisting, you are buffering regardless. For small chunks (under 5MB), a simple buffer-then-write approach is clearer and equally performant.
