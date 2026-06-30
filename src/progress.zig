const std = @import("std");

pub const ProgessMsg = enum { ChunkCompleted, Done };

pub fn receive_progress(io: std.Io, chan: *std.Io.Queue(ProgessMsg), total: u64) !void {
    var count: u64 = 1;
    while (true) {
        const msg = try chan.getOne(io);
        if (msg == .Done) {
            try std.Io.File.stdout().writeStreamingAll(io, "\x1b[2J\x1b[H");
            try std.Io.File.stdout().writeStreamingAll(io, "Done\n");
            return;
        }

        try std.Io.File.stdout().writeStreamingAll(io, "\x1b[2J\x1b[H");

        var buf: [128]u8 = undefined;
        const progress_string = try std.fmt.bufPrint(&buf, "{}%", .{(100 * count) / total});
        try std.Io.File.stdout().writeStreamingAll(io, progress_string);
        count += 1;
    }
}
