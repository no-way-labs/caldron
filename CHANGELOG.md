# Changelog

All notable changes to mitt will be documented in this file.

## [0.4.0] - 2025-12-03

### Added
- `--bore-port` flag to request specific remote bore port
- Automatic fallback to random port when requested bore port is already in use
- Clear error messages for port conflicts with automatic retry
- Input validation for bore port parameter (0-65535)

## [0.3.0] - 2025-12-02

### Fixed
- Fixed `--text` flag argument parsing bug that incorrectly treated text as a file path
- Text payloads now work correctly without requiring a positional file argument

### Changed
- Improved argument parsing to support optional payload when using `--text` flag
- Updated README with JSON text example

## [0.2.0] - 2024-XX-XX

### Added
- Initial public release
- End-to-end encryption using XChaCha20-Poly1305
- Password-based authentication
- Bore tunnel support for public file transfers
- File filtering by extension and size
- Send files, stdin, or literal text
- Homebrew installation support
