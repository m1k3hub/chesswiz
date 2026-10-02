CQL source distribution

COMPILING CQL
-------------
To make:

    make cql

COMPILING FOR LINUX
--------------------
For Linux distributions, remove the initial '#' character
in the line:

    #LINUXPTHREADOPTION = -pthread

located in the file

    makefile-flags

Otherwise, an error mentioning "pthread" may result when compiling. This
is due to differences in the clang and gcc compiler options.

Also, uncomment the line beginning
 # OSFLAGS=

in the file makefile-flags.

Note to Linux users: Should additional changes to makefile-flags be necessary, please inform
us.

DOCUMENTATION
------------
This source distribution includes only minimal source code documentation.
Contact the authors if you want to modify the source code and would like
additional documentation.

LICENSE
-------

 All the files in the subdirectory orig/ are by Shane Hudson and
 were distributed under the GNU License version 2. 

 The file origChanges.cpp consists of minor modifications to those files.

 All other files are Copyright Lewis Stiller and Gady Costeff and except as
 specified all rights are reserved.

 For documentation, see http://www.gadycosteff.com/cql
 
  
