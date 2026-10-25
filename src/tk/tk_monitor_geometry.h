// Exact, signed root-coordinate geometry shared by the X11 adapter and tests.
#ifndef TK_MONITOR_GEOMETRY_H
#define TK_MONITOR_GEOMETRY_H
#include <algorithm>
namespace monitor_geometry {
struct Rectangle {
	int x, y, width, height;
	Rectangle(int x_=0, int y_=0, int w=0, int h=0)
		: x(x_), y(y_), width(w), height(h) {}
};
inline Rectangle intersect(Rectangle const& a, Rectangle const& b) {
	int x = std::max(a.x, b.x), y = std::max(a.y, b.y);
	return Rectangle(x, y,
		std::max(0, std::min(a.x+a.width, b.x+b.width)-x),
		std::max(0, std::min(a.y+a.height, b.y+b.height)-y));
}
// Half-open monitor bounds give an unambiguous owner at a shared edge.
// In gaps in a staggered arrangement use the nearest monitor.
inline long long distance(Rectangle const& r, int x, int y) {
	long long dx = x < r.x ? r.x-x : x >= r.x+r.width ? x-(r.x+r.width-1) : 0;
	long long dy = y < r.y ? r.y-y : y >= r.y+r.height ? y-(r.y+r.height-1) : 0;
	return dx*dx + dy*dy;
}
}
#endif
