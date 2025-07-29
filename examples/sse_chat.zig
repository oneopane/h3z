//! Real-time chat application using Server-Sent Events (SSE)
//! This example demonstrates:
//! - Multiple concurrent SSE connections
//! - Broadcasting messages to all connected clients
//! - Handling client connections and disconnections
//! - JSON message formatting for chat events

const std = @import("std");
const h3 = @import("h3");

const H3 = h3.H3;
const serve = h3.serve;
const ServeOptions = h3.ServeOptions;
const SSEWriter = h3.SSEWriter;
const SSEEvent = h3.SSEEvent;

/// Chat message structure
const ChatMessage = struct {
    id: u64,
    user: []const u8,
    message: []const u8,
    timestamp: i64,
};

/// Connected client information
const Client = struct {
    id: u64,
    username: []const u8,
    writer: *SSEWriter,
    connected_at: i64,
    
    pub fn deinit(self: *Client, allocator: std.mem.Allocator) void {
        allocator.free(self.username);
        self.writer.close();
        allocator.destroy(self.writer);
    }
};

/// Chat room manager
const ChatRoom = struct {
    allocator: std.mem.Allocator,
    clients: std.ArrayList(*Client),
    message_history: std.ArrayList(ChatMessage),
    next_client_id: std.atomic.Value(u64),
    next_message_id: std.atomic.Value(u64),
    mutex: std.Thread.Mutex,
    
    pub fn init(allocator: std.mem.Allocator) ChatRoom {
        return .{
            .allocator = allocator,
            .clients = std.ArrayList(*Client).init(allocator),
            .message_history = std.ArrayList(ChatMessage).init(allocator),
            .next_client_id = std.atomic.Value(u64).init(1),
            .next_message_id = std.atomic.Value(u64).init(1),
            .mutex = std.Thread.Mutex{},
        };
    }
    
    pub fn deinit(self: *ChatRoom) void {
        // Clean up all clients
        for (self.clients.items) |client| {
            client.deinit(self.allocator);
            self.allocator.destroy(client);
        }
        self.clients.deinit();
        
        // Clean up message history
        for (self.message_history.items) |msg| {
            self.allocator.free(msg.user);
            self.allocator.free(msg.message);
        }
        self.message_history.deinit();
    }
    
    /// Add a new client to the chat room
    pub fn addClient(self: *ChatRoom, username: []const u8, writer: *SSEWriter) !*Client {
        const client = try self.allocator.create(Client);
        client.* = .{
            .id = self.next_client_id.fetchAdd(1, .seq_cst),
            .username = try self.allocator.dupe(u8, username),
            .writer = writer,
            .connected_at = std.time.timestamp(),
        };
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.clients.append(client);
        
        // Send welcome message
        const welcome_data = try std.fmt.allocPrint(self.allocator, 
            \\{{
            \\  "type": "welcome",
            \\  "userId": {d},
            \\  "message": "Welcome to the chat, {s}!"
            \\}}
        , .{ client.id, client.username });
        defer self.allocator.free(welcome_data);
        
        try writer.sendEvent(SSEEvent.typedEvent("system", welcome_data));
        
        // Send recent message history
        const history_start = if (self.message_history.items.len > 10) 
            self.message_history.items.len - 10 
        else 
            0;
            
        for (self.message_history.items[history_start..]) |msg| {
            const history_data = try std.fmt.allocPrint(self.allocator,
                \\{{
                \\  "type": "message",
                \\  "id": {d},
                \\  "user": "{s}",
                \\  "message": "{s}",
                \\  "timestamp": {d}
                \\}}
            , .{ msg.id, msg.user, msg.message, msg.timestamp });
            defer self.allocator.free(history_data);
            
            try writer.sendEvent(SSEEvent.typedEvent("message", history_data));
        }
        
        // Notify other clients
        try self.broadcastUserEvent(client, "join");
        
        std.log.info("Client {s} (ID: {d}) joined the chat", .{ client.username, client.id });
        
        return client;
    }
    
    /// Remove a client from the chat room
    pub fn removeClient(self: *ChatRoom, client_id: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var removed_client: ?*Client = null;
        var i: usize = 0;
        while (i < self.clients.items.len) {
            if (self.clients.items[i].id == client_id) {
                removed_client = self.clients.orderedRemove(i);
                break;
            }
            i += 1;
        }
        
        if (removed_client) |client| {
            std.log.info("Client {s} (ID: {d}) left the chat", .{ client.username, client.id });
            self.broadcastUserEvent(client, "leave") catch |err| {
                std.log.err("Failed to broadcast leave event: {}", .{err});
            };
            
            client.deinit(self.allocator);
            self.allocator.destroy(client);
        }
    }
    
    /// Broadcast a message from a client to all other clients
    pub fn broadcastMessage(self: *ChatRoom, sender_id: u64, message_text: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Find sender
        var sender: ?*Client = null;
        for (self.clients.items) |client| {
            if (client.id == sender_id) {
                sender = client;
                break;
            }
        }
        
        if (sender == null) return;
        
        // Create message
        const msg = ChatMessage{
            .id = self.next_message_id.fetchAdd(1, .seq_cst),
            .user = try self.allocator.dupe(u8, sender.?.username),
            .message = try self.allocator.dupe(u8, message_text),
            .timestamp = std.time.timestamp(),
        };
        
        // Add to history
        try self.message_history.append(msg);
        
        // Keep history limited to 100 messages
        if (self.message_history.items.len > 100) {
            const old_msg = self.message_history.orderedRemove(0);
            self.allocator.free(old_msg.user);
            self.allocator.free(old_msg.message);
        }
        
        // Format message as JSON
        const json_data = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "type": "message",
            \\  "id": {d},
            \\  "user": "{s}",
            \\  "message": "{s}",
            \\  "timestamp": {d}
            \\}}
        , .{ msg.id, msg.user, msg.message, msg.timestamp });
        defer self.allocator.free(json_data);
        
        // Broadcast to all clients
        var failed_clients = std.ArrayList(u64).init(self.allocator);
        defer failed_clients.deinit();
        
        for (self.clients.items) |client| {
            client.writer.sendEvent(SSEEvent.typedEvent("message", json_data)) catch |err| {
                std.log.warn("Failed to send message to client {d}: {}", .{ client.id, err });
                try failed_clients.append(client.id);
            };
        }
        
        // Remove failed clients (outside the loop to avoid iterator invalidation)
        for (failed_clients.items) |client_id| {
            self.removeClient(client_id);
        }
    }
    
    /// Broadcast user join/leave events
    fn broadcastUserEvent(self: *ChatRoom, user: *Client, event_type: []const u8) !void {
        const json_data = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "type": "user-{s}",
            \\  "userId": {d},
            \\  "username": "{s}",
            \\  "timestamp": {d}
            \\}}
        , .{ event_type, user.id, user.username, std.time.timestamp() });
        defer self.allocator.free(json_data);
        
        // Send to all other clients
        for (self.clients.items) |client| {
            if (client.id != user.id) {
                client.writer.sendEvent(SSEEvent.typedEvent("user-event", json_data)) catch |err| {
                    std.log.warn("Failed to send user event to client {d}: {}", .{ client.id, err });
                };
            }
        }
    }
    
    /// Send periodic heartbeat to all clients
    pub fn sendHeartbeat(self: *ChatRoom) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        var failed_clients = std.ArrayList(u64).init(self.allocator);
        defer failed_clients.deinit();
        
        for (self.clients.items) |client| {
            client.writer.sendKeepAlive() catch |err| {
                std.log.debug("Failed to send heartbeat to client {d}: {}", .{ client.id, err });
                failed_clients.append(client.id) catch {};
            };
        }
        
        // Remove failed clients
        for (failed_clients.items) |client_id| {
            self.removeClient(client_id);
        }
    }
};

// Global chat room instance
var chat_room: ?ChatRoom = null;

/// SSE endpoint for chat stream
pub fn handleChatStream(event: *h3.Event) !void {
    // Get username from query parameter
    const username = event.getQuery("username") orelse "Anonymous";
    
    // Start SSE
    try event.startSSE();
    
    // Get SSE writer
    const writer = try event.getSSEWriter();
    
    // Add client to chat room
    if (chat_room) |*room| {
        const client = try room.addClient(username, writer);
        
        // Note: In a real application, you would need to handle cleanup
        // when the connection is closed. This could be done by:
        // 1. Using a connection close callback from the server adapter
        // 2. Detecting write failures and removing the client
        // 3. Implementing a timeout mechanism
        
        _ = client;
    }
}

/// REST endpoint for sending messages
pub fn handleSendMessage(event: *h3.Event) !void {
    // Parse request body
    const body = event.readBody() orelse {
        try event.sendError(.bad_request, "Missing request body");
        return;
    };
    
    // Simple JSON parsing (in production, use a proper JSON parser)
    // Expected format: {"userId": 123, "message": "Hello, world!"}
    var user_id: ?u64 = null;
    var message: ?[]const u8 = null;
    
    // Extract userId
    if (std.mem.indexOf(u8, body, "\"userId\":")) |user_id_pos| {
        const start = user_id_pos + 9;
        var end = start;
        while (end < body.len and body[end] >= '0' and body[end] <= '9') : (end += 1) {}
        user_id = try std.fmt.parseInt(u64, body[start..end], 10);
    }
    
    // Extract message
    if (std.mem.indexOf(u8, body, "\"message\":")) |msg_pos| {
        const start = msg_pos + 10;
        if (start < body.len and body[start] == '"') {
            const msg_start = start + 1;
            if (std.mem.indexOf(u8, body[msg_start..], "\"")) |msg_end| {
                message = body[msg_start..msg_start + msg_end];
            }
        }
    }
    
    if (user_id == null or message == null) {
        try event.sendError(.bad_request, "Invalid request format");
        return;
    }
    
    // Broadcast message
    if (chat_room) |*room| {
        try room.broadcastMessage(user_id.?, message.?);
        try event.sendJson("{\"success\": true}");
    } else {
        try event.sendError(.internal_server_error, "Chat room not initialized");
    }
}

/// HTML page for the chat client
pub fn handleChatPage(event: *h3.Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>H3Z SSE Chat Example</title>
        \\    <style>
        \\        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        \\        #chat-box { height: 400px; overflow-y: auto; border: 1px solid #ccc; padding: 10px; margin-bottom: 10px; }
        \\        .message { margin: 5px 0; }
        \\        .system { color: #666; font-style: italic; }
        \\        .user-event { color: #090; }
        \\        #message-input { width: 70%; padding: 5px; }
        \\        #send-button { width: 25%; padding: 5px; }
        \\        #username-input { margin-bottom: 10px; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <h1>H3Z SSE Chat Example</h1>
        \\    <div id="login">
        \\        <input type="text" id="username-input" placeholder="Enter your username" />
        \\        <button onclick="connect()">Join Chat</button>
        \\    </div>
        \\    <div id="chat" style="display: none;">
        \\        <div id="chat-box"></div>
        \\        <div>
        \\            <input type="text" id="message-input" placeholder="Type a message..." />
        \\            <button id="send-button" onclick="sendMessage()">Send</button>
        \\        </div>
        \\    </div>
        \\    
        \\    <script>
        \\        let eventSource = null;
        \\        let userId = null;
        \\        
        \\        function connect() {
        \\            const username = document.getElementById('username-input').value || 'Anonymous';
        \\            
        \\            eventSource = new EventSource('/chat/stream?username=' + encodeURIComponent(username));
        \\            
        \\            eventSource.addEventListener('system', (e) => {
        \\                const data = JSON.parse(e.data);
        \\                if (data.type === 'welcome') {
        \\                    userId = data.userId;
        \\                    addMessage('System', data.message, 'system');
        \\                    document.getElementById('login').style.display = 'none';
        \\                    document.getElementById('chat').style.display = 'block';
        \\                }
        \\            });
        \\            
        \\            eventSource.addEventListener('message', (e) => {
        \\                const data = JSON.parse(e.data);
        \\                addMessage(data.user, data.message, 'message');
        \\            });
        \\            
        \\            eventSource.addEventListener('user-event', (e) => {
        \\                const data = JSON.parse(e.data);
        \\                if (data.type === 'user-join') {
        \\                    addMessage('System', data.username + ' joined the chat', 'user-event');
        \\                } else if (data.type === 'user-leave') {
        \\                    addMessage('System', data.username + ' left the chat', 'user-event');
        \\                }
        \\            });
        \\            
        \\            eventSource.onerror = (e) => {
        \\                console.error('SSE error:', e);
        \\                addMessage('System', 'Connection lost. Please refresh the page.', 'system');
        \\                eventSource.close();
        \\            };
        \\        }
        \\        
        \\        function addMessage(user, message, className) {
        \\            const chatBox = document.getElementById('chat-box');
        \\            const messageDiv = document.createElement('div');
        \\            messageDiv.className = 'message ' + className;
        \\            messageDiv.textContent = user + ': ' + message;
        \\            chatBox.appendChild(messageDiv);
        \\            chatBox.scrollTop = chatBox.scrollHeight;
        \\        }
        \\        
        \\        function sendMessage() {
        \\            const input = document.getElementById('message-input');
        \\            const message = input.value.trim();
        \\            
        \\            if (message && userId) {
        \\                fetch('/chat/send', {
        \\                    method: 'POST',
        \\                    headers: { 'Content-Type': 'application/json' },
        \\                    body: JSON.stringify({ userId: userId, message: message })
        \\                }).catch(err => console.error('Send error:', err));
        \\                
        \\                input.value = '';
        \\            }
        \\        }
        \\        
        \\        // Send message on Enter key
        \\        document.addEventListener('DOMContentLoaded', () => {
        \\            document.getElementById('message-input').addEventListener('keypress', (e) => {
        \\                if (e.key === 'Enter') sendMessage();
        \\            });
        \\            document.getElementById('username-input').addEventListener('keypress', (e) => {
        \\                if (e.key === 'Enter') connect();
        \\            });
        \\        });
        \\    </script>
        \\</body>
        \\</html>
    ;
    
    try event.sendHtml(html);
}

/// Heartbeat thread function
fn heartbeatThread() void {
    while (true) {
        std.time.sleep(30 * std.time.ns_per_s); // Send heartbeat every 30 seconds
        
        if (chat_room) |*room| {
            room.sendHeartbeat();
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize chat room
    chat_room = ChatRoom.init(allocator);
    defer if (chat_room) |*room| room.deinit();
    
    // Start heartbeat thread
    const heartbeat = try std.Thread.spawn(.{}, heartbeatThread, .{});
    heartbeat.detach();
    
    // Create app using legacy API
    var app = try H3.init(allocator);
    defer app.deinit();
    
    // Register routes
    _ = app.get("/", handleChatPage);
    _ = app.get("/chat/stream", handleChatStream);
    _ = app.post("/chat/send", handleSendMessage);
    
    // Start server
    const port: u16 = 3001;
    std.log.info("SSE Chat server starting on http://localhost:{d}", .{port});
    std.log.info("Open multiple browser windows to test multi-user chat", .{});
    
    try serve(&app, ServeOptions{ .port = port });
}