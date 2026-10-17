// Classic .cba quotation move replay. See docs/formats/re/cba-quotation-format.md.
#ifndef _cbh_quotation_included
#define _cbh_quotation_included

#include "m_string.h"

namespace db { namespace cbh {

// Decode a complete standard-start quotation to numbered SAN. On malformed,
// illegal, or unsupported data return false without changing the output.
bool decodeQuotationMoves(unsigned char const* bytes, unsigned length, mstl::string& san);

} }
#endif

