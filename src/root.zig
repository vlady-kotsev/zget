//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const config = @import("config");
const progress = @import("progress.zig");
pub const SHA256_HEX_LEN: u64 = 64;
const N_CONNECTION: u64 = 20;

pub const ZigGetError = error{
    UrlNotProvided,
    ContentLengthMissing,
    InvalidIntegrityHash,
    FileIntegrityMismatch,
};

pub const ZGet = struct {
    client: std.http.Client,
    allocator: std.mem.Allocator,
    io: std.Io,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Self {
        return Self{
            .client = .{
                .allocator = allocator,
                .io = io,
            },
            .io = io,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }

    fn get_file_length(self: *Self, uri: std.Uri) !u64 {
        var req = try self.client.request(.HEAD, uri, .{
            .headers = .{
                .accept_encoding = .{
                    .override = "identity",
                },
            },
        });
        defer req.deinit();
        try req.sendBodiless();

        var response_buf: [8 * 1024]u8 = undefined;
        const response = try req.receiveHead(&response_buf);

        var headers_it = response.head.iterateHeaders();
        if (config.DEBUG) {
            while (headers_it.next()) |head| {
                std.debug.print("{s}: {s}\n", .{ head.name, head.value });
            }
        }
        return response.head.content_length orelse ZigGetError.ContentLengthMissing;
    }

    fn download_chunk_async(self: *ZGet, channel: *std.Io.Queue(progress.ProgessMsg), file: std.Io.File, uri: std.Uri, start: u64, end: u64, chunk_size: u64) error{Canceled}!void {
        download_chunk(self, channel, file, uri, start, end, chunk_size) catch {
            return error.Canceled;
        };
    }

    fn download_chunk(self: *Self, channel: *std.Io.Queue(progress.ProgessMsg), file: std.Io.File, uri: std.Uri, start: u64, end: u64, chunk_size: u64) !void {
        var range_buffer: [128]u8 = undefined;
        const range = try std.fmt.bufPrint(&range_buffer, "bytes={}-{}", .{ start, end - 1 });

        const write_buffer = try self.allocator.alloc(u8, chunk_size);
        defer self.allocator.free(write_buffer);

        var writer = file.writer(self.io, write_buffer);
        defer writer.flush() catch {};

        try writer.seekTo(start); // position where this chunk should land

        const extra_headers = [1]std.http.Header{std.http.Header{
            .name = "Range",
            .value = range,
        }};

        _ = try self.client.fetch(.{
            .location = .{ .uri = uri },
            .headers = .{ .accept_encoding = .{ .override = "identity" } },
            .extra_headers = &extra_headers,
            .response_writer = &writer.interface,
        });
        try channel.putOne(self.io, progress.ProgessMsg.ChunkCompleted);
    }

    pub fn download_file(self: *Self, uri: std.Uri, file: std.Io.File) !u64 {
        var group: std.Io.Group = .init;
        defer group.cancel(self.io);

        const file_length = try self.get_file_length(uri);
        const n_connection: u64 = @min(file_length, N_CONNECTION);
        const chunk_size: u64 = file_length / n_connection;
        const remainder_size: u64 = file_length % n_connection;

        const queue_buffer = try self.allocator.alloc(progress.ProgessMsg, n_connection);
        defer self.allocator.free(queue_buffer);

        var channel = std.Io.Queue(progress.ProgessMsg).init(queue_buffer);
        var progress_future = self.io.async(progress.receive_progress, .{ self.io, &channel, n_connection });

        var start: u64 = 0;
        var end: u64 = chunk_size;

        for (0..n_connection) |_| {
            group.async(self.io, download_chunk_async, .{ self, &channel, file, uri, start, end, chunk_size });

            start = end;
            end += chunk_size;
        }
        try group.await(self.io);

        if (remainder_size != 0) {
            try self.download_chunk(&channel, file, uri, start, file_length, remainder_size);
        }
        try channel.putOne(self.io, progress.ProgessMsg.Done);

        _ = try progress_future.await(self.io);

        return file_length;
    }

    pub fn verify_integrity(self: *Self, file: std.Io.File, file_size: u64, integrity_hash: []const u8) !void {
        var hash_buffer: [32]u8 = undefined;
        const expected_hash: []u8 = std.fmt.hexToBytes(&hash_buffer, integrity_hash) catch {
            return ZigGetError.InvalidIntegrityHash;
        };

        const file_buffer = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(file_buffer);

        var read_buffer: [64 * 1024]u8 = undefined;
        var reader = file.reader(self.io, &read_buffer);

        try reader.interface.readSliceAll(file_buffer);

        var actual_hash_buffer: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(file_buffer, &actual_hash_buffer, .{});

        if (!std.mem.eql(u8, expected_hash, &actual_hash_buffer)) {
            return ZigGetError.FileIntegrityMismatch;
        }
    }
};
