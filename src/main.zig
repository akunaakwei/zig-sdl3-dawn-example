const sdl3 = @import("sdl3");
const webgpu = @import("webgpu");
const sdl3webgpu = @import("sdl3webgpu");

inline fn sv(data: []const u8) webgpu.WGPUStringView {
    return .{ .data = data.ptr, .length = data.len };
}

inline fn vs(view: webgpu.WGPUStringView) []const u8 {
    return view.data[0..view.length];
}

pub fn main() !void {
    if (!sdl3.SDL_Init(sdl3.SDL_INIT_VIDEO)) {
        return error.SDLInitFailed;
    }
    defer sdl3.SDL_Quit();

    const instance = instance: {
        const features = [_]webgpu.WGPUInstanceFeatureName{
            webgpu.WGPUInstanceFeatureName_TimedWaitAny,
        };
        const desc: webgpu.WGPUInstanceDescriptor = .{
            .requiredFeatureCount = features.len,
            .requiredFeatures = &features,
        };
        break :instance webgpu.wgpuCreateInstance(&desc);
    };

    const window_width = 800;
    const window_height = 600;
    const window = sdl3.SDL_CreateWindow("example", window_width, window_height, 0);
    defer sdl3.SDL_DestroyWindow(window);

    const surface = sdl3webgpu.SDL_GetWGPUSurface(instance, window);

    const adapter = adapter: {
        const options: webgpu.WGPURequestAdapterOptions = .{
            .compatibleSurface = surface,
        };
        var result: webgpu.WGPUAdapter = undefined;
        const info: webgpu.WGPURequestAdapterCallbackInfo = .{
            .mode = webgpu.WGPUCallbackMode_WaitAnyOnly,
            .callback = struct {
                pub fn cb(status: webgpu.WGPURequestAdapterStatus, adapter: webgpu.WGPUAdapter, msg: webgpu.WGPUStringView, user1: ?*anyopaque, user2: ?*anyopaque) callconv(.c) void {
                    _ = msg;
                    _ = user2;

                    if (status != webgpu.WGPURequestAdapterStatus_Success) {
                        sdl3.SDL_Log("Failed to create adapter");
                        return;
                    }
                    @as(*webgpu.WGPUAdapter, @ptrCast(@alignCast(user1))).* = adapter;
                }
            }.cb,
            .userdata1 = @ptrCast(&result),
        };
        const future = webgpu.wgpuInstanceRequestAdapter(instance, &options, info);
        var wait = [_]webgpu.WGPUFutureWaitInfo{
            .{ .future = future },
        };
        _ = webgpu.wgpuInstanceWaitAny(instance, wait.len, &wait, 0);

        var adapter_info: webgpu.WGPUAdapterInfo = .{};
        if (webgpu.wgpuAdapterGetInfo(result, &adapter_info) == webgpu.WGPUStatus_Success) {
            sdl3.SDL_Log("Device\t: %.*s", adapter_info.device.length, adapter_info.device.data);
            sdl3.SDL_Log("Vendor\t: %.*s", adapter_info.vendor.length, adapter_info.vendor.data);
        } else {
            sdl3.SDL_LogError(sdl3.SDL_LOG_CATEGORY_GPU, "could not get adapter info");
        }

        break :adapter result;
    };
    const capabilities = capabilities: {
        var result: webgpu.WGPUSurfaceCapabilities = undefined;
        if (webgpu.wgpuSurfaceGetCapabilities(surface, adapter, &result) != webgpu.WGPUStatus_Success) {
            sdl3.SDL_LogError(sdl3.SDL_LOG_CATEGORY_GPU, "could not get surface capabilities");
            return error.NoSurfaceCapabilities;
        }
        break :capabilities result;
    };

    const device = device: {
        const desc: webgpu.WGPUDeviceDescriptor = .{
            .uncapturedErrorCallbackInfo = .{
                .callback = struct {
                    pub fn cb(device: [*c]const webgpu.WGPUDevice, error_type: webgpu.WGPUErrorType, text: webgpu.WGPUStringView, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                        _ = device;
                        _ = error_type;
                        sdl3.SDL_Log("%.*s", text.length, text.data);
                    }
                }.cb,
            },
        };
        var result: webgpu.WGPUDevice = undefined;
        const info: webgpu.WGPURequestDeviceCallbackInfo = .{
            .mode = webgpu.WGPUCallbackMode_WaitAnyOnly,
            .callback = struct {
                pub fn cb(status: webgpu.WGPURequestDeviceStatus, device: webgpu.WGPUDevice, msg: webgpu.WGPUStringView, user1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                    _ = msg;

                    if (status != webgpu.WGPURequestDeviceStatus_Success) {
                        sdl3.SDL_Log("Failed to create device");
                        return;
                    }
                    @as(*webgpu.WGPUDevice, @ptrCast(@alignCast(user1))).* = device;
                }
            }.cb,
            .userdata1 = @ptrCast(&result),
        };
        const future = webgpu.wgpuAdapterRequestDevice(adapter, &desc, info);
        var wait = [_]webgpu.WGPUFutureWaitInfo{
            .{ .future = future },
        };
        _ = webgpu.wgpuInstanceWaitAny(instance, wait.len, &wait, 0);
        break :device result;
    };
    webgpu.wgpuSurfaceConfigure(surface, &.{
        .device = device,
        .format = capabilities.formats[0],
        .usage = webgpu.WGPUTextureUsage_RenderAttachment,
        .width = window_width,
        .height = window_height,
        .presentMode = capabilities.presentModes[0],
    });
    const preferred_texture_format = capabilities.formats[0];

    const queue = webgpu.wgpuDeviceGetQueue(device);

    const vertex_data = [_]f32{
        0.0, 0.5, 0.0, 1.0, -0.5, -0.5, 0.0, 1.0, 0.5, -0.5, 0.0, 1.0,
    };
    const vertex_buffer = buffer: {
        const desc: webgpu.WGPUBufferDescriptor = .{
            .size = @sizeOf(@TypeOf(vertex_data)),
            .usage = webgpu.WGPUBufferUsage_Vertex | webgpu.WGPUBufferUsage_CopyDst,
        };
        const result = webgpu.wgpuDeviceCreateBuffer(device, &desc);
        webgpu.wgpuQueueWriteBuffer(queue, result, 0, &vertex_data, @sizeOf(@TypeOf(vertex_data)));
        break :buffer result;
    };

    const shader_module = shader: {
        var source: webgpu.WGPUShaderSourceWGSL = .{
            .chain = .{ .sType = webgpu.WGPUSType_ShaderSourceWGSL },
            .code = sv(
                \\@vertex fn vs(@location(0) pos : vec4f) -> @builtin(position) vec4f {
                \\    return pos;
                \\}
                \\@fragment fn fs(@builtin(position) FragCoord : vec4f) -> @location(0) vec4f {
                \\    return vec4f(1, 0, 0, 1);
                \\}
            ),
        };
        const desc: webgpu.WGPUShaderModuleDescriptor = .{ .nextInChain = @ptrCast(&source) };
        const result = webgpu.wgpuDeviceCreateShaderModule(device, &desc);
        break :shader result;
    };

    const pipeline = pipeline: {
        const desc: webgpu.WGPURenderPipelineDescriptor = .{
            .vertex = .{
                .module = shader_module,
                .entryPoint = sv("vs"),
                .buffers = &[_]webgpu.WGPUVertexBufferLayout{.{
                    .arrayStride = 4 * @sizeOf(f32),
                    .attributes = &[_]webgpu.WGPUVertexAttribute{
                        .{ .format = webgpu.WGPUVertexFormat_Float32x4 },
                    },
                    .attributeCount = 1,
                }},
                .bufferCount = 1,
            },
            .fragment = &.{
                .module = shader_module,
                .entryPoint = sv("fs"),
                .targets = &[_]webgpu.WGPUColorTargetState{
                    .{
                        .format = preferred_texture_format,
                        .writeMask = webgpu.WGPUColorWriteMask_All,
                        .blend = &.{
                            .color = .{
                                .operation = webgpu.WGPUBlendOperation_Add,
                                .srcFactor = webgpu.WGPUBlendFactor_One,
                                .dstFactor = webgpu.WGPUBlendFactor_One,
                            },
                            .alpha = .{
                                .operation = webgpu.WGPUBlendOperation_Add,
                                .srcFactor = webgpu.WGPUBlendFactor_One,
                                .dstFactor = webgpu.WGPUBlendFactor_One,
                            },
                        },
                    },
                },
                .targetCount = 1,
            },
            .multisample = .{
                .count = 1,
                .mask = 0xFFFFFFFF,
                .alphaToCoverageEnabled = webgpu.WGPU_FALSE,
            },
        };
        const result = webgpu.wgpuDeviceCreateRenderPipeline(device, &desc);
        break :pipeline result;
    };
    defer webgpu.wgpuRenderPipelineRelease(pipeline);

    var quit = false;
    while (!quit) {
        var event: sdl3.SDL_Event = undefined;
        while (sdl3.SDL_PollEvent(&event)) {
            if (event.type == sdl3.SDL_EVENT_QUIT) {
                quit = true;
            }
        }
        const surface_texture = surface_texture: {
            var result: webgpu.WGPUSurfaceTexture = undefined;
            webgpu.wgpuSurfaceGetCurrentTexture(surface, &result);
            break :surface_texture result;
        };

        const view = view: {
            const desc: webgpu.WGPUTextureViewDescriptor = .{
                .mipLevelCount = webgpu.WGPU_MIP_LEVEL_COUNT_UNDEFINED,
                .arrayLayerCount = webgpu.WGPU_ARRAY_LAYER_COUNT_UNDEFINED,
            };
            const result = webgpu.wgpuTextureCreateView(surface_texture.texture, &desc);
            break :view result;
        };

        const encoder = encoder: {
            const desc: webgpu.WGPUCommandEncoderDescriptor = .{};
            const result = webgpu.wgpuDeviceCreateCommandEncoder(device, &desc);
            break :encoder result;
        };

        const pass = pass: {
            const colors = [_]webgpu.WGPURenderPassColorAttachment{
                .{
                    .view = view,
                    .loadOp = webgpu.WGPULoadOp_Clear,
                    .storeOp = webgpu.WGPUStoreOp_Store,
                    .clearValue = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                    .depthSlice = webgpu.WGPU_DEPTH_SLICE_UNDEFINED,
                },
            };

            const desc: webgpu.WGPURenderPassDescriptor = .{
                .colorAttachmentCount = colors.len,
                .colorAttachments = &colors,
            };
            const result = webgpu.wgpuCommandEncoderBeginRenderPass(encoder, &desc);
            break :pass result;
        };
        webgpu.wgpuRenderPassEncoderSetPipeline(pass, pipeline);
        webgpu.wgpuRenderPassEncoderSetVertexBuffer(pass, 0, vertex_buffer, 0, webgpu.WGPU_WHOLE_SIZE);
        webgpu.wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0);
        webgpu.wgpuRenderPassEncoderEnd(pass);

        const cmd_buffer = cmd_buffer: {
            const desc: webgpu.WGPUCommandBufferDescriptor = .{};
            const result = webgpu.wgpuCommandEncoderFinish(encoder, &desc);
            break :cmd_buffer result;
        };
        const cmds = [_]webgpu.WGPUCommandBuffer{cmd_buffer};
        webgpu.wgpuQueueSubmit(queue, cmds.len, &cmds);
        _ = webgpu.wgpuSurfacePresent(surface);
    }
}
