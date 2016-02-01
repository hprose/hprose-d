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
 * LastModified: Feb 1, 2016                              *
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

alias OnBeforeInvoke = void delegate(string name, Variant[] args, bool byRef, Context context);
alias OnAfterInvoke = void delegate(string name, Variant[] args, bool byRef, Variant result, Context context);
alias OnSendError = Exception delegate(Exception e, Context context);

alias NextInvokeHandler = Variant delegate(string name, ref Variant[] args, Context context);
alias InvokeHandler = Variant delegate(string name, ref Variant[] args, Context context, NextInvokeHandler next);

alias NextIOHandler = ubyte[] delegate(ubyte[] request, Context context);
alias IOHandler = ubyte[] delegate(ubyte[] request, Context context, NextIOHandler next);

class Service {

    private {
        alias RemoteMethod = char delegate(string, Reader, BytesIO, Context);
        Filter[] _filters;
        RemoteMethod[string] _remoteMethods;
        string[] _allNames;
    }

    bool simple = false;

    bool debugEnabled = false;

    OnBeforeInvoke onBeforeInvoke = null;
    OnAfterInvoke onAfterInvoke = null;
    OnSendError onSendError = null;
    InvokeHandler[] invokeHandlers = [];
    IOHandler[] beforeFilterHandlers = [];
    IOHandler[] afterFilterHandlers = [];
    NextIOHandler beforeFilterHandler;
    NextIOHandler afterFilterHandler;

    @property ref filters() {
        return this._filters;
    }

    this() {
        this._filters = [];
        beforeFilterHandler = &beforeFilter;
        afterFilterHandler = &afterFilter;
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
                    tag = _remoteMethods[aliasName](name, reader, output, context);
                }
                else if ("*" in _remoteMethods) {
                    tag = _remoteMethods["*"](name, reader, output, context);
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
            return cast(ubyte[])output.buffer;
        }

        ubyte[] doFunctionList() {
            BytesIO output = new BytesIO();
            Writer writer = new Writer(output, true);
            output.write(TagFunctions);
            writer.writeList(_allNames);
            output.write(TagEnd);
            return cast(ubyte[])output.buffer;
        }

        ubyte[] afterFilter(ubyte[] data, Context context) {
            try {
                BytesIO input = new BytesIO(data);
                switch (input.read()) {
                    case TagCall: return doInvoke(input, context);
                    case TagEnd: return doFunctionList();
                    default: throw new Exception("Wrong Request: \r\n" ~ input.toString());
                }
            }
            catch (Exception e) {
                return sendError(e, context);
            }
        }

        ubyte[] beforeFilter(ubyte[] data, Context context) {
            try {
                data = inputFilter(data, context);
                data = afterFilterHandler(data, context);
                return outputFilter(data, context);
            }
            catch (Exception e) {
                return outputFilter(sendError(e, context), context);
            }
        }

        ubyte[] handle(ubyte[] data, Context context) {
            return beforeFilterHandler(data, context);
        }
    }

    void addFunction(string name, ResultMode mode = ResultMode.Normal, bool simple = false, T)(T func) if (isCallable!T && (name != "*" || is(ReturnType!T == Variant) && Parameters!T.length >= 2 && is(Parameters!T[0] == string) && is(Parameters!T[1] == Variant[]))) {
        _remoteMethods[toLower(name)] = delegate(string aliasName, Reader reader, BytesIO output, Context context) {
            alias returnType = ReturnType!T;
            alias paramsType = Parameters!T;
            alias defaultArgs = ParameterDefaults!T;

            Tuple!(paramsType) args;
            foreach (i, ref arg; args) {
                static if (!is(defaultArgs[i] == void)) {
                    arg = defaultArgs[i];
                }
            }

            static if (is(paramsType[$ - 1] : Context)) {
                args[$ - 1] = cast(paramsType[$ - 1])context;
            }

            static if (name == "*") {
                args[0] = aliasName;
            }

            BytesIO input = reader.stream;
            char tag = input.read();
            bool byRef = false;
            if (tag == TagList) {
                reader.reset();
                static if (name == "*") {
                    args[1] = reader.readArrayWithoutTag!(Variant[])();
                }
                else static if (is(paramsType[$ - 1] : Context)) {
                    reader.readTupleWithoutTag(args[0 .. $ - 1]);
                }
                else {
                    reader.readTupleWithoutTag(args.expand);
                }
                tag = input.read();
                if (tag == TagTrue) {
                    byRef = true;
                    tag = input.read();
                }
            }
            if (onBeforeInvoke !is null) {
                static if (name == "*") {
                    onBeforeInvoke(aliasName, args[1], byRef, context);
                }
                else {
                    onBeforeInvoke(aliasName, variantArray(args.expand), byRef, context);
                }
            }
            static if (is(returnType == void)) {
                Variant result = null;
            }
            else {
                returnType result;
            }
            if (invokeHandlers.length == 0) {
                static if (is(returnType == void)) {
                    func(args.expand);
                }
                else {
                    result = func(args.expand);
                }
            }
            else {
                NextInvokeHandler next = delegate Variant(string name, ref Variant[] args, Context context) {
                    Tuple!(paramsType) _args;
                    foreach (i, ref arg; _args) {
                        arg = args[i].get!(paramsType[i]);
                    }
                    Variant result;
                    static if (is(returnType == void)) {
                        func(_args.expand);
                        result = null;
                    }
                    else {
                        result = cast(Variant)(func(_args.expand));
                    }
                    foreach (i, ref arg; _args) {
                        args[i] = cast(Variant)arg;
                    }
                    return result;
                };

                foreach (handler; invokeHandlers) {
                    next = (delegate(NextInvokeHandler next, InvokeHandler handler) {
                        return delegate Variant(string name, ref Variant[] args, Context context) {
                            return handler(name, args, context, next);
                        };
                        })(next, handler);
                }

                Variant[] _args = variantArray(args.expand);

                static if (is(returnType == void)) {
                    next(name, _args, context);
                }
                else static if (is(returnType == Variant)) {
                    result = next(name, _args, context);
                }
                else {
                    result = next(name, _args, context).get!(returnType);
                }

                foreach (i, ref arg; args) {
                    arg = _args[i].get!(paramsType[i]);
                }
            }

            if (onAfterInvoke !is null) {
                static if (name == "*") {
                    onAfterInvoke(aliasName, args[1], byRef, result, context);
                }
                else {
                    onAfterInvoke(aliasName, variantArray(args.expand), byRef, cast(Variant)result, context);
                }
            }
            static if (mode == ResultMode.RawWithEndTag) {
                static if (is(returnType == Variant)) {
                    output.write(result.get!(ubyte[]));
                }
                else {
                    output.write(cast(ubyte[])result);
                }
                return 0;
            }
            else static if (mode == ResultMode.Raw) {
                static if (is(returnType == Variant)) {
                    output.write(result.get!(ubyte[]));
                }
                else {
                    output.write(cast(ubyte[])result);
                }
            }
            else {
                output.write(TagResult);
                Writer writer = new Writer(output, simple);
                static if (mode == ResultMode.Serialized) {
                    static if (is(returnType == Variant)) {
                        output.write(result.get!(ubyte[]));
                    }
                    else {
                        output.write(cast(ubyte[])result);
                    }
                }
                else {
                    writer.serialize(result);
                }
                static if (name == "*") {
                    if (byRef) {
                        output.write(TagArgument);
                        writer.reset();
                        writer.writeArray(args[1]);
                    }
                }
                else static if ((paramsType.length > 1) || (paramsType.length == 1) && is(paramsType[$ - 1] : Context)) {
                    if (byRef) {
                        output.write(TagArgument);
                        writer.reset();
                        static if (is(paramsType[$ - 1] : Context)) {
                             writer.writeTuple(args[0 .. $ - 1]);
                        }
                        else {
                            writer.writeTuple(args.expand);
                        }
                    }
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

    void addMethod(string name, T, string aliasName = "", ResultMode mode = ResultMode.Normal, bool simple = false)() if (is(T == class) && !isCallable!T) {
        addFunction!((aliasName == "" ? name : aliasName), mode, simple)(mixin("&T." ~ name));
    }

    void addMethod(string name, T, ResultMode mode, bool simple = false)() if (is(T == class) && !isCallable!T) {
        addMethod!(name, T, "", mode, simple)();
    }

    void addMethod(string name, T, bool simple)() if (is(T == class) && !isCallable!T) {
        addMethod!(name, T, "", ResultMode.Normal, simple)();
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

    void addMissingFunction(ResultMode mode = ResultMode.Normal, bool simple = false, T)(T func) if (isCallable!T && is(ReturnType!T == Variant) && Parameters!T.length >=2 && is(Parameters!T[0] == string) && is(Parameters!T[1] == Variant[])) {
        addFunction!("*", mode, simple)(func);
    }

    void addMissingFunction(bool simple, T)(T func) if (isCallable!T && is(ReturnType!T == Variant) && Parameters!T.length >=2 && is(Parameters!T[0] == string) && is(Parameters!T[1] == Variant[])) {
        addMissingFunction!(ResultMode.Normal, simple)(func);
    }
    
    void addMissingMethod(string name, ResultMode mode = ResultMode.Normal, bool simple = false, T)(T obj) if (is(T == class) && !isCallable!T) {
        addMissingFunction!(mode, simple)(mixin("&obj." ~ name));
    }

    void addMissingMethod(string name, bool simple, T)(T obj) if (is(T == class) && !isCallable!T) {
        addMissingMethod!(name, ResultMode.Normal, simple)(obj);
    }

    void addMissingMethod(string name, T, ResultMode mode = ResultMode.Normal, bool simple = false)() if (is(T == class) && !isCallable!T) {
        addMissingFunction!(mode, simple)(mixin("&T." ~ name));
    }

    void addMissingMethod(string name, T, bool simple)() if (is(T == class) && !isCallable!T) {
        addMissingMethod!(name, T, ResultMode.Normal, simple)();
    }

    alias addFunction add;
    alias addFunctions add;
    alias addMethod add;
    alias addMethods add;

    void use(InvokeHandler[] handler...) {
        if (handler !is null) {
            invokeHandlers ~= handler;
        }
    }
    void use(string when)(IOHandler[] handler...) if ((when == "beforeFilter") || (when == "afterFilter")) {
        if (handler !is null) {
            mixin(
                when ~ "Handlers ~= handler;\r\n" ~
                when ~ "Handler = &" ~ when ~ ";\r\n" ~
                "foreach (h; " ~ when ~ "Handlers) {\r\n" ~
                "    " ~ when ~ "Handler = (delegate(NextIOHandler next, IOHandler handler) {\r\n" ~
                "        return delegate ubyte[](ubyte[] request, Context context) {\r\n" ~
                "            return handler(request, context, next);\r\n" ~
                "        };\r\n" ~
                "    })(" ~ when ~ "Handler, h);\r\n" ~
                "}\r\n"
            );
        }
    }
}