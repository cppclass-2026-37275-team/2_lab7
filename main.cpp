#include <iostream>
#include "dayOfYear.h"

namespace KimYeonjin2693058
{
    void parVal(dayOfYear d){d+=1;}
    void parRef(dayOfYear& r) {r+=1;}
    void parPtr(dayOfYear* p){*p+=1;}

    dayOfYear retVal(dayOfYear d) {d+=1; return d;}
    dayOfYear& retRef(dayOfYear& r) {r+=1; return r;}
    dayOfYear* retPtr(dayOfYear* p) {*p+=1; return p;}    
}

int main()
{
    using namespace KimYeonjin2693058;
    dayOfYear d{10, 19}; std::cout << d;
    parVal(d); std::cout << d;
    dayOfYear& r{d}; std::cout << r;
    parRef(r); std::cout << r;
    dayOfYear* p{&d};std::cout << *p;
    parPtr(p); std::cout << *p;
    std::cout << std::endl;

    d = dayOfYear{10, 26};
    std::cout << d;
    std::cout << retVal(d);
    std::cout << r;
    std::cout << retRef(r);
    std::cout << *p;
    std::cout << *retPtr(p);

    dayOfYear* ptr{ new dayOfYear};
    ptr->setMonth(10);
    ptr->setDay(30);
    std::cout << *ptr;
    delete ptr;
    
    return 0;
}