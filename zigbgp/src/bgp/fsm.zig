const std = @import("std");
const open = @import("open.zig");
const notification = @import("notification.zig");

pub const MIN_HOLD_TIME: u16 = 3;

// ── BGP Finite State Machine (RFC 4271 §8) ────────────────────────────────────
//
// States:
//
//   Idle → Connect → Active → OpenSent → OpenConfirm → Established
//
// The FSM is pure: no I/O, no allocation. handle() takes an event, updates
// self.state, and returns an FsmAction describing what the caller must do
// (send a message, close the connection, (re)start timers).

pub const FSMState = enum { idle, connect, active, open_sent, open_confirm, established };

pub const FSMEvent = union(enum) {
    manual_start,
    manual_stop,
    tcp_connection_confirmed,
    tcp_connection_fails,
    hold_timer_expired,
    keepalive_timer_expired,
    open_received: open.Open,
    keepalive_received,
    update_received,
    notification_received: notification.Notification,
};

pub const FSMAction = struct {
    send_open: bool = false,
    send_keepalive: bool = false,
    send_notification: ?notification.Notification = null,
    close_connection: bool = false,
    /// Set when entering OpenConfirm. Caller must (re)start the hold timer.
    /// null means no change to the hold timer.
    negotiated_hold_time: ?u16 = null,
};

pub fn HoldTimerExpiredNotification() notification.Notification {
    return notification.Notification{
        .error_code = .hold_timer_expired,
        .error_subcode = 0,
        .data = &.{},
    };
}

pub fn CeaseAdminShutdownNotification() notification.Notification {
    return notification.Notification{
        .error_code = .cease,
        .error_subcode = @intFromEnum(notification.CeaseSubcode.admin_shutdown),
        .data = &.{},
    };
}

pub fn OpenMsgBadPeerNotification() notification.Notification {
    return notification.Notification{
        .error_code = .open_message,
        .error_subcode = @intFromEnum(notification.OpenSubcode.bad_peer_as),
        .data = &.{},
    };
}

pub fn OpenMsgUnacceptableHoldTimerNotification() notification.Notification {
    return notification.Notification{
        .error_code = .open_message,
        .error_subcode = @intFromEnum(notification.OpenSubcode.unacceptable_hold_time),
        .data = &.{},
    };
}

pub const FSM = struct {
    state: FSMState = .idle,
    local_as: u32,
    router_id: [4]u8,
    hold_time: u16, // advertised in our open msg
    negotiated_hold_time: ?u16 = null, // hold time after negotiateion
    remote_as: ?u32, // null = accept any

    /// Process one event. Mutates self.state. Never fails - invalid events are silently ignored.
    pub fn handle(self: *FSM, event: FSMEvent) FSMAction {
        switch (self.state) {
            .idle => return self.handleIdleEvents(event),
            .connect => return self.handleConnectEvents(event),
            .active => return self.handleActiveEvents(event),
            .open_sent => return self.handleOpenSentEvents(event),
            .open_confirm => return self.handleOpenConfirmEvents(event),
            .established => return self.handleEstablishedEvents(event),
        }
    }

    pub fn handleIdleEvents(self: *FSM, event: FSMEvent) FSMAction {
        switch (event) {
            .manual_start => return self.setStateAndReturnAction(.connect, .{}),
            else => return .{}, // ignore everything else
        }
    }

    pub fn handleConnectEvents(self: *FSM, event: FSMEvent) FSMAction {
        switch (event) {
            .tcp_connection_confirmed => return self.setStateAndReturnAction(.open_sent, .{ .send_open = true }),
            .tcp_connection_fails => return self.setStateAndReturnAction(.active, .{}),
            .manual_stop => return self.setStateAndReturnAction(.idle, .{}),
            else => return .{},
        }
    }

    pub fn handleActiveEvents(self: *FSM, event: FSMEvent) FSMAction {
        switch (event) {
            .tcp_connection_confirmed => return self.setStateAndReturnAction(.open_sent, .{ .send_open = true }),
            .manual_stop => return self.setStateAndReturnAction(.idle, .{}),
            else => return .{},
        }
    }

    pub fn handleOpenSentEvents(self: *FSM, event: FSMEvent) FSMAction {
        switch (event) {
            .open_received => |o| {
                // validate their AS
                if (self.remote_as) |expected| {
                    if (o.asNumber() != expected) return self.setStateAndReturnAction(.idle, .{
                        .close_connection = true,
                        .send_notification = OpenMsgBadPeerNotification(),
                    });
                }
                const negotiated: u16 = @min(self.hold_time, o.hold_time);
                if (negotiated != 0 and negotiated < MIN_HOLD_TIME)
                    return self.setStateAndReturnAction(.idle, .{
                        .close_connection = true,
                        .send_notification = OpenMsgUnacceptableHoldTimerNotification(),
                    });
                // use negotiated hold timer
                self.negotiated_hold_time = negotiated;
                return self.setStateAndReturnAction(.open_confirm, .{ .send_keepalive = true, .negotiated_hold_time = negotiated });
            },
            .hold_timer_expired => return self.setStateAndReturnAction(.idle, .{
                .close_connection = true,
                .send_notification = HoldTimerExpiredNotification(),
            }),
            .tcp_connection_fails => return self.setStateAndReturnAction(.active, .{}),
            .manual_stop => return self.setStateAndReturnAction(.idle, .{
                .close_connection = true,
                .send_notification = CeaseAdminShutdownNotification(),
            }),
            else => return .{},
        }
    }

    pub fn handleOpenConfirmEvents(self: *FSM, event: FSMEvent) FSMAction {
        switch (event) {
            .keepalive_received => return self.setStateAndReturnAction(.established, .{}),
            .hold_timer_expired => return self.setStateAndReturnAction(.idle, .{
                .close_connection = true,
                .send_notification = HoldTimerExpiredNotification(),
            }),
            .notification_received => return self.setStateAndReturnAction(.idle, .{}),
            .manual_stop => return self.setStateAndReturnAction(.idle, .{
                .close_connection = true,
                .send_notification = CeaseAdminShutdownNotification(),
            }),
            else => return .{},
        }
    }

    pub fn handleEstablishedEvents(self: *FSM, event: FSMEvent) FSMAction {
        switch (event) {
            .keepalive_received, .update_received => {
                const hold_time = self.negotiated_hold_time orelse self.hold_time;
                return self.setStateAndReturnAction(.established, .{ .negotiated_hold_time = hold_time });
            },
            .hold_timer_expired => return self.setStateAndReturnAction(.idle, .{
                .close_connection = true,
                .send_notification = HoldTimerExpiredNotification(),
            }),
            .notification_received => return self.setStateAndReturnAction(.idle, .{}),
            .manual_stop => return self.setStateAndReturnAction(.idle, .{
                .close_connection = true,
                .send_notification = CeaseAdminShutdownNotification(),
            }),
            else => return .{},
        }
    }

    fn setStateAndReturnAction(self: *FSM, next: FSMState, ret: FSMAction) FSMAction {
        self.state = next;
        return ret;
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

fn testFsm() FSM {
    return FSM{
        .local_as = 65001,
        .router_id = .{ 10, 0, 0, 1 },
        .hold_time = 90,
        .remote_as = 65002,
    };
}

fn peerOpen() open.Open {
    return open.Open{
        .version = 4,
        .my_as = 65002,
        .hold_time = 90,
        .bgp_id = .{ 10, 0, 0, 2 },
        .four_octet_as = null,
    };
}

// ── Idle ──────────────────────────────────────────────────────────────────────

test "Idle: manual_start → Connect" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    try std.testing.expectEqual(FSMState.connect, fsm.state);
}

test "Idle: any other event is ignored" {
    var fsm = testFsm();
    _ = fsm.handle(.tcp_connection_confirmed);
    try std.testing.expectEqual(FSMState.idle, fsm.state);
    _ = fsm.handle(.hold_timer_expired);
    try std.testing.expectEqual(FSMState.idle, fsm.state);
}

// ── Connect ───────────────────────────────────────────────────────────────────

test "Connect: tcp_connection_confirmed → OpenSent, sends OPEN" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    const action = fsm.handle(.tcp_connection_confirmed);
    try std.testing.expectEqual(FSMState.open_sent, fsm.state);
    try std.testing.expect(action.send_open);
}

test "Connect: tcp_connection_fails → Active" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_fails);
    try std.testing.expectEqual(FSMState.active, fsm.state);
}

test "Connect: manual_stop → Idle" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.manual_stop);
    try std.testing.expectEqual(FSMState.idle, fsm.state);
}

// ── Active ────────────────────────────────────────────────────────────────────

test "Active: tcp_connection_confirmed → OpenSent, sends OPEN" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_fails); // → Active
    const action = fsm.handle(.tcp_connection_confirmed);
    try std.testing.expectEqual(FSMState.open_sent, fsm.state);
    try std.testing.expect(action.send_open);
}

test "Active: manual_stop → Idle" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_fails);
    _ = fsm.handle(.manual_stop);
    try std.testing.expectEqual(FSMState.idle, fsm.state);
}

// ── OpenSent ──────────────────────────────────────────────────────────────────

test "OpenSent: valid open_received → OpenConfirm, sends KEEPALIVE" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    const action = fsm.handle(.{ .open_received = peerOpen() });
    try std.testing.expectEqual(FSMState.open_confirm, fsm.state);
    try std.testing.expect(action.send_keepalive);
    try std.testing.expectEqual(@as(?notification.Notification, null), action.send_notification);
}

test "OpenSent: hold_time negotiated as min(local, peer)" {
    var fsm = testFsm();
    fsm.hold_time = 90;
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    var peer = peerOpen();
    peer.hold_time = 60; // peer advertises lower hold time
    const action = fsm.handle(.{ .open_received = peer });
    try std.testing.expectEqual(FSMState.open_confirm, fsm.state);
    // negotiated hold time must be min(90, 60) = 60
    try std.testing.expectEqual(@as(?u16, 60), action.negotiated_hold_time);
}

test "OpenSent: bad peer AS → Idle, sends NOTIFICATION(open_message/bad_peer_as)" {
    var fsm = testFsm();
    fsm.remote_as = 65002;
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    var bad_open = peerOpen();
    bad_open.my_as = 65099; // wrong AS
    const action = fsm.handle(.{ .open_received = bad_open });
    try std.testing.expectEqual(FSMState.idle, fsm.state);
    try std.testing.expect(action.close_connection);
    const n = action.send_notification.?;
    try std.testing.expectEqual(notification.ErrorCode.open_message, n.error_code);
    try std.testing.expectEqual(@intFromEnum(notification.OpenSubcode.bad_peer_as), n.error_subcode);
}

test "OpenSent: unacceptable hold_time (1) → Idle, sends NOTIFICATION" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    var bad_open = peerOpen();
    bad_open.hold_time = 1; // < 3 and != 0 is unacceptable per RFC 4271
    const action = fsm.handle(.{ .open_received = bad_open });
    try std.testing.expectEqual(FSMState.idle, fsm.state);
    const n = action.send_notification.?;
    try std.testing.expectEqual(notification.ErrorCode.open_message, n.error_code);
    try std.testing.expectEqual(@intFromEnum(notification.OpenSubcode.unacceptable_hold_time), n.error_subcode);
}

test "OpenSent: hold_time 0 is valid (disables timers)" {
    var fsm = testFsm();
    fsm.hold_time = 0;
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    var peer = peerOpen();
    peer.hold_time = 0;
    const action = fsm.handle(.{ .open_received = peer });
    try std.testing.expectEqual(FSMState.open_confirm, fsm.state);
    try std.testing.expectEqual(@as(?u16, 0), action.negotiated_hold_time);
}

test "OpenSent: hold_timer_expired → Idle, sends NOTIFICATION" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    const action = fsm.handle(.hold_timer_expired);
    try std.testing.expectEqual(FSMState.idle, fsm.state);
    try std.testing.expect(action.close_connection);
    const n = action.send_notification.?;
    try std.testing.expectEqual(notification.ErrorCode.hold_timer_expired, n.error_code);
}

test "OpenSent: tcp_connection_fails → Active" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    _ = fsm.handle(.tcp_connection_fails);
    try std.testing.expectEqual(FSMState.active, fsm.state);
}

test "OpenSent: manual_stop → Idle, sends NOTIFICATION(cease/admin_shutdown)" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    const action = fsm.handle(.manual_stop);
    try std.testing.expectEqual(FSMState.idle, fsm.state);
    try std.testing.expect(action.close_connection);
    const n = action.send_notification.?;
    try std.testing.expectEqual(notification.ErrorCode.cease, n.error_code);
    try std.testing.expectEqual(@intFromEnum(notification.CeaseSubcode.admin_shutdown), n.error_subcode);
}

// ── OpenConfirm ───────────────────────────────────────────────────────────────

test "OpenConfirm: keepalive_received → Established" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    _ = fsm.handle(.{ .open_received = peerOpen() });
    _ = fsm.handle(.keepalive_received);
    try std.testing.expectEqual(FSMState.established, fsm.state);
}

test "OpenConfirm: hold_timer_expired → Idle, sends NOTIFICATION" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    _ = fsm.handle(.{ .open_received = peerOpen() });
    const action = fsm.handle(.hold_timer_expired);
    try std.testing.expectEqual(FSMState.idle, fsm.state);
    try std.testing.expect(action.close_connection);
    const n = action.send_notification.?;
    try std.testing.expectEqual(notification.ErrorCode.hold_timer_expired, n.error_code);
}

test "OpenConfirm: notification_received → Idle" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    _ = fsm.handle(.{ .open_received = peerOpen() });
    const n = notification.Notification{ .error_code = .cease, .error_subcode = 0, .data = &.{} };
    _ = fsm.handle(.{ .notification_received = n });
    try std.testing.expectEqual(FSMState.idle, fsm.state);
}

test "OpenConfirm: manual_stop → Idle, sends NOTIFICATION(cease/admin_shutdown)" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    _ = fsm.handle(.{ .open_received = peerOpen() });
    const action = fsm.handle(.manual_stop);
    try std.testing.expectEqual(FSMState.idle, fsm.state);
    const n = action.send_notification.?;
    try std.testing.expectEqual(notification.ErrorCode.cease, n.error_code);
}

// ── Established ───────────────────────────────────────────────────────────────

test "Established: keepalive_received → Established, resets hold timer" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    _ = fsm.handle(.{ .open_received = peerOpen() });
    _ = fsm.handle(.keepalive_received); // → Established
    const action = fsm.handle(.keepalive_received);
    try std.testing.expectEqual(FSMState.established, fsm.state);
    // hold timer must be reset — signal by returning negotiated_hold_time
    try std.testing.expect(action.negotiated_hold_time != null);
}

test "Established: update_received → Established, resets hold timer" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    _ = fsm.handle(.{ .open_received = peerOpen() });
    _ = fsm.handle(.keepalive_received);
    const action = fsm.handle(.update_received);
    try std.testing.expectEqual(FSMState.established, fsm.state);
    try std.testing.expect(action.negotiated_hold_time != null);
}

test "Established: hold_timer_expired → Idle, sends NOTIFICATION" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    _ = fsm.handle(.{ .open_received = peerOpen() });
    _ = fsm.handle(.keepalive_received);
    const action = fsm.handle(.hold_timer_expired);
    try std.testing.expectEqual(FSMState.idle, fsm.state);
    try std.testing.expect(action.close_connection);
    const n = action.send_notification.?;
    try std.testing.expectEqual(notification.ErrorCode.hold_timer_expired, n.error_code);
}

test "Established: notification_received → Idle" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    _ = fsm.handle(.{ .open_received = peerOpen() });
    _ = fsm.handle(.keepalive_received);
    const n = notification.Notification{ .error_code = .cease, .error_subcode = 0, .data = &.{} };
    _ = fsm.handle(.{ .notification_received = n });
    try std.testing.expectEqual(FSMState.idle, fsm.state);
}

test "Established: manual_stop → Idle, sends NOTIFICATION(cease/admin_shutdown)" {
    var fsm = testFsm();
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    _ = fsm.handle(.{ .open_received = peerOpen() });
    _ = fsm.handle(.keepalive_received);
    const action = fsm.handle(.manual_stop);
    try std.testing.expectEqual(FSMState.idle, fsm.state);
    try std.testing.expect(action.close_connection);
    const n = action.send_notification.?;
    try std.testing.expectEqual(notification.ErrorCode.cease, n.error_code);
    try std.testing.expectEqual(@intFromEnum(notification.CeaseSubcode.admin_shutdown), n.error_subcode);
}

// ── remote_as = null (accept any peer AS) ─────────────────────────────────────

test "OpenSent: remote_as null accepts any peer AS" {
    var fsm = testFsm();
    fsm.remote_as = null; // accept any
    _ = fsm.handle(.manual_start);
    _ = fsm.handle(.tcp_connection_confirmed);
    var peer = peerOpen();
    peer.my_as = 64999; // any AS
    _ = fsm.handle(.{ .open_received = peer });
    try std.testing.expectEqual(FSMState.open_confirm, fsm.state);
}
