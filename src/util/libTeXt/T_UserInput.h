// ======================================================================
// Author : $Author$
// Version: $Revision: 609 $
// Date   : $Date: 2013-01-02 12:35:19 -0500 (Wed, 02 Jan 2013) $
// Url    : $URL$
// ======================================================================

// ======================================================================
// Copyright: (C) 2009-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#ifndef _TeXt_UserInput_included
#define _TeXt_UserInput_included

#include "T_Input.h"

#include "m_string.h"

namespace TeXt {

class Environment;

class UserInput : public Input
{
public:

	UserInput(mstl::string const& text);

	Source source() const override;

	bool readNextLine(mstl::string& result) override;

private:

	mstl::string m_text;
};

} // namespace TeXt

#endif // _TeXt_UserInput_included

// vi:set ts=3 sw=3:
