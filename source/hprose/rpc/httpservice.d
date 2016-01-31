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
 * hprose/rpc/httpservice.d                               *
 *                                                        *
 * hprose http service library for D.                     *
 *                                                        *
 * LastModified: Jan 31, 2016                             *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.rpc.httpservice;

import hprose.rpc.service;
import hprose.rpc.common;
import hprose.rpc.httpcontext;
import std.conv;
import std.file;
import std.stdio;
import std.traits;
import std.typecons;
import std.variant;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.operations;

alias OnSendHeader = void delegate(HttpContext context);

class HttpService: Service {
    private {
        bool[string] origins;

        void sendHeader(HttpContext context) {
            if (onSendHeader !is null) {
                onSendHeader(context);
            }
            HTTPServerRequest req = context.request;
            HTTPServerResponse res = context.response;
            res.headers["Content-Type"] = "text/plain";
            if (p3p) {
                res.headers["P3P"] = "CP=\"CAO DSP COR CUR ADM DEV TAI PSA PSD " ~
                    "IVAi IVDi CONi TELo OTPi OUR DELi SAMi " ~
                    "OTRi UNRi PUBi IND PHY ONL UNI PUR FIN " ~
                    "COM NAV INT DEM CNT STA POL HEA PRE GOV\"";
            }
            if (crossDomain) {
                string origin = req.headers["Origin"];
                if (origin != "" && origin != "null") {
                    if (origins.length == 0 || origin in origins) {
                        res.headers["Access-Control-Allow-Origin"] = origin;
                        res.headers["Access-Control-Allow-Credentials"] = "true";
                    }
                }
                else {
                    res.headers["Access-Control-Allow-Origin"] = "*";
                }
            }
        }
    }

    bool get;
    bool p3p;
    bool crossDomain;
    OnSendHeader onSendHeader;

    void handler(HTTPServerRequest req, HTTPServerResponse res) {
        HttpContext context = new HttpContext(req, res);
        sendHeader(context);
        switch(req.method) {
            case HTTPMethod.GET: {
                if (get) {
                    res.writeBody(doFunctionList(context));
                }
                else {
                    res.statusCode = HTTPStatus.forbidden;
                }
                break;
            }
            case HTTPMethod.POST: {
                res.writeBody(handle(req.bodyReader.readAll(), context));
                break;
            }
            default: break;
        }
    }
}

class HttpServer: HttpService {
    private {
        string _crossDomainXmlFile;
        string _clientAccessPolicyXmlFile;
        string _lastModified = null;
        string _etag = null;
    }

    @property string crossDomainXmlFile() {
        return _crossDomainXmlFile;
    }

    @property string crossDomainXmlFile(string file) {
        _crossDomainXmlFile = file;
        crossDomainXmlContext = readText(file);
        return file;
    }

    @property string clientAccessPolicyXmlFile() {
        return _clientAccessPolicyXmlFile;
    }
    
    @property string clientAccessPolicyXmlFile(string file) {
        _clientAccessPolicyXmlFile = file;
        clientAccessPolicyXmlContent = readText(file);
        return file;
    }
    
    string crossDomainXmlContext;
    string clientAccessPolicyXmlContent;
    HTTPServerSettings settings = new HTTPServerSettings();

    void crossDomainXmlHandler(HTTPServerRequest req, HTTPServerResponse res) {
        if (req.headers["If-Modified-Since"] == _lastModified &&
            req.headers["If-None-Match"] == _etag) {
            res.statusCode = HTTPStatus.notModified;
        }
        else {
            res.headers["Last-Modified"] = _lastModified;
            res.headers["Etag"] = _etag;
            res.writeBody(crossDomainXmlContext, "text/xml");
        }
    }

    void clientAccessPolicyXmlHandler(HTTPServerRequest req, HTTPServerResponse res) {
        if (req.headers["If-Modified-Since"] == _lastModified &&
            req.headers["If-None-Match"] == _etag) {
            res.statusCode = HTTPStatus.notModified;
        }
        else {
            res.headers["Last-Modified"] = _lastModified;
            res.headers["Etag"] = _etag;
            res.writeBody(clientAccessPolicyXmlContent, "text/xml");
        }
    }

    HTTPListener start(string path = "/") {
        URLRouter router = new URLRouter();
        router.get("/crossdomain.xml", &crossDomainXmlHandler);
        router.get("/clientaccesspolicy.xml", &clientAccessPolicyXmlHandler);
        router.any(path, &handler);

        return listenHTTP(settings, router);
    }
}

unittest {
    import hprose.rpc.httpclient;
    import hprose.rpc.context;
    import hprose.rpc.filter;

    string hello(string name) {
        return "hello " ~ name ~ "!";
    }

    string goodbye(string name) {
        return "goodbye " ~ name ~ "!";
    }

    Variant missfunc(string name, Variant[] args) {
        if (name == "mul") {
            return args[0] * args[1];
        }
        else if (name == "div") {
            return args[0] / args[1];
        }
        else {
            return Variant(null);
        }
    }

    int inc(ref int n, HttpContext context) {
        auto req = context.request;
        auto res = context.response;
        n++;
        return n;
    }

    class BaseTest {
        int add(int a, int b) {
            return a + b;
        }
        int sub(int a, int b) {
            return a - b;
        }
    }
    class Test: BaseTest {
        int sum(int[] nums) {
            int sum = 0;
            foreach (x; nums) {
                sum += x;
            }
            return sum;
        }
        static string[] test() {
            return ["Tom", "Jerry"];
        }
        static Variant[string] test2() {
            return ["name": Variant("张三"), "age": Variant(18)];
        }
    }

    Test test = new Test();

    // Server
    HttpServer server = new HttpServer();
    server.add!("hello")(&hello);
    server.add!(["goodbye", "inc"])(&goodbye, &inc);
    server.add!(["add", "sub", "sum"])(test);
    server.add!("test", Test)(); // add Test.test method to the server
    server.add!(Test, "test")(); // add all static methods on Test with prefix "test" to the server
    server.addMissingFunction(&missfunc);
    server.use(delegate Variant(string name, ref Variant[] args, Context context, NextInvokeHandler next) {
            writeln(name);
            writeln(args);
            Variant result = next(name, args, context);
            writeln(result);
            return result;
        }, delegate Variant(string name, ref Variant[] args, Context context, NextInvokeHandler next) {
            writeln(std.datetime.Clock.currStdTime());
            Variant result = next(name, args, context);
            writeln(std.datetime.Clock.currStdTime());
            return result;
        }, delegate Variant(string name, ref Variant[] args, Context context, NextInvokeHandler next) {
            Variant result = next(name, args, context);
            writeln();
            return result;
        });
    server.settings.bindAddresses = ["127.0.0.1"];
    server.settings.port = 4444;
    server.settings.sessionStore = new MemorySessionStore();
    server.start();

    // Client
    interface Hello {
        @Simple() string hello(string name);
        string goodbye(string name);
        int add(int a, int b);
        int sub(int a, int b = 3);
        int mul(int a, int b);
        int div(int a, int b);
        int sum(int[] nums...);
        int inc(ref int n);
        string[] test();
        Variant[string] test2();
    }

    auto client = new HttpClient("http://127.0.0.1:4444/");
    Hello proxy = client.useService!Hello();

    Hello proxy2 = client.useService!(Hello, "test")();

//    client.filters ~= new class Filter {
//        override ubyte[] inputFilter(ubyte[] data, Context context) {
//            writeln(cast(string)data);
//            return data;
//        }
//
//        override ubyte[] outputFilter(ubyte[] data, Context context) {
//            writeln(cast(string)data);
//            return data;
//        };
//    };

    assert(proxy.hello("world") == "hello world!");
    assert(proxy.goodbye("world") == "goodbye world!");
    assert(proxy.add(1, 2) == 3);
    assert(proxy.sub(1, 2) == -1);
    assert(proxy.mul(1, 2) == 2);
    assert(proxy.div(2, 2) == 1);
    assert(proxy.sum(1, 2, 3) == 6);
    assert(proxy.test() == ["Tom", "Jerry"]);
    int n = 0;
    assert(proxy.inc(n) == 1);
    assert(proxy.inc(n) == 2);
    assert(proxy.inc(n) == 3);
    assert(n == 3);
    assert(proxy2.test() == ["Tom", "Jerry"]);
    assert(proxy2.test2() == ["name": Variant("张三"), "age": Variant(18)]);

}