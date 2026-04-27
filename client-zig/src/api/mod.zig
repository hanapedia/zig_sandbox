//! Kubernetes API client module.
pub const typed = @import("typed.zig");
pub const watch = @import("watch.zig");

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
