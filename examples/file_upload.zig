//! File Upload Example
//! Demonstrates multipart form data handling, file uploads, and streaming

const std = @import("std");
const h3 = @import("h3");

const FileInfo = struct {
    id: []const u8,
    filename: []const u8,
    size: usize,
    mime_type: []const u8,
    uploaded_at: i64,
};

var uploads: std.ArrayList(FileInfo) = undefined;
var upload_dir: []const u8 = "uploads";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize uploads list
    uploads = std.ArrayList(FileInfo).init(allocator);
    defer uploads.deinit();

    // Create uploads directory
    std.fs.cwd().makeDir(upload_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Create app with custom config for file uploads
    const config = h3.ConfigBuilder.init()
        .setMaxRequestSize(50 * 1024 * 1024) // 50MB max upload
        .setUseEventPool(true)
        .setUseFastMiddleware(true)
        .build();

    var app = try h3.createAppWithConfig(allocator, config);
    defer app.deinit();

    // Middleware
    _ = app.useFast(h3.fastMiddleware.logger);
    _ = app.useFast(h3.fastMiddleware.cors);
    _ = app.use(uploadMiddleware);

    // Routes
    _ = app.get("/", uploadFormHandler);
    _ = app.post("/upload", uploadHandler);
    _ = app.get("/uploads", listUploadsHandler);
    _ = app.get("/download/:id", downloadHandler);
    _ = app.delete("/upload/:id", deleteUploadHandler);
    _ = app.post("/upload/chunked", chunkedUploadHandler);
    _ = app.get("/stream/:id", streamFileHandler);

    std.log.info("📁 File Upload server starting on http://127.0.0.1:3000", .{});
    std.log.info("Max upload size: 50MB", .{});

    try h3.serve(&app, .{ .port = 3000 });
}

fn uploadFormHandler(event: *h3.Event) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>H3 File Upload</title>
        \\    <style>
        \\        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        \\        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        \\        .upload-area { border: 2px dashed #007bff; border-radius: 5px; padding: 40px; text-align: center; margin: 20px 0; background: #f8f9fa; }
        \\        .upload-area.dragover { background: #e3f2fd; border-color: #2196f3; }
        \\        input[type="file"] { margin: 20px 0; }
        \\        button { background: #007bff; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; font-size: 16px; }
        \\        button:hover { background: #0056b3; }
        \\        .file-list { margin-top: 30px; }
        \\        .file-item { background: #f8f9fa; padding: 15px; margin: 10px 0; border-radius: 5px; display: flex; justify-content: space-between; align-items: center; }
        \\        .progress { width: 100%; height: 20px; background: #e0e0e0; border-radius: 10px; margin: 10px 0; overflow: hidden; }
        \\        .progress-bar { height: 100%; background: #4caf50; transition: width 0.3s; }
        \\        .error { color: #f44336; margin: 10px 0; }
        \\        .success { color: #4caf50; margin: 10px 0; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <div class="container">
        \\        <h1>📁 H3 File Upload</h1>
        \\        
        \\        <div class="upload-area" id="uploadArea">
        \\            <p>Drag and drop files here or click to browse</p>
        \\            <input type="file" id="fileInput" multiple />
        \\            <button onclick="uploadFiles()">Upload Files</button>
        \\        </div>
        \\        
        \\        <div class="progress" id="progressContainer" style="display: none;">
        \\            <div class="progress-bar" id="progressBar"></div>
        \\        </div>
        \\        
        \\        <div id="message"></div>
        \\        
        \\        <div class="file-list">
        \\            <h2>Uploaded Files</h2>
        \\            <div id="fileList"></div>
        \\        </div>
        \\        
        \\        <h3>Features:</h3>
        \\        <ul>
        \\            <li>Drag & drop support</li>
        \\            <li>Multiple file upload</li>
        \\            <li>Progress tracking</li>
        \\            <li>File download</li>
        \\            <li>File streaming</li>
        \\            <li>Chunked upload support</li>
        \\        </ul>
        \\    </div>
        \\    
        \\    <script>
        \\        const uploadArea = document.getElementById('uploadArea');
        \\        const fileInput = document.getElementById('fileInput');
        \\        const progressContainer = document.getElementById('progressContainer');
        \\        const progressBar = document.getElementById('progressBar');
        \\        const message = document.getElementById('message');
        \\        
        \\        // Drag and drop
        \\        uploadArea.addEventListener('dragover', (e) => {
        \\            e.preventDefault();
        \\            uploadArea.classList.add('dragover');
        \\        });
        \\        
        \\        uploadArea.addEventListener('dragleave', () => {
        \\            uploadArea.classList.remove('dragover');
        \\        });
        \\        
        \\        uploadArea.addEventListener('drop', (e) => {
        \\            e.preventDefault();
        \\            uploadArea.classList.remove('dragover');
        \\            fileInput.files = e.dataTransfer.files;
        \\        });
        \\        
        \\        uploadArea.addEventListener('click', () => {
        \\            fileInput.click();
        \\        });
        \\        
        \\        async function uploadFiles() {
        \\            const files = fileInput.files;
        \\            if (!files.length) {
        \\                showMessage('Please select files to upload', 'error');
        \\                return;
        \\            }
        \\            
        \\            progressContainer.style.display = 'block';
        \\            
        \\            for (let i = 0; i < files.length; i++) {
        \\                const file = files[i];
        \\                const formData = new FormData();
        \\                formData.append('file', file);
        \\                
        \\                try {
        \\                    const xhr = new XMLHttpRequest();
        \\                    
        \\                    xhr.upload.addEventListener('progress', (e) => {
        \\                        if (e.lengthComputable) {
        \\                            const percentComplete = (e.loaded / e.total) * 100;
        \\                            progressBar.style.width = percentComplete + '%';
        \\                        }
        \\                    });
        \\                    
        \\                    xhr.onload = function() {
        \\                        if (xhr.status === 200) {
        \\                            showMessage(`Uploaded ${file.name} successfully`, 'success');
        \\                            loadFileList();
        \\                        } else {
        \\                            showMessage(`Failed to upload ${file.name}`, 'error');
        \\                        }
        \\                    };
        \\                    
        \\                    xhr.open('POST', '/upload');
        \\                    xhr.send(formData);
        \\                } catch (error) {
        \\                    showMessage(`Error uploading ${file.name}: ${error}`, 'error');
        \\                }
        \\            }
        \\            
        \\            fileInput.value = '';
        \\            setTimeout(() => {
        \\                progressContainer.style.display = 'none';
        \\                progressBar.style.width = '0%';
        \\            }, 1000);
        \\        }
        \\        
        \\        function showMessage(text, type) {
        \\            message.className = type;
        \\            message.textContent = text;
        \\            setTimeout(() => {
        \\                message.textContent = '';
        \\            }, 3000);
        \\        }
        \\        
        \\        async function loadFileList() {
        \\            try {
        \\                const response = await fetch('/uploads');
        \\                const files = await response.json();
        \\                
        \\                const fileList = document.getElementById('fileList');
        \\                fileList.innerHTML = '';
        \\                
        \\                files.forEach(file => {
        \\                    const item = document.createElement('div');
        \\                    item.className = 'file-item';
        \\                    item.innerHTML = `
        \\                        <div>
        \\                            <strong>${file.filename}</strong><br>
        \\                            <small>${formatBytes(file.size)} - ${file.mime_type}</small>
        \\                        </div>
        \\                        <div>
        \\                            <button onclick="downloadFile('${file.id}')">Download</button>
        \\                            <button onclick="streamFile('${file.id}')">Stream</button>
        \\                            <button onclick="deleteFile('${file.id}')">Delete</button>
        \\                        </div>
        \\                    `;
        \\                    fileList.appendChild(item);
        \\                });
        \\            } catch (error) {
        \\                console.error('Failed to load file list:', error);
        \\            }
        \\        }
        \\        
        \\        function formatBytes(bytes) {
        \\            if (bytes === 0) return '0 Bytes';
        \\            const k = 1024;
        \\            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        \\            const i = Math.floor(Math.log(bytes) / Math.log(k));
        \\            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        \\        }
        \\        
        \\        function downloadFile(id) {
        \\            window.location.href = `/download/${id}`;
        \\        }
        \\        
        \\        function streamFile(id) {
        \\            window.open(`/stream/${id}`, '_blank');
        \\        }
        \\        
        \\        async function deleteFile(id) {
        \\            if (!confirm('Are you sure you want to delete this file?')) return;
        \\            
        \\            try {
        \\                const response = await fetch(`/upload/${id}`, { method: 'DELETE' });
        \\                if (response.ok) {
        \\                    showMessage('File deleted successfully', 'success');
        \\                    loadFileList();
        \\                }
        \\            } catch (error) {
        \\                showMessage('Failed to delete file', 'error');
        \\            }
        \\        }
        \\        
        \\        // Load file list on page load
        \\        loadFileList();
        \\    </script>
        \\</body>
        \\</html>
    ;

    try h3.sendHtml(event, html);
}

fn uploadMiddleware(ctx: *h3.MiddlewareContext, next: h3.Handler) !void {
    const content_type = h3.getHeader(ctx.event, "Content-Type") orelse {
        try next(ctx.event);
        return;
    };

    // Check if it's multipart form data
    if (std.mem.startsWith(u8, content_type, "multipart/form-data")) {
        // Parse multipart data would happen here
        // For this example, we'll use a simplified approach
    }

    try next(ctx.event);
}

fn uploadHandler(event: *h3.Event) !void {
    // In a real implementation, you would parse multipart form data
    // For this example, we'll simulate file upload
    
    const body = h3.readBody(event) orelse {
        try h3.response.badRequest(event, "No file data");
        return;
    };

    // Generate unique ID
    const id = try std.fmt.allocPrint(
        event.allocator,
        "{d}_{d}",
        .{ std.time.timestamp(), std.crypto.random.int(u32) }
    );

    // Simulate file info
    const file_info = FileInfo{
        .id = id,
        .filename = "uploaded_file.bin",
        .size = body.len,
        .mime_type = "application/octet-stream",
        .uploaded_at = std.time.timestamp(),
    };

    // Save file (simplified)
    const file_path = try std.fmt.allocPrint(
        event.allocator,
        "{s}/{s}",
        .{ upload_dir, id }
    );
    defer event.allocator.free(file_path);

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(body);

    // Store file info
    try uploads.append(file_info);

    const response = .{
        .success = true,
        .file = file_info,
    };

    try h3.sendJson(event, response);
}

fn listUploadsHandler(event: *h3.Event) !void {
    try h3.sendJson(event, uploads.items);
}

fn downloadHandler(event: *h3.Event) !void {
    const id = h3.getParam(event, "id") orelse return error.MissingParam;

    // Find file info
    var file_info: ?FileInfo = null;
    for (uploads.items) |info| {
        if (std.mem.eql(u8, info.id, id)) {
            file_info = info;
            break;
        }
    }

    const info = file_info orelse {
        try h3.response.notFound(event, "File not found");
        return;
    };

    // Read file
    const file_path = try std.fmt.allocPrint(
        event.allocator,
        "{s}/{s}",
        .{ upload_dir, id }
    );
    defer event.allocator.free(file_path);

    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        try h3.response.notFound(event, "File not found");
        return;
    };
    defer file.close();

    const content = try file.readToEndAlloc(event.allocator, info.size);
    defer event.allocator.free(content);

    // Set headers for download
    try h3.setHeader(event, "Content-Type", info.mime_type);
    try h3.setHeader(event, "Content-Disposition", 
        try std.fmt.allocPrint(event.allocator, "attachment; filename=\"{s}\"", .{info.filename})
    );
    try h3.setHeader(event, "Content-Length", 
        try std.fmt.allocPrint(event.allocator, "{d}", .{content.len})
    );

    try h3.sendText(event, content);
}

fn deleteUploadHandler(event: *h3.Event) !void {
    const id = h3.getParam(event, "id") orelse return error.MissingParam;

    // Find and remove file info
    var index: ?usize = null;
    for (uploads.items, 0..) |info, i| {
        if (std.mem.eql(u8, info.id, id)) {
            index = i;
            break;
        }
    }

    if (index) |i| {
        // Delete file
        const file_path = try std.fmt.allocPrint(
            event.allocator,
            "{s}/{s}",
            .{ upload_dir, id }
        );
        defer event.allocator.free(file_path);

        std.fs.cwd().deleteFile(file_path) catch {};

        _ = uploads.orderedRemove(i);
        try h3.response.noContent(event);
    } else {
        try h3.response.notFound(event, "File not found");
    }
}

fn chunkedUploadHandler(event: *h3.Event) !void {
    // Handle chunked upload
    const chunk_header = h3.getHeader(event, "X-Chunk-Index") orelse {
        try h3.response.badRequest(event, "Missing chunk index");
        return;
    };

    const total_chunks = h3.getHeader(event, "X-Total-Chunks") orelse {
        try h3.response.badRequest(event, "Missing total chunks");
        return;
    };

    const response = .{
        .success = true,
        .chunk = chunk_header,
        .total = total_chunks,
        .message = "Chunk received",
    };

    try h3.sendJson(event, response);
}

fn streamFileHandler(event: *h3.Event) !void {
    const id = h3.getParam(event, "id") orelse return error.MissingParam;

    // Find file info
    var file_info: ?FileInfo = null;
    for (uploads.items) |info| {
        if (std.mem.eql(u8, info.id, id)) {
            file_info = info;
            break;
        }
    }

    const info = file_info orelse {
        try h3.response.notFound(event, "File not found");
        return;
    };

    // Set streaming headers
    try h3.setHeader(event, "Content-Type", info.mime_type);
    try h3.setHeader(event, "Content-Length", 
        try std.fmt.allocPrint(event.allocator, "{d}", .{info.size})
    );
    try h3.setHeader(event, "Accept-Ranges", "bytes");

    // Check for range request
    const range_header = h3.getHeader(event, "Range");
    if (range_header) |range| {
        // Handle range request for video/audio streaming
        _ = range;
        h3.setStatus(event, .partial_content);
    }

    // Stream file content
    const file_path = try std.fmt.allocPrint(
        event.allocator,
        "{s}/{s}",
        .{ upload_dir, id }
    );
    defer event.allocator.free(file_path);

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(event.allocator, info.size);
    defer event.allocator.free(content);

    try h3.sendText(event, content);
}