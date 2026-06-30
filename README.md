# zget

A parallel file downloader written in Zig. Downloads files over HTTP/HTTPS using multiple concurrent connections with optional SHA256 integrity verification.

## Build

Requires Zig >= 0.16.0.

```sh
zig build
```

## Run

```sh
# Basic usage
zig build run -- <URL> [connections] [sha256_hash]

# Or run the binary directly
./zig-out/bin/zig_get <URL> [connections] [sha256_hash]
```

## Usage

```sh
# Download a file with default 20 connections
zig build run -- https://example.com/file.tar.gz

# Download with 4 parallel connections
zig build run -- https://example.com/file.tar.gz 4

# Download and verify SHA256 integrity
zig build run -- https://example.com/file.tar.gz 4 a7b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4
```

### Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| URL | yes | - | HTTP/HTTPS URL to download |
| connections | no | 20 | Number of parallel connections |
| sha256_hash | no | - | SHA256 hash for integrity verification |
