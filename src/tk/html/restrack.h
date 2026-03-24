// ======================================================================
// Author : $Author$
// Version: $Revision: 1 $
// Date   : $Date: 2011-05-03 20:04:08 -0400 (Tue, 03 May 2011) $
// Url    : $URL$
// ======================================================================

#ifndef __RESTRACK_H__
#define __RESTRACK_H__

#include <tcl.h>

char * Rt_Alloc(const char * ,int);
char * Rt_Realloc(const char *, char *, int);
void Rt_Free(char *);

Tcl_ObjCmdProc Rt_AllocCommand;
Tcl_ObjCmdProc HtmlHeapDebug;

#endif

