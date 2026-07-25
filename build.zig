const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl3_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .SDL_OPENGL = false,
        .SDL_OPENGLES = false,
        .SDL_GPU = false,
        .SDL_DIALOG = false,
        .SDL_SENSOR = false,
        .SDL_POWER = false,
        .SDL_CAMERA = false,
        .SDL_RENDER_D3D = false,
        .SDL_RENDER_D3D11 = false,
        .SDL_VULKAN = false,
    });
    const sdl3_lib = sdl3_dep.artifact("sdl3");

    const dawn_dep = b.dependency("dawn", .{
        .target = target,
        .optimize = optimize,
        .linkage = .dynamic,
        .DAWN_ENABLE_VULKAN = true,
        .DAWN_FORCE_SYSTEM_COMPONENT_LOAD = true,
    });
    const webgpu_lib = dawn_dep.artifact("webgpu_dawn");

    const sdl3webgpu_dep = b.dependency("sdl3webgpu", .{
        .target = target,
        .optimize = optimize,
        .sdl3_headers = sdl3_lib.getEmittedIncludeTree(),
        .sdl3_library = sdl3_lib.getEmittedBin(),
        .webgpu_headers = webgpu_lib.getEmittedIncludeTree(),
        .webgpu_library = webgpu_lib.getEmittedBin(),
    });
    const sdl3webgpu_lib = sdl3webgpu_dep.artifact("sdl3webgpu");

    const amalgamate_c = b.addWriteFile("c.h",
        \\#include <SDL3/SDL.h>
        \\#include <dawn/webgpu.h>
        \\#include <sdl3webgpu.h>
    );

    const translate_c = b.addTranslateC(.{
        .root_source_file = amalgamate_c.getDirectory().path(b, "c.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(sdl3_lib.getEmittedIncludeTree());
    translate_c.addIncludePath(webgpu_lib.getEmittedIncludeTree());
    translate_c.addIncludePath(sdl3webgpu_lib.getEmittedIncludeTree());

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.linkLibrary(sdl3webgpu_lib);
    exe.root_module.linkLibrary(sdl3_lib);
    exe.root_module.linkLibrary(webgpu_lib);

    exe.root_module.addImport("c", translate_c.createModule());

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
