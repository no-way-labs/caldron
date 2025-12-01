# Caldron

A monorepo for various CLI applications written in Zig.

## Structure

```
caldron/
├── apps/
│   └── hello-world/     # Simple hello world CLI
│       ├── src/
│       │   └── main.zig
│       └── build.zig
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
caldron-hello-world -- Alice
```

## Building

Build all apps from the root:
```bash
zig build
```

Build a specific app:
```bash
cd apps/hello-world
zig build
```

## Running (without installing)

Run from the root:
```bash
# Run default app (hello-world)
zig build run -- YourName

# Run specific app
zig build hello-world -- YourName
```

Run from app directory:
```bash
cd apps/hello-world
zig build run -- YourName
```

## Apps

### hello-world
A simple CLI app that greets you by name.

```bash
zig build hello-world -- Alice
# Output: Hello, Alice!
```

## Adding New Apps

To add a new CLI app:

1. Create a new directory under `apps/`:
   ```bash
   mkdir -p apps/my-new-app/src
   ```

2. Add your Zig source files in `apps/my-new-app/src/main.zig`

3. Create `apps/my-new-app/build.zig` (copy from hello-world as template)

4. Update the root `build.zig` to include your new app