//
//  compilertron.cpp
//  Compilertron
//
//  Created by John Holdsworth on 20/11/2022.
//
//  Stub of code to be #inlucded into the Swift compiler
//  which loads the dynamic libraries prepared by the app
//  and interposes their new implementations into place.
//  For this to work you need to have linked the compiler
//  with "Other Linker Flags": `-Xlinker -interposable`.
//

#include "compilertron.hpp"
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <string.h>
#include <dlfcn.h>
#include <stdio.h>
#include <vector>
#include <string>
#include <map>

#include "fishhook.cpp"

#define ERROR(...) return fprintf(output, __FILE__ \
            " dyload_patches() error: " __VA_ARGS__)

extern "C" {
    char *__cxa_demangle(const char *symbol, char *out,
                         size_t *length, int *status);
}

static time_t timeModified(const char *path) {
    struct stat s;
    return stat(path, &s) == 0 ? s.st_mtimespec.tv_sec : 0;
}

FILE *compilertronLOG;

FILE *dyLOG() {
    if (!compilertronLOG) {
        compilertronLOG = fopen("/tmp/compilertron.log", "a+");
        setbuf(compilertronLOG, NULL);
    }
    return compilertronLOG;
}

int dyprintf(const char *fmt, ...) {
    va_list al;
    va_start(al, fmt);
    int bytes = vfprintf(dyLOG(), fmt, al);
    va_end(al);
    return bytes;
}

int dyload_patches() {
    FILE *output = dyLOG();
    if (!output)
        output = stderr;
    void *main = dlsym(RTLD_SELF, "main");
    if (!main)
        ERROR("Could not lookup main\n");
    struct dl_info execInfo;
    if (!dladdr(main, &execInfo))
        ERROR("Could not locate main\n");
    time_t lastBuilt = timeModified(execInfo.dli_fname);

    fprintf(output, "\ndyload_patches(\"%s\")\n", execInfo.dli_fname);
    FILE *patchDylibs = popen("ls -rt 2>/dev/null " COMPILERTRON_PATCHES, "r");
    if (!patchDylibs)
        ERROR("Could not list patches\n");
    static char lineBuff[100*1024];
    std::map<std::string, void *> previous;

    while (const char *patchDylib =
           fgets(lineBuff, sizeof lineBuff, patchDylibs)) {
        lineBuff[strlen(lineBuff)-1] = 0;
        if (timeModified(patchDylib) < lastBuilt)
            continue;

        auto lastImage = _dyld_image_count();
        void *dylilbHandle = dlopen(patchDylib, RTLD_NOW);
        if (!dylilbHandle) {
            fprintf(output, __FILE__ " Failed %s\n", dlerror());
            continue;
        }

        static rebinding interposes[100000];
        int ninterposes = 0, napplied = 0;
        for (auto &pair : previous) {
            interposes[ninterposes].name = pair.first.c_str();
            interposes[ninterposes].replacement = pair.second;
            interposes[ninterposes++].replaced = nullptr;
        }

        rebind_symbols_image((void *)_dyld_get_image_header(lastImage),
                             _dyld_get_image_vmaddr_slide(lastImage),
                             interposes, ninterposes);

        std::string dylibstr = patchDylib;
        auto nmCommand = "nm '"+dylibstr+"' | grep 'T __Z'";
        FILE *interposableSymbols = popen(nmCommand.c_str(), "r");
        if (!interposableSymbols)
            ERROR("Could not extract syms %s\n", nmCommand.c_str());

        struct interpose { char *name; void *applied; };
        std::vector<struct interpose> dylibSymbols;
        while (const char *nmOutput =
               fgets(lineBuff, sizeof lineBuff, interposableSymbols)) {
            lineBuff[strlen(lineBuff)-1] = 0;
            dylibSymbols.push_back({strdup(nmOutput + 20), nullptr});
        }

        ninterposes = 0;
        for (auto &pair : dylibSymbols) {
            interposes[ninterposes].name = pair.name;
            interposes[ninterposes].replaced = &pair.applied;
            if (auto loaded = dlsym(dylilbHandle, pair.name)) {
                interposes[ninterposes++].replacement = loaded;
                previous[pair.name] = loaded;
            }
            else
                fprintf(output,
                        __FILE__ " Could not lookup %s in %s\n",
                        pair.name, nmCommand.c_str());
        }

        rebind_symbols(interposes, ninterposes);

        bool log = output != stderr || 
                   getenv("LOG_INTERPOSES") != nullptr ||
                   getenv("INJECTION_DETAIL") != nullptr;
        for (int i=0; i<ninterposes; i++)
            if (*interposes[i].replaced && ++napplied && log)
                fprintf(output, "  Interposed %s\n",
                        __cxa_demangle(interposes[i].name,
                                       nullptr, nullptr, nullptr));

        fprintf(output, "Patched %d/%d/%d symbols from: %s\n\n",
                napplied, ninterposes, (int)dylibSymbols.size(),
                dylibstr.c_str());

        for (auto &pair : dylibSymbols)
            free(pair.name);
        pclose(interposableSymbols);
    }

    pclose(patchDylibs);
    return 0;
}
