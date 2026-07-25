const c = @import("c");

inline fn sv(data: []const u8) c.WGPUStringView {
    return .{ .data = data.ptr, .length = data.len };
}

inline fn vs(view: c.WGPUStringView) []const u8 {
    return view.data[0..view.length];
}

pub fn main() !void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    const instance = instance: {
        const features = [_]c.WGPUInstanceFeatureName{
            c.WGPUInstanceFeatureName_TimedWaitAny,
        };
        const desc: c.WGPUInstanceDescriptor = .{
            .requiredFeatureCount = features.len,
            .requiredFeatures = &features,
        };
        break :instance c.wgpuCreateInstance(&desc);
    };

    const window_width = 800;
    const window_height = 600;
    const window = c.SDL_CreateWindow("example", window_width, window_height, 0);
    defer c.SDL_DestroyWindow(window);

    const surface = c.SDL_GetWGPUSurface(instance, window);

    const adapter = adapter: {
        const options: c.WGPURequestAdapterOptions = .{
            .compatibleSurface = surface,
        };
        var result: c.WGPUAdapter = undefined;
        const info: c.WGPURequestAdapterCallbackInfo = .{
            .mode = c.WGPUCallbackMode_WaitAnyOnly,
            .callback = struct {
                pub fn cb(status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, msg: c.WGPUStringView, user1: ?*anyopaque, user2: ?*anyopaque) callconv(.c) void {
                    _ = msg;
                    _ = user2;

                    if (status != c.WGPURequestAdapterStatus_Success) {
                        c.SDL_Log("Failed to create adapter");
                        return;
                    }
                    @as(*c.WGPUAdapter, @ptrCast(@alignCast(user1))).* = adapter;
                }
            }.cb,
            .userdata1 = @ptrCast(&result),
        };
        const future = c.wgpuInstanceRequestAdapter(instance, &options, info);
        var wait = [_]c.WGPUFutureWaitInfo{
            .{ .future = future },
        };
        _ = c.wgpuInstanceWaitAny(instance, wait.len, &wait, 0);

        var adapter_info: c.WGPUAdapterInfo = .{};
        if (c.wgpuAdapterGetInfo(result, &adapter_info) == c.WGPUStatus_Success) {
            c.SDL_Log("Device\t: %.*s", adapter_info.device.length, adapter_info.device.data);
            c.SDL_Log("Vendor\t: %.*s", adapter_info.vendor.length, adapter_info.vendor.data);
        } else {
            c.SDL_LogError(c.SDL_LOG_CATEGORY_GPU, "could not get adapter info");
        }

        break :adapter result;
    };
    const capabilities = capabilities: {
        var result: c.WGPUSurfaceCapabilities = undefined;
        if (c.wgpuSurfaceGetCapabilities(surface, adapter, &result) != c.WGPUStatus_Success) {
            c.SDL_LogError(c.SDL_LOG_CATEGORY_GPU, "could not get surface capabilities");
            return error.NoSurfaceCapabilities;
        }
        break :capabilities result;
    };

    const device = device: {
        const desc: c.WGPUDeviceDescriptor = .{
            .uncapturedErrorCallbackInfo = .{
                .callback = struct {
                    pub fn cb(device: [*c]const c.WGPUDevice, error_type: c.WGPUErrorType, text: c.WGPUStringView, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                        _ = device;
                        _ = error_type;
                        c.SDL_Log("%.*s", text.length, text.data);
                    }
                }.cb,
            },
        };
        var result: c.WGPUDevice = undefined;
        const info: c.WGPURequestDeviceCallbackInfo = .{
            .mode = c.WGPUCallbackMode_WaitAnyOnly,
            .callback = struct {
                pub fn cb(status: c.WGPURequestDeviceStatus, device: c.WGPUDevice, msg: c.WGPUStringView, user1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
                    _ = msg;

                    if (status != c.WGPURequestDeviceStatus_Success) {
                        c.SDL_Log("Failed to create device");
                        return;
                    }
                    @as(*c.WGPUDevice, @ptrCast(@alignCast(user1))).* = device;
                }
            }.cb,
            .userdata1 = @ptrCast(&result),
        };
        const future = c.wgpuAdapterRequestDevice(adapter, &desc, info);
        var wait = [_]c.WGPUFutureWaitInfo{
            .{ .future = future },
        };
        _ = c.wgpuInstanceWaitAny(instance, wait.len, &wait, 0);
        break :device result;
    };
    c.wgpuSurfaceConfigure(surface, &.{
        .device = device,
        .format = capabilities.formats[0],
        .usage = c.WGPUTextureUsage_RenderAttachment,
        .width = window_width,
        .height = window_height,
        .presentMode = capabilities.presentModes[0],
    });
    const preferred_texture_format = capabilities.formats[0];

    const queue = c.wgpuDeviceGetQueue(device);

    const vertex_data = [_]f32{
        0.0, 0.5, 0.0, 1.0, -0.5, -0.5, 0.0, 1.0, 0.5, -0.5, 0.0, 1.0,
    };
    const vertex_buffer = buffer: {
        const desc: c.WGPUBufferDescriptor = .{
            .size = @sizeOf(@TypeOf(vertex_data)),
            .usage = c.WGPUBufferUsage_Vertex | c.WGPUBufferUsage_CopyDst,
        };
        const result = c.wgpuDeviceCreateBuffer(device, &desc);
        c.wgpuQueueWriteBuffer(queue, result, 0, &vertex_data, @sizeOf(@TypeOf(vertex_data)));
        break :buffer result;
    };

    const shader_module = shader: {
        var source: c.WGPUShaderSourceWGSL = .{
            .chain = .{ .sType = c.WGPUSType_ShaderSourceWGSL },
            .code = sv(
                \\@vertex fn vs(@location(0) pos : vec4f) -> @builtin(position) vec4f {
                \\    return pos;
                \\}
                \\@fragment fn fs(@builtin(position) FragCoord : vec4f) -> @location(0) vec4f {
                \\    return vec4f(1, 0, 0, 1);
                \\}
            ),
        };
        const desc: c.WGPUShaderModuleDescriptor = .{ .nextInChain = @ptrCast(&source) };
        const result = c.wgpuDeviceCreateShaderModule(device, &desc);
        break :shader result;
    };

    const pipeline = pipeline: {
        const desc: c.WGPURenderPipelineDescriptor = .{
            .vertex = .{
                .module = shader_module,
                .entryPoint = sv("vs"),
                .buffers = &[_]c.WGPUVertexBufferLayout{.{
                    .arrayStride = 4 * @sizeOf(f32),
                    .attributes = &[_]c.WGPUVertexAttribute{
                        .{ .format = c.WGPUVertexFormat_Float32x4 },
                    },
                    .attributeCount = 1,
                }},
                .bufferCount = 1,
            },
            .fragment = &.{
                .module = shader_module,
                .entryPoint = sv("fs"),
                .targets = &[_]c.WGPUColorTargetState{
                    .{
                        .format = preferred_texture_format,
                        .writeMask = c.WGPUColorWriteMask_All,
                        .blend = &.{
                            .color = .{
                                .operation = c.WGPUBlendOperation_Add,
                                .srcFactor = c.WGPUBlendFactor_One,
                                .dstFactor = c.WGPUBlendFactor_One,
                            },
                            .alpha = .{
                                .operation = c.WGPUBlendOperation_Add,
                                .srcFactor = c.WGPUBlendFactor_One,
                                .dstFactor = c.WGPUBlendFactor_One,
                            },
                        },
                    },
                },
                .targetCount = 1,
            },
            .multisample = .{
                .count = 1,
                .mask = 0xFFFFFFFF,
                .alphaToCoverageEnabled = c.WGPU_FALSE,
            },
        };
        const result = c.wgpuDeviceCreateRenderPipeline(device, &desc);
        break :pipeline result;
    };
    defer c.wgpuRenderPipelineRelease(pipeline);

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                quit = true;
            }
        }
        const surface_texture = surface_texture: {
            var result: c.WGPUSurfaceTexture = undefined;
            c.wgpuSurfaceGetCurrentTexture(surface, &result);
            break :surface_texture result;
        };

        const view = view: {
            const desc: c.WGPUTextureViewDescriptor = .{
                .mipLevelCount = c.WGPU_MIP_LEVEL_COUNT_UNDEFINED,
                .arrayLayerCount = c.WGPU_ARRAY_LAYER_COUNT_UNDEFINED,
            };
            const result = c.wgpuTextureCreateView(surface_texture.texture, &desc);
            break :view result;
        };

        const encoder = encoder: {
            const desc: c.WGPUCommandEncoderDescriptor = .{};
            const result = c.wgpuDeviceCreateCommandEncoder(device, &desc);
            break :encoder result;
        };

        const pass = pass: {
            const colors = [_]c.WGPURenderPassColorAttachment{
                .{
                    .view = view,
                    .loadOp = c.WGPULoadOp_Clear,
                    .storeOp = c.WGPUStoreOp_Store,
                    .clearValue = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                    .depthSlice = c.WGPU_DEPTH_SLICE_UNDEFINED,
                },
            };

            const desc: c.WGPURenderPassDescriptor = .{
                .colorAttachmentCount = colors.len,
                .colorAttachments = &colors,
            };
            const result = c.wgpuCommandEncoderBeginRenderPass(encoder, &desc);
            break :pass result;
        };
        c.wgpuRenderPassEncoderSetPipeline(pass, pipeline);
        c.wgpuRenderPassEncoderSetVertexBuffer(pass, 0, vertex_buffer, 0, c.WGPU_WHOLE_SIZE);
        c.wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0);
        c.wgpuRenderPassEncoderEnd(pass);

        const cmd_buffer = cmd_buffer: {
            const desc: c.WGPUCommandBufferDescriptor = .{};
            const result = c.wgpuCommandEncoderFinish(encoder, &desc);
            break :cmd_buffer result;
        };
        const cmds = [_]c.WGPUCommandBuffer{cmd_buffer};
        c.wgpuQueueSubmit(queue, cmds.len, &cmds);
        _ = c.wgpuSurfacePresent(surface);
    }
}
