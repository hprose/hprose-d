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
 * LastModified: Feb 14, 2015                             *
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
    alias U = Unqual!T;
    static if (is(U == typeof(null)) ||
        isBasicType!(U) ||
        isSomeString!(U) ||
        is(U == struct)) {
        enum isSerializable = true;
    }
    else static if (is(U == class) && !isAbstractClass!(U)
        && __traits(compiles, { new U; })) {
        enum isSerializable = true;
    }
    else static if (isArray!(U)) {
        enum isSerializable = isSerializable!(ForeachType!(U));
    }
    else static if (isAssociativeArray!(U)) {
        enum isSerializable = isSerializable!(KeyType!(U)) && isSerializable!(ValueType!(U));
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
        static assert(0, T.stringof ~ " has no fields");
    }
}


private {

    struct MyStruct { int a; };

    class MyClass { int a; this(int a) {}; this() {}; };

}

unittest {
    assert(getSerializableFields!(MyStruct) == tuple("a"));
    assert(getSerializableFields!(MyClass) == tuple("a"));
}
