/**********************************************************\
|                                                          |
|                          hprose                          |
|                                                          |
| Official WebSite: http://www.hprose.com/                 |
|                   http://www.hprose.org/                 |
|                                                          |
\**********************************************************/

/**********************************************************\
 *                                                        *
 * hprose/classmanager.d                                  *
 *                                                        *
 * hprose classmanager library for D.                     *
 *                                                        *
 * LastModified: Aug 1, 2014                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.classmanager;
@trusted:

import std.stdio;
import std.traits;


private synchronized class classmanager {
    private TypeInfo[string] nameCache;
    private string[TypeInfo] typeCache;
    string register(T)(string name) {
        if (name !in nameCache) {
            nameCache[name] = cast(shared)typeid(Unqual!(T));
            typeCache[typeid(Unqual!(T))] = name;
        }
        return name;
    }
    TypeInfo getClass(string name) {
        return cast(TypeInfo)nameCache.get(name, null);
    }
    string getAlias(T)() {
        return typeCache.get(typeid(Unqual!(T)), register!(T)(Unqual!(T).stringof));
    }
}

static shared classmanager ClassManager = new shared classmanager();

unittest {
    class MyClass {}
    class MyClass2 {}
    ClassManager.register!(MyClass)("Apple");
    assert(ClassManager.getAlias!(MyClass) == "Apple");
    assert(ClassManager.getAlias!(MyClass2) == "MyClass2");
    assert(ClassManager.getClass("Apple") is typeid(MyClass));
    assert(ClassManager.getClass("MyClass2") is typeid(MyClass2));
}