//this file is to be #included inside the class declaration of util.h

template<class T> static bool member(const vector<T>&  elts, const T& elt){
  return std::find(elts.begin(), elts.end(), elt)!= elts.end();
}
