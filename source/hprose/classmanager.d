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
 * LastModified: Feb 15, 2015                             *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.classmanager;
@trusted:

import hprose.common;
import hprose.reader;
import std.container.util;
import std.stdio;
import std.traits;
import std.variant;

package interface Unserializer {
    Variant get();
    void setRef();
    void setField(string name);
}

private synchronized class classmanager {
    private {
        TypeInfo[string] nameCache;
        string[TypeInfo] typeCache;
        Unserializer delegate(Reader reader)[TypeInfo] unserializerCache;
    }
    string register(T)(string name) {
        if (name !in nameCache) {
            nameCache[name] = cast(shared)typeid(Unqual!T);
            typeCache[typeid(Unqual!T)] = name;
            unserializerCache[typeid(Unqual!T)] = delegate(Reader reader) {
                class UnserializerImpl: Unserializer {
                    private {
                        Unqual!T value = make!(Unqual!T);
                        @safe void delegate()[string] setters;
                    }
                    this() {
                        enum fieldList = getSerializableFields!(Unqual!T);
                        foreach(f; fieldList) {
                            setters[f] = delegate() {
                                __traits(getMember, value, f) = reader.unserialize!(typeof(__traits(getMember, value, f)))();
                            };
                        }
                    }
                    Variant get() {
                        return Variant(value);
                    }
                    void setRef() {
                        static if (is(T == struct)) {
                            reader.setRef(null);
                        }
                        else {
                            reader.setRef(value);
                        }
                    }
                    void setField(string name) {
                        if (name in setters) {
                            setters[name]();
                        }
                        else {
                            reader.unserialize!Variant();
                        }
                    }
                }
                return new UnserializerImpl();
            };
        }
        return name;
    }
    TypeInfo getClass(string name) {
        return (cast(TypeInfo[string])nameCache).get(name, null);
    }
    Unserializer getUnserializer(TypeInfo t, Reader reader) {
        if (t in unserializerCache) {
            return unserializerCache[t](reader);
        }
        return null;
    }
    string getAlias(T)() {
        return (cast(string[TypeInfo])typeCache).get(typeid(Unqual!T), register!T(Unqual!T.stringof));
    }
}

static shared classmanager ClassManager = new shared classmanager();

private {
    class MyClass { int a; }
    class MyClass2 { int a; }
}

unittest {
    ClassManager.register!(MyClass)("Apple");
    assert(ClassManager.getAlias!(MyClass) == "Apple");
    assert(ClassManager.getAlias!(MyClass2) == "MyClass2");
    assert(ClassManager.getClass("Apple") is typeid(MyClass));
    assert(ClassManager.getClass("MyClass2") is typeid(MyClass2));
}
