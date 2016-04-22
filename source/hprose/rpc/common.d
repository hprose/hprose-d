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
 * hprose/rpc/common.d                                    *
 *                                                        *
 * hprose common library for D.                           *
 *                                                        *
 * LastModified: Apr 22, 2016                             *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.rpc.common;

import hprose.rpc.context;
import std.stdio;
import std.variant;
import std.traits;
import std.typecons;
import std.typetuple;

alias NextInvokeHandler = Variant delegate(string name, ref Variant[] args, Context context);
alias InvokeHandler = Variant delegate(string name, ref Variant[] args, Context context, NextInvokeHandler next);

alias NextFilterHandler = ubyte[] delegate(ubyte[] request, Context context);
alias FilterHandler = ubyte[] delegate(ubyte[] request, Context context, NextFilterHandler next);

struct MethodName {
    string value;
}

enum ResultMode {
    Normal, Serialized, Raw, RawWithEndTag
}

struct Simple {
    bool value = true;
}

template isAbstractMethod(T) if (is(T == interface) || is(T == class)) {
    template isAbstractMethod(string M) {
        static if (__traits(hasMember, T, M) && __traits(compiles, __traits(getMember, T, M))) {
            enum isAbstractMethod = __traits(isAbstractFunction, mixin("T." ~ M));
            
        }
        else {
            enum isAbstractMethod = false;
        }
    }
}

template getAbstractMethods(T) if (is(T == interface) || is(T == class)) {
    enum allMembers = __traits(allMembers, T);
    static if (allMembers.length > 0) {
        enum getAbstractMethods = tuple(Filter!(isAbstractMethod!T, allMembers));
    }
    else {
        static assert(0, T.stringof ~ " has no virtual methods");
    }
}
