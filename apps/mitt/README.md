# mitt

A CLI tool for ephemeral file/data transfer. One party opens a "mitt" (a publicly reachable inbox), others send to it.

## Features

- No accounts or central server required
- Tunneling via third-party providers (bore)
- Human-readable IDs (e.g., `blue-fox-42`)
- File filtering by extension and size
- Send files, stdin, or text

## Prerequisites

- Zig 0.14.0 or later
- [bore](https://github.com/ekzhang/bore) CLI installed in your PATH

```bash
# Install bore
cargo install bore-cli
```

## Building

```bash
cd apps/mitt
zig build
```

The binary will be at `zig-out/bin/mitt`.

## Usage

### Open a mitt (receive files)

```bash
# Basic usage - receive files to ./inbox
mitt open

# Specify custom directory
mitt open --dir ~/downloads

# Accept only specific file types
mitt open --accept "*.txt,*.json,*.csv"

# Reject specific file types
mitt open --reject "*.exe,*.sh"

# Limit file size (in bytes)
mitt open --max-size 10485760  # 10MB

# Print received data to stdout instead of saving
mitt open --stdout

# Use specific port
mitt open --port 8080
```

When you run `mitt open`, you'll see output like:

```
Your mitt: calm-river-73@bore
Public URL: https://calm-river-73.bore.pub
Waiting for files...
```

### Send files to a mitt

```bash
# Send a file
mitt send calm-river-73@bore ./document.pdf

# Send from stdin
cat data.txt | mitt send calm-river-73@bore -

# Send literal text
mitt send calm-river-73@bore --text "Hello, World!"

# With custom timeout
mitt send calm-river-73@bore ./file.txt --timeout 60
```

## Example Session

Terminal 1 (receiver):
```bash
$ mitt open --accept "*.txt,*.json" --max-size 10485760
Your mitt: green-moon-17@bore
Public URL: https://green-moon-17.bore.pub
Waiting for files...

Received: notes.txt (421 bytes) -> ./inbox/notes.txt
```

Terminal 2 (sender):
```bash
$ mitt send green-moon-17@bore ./notes.txt
Delivered.

$ mitt send green-moon-17@bore ./huge.zip
Rejected: {"error": "max size 10mb, got 243mb"}

$ mitt send green-moon-17@bore ./script.exe
Rejected: {"error": "file type not accepted: not in accept list"}
```

## Architecture

```
mitt/
├── src/
│   ├── main.zig              # Entry point, arg parsing, subcommand dispatch
│   ├── server.zig            # HTTP server for receiving data
│   ├── client.zig            # HTTP client for sending data
│   ├── tunnel.zig            # Tunnel provider abstraction + bore implementation
│   ├── id.zig                # Human-readable ID generation
│   ├── filter.zig            # Accept/reject logic (extension, size, MIME)
│   ├── storage.zig           # Write incoming files to disk
│   ├── config.zig            # Config file parsing, defaults
│   ├── test_integration.zig  # Integration tests
│   └── wordlist.txt          # Words for ID generation (embedded at compile time)
└── build.zig
```

## Testing

### Running Unit Tests

```bash
zig build test
```

This runs the unit tests for individual modules:
- `id.zig` - ID generation and parsing
- `filter.zig` - File filtering logic (extensions, size limits)
- `storage.zig` - File saving and collision handling

### Integration Testing

For integration testing with the full send/receive flow:

#### 1. Test local file transfer (without bore tunnel)

Terminal 1:
```bash
# Start server on a specific port (no tunnel needed for local testing)
zig-out/bin/mitt open --port 8080 --dir ./test-inbox
```

Terminal 2:
```bash
# Create a test file
echo "Hello, World!" > test.txt

# Send to localhost (modify client to support localhost for testing)
# Or use curl to test the server endpoint:
curl -X POST http://localhost:8080 \
  -H "x-filename: test.txt" \
  -H "x-size: 14" \
  -H "content-type: text/plain" \
  --data "Hello, World!"
```

Check that `./test-inbox/test.txt` contains the expected content.

#### 2. Test filtering

Terminal 1:
```bash
# Start with accept filter
zig-out/bin/mitt open --port 8080 --accept "*.txt" --dir ./test-inbox
```

Terminal 2:
```bash
# This should succeed
curl -X POST http://localhost:8080 \
  -H "x-filename: allowed.txt" \
  -H "x-size: 5" \
  --data "Hello"

# This should return 403
curl -X POST http://localhost:8080 \
  -H "x-filename: blocked.exe" \
  -H "x-size: 5" \
  --data "Hello"
```

#### 3. Test size limits

Terminal 1:
```bash
# Start with 100 byte limit
zig-out/bin/mitt open --port 8080 --max-size 100 --dir ./test-inbox
```

Terminal 2:
```bash
# This should succeed (under limit)
curl -X POST http://localhost:8080 \
  -H "x-filename: small.txt" \
  -H "x-size: 50" \
  --data-binary @<(head -c 50 /dev/zero)

# This should return 413
curl -X POST http://localhost:8080 \
  -H "x-filename: large.txt" \
  -H "x-size: 200" \
  --data-binary @<(head -c 200 /dev/zero)
```

#### 4. Test stdout mode

Terminal 1:
```bash
zig-out/bin/mitt open --port 8080 --stdout | tee output.txt
```

Terminal 2:
```bash
curl -X POST http://localhost:8080 \
  -H "x-filename: data.txt" \
  -H "x-size: 14" \
  --data "Hello, World!"
```

Verify that "Hello, World!" appears in terminal 1 and in `output.txt`.

#### 5. Test file collision handling

Terminal 1:
```bash
zig-out/bin/mitt open --port 8080 --dir ./test-inbox
```

Terminal 2:
```bash
# Send the same filename multiple times
curl -X POST http://localhost:8080 \
  -H "x-filename: duplicate.txt" \
  -H "x-size: 6" \
  --data "First"

curl -X POST http://localhost:8080 \
  -H "x-filename: duplicate.txt" \
  -H "x-size: 7" \
  --data "Second"

curl -X POST http://localhost:8080 \
  -H "x-filename: duplicate.txt" \
  -H "x-size: 6" \
  --data "Third"
```

Verify that `./test-inbox` contains:
- `duplicate.txt` (content: "First")
- `duplicate_1.txt` (content: "Second")
- `duplicate_2.txt` (content: "Third")

#### 6. End-to-end test with bore tunnel

This requires bore to be installed and running.

Terminal 1:
```bash
# Start mitt with bore tunnel
zig-out/bin/mitt open --dir ./test-inbox
# Note the mitt ID from the output, e.g., "green-moon-17@bore"
```

Terminal 2:
```bash
# Create test file
echo "Remote test" > remote.txt

# Send via mitt client
zig-out/bin/mitt send green-moon-17@bore remote.txt
```

Verify that `./test-inbox/remote.txt` exists with correct content.

### Cleanup

After testing, remove test artifacts:
```bash
rm -rf ./test-inbox ./output.txt test.txt remote.txt
```

## Exit Codes

- `0` - Success
- `1` - Rejected by receiver
- `2` - Timeout or unreachable

## License

See the main Caldron project license.
