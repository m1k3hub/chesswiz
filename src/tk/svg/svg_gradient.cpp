// ======================================================================
// Author : $Author$
// Version: $Revision: 609 $
// Date   : $Date: 2013-01-02 12:35:19 -0500 (Wed, 02 Jan 2013) $
// Url    : $URL$
// ======================================================================

// ======================================================================
// Copyright: (C) 2008-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "svg_gradient.h"

using namespace svg;


gradient::attr::attr()
	:offset(0.0)
	,opacity(1.0)
	,color(255, 255, 255)
{
}


gradient::gradient()
	:x1(0.0)
	,y1(0.0)
	,x2(100.0)
	,y2(0.0)
	,userSpaceOnUse(false)
{
}

// vi:set ts=3 sw=3:
