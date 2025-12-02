**`mitt` – Architecture Document**

---

## Overview

A CLI tool for ephemeral file/data transfer. One party opens a "mitt" (a publicly reachable inbox), others send to it. No accounts, no central server we control—tunneling handled by third-party providers (bore, cloudflare, etc.).

---

## Core Components

```
mitt/
├── src/
│   ├── main.zig           # Entry point, arg parsing, subcommand dispatch
│   ├── server.zig         # HTTP server for receiving data
│   ├── client.zig         # HTTP client for sending data
│   ├── tunnel.zig         # Tunnel provider abstraction + bore implementation
│   ├── id.zig             # Human-readable ID generation
│   ├── filter.zig         # Accept/reject logic (extension, size, MIME)
│   ├── storage.zig        # Write incoming files to disk
│   └── config.zig         # Config file parsing, defaults
├── build.zig
└── wordlist.txt           # Words for ID generation (embedded at compile time)
```

---

## Subcommands

### `mitt open`

Starts a local server, establishes tunnel, prints mitt ID, waits for incoming data.

**Flags:**
- `--port <port>` – Local port (default: random available)
- `--id <name>` – Request specific ID if provider supports it (default: generated)
- `--via <provider>` – Tunnel provider (default: `bore`)
- `--dir <path>` – Where to save files (default: `./inbox`)
- `--stdout` – Print incoming data to stdout instead of saving
- `--accept <globs>` – Comma-separated whitelist (e.g., `*.txt,*.csv`)
- `--reject <globs>` – Comma-separated blacklist (e.g., `*.exe`)
- `--max-size <bytes>` – Reject files larger than this (default: 100mb)

**Flow:**
1. Parse flags, load config
2. Bind local HTTP server on port
3. Call `tunnel.establish(provider, port)` → returns public URL + ID
4. Print `Your mitt: {id}@{provider}`
5. Loop: accept connections, validate against filters, save/stream, send ACK

**HTTP endpoint:**

```
POST /
Headers:
  X-Filename: <original filename>
  X-Size: <size in bytes>
  Content-Type: <MIME type>
Body: raw file bytes
```

**Responses:**
- `200 OK` + body `{"status": "received", "filename": "...", "size": ...}`
- `403 Forbidden` + body `{"error": "file type not accepted"}`
- `413 Payload Too Large` + body `{"error": "max size 100mb, got 243mb"}`

---

### `mitt send <id@provider> <payload>`

Sends data to an open mitt.

**Arguments:**
- `<id@provider>` – Target (e.g., `blue-fox-42@bore`)
- `<payload>` – File path, or `-` for stdin

**Flags:**
- `--text <string>` – Send literal text instead of file
- `--timeout <seconds>` – How long to wait for ACK (default: 30)

**Flow:**
1. Parse `id@provider` → resolve to URL (e.g., `https://blue-fox-42.bore.pub`)
2. Read payload (file, stdin, or text flag)
3. POST to URL with headers (filename, size, content-type)
4. Wait for response
5. Print result: "Delivered." or error message
6. Exit code: 0 = success, 1 = rejected, 2 = timeout/unreachable

---

## Module Details

### `server.zig`

- Use `std.http.Server` (or raw TCP + minimal HTTP parsing if more control needed)
- Single-threaded is fine for prototype
- Parse incoming headers, validate via `filter.check()`, pass body to `storage.save()`
- Return JSON response

**Interface:**
```zig
pub const Server = struct {
    pub fn init(port: u16, config: Config) !Server
    pub fn run(self: *Server) !void  // Blocks, runs accept loop
    pub fn shutdown(self: *Server) void
};

pub const IncomingFile = struct {
    filename: []const u8,
    size: u64,
    content_type: []const u8,
    body_reader: std.io.AnyReader,
};

pub const HandleResult = union(enum) {
    accepted: struct { filename: []const u8, bytes_written: u64 },
    rejected: struct { code: u16, message: []const u8 },
};
```

---

### `client.zig`

- Use `std.http.Client`
- Build request with headers, stream body from file
- Parse response, return structured result

**Interface:**
```zig
pub const SendResult = union(enum) {
    delivered: struct { reply: ?[]const u8 },
    rejected: struct { reason: []const u8 },
    failed: struct { err: []const u8 },
    timeout,
};

pub fn send(url: []const u8, payload: Payload, timeout_ms: u64) !SendResult

pub const Payload = union(enum) {
    file: []const u8,   // Path
    stdin,
    text: []const u8,
};
```

---

### `tunnel.zig`

Abstraction over tunnel providers. Prototype only needs bore.

**Interface:**
```zig
pub const Provider = enum {
    bore,
    // Future: cloudflare, ngrok
};

pub const Tunnel = struct {
    public_url: []const u8,
    id: []const u8,
    process: std.ChildProcess,

    pub fn establish(provider: Provider, local_port: u16, requested_id: ?[]const u8) !Tunnel
    pub fn shutdown(self: *Tunnel) void
};
```

**Bore implementation:**
- Spawn `bore local <port> --to bore.pub`
- Parse stdout for assigned URL
- If `--id` requested, bore may not support custom subdomains—fall back to whatever it assigns, or error

**Note:** bore must be installed on system. Alternatively, could vendor bore or use libcurl to implement the tunnel protocol directly (future).

---

### `id.zig`

Generates human-readable IDs like `blue-fox-42`.

**Interface:**
```zig
pub fn generate() []const u8   // e.g., "calm-river-73"
pub fn parse(id: []const u8) struct { words: []const []const u8, number: u16 }
```

**Implementation:**
- Embed wordlist at compile time (`@embedFile("wordlist.txt")`)
- Pick 2 random words + 2-digit number
- ~10k words × 10k words × 100 = 10 billion combinations

---

### `filter.zig`

Checks incoming files against accept/reject rules.

**Interface:**
```zig
pub const Filter = struct {
    accept_globs: ?[]const []const u8,
    reject_globs: ?[]const []const u8,
    max_size: u64,

    pub fn check(self: Filter, filename: []const u8, size: u64, content_type: []const u8) FilterResult
};

pub const FilterResult = union(enum) {
    ok,
    rejected_extension: []const u8,
    rejected_size: struct { max: u64, got: u64 },
    rejected_type: []const u8,
};
```

**Glob matching:**
- Simple extension matching is enough for prototype (`*.txt` matches `.txt` suffix)
- Don't need full glob semantics

---

### `storage.zig`

Handles writing incoming data to disk.

**Interface:**
```zig
pub fn save(dir: []const u8, filename: []const u8, reader: std.io.AnyReader) !struct { path: []const u8, bytes: u64 }
```

**Behavior:**
- Create dir if not exists
- Handle filename collisions: `file.txt` → `file_1.txt` → `file_2.txt`
- Stream to disk (don't buffer entire file in memory)

---

### `config.zig`

Optional config file at `~/.config/mitt/config.zon` or similar.

```zig
pub const Config = struct {
    default_provider: Provider = .bore,
    default_dir: []const u8 = "./inbox",
    max_size: u64 = 100 * 1024 * 1024,
    accept: ?[]const []const u8 = null,
    reject: ?[]const []const u8 = null,
};

pub fn load() Config   // Returns defaults if no file
```

---

## Error Handling

- Use Zig's error unions throughout
- `main.zig` catches top-level errors, prints human-readable message, exits with appropriate code
- No panics in library code

---

## Testing Strategy

- Unit tests for `filter.zig`, `id.zig` (pure logic)
- Integration test: spawn `mitt open` in subprocess, run `mitt send` against it, verify file arrives
- Manual testing with actual bore tunnel

---

## Dependencies

- Zig standard library only for prototype
- External: `bore` CLI must be in PATH

---

## Future Considerations (not in prototype)

- Dead drop mode (`--for`, `--claim`)
- Interactive `--confirm` before accepting
- `--exec <cmd>` to process incoming data
- `--reply` for custom response content
- Encryption (encrypt client-side, decrypt on claim)
- Additional tunnel providers (cloudflare, ngrok)
- Persistent ID registration with a provider

---

## Example Session

```bash
# Terminal 1
$ mitt open --accept "*.txt,*.json" --max-size 10mb
Your mitt: green-moon-17@bore
Waiting for files...

Received: notes.txt (421 bytes) -> ./inbox/notes.txt

# Terminal 2
$ mitt send green-moon-17@bore ./notes.txt
Delivered.

$ mitt send green-moon-17@bore ./huge.zip
Rejected: max size 10mb, got 243mb

$ mitt send green-moon-17@bore ./script.exe
Rejected: file type not accepted (allowed: *.txt, *.json)
```

---
