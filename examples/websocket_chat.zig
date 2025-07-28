//! WebSocket Chat Example
//! Demonstrates WebSocket support, real-time communication, and component architecture

const std = @import("std");
const h3 = @import("h3");

const Message = struct {
    id: u32,
    user: []const u8,
    text: []const u8,
    timestamp: i64,
};

const ChatRoom = struct {
    name: []const u8,
    messages: std.ArrayList(Message),
    connections: std.ArrayList(*h3.Event),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !ChatRoom {
        return .{
            .name = try allocator.dupe(u8, name),
            .messages = std.ArrayList(Message).init(allocator),
            .connections = std.ArrayList(*h3.Event).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ChatRoom) void {
        self.allocator.free(self.name);
        self.messages.deinit();
        self.connections.deinit();
    }

    pub fn addMessage(self: *ChatRoom, user: []const u8, text: []const u8) !void {
        const msg = Message{
            .id = @intCast(self.messages.items.len + 1),
            .user = try self.allocator.dupe(u8, user),
            .text = try self.allocator.dupe(u8, text),
            .timestamp = std.time.timestamp(),
        };
        try self.messages.append(msg);
    }

    pub fn broadcast(self: *ChatRoom, message: []const u8) !void {
        for (self.connections.items) |conn| {
            // In real implementation, send WebSocket frame
            _ = conn;
            _ = message;
        }
    }
};

const ChatComponent = struct {
    rooms: std.StringHashMap(ChatRoom),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !ChatComponent {
        var rooms = std.StringHashMap(ChatRoom).init(allocator);
        
        // Create default room
        var default_room = try ChatRoom.init(allocator, "general");
        try rooms.put("general", default_room);

        return .{
            .rooms = rooms,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ChatComponent) void {
        var it = self.rooms.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.rooms.deinit();
    }

    pub fn configure(self: *ChatComponent, app: *h3.H3App) !void {
        // Chat UI
        _ = try app.router.get("/", chatUIHandler);
        
        // WebSocket endpoint
        _ = try app.router.get("/ws/:room", self.websocketHandler);
        
        // REST API for chat
        _ = try app.router.get("/api/rooms", self.getRoomsHandler);
        _ = try app.router.post("/api/rooms", self.createRoomHandler);
        _ = try app.router.get("/api/rooms/:room/messages", self.getMessagesHandler);
        _ = try app.router.post("/api/rooms/:room/messages", self.postMessageHandler);
    }

    fn websocketHandler(self: *ChatComponent, event: *h3.Event) !void {
        const room_name = h3.getParam(event, "room") orelse "general";
        
        // Check for WebSocket upgrade
        const upgrade_header = h3.getHeader(event, "Upgrade") orelse {
            try h3.response.badRequest(event, "WebSocket upgrade required");
            return;
        };

        if (!std.mem.eql(u8, upgrade_header, "websocket")) {
            try h3.response.badRequest(event, "WebSocket upgrade required");
            return;
        }

        // Get or create room
        const room = self.rooms.getPtr(room_name) orelse {
            try h3.response.notFound(event, "Room not found");
            return;
        };

        // Simulate WebSocket upgrade
        try h3.setHeader(event, "Upgrade", "websocket");
        try h3.setHeader(event, "Connection", "Upgrade");
        h3.setStatus(event, .switching_protocols);

        // Add connection to room
        try room.connections.append(event);

        // Send join message
        const join_msg = try std.fmt.allocPrint(
            event.allocator,
            "{{\"type\":\"join\",\"room\":\"{s}\",\"users\":{d}}}",
            .{ room_name, room.connections.items.len }
        );
        defer event.allocator.free(join_msg);

        try room.broadcast(join_msg);
    }

    fn getRoomsHandler(self: *ChatComponent, event: *h3.Event) !void {
        var rooms_list = std.ArrayList(struct {
            name: []const u8,
            users: usize,
            messages: usize,
        }).init(event.allocator);
        defer rooms_list.deinit();

        var it = self.rooms.iterator();
        while (it.next()) |entry| {
            try rooms_list.append(.{
                .name = entry.key_ptr.*,
                .users = entry.value_ptr.connections.items.len,
                .messages = entry.value_ptr.messages.items.len,
            });
        }

        try h3.sendJson(event, rooms_list.items);
    }

    fn createRoomHandler(self: *ChatComponent, event: *h3.Event) !void {
        const CreateRoomRequest = struct {
            name: []const u8,
        };

        const req = try h3.readJson(event, CreateRoomRequest);

        // Check if room exists
        if (self.rooms.contains(req.name)) {
            try h3.response.badRequest(event, "Room already exists");
            return;
        }

        // Create new room
        var room = try ChatRoom.init(self.allocator, req.name);
        try self.rooms.put(req.name, room);

        const response = .{
            .success = true,
            .room = req.name,
        };

        h3.setStatus(event, .created);
        try h3.sendJson(event, response);
    }

    fn getMessagesHandler(self: *ChatComponent, event: *h3.Event) !void {
        const room_name = h3.getParam(event, "room") orelse return error.MissingParam;
        
        const room = self.rooms.get(room_name) orelse {
            try h3.response.notFound(event, "Room not found");
            return;
        };

        try h3.sendJson(event, room.messages.items);
    }

    fn postMessageHandler(self: *ChatComponent, event: *h3.Event) !void {
        const room_name = h3.getParam(event, "room") orelse return error.MissingParam;
        
        const PostMessageRequest = struct {
            user: []const u8,
            text: []const u8,
        };

        const req = try h3.readJson(event, PostMessageRequest);

        var room = self.rooms.getPtr(room_name) orelse {
            try h3.response.notFound(event, "Room not found");
            return;
        };

        try room.addMessage(req.user, req.text);

        // Broadcast to WebSocket connections
        const ws_msg = try std.fmt.allocPrint(
            event.allocator,
            "{{\"type\":\"message\",\"user\":\"{s}\",\"text\":\"{s}\",\"timestamp\":{d}}}",
            .{ req.user, req.text, std.time.timestamp() }
        );
        defer event.allocator.free(ws_msg);

        try room.broadcast(ws_msg);

        const response = .{
            .success = true,
            .message_id = room.messages.items.len,
        };

        try h3.sendJson(event, response);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create component-based app
    var app = try h3.createComponentApp(allocator);
    defer app.deinit();

    // Global middleware
    _ = try app.useFast(h3.fastMiddleware.logger);
    _ = try app.useFast(h3.fastMiddleware.cors);

    // Register chat component
    var chat = try ChatComponent.init(allocator);
    defer chat.deinit();
    try chat.configure(&app);

    std.log.info("💬 WebSocket Chat server starting on http://127.0.0.1:3000", .{});
    std.log.info("Default room: general", .{});

    try h3.serve(&app, .{ .port = 3000 });
}

fn chatUIHandler(event: *h3.Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>H3 WebSocket Chat</title>
        \\    <style>
        \\        * { box-sizing: border-box; }
        \\        body { font-family: Arial, sans-serif; margin: 0; padding: 0; background: #f0f0f0; }
        \\        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        \\        .chat-container { display: flex; gap: 20px; height: 600px; }
        \\        .rooms-panel { width: 250px; background: white; border-radius: 10px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        \\        .chat-panel { flex: 1; background: white; border-radius: 10px; display: flex; flex-direction: column; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        \\        .chat-header { padding: 20px; border-bottom: 1px solid #e0e0e0; }
        \\        .messages { flex: 1; padding: 20px; overflow-y: auto; }
        \\        .message { margin: 10px 0; padding: 10px; background: #f5f5f5; border-radius: 5px; }
        \\        .message.own { background: #e3f2fd; text-align: right; }
        \\        .message-info { font-size: 12px; color: #666; margin-bottom: 5px; }
        \\        .input-area { padding: 20px; border-top: 1px solid #e0e0e0; display: flex; gap: 10px; }
        \\        .input-area input { flex: 1; padding: 10px; border: 1px solid #ddd; border-radius: 5px; }
        \\        .input-area button { padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer; }
        \\        .input-area button:hover { background: #0056b3; }
        \\        .room-item { padding: 10px; margin: 5px 0; background: #f5f5f5; border-radius: 5px; cursor: pointer; }
        \\        .room-item:hover { background: #e0e0e0; }
        \\        .room-item.active { background: #007bff; color: white; }
        \\        .connection-status { padding: 10px; text-align: center; font-size: 14px; }
        \\        .connected { color: #4caf50; }
        \\        .disconnected { color: #f44336; }
        \\        h1 { text-align: center; color: #333; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <div class="container">
        \\        <h1>💬 H3 WebSocket Chat</h1>
        \\        
        \\        <div class="chat-container">
        \\            <div class="rooms-panel">
        \\                <h3>Rooms</h3>
        \\                <div id="roomsList"></div>
        \\                <div style="margin-top: 20px;">
        \\                    <input type="text" id="newRoomName" placeholder="New room name" style="width: 100%; padding: 5px;">
        \\                    <button onclick="createRoom()" style="width: 100%; margin-top: 5px;">Create Room</button>
        \\                </div>
        \\            </div>
        \\            
        \\            <div class="chat-panel">
        \\                <div class="chat-header">
        \\                    <h2 id="currentRoom">general</h2>
        \\                    <div class="connection-status" id="connectionStatus">
        \\                        <span class="disconnected">● Disconnected</span>
        \\                    </div>
        \\                </div>
        \\                
        \\                <div class="messages" id="messages"></div>
        \\                
        \\                <div class="input-area">
        \\                    <input type="text" id="username" placeholder="Your name" style="width: 150px;">
        \\                    <input type="text" id="messageInput" placeholder="Type a message..." onkeypress="handleKeyPress(event)">
        \\                    <button onclick="sendMessage()">Send</button>
        \\                </div>
        \\            </div>
        \\        </div>
        \\    </div>
        \\    
        \\    <script>
        \\        let ws = null;
        \\        let currentRoom = 'general';
        \\        let username = 'User' + Math.floor(Math.random() * 1000);
        \\        
        \\        document.getElementById('username').value = username;
        \\        
        \\        function connectToRoom(room) {
        \\            if (ws) {
        \\                ws.close();
        \\            }
        \\            
        \\            currentRoom = room;
        \\            document.getElementById('currentRoom').textContent = room;
        \\            document.getElementById('messages').innerHTML = '';
        \\            
        \\            // Update active room
        \\            document.querySelectorAll('.room-item').forEach(item => {
        \\                item.classList.remove('active');
        \\                if (item.dataset.room === room) {
        \\                    item.classList.add('active');
        \\                }
        \\            });
        \\            
        \\            // Simulate WebSocket connection
        \\            updateConnectionStatus(true);
        \\            
        \\            // Load messages
        \\            loadMessages(room);
        \\        }
        \\        
        \\        function updateConnectionStatus(connected) {
        \\            const status = document.getElementById('connectionStatus');
        \\            if (connected) {
        \\                status.innerHTML = '<span class="connected">● Connected</span>';
        \\            } else {
        \\                status.innerHTML = '<span class="disconnected">● Disconnected</span>';
        \\            }
        \\        }
        \\        
        \\        async function loadRooms() {
        \\            try {
        \\                const response = await fetch('/api/rooms');
        \\                const rooms = await response.json();
        \\                
        \\                const roomsList = document.getElementById('roomsList');
        \\                roomsList.innerHTML = '';
        \\                
        \\                rooms.forEach(room => {
        \\                    const item = document.createElement('div');
        \\                    item.className = 'room-item';
        \\                    item.dataset.room = room.name;
        \\                    item.innerHTML = `
        \\                        <strong>${room.name}</strong><br>
        \\                        <small>${room.users} users, ${room.messages} messages</small>
        \\                    `;
        \\                    item.onclick = () => connectToRoom(room.name);
        \\                    roomsList.appendChild(item);
        \\                });
        \\                
        \\                // Connect to default room
        \\                connectToRoom(currentRoom);
        \\            } catch (error) {
        \\                console.error('Failed to load rooms:', error);
        \\            }
        \\        }
        \\        
        \\        async function loadMessages(room) {
        \\            try {
        \\                const response = await fetch(`/api/rooms/${room}/messages`);
        \\                const messages = await response.json();
        \\                
        \\                const messagesDiv = document.getElementById('messages');
        \\                messagesDiv.innerHTML = '';
        \\                
        \\                messages.forEach(msg => {
        \\                    addMessageToUI(msg.user, msg.text, new Date(msg.timestamp * 1000));
        \\                });
        \\            } catch (error) {
        \\                console.error('Failed to load messages:', error);
        \\            }
        \\        }
        \\        
        \\        function addMessageToUI(user, text, timestamp) {
        \\            const messagesDiv = document.getElementById('messages');
        \\            const messageDiv = document.createElement('div');
        \\            messageDiv.className = 'message' + (user === username ? ' own' : '');
        \\            
        \\            const time = timestamp.toLocaleTimeString();
        \\            messageDiv.innerHTML = `
        \\                <div class="message-info">${user} • ${time}</div>
        \\                <div>${text}</div>
        \\            `;
        \\            
        \\            messagesDiv.appendChild(messageDiv);
        \\            messagesDiv.scrollTop = messagesDiv.scrollHeight;
        \\        }
        \\        
        \\        async function sendMessage() {
        \\            const input = document.getElementById('messageInput');
        \\            const text = input.value.trim();
        \\            
        \\            if (!text) return;
        \\            
        \\            username = document.getElementById('username').value || username;
        \\            
        \\            try {
        \\                const response = await fetch(`/api/rooms/${currentRoom}/messages`, {
        \\                    method: 'POST',
        \\                    headers: { 'Content-Type': 'application/json' },
        \\                    body: JSON.stringify({ user: username, text: text })
        \\                });
        \\                
        \\                if (response.ok) {
        \\                    input.value = '';
        \\                    addMessageToUI(username, text, new Date());
        \\                }
        \\            } catch (error) {
        \\                console.error('Failed to send message:', error);
        \\            }
        \\        }
        \\        
        \\        async function createRoom() {
        \\            const input = document.getElementById('newRoomName');
        \\            const name = input.value.trim();
        \\            
        \\            if (!name) return;
        \\            
        \\            try {
        \\                const response = await fetch('/api/rooms', {
        \\                    method: 'POST',
        \\                    headers: { 'Content-Type': 'application/json' },
        \\                    body: JSON.stringify({ name: name })
        \\                });
        \\                
        \\                if (response.ok) {
        \\                    input.value = '';
        \\                    loadRooms();
        \\                }
        \\            } catch (error) {
        \\                console.error('Failed to create room:', error);
        \\            }
        \\        }
        \\        
        \\        function handleKeyPress(event) {
        \\            if (event.key === 'Enter') {
        \\                sendMessage();
        \\            }
        \\        }
        \\        
        \\        // Initialize
        \\        loadRooms();
        \\        
        \\        // Simulate real-time updates
        \\        setInterval(() => {
        \\            if (currentRoom) {
        \\                loadMessages(currentRoom);
        \\            }
        \\        }, 5000);
        \\    </script>
        \\</body>
        \\</html>
    ;

    try h3.sendHtml(event, html);
}