#pragma once
template <class T> void myinsert(vector<T>&v, const T& t){
  for(auto e: v)
    if (e==t) return;
  v.push_back(t);
}

template <class T> int myindex(const vector<T>&v, const T& t){
  for(int i=0;i<v.size();++i)
    if(v[i]==t)return i;
  return -1;
}

template <class T> int myindex(const vector<const T>&v, const T& t){
  for(int i=0;i<v.size();++i)
    if(v[i]==t)return i;
  return -1;
}

template <class T> int mycount(const vector<T>&v, const T& t){
  int count=0;
  for (int i=0; i<(int)(v.size());++i)
    if (t==v.at(i))++count;
  return count;
}

template <class T> bool myisset(const vector<T>&v){
  for (int i=0;i<(int)(v.size());++i){
    int count = mycount<T>(v,v.at(i));
    if (count!=1) return false;
  }
  return true;
}

template<class T> void myprint(const vector<T>&v){
  int s =(int)(v.size());
  cout<<"Printing vector of size: "<<s<<endl;
  for(int i=0;i<s;++i){
    cout<<" Entry "<<i<<" of "<<s<<endl;
    v.at(i)->print();
  }
  cout<<"\nDone printing vector of size: "<<s;
}
    
  
