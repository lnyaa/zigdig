// DNS protocol helpers, e.g starting a socket.
const std = @import("std");
const net = std.net;
const os = std.os;
const io = std.io;

const posix = os.posix;

const DNSError = error{NetError};

const OutError = io.SliceOutStream.Error;
const InError = io.SliceInStream.Error;

/// Returns the socket file descriptor for an UDP socket.
pub fn openDNSSocket(addr: net.Address) !i32 {
    var sockfd = try os.posixSocket(
        posix.AF_INET,
        posix.SOCK_DGRAM,
        posix.PROTO_udp,
    );

    const const_addr = &addr.os_addr;
    try os.posixConnect(sockfd, const_addr);
    return sockfd;
}

pub fn sendDNSPacket(sockfd: i32, packet: DNSPacket, buffer: []u8) !void {
    var out = io.SliceOutStream.inti(buffer);
    var out_stream = &out.stream;
    var serializer = io.Serializer(.Big, .Bit, OutError).init(out_stream);

    try serializer.serialize(packet);
    try serializer.flush();

    try os.posixWrite(sockfd, buffer);
}

pub fn recvDNSPacket(sockfd: i32, buffer: []u8) !DNSPacket {
    var byte_count = try os.posixRead(sockfd, buffer);
    if (byte_count == 0) return DNSError.NetError;

    var in = io.SliceInStream.init(buffer);
    var in_stream = &in.stream;
    var deserializer = io.Deserializer(.Big, .Bit, InError).init(in_stream);
    return try deserializer.deserialize(DNSPacket);
}

test "fake socket open/close" {
    var ip4addr = try std.net.parseIp4("127.0.0.1");
    var addr = std.net.Address.initIp4(ip4addr, 53);
    var sockfd = try openDNSSocket(addr);

    os.close(sockfd);
}