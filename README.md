# Caldron

A monorepo for various CLI applications written in Zig.

## Structure

```
caldron/
├── apps/
│   └── mitt/            # Encrypted file transfer CLI
│       ├── src/
│       │   ├── main.zig
│       │   ├── server.zig
│       │   ├── client.zig
│       │   ├── crypto.zig
│       │   └── ...
│       ├── build.zig
│       └── README.md
└── build.zig            # Root build file
```

## Installation

Install all CLI apps to `~/.local/bin` with the `caldron-` prefix:

```bash
./install.sh
```

To install to a custom location:
```bash
INSTALL_DIR=/usr/local/bin ./install.sh
```

Make sure `~/.local/bin` is in your PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

After installation, you can run apps from anywhere:
```bash
mitt open
```

## Building

Build all apps from the root:
```bash
zig build
```

Build a specific app:
```bash
cd apps/mitt
zig build
```

## Running (without installing)

Run from the root:
```bash
# Run default app (mitt)
zig build run -- open

# Run specific app
zig build mitt -- open
```

Run from app directory:
```bash
cd apps/mitt
zig build run -- open
```

## Apps

### mitt
An encrypted file transfer CLI tool. One party opens a "mitt" (a publicly reachable inbox), others send to it.

**Features:**
- End-to-end encryption using XChaCha20-Poly1305
- Password-based authentication
- Tunneling via bore (optional)
- File filtering by extension and size
- Raw TCP for fast transfers

```bash
# Receiver
mitt open

# Sender
mitt send bore.pub:54321 file.txt --password fuzzy-planet-cat
```

See [apps/mitt/README.md](apps/mitt/README.md) for full documentation.

## Adding New Apps

To add a new CLI app:

1. Create a new directory under `apps/`:
   ```bash
   mkdir -p apps/my-new-app/src
   ```

2. Add your Zig source files in `apps/my-new-app/src/main.zig`

3. Create `apps/my-new-app/build.zig` (copy from mitt as template)

4. Update the root `build.zig` to include your new app

## License

MIT