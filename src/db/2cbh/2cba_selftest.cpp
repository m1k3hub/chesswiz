
// 2cba_selftest.cpp -- parse sampled .2cba records with the production
// parser and emit the items for cross-validation against Python.
#include "2cbh_annotations.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>

static std::string g_cbag, g_cba;
static bool loadFile(char const* n, std::string& d) {
   FILE* f = fopen(n, "rb");
   if (!f) return false;
   fseek(f, 0, SEEK_END);
   long sz = ftell(f);
   fseek(f, 0, SEEK_SET);
   d.resize(sz);
   if (sz) fread(&d[0], 1, sz, f);
   fclose(f);
   return true;
}

int main(int argc, char** argv)
{
   if (argc < 4) { ::fprintf(stderr, "usage: 2cba_selftest <prefix> <ids> <out>\n"); return 1; }
   std::string prefix(argv[1]);
   if (!loadFile((prefix + ".2cbh").c_str(), g_cbag)) { ::fprintf(stderr, "no 2cbh\n"); return 1; }
   if (!loadFile((prefix + ".2cba").c_str(), g_cba)) { ::fprintf(stderr, "no 2cba\n"); return 1; }
   FILE* f = fopen(argv[2], "r");
   FILE* out = ::fopen(argv[3], "w");
   unsigned long k;
   unsigned long cbaOff;
   unsigned long ds;
   while (::fscanf(f, "%lu %lu %lu", &k, &cbaOff, &ds) == 3)
   {
      unsigned char const* arec = (unsigned char const*) g_cba.c_str() + cbaOff;
      mstl::vector<db::cb2::CbaItem> items;
      bool complete = db::cb2::parseCbaItems(arec + 0x1a, uint32_t(ds), items);
      ::fprintf(out, "G %lu %d %zu\n", k, complete ? 1 : 0, items.size());
      for (size_t i = 0; i < items.size(); ++i)
      {
         // replace newlines to keep the line format
         mstl::string t = items[i].text;
         ::fprintf(out, "I %u %u %u\n", items[i].position, items[i].nag, unsigned(t.size()));
         ::fprintf(out, "T ");
         for (unsigned j = 0; j < t.size(); ++j)
         {
            if (t[j] == '\n') ::fprintf(out, "\\n");
            else if (t[j] == '\r') ::fprintf(out, "\\r");
            else ::fputc(t[j], out);
         }
         ::fprintf(out, "\n");
      }
   }
   ::fclose(f);
   ::fclose(out);
   return 0;
}
