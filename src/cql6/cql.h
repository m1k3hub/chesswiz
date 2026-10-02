#pragma once
extern const char * CqlVersion;
extern const char * CqlBuild;
extern const char * CqlOptimizeLevel;

void parseargs(int argc, char*argv[]);
void cql_initialize();
void versionInitialize();
void cqlglobals_initialize();
void hhdb_parse_option(int& nextarg, int argc, char *argv[]);

