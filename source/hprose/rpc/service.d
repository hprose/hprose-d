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
 * hprose/rpc/service.d                                   *
 *                                                        *
 * hprose service library for D.                          *
 *                                                        *
 * LastModified: Jan 5, 2016                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.rpc.service;

import hprose.io;
import hprose.rpc.common;
import hprose.rpc.context;
import hprose.rpc.filter;
import std.conv;
import std.stdio;
import std.string;
import std.traits;
import std.typecons;
import std.variant;

alias RemoteMethod = char delegate(Reader reader, BytesIO output, Context context);
alias OnBeforeInvoke = void delegate(string name, Variant[] args, bool byRef, Context context);
alias OnAfterInvoke = void delegate(string name, Variant[] args, bool byRef, Variant result, Context context);
alias OnSendError = Exception delegate(Exception e, Context context);

class Service {

    private {
        Filter[] _filters;
        RemoteMethod[string] _remoteMethods;
        string[] _allNames;
    }

    bool simple = false;

    bool debugEnabled = false;

    OnBeforeInvoke onBeforeInvoke = null;
    OnAfterInvoke onAfterInvoke = null;
    OnSendError onSendError = null;

    @property ref filters() {
        return this._filters;
    }

    this() {
        this._filters = [];
    }

    private {
        ubyte[] inputFilter(ubyte[] data, Context context) {
            foreach_reverse(filter; _filters) {
                data = filter.inputFilter(data, context);
            }
            return data;
        }

        ubyte[] outputFilter(ubyte[] data, Context context) {
            foreach(filter; _filters) {
                data = filter.outputFilter(data, context);
            }
            return data;
        }

        ubyte[] sendError(Exception e, Context context) {
            try {
                if (onSendError !is null) {
                    Exception ex = onSendError(e, context);
                    if (ex !is null) {
                        e = ex;
                    }
                }
            }
            catch (Exception ex) {
                e = ex;
            }
            BytesIO stream = new BytesIO();
            Writer writer = new Writer(stream, true);
            stream.write(TagError);
            writer.writeString(debugEnabled ? e.toString() : e.msg);
            stream.write(TagEnd);
            return cast(ubyte[])stream.buffer;
        }

        ubyte[] responseEnd(BytesIO data, Context context) {
            return inputFilter(cast(ubyte[])data.buffer, context);
        }
    }

    protected {
        ubyte[] doInvoke(BytesIO input, Context context) {
            Reader reader = new Reader(input);
            BytesIO output = new BytesIO();
            char tag;
            do {
                reader.reset();
                string name = reader.readString!string();
                string aliasName = toLower(name);
                if (aliasName in _remoteMethods) {
                    tag = _remoteMethods[aliasName](reader, output, context);
                }
                else if ("*" in _remoteMethods) {
                    tag = _remoteMethods["*"](reader, output, context);
                }
                else {
                    throw new Exception("Can't find this method " ~ name);
                }
            } while (tag == TagCall);
            if (tag != TagEnd && tag != 0) {
                throw new Exception("Wrong Request: \r\n" ~ input.toString());
            }
            if (tag == TagEnd) {
                output.write(TagEnd);
            }
            return responseEnd(output, context);
        }
        ubyte[] doFunctionList(Context context) {
            BytesIO output = new BytesIO();
            Writer writer = new Writer(output, true);
            output.write(TagFunctions);
            writer.writeList(_allNames);
            output.write(TagEnd);
            return responseEnd(output, context);
        }
        ubyte[] handle(ubyte[] data, Context context) {
            try {
                data = inputFilter(data, context);
                BytesIO input = new BytesIO(data);
                switch (input.read()) {
                    case TagCall: return doInvoke(input, context);
                    case TagEnd: return doFunctionList(context);
                    default: throw new Exception("Wrong Request: \r\n" ~ input.toString());
                }
            }
            catch (Exception e) {
                return sendError(e, context);
            }
        }
    }

    void addFunction(string name, ResultMode mode = ResultMode.Normal, bool simple = false, T)(T func) if (isCallable!T) {
        _remoteMethods[toLower(name)] = delegate(Reader reader, BytesIO output, Context context) {
            alias returnType = ReturnType!T;
            alias paramsType = Parameters!T;
            alias defaultArgs = ParameterDefaults!T;

            Tuple!(paramsType) args;
            foreach (i, ref arg; args) {
                static if (!is(defaultArgs[i] == void)) {
                    arg = defaultArgs[i];
                }
            }

            BytesIO input = reader.stream;
            char tag = input.current;
            bool byRef = false;
            if (tag == TagList) {
                reader.reset();
                reader.readTuple!(paramsType)(args.expand);
            }
            tag = input.read();
            if (tag == TagTrue) {
                byRef = true;
                tag = input.read();
            }
            if (onBeforeInvoke !is null) {
                onBeforeInvoke(name, variantArray(args.expand), byRef, context);
            }
            static if (is(returnType == void)) {
                Variant result = null;
                func(args.expand);
            }
            else {
                returnType result = func(args.expand);
            }
            if (onAfterInvoke !is null) {
                onAfterInvoke(name, variantArray(args.expand), byRef, cast(Variant)result, context);
            }
            static if (mode == ResultMode.RawWithEndTag) {
                output.write(cast(ubyte[])result);
                return 0;
            }
            else static if (mode == ResultMode.Raw) {
                output.write(cast(ubyte[])result);
            }
            else {
                output.write(TagResult);
                Writer writer = new Writer(output, simple);
                static if (mode == ResultMode.Serialized) {
                    output.write(cast(ubyte[])result);
                }
                else {
                    writer.serialize(result);
                }
            }
            return tag;
        };
        _allNames ~= name;
    }

    void addFunction(string name, bool simple, T)(T func) if (isCallable!T) {
        addFunction!(name, ResultMode.Normal, simple)(func);
    }

    void addFunctions(string[] names, ResultMode mode = ResultMode.Normal, bool simple = false, T...)(T funcs) if (names.length == T.length && ((T.length > 1) || (T.length == 1) && isCallable!T)) {
        addFunction!(names[0], mode, simple)(funcs[0]);
        static if (names.length > 1) {
            addFunctions!(names[1..$], mode, simple)(funcs[1..$]);
        }
    }

    void addFunctions(string[] names, bool simple, T...)(T funcs) if (names.length == T.length && ((T.length > 1) || (T.length == 1) && isCallable!T)) {
        addFunctions!(names, ResultMode.Normal, simple)(funcs);
    }

    void addMethod(string name, string aliasName = "", ResultMode mode = ResultMode.Normal, bool simple = false, T)(T obj) if (is(T == class) && !isCallable!T) {
        addFunction!((aliasName == "" ? name : aliasName), mode, simple)(mixin("&obj." ~ name));
    }

    void addMethod(string name, ResultMode mode, bool simple = false, T)(T obj) if (is(T == class) && !isCallable!T) {
        addMethod!(name, "", mode, simple)(obj);
    }

    void addMethod(string name, bool simple, T)(T obj) if (is(T == class) && !isCallable!T) {
        addMethod!(name, "", ResultMode.Normal, simple)(obj);
    }

    void addMethod(T, string name, string aliasName = "", ResultMode mode = ResultMode.Normal, bool simple = false)() if (is(T == class) && !isCallable!T) {
        addFunction!((aliasName == "" ? name : aliasName), mode, simple)(mixin("&T." ~ name));
    }

    void addMethod(T, string name, ResultMode mode, bool simple = false)() if (is(T == class) && !isCallable!T) {
        addMethod!(T, name, "", mode, simple)();
    }

    void addMethod(T, string name, bool simple)() if (is(T == class) && !isCallable!T) {
        addMethod!(T, name, "", ResultMode.Normal, simple)();
    }

    void addMethods(string[] names, string[] aliasNames = null, ResultMode mode = ResultMode.Normal, bool simple = false, T)(T obj) if (is(T == class) && !isCallable!T && (names.length > 0) && ((names.length == aliasNames.length) || (aliasNames == null))) {
        static if (aliasNames == null) {
            addMethod!(names[0], "", mode, simple)(obj);
            static if (names.length > 1) {
                addMethods!(names[1..$], null, mode, simple)(obj);
            }
        }
        else {
            addMethod!(names[0], aliasNames[0], mode, simple)(obj);
            static if (names.length > 1) {
                addMethods!(names[1..$], aliasNames[1..$], mode, simple)(obj);
            }
        }
    }

    void addMethods(string[] names, ResultMode mode, bool simple = false, T)(T obj) if (is(T == class) && !isCallable!T && (names.length > 0)) {
        addMethods!(names, null, mode, simple)(obj);
    }

    void addMethods(string[] names, string[] aliasNames, bool simple, T)(T obj) if (is(T == class) && !isCallable!T && (names.length > 0) && ((names.length == aliasNames.length) || (aliasNames == null))) {
        addMethods!(names, aliasNames, ResultMode.Normal, simple)(obj);
    }

    void addMethods(string[] names, bool simple, T)(T obj) if (is(T == class) && !isCallable!T && (names.length > 0)) {
        addMethods!(names, null, ResultMode.Normal, simple)(obj);
    }

    void addMethods(U = void, string prefix = "", ResultMode mode = ResultMode.Normal, bool simple = false, T)(T obj = null) if ((is(T == class) && (is(U == void) || is(T : U)) && !isCallable!T) || (is(T == typeof(null)) && is(U == class))) {
        static if (is(U == void)) {
            alias B = Object;
            alias C = T;
        }
        else {
            alias B = BaseClassesTuple!U[0];
            alias C = U;
        }
        static if (is(T == typeof(null))) {
            foreach (M; __traits(allMembers, C)) {
                static if (__traits(compiles, mixin("typeof(&U." ~ M ~ ")"))) {
                    static if (!__traits(hasMember, B, M) || !__traits(isSame, __traits(getMember, B, M), __traits(getMember, C, M))) {
                        mixin("alias MT = typeof(&U." ~ M ~ ");");
                        static if (isCallable!MT) {
                            addFunction!((prefix == "" ? M : prefix ~ '_' ~ M), mode, simple)(mixin("&U." ~ M));
                        }
                    }
                }
            }
        }
        else {
            foreach (M; __traits(allMembers, C)) {
                static if (__traits(compiles, mixin("typeof(&obj." ~ M ~ ")"))) {
                    static if (!__traits(hasMember, B, M) || !__traits(isSame, __traits(getMember, B, M), __traits(getMember, C, M))) {
                        mixin("alias MT = typeof(&obj." ~ M ~ ");");
                        static if (isCallable!MT) {
                            addFunction!((prefix == "" ? M : prefix ~ '_' ~ M), mode, simple)(mixin("&obj." ~ M));
                        }
                    }
                }
            }
        }
    }

    void addMethods(string prefix, ResultMode mode = ResultMode.Normal, bool simple = false, T)(T obj) if (is(T == class) && !isCallable!T) {
        addMethods!(void, prefix, mode, simple)(obj);
    }

    void addMethods(ResultMode mode, bool simple = false, T)(T obj) if (is(T == class) && !isCallable!T) {
        addMethods!(void, "", mode, simple)(obj);
    }

    void addMethods(string prefix, bool simple, T)(T obj) if (is(T == class) && !isCallable!T) {
        addMethods!(void, prefix, ResultMode.Normal, simple)(obj);
    }

    void addMethods(bool simple, T)(T obj) if (is(T == class) && !isCallable!T) {
        addMethods!(void, "", ResultMode.Normal, simple)(obj);
    }

    void addMethods(U, ResultMode mode, bool simple = false)() if (is(U == class) && !isCallable!U) {
        addMethods!(U, "", mode, simple)();
    }

    void addMethods(U, string prefix, bool simple)() if (is(U == class) && !isCallable!T) {
        addMethods!(U, prefix, ResultMode.Normal, simple)();
    }

    void addMethods(U, bool simple)() if (is(U == class) && !isCallable!U) {
        addMethods!(U, "", ResultMode.Normal, simple)();
    }

    void addStaticMethods(U, string prefix = "", ResultMode mode = ResultMode.Normal, bool simple = false)() if (is(U == class) && !isCallable!U) {
        addMethods!(U, prefix, mode, simple)();
    }

    void addStaticMethods(U, ResultMode mode, bool simple = false)() if (is(U == class) && !isCallable!U) {
        addMethods!(U, "", mode, simple)();
    }

    void addStaticMethods(U, string prefix, bool simple)() if (is(U == class) && !isCallable!T) {
        addMethods!(U, prefix, ResultMode.Normal, simple)();
    }

    void addStaticMethods(U, bool simple)() if (is(U == class) && !isCallable!U) {
        addMethods!(U, "", ResultMode.Normal, simple)();
    }

    void addInstanceMethods(U = void, string prefix = "", ResultMode mode = ResultMode.Normal, bool simple = false, T)(T obj) if (is(T == class) && (is(U == void) || is(T : U)) && !isCallable!T) {
        static if (is(U == void)) {
            alias B = Object;
            alias C = T;
        }
        else {
            alias B = BaseClassesTuple!U[0];
            alias C = U;
        }
        foreach (M; __traits(allMembers, C)) {
            static if (__traits(compiles, mixin("typeof(&obj." ~ M ~ ")"))) {
                static if (!__traits(hasMember, B, M) || !__traits(isSame, __traits(getMember, B, M), __traits(getMember, C, M))) {
                    mixin("alias MT = typeof(&obj." ~ M ~ ");");
                    static if (isCallable!MT && !__traits(isStaticFunction, __traits(getMember, C, M))) {
                        addFunction!((prefix == "" ? M : prefix ~ '_' ~ M), mode, simple)(mixin("&obj." ~ M));
                    }
                }
            }
        }
    }

    void addInstanceMethods(U, ResultMode mode, bool simple = false, T)(T obj) if (is(T == class) && (is(U == void) || is(T : U)) && !isCallable!T) {
        addInstanceMethods!(U, "", mode, simple)(obj);
    }

    void addInstanceMethods(U, string prefix, bool simple, T)(T obj) if (is(T == class) && (is(U == void) || is(T : U)) && !isCallable!T) {
        addInstanceMethods!(U, prefix, ResultMode.Normal, simple)(obj);
    }

    void addInstanceMethods(U, bool simple, T)(T obj) if (is(T == class) && (is(U == void) || is(T : U)) && !isCallable!T) {
        addInstanceMethods!(U, "", ResultMode.Normal, simple)(obj);
    }

    void addInstanceMethods(ResultMode mode, bool simple = false, T)(T obj) if (is(T == class) && !isCallable!T) {
        addInstanceMethods!(void, "", mode, simple)(obj);
    }

    void addInstanceMethods(string prefix, bool simple, T)(T obj) if (is(T == class) && !isCallable!T) {
        addInstanceMethods!(void, prefix, ResultMode.Normal, simple)(obj);
    }

    void addInstanceMethods(bool simple, T)(T obj) if (is(T == class) && !isCallable!T) {
        addInstanceMethods!(void, "", ResultMode.Normal, simple)(obj);
    }

    alias addFunction add;
    alias addFunctions add;
    alias addMethod add;
    alias addMethods add;
}