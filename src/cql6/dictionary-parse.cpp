#include "dictionary.h"
#include "dictionaryaccessnode.h"
#include "tokens.h"
#include "node.h"

/*matches either DictionaryRetrieveNode, dictionary, or DictionaryAssignNode:
  dic
  dic[foo]
  dic[foo]=bar
*/
Node* Tokens::match_dictionaryretrieveorassign(){
  int x=save();
  Dictionary* dictionary=match_dictionary();
  if(!dictionary)return NULL;
  string name=dictionary->name;
  if (!match_lbracket()){
    restore(x);
    return NULL;
  }
  Node*key=match_node();
  if (!key)
    show_error("could not parse filter after dictionary [: ",name);
  ValueType keytype=key->valuetype();
  if(keytype==ValueType::None||keytype==ValueType::Logical){
    show_error("The type of the key in dict[key] must be set, number, position, or string. This key has no allowed value");
  }
  if(!dictionary->verifyKey(key))
    show_error("Attempt to access dictionary with key of wrong type");
  if (!match_rbracket())
    show_error("expected ']' following 'dictionaryname [ filter': ",name);
  uassert(dictionary->keyType==key->valuetype(),
	  "unexpected key/key type mismatch");
  /* Now we have parsed: dictionary[key]. */
  /*check that if the key type is position, the the dictionary is a local dictionary*/
  if(keytype==ValueType::Position&&dictionary->isPersistent())
    show_error("Attempt to use a position-valued key for a dictionary that is not a local dictionary");
  /* Two cases: retrieval or assignment*/
  /*case 1: retrieval*/
  if (!match_special("=")){
    return new DictionaryRetrieveNode(dictionary,key);
  }
  /* end case 1*/

  /*Case 2: assignment: dictionary[key]=value*/
  Node*value=match_node();
  if (!value)
    show_error("missing node following 'dictionaryname[key]='");
  if(dictionary->keyType!=ValueType::None
     &&dictionary->keyType!=keytype)
    show_error("key of wrong type in 'dictionaryname[key]=v'. Does not match previous key for this dictionary");
  ValueType vtype=value->valuetype();
  if (vtype==ValueType::Position&&dictionary->isPersistent())
    show_error("Attempt to insert a position value into a dictionary that is not a local dictionary");
  if(vtype==ValueType::None||vtype==ValueType::Logical)
    show_error("value not assignable type in 'dictionaryname[key]=value'");
  if(dictionary->valueType!=ValueType::None&&
     dictionary->valueType!=vtype)
    show_error("value type does not match previous assignment value type to dictionary in 'dictionaryname[key]=value");
  dictionary->setTypes(keytype,vtype);
    
  return new DictionaryAssignNode(dictionary,key,value);
}

/*match a dictionary use of the type:
   dictionary d
   local dictionary d
   persistent dictionary d
   d
*/

Dictionary* Tokens::match_dictionary(){
  Dictionary*dictionary=match_dictionary_variable();
  if(dictionary)return dictionary;
  int x=save();

  bool ispersistent{false};
  if(match_keyword("local"))
    ispersistent=false;
  else if(match_keyword("persistent"))
    ispersistent=true;
  else
    ispersistent=true;
    
  if(!match_keyword("dictionary")){
    restore(x);
    return NULL;
  }

  string name=match_id();
  if (name.size()==0)
    show_error("expected name after keyword 'dictionary'");
  Variable*v=environment->find(name);
  if(v&&!v->isDictionary())
    show_error("The variable "s+name+" is already in use as a non-dictionary and should not be preceded by 'dictionary'");
  if(v&&v->isDictionary()){
    Dictionary*dv=dynamic_cast<Dictionary*>(v);
    uassert(dv,"expected a dictionary in match_dictionary");
    if(dv->isPersistent()!=ispersistent)
      show_error("persistence mismatch for 'dictionary '"s
		 +name);
    return dv;
  }
  uassert(!v,"match_dictionary internal name");
  if(0)cout<<"match_dictionary: creating dictionary with name: "<<name <<" and ispersistent: "<<ispersistent<<endl;
  
  return environment->createDictionary(name,ispersistent);
}//match_dictionary

Dictionary* Tokens::match_dictionary_variable(){
  int x=save();
  string name=match_id();
  if(name=="")return NULL;
  Variable*v=environment->find(name);
  if(!v||!v->isDictionary()){
    restore(x);
    return NULL;
  }
  Dictionary*ret=dynamic_cast<Dictionary*>(v);
  uassert(ret,"expected dictionar in match_dv");
  return ret;
}
  
  
    

Node*Tokens::match_dictionaryiterator(){
  Node*old=match_dictionaryiterator61();
  if(old)return old;
  int x=save();
  string name=match_id();
  if(name==""){
    restore(x);
    return NULL;}
  if (!match_element()){
    restore(x);
    return NULL;
  }
  Dictionary*d=match_dictionary();
  if(!d){
    restore(x);
    return NULL;
  }
  if(match_lbracket()){ //check for x[element]D[2] for set valued D[2]
    restore(x);
    return NULL;
  }
  if(d->keyType==ValueType::None||d->valueType==ValueType::None)
    show_error("type of dictionary is not yet set. You must first assign to a dictionary before using 'varname [element] dictionaryname body'");
  Variable* v=environment->find(name);
  string errmess;
  if(!v){
    v=environment->createVariable(name,d->keyType,false,errmess);
    if(errmess!="")
      show_error("variable creation failed in 'var [element] dictionaryname body': "s
		 +errmess);
  }
  uassert(v,"expected nonnull v in dictionary iterator parse");
  if(v->valuetype()!=d->keyType)
    show_error("type of variable in dictionary iterator "s
	       +Node::valuetypeToString(v->valuetype())
	       +" does not match that of the key of the dictionary "
	       + Node::valuetypeToString(d->keyType));
  Node*body=match_node();
  if(!body)
    show_error("Expected filter following '[type] var in dictionaryname'");
  return new DictionaryIterateNode(d,v,body);
}


//This must precede match_unbind, the more general version, because match_unbind() fails with a dictionary argument
Node*Tokens::match_dictionary_unbind(){
  int x=save();
  if(!match_keyword("unbind")) //add 'clear' later
    return NULL;
  Dictionary* dictionary=match_dictionary();
  if(!dictionary){
    restore(x);
    return NULL;
  }
  if(match_lbracket()){
    Node*key=match_node();
    if(!key)
      show_error("expected a node following 'dictionaryname[");
    if(dictionary->keyType==ValueType::None||
       dictionary->keyType!=key->valuetype())
      show_error("In attempting to clear a dictionary entry with 'unbind dict[key]', the key is of invalid type or does not match the type of a previous key assignment");
    if(!match_rbracket())
      show_error("missing right bracket following 'unbind dictionaryname[key'");
    return new DictionaryDeleteEntryNode(dictionary,key);
  }
  return new DictionaryDeleteDictionaryNode(dictionary);
}
  
/*this handles the case of string Key in Dictionary for back-compatibility*/
Node*Tokens::match_dictionaryiterator61(){
  int x=save();
  if(!match_keyword("string")){
    restore(x);
    return NULL;
  }
  string name=match_id();
  if(name==""){
    restore(x);
    return NULL;}
  if (!match_keyword("in")){
    restore(x);
    return NULL;
  }

  Dictionary*d=match_dictionary();
  if(!d){
    restore(x);
    return NULL;
  }
  if(d->keyType!=ValueType::String)
    show_error("type of dictionary must be string here for 'string x in D'");
  Variable* v=environment->find(name);
  string errmess;
  if(!v){
    v=environment->createVariable(name,ValueType::String,false,errmess);
    if(errmess!="")
      show_error("variable creation failed in '[type] var in dictionaryname body'");
  }
  uassert(v,"expected nonnull v in dictionary iterator parse");
  if(v->valuetype()!=d->keyType)
    show_error("variable in dictionary iterator does not match that of the key of the dictionary");
  Node*body=match_node();
  if(!body)
    show_error("Expected filter following '[type] var in dictionaryname'");
  return new DictionaryIterateNode(d,v,body);
}
