//
//  compilertron.cpp
//  Compilertron
//
//  Created by John Holdsworth on 20/11/2022.
//
//  Stub of code to be #inlucded into the Swift compiler
//  which loads the dynamic libraries prepared by the app
//  and interposes their new imlementations into place.
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

#define ERROR(...) return fprintf(stderr, __FILE__ \
            " dyload_patches() error: " __VA_ARGS__)

static time_t timeModified(const char *path) {
    struct stat s;
    return stat(path, &s) == 0 ? s.st_mtimespec.tv_sec : 0;
}

int dyload_patches() {
    struct dl_info execInfo;
    void *main = dlsym(RTLD_SELF, "main");
    if (!main)
        ERROR("Could not lookup main\n");
    if (!dladdr(main, &execInfo))
        ERROR("Could not locate main\n");
    time_t lastBuilt = timeModified(execInfo.dli_fname);
    fprintf(stderr, "dyload_patches( %s )\n", execInfo.dli_fname);

    FILE *patchDylibs = popen("ls -rt " COMPILERTRON_PATCHES, "r");
    if (!patchDylibs)
        ERROR("Could not load list patches\n");
    char lineBuff[10*1024];

    while (const char *patchDylib =
           fgets(lineBuff, sizeof lineBuff, patchDylibs)) {
        lineBuff[strlen(lineBuff)-1] = 0;
        if (timeModified(patchDylib) < lastBuilt)
            continue;
        void *dlopenedPatch = dlopen(patchDylib, RTLD_NOW);
        if (!dlopenedPatch) {
            fprintf(stderr, __FILE__ " dlopen %s failed %s\n",
                    patchDylib, dlerror());
            continue;
        }

        auto nmCommand = std::string("nm '")+patchDylib+"' | grep 'T __Z'";
        FILE *interposableSymbols = popen(nmCommand.c_str(), "r");
        if (!interposableSymbols)
            ERROR("Could not extract syms %s\n", nmCommand.c_str());
        std::vector<const char *> symbolNames;
        while (const char *nmOutput =
               fgets(lineBuff, sizeof lineBuff, interposableSymbols)) {
            lineBuff[strlen(lineBuff)-1] = 0;
            symbolNames.push_back(strdup(nmOutput + 20));
        }

        auto interposes = (rebinding *)
            calloc(symbolNames.size(), sizeof(rebinding));
        int ninterposes = 0;
        for (auto name : symbolNames) {
            interposes[ninterposes].name = name;
            if (auto loaded = dlsym(dlopenedPatch, name))
                interposes[ninterposes++].replacement = loaded;
            else
                fprintf(stderr, __FILE__ "Could not lookup %s in %s\n",
                        name, nmCommand.c_str());
        }

        rebind_symbols(interposes, ninterposes);

        fprintf(stderr, "Patched %d symbols from: %s\n",
                ninterposes, nmCommand.c_str());

        for (auto name : symbolNames)
            free((void *)name);
        free(interposes);
        pclose(interposableSymbols);
    }

    pclose(patchDylibs);
    return 0;
}
