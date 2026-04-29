#!/usr/bin/env bash
# Post-processing script to patch generated proto types for Kubernetes JSON compatibility.
# This script:
# 1. Renames generated types that need custom JSON parsing (e.g., Time -> _GeneratedTime)
# 2. Adds imports to use the override types from src/proto/overrides/

set -e

PROTO_DIR="src/proto"
OVERRIDES_IMPORT_PATH="overrides"

# Define the types to patch and their locations
# Format: "file_path:type_name:override_module"
PATCHES=(
    "k8s/io/apimachinery/pkg/apis/meta/v1.pb.zig:Time:time"
    "k8s/io/apimachinery/pkg/apis/meta/v1.pb.zig:MicroTime:time"
    "k8s/io/apimachinery/pkg/apis/meta/v1.pb.zig:FieldsV1:fields_v1"
    "k8s/io/apimachinery/pkg/api/resource.pb.zig:Quantity:quantity"
    "k8s/io/apimachinery/pkg/api/resource.pb.zig:QuantityValue:quantity"
    "k8s/io/apimachinery/pkg/util/intstr.pb.zig:IntOrString:intstr"
    "k8s/io/apimachinery/pkg/runtime.pb.zig:RawExtension:raw_extension"
)

echo "Patching proto types for Kubernetes JSON compatibility..."

for patch in "${PATCHES[@]}"; do
    IFS=':' read -r file_path type_name override_module <<< "$patch"
    full_path="${PROTO_DIR}/${file_path}"

    if [[ ! -f "$full_path" ]]; then
        echo "Warning: File not found: $full_path"
        continue
    fi

    echo "  Patching ${type_name} in ${file_path}..."

    # 1. Rename the generated type (e.g., "pub const Time = struct {" -> "pub const _GeneratedTime = struct {")
    sed -i "s/^pub const ${type_name} = struct {/pub const _Generated${type_name} = struct {/" "$full_path"

    # 2. Calculate the relative import path based on file depth
    # Count the depth from src/proto/k8s/... to src/proto/overrides/
    depth=$(echo "$file_path" | tr -cd '/' | wc -c)
    rel_path=""
    for ((i=0; i<depth; i++)); do
        rel_path="../${rel_path}"
    done
    rel_path="${rel_path}${OVERRIDES_IMPORT_PATH}/${override_module}.zig"

    # 3. Check if import already exists
    if grep -q "const ${type_name} = @import(\".*${override_module}.zig\").${type_name};" "$full_path"; then
        echo "    Import already exists for ${type_name}"
        continue
    fi

    # 4. Add the import after the existing imports (after "const fd = protobuf.fd;")
    # We add: pub const Time = @import("../../../overrides/time.zig").Time;
    sed -i "/^const fd = protobuf.fd;/a\\
pub const ${type_name} = @import(\"${rel_path}\").${type_name};" "$full_path"

    echo "    Added import: pub const ${type_name} = @import(\"${rel_path}\").${type_name};"
done

echo "Done patching proto types."

# Format the patched files
echo "Formatting patched files..."
zig fmt "${PROTO_DIR}/" 2>/dev/null || true

echo "Proto type patching complete!"
