//! HTTP status codes as defined in RFC 7231 and other RFCs

const std = @import("std");
const string_format = @import("../utils/string_format.zig");

/// HTTP status codes
pub const HttpStatus = enum(u16) {
    // 1xx Informational
    continue_ = 100,
    switching_protocols = 101,
    processing = 102,
    early_hints = 103,

    // 2xx Success
    ok = 200,
    created = 201,
    accepted = 202,
    non_authoritative_information = 203,
    no_content = 204,
    reset_content = 205,
    partial_content = 206,
    multi_status = 207,
    already_reported = 208,
    im_used = 226,

    // 3xx Redirection
    multiple_choices = 300,
    moved_permanently = 301,
    found = 302,
    see_other = 303,
    not_modified = 304,
    use_proxy = 305,
    temporary_redirect = 307,
    permanent_redirect = 308,

    // 4xx Client Error
    bad_request = 400,
    unauthorized = 401,
    payment_required = 402,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    not_acceptable = 406,
    proxy_authentication_required = 407,
    request_timeout = 408,
    conflict = 409,
    gone = 410,
    length_required = 411,
    precondition_failed = 412,
    payload_too_large = 413,
    uri_too_long = 414,
    unsupported_media_type = 415,
    range_not_satisfiable = 416,
    expectation_failed = 417,
    im_a_teapot = 418,
    misdirected_request = 421,
    unprocessable_entity = 422,
    locked = 423,
    failed_dependency = 424,
    too_early = 425,
    upgrade_required = 426,
    precondition_required = 428,
    too_many_requests = 429,
    request_header_fields_too_large = 431,
    unavailable_for_legal_reasons = 451,

    // 5xx Server Error
    internal_server_error = 500,
    not_implemented = 501,
    bad_gateway = 502,
    service_unavailable = 503,
    gateway_timeout = 504,
    http_version_not_supported = 505,
    variant_also_negotiates = 506,
    insufficient_storage = 507,
    loop_detected = 508,
    not_extended = 510,
    network_authentication_required = 511,

    /// Get the numeric value of the status code
    pub fn code(self: HttpStatus) u16 {
        return @intFromEnum(self);
    }

    /// Get the reason phrase for the status code
    pub fn phrase(self: HttpStatus) []const u8 {
        return switch (self) {
            .continue_ => "Continue",
            .ok => "OK",
            .im_used => "IM Used",
            .im_a_teapot => "I'm a teapot",
            inline else => |tag| comptime string_format.snakeCaseToTitleCase(@tagName(tag)),
        };
    }

    /// Check if status code indicates success (2xx)
    pub fn isSuccess(self: HttpStatus) bool {
        const code_val = self.code();
        return code_val >= 200 and code_val < 300;
    }

    /// Check if status code indicates redirection (3xx)
    pub fn isRedirection(self: HttpStatus) bool {
        const code_val = self.code();
        return code_val >= 300 and code_val < 400;
    }

    /// Check if status code indicates client error (4xx)
    pub fn isClientError(self: HttpStatus) bool {
        const code_val = self.code();
        return code_val >= 400 and code_val < 500;
    }

    /// Check if status code indicates server error (5xx)
    pub fn isServerError(self: HttpStatus) bool {
        const code_val = self.code();
        return code_val >= 500 and code_val < 600;
    }

    /// Check if status code indicates an error (4xx or 5xx)
    pub fn isError(self: HttpStatus) bool {
        return self.isClientError() or self.isServerError();
    }
};

test "HttpStatus.code" {
    try std.testing.expectEqual(@as(u16, 200), HttpStatus.ok.code());
    try std.testing.expectEqual(@as(u16, 404), HttpStatus.not_found.code());
    try std.testing.expectEqual(@as(u16, 500), HttpStatus.internal_server_error.code());
}

test "HttpStatus.phrase" {
    try std.testing.expectEqualStrings("OK", HttpStatus.ok.phrase());
    try std.testing.expectEqualStrings("Not Found", HttpStatus.not_found.phrase());
    try std.testing.expectEqualStrings("Internal Server Error", HttpStatus.internal_server_error.phrase());
}

test "HttpStatus.isSuccess" {
    try std.testing.expect(HttpStatus.ok.isSuccess());
    try std.testing.expect(HttpStatus.created.isSuccess());
    try std.testing.expect(!HttpStatus.not_found.isSuccess());
    try std.testing.expect(!HttpStatus.internal_server_error.isSuccess());
}

test "HttpStatus.isError" {
    try std.testing.expect(HttpStatus.not_found.isError());
    try std.testing.expect(HttpStatus.internal_server_error.isError());
    try std.testing.expect(!HttpStatus.ok.isError());
    try std.testing.expect(!HttpStatus.found.isError());
}
