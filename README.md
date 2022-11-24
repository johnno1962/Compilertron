
### Compilertron -- InjectionIII for working on the Swift compiler.

Compilertron allows you to avoid having to wait for
most builds of the swift-frontend executable while
working on the compiler. It is a minimal
implementation of the basic interposing functionality
of the [InjectionIII](https://github.com/johnno1962/InjectionIII)
app. In order to be able to use it, clone this repo 
to your `swift-sources` directory at the same level
as the `swift` project and make this patch to the
swift project itself:

```
diff --git a/lib/Frontend/CompilerInvocation.cpp b/lib/Frontend/CompilerInvocation.cpp
index c2ac2ebdb421a..237916675faa5 100644
--- a/lib/Frontend/CompilerInvocation.cpp
+++ b/lib/Frontend/CompilerInvocation.cpp
@@ -2561,6 +2561,11 @@ static bool ParseMigratorArgs(MigratorOptions &Opts,
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
@@ -2568,6 +2573,10 @@ bool CompilerInvocation::parseArgs(
     StringRef workingDirectory, StringRef mainExecutablePath) {
   using namespace options;
 
+  #ifndef NDEBUG
+  dyload_patches();
+  #endif
+
   if (Args.empty())
     return false;
```

You will also need to add `-Xlinker -interposable` to the 
`"Other Linker Flags"` of the `swift-frontend` target and rebuild.

After this, if you run the macOS app in this repo, when you edit
and save a .cpp source file the app greps though the last build log 
of the `Swift.xcodeproj` (or `LLVM.xcodeproj`) to find how to
recompile the source, then links the resulting object file into a
dynamic library. The next time you run a swift compiler modified as
described above it will dynamically load the new implementation of the
function just edited instead of having to wait for the compiler to
build again. You can patch multiple files in this way and they will be
loaded separately. Somehow, LLDB is able to correctly set
debugger breakpoints in the dynamically loaded code.

This only works for functions or member function bodies of C++
classes. You cannot alter headers or the memory layout of
classes over a patch but you can iterate of the implementation
of a function body without having to do a full rebuild. To launch
the compiler in Xcode without having to wait for the rebuild,
hold the control button as you launch swift-frontend to debug.

Compilertron uses `interpossing`, a feature related to dynamic
linking that allows you to modify the destination of all calls
to any public function. It does this using the `-interposbale`
flag in combination with facebook's incredibly handy
[fishhook](https://github.com/facebook/fishhook). The licensing
details for this library are in the `fishhook.cpp` file and header.
Details on how this works are laid out in detail [here](https://www.mikeash.com/pyblog/friday-qa-2012-11-09-dyld-dynamic-linking-on-os-x.html).

The UI is as limited as my SwiftUI skills. In essence
when it is idle it starts out with black text, which
turns orange when a file has ben modified and it is
searching logs for the compile command, then green
during re-compilation then back to black when the
dynamic library has been built. It will display text
in red if there is an error while compiling the
modified source.

$Date: 2022/11/24 $
