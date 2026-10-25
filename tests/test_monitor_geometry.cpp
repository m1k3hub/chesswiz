// Run: c++ -std=c++11 -Wall -Wextra tests/test_monitor_geometry.cpp -o /tmp/test-monitor-geometry && /tmp/test-monitor-geometry
#include "../src/tk/tk_monitor_geometry.h"
#include <cassert>
#include <iostream>
using namespace monitor_geometry;
static void check(Rectangle a, Rectangle b, Rectangle expected) {
	Rectangle r = intersect(a,b);
	assert(r.x == expected.x && r.y == expected.y);
	assert(r.width == expected.width && r.height == expected.height);
}
int main() {
	check(Rectangle(0,0,3840,1080),Rectangle(1920,0,1920,1080),Rectangle(1920,0,1920,1080));
	check(Rectangle(0,30,3840,1050),Rectangle(0,0,1920,1080),Rectangle(0,30,1920,1050));
	check(Rectangle(-1920,-200,3840,1280),Rectangle(-1920,-200,1920,1080),Rectangle(-1920,-200,1920,1080));
	check(Rectangle(-1900,-170,3800,1200),Rectangle(-1920,-200,1920,1080),Rectangle(-1900,-170,1900,1050));
	check(Rectangle(0,0,3840,1600),Rectangle(1920,400,1920,1080),Rectangle(1920,400,1920,1080));
	check(Rectangle(0,0,100,100),Rectangle(100,0,100,100),Rectangle(100,0,0,100));
	check(Rectangle(0,0,100,100),Rectangle(200,200,100,100),Rectangle(200,200,0,0));
	check(Rectangle(0,0,1920,1080),Rectangle(0,0,1920,1080),Rectangle(0,0,1920,1080));
	assert(distance(Rectangle(-1920,-200,1920,1080),-1,0)==0);
	assert(distance(Rectangle(-1920,-200,1920,1080),0,0)==1);
	assert(distance(Rectangle(0,0,1920,1080),0,0)==0);
	assert(distance(Rectangle(1920,400,1920,1080),2000,200)==40000);
	std::cout << "monitor geometry: 12 checks passed\n";
}
