//
//  compilertron.hpp
//  Compilertron
//
//  Created by John Holdsworth on 20/11/2022.
//

#ifndef copilertron_hpp
#define copilertron_hpp

#include <stdio.h>

#define COMPILERTRON_PATCHES "/tmp/compilertron_patches/*.dylib"
#ifdef __cplusplus
extern "C" {
#endif
extern int dyload_patches();
extern FILE *compilertronLOG, *dyLOG();
extern int dyprintf(const char *fmt, ...);
#ifdef __cplusplus
}
#endif
#endif /* copilertron_hpp */
