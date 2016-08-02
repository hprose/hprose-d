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
 * hprose/rpc/tcpservice.d                                *
 *                                                        *
 * hprose tcp service library for D.                      *
 *                                                        *
 * LastModified: Aug 3, 2016                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.rpc.tcpservice;

import hprose.rpc.service;
import hprose.rpc.common;
import hprose.rpc.tcpcontext;
import std.conv;
import std.file;
import std.stdio;
import std.traits;
import std.typecons;
import std.variant;
import vibe.core.net;
import vibe.stream.operations;

class TcpService: Service {

    void handler(TCPConnection conn) {
        while (conn.connected) {
            try {
                TcpContext context = new TcpContext(conn);
                int headerLength = 4;
                int dataLength = -1;
                ubyte[4] id;
                ubyte[4] dataLen;
                conn.read(dataLen);
                dataLength =
                    cast(int)(dataLen[0] & 0x7f) << 24 |
                    cast(int)(dataLen[1])        << 16 |
                    cast(int)(dataLen[2])        << 8  |
                    cast(int)(dataLen[3]);
                if ((dataLen[0] & 0x80) != 0) {
                    headerLength = 8;
                    conn.read(id);
                }
                ubyte[] data = new ubyte[dataLength];
                conn.read(data);
                data = handle(data, context);
                dataLength = cast(int)data.length;
                if (headerLength == 8) {
                    dataLen[0] = cast(ubyte)((dataLength >> 24) & 0x7f | 0x80);
                    dataLen[1] = cast(ubyte)((dataLength >> 16) & 0xff);
                    dataLen[2] = cast(ubyte)((dataLength >> 8) & 0xff);
                    dataLen[3] = cast(ubyte)((dataLength) & 0xff);
                    conn.write(dataLen);
                    conn.write(id);
                }
                else {
                    dataLen[0] = cast(ubyte)((dataLength >> 24) & 0x7f);
                    dataLen[1] = cast(ubyte)((dataLength >> 16) & 0xff);
                    dataLen[2] = cast(ubyte)((dataLength >> 8) & 0xff);
                    dataLen[3] = cast(ubyte)((dataLength) & 0xff);
                    conn.write(dataLen);
                }
                conn.write(data);
            }
            catch(Exception e) {
                break;
            }
        }
    }
}

class TcpServer: TcpService {
    TCPListener start(ushort port, string address = "0.0.0.0") {
        return listenTCP(port, &handler, address, TCPListenOptions.distribute);
    }
}

unittest {
//    import hprose.rpc.tcpclient;
    import hprose.rpc.context;
    import hprose.rpc.filter;
    import std.datetime;

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

    int inc(ref int n, Context context) {
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
    TcpServer server = new TcpServer();
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
            writeln(Clock.currStdTime());
            Variant result = next(name, args, context);
            writeln(Clock.currStdTime());
            return result;
        });
    server.use!"beforeFilter"(delegate ubyte[](ubyte[] request, Context context, NextFilterHandler next) {
            writeln("beforeFilter");
            writeln(cast(string)request);
            ubyte[] response = next(request, context);
            writeln("beforeFilter");
            writeln(cast(string)response);
            writeln();
            return response;
        });
    server.use!"afterFilter"(delegate ubyte[](ubyte[] request, Context context, NextFilterHandler next) {
            writeln("afterFilter");
            writeln(cast(string)request);
            ubyte[] response = next(request, context);
            writeln("afterFilter");
            writeln(cast(string)response);
            return response;
        });
    server.start(1234);

/*
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

    auto client = new TcpClient("tcp://127.0.0.1:1234/");
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

*/
}