//! A CVDisplayLink that is only ever started, stopped, or re-targeted
//! from the main thread.
//!
//! ## Why start and stop must happen on the main thread
//!
//! CoreVideo's `CVDisplayLinkStop` clears the link's running flag and
//! then waits, once and unconditionally, for the link's IO thread to
//! notice and exit. While it waits, the link's mutex is released. If any
//! thread calls `CVDisplayLinkStart` during that wait, the flag is set
//! again and a second IO thread is created. The first IO thread wakes up,
//! sees the flag set, and keeps running. Nothing ever signals the waiting
//! `CVDisplayLinkStop`, so it blocks forever.
//!
//! CoreVideo itself performs exactly this stop and start sequence, on the
//! main thread, inside its display reconfiguration callback. That fires
//! whenever the display the link is bound to changes mode, which happens
//! on display sleep and wake, resolution changes, and hotplug.
//! `CVDisplayLinkSetCurrentCGDisplay` performs the same sequence. None of
//! these calls take a lock that protects against each other.
//!
//! So a start or stop issued from the render thread can collide with
//! CoreVideo's own, and whichever side loses is stuck in
//! `CVDisplayLinkStop` forever. In Ghostty that first wedged the render
//! thread, then the main thread as soon as it waited on the renderer, and
//! the whole app froze. See
//! https://github.com/ghostty-org/ghostty/discussions/14150.
//!
//! The fix is to issue every state change from the main thread, where it
//! is serialized with CoreVideo's own reconfiguration handling simply by
//! running on the same thread.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const macos = @import("macos");
const log = std.log.scoped(.display_link);

pub const DisplayLink = Managed(CoreVideo);

const CoreVideo = struct {
    const Link = macos.video.DisplayLink;
    extern "c" fn pthread_main_np() c_int;

    fn create() !*Link {
        return Link.createWithActiveCGDisplays();
    }

    fn enqueue(context: *anyopaque, callback: *const fn (?*anyopaque) callconv(.c) void) void {
        macos.dispatch.c.dispatch_async_f(macos.dispatch.c.dispatch_get_main_queue(), context, callback);
    }

    fn assertMainThread() void {
        assert(pthread_main_np() != 0);
    }
};

/// The backend boundary permits deterministic lifetime and scheduling tests.
fn Managed(comptime Backend: type) type {
    return struct {
        const Self = @This();
        alloc: Allocator,

        /// The underlying CVDisplayLink. Its state is only changed on the
        /// main thread.
        link: *Backend.Link,

        /// Set by `close`. A sync that was already queued when `close` ran
        /// sees this, skips its work, and frees the struct. Main thread only.
        closed: bool = false,

        /// The display the link was last bound to with `setDisplay`, or zero
        /// if `setDisplay` was never called. Main thread only.
        display: u32 = 0,

        /// The state the owner has asked for. Written by `setRunning` and
        /// `setDisplay` on the owner's thread and read by the sync on the
        /// main thread. Packing both fields into one atomic means the sync
        /// always sees them together as they were last requested.
        requested: std.atomic.Value(Requested) = .init(.{}),

        /// True while a sync is queued on the main thread and has not yet
        /// started. Used to collapse many requests into one sync, and by
        /// `close` to know whether a queued sync still needs this struct.
        sync_queued: std.atomic.Value(bool) = .init(false),

        /// The state the owner wants the link in. This is a single 64-bit
        /// value so that it can be read and written atomically as a whole.
        const Requested = packed struct(u64) {
            /// Whether the link should be running.
            running: bool = false,

            _padding: u31 = 0,

            /// The CGDirectDisplayID the link should be bound to, or zero if
            /// no display has been requested.
            display: u32 = 0,
        };

        /// Create a display link bound to the active displays, with the given
        /// output callback. The link starts out stopped. Call `setRunning` to
        /// start it.
        ///
        /// `callbackFn` is invoked by CoreVideo on its own thread once per
        /// display refresh while the link is running, with `userdata` as its
        /// argument. `userdata` must stay valid until `close` returns.
        ///
        /// This can be called from any thread. Creating a link and setting its
        /// callback do not change its running state, so they do not collide
        /// with CoreVideo's reconfiguration handling.
        ///
        /// Fails if no display is available, which can happen briefly while
        /// the session is locked or a display is asleep. Callers can continue
        /// without vsync and try again later.
        pub fn create(
            alloc: Allocator,
            comptime Userdata: type,
            comptime callbackFn: *const fn (*Backend.Link, ?*Userdata) void,
            userdata: ?*Userdata,
        ) !*Self {
            const link = try Backend.create();
            errdefer link.release();
            try link.setOutputCallback(Userdata, callbackFn, userdata);

            const self = try alloc.create(Self);
            errdefer alloc.destroy(self);
            self.* = .{
                .alloc = alloc,
                .link = link,
            };

            return self;
        }

        /// Stop and release the display link. The pointer is invalid after
        /// this call.
        ///
        /// Must be called on the main thread. Stopping waits for CoreVideo's
        /// IO thread to exit, and that is only safe on the main thread, where
        /// CoreVideo's own stop and start also run and so cannot restart the
        /// link while we wait. Our apprts always destroy surfaces on the main
        /// thread.
        ///
        /// The link is stopped before this returns, so the output callback is
        /// not invoked again and whatever `userdata` pointed at can be freed.
        ///
        /// No other method may be called on this link after or concurrently
        /// with `close`. In practice the render thread that makes those calls
        /// has already exited by the time the renderer is deinitialized.
        pub fn close(self: *Self) void {
            Backend.assertMainThread();
            assert(!self.closed);
            self.closed = true;

            if (self.link.isRunning()) self.link.stop() catch |err| {
                log.warn("error stopping display link err={}", .{err});
            };
            self.link.release();

            // If a sync is queued on the main thread it runs after we return
            // and still needs this struct, so it frees it instead of us.
            if (!self.sync_queued.load(.seq_cst)) self.destroy();
        }

        fn destroy(self: *Self) void {
            const alloc = self.alloc;
            self.* = undefined;
            alloc.destroy(self);
        }

        /// Returns true if the link is running right now, meaning CoreVideo is
        /// invoking the output callback on every display refresh.
        ///
        /// This reports the link's actual state, not the state most recently
        /// requested with `setRunning`. The two differ briefly after a request,
        /// and also when a start failed or CoreVideo stopped the link itself
        /// during a display reconfiguration. Can be called from any thread.
        pub fn isRunning(self: *Self) bool {
            return self.link.isRunning();
        }

        /// Request that the link run, or stop running. Never blocks.
        ///
        /// The change is applied shortly after on the main thread. Until then
        /// `isRunning` keeps reporting the old state. Calling this repeatedly
        /// with the same value is cheap, and calling it with alternating values
        /// in quick succession results in at most one real change.
        ///
        /// This and `setDisplay` must be called from a single thread, which
        /// for the renderer is the render thread. That thread is the only
        /// writer of the requested state, so no compare-and-swap is needed.
        pub fn setRunning(self: *Self, running: bool) void {
            var requested = self.requested.load(.seq_cst);
            const changed = requested.running != running;
            requested.running = running;
            self.requested.store(requested, .seq_cst);
            if (changed or running != self.link.isRunning()) self.queueSync();
        }

        /// Request that the link be bound to the given CGDirectDisplayID, so
        /// that it follows that display's refresh rate. Never blocks.
        ///
        /// Call this when the window moves to a different screen. A display ID
        /// of zero means no display and is ignored. See `setRunning` for the
        /// threading requirement.
        pub fn setDisplay(self: *Self, display_id: u32) void {
            if (display_id == 0) return;
            var requested = self.requested.load(.seq_cst);
            if (requested.display == display_id) return;
            requested.display = display_id;
            self.requested.store(requested, .seq_cst);
            self.queueSync();
        }

        /// Queue a sync onto the main thread, unless one is already queued and
        /// has not started yet.
        ///
        /// A sync that has already started clears `sync_queued` before it reads
        /// the requested state, so a request that arrives too late for it will
        /// queue another sync rather than be lost.
        fn queueSync(self: *Self) void {
            if (self.sync_queued.swap(true, .seq_cst)) return;
            Backend.enqueue(self, &syncCallback);
        }

        fn syncCallback(ud: ?*anyopaque) callconv(.c) void {
            const self: *Self = @ptrCast(@alignCast(ud.?));

            // Clear this before reading the requested state. See queueSync.
            self.sync_queued.store(false, .seq_cst);

            // If the owner closed the link while we were queued, it left the
            // struct for us to free. See close.
            if (self.closed) {
                self.destroy();
                return;
            }

            self.sync();
        }

        /// Make the link's actual state match the requested state. Main thread
        /// only. Every CoreVideo call that changes the link's state is made
        /// from here or from `close`.
        fn sync(self: *Self) void {
            Backend.assertMainThread();
            const requested = self.requested.load(.seq_cst);

            if (requested.display != 0 and requested.display != self.display) {
                // Record the display even if binding fails so that we don't
                // retry on every sync. The next display change tries again.
                self.display = requested.display;
                log.info("updating display link display id={}", .{requested.display});

                // If the link is running, CoreVideo stops and restarts it
                // internally. That is safe here for the same reason our own
                // stop below is.
                self.link.setCurrentCGDisplay(requested.display) catch |err| {
                    log.warn("error setting display link display id err={}", .{err});
                };
            }

            const running = self.link.isRunning();
            if (requested.running and !running) {
                // If this fails the link stays stopped. The renderer notices
                // through isRunning and draws without vsync, and the next
                // request retries. This is logged at debug level because a
                // display can be unavailable for a while, such as during a
                // locked session, and we would otherwise log once per frame.
                self.link.start() catch |err| {
                    log.debug("error starting display link err={}", .{err});
                };
            } else if (!requested.running and running) {
                self.link.stop() catch |err| {
                    log.warn("error stopping display link err={}", .{err});
                };
            }
        }
    };
}

// Models CoreVideo and a main queue that the render thread cannot drain.
// No CoreVideo state mutation is permitted until the queue is explicitly run.
const Mock = struct {
    var link: Link = .{};
    var queued: ?struct { context: *anyopaque, callback: *const fn (?*anyopaque) callconv(.c) void } = null;
    var on_main: bool = false;
    var during_start: ?*const fn () void = null;

    const Link = struct {
        running: bool = false,
        starts: usize = 0,
        stops: usize = 0,
        displays: usize = 0,
        releases: usize = 0,
        fail_start: bool = false,
        fail_display: bool = false,

        fn setOutputCallback(_: *Link, comptime U: type, comptime _: *const fn (*Link, ?*U) void, _: ?*U) !void {}
        fn isRunning(self: *Link) bool {
            assert(self.releases == 0);
            return self.running;
        }
        fn start(self: *Link) !void {
            assertMainThread();
            self.starts += 1;
            if (during_start) |f| {
                during_start = null;
                // A render request arrives after sync loaded its snapshot,
                // but before CoreVideo has set the actual running flag.
                on_main = false;
                f();
                on_main = true;
            }
            if (self.fail_start) return error.NoDisplay;
            self.running = true;
        }
        fn stop(self: *Link) !void {
            assertMainThread();
            self.stops += 1;
            self.running = false;
        }
        fn setCurrentCGDisplay(self: *Link, _: u32) !void {
            assertMainThread();
            self.displays += 1;
            if (self.fail_display) return error.NoDisplay;
        }
        fn release(self: *Link) void {
            assertMainThread();
            self.releases += 1;
        }
    };
    fn create() !*Link {
        return &link;
    }
    fn enqueue(context: *anyopaque, callback: *const fn (?*anyopaque) callconv(.c) void) void {
        assert(queued == null);
        queued = .{ .context = context, .callback = callback };
    }
    fn assertMainThread() void {
        assert(on_main);
    }
    fn reset() void {
        link = .{};
        queued = null;
        on_main = false;
        during_start = null;
    }
    fn drainOne() void {
        const item = queued orelse return;
        queued = null;
        on_main = true;
        defer on_main = false;
        item.callback(item.context);
    }
    fn outputCallback(_: *Link, _: ?*void) void {}
};

test "DisplayLink coalesces state on main without blocking render" {
    const testing = std.testing;
    Mock.reset();
    const link = try Managed(Mock).create(testing.allocator, void, Mock.outputCallback, null);
    link.setDisplay(42);
    for (0..1000) |i| link.setRunning(i % 2 == 0);
    link.setRunning(true);
    try testing.expect(!link.isRunning());
    try testing.expectEqual(0, Mock.link.starts);
    try testing.expectEqual(0, Mock.link.displays);
    Mock.drainOne();
    try testing.expect(link.isRunning());
    try testing.expectEqual(1, Mock.link.starts);
    try testing.expectEqual(1, Mock.link.displays);
    link.setDisplay(42);
    link.setDisplay(0);
    link.setRunning(true);
    try testing.expect(Mock.queued == null);
    link.setRunning(false);
    Mock.drainOne();
    try testing.expect(!link.isRunning());
    Mock.on_main = true;
    link.close();
    try testing.expectEqual(1, Mock.link.releases);
}

test "DisplayLink close stops before callback target is freed and drains queued sync" {
    const testing = std.testing;
    Mock.reset();
    const link = try Managed(Mock).create(testing.allocator, void, Mock.outputCallback, null);
    link.setRunning(true);
    Mock.drainOne();
    link.setDisplay(99);
    // Main can join the already-finished render thread without draining its
    // queued work, then synchronously stop before destroying the callback.
    Mock.on_main = true;
    link.close();
    try testing.expect(!Mock.link.running);
    try testing.expectEqual(1, Mock.link.stops);
    try testing.expectEqual(1, Mock.link.releases);
    Mock.drainOne();
    try testing.expectEqual(0, Mock.link.displays);
    try testing.expect(Mock.queued == null);
}

test "DisplayLink retries failed starts and external stops" {
    const testing = std.testing;
    Mock.reset();
    const link = try Managed(Mock).create(testing.allocator, void, Mock.outputCallback, null);
    Mock.link.fail_start = true;
    link.setRunning(true);
    Mock.drainOne();
    try testing.expect(!link.isRunning());
    Mock.link.fail_start = false;
    link.setRunning(true);
    Mock.drainOne();
    try testing.expect(link.isRunning());
    Mock.link.running = false; // CoreVideo reconfiguration stopped it.
    link.setRunning(true);
    Mock.drainOne();
    try testing.expect(link.isRunning());
    try testing.expectEqual(3, Mock.link.starts);
    Mock.on_main = true;
    link.close();
}

test "DisplayLink does not lose a stop requested while start is applying" {
    const testing = std.testing;
    const Driver = struct {
        var link: *Managed(Mock) = undefined;
        fn stop() void {
            link.setRunning(false);
        }
    };
    Mock.reset();
    const link = try Managed(Mock).create(testing.allocator, void, Mock.outputCallback, null);
    Driver.link = link;
    Mock.during_start = Driver.stop;
    link.setRunning(true);
    Mock.drainOne();
    try testing.expect(link.isRunning());
    try testing.expect(Mock.queued != null);
    Mock.drainOne();
    try testing.expect(!link.isRunning());
    Mock.on_main = true;
    link.close();
}
