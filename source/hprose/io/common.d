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
 * hprose/io/common.d                                     *
 *                                                        *
 * hprose common library for D.                           *
 *                                                        *
 * LastModified: Jul 15, 2015                             *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.io.common;
@safe:

import std.stdio;
import std.traits;
import std.typecons;
import std.typetuple;

template make(T)
if (is(T == struct) || is(T == class)) {
    T make(Args...)(Args arguments)
    if (is(T == struct) && __traits(compiles, T(arguments))) {
        return T(arguments);
    }
    
    T make(Args...)(Args arguments)
    if (is(T == class) && __traits(compiles, new T(arguments))) {
        return new T(arguments);
    }
}

template isSerializable(T) {
    alias U = Unqual!T;
    static if (is(U == typeof(null)) ||
        isBasicType!U ||
        isSomeString!U ||
        is(U == struct)) {
        enum isSerializable = true;
    }
    else static if (is(U == class) && !isAbstractClass!U
        && __traits(compiles, { new U; })) {
        enum isSerializable = true;
    }
    else static if (isArray!U) {
        enum isSerializable = isSerializable!(ForeachType!U);
    }
    else static if (isAssociativeArray!U) {
        enum isSerializable = isSerializable!(KeyType!U) && isSerializable!(ValueType!U);
    }
    else {
        enum isSerializable = false;
    }
}

template isSerializableField(T) if (is(T == struct) || is(T == class)) {
    template isSerializableField(string M) {
        static if (__traits(hasMember, T, M) && is(typeof(__traits(getMember, T, M)))) {
            alias U = typeof(__traits(getMember, T, M));
            enum isSerializableField = isAssignable!U && isSerializable!U &&
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
        enum getSerializableFields = tuple(Filter!(isSerializableField!T, allMembers));
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
