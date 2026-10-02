#include "converttoexternal.h"
#ifdef CQL6_EMBEDDED // scidb: file lockdown during embedded searches
#include "scidb_lockdown.h"
#endif

#include "util.h"
#include "cqlassert.h"
#include <fstream>
#include "converttocolorize.h"
using std::ofstream;

string ConvertToExternal::escape(const string&cqlstring){
  stringstream s;
  for(char c:cqlstring){
    if (c=='<')
      s<<"&lt;";
    else if (c=='>')
      s<<"&gt;";
    else if (c=='&')
      s<<"&amp;";
    else
      s<<c;
  }
  return s.str();
}

void ConvertToExternal::exporthtml(const string filename){
#ifdef CQL6_EMBEDDED // scidb: no file access during an embedded search
  scidb::file_guard("ConvertToExternal::exporthtml", filename.c_str());
#endif
  uassert(filename_is_cql(filename),"html exporthtml: argument is not a cql filename");
  string stem=filename_stem(filename);
  if(stem.empty())
    eassert(false, "could not get the base name of the filename: "s+filename);
  string outputfile=stem+"-cql.html";
  stringstream s;
  cout<<"Converting to external html file: "<<filename<<endl;
  string contents=util::string_from_filename(filename);
  int filesize=(int)(contents.size());
  cout<<"In html export: read "<<filesize<<" bytes"<<endl;
  string escaped=ConvertToColorize::convert(contents);
  const string prefix=
    R"~++~(
<html>
 <head>
  <meta charset="UTF-8">
  <title="TTTT">
  <link rel="stylesheet"
        type="text/css"
        href="http://gadycosteff.com/externalcss/pygments.css">
  <link rel="stylesheet" 
        type="text/css" 
        href="http://gadycosteff.com/externalcss/external.css">
 </head>
<body>
  <pre class="highlight">
   <span class="c">
   /* Automatically generated from TTTT using 
             cql -html TTTT
      <p>Note: to verify that the correct font is used,
      check that there is a stem on the lower right of 
      this capital U and that this grid has squares in two colors: &#x25A6;
       */</span>
   </pre>
   <pre class="highlight">
)~++~";
  string newprefix=util::replaceAll(prefix,"TTTT",outputfile);
  s<<newprefix
   <<escaped
   << "</pre></body></html>\n";
  string output=s.str();
  cout<<"html export: opening file for writing: "<<outputfile<<endl;
  ofstream*streamp=new ofstream(outputfile);
  if(!streamp->good())
    eassert(false,"html: could not open file for writing: ",outputfile);
  *streamp<<output;
  eassert(streamp->good(),"html: write failed to: ",outputfile);
  streamp->flush();
  eassert(streamp->good(),"html: write flush failed to: ",outputfile);
  cout<<"html export: wrote "<<output.size()<<" bytes to: "<<outputfile<<endl;
}
    

