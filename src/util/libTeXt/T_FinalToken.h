// ======================================================================
// Author : $Author$
// Version: $Revision: 1449 $
// Date   : $Date: 2017-12-06 08:17:54 -0500 (Wed, 06 Dec 2017) $
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

#ifndef _TeXt_FinalToken_included
#define _TeXt_FinalToken_included

#include "T_Token.h"

namespace TeXt {

class FinalToken : public Token
{
public:

	bool isFinal() const override;

	void bind(Environment& env) override;
	void resolve(Environment& env) override;
	void expand(Environment& env) override;
	void execute(Environment& env) override;

protected:

	virtual void perform(Environment& env) = 0;
};

} // namespace TeXt

#endif // _TeXt_FinalToken_included

// vi:set ts=3 sw=3:
