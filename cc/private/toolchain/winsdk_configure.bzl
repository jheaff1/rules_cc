# Copyright 2019 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Configure local Resource Compilers for every available target platform.

Platform support:

- Linux/macOS/non-Windows: this repository rule is almost a no-op.
  It generates an empty BUILD file, and does not actually discover any
  toolchains. The register_local_rc_exe_toolchains() method is a no-op.

- Windows: this repository rule discovers the Windows SDK path, the installed
  rc.exe compilers. The register_local_rc_exe_toolchains() registers a toolchain
  for each rc.exe compiler.

Usage:

    load("//cc/private/toolchains:winsdk_configure.bzl", "winsdk_configure")

    winsdk_configure(name = "local_config_winsdk")

    load("@local_config_winsdk//:toolchains.bzl", "register_local_rc_exe_toolchains")

    register_local_rc_exe_toolchains()
"""

load("@bazel_tools//tools/cpp:cc_configure.bzl", "MSVC_ENVVARS")
load("@bazel_tools//tools/cpp:windows_cc_configure.bzl", "find_vc_path", "setup_vc_env_vars")

# Keys: target architecture, as in <Windows-SDK-path>/<target-architecture>/bin/rc.exe
# Values: corresponding Bazel CPU value under @platforms//cpu:*
_TARGET_ARCH = {
    "arm": "arm",
    "arm64": "aarch64",
    "x64": "x86_64",
    "x86": "x86_32",
}

def _find_rc_exes(root):
    result = {}
    for a in _TARGET_ARCH:
        exe = root.get_child(a).get_child("rc.exe")
        if exe.exists:
            result[a] = str(exe)
    return result

def _find_all_rc_exe(repository_ctx):
    if not repository_ctx.os.name.startswith("windows"):
        return {}

    vc = find_vc_path(repository_ctx)
    if vc:
        env = setup_vc_env_vars(
            repository_ctx,
            vc,
            envvars = [
                "WindowsSdkDir",
                "WindowsSdkVerBinPath",
            ],
            allow_empty = True,
            escape = False,
        )

        # Try the versioned directory.
        sdk = env.get("WindowsSdkVerBinPath")
        if sdk:
            archs = _find_rc_exes(repository_ctx.path(sdk))
            if archs:
                return archs

        # Try the unversioned directory (typically Windows 8.1 SDK).
        sdk = env.get("WindowsSdkDir")
        if sdk:
            archs = _find_rc_exes(repository_ctx.path(sdk).get_child("bin"))
            if archs:
                return archs
    return {}

def _toolchain_defs(repository_ctx, rc_exes):
    if not rc_exes:
        return ""

    result = ["""# Auto-generated by winsdk_configure.bzl
load(
    "@rules_cc//cc/private/toolchain:winsdk_toolchain.bzl",
    "WINDOWS_RESOURCE_COMPILER_TOOLCHAIN_TYPE",
    "windows_resource_compiler_toolchain",
)"""]

    for arch, rc_path in rc_exes.items():
        wrapper = "rc_%s.bat" % arch
        repository_ctx.file(
            wrapper,
            content = "@\"%s\" %%*" % rc_path,
            executable = True,
        )

        result.append(
            """
windows_resource_compiler_toolchain(
    name = "local_{arch}_tc",
    rc_exe = "{wrapper}",
)

toolchain(
    name = "local_{arch}",
    exec_compatible_with = [
        "@platforms//os:windows",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:windows",
        "@platforms//cpu:{cpu}",
    ],
    toolchain = ":local_{arch}_tc",
    toolchain_type = WINDOWS_RESOURCE_COMPILER_TOOLCHAIN_TYPE,
    visibility = ["//visibility:public"],
)
""".format(
                arch = arch,
                wrapper = wrapper,
                cpu = _TARGET_ARCH[arch],
            ),
        )

    return "\n".join(result)

def _toolchain_labels(repository_ctx, rc_exes):
    tc_labels = [
        "\"@{repo}//:local_{arch}\"".format(repo = repository_ctx.name, arch = arch)
        for arch in rc_exes
    ]
    if rc_exes:
        body = "native.register_toolchains(%s)" % ", ".join(tc_labels)
    else:
        body = "pass"

    return """# Auto-generated by winsdk_configure.bzl

def register_local_rc_exe_toolchains():
    {body}
""".format(body = body)

def _impl(repository_ctx):
    rc_exes = _find_all_rc_exe(repository_ctx)
    repository_ctx.file(
        "BUILD",
        content = _toolchain_defs(repository_ctx, rc_exes),
        executable = False,
    )

    repository_ctx.file(
        "toolchains.bzl",
        content = _toolchain_labels(repository_ctx, rc_exes),
        executable = False,
    )

winsdk_configure = repository_rule(
    implementation = _impl,
    local = True,
    environ = list(MSVC_ENVVARS),
)
