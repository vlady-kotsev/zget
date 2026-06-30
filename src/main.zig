const std = @import("std");
const Io = std.Io;

const zig_get = @import("zig_get");
const ZGet = zig_get.ZGet;
const ZigGetError = zig_get.ZigGetError;

pub fn main(init: std.process.Init) !void {
    var threaded_io: Io.Threaded = .init(init.gpa, .{
        .async_limit = .limited(30),
        .concurrent_limit = .limited(30),
    });

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        return ZigGetError.UrlNotProvided;
    }

    const uri = try std.Uri.parse(args[1]);
    var zget = ZGet.init(init.gpa, threaded_io.io());
    defer zget.deinit();

    const file_name = std.Io.Dir.path.basenamePosix(uri.path.percent_encoded);

    const out_file = try std.Io.Dir.cwd().createFile(threaded_io.io(), file_name, .{ .read = true });
    defer out_file.close(threaded_io.io());

    const file_length = try zget.download_file(uri, out_file);
    if (args.len >= 3) {
        const integrity_hash = args[2];
        if (integrity_hash.len != zig_get.SHA256_HEX_LEN) {
            return ZigGetError.InvalidIntegrityHash;
        }

        try zget.verify_integrity(out_file, file_length, integrity_hash);
        try std.Io.File.stdout().writeStreamingAll(threaded_io.io(), "Data integrity checked!\n");
    }
    //std.debug.print("Status: {s}\n", .{file_status.phrase() orelse "Chedaaa moi"});
}
