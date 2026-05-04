//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#ifndef NoctilucaClient_Bridging_Header_h
#define NoctilucaClient_Bridging_Header_h

#include <fcntl.h>
#include <sys/stat.h>

// Swift 의 namespace 에서 `stat` 이 함수와 struct 양쪽으로 사용되어 ambiguity 가 발생한다.
// Swift 에서는 alias `noc_stat_t` 를 통해 struct 만 명시적으로 참조한다.
typedef struct stat noc_stat_t;

// Swift 는 C variadic 함수 (open(path, oflag, ...)) 를 직접 호출할 수 없으므로
// 명시적 mode 인자를 받는 wrapper 를 노출한다.
static inline int noc_open_with_mode(const char * _Nonnull path, int oflag, mode_t mode) {
    return open(path, oflag, mode);
}

static inline int noc_stat(const char * _Nonnull path, noc_stat_t * _Nonnull buf) {
    return stat(path, buf);
}

static inline int noc_lstat(const char * _Nonnull path, noc_stat_t * _Nonnull buf) {
    return lstat(path, buf);
}

static inline int noc_fstat(int fd, noc_stat_t * _Nonnull buf) {
    return fstat(fd, buf);
}

#endif /* NoctilucaClient_Bridging_Header_h */
