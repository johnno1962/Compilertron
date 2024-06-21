
### Compilertron II -- Injecting changes into the Swift compiler.

Updated 21/6/2024:

Compilertron allows you to avoid having to wait for
many builds of the swift-frontend executable while
working on the compiler using facebooks's legondary
[fishhook](https://github.com/facebook/fishhook).
It is a minimal implementation of the basic interposing functionality 
of the [InjectionIII](https://github.com/johnno1962/InjectionIII)
app. In order to use it, clone this repo into your `swift-sources` 
directory at the same level as the `swift` project and `git apply` 
the folowing patch to the swift project itself then build a toolchain:

```
diff --git a/cmake/modules/AddSwift.cmake b/cmake/modules/AddSwift.cmake
index 0ee1eef27a9..5515e480519 100644
--- a/cmake/modules/AddSwift.cmake
+++ b/cmake/modules/AddSwift.cmake
@@ -437,8 +437,9 @@ function(_add_host_variant_link_flags target)
     if (NOT SWIFT_DISABLE_DEAD_STRIPPING)
       # See rdar://48283130: This gives 6MB+ size reductions for swift and
       # SourceKitService, and much larger size reductions for sil-opt etc.
-      target_link_options(${target} PRIVATE
-        "SHELL:-Xlinker -dead_strip")
+# This option doesn't help with injection
+#      target_link_options(${target} PRIVATE
+#        "SHELL:-Xlinker -dead_strip")
     endif()
   endif()
 
@@ -447,6 +448,9 @@ function(_add_host_variant_link_flags target)
       "SHELL:-Xlinker -no_warn_duplicate_libraries")
   endif()
 
+  # Don't check these 3 lines in
+  target_link_options(${target} PRIVATE
+    "SHELL:-Xlinker -interposable")
 endfunction()
 
 function(_add_swift_runtime_link_flags target relpath_to_lib_dir bootstrapping)
diff --git a/include/swift/AST/Expr.h b/include/swift/AST/Expr.h
index 3fd18a50511..01a273f2165 100644
--- a/include/swift/AST/Expr.h
+++ b/include/swift/AST/Expr.h
@@ -36,6 +36,8 @@
 #include <optional>
 #include <utility>
 
+#include "../../../../Compilertron/Compilertron/compilertron.hpp"
+
 namespace llvm {
   struct fltSemantics;
 }
diff --git a/lib/Frontend/CompilerInvocation.cpp b/lib/Frontend/CompilerInvocation.cpp
index 26e5f319e94..6eab3abac09 100644
--- a/lib/Frontend/CompilerInvocation.cpp
+++ b/lib/Frontend/CompilerInvocation.cpp
@@ -3433,6 +3433,11 @@ static bool ParseMigratorArgs(MigratorOptions &Opts,
   return false;
 }
 
+#ifndef NDEBUG
+// repo: https://github.com/johnno1962/Compilertron
+#include "../../../Compilertron/Compilertron/compilertron.cpp"
+#endif
+
 bool CompilerInvocation::parseArgs(
     ArrayRef<const char *> Args, DiagnosticEngine &Diags,
     SmallVectorImpl<std::unique_ptr<llvm::MemoryBuffer>>
@@ -3440,6 +3445,12 @@ bool CompilerInvocation::parseArgs(
     StringRef workingDirectory, StringRef mainExecutablePath) {
   using namespace options;
 
+  #ifndef NDEBUG
+  dyload_patches();
+  if (Args.empty())
+    dyprintf("Avoid symbol stripping\n");
+  #endif
+
   if (Args.empty())
     return false;
 

```

Then, use the following command to generate Xcode projects for the Swift
and LLVM sources:

```
utils/build-script --skip-build-benchmarks \
  --skip-ios --skip-watchos --skip-tvos --swift-darwin-supported-archs "$(uname -m)" \
  --sccache --release-debuginfo --swift-disable-dead-stripping --xcode`
```

You no longer run the small SwiftUI app in this repo but compilertron 
now works in conjunction with the renovated implementation of injection:
[InjectionNext](https://github.com/johnno1962/InjectionNext). Download or
build the app in that repo and run it, quit Xcode and use the InjectionNext
app (which runs on the menu bar) to "Launch Xcode" then open the generated
`build/Xcode-RelWithDebInfoAssert/swift-macosx-arm64/Swift.xcodeproj`.
When you save a file it should compile it and prepare a dynamic library in
`/tmp/compilertron_patches`. The next time you compile using the toolchain
you prepared earlier it should "interpose" any new implementations in this
driectory into the compiler before running it. A log of which functions
that have been "interposed" is logged `/tmp/compilertron.log`.

For example, if you have a compiler crash in the toolchain for a particular
project you can insert dyprintf() statements into your code and save the file.
After it has completed compiling (when the menubar icon stops being green)
the next time you do an Xcode build on the problematic project if it is using
the toolchain you built easier it will log your debug dyprintf()s to 
`/tmp/compilertron.log` without having to rebuild the entire toolchain. It is 
also possible to edit and patch sources in LLVM.xcodeproj though if you want 
to log information you'll need the following somewhere in the LLVM sources:

```
#if INJECTING
extern "C" { extern int dyprintf(const char *fmt, ...); }
#endif
```

### Limitations

You can only inject changes to public function bodies and not inject
headers or changes to members of a class. I've also noticed that 
source files that run top level C++ initialisers fail to load.
If in doubt, `tail -f /tmp/compilertron.log &` for error messages.

$Date: 2024/06/21 $
