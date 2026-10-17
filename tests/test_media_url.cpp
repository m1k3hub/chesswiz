#include "../src/tcl/media_url.h"
#include <assert.h>
int main() {
    char const* urls[] = {"http://a/b", "https://a/live.m3u8?q=1", "file:///tmp/a%20b", "RTSP://a", "custom+one.two-x:abc"};
    char const* paths[] = {"", "/tmp/a:b", "relative file.mp4", "./a:b", "C:/a.wmv", "C:\\a.wmv", "1http:x", ":x"};
    for (unsigned i = 0; i < sizeof(urls)/sizeof(*urls); ++i) assert(mediaHasUrlScheme(urls[i]));
    for (unsigned i = 0; i < sizeof(paths)/sizeof(*paths); ++i) assert(!mediaHasUrlScheme(paths[i]));
}
