const std = @import("std");
const fmt = std.fmt;

const dns = @import("./dns.zig");
const Type = dns.ResourceType;

pub const SOAData = struct {
    mname: dns.Name,
    rname: dns.Name,
    serial: u32,
    refresh: u32,
    retry: u32,
    expire: u32,
    minimum: u32,
};

pub const MXData = struct {
    preference: u16,
    exchange: dns.Name,
};

pub const SRVData = struct {
    priority: u16,
    weight: u16,
    port: u16,
    target: dns.Name,
};

/// Common representations of DNS' Resource Data.
pub const ResourceData = union(Type) {
    A: std.net.Address,
    AAAA: std.net.Address,

    NS: dns.Name,
    MD: dns.Name,
    MF: dns.Name,
    CNAME: dns.Name,
    SOA: SOAData,

    MB: dns.Name,
    MG: dns.Name,
    MR: dns.Name,

    // ????
    NULL: void,

    // TODO WKS bit map
    WKS: struct {
        addr: u32,
        proto: u8,
        // how to define bit map? align(8)?
    },
    PTR: dns.Name,

    // TODO replace by Name?
    HINFO: struct {
        cpu: []const u8,
        os: []const u8,
    },
    MINFO: struct {
        rmailbx: dns.Name,
        emailbx: dns.Name,
    },
    MX: MXData,
    TXT: [][]const u8,

    SRV: SRVData,

    const Self = @This();

    pub fn size(self: Self) usize {
        return switch (self) {
            .A => 4,
            .AAAA => 16,
            .NS, .MD, .MF, .MB, .MG, .MR, .CNAME, .PTR => |name| name.size(),

            else => @panic("TODO"),
        };
    }

    /// Format the RData into a prettier version of it.
    ///
    /// For example, a resource data of type A would be
    /// formatted to its representing IPv4 address.
    pub fn format(self: Self, comptime f: []const u8, options: fmt.FormatOptions, writer: anytype) !void {
        if (f.len != 0) {
            @compileError("Unknown format character: '" ++ f ++ "'");
        }

        switch (self) {
            .A, .AAAA => |addr| return fmt.format(writer, "{}", .{addr}),

            .NS, .MD, .MF, .MB, .MG, .MR, .CNAME, .PTR => |name| return fmt.format(writer, "{}", .{name}),

            .SOA => |soa| return fmt.format(writer, "{} {} {} {} {} {} {}", .{
                soa.mname,
                soa.rname,
                soa.serial,
                soa.refresh,
                soa.retry,
                soa.expire,
                soa.minimum,
            }),

            .MX => |mx| return fmt.format(writer, "{} {}", .{ mx.preference, mx.exchange }),
            .SRV => |srv| return fmt.format(writer, "{} {} {} {}", .{
                srv.priority,
                srv.weight,
                srv.port,
                srv.target,
            }),

            else => return fmt.format(writer, "TODO support {}", .{@tagName(self)}),
        }
        return fmt.format(writer, "{}");
    }

    pub fn serialize(self: Self, serializer: anytype) !void {
        switch (self) {
            .A => |addr| {
                try serializer.serialize(addr.in.sa.addr);
            },
            .AAAA => |addr| try serializer.serialize(addr.in6.sa.addr),

            .NS, .MD, .MF, .MB, .MG, .MR, .CNAME, .PTR => |name| try serializer.serialize(name),

            .SOA => |soa_data| {
                try serializer.serialize(soa_data.mname);
                try serializer.serialize(soa_data.rname);
                try serializer.serialize(soa_data.serial);
                try serializer.serialize(soa_data.refresh);
                try serializer.serialize(soa_data.retry);
                try serializer.serialize(soa_data.expire);
                try serializer.serialize(soa_data.minimum);
            },

            .MX => |mxdata| {
                try serializer.serialize(mxdata.preference);
                try serializer.serialize(mxdata.exchange);
            },

            .SRV => |srv| {
                try serializer.serialize(srv.priority);
                try serializer.serialize(srv.weight);
                try serializer.serialize(srv.port);
                try serializer.serialize(srv.target);
            },

            else => @panic("not implemented"),
        }
    }
};

/// Deserialize a given opaque resource data.
pub fn deserializeRData(
    allocator: *std.mem.Allocator,
    opaque_resource_data: []const u8,
) !ResourceData {
    var in = dns.FixedStream{ .buffer = resource.opaque_rdata, .pos = 0 };
    var deserializer = dns.DNSDeserializer.init(in.reader());

    const BufferT = std.io.FixedBufferStream([]const u8);
    var stream = BufferT{ .buffer = opaque_resource_data, .pos = 0 };
    const DeserializerT = std.io.Deserializer(.Big, .Bit, BufferT.Reader);

    var deserializer = DeserializerT.init(stream);

    var rdata = switch (resource.rr_type) {
        .A => blk: {
            var ip4addr: [4]u8 = undefined;
            for (ip4addr) |_, i| {
                ip4addr[i] = try deserializer.deserialize(u8);
            }

            break :blk ResourceData{
                .A = std.net.Address.initIp4(ip4addr, 0),
            };
        },
        .AAAA => blk: {
            var ip6_addr: [16]u8 = undefined;

            for (ip6_addr) |byte, i| {
                ip6_addr[i] = try deserializer.deserialize(u8);
            }

            break :blk ResourceData{
                .AAAA = std.net.Address.initIp6(ip6_addr, 0, 0, 0),
            };
        },

        .NS => ResourceData{ .NS = try pkt.deserializeName(&deserializer) },
        .CNAME => ResourceData{ .CNAME = try pkt.deserializeName(&deserializer) },
        .PTR => ResourceData{ .PTR = try pkt.deserializeName(&deserializer) },
        .MX => blk: {
            break :blk ResourceData{
                .MX = MXData{
                    .preference = try deserializer.deserialize(u16),
                    .exchange = try pkt.deserializeName(&deserializer),
                },
            };
        },
        .MD => ResourceData{ .MD = try pkt.deserializeName(&deserializer) },
        .MF => ResourceData{ .MF = try pkt.deserializeName(&deserializer) },

        .SOA => blk: {
            var mname = try pkt.deserializeName(&deserializer);
            var rname = try pkt.deserializeName(&deserializer);
            var serial = try deserializer.deserialize(u32);
            var refresh = try deserializer.deserialize(u32);
            var retry = try deserializer.deserialize(u32);
            var expire = try deserializer.deserialize(u32);
            var minimum = try deserializer.deserialize(u32);

            break :blk ResourceData{
                .SOA = SOAData{
                    .mname = mname,
                    .rname = rname,
                    .serial = serial,
                    .refresh = refresh,
                    .retry = retry,
                    .expire = expire,
                    .minimum = minimum,
                },
            };
        },
        .SRV => blk: {
            const priority = try deserializer.deserialize(u16);
            const weight = try deserializer.deserialize(u16);
            const port = try deserializer.deserialize(u16);
            var target = try pkt.deserializeName(&deserializer);

            break :blk ResourceData{
                .SRV = .{
                    .priority = priority,
                    .weight = weight,
                    .port = port,
                    .target = target,
                },
            };
        },

        else => {
            return error.InvalidRData;
        },
    };

    return rdata;
}

/// Serialize a given ResourceData into []u8
pub fn serializeRData(
    rdata: ResourceData,
    serializer: anytype,
) !void {
    switch (rdata) {
        .A => |addr| try serializer.serialize(addr.in.addr),
        .AAAA => |addr| try serializer.serialize(addr.in6.addr),

        .NS, .MD, .MF, .MB, .MG, .MR, .CNAME, .PTR => |name| try serializer.serialize(name),

        .SOA => |soa_data| blk: {
            try serializer.serialize(soa_data.mname);
            try serializer.serialize(soa_data.rname);

            try serializer.serialize(soa_data.serial);
            try serializer.serialize(soa_data.refresh);
            try serializer.serialize(soa_data.retry);
            try serializer.serialize(soa_data.expire);
            try serializer.serialize(soa_data.minimum);
        },

        .MX => |mxdata| blk: {
            try serializer.serialize(mxdata.preference);
            try serializer.serialize(mxdata.exchange);
        },

        .SRV => |srv| blk: {
            try serializer.serialize(srv.priority);
            try serializer.serialize(srv.weight);
            try serializer.serialize(srv.port);
            try serializer.serialize(srv.target);
        },

        else => return error.NotImplemented,
    }
}