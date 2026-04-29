//! Override types for Kubernetes-compatible JSON parsing.
//!
//! These types replace the generated protobuf types to handle
//! Kubernetes JSON format differences:
//! - Time/MicroTime: RFC3339 strings instead of {seconds, nanos}
//! - Quantity: Plain strings instead of {string: "..."}
//! - IntOrString: Raw int/string instead of {type, intVal, strVal}
//! - RawExtension: Embedded objects instead of {raw: bytes}
//! - FieldsV1: Embedded objects instead of {Raw: bytes}

pub const time = @import("time.zig");
pub const quantity = @import("quantity.zig");
pub const intstr = @import("intstr.zig");
pub const raw_extension = @import("raw_extension.zig");
pub const fields_v1 = @import("fields_v1.zig");

// Re-export the types directly
pub const Time = time.Time;
pub const MicroTime = time.MicroTime;
pub const Quantity = quantity.Quantity;
pub const QuantityValue = quantity.QuantityValue;
pub const IntOrString = intstr.IntOrString;
pub const RawExtension = raw_extension.RawExtension;
pub const FieldsV1 = fields_v1.FieldsV1;
