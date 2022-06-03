load("@rules_cc//cc:defs.bzl", "windows_resources", "cc_binary")


windows_resources(
    name = "hello_resources",
    rc_files = [
        "hello.rc",
        "version.rc",
    ],
    resources = [
        "version.txt",
        "//images:app.ico",
    ],
)

cc_binary(
    name = "hello",
    srcs = ["main.cc"],
    deps = [":hello_resources"],
)