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
 * hprose/rpc/httpclient.d                                *
 *                                                        *
 * hprose http client library for D.                      *
 *                                                        *
 * LastModified: Mar 3, 2015                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.rpc.httpclient;

import hprose.rpc.client;
import hprose.rpc.common;
import std.conv;
import std.stdio;
import std.traits;
import std.typecons;
import std.variant;
import vibe.http.client;
import vibe.stream.operations;

class HttpClient: Client {
    private {
        HTTPClientSettings settings = new HTTPClientSettings;
    }
    alias settings this;
    protected {
        override ubyte[] sendAndReceive(ubyte[] request) {
            return requestHTTP(uri, 
                (scope HTTPClientRequest req) {
                    req.method = HTTPMethod.POST;
                    req.writeBody(request, "application/hprose");
                },
                settings).bodyReader.readAll();
        }
        override void sendAndReceive(ubyte[] request, void delegate(ubyte[]) callback) {
            requestHTTP(uri,
                (scope HTTPClientRequest req) {
                    req.method = HTTPMethod.POST;
                    req.writeBody(request, "application/hprose");
                },
                (scope HTTPClientResponse resp) {
                    callback(resp.bodyReader.readAll());
                },
                settings);
        }
    }
    this(string uri = "") {
        super(uri);
    }
}

unittest {
    import hprose.rpc.filter;
    import hprose.rpc.context;

    interface Hello {
        @Simple() @(ResultMode.Normal) string hello(string name);
        @MethodName("hello") void asyncHello(string name);
        void hello(string name, void delegate(string result) callback);
        void hello(string name, void delegate(string result, string name) callback);
        void hello(string name, void delegate(string result, ref string name) callback);
        void hello(string name, void function(string result) callback);
        void hello(string name, void function(string result, string name) callback);
        void hello(string name, void function(string result, ref string name) callback);
    }
    auto client = new HttpClient("http://hprose.com/example/index.php");
    Hello proxy = client.useService!Hello();
    client.filters ~= new class Filter {
        override ubyte[] inputFilter(ubyte[] data, Context context) {
            writeln(cast(string)data);
            return data;
        }

        override ubyte[] outputFilter(ubyte[] data, Context context) {
            writeln(cast(string)data);
            return data;
        };
    };
    string name = "world";
    writeln(proxy.hello("proxy sync"));
    proxy.asyncHello("proxy async");
    proxy.hello("proxy async1", (result) { writeln(result); });
    proxy.hello("proxy async2", (result, arg0) { writeln(result); writeln(arg0); });
    proxy.hello("proxy async3", (result, ref arg0) { writeln(result); writeln(arg0); });
    proxy.hello("proxy async4", function(result) { writeln(result); });
    proxy.hello("proxy async5", function(result, arg0) { writeln(result); writeln(arg0); });
    proxy.hello("proxy async6", function(result, ref arg0) { writeln(result); writeln(arg0); });

    client.invoke!(void)("hello", "马秉尧");
    client.invoke("hello", "async1", "async1", delegate(string result) { writeln(result); });
    client.invoke("hello", "async2", "async2", delegate(string result, string arg1, string arg2) { writeln(result); writeln(arg1); writeln(arg2); });
    client.invoke("hello", name, delegate(string result, string arg1) { writeln(result); writeln(arg1); });
    client.invoke("hello", name, delegate(string result, ref string arg1) { writeln(result); writeln(arg1); });
    client.invoke("hello", "async3", function(string result) { writeln(result); });
    client.invoke("hello", "async4", function(string result, string arg1) { writeln(result); writeln(arg1); });
    client.invoke("hello", name, function(string result, string arg1) { writeln(result); writeln(arg1); });
    client.invoke("hello", name, function(string result, ref string arg1) { writeln(result); writeln(arg1); });
}