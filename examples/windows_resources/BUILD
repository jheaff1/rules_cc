load("@rules_cc//cc:defs.bzl", "windows_resources", "cc_binary")


windows_resources(
    name = "test_resources",
    rc_files = [
        "version.rc",
    ],
)

cc_binary(
    name = "test",
    srcs = ["main.cc"],
    deps = [":test_resources"],
)