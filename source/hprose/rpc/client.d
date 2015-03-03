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
 * hprose/rpc/client.d                                    *
 *                                                        *
 * hprose client library for D.                           *
 *                                                        *
 * LastModified: Mar 3, 2015                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.rpc.client;

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

private {
    pure string generate(T, string namespace)() {
        alias FA = FunctionAttribute;
        alias STC = ParameterStorageClass;
        string code = "new class T {\n";
        enum methods = getAbstractMethods!(T);
        foreach(m; methods) {
            foreach(mm; __traits(getVirtualMethods, T, m)) {
                string name = m;
                ResultMode mode = ResultMode.Normal;
                bool simple = false;
                code ~= "    override ";
                enum attrs = __traits(getAttributes, mm);
                foreach (attr; attrs) {
                    static if (is(typeof(attr) == MethodName)) {
                        name = attr.value;
                    }
                    else static if (is(typeof(attr) == ResultMode)) {
                        mode = attr;
                    }
                    else static if (is(typeof(attr) == Simple)) {
                        simple = attr.value;
                    }
                }
                alias paramTypes = ParameterTypeTuple!(mm);
                alias paramStors = ParameterStorageClassTuple!(mm);
                alias paramIds = ParameterIdentifierTuple!(mm);
                alias paramValues = ParameterDefaultValueTuple!(mm);
                alias returntype = ReturnType!(mm);
                code ~= returntype.stringof ~ " " ~ m ~ "(";
                bool byref = false;
                foreach(i, p; paramTypes) {
                    static if (i > 0) {
                        code ~= ", ";
                    }
                    static if (paramStors[i] == STC.out_ || paramStors[i] == STC.ref_) {
                        byref = true;
                    }
                    static if (paramIds[i] != "") {
                        code ~= p.stringof ~ " " ~ paramIds[i];
                    }
                    else {
                        code ~= p.stringof ~ " arg" ~ to!string(i);
                    }
                    static if (!is(paramValues[i] == void)) {
                        code ~= " = " ~ paramValues[i].stringof;
                    }
                }
                code ~= ") {\n";
                static if (is(returntype == void)) {
                    static if (paramTypes.length > 0 && is(paramTypes[$-1] == return)) {
                        alias Callback = paramTypes[$-1];
                        alias callbackParams = ParameterTypeTuple!Callback;
                        static if (callbackParams.length == 1) {
                            code ~= "        invoke!(" ~ Callback.stringof ~ ", ";
                        }
                        else static if (callbackParams.length > 1) {
                            code ~= "        invoke!(" ~ ParameterTypeTuple!Callback[0].stringof ~ ", ";
                            foreach(s; ParameterStorageClassTuple!Callback) {
                                static if (s == STC.out_ || s == STC.ref_) {
                                    byref = true;
                                }
                            }
                            code ~= to!string(byref) ~ ", ";
                        }
                        else {
                            static assert(0, "can't support this callback type: " ~ Callback.stringof);
                        }
                        code ~= "ResultMode." ~ to!string(mode) ~ ", " ~
                                to!string(simple) ~ ")(\"";
                    }
                    else {
                        code ~= "        invoke!(" ~ returntype.stringof ~ ", " ~
                            to!string(byref) ~ ", " ~
                                "ResultMode." ~ to!string(mode) ~ ", " ~
                                to!string(simple) ~ ")(\"";
                    }
                }
                else {
                    code ~= "        return invoke!(" ~ returntype.stringof ~ ", " ~
                        to!string(byref) ~ ", " ~
                            "ResultMode." ~ to!string(mode) ~ ", " ~
                            to!string(simple) ~ ")(\"";
                }
                static if (namespace != "") {
                    code ~= namespace ~ "_";
                }
                code ~= name ~ "\"" ;
                foreach(i, id; paramIds) {
                    static if (id != "") {
                        code ~= ", " ~ id;
                    }
                    else {
                        code ~= ", arg" ~ to!string(i);
                    }
                }
                code ~= ");\n";
                code ~= "    }\n";
            }
        }
        code ~= "}\n";
        return code;
    }

    pure string asyncInvoke(bool byref, bool hasargs)() {
        string code = "foreach(T; Args) static assert(isSerializable!T);\n";
        code ~= "auto context = new Context();\n";
        code ~= "auto request = doOutput!(" ~ to!string(byref) ~ ", simple)(name, context, args);\n";
        code ~= "sendAndReceive(request, delegate(ubyte[] response) {\n";
        code ~= "        auto result = doInput!(Result, mode)(response, context, args);\n";
        code ~= "        callback(result" ~ (hasargs ? ", args" : "") ~ ");\n";
        code ~= "    });\n";
        return code;
    }
}

class Client {
    private {
        Filter[] _filters;
        ubyte[] doOutput(bool byref = false, bool simple = false, Args...)(string name, Context context, ref Args args) {
            auto bytes = new BytesIO();
            auto writer = new Writer(bytes, simple);
            bytes.write(TagCall);
            writer.writeString(name);
            if (args.length > 0 || byref) {
                writer.reset();
                writer.writeTuple(args);
                static if (byref) {
                    writer.writeBool(true);
                }
            }
            bytes.write(TagEnd);
            auto request = cast(ubyte[])(bytes.buffer);
            bytes.close();
            foreach(filter; filters) {
                request = filter.outputFilter(request, context);
            }
            return request;
        }
        Result doInput(Result, ResultMode mode = ResultMode.Normal, Args...)(ubyte[]response, Context context, ref Args args) if (mode == ResultMode.Normal || is(Result == ubyte[])) {
            foreach_reverse(filter; filters) {
                response = filter.inputFilter(response, context);
            }
            static if (mode == ResultMode.RawWithEndTag) {
                return response;
            }
            else static if (mode == ResultMode.Raw) {
                return response[0..$-1];
            }
            else {
                auto bytes = new BytesIO(response);
                auto reader = new Reader(bytes);
                Result result;
                char tag;
                while((tag = bytes.read()) != TagEnd) {
                    switch(tag) {
                        case TagResult: {
                            static if (mode == ResultMode.Serialized) {
                                result = cast(ubyte[])(reader.readRaw().buffer);
                            }
                            else {
                                reader.reset();
                                result = reader.unserialize!Result();
                            }
                            break;
                        }
                        case TagArgument: {
                            reader.reset();
                            reader.readTuple(args);
                            break;
                        }
                        case TagError: {
                            reader.reset();
                            throw new Exception(reader.unserialize!string());
                        }
                        default: {
                            throw new Exception("Wrong Response: \r\n" ~ cast(string)response);
                        }
                    }
                }
                bytes.close();
                return result;
            }
        }
    }
    protected {
        string uri;
        abstract ubyte[] sendAndReceive(ubyte[] request);
        abstract void sendAndReceive(ubyte[] request, void delegate(ubyte[]) callback);
    }
    this(string uri = "") {
        this.uri = uri;
        this._filters = [];
    }
    void useService(string uri = "") {
        if (uri != "") {
            this.uri = uri;
        }
    }
    T useService(T, string namespace = "")(string uri = "") if (is(T == interface) || is(T == class)) {
        useService(uri);
        return mixin(generate!(T, namespace));
    }
    Result invoke(Result, bool byref = false, ResultMode mode = ResultMode.Normal, bool simple = false, Args...)
        (string name, Args args) if (args.length > 0 && byref == false && !is(typeof(args[$-1]) == return) &&
        (mode == ResultMode.Normal || is(Result == ubyte[]))) {
        static if (is(Result == void)) {
            invoke!(Result, byref, mode, simple)(name, args);
        }
        else {
            return invoke!(Result, byref, mode, simple)(name, args);
        }
    }
    Result invoke(Result, bool byref = false, ResultMode mode = ResultMode.Normal, bool simple = false, Args...)
        (string name, ref Args args) if (((args.length == 0) || !is(typeof(args[$-1]) == return)) &&
        (mode == ResultMode.Normal || is(Result == ubyte[]))) {
        foreach(T; Args) static assert(isSerializable!(T));
        auto context = new Context();
        auto request = doOutput!(byref, simple)(name, context, args);
        static if (is(Result == void)) {
            sendAndReceive(request, delegate(ubyte[] response) {
                    doInput!(Variant, mode)(response, context, args);
                });
        }
        else {
            return doInput!(Result, mode)(sendAndReceive(request), context, args);
        }
    }
    void invoke(Callback, ResultMode mode = ResultMode.Normal, bool simple = false, Args...)
    (string name, Args args, Callback callback) if (is(Callback R == void delegate(R)) && (mode == ResultMode.Normal || is(Result == ubyte[]))) {
        alias Result = ParameterTypeTuple!callback[0];
        mixin(asyncInvoke!(false, false));
    }
    void invoke(Result, bool byref = false, ResultMode mode = ResultMode.Normal, bool simple = false, Args...)
    (string name, Args args, void delegate(Result result, Args args) callback) if (args.length > 0 && (mode == ResultMode.Normal || is(Result == ubyte[]))) {
        mixin(asyncInvoke!(byref, true));
    }
    void invoke(Result, bool byref = true, ResultMode mode = ResultMode.Normal, bool simple = false, Args...)
    (string name, ref Args args, void delegate(Result result, ref Args args) callback) if (args.length > 0 && (mode == ResultMode.Normal || is(Result == ubyte[]))) {
        mixin(asyncInvoke!(byref, true));
    }
    void invoke(Callback, ResultMode mode = ResultMode.Normal, bool simple = false, Args...)
    (string name, Args args, Callback callback) if (is(Callback R == void function(R)) && (mode == ResultMode.Normal || is(Result == ubyte[]))) {
        alias Result = ParameterTypeTuple!callback[0];
        mixin(asyncInvoke!(false, false));
    }
    void invoke(Result, bool byref = false, ResultMode mode = ResultMode.Normal, bool simple = false, Args...)
    (string name, Args args, void function(Result result, Args args) callback) if (args.length > 0 && (mode == ResultMode.Normal || is(Result == ubyte[]))) {
        mixin(asyncInvoke!(byref, true));
    }
    void invoke(Result, bool byref = true, ResultMode mode = ResultMode.Normal, bool simple = false, Args...)
    (string name, ref Args args, void function(Result result, ref Args args) callback) if (args.length > 0 && (mode == ResultMode.Normal || is(Result == ubyte[]))) {
        mixin(asyncInvoke!(byref, true));
    }
    @property ref filters() {
        return this._filters;
    }
}
