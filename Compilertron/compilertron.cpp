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
#include "fishhook.cpp"
#include <sys/stat.h>
#include <sys/time.h>
#include <string.h>
#include <dlfcn.h>
#include <stdio.h>
#include <vector>
#include <string>

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

int dyload_patches() {
    FILE *output = stderr;
    void *main = dlsym(RTLD_SELF, "main");
    if (!main)
        ERROR("Could not lookup main\n");
    struct dl_info execInfo;
    if (!dladdr(main, &execInfo))
        ERROR("Could not locate main\n");
    time_t lastBuilt = timeModified(execInfo.dli_fname);

    fprintf(output, "dyload_patches( %s )\n", execInfo.dli_fname);
    FILE *patchDylibs = popen("ls -rt " COMPILERTRON_PATCHES, "r");
    if (!patchDylibs)
        ERROR("Could not list patches\n");
    static char lineBuff[100*1024];

    while (const char *patchDylib =
           fgets(lineBuff, sizeof lineBuff, patchDylibs)) {
        lineBuff[strlen(lineBuff)-1] = 0;
        if (timeModified(patchDylib) < lastBuilt)
            continue;
        void *dylilbHandle = dlopen(patchDylib, RTLD_NOW);
        if (!dylilbHandle) {
            fprintf(output, __FILE__ " dlopen %s failed %s\n",
                    patchDylib, dlerror());
            continue;
        }

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

        auto interposes = (rebinding *)
            calloc(dylibSymbols.size(), sizeof(rebinding));
        int ninterposes = 0, napplied = 0;
        for (auto &pair : dylibSymbols) {
            interposes[ninterposes].name = pair.name;
            interposes[ninterposes].replaced = &pair.applied;
            if (auto loaded = dlsym(dylilbHandle, pair.name))
                interposes[ninterposes++].replacement = loaded;
            else
                fprintf(output,
                        __FILE__ " Could not lookup %s in %s\n",
                        pair.name, nmCommand.c_str());
        }

        rebind_symbols(interposes, ninterposes);

        bool log = getenv("LOG_INTERPOSES") != nullptr;
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
        free(interposes);
        pclose(interposableSymbols);
    }

    pclose(patchDylibs);
    return 0;
}
