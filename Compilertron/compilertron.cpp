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

static time_t mtime(const char *path) {
    struct stat s;
    return stat(path, &s) == 0 ? s.st_mtimespec.tv_sec : 0;
}

int dyload_patches() {
    struct dl_info info;
    void *main = dlsym(RTLD_SELF, "main");
    if (!main)
        return fprintf(stderr, "!Could not lookup main\n");
    if (!dladdr(main, &info))
        return fprintf(stderr, "!Could not locate main\n");
    time_t lastbuilt = mtime(info.dli_fname);
    fprintf(stderr, "dyload_patches( %s )\n", info.dli_fname);

    FILE *patches = popen("ls -rt " COMPILERTRON_PATCHES, "r");
    if (!patches)
        return fprintf(stderr, "!Could not load list patches\n");
    char buffer[10*1024];

    while (fgets(buffer, sizeof buffer, patches)) {
        buffer[strlen(buffer)-1] = 0;
        if (mtime(buffer) < lastbuilt)
            continue;
        void *handle = dlopen(buffer, RTLD_NOW);
        if (!handle) {
            fprintf(stderr, "!dlopen %s failed %s\n",
                    buffer, dlerror());
            continue;
        }

        auto nm = std::string("nm ")+buffer+" | grep 'T __Z'";
        FILE *syms = popen(nm.c_str(), "r");
        if (!syms)
            return fprintf(stderr, "!Could not extract syms %s\n", nm.c_str());
        std::vector<const char *> symbols;
        while (fgets(buffer, sizeof buffer, syms)) {
            buffer[strlen(buffer)-1] = 0;
            symbols.push_back(strdup(buffer+20));
        }

        auto rebindings = (rebinding *)
            calloc(symbols.size(), sizeof(rebinding));
        int i = 0;
        for (auto sym : symbols) {
            rebindings[i].name = sym;
            rebindings[i++].replacement = dlsym(handle, sym);
        }

        rebind_symbols(rebindings, symbols.size());

        fprintf(stderr, "Patched %lu symbols from: %s\n",
                symbols.size(), nm.c_str());

        for (auto sym : symbols)
            free((void *)sym);
        free(rebindings);
        pclose(syms);
    }

    pclose(patches);
    return 0;
}
