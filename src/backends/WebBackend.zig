const std = @import("std");
const dvui = @import("dvui");

const WebBackend = @This();

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var arena: std.mem.Allocator = undefined;
cursor_last: dvui.enums.Cursor = .wait,
touchPoints: [10]?dvui.Point = [_]?dvui.Point{null} ** 10,
last_touch_enum: dvui.enums.Button = .none,

const EventTemp = struct {
    kind: u8,
    int1: u32,
    int2: u32,
    float1: f32,
    float2: f32,
};

pub var event_temps = std.ArrayList(EventTemp).init(gpa);

pub const wasm = struct {
    pub extern fn wasm_panic(ptr: [*]const u8, len: usize) void;
    pub extern fn wasm_log_write(ptr: [*]const u8, len: usize) void;
    pub extern fn wasm_log_flush() void;

    pub extern fn wasm_now() f64;
    pub extern fn wasm_sleep(ms: u32) void;

    pub extern fn wasm_pixel_width() f32;
    pub extern fn wasm_pixel_height() f32;
    pub extern fn wasm_canvas_width() f32;
    pub extern fn wasm_canvas_height() f32;

    pub extern fn wasm_clear() void;
    pub extern fn wasm_textureCreate(pixels: [*]u8, width: u32, height: u32) u32;
    pub extern fn wasm_textureDestroy(u32) void;
    pub extern fn wasm_renderGeometry(texture: u32, index_ptr: [*]const u8, index_len: usize, vertex_ptr: [*]const u8, vertex_len: usize, sizeof_vertex: u8, offset_pos: u8, offset_col: u8, offset_uv: u8, x: u32, y: u32, w: u32, h: u32) void;
    pub extern fn wasm_cursor(name: [*]const u8, name_len: u32) void;
    pub extern fn wasm_on_screen_keyboard(x: f32, y: f32, w: f32, h: f32) void;
};

export const __stack_chk_guard: c_ulong = 0xBAAAAAAD;
export fn __stack_chk_fail() void {}

export fn dvui_c_alloc(size: usize) ?*anyopaque {
    //std.log.debug("dvui_c_alloc {d}", .{size});
    const buffer = gpa.alignedAlloc(u8, 16, size + 16) catch {
        //std.log.debug("dvui_c_alloc {d} failed", .{size});
        return null;
    };
    std.mem.writeIntNative(usize, buffer[0..@sizeOf(usize)], buffer.len);
    return buffer.ptr + 16;
}

export fn dvui_c_free(ptr: ?*anyopaque) void {
    const buffer = @as([*]align(16) u8, @alignCast(@ptrCast(ptr orelse return))) - 16;
    const len = std.mem.readIntNative(usize, buffer[0..@sizeOf(usize)]);
    //std.log.debug("dvui_c_free {d}", .{len - 16});

    gpa.free(buffer[0..len]);
}

export fn dvui_c_realloc_sized(ptr: ?*anyopaque, oldsize: usize, newsize: usize) ?*anyopaque {
    _ = oldsize;
    //std.log.debug("dvui_c_realloc_sized {d} {d}", .{ oldsize, newsize });

    if (ptr == null) {
        return dvui_c_alloc(newsize);
    }

    const buffer = @as([*]u8, @ptrCast(ptr.?)) - 16;
    const len = std.mem.readIntNative(usize, buffer[0..@sizeOf(usize)]);

    var slice = buffer[0..len];
    _ = gpa.resize(slice, newsize + 16);

    std.mem.writeIntNative(usize, slice[0..@sizeOf(usize)], slice.len);
    return slice.ptr + 16;
}

export fn dvui_c_panic(msg: [*c]const u8) noreturn {
    wasm.wasm_panic(msg, std.mem.len(msg));
    unreachable;
}

export fn dvui_c_pow(x: f64, y: f64) f64 {
    return @exp(@log(x) * y);
}

export fn dvui_c_ldexp(x: f64, n: c_int) f64 {
    return x * @exp2(@as(f64, @floatFromInt(n)));
}

export fn arena_u8(len: usize) [*c]u8 {
    var buf = arena.alloc(u8, len) catch return @ptrFromInt(0);
    return buf.ptr;
}

export fn add_event(kind: u8, int1: u32, int2: u32, float1: f32, float2: f32) void {
    event_temps.append(.{
        .kind = kind,
        .int1 = int1,
        .int2 = int2,
        .float1 = float1,
        .float2 = float2,
    }) catch |err| {
        var msg = std.fmt.allocPrint(gpa, "{!}", .{err}) catch "allocPrint OOM";
        wasm.wasm_panic(msg.ptr, msg.len);
    };
}

pub fn hasEvent(_: *WebBackend) bool {
    return event_temps.items.len > 0;
}

fn buttonFromJS(jsButton: u32) dvui.enums.Button {
    return switch (jsButton) {
        0 => .left,
        1 => .middle,
        2 => .right,
        3 => .four,
        4 => .five,
        else => .six,
    };
}

fn hashKeyCode(str: []const u8) u32 {
    var fnv = std.hash.Fnv1a_32.init();
    fnv.update(str);
    return fnv.final();
}

fn web_key_code_to_dvui(code: []u8) dvui.enums.Key {
    @setEvalBranchQuota(2000);
    var fnv = std.hash.Fnv1a_32.init();
    fnv.update(code);
    return switch (fnv.final()) {
        hashKeyCode("KeyA") => .a,
        hashKeyCode("KeyB") => .b,
        hashKeyCode("KeyC") => .c,
        hashKeyCode("KeyD") => .d,
        hashKeyCode("KeyE") => .e,
        hashKeyCode("KeyF") => .f,
        hashKeyCode("KeyG") => .g,
        hashKeyCode("KeyH") => .h,
        hashKeyCode("KeyI") => .i,
        hashKeyCode("KeyJ") => .j,
        hashKeyCode("KeyK") => .k,
        hashKeyCode("KeyL") => .l,
        hashKeyCode("KeyM") => .m,
        hashKeyCode("KeyN") => .n,
        hashKeyCode("KeyO") => .o,
        hashKeyCode("KeyP") => .p,
        hashKeyCode("KeyQ") => .q,
        hashKeyCode("KeyR") => .r,
        hashKeyCode("KeyS") => .s,
        hashKeyCode("KeyT") => .t,
        hashKeyCode("KeyU") => .u,
        hashKeyCode("KeyV") => .v,
        hashKeyCode("KeyW") => .w,
        hashKeyCode("KeyX") => .x,
        hashKeyCode("KeyY") => .y,
        hashKeyCode("KeyZ") => .z,

        hashKeyCode("Digit0") => .zero,
        hashKeyCode("Digit1") => .one,
        hashKeyCode("Digit2") => .two,
        hashKeyCode("Digit3") => .three,
        hashKeyCode("Digit4") => .four,
        hashKeyCode("Digit5") => .five,
        hashKeyCode("Digit6") => .six,
        hashKeyCode("Digit7") => .seven,
        hashKeyCode("Digit8") => .eight,
        hashKeyCode("Digit9") => .nine,

        hashKeyCode("F1") => .f1,
        hashKeyCode("F2") => .f2,
        hashKeyCode("F3") => .f3,
        hashKeyCode("F4") => .f4,
        hashKeyCode("F5") => .f5,
        hashKeyCode("F6") => .f6,
        hashKeyCode("F7") => .f7,
        hashKeyCode("F8") => .f8,
        hashKeyCode("F9") => .f9,
        hashKeyCode("F10") => .f10,
        hashKeyCode("F11") => .f11,
        hashKeyCode("F12") => .f12,

        hashKeyCode("NumpadDivide") => .kp_divide,
        hashKeyCode("NumpadMultiply") => .kp_multiply,
        hashKeyCode("NumpadSubtract") => .kp_subtract,
        hashKeyCode("NumpadAdd") => .kp_add,
        hashKeyCode("NumpadEnter") => .kp_enter,
        hashKeyCode("Numpad0") => .kp_0,
        hashKeyCode("Numpad1") => .kp_1,
        hashKeyCode("Numpad2") => .kp_2,
        hashKeyCode("Numpad3") => .kp_3,
        hashKeyCode("Numpad4") => .kp_4,
        hashKeyCode("Numpad5") => .kp_5,
        hashKeyCode("Numpad6") => .kp_6,
        hashKeyCode("Numpad7") => .kp_7,
        hashKeyCode("Numpad8") => .kp_8,
        hashKeyCode("Numpad9") => .kp_9,
        hashKeyCode("NumpadDecimal") => .kp_decimal,

        hashKeyCode("Enter") => .enter,
        hashKeyCode("Escape") => .escape,
        hashKeyCode("Tab") => .tab,
        hashKeyCode("ShiftLeft") => .left_shift,
        hashKeyCode("ShiftRight") => .right_shift,
        hashKeyCode("ControlLeft") => .left_control,
        hashKeyCode("ControlRight") => .right_control,
        hashKeyCode("AltLeft") => .left_alt,
        hashKeyCode("AltRight") => .right_alt,
        hashKeyCode("MetaLeft") => .left_command, // is this correct?
        hashKeyCode("MetaRight") => .right_command, // is this correct?
        hashKeyCode("ContextMenu") => .menu, // is this correct?
        hashKeyCode("NumLock") => .num_lock,
        hashKeyCode("CapsLock") => .caps_lock,
        //c.SDLK_PRINTSCREEN => .print,  // can we get this?
        hashKeyCode("ScrollLock") => .scroll_lock,
        hashKeyCode("Pause") => .pause,

        hashKeyCode("Delete") => .delete,
        hashKeyCode("Home") => .home,
        hashKeyCode("End") => .end,
        hashKeyCode("PageUp") => .page_up,
        hashKeyCode("PageDown") => .page_down,
        hashKeyCode("Insert") => .insert,
        hashKeyCode("ArrowLeft") => .left,
        hashKeyCode("ArrowRight") => .right,
        hashKeyCode("ArrowUp") => .up,
        hashKeyCode("ArrowDown") => .down,
        hashKeyCode("Backspace") => .backspace,
        hashKeyCode("Space") => .space,
        hashKeyCode("Minus") => .minus,
        hashKeyCode("Equal") => .equal,
        hashKeyCode("BracketLeft") => .left_bracket,
        hashKeyCode("BracketRight") => .right_bracket,
        hashKeyCode("Backslash") => .backslash,
        hashKeyCode("Semicolon") => .semicolon,
        hashKeyCode("Quote") => .apostrophe,
        hashKeyCode("Comma") => .comma,
        hashKeyCode("Period") => .period,
        hashKeyCode("Slash") => .slash,
        hashKeyCode("Backquote") => .grave,

        else => blk: {
            dvui.log.debug("web_key_code_to_dvui unknown key code {s}\n", .{code});
            break :blk .unknown;
        },
    };
}

fn web_mod_code_to_dvui(wmod: u8) dvui.enums.Mod {
    if (wmod == 0) return .none;

    var m: u16 = 0;
    if (wmod & 0b0001 > 0) m |= @intFromEnum(dvui.enums.Mod.lshift);
    if (wmod & 0b0010 > 0) m |= @intFromEnum(dvui.enums.Mod.lcontrol);
    if (wmod & 0b0100 > 0) m |= @intFromEnum(dvui.enums.Mod.lalt);
    if (wmod & 0b1000 > 0) m |= @intFromEnum(dvui.enums.Mod.lcommand);

    return @as(dvui.enums.Mod, @enumFromInt(m));
}

pub fn addAllEvents(self: *WebBackend, win: *dvui.Window) !void {
    for (event_temps.items) |e| {
        switch (e.kind) {
            1 => _ = try win.addEventMouseMotion(e.float1, e.float2),
            2 => _ = try win.addEventMouseButton(buttonFromJS(e.int1), .press),
            3 => _ = try win.addEventMouseButton(buttonFromJS(e.int1), .release),
            4 => _ = try win.addEventMouseWheel(if (e.float1 > 0) -20 else 20),
            5 => {
                const str = @as([*]u8, @ptrFromInt(e.int1))[0..e.int2];
                _ = try win.addEventKey(.{
                    .action = if (e.float1 > 0) .repeat else .down,
                    .code = web_key_code_to_dvui(str),
                    .mod = web_mod_code_to_dvui(@intFromFloat(e.float2)),
                });
            },
            6 => {
                const str = @as([*]u8, @ptrFromInt(e.int1))[0..e.int2];
                _ = try win.addEventKey(.{
                    .action = .up,
                    .code = web_key_code_to_dvui(str),
                    .mod = web_mod_code_to_dvui(@intFromFloat(e.float2)),
                });
            },
            7 => {
                const str = @as([*]u8, @ptrFromInt(e.int1))[0..e.int2];
                _ = try win.addEventText(str);
            },
            8 => {
                const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + e.int1);
                self.last_touch_enum = touch;
                _ = try win.addEventPointer(touch, .press, .{ .x = e.float1, .y = e.float2 });
                self.touchPoints[e.int1] = .{ .x = e.float1, .y = e.float2 };
            },
            9 => {
                const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + e.int1);
                self.last_touch_enum = touch;
                _ = try win.addEventPointer(touch, .release, .{ .x = e.float1, .y = e.float2 });
                self.touchPoints[e.int1] = null;
            },
            10 => {
                const touch: dvui.enums.Button = @enumFromInt(@intFromEnum(dvui.enums.Button.touch0) + e.int1);
                self.last_touch_enum = touch;
                var dx: f32 = 0;
                var dy: f32 = 0;
                if (self.touchPoints[e.int1]) |p| {
                    dx = e.float1 - p.x;
                    dy = e.float2 - p.y;
                }
                _ = try win.addEventTouchMotion(touch, e.float1, e.float2, dx, dy);
            },
            else => dvui.log.debug("addAllEvents unknown event kind {d}", .{e.kind}),
        }
    }

    event_temps.clearRetainingCapacity();
}

pub fn init() !WebBackend {
    var back: WebBackend = .{};
    return back;
}

pub fn deinit(self: *WebBackend) void {
    _ = self;
}

pub fn clear(self: *WebBackend) void {
    _ = self;
    wasm.wasm_clear();
}

pub fn backend(self: *WebBackend) dvui.Backend {
    return dvui.Backend.init(self, nanoTime, sleep, begin, end, pixelSize, windowSize, contentScale, renderGeometry, textureCreate, textureDestroy, showKeyboard, clipboardText, clipboardTextSet, openURL, refresh);
}

pub fn nanoTime(self: *WebBackend) i128 {
    _ = self;
    return @as(i128, @intFromFloat(wasm.wasm_now())) * 1_000_000;
}

pub fn sleep(self: *WebBackend, ns: u64) void {
    _ = self;
    wasm.wasm_sleep(@intCast(@divTrunc(ns, 1_000_000)));
}

pub fn begin(self: *WebBackend, arena_in: std.mem.Allocator) void {
    _ = self;
    arena = arena_in;
}

pub fn end(_: *WebBackend) void {}

pub fn pixelSize(_: *WebBackend) dvui.Size {
    return dvui.Size{ .w = wasm.wasm_pixel_width(), .h = wasm.wasm_pixel_height() };
}

pub fn windowSize(_: *WebBackend) dvui.Size {
    return dvui.Size{ .w = wasm.wasm_canvas_width(), .h = wasm.wasm_canvas_height() };
}

pub fn contentScale(_: *WebBackend) f32 {
    return 1.0;
}

pub fn renderGeometry(_: *WebBackend, texture: ?*anyopaque, vtx: []const dvui.Vertex, idx: []const u32) void {
    const clipr = dvui.windowRectPixels().intersect(dvui.clipGet());
    if (clipr.empty()) {
        return;
    }

    // figure out how much we are losing by truncating x and y, need to add that back to w and h
    const x: u32 = @intFromFloat(clipr.x);
    const w: u32 = @intFromFloat(@ceil(clipr.w + clipr.x - @floor(clipr.x)));

    // y needs to be converted to 0 at bottom first
    const ry: f32 = wasm.wasm_pixel_height() - clipr.y - clipr.h;
    const y: u32 = @intFromFloat(ry);
    const h: u32 = @intFromFloat(@ceil(clipr.h + ry - @floor(ry)));

    //dvui.log.debug("renderGeometry pixels {} clipr {} ry {d} clip {d} {d} {d} {d}", .{ dvui.windowRectPixels(), clipr, ry, x, y, w, h });

    var index_slice = std.mem.sliceAsBytes(idx);
    var vertex_slice = std.mem.sliceAsBytes(vtx);

    wasm.wasm_renderGeometry(
        if (texture) |t| @as(u32, @intFromPtr(t)) else 0,
        index_slice.ptr,
        index_slice.len,
        vertex_slice.ptr,
        vertex_slice.len,
        @sizeOf(dvui.Vertex),
        @offsetOf(dvui.Vertex, "pos"),
        @offsetOf(dvui.Vertex, "col"),
        @offsetOf(dvui.Vertex, "uv"),
        x,
        y,
        w,
        h,
    );
}

pub fn textureCreate(self: *WebBackend, pixels: [*]u8, width: u32, height: u32) *anyopaque {
    _ = self;

    // convert to premultiplied alpha
    for (0..height) |h| {
        for (0..width) |w| {
            const i = (h * width + w) * 4;
            const a: u16 = pixels[i + 3];
            pixels[i] = @intCast(@divTrunc(@as(u16, pixels[i]) * a, 255));
            pixels[i + 1] = @intCast(@divTrunc(@as(u16, pixels[i + 1]) * a, 255));
            pixels[i + 2] = @intCast(@divTrunc(@as(u16, pixels[i + 2]) * a, 255));
        }
    }

    const id = wasm.wasm_textureCreate(pixels, width, height);
    return @ptrFromInt(id);
}

pub fn textureDestroy(_: *WebBackend, texture: *anyopaque) void {
    wasm.wasm_textureDestroy(@as(u32, @intFromPtr(texture)));
}

pub fn showKeyboard(_: *WebBackend, rect: ?dvui.Rect) void {
    if (rect) |_| {
        wasm.wasm_on_screen_keyboard(0, 0, 1, 1);
    } else {
        wasm.wasm_on_screen_keyboard(0, 0, 0, 0);
    }
}

pub fn clipboardText(self: *WebBackend) error{OutOfMemory}![]u8 {
    _ = self;
    var buf: [10]u8 = [_]u8{0} ** 10;
    @memcpy(buf[0..9], "clipboard");
    return &buf;
}

pub fn clipboardTextSet(self: *WebBackend, text: []const u8) !void {
    _ = self;
    _ = text;
    return;
}

pub fn openURL(self: *WebBackend, url: []const u8) !void {
    _ = self;
    _ = url;
}

pub fn refresh(self: *WebBackend) void {
    _ = self;
}

pub fn setCursor(self: *WebBackend, cursor: dvui.enums.Cursor) void {
    if (cursor != self.cursor_last) {
        self.cursor_last = cursor;

        const name: []const u8 = switch (cursor) {
            .arrow => "default",
            .ibeam => "text",
            .wait => "wait",
            .wait_arrow => "progress",
            .crosshair => "crosshair",
            .arrow_nw_se => "nwse-resize",
            .arrow_ne_sw => "nesw-resize",
            .arrow_w_e => "ew-resize",
            .arrow_n_s => "ns-resize",
            .arrow_all => "move",
            .bad => "not-allowed",
            .hand => "pointer",
        };
        wasm.wasm_cursor(name.ptr, name.len);
    }
}
