// ======================================================================
// 3D OpenGL Chessboard Renderer for Tk / Togl
// ======================================================================

#include "tk_glboard.h"
#include "tcl_base.h"
#include "gl_piece_data.h"

#include <tcl.h>
#include <tk.h>
#include <GL/gl.h>
#include <GL/glu.h>
#include <dlfcn.h>
#include <math.h>
#include <string.h>
#include <stdio.h>

struct Togl;

// Dynamic function pointers to Togl functions in libTogl.so
typedef int (*Togl_GetToglFromName_fn)(Tcl_Interp* interp, const char* cmdName, struct Togl** toglPtr);
typedef void (*Togl_MakeCurrent_fn)(const struct Togl* togl);
typedef void (*Togl_SwapBuffers_fn)(const struct Togl* togl);
typedef int (*Togl_Width_fn)(const struct Togl* togl);
typedef int (*Togl_Height_fn)(const struct Togl* togl);

static Togl_GetToglFromName_fn fn_Togl_GetToglFromName = NULL;
static Togl_MakeCurrent_fn fn_Togl_MakeCurrent = NULL;
static Togl_SwapBuffers_fn fn_Togl_SwapBuffers = NULL;
static Togl_Width_fn fn_Togl_Width = NULL;
static Togl_Height_fn fn_Togl_Height = NULL;

static void clearToglSyms()
{
    fn_Togl_GetToglFromName = NULL;
    fn_Togl_MakeCurrent = NULL;
    fn_Togl_SwapBuffers = NULL;
    fn_Togl_Width = NULL;
    fn_Togl_Height = NULL;
}

static bool resolveToglSyms(void* handle)
{
    fn_Togl_GetToglFromName = (Togl_GetToglFromName_fn)dlsym(handle, "Togl_GetToglFromName");
    fn_Togl_MakeCurrent = (Togl_MakeCurrent_fn)dlsym(handle, "Togl_MakeCurrent");
    fn_Togl_SwapBuffers = (Togl_SwapBuffers_fn)dlsym(handle, "Togl_SwapBuffers");
    fn_Togl_Width = (Togl_Width_fn)dlsym(handle, "Togl_Width");
    fn_Togl_Height = (Togl_Height_fn)dlsym(handle, "Togl_Height");
    return (fn_Togl_GetToglFromName && fn_Togl_MakeCurrent && fn_Togl_SwapBuffers
        && fn_Togl_Width && fn_Togl_Height);
}

static bool loadToglSymbols(Tcl_Interp* interp)
{
    typedef int (*Togl_Init_fn)(Tcl_Interp*);

    if (fn_Togl_GetToglFromName != NULL) return true;
    clearToglSyms();

    // 1. Maybe libTogl is already in the global dynamic scope.
    if (resolveToglSyms(RTLD_DEFAULT)) return true;
    clearToglSyms();

    // 2. Prefer the exact libTogl instance that Tcl's `load` command opened
    //    (Tcl loads extension libraries RTLD_LOCAL, so they are invisible to
    //    RTLD_DEFAULT).  Opening the very same file again hands us the
    //    already-loaded object whose Tcl stubs table was initialized by its
    //    Togl_Init.  Opening a *different* copy of libTogl would create a
    //    second instance with an uninitialized stubs table, and calling into
    //    it segfaults on the first stubs-table dispatch.
    if (interp != NULL && Tcl_Eval(interp, "info loaded") == TCL_OK) {
        Tcl_Obj* loaded = Tcl_GetObjResult(interp);
        int n = 0;
        if (Tcl_ListObjLength(interp, loaded, &n) == TCL_OK) {
            for (int i = 0; i < n; ++i) {
                Tcl_Obj* entry = NULL;
                Tcl_Obj* file = NULL;
                Tcl_Obj* pkg = NULL;
                if (Tcl_ListObjIndex(interp, loaded, i, &entry) != TCL_OK) break;
                int len = 0;
                if (Tcl_ListObjLength(interp, entry, &len) != TCL_OK || len < 2) continue;
                if (Tcl_ListObjIndex(interp, entry, 0, &file) != TCL_OK
                    || Tcl_ListObjIndex(interp, entry, 1, &pkg) != TCL_OK) continue;
                const char* pkgName = Tcl_GetString(pkg);
                if (pkgName == NULL || strcmp(pkgName, "Togl") != 0) continue;
                const char* path = Tcl_GetString(file);
                if (path == NULL || path[0] == '\0') continue; // statically linked
                void* handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
                if (handle == NULL) continue;
                if (resolveToglSyms(handle)) return true;
                clearToglSyms();
            }
        }
        Tcl_ResetResult(interp);
    }

    // 3. Last resort: open a system libTogl ourselves.  A fresh instance
    //    comes with an uninitialized stubs table, so run its Togl_Init to
    //    make it usable (this also creates the `togl` command).
    static const char* candidates[] = {
        "/usr/lib/libTogl.so",
        "/usr/lib/libTogl.so.2.0",
        "/usr/lib/x86_64-linux-gnu/libTogl.so",
        "libTogl.so.2",
    };
    for (unsigned i = 0; i < sizeof(candidates)/sizeof(candidates[0]); ++i) {
        void* handle = dlopen(candidates[i], RTLD_NOW | RTLD_GLOBAL);
        if (handle == NULL) continue;
        if (!resolveToglSyms(handle)) {
            clearToglSyms();
            continue;
        }
        Togl_Init_fn init = (Togl_Init_fn)dlsym(handle, "Togl_Init");
        if (init == NULL || init(interp) != TCL_OK) {
            clearToglSyms();
            if (interp != NULL) Tcl_ResetResult(interp);
            continue;
        }
        return true;
    }

    return false;
}

namespace {

// Display lists for pieces
static GLuint g_pieceDisplayLists[6] = {0, 0, 0, 0, 0, 0}; // p, r, n, b, q, k
static bool g_listsCompiled = false;

static void compileDisplayLists()
{
    if (g_listsCompiled) return;

    GLuint base = glGenLists(6);
    for (int i = 0; i < 6; ++i) {
        g_pieceDisplayLists[i] = base + i;
    }

    const struct {
        int tris;
        const float* data;
    } pieceMeshes[6] = {
        { p_num_tris, p_tri_data },
        { r_num_tris, r_tri_data },
        { n_num_tris, n_tri_data },
        { b_num_tris, b_tri_data },
        { q_num_tris, q_tri_data },
        { k_num_tris, k_tri_data }
    };

    for (int idx = 0; idx < 6; ++idx) {
        glNewList(g_pieceDisplayLists[idx], GL_COMPILE);
        glBegin(GL_TRIANGLES);
        const float* d = pieceMeshes[idx].data;
        int nTris = pieceMeshes[idx].tris;
        for (int t = 0; t < nTris; ++t) {
            // Vertex 1
            glNormal3f(d[3], d[4], d[5]);
            glVertex3f(d[0], d[1], d[2]);
            // Vertex 2
            glNormal3f(d[9], d[10], d[11]);
            glVertex3f(d[6], d[7], d[8]);
            // Vertex 3
            glNormal3f(d[15], d[16], d[17]);
            glVertex3f(d[12], d[13], d[14]);
            d += 18;
        }
        glEnd();
        glEndList();
    }

    g_listsCompiled = true;
}

static void drawCube(float x, float y, float z, float sx, float sy, float sz)
{
    float hx = sx * 0.5f;
    float hy = sy * 0.5f;
    float hz = sz * 0.5f;

    glBegin(GL_QUADS);
    // Top (+Z)
    glNormal3f(0.0f, 0.0f, 1.0f);
    glVertex3f(x - hx, y - hy, z + hz);
    glVertex3f(x + hx, y - hy, z + hz);
    glVertex3f(x + hx, y + hy, z + hz);
    glVertex3f(x - hx, y + hy, z + hz);

    // Bottom (-Z)
    glNormal3f(0.0f, 0.0f, -1.0f);
    glVertex3f(x - hx, y - hy, z - hz);
    glVertex3f(x - hx, y + hy, z - hz);
    glVertex3f(x + hx, y + hy, z - hz);
    glVertex3f(x + hx, y - hy, z - hz);

    // Front (-Y)
    glNormal3f(0.0f, -1.0f, 0.0f);
    glVertex3f(x - hx, y - hy, z - hz);
    glVertex3f(x + hx, y - hy, z - hz);
    glVertex3f(x + hx, y - hy, z + hz);
    glVertex3f(x - hx, y - hy, z + hz);

    // Back (+Y)
    glNormal3f(0.0f, 1.0f, 0.0f);
    glVertex3f(x - hx, y + hy, z - hz);
    glVertex3f(x - hx, y + hy, z + hz);
    glVertex3f(x + hx, y + hy, z + hz);
    glVertex3f(x + hx, y + hy, z - hz);

    // Left (-X)
    glNormal3f(-1.0f, 0.0f, 0.0f);
    glVertex3f(x - hx, y - hy, z - hz);
    glVertex3f(x - hx, y - hy, z + hz);
    glVertex3f(x - hx, y + hy, z + hz);
    glVertex3f(x - hx, y + hy, z - hz);

    // Right (+X)
    glNormal3f(1.0f, 0.0f, 0.0f);
    glVertex3f(x + hx, y - hy, z - hz);
    glVertex3f(x + hx, y + hy, z - hz);
    glVertex3f(x + hx, y + hy, z + hz);
    glVertex3f(x + hx, y - hy, z + hz);
    glEnd();
}

static void drawBoard(int selectedSq, int suggestedSq)
{
    // Wood border base slab
    float woodAmbient[4]  = {0.25f, 0.15f, 0.08f, 1.0f};
    float woodDiffuse[4]  = {0.45f, 0.28f, 0.14f, 1.0f};
    float woodSpecular[4] = {0.15f, 0.15f, 0.15f, 1.0f};
    glMaterialfv(GL_FRONT, GL_AMBIENT, woodAmbient);
    glMaterialfv(GL_FRONT, GL_DIFFUSE, woodDiffuse);
    glMaterialfv(GL_FRONT, GL_SPECULAR, woodSpecular);
    glMaterialf(GL_FRONT, GL_SHININESS, 25.0f);

    // Slab: width 9.6, length 9.6, height 0.5, centered at (4.0, 4.0, -0.25)
    drawCube(4.0f, 4.0f, -0.25f, 9.6f, 9.6f, 0.5f);

    // 64 Squares: top surface at Z = 0.01f, height 0.02f
    float lightAmbient[4]  = {0.35f, 0.32f, 0.28f, 1.0f};
    float lightDiffuse[4]  = {0.94f, 0.85f, 0.71f, 1.0f};
    float lightSpecular[4] = {0.25f, 0.25f, 0.25f, 1.0f};

    float darkAmbient[4]   = {0.20f, 0.14f, 0.10f, 1.0f};
    float darkDiffuse[4]   = {0.55f, 0.35f, 0.22f, 1.0f};
    float darkSpecular[4]  = {0.20f, 0.20f, 0.20f, 1.0f};

    float selAmbient[4]    = {0.40f, 0.38f, 0.10f, 1.0f};
    float selDiffuse[4]    = {0.95f, 0.85f, 0.20f, 1.0f};
    float selSpecular[4]   = {0.50f, 0.50f, 0.30f, 1.0f};

    float sugAmbient[4]    = {0.08f, 0.18f, 0.42f, 1.0f};
    float sugDiffuse[4]    = {0.30f, 0.50f, 0.95f, 1.0f};
    float sugSpecular[4]   = {0.40f, 0.40f, 0.45f, 1.0f};

    for (int r = 0; r < 8; ++r) {
        for (int c = 0; c < 8; ++c) {
            int sq = r * 8 + c;
            bool isLight = ((r + c) % 2) != 0;

            if (sq == selectedSq) {
                glMaterialfv(GL_FRONT, GL_AMBIENT, selAmbient);
                glMaterialfv(GL_FRONT, GL_DIFFUSE, selDiffuse);
                glMaterialfv(GL_FRONT, GL_SPECULAR, selSpecular);
                glMaterialf(GL_FRONT, GL_SHININESS, 60.0f);
            } else if (sq == suggestedSq) {
                glMaterialfv(GL_FRONT, GL_AMBIENT, sugAmbient);
                glMaterialfv(GL_FRONT, GL_DIFFUSE, sugDiffuse);
                glMaterialfv(GL_FRONT, GL_SPECULAR, sugSpecular);
                glMaterialf(GL_FRONT, GL_SHININESS, 55.0f);
            } else if (isLight) {
                glMaterialfv(GL_FRONT, GL_AMBIENT, lightAmbient);
                glMaterialfv(GL_FRONT, GL_DIFFUSE, lightDiffuse);
                glMaterialfv(GL_FRONT, GL_SPECULAR, lightSpecular);
                glMaterialf(GL_FRONT, GL_SHININESS, 40.0f);
            } else {
                glMaterialfv(GL_FRONT, GL_AMBIENT, darkAmbient);
                glMaterialfv(GL_FRONT, GL_DIFFUSE, darkDiffuse);
                glMaterialfv(GL_FRONT, GL_SPECULAR, darkSpecular);
                glMaterialf(GL_FRONT, GL_SHININESS, 40.0f);
            }

            // board string row 0 = rank 1 (white's home rank), like
            // ::board::diagram; the white camera sits at the y = 0 side
            float cx = (float)c + 0.5f;
            float cy = (float)r + 0.5f;
            drawCube(cx, cy, 0.005f, 0.98f, 0.98f, 0.02f);
        }
    }
}

static void drawMarkQuad(int sq, float inset, float z, float r, float g, float b, float a)
{
    if (sq < 0 || sq > 63) return;
    int col = sq % 8;
    int row = sq / 8;
    float x0 = (float)col + 0.02f + inset;
    float x1 = (float)col + 0.98f - inset;
    float y0 = (float)row + 0.02f + inset;
    float y1 = (float)row + 0.98f - inset;
    glColor4f(r, g, b, a);
    glBegin(GL_QUADS);
    glVertex3f(x0, y0, z);
    glVertex3f(x1, y0, z);
    glVertex3f(x1, y1, z);
    glVertex3f(x0, y1, z);
    glEnd();
}


static void drawMarkArrow(int sq, int sq2, float z, float r, float g, float b)
{
    if (sq < 0 || sq > 63 || sq2 < 0 || sq2 > 63) return;
    float fx = (float)(sq % 8) + 0.5f;
    float fy = (float)(sq / 8) + 0.5f;
    float tx = (float)(sq2 % 8) + 0.5f;
    float ty = (float)(sq2 / 8) + 0.5f;
    float dx = tx - fx, dy = ty - fy;
    float len = sqrtf(dx*dx + dy*dy);
    if (len < 1e-4f) return;
    dx /= len; dy /= len;
    float px = -dy, py = dx;
    const float shaftW = 0.10f, headW = 0.26f, headL = 0.42f;
    float ex = tx - dx*headL, ey = ty - dy*headL; // shaft end before the head

    glColor4f(r, g, b, 0.8f);
    glBegin(GL_QUADS);
    glVertex3f(fx - px*shaftW, fy - py*shaftW, z);
    glVertex3f(fx + px*shaftW, fy + py*shaftW, z);
    glVertex3f(ex + px*shaftW, ey + py*shaftW, z);
    glVertex3f(ex - px*shaftW, ey - py*shaftW, z);
    glEnd();
    glBegin(GL_TRIANGLES);
    glVertex3f(tx, ty, z);
    glVertex3f(ex + px*headW, ey + py*headW, z);
    glVertex3f(ex - px*headW, ey - py*headW, z);
    glEnd();
}


// Draw the game marks: a flat list {kind sq sq2 r g b ...} where kind is
// one of f (full/square), c (circle), d (disk), a (arrow).
static void drawMarks(Tcl_Interp* interp, Tcl_Obj* marksObj)
{
    if (marksObj == NULL) return;
    int n = 0;
    if (Tcl_ListObjLength(interp, marksObj, &n) != TCL_OK) return;
    if (n < 6 || (n % 6) != 0) return;

    glDisable(GL_LIGHTING);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    const float markZ = 0.03f;
    for (int i = 0; i + 5 < n; i += 6) {
        Tcl_Obj* kindObj = NULL;
        Tcl_Obj* v[5];
        if (Tcl_ListObjIndex(interp, marksObj, i, &kindObj) != TCL_OK) break;
        int sq = -1, sq2 = -1;
        double r = 1.0, g = 1.0, b = 1.0;
        bool ok = true;
        for (int k = 0; k < 5; ++k) {
            if (Tcl_ListObjIndex(interp, marksObj, i + 1 + k, &v[k]) != TCL_OK) { ok = false; break; }
        }
        if (!ok) break;
        if (Tcl_GetIntFromObj(NULL, v[0], &sq) != TCL_OK
            || Tcl_GetIntFromObj(NULL, v[1], &sq2) != TCL_OK
            || Tcl_GetDoubleFromObj(NULL, v[2], &r) != TCL_OK
            || Tcl_GetDoubleFromObj(NULL, v[3], &g) != TCL_OK
            || Tcl_GetDoubleFromObj(NULL, v[4], &b) != TCL_OK) {
            continue;
        }
        const char* kind = Tcl_GetString(kindObj);
        switch (kind[0]) {
            case 'f': case 's':
                drawMarkQuad(sq, 0.06f, markZ, (float)r, (float)g, (float)b, 0.55f);
                break;
            case 'c':
                drawMarkQuad(sq, 0.22f, markZ, (float)r, (float)g, (float)b, 0.75f);
                break;
            case 'd':
                drawMarkQuad(sq, 0.32f, markZ, (float)r, (float)g, (float)b, 0.9f);
                break;
            case 'a':
                drawMarkArrow(sq, sq2, markZ, (float)r, (float)g, (float)b);
                break;
            default:
                break;
        }
    }

    glDisable(GL_BLEND);
    glEnable(GL_LIGHTING);
}


static void drawPiece(char pieceChar, float x, float y, float lift)
{
    bool isWhite = (pieceChar >= 'A' && pieceChar <= 'Z');
    char lower = isWhite ? (pieceChar + ('a' - 'A')) : pieceChar;

    int pieceIndex = -1;
    switch (lower) {
        case 'p': pieceIndex = 0; break;
        case 'r': pieceIndex = 1; break;
        case 'n': pieceIndex = 2; break;
        case 'b': pieceIndex = 3; break;
        case 'q': pieceIndex = 4; break;
        case 'k': pieceIndex = 5; break;
        default: return;
    }

    if (isWhite) {
        float matAmbient[4]  = {0.35f, 0.30f, 0.22f, 1.0f};
        float matDiffuse[4]  = {0.92f, 0.82f, 0.68f, 1.0f};
        float matSpecular[4] = {0.35f, 0.35f, 0.35f, 1.0f};
        glMaterialfv(GL_FRONT, GL_AMBIENT, matAmbient);
        glMaterialfv(GL_FRONT, GL_DIFFUSE, matDiffuse);
        glMaterialfv(GL_FRONT, GL_SPECULAR, matSpecular);
        glMaterialf(GL_FRONT, GL_SHININESS, 45.0f);
    } else {
        float matAmbient[4]  = {0.12f, 0.08f, 0.05f, 1.0f};
        float matDiffuse[4]  = {0.18f, 0.14f, 0.12f, 1.0f};
        float matSpecular[4] = {0.25f, 0.25f, 0.25f, 1.0f};
        glMaterialfv(GL_FRONT, GL_AMBIENT, matAmbient);
        glMaterialfv(GL_FRONT, GL_DIFFUSE, matDiffuse);
        glMaterialfv(GL_FRONT, GL_SPECULAR, matSpecular);
        glMaterialf(GL_FRONT, GL_SHININESS, 35.0f);
    }

    glPushMatrix();
    glTranslatef(x, y, 0.015f + lift);

    // Orientation: knights face toward the opponent's side
    if (lower == 'n') {
        if (isWhite) {
            glRotatef(-105.0f, 0.0f, 0.0f, 1.0f);
        } else {
            glRotatef(75.0f, 0.0f, 0.0f, 1.0f);
        }
    }

    glCallList(g_pieceDisplayLists[pieceIndex]);
    glPopMatrix();
}

} // anonymous namespace

static int
glboardRenderCmd(ClientData clientData, Tcl_Interp* interp, int objc, Tcl_Obj* const objv[])
{
    // Syntax: ::scidb::tk::glboard_render <toglWidgetName> <boardString> <yaw> <pitch> <distance> ?selected? ?suggested? ?dragFrom? ?dragX? ?dragY? ?marks?
    if (objc < 6) {
        Tcl_WrongNumArgs(interp, 1, objv, "toglName board yaw pitch distance ?selected? ?suggested? ?dragFrom? ?dragX? ?dragY? ?marks?");
        return TCL_ERROR;
    }

    if (!loadToglSymbols(interp)) {
        Tcl_AppendResult(interp, "glboard: Togl symbols not found in process or dynamic library", NULL);
        return TCL_ERROR;
    }

    const char* toglName = Tcl_GetString(objv[1]);
    const char* boardStr = Tcl_GetString(objv[2]);

    double yaw = 0.0, pitch = 56.0, distance = 14.0;
    int selectedSq = -1;
    int suggestedSq = -1;
    int dragFrom = -1;
    double dragX = 0.0, dragY = 0.0;

    if (Tcl_GetDoubleFromObj(interp, objv[3], &yaw) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[4], &pitch) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[5], &distance) != TCL_OK) return TCL_ERROR;
    if (objc >= 7) {
        if (Tcl_GetIntFromObj(interp, objv[6], &selectedSq) != TCL_OK) return TCL_ERROR;
    }
    if (objc >= 8) {
        if (Tcl_GetIntFromObj(interp, objv[7], &suggestedSq) != TCL_OK) return TCL_ERROR;
    }
    if (objc >= 9) {
        if (Tcl_GetIntFromObj(interp, objv[8], &dragFrom) != TCL_OK) return TCL_ERROR;
    }
    if (objc >= 10) {
        if (Tcl_GetDoubleFromObj(interp, objv[9], &dragX) != TCL_OK) return TCL_ERROR;
    }
    if (objc >= 11) {
        if (Tcl_GetDoubleFromObj(interp, objv[10], &dragY) != TCL_OK) return TCL_ERROR;
    }
    Tcl_Obj* marksObj = (objc >= 12) ? objv[11] : NULL;

    struct Togl* togl = NULL;
    if (fn_Togl_GetToglFromName(interp, toglName, &togl) != TCL_OK || !togl) {
        Tcl_AppendResult(interp, "glboard: invalid Togl widget '", toglName, "'", NULL);
        return TCL_ERROR;
    }

    fn_Togl_MakeCurrent(togl);

    int width = fn_Togl_Width(togl);
    int height = fn_Togl_Height(togl);
    if (width <= 0) width = 1;
    if (height <= 0) height = 1;

    compileDisplayLists();

    // Viewport & Projection
    glViewport(0, 0, width, height);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(42.0, (double)width / (double)height, 1.0, 100.0);

    // Camera Modelview: orbit around board center (4.0, 4.0, 0.5)
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    double radYaw = yaw * M_PI / 180.0;
    double radPitch = pitch * M_PI / 180.0;
    if (radPitch < 0.1) radPitch = 0.1;
    if (radPitch > 1.55) radPitch = 1.55;

    double eyeX = 4.0 + distance * cos(radPitch) * sin(radYaw);
    double eyeY = 4.0 - distance * cos(radPitch) * cos(radYaw);
    double eyeZ = 0.5 + distance * sin(radPitch);

    gluLookAt(eyeX, eyeY, eyeZ,  4.0, 4.0, 0.5,  0.0, 0.0, 1.0);

    // Clear background
    glClearColor(0.08f, 0.10f, 0.13f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    glEnable(GL_LIGHT1);
    glEnable(GL_NORMALIZE);
    glShadeModel(GL_SMOOTH);

    // Key Light (warm sun from upper-left)
    float l0Pos[4]      = {15.0f, -10.0f, 25.0f, 1.0f};
    float l0Diffuse[4]  = {1.0f, 0.95f, 0.88f, 1.0f};
    float l0Specular[4] = {0.8f, 0.8f, 0.8f, 1.0f};
    float l0Ambient[4]  = {0.18f, 0.18f, 0.20f, 1.0f};
    glLightfv(GL_LIGHT0, GL_POSITION, l0Pos);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, l0Diffuse);
    glLightfv(GL_LIGHT0, GL_SPECULAR, l0Specular);
    glLightfv(GL_LIGHT0, GL_AMBIENT, l0Ambient);

    // Fill Light (cool fill from upper-right)
    float l1Pos[4]      = {-10.0f, 20.0f, 15.0f, 1.0f};
    float l1Diffuse[4]  = {0.40f, 0.45f, 0.55f, 1.0f};
    float l1Specular[4] = {0.2f, 0.2f, 0.2f, 1.0f};
    glLightfv(GL_LIGHT1, GL_POSITION, l1Pos);
    glLightfv(GL_LIGHT1, GL_DIFFUSE, l1Diffuse);
    glLightfv(GL_LIGHT1, GL_SPECULAR, l1Specular);

    // Render 3D Board
    drawBoard(selectedSq, suggestedSq);

    // game marks on the board plane, under the pieces
    if (marksObj != NULL) {
        drawMarks(interp, marksObj);
    }

    // Render Pieces
    if (strlen(boardStr) >= 64) {
        for (int r = 0; r < 8; ++r) {
            for (int c = 0; c < 8; ++c) {
                // board string row 0 = rank 1 (white's home rank), the same
                // indexing ::board::diagram and ::move use (a1 = 0, h8 = 63);
                // row r is drawn at world y = r, so white sits at the near
                // edge of the default (white) camera
                int boardIdx = r * 8 + c;
                char piece = boardStr[boardIdx];
                if (piece == ' ' || piece == '.' || piece == 0) { continue; }
                if (boardIdx == dragFrom) { continue; } // lifted by the cursor
                float px = (float)c + 0.5f;
                float py = (float)r + 0.5f;
                drawPiece(piece, px, py, 0.0f);
            }
        }
        // the dragged piece hovers over the board at the cursor position
        if (dragFrom >= 0 && dragFrom < 64) {
            char piece = boardStr[dragFrom];
            if (piece != ' ' && piece != '.' && piece != 0) {
                drawPiece(piece, (float)dragX, (float)dragY, 0.75f);
            }
        }
    }

    fn_Togl_SwapBuffers(togl);

    Tcl_SetObjResult(interp, Tcl_NewIntObj(1));
    return TCL_OK;
}

// Pick the board square under screen coordinates (x, y) of the Togl
// widget.  Uses exactly the same projection as glboardRenderCmd, so the
// result matches what the user sees.  Returns the square index in board
// string order (row 0 = rank 8, i.e. row*8+col), or -1 when the ray
// misses the playing surface.
static int
glboardPickCmd(ClientData clientData, Tcl_Interp* interp, int objc, Tcl_Obj* const objv[])
{
    // Syntax: ::scidb::tk::glboard_pick <toglWidgetName> <x> <y> <yaw> <pitch> <distance> ?withWorld?
    if (objc < 7) {
        Tcl_WrongNumArgs(interp, 1, objv, "toglName x y yaw pitch distance ?withWorld?");
        return TCL_ERROR;
    }

    if (!loadToglSymbols(interp)) {
        Tcl_AppendResult(interp, "glboard: Togl symbols not found in process or dynamic library", NULL);
        return TCL_ERROR;
    }

    const char* toglName = Tcl_GetString(objv[1]);
    int x = 0, y = 0;
    double yaw = 0.0, pitch = 56.0, distance = 14.0;
    if (Tcl_GetIntFromObj(interp, objv[2], &x) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetIntFromObj(interp, objv[3], &y) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[4], &yaw) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[5], &pitch) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetDoubleFromObj(interp, objv[6], &distance) != TCL_OK) return TCL_ERROR;

    struct Togl* togl = NULL;
    if (fn_Togl_GetToglFromName(interp, toglName, &togl) != TCL_OK || !togl) {
        Tcl_AppendResult(interp, "glboard: invalid Togl widget '", toglName, "'", NULL);
        return TCL_ERROR;
    }

    fn_Togl_MakeCurrent(togl);

    int width = fn_Togl_Width(togl);
    int height = fn_Togl_Height(togl);
    if (width <= 0 || height <= 0) {
        Tcl_SetObjResult(interp, Tcl_NewIntObj(-1));
        return TCL_OK;
    }

    // Viewport & projection identical to glboardRenderCmd
    glViewport(0, 0, width, height);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(42.0, (double)width / (double)height, 1.0, 100.0);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    double radYaw = yaw * M_PI / 180.0;
    double radPitch = pitch * M_PI / 180.0;
    if (radPitch < 0.1) radPitch = 0.1;
    if (radPitch > 1.55) radPitch = 1.55;

    double eyeX = 4.0 + distance * cos(radPitch) * sin(radYaw);
    double eyeY = 4.0 - distance * cos(radPitch) * cos(radYaw);
    double eyeZ = 0.5 + distance * sin(radPitch);

    gluLookAt(eyeX, eyeY, eyeZ,  4.0, 4.0, 0.5,  0.0, 0.0, 1.0);

    GLdouble model[16], proj[16];
    GLint view[4];
    glGetDoublev(GL_MODELVIEW_MATRIX, model);
    glGetDoublev(GL_PROJECTION_MATRIX, proj);
    glGetIntegerv(GL_VIEWPORT, view);

    // Tk reports y = 0 at the top; OpenGL wants y = 0 at the bottom
    double oglY = (double)(height - 1 - y);

    double nx = 0.0, ny = 0.0, nz = 0.0;
    double fx = 0.0, fy = 0.0, fz = 0.0;
    if (gluUnProject((double)x, oglY, 0.0, model, proj, view, &nx, &ny, &nz) == GL_FALSE
        || gluUnProject((double)x, oglY, 1.0, model, proj, view, &fx, &fy, &fz) == GL_FALSE) {
        Tcl_SetObjResult(interp, Tcl_NewIntObj(-1));
        return TCL_OK;
    }

    // Intersect the pick ray with the tile top plane z = 0.015.  t is the
    // parameter along the near->far unprojected segment (0 = near plane,
    // 1 = far plane), so an intersection behind the near plane means the
    // click is above the horizon.
    double dz = fz - nz;
    if (fabs(dz) < 1e-9) {
        Tcl_SetObjResult(interp, Tcl_NewIntObj(-1));
        return TCL_OK;
    }
    double t = (0.015 - nz) / dz;
    if (t < 0.0) {
        Tcl_SetObjResult(interp, Tcl_NewIntObj(-1));
        return TCL_OK;
    }
    double wx = nx + t * (fx - nx);
    double wy = ny + t * (fy - ny);
    // keep the world position near the board so the dragged piece stays
    // in view even for wild rays
    if (wx < -2.0) { wx = -2.0; } else if (wx > 10.0) { wx = 10.0; }
    if (wy < -2.0) { wy = -2.0; } else if (wy > 10.0) { wy = 10.0; }

    int sq = -1;
    int col = (int)wx;
    int row = (int)wy;
    if (wx >= 0.0 && wx < 8.0 && wy >= 0.0 && wy < 8.0) {
        // board string row 0 = rank 1 (white's home rank), matching
        // ::board::diagram / ::move (a1 = 0, h8 = 63)
        sq = row * 8 + col;
    }

    // optional second result form: {square worldX worldY}, used by the
    // 3D move input to position the dragged piece
    if (objc >= 8) {
        int withWorld = 0;
        if (Tcl_GetBooleanFromObj(interp, objv[7], &withWorld) != TCL_OK) return TCL_ERROR;
        if (withWorld) {
            Tcl_Obj* result[3];
            result[0] = Tcl_NewIntObj(sq);
            result[1] = Tcl_NewDoubleObj(wx);
            result[2] = Tcl_NewDoubleObj(wy);
            Tcl_SetObjResult(interp, Tcl_NewListObj(3, result));
            return TCL_OK;
        }
    }

    Tcl_SetObjResult(interp, Tcl_NewIntObj(sq));
    return TCL_OK;
}


void tk::glboard_init(Tcl_Interp* ti)
{
    tcl::createCommand(ti, "::scidb::tk::glboard_render", glboardRenderCmd);
    tcl::createCommand(ti, "::scidb::tk::glboard_pick", glboardPickCmd);
}

// vi:set ts=4 sw=4:
