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
 * hprose/io/classmanager.d                               *
 *                                                        *
 * hprose classmanager library for D.                     *
 *                                                        *
 * LastModified: Jan 3, 2016                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.io.classmanager;

import hprose.io.common;
import hprose.io.reader;
import std.stdio;
import std.traits;
import std.variant;
import std.typecons;

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
                        Unqual!T value = make!(Unqual!T)();
                        @safe void delegate()[string] setters;
                    }
                    private void genSetters(alias fieldList)() {
                        static if (fieldList.length > 0) {
                            enum f = fieldList[0];
                            setters[f] = delegate() {
                                __traits(getMember, value, f) = reader.unserialize!(typeof(__traits(getMember, value, f)))();
                            };
                            static if (fieldList.length > 1) {
                                genSetters!(tuple(fieldList[1..$]))();
                            }
                        }
                    }
                    this() {
                        genSetters!(getSerializableFields!(Unqual!T))();
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
    string getAlias(T)() {
        return (cast(string[TypeInfo])typeCache).get(typeid(Unqual!T), register!T(Unqual!T.stringof));
    }
    package Unserializer getUnserializer(TypeInfo t, Reader reader) {
        if (t in unserializerCache) {
            return unserializerCache[t](reader);
        }
        return null;
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
