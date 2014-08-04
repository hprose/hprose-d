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
 * hprose/common.d                                        *
 *                                                        *
 * hprose common library for D.                           *
 *                                                        *
 * LastModified: Aug 1, 2014                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.common;
@safe:

import std.typecons;
import std.traits;
import std.typetuple;
import std.stdio;

enum ResultMode {
    Normal, Serialized, Raw, RawWithEndTag
}

template isSerializable(T) {
    static if (is(T == typeof(null)) ||
               isBasicType!(T) ||
               isSomeString!(T) ||
               is(T == struct)) {
        enum isSerializable = true;
    }
    else static if (is(T == class) && !isAbstractClass!(T)
                    && __traits(compiles, { new T; })) {
        enum isSerializable = true;
    }
    else static if (isArray!(T)) {
        enum isSerializable = isSerializable!(Unqual!(ForeachType!(T)));
    }
    else static if (isAssociativeArray!(T)) {
        enum isSerializable = isSerializable!(Unqual!(KeyType!(T))) && isSerializable!(Unqual!(ValueType!(T)));
    }
    else {
        enum isSerializable = false;
    }
}

template isSerializableField(T) if (is(T == struct) || is(T == class)) {
    template isSerializableField(string M) {
        static if (__traits(hasMember, T, M) && is(typeof(__traits(getMember, T, M)))) {
            alias U = typeof(__traits(getMember, T, M));
            enum isSerializableField = isAssignable!(U) && isSerializable!(U) &&
                !__traits(compiles, { mixin("(T)." ~ M ~ " = (U).init;"); }) &&
                __traits(compiles, { mixin("const T x = T.init; U y = x." ~ M ~ ";"); });
        }
        else {
            enum isSerializableField = false;
        }
    }
}

template getSerializableFields(T) if (is(T == struct) || is(T == class)) {
    enum allMembers = __traits(allMembers, T);
    static if (allMembers.length > 0) {
        enum getSerializableFields = tuple(Filter!(isSerializableField!(T), allMembers));
    }
    else {
        enum getSerializableFields = tuple();
    }
}


private struct MyStruct { int a; };

private class MyClass { int a; this(int a) {}; this() {}; };

unittest {
    assert(getSerializableFields!(MyStruct) == tuple("a"));
    assert(getSerializableFields!(MyClass) == tuple("a"));
}