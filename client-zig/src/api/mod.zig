//! Kubernetes API client module.
pub const typed = @import("typed.zig");
pub const watch = @import("watch.zig");
pub const lw = @import("lister_watcher.zig");

// TypedClient export
pub const TypedClient = typed.TypedClient;
pub const ListOptions = typed.ListOptions;
pub const ResourceInfo = typed.ResourceInfo;

// Watcher export
pub const WatchStream = watch.WatchStream;
pub const Watcher = watch.Watcher;
pub const WatchOptions = watch.WatchOptions;
pub const WatchEvent = watch.WatchEvent;
pub const EventType = watch.EventType;

// lister_watcher export
pub const ListerWatcher = lw.ListerWatcher;
pub const EventQueue = lw.EventQueue;
