const client_file = @import("Client.zig");

pub const Client = client_file.Client;
pub const ClientError = client_file.ClientError;

test {
    _ = client_file;
}
