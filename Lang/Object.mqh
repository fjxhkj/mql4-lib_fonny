//+------------------------------------------------------------------+
//|                                                       Object.mqh |
//|                                          Copyright 2015, Li Ding |
//|                                             http://dingmaotu.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2015, Li Ding"
#property link      "http://dingmaotu.com"
#property strict

#include "Integer.mqh"
//+------------------------------------------------------------------+
//| Base class for all complicated objects in this library           |
//+------------------------------------------------------------------+
class Object
  {
public:
                     Object() {}
   virtual          ~Object() {}
   virtual string    toString() const {return StringFormat("[Object #%d]",hash());}
   virtual int       hash() const;
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
struct ObjectPointer
  {
   Object           *pointer;
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int Object::hash(void) const
  {
   ObjectPointer p;
   p.pointer=(Object*)GetPointer(this);
   return ((LargeInt)p).lowPart;
  }
//+------------------------------------------------------------------+