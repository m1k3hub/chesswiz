// Native geometry for the Tk Aqua window-manager adapter.
#include <tkInt.h>
#include <tkMacOSXInt.h>
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#include <stdlib.h>

extern "C" double chesswizAquaDpi(Tk_Window tkwin)
{
    Tk_MakeWindowExist(tkwin);
    TkWindow* win = reinterpret_cast<TkWindow*>(tkwin);
    NSWindow* window = [win->privatePtr->toplevel->view window];
    return 72.0 * (window ? window.backingScaleFactor : NSScreen.mainScreen.backingScaleFactor);
}

extern "C" void chesswizAquaGeometry(Tk_Window tkwin, int workarea, int* values)
{
    Tk_MakeWindowExist(tkwin);
    TkWindow* win = reinterpret_cast<TkWindow*>(tkwin);
    NSWindow* window = [win->privatePtr->toplevel->view window];
    if (workarea) {
        NSScreen* screen = window.screen ?: NSScreen.mainScreen;
        NSRect frame = screen.visibleFrame;
        CGFloat top = NSMaxY([NSScreen.screens.firstObject frame]);
        values[0] = frame.origin.x;
        values[1] = top - NSMaxY(frame);
        values[2] = frame.size.width;
        values[3] = frame.size.height;
    } else if (window) {
        NSRect frame = window.frame;
        NSRect content = [window contentRectForFrameRect:frame];
        values[0] = NSMinX(content) - NSMinX(frame);
        values[1] = NSMaxX(frame) - NSMaxX(content);
        values[2] = NSMaxY(frame) - NSMaxY(content);
        values[3] = NSMinY(content) - NSMinY(frame);
    }
}

// Every screen's visible frame in Tk root coordinates, the screen hosting
// <tkwin> first. Returns the number written (at most max).
extern "C" int chesswizAquaWorkAreas(Tk_Window tkwin, int* values, int max)
{
    Tk_MakeWindowExist(tkwin);
    TkWindow* win = reinterpret_cast<TkWindow*>(tkwin);
    NSWindow* window = [win->privatePtr->toplevel->view window];
    NSArray<NSScreen*>* screens = [NSScreen screens];
    NSScreen* host = window.screen ?: NSScreen.mainScreen;
    // Tk's root Y is measured down from the primary screen's top edge, the
    // same origin chesswizAquaGeometry above uses.
    CGFloat top = NSMaxY([NSScreen.screens.firstObject frame]);
    int count = 0;
    for (int pass = 0; pass < 2; ++pass) {
        for (NSScreen* screen in screens) {
            if ((pass == 0) != (screen == host)) continue;
            if (count >= max) return count;
            NSRect frame = screen.visibleFrame;
            values[count * 4 + 0] = (int)frame.origin.x;
            values[count * 4 + 1] = (int)(top - NSMaxY(frame));
            values[count * 4 + 2] = (int)frame.size.width;
            values[count * 4 + 3] = (int)frame.size.height;
            ++count;
        }
    }
    return count;
}

// Register bundled figurine/symbol fonts for this process only.
extern "C" void chesswizAquaRegisterFonts()
{
    const char* share = getenv("SCIDB_SHAREDIR");
    if (!share) return;
    NSString* dir = [[NSString stringWithUTF8String:share] stringByAppendingPathComponent:@"fonts"];
    for (NSString* name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
        if (![name.pathExtension.lowercaseString isEqualToString:@"ttf"]) continue;
        NSURL* url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
        CTFontManagerRegisterFontsForURL((CFURLRef)url, kCTFontManagerScopeProcess, NULL);
    }
}
