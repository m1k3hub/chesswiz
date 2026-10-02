const char* CqlBuild="9.493"; 
const char* CqlVersion="6.2";
#ifndef _WIN32
#ifdef __OPTIMIZE__
const char* CqlOptimizeLevel="Optimized";
#else
const char* CqlOptimizeLevel="Unoptimized";
#endif
#else
const char* CqlOptimizeLevel="";
#endif


