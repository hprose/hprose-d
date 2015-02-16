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
 * hprose/bytes.d                                         *
 *                                                        *
 * hprose bytes io library for D.                         *
 *                                                        *
 * LastModified: Feb 15, 2015                             *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.bytes;
@trusted:

import hprose.tags;
import std.algorithm;
import std.bigint;
import std.conv;
import std.stdio;
import std.string;
import std.traits;

class BytesIO {
    private {
        char[] _buffer;
        long _pos;
    }

    @property {
        long size() {
            return _buffer.length;
        }
        bool eof() {
            return _pos >= size;
        }
        immutable(ubyte)[] buffer() {
            return cast(immutable(ubyte)[])_buffer;
        }
    }

    this() {
        this("");
    }
    this(string data) {
        init(data);
    }
    this(ubyte[] data) {
        init(data);
    }
    void init(T)(T data) {
        _buffer = cast(char[])data;
        _pos = 0;
    }
    void close() {
        _buffer.length = 0;
        _pos = 0;
    }
    char read() {
        if (size > _pos) {
            return _buffer[_pos++];
        }
        else {
            throw new Exception("no byte found in stream");
        }
    }
    char[] read(int n) {
        char[] bytes = _buffer[_pos .. _pos + n];
        _pos += n;
        return bytes;
    }
    char[] readFull() {
        char[] bytes = _buffer[_pos .. $];
        _pos = size;
        return bytes;
    }
    char[] readUntil(T...)(T tags) {
        long count = countUntil(_buffer[_pos .. $], tags);
        if (count < 0) return readFull();
        char[] bytes = _buffer[_pos .. _pos + count];
        _pos += count + 1;
        return bytes;
    }
    char skipUntil(T...)(T tags) {
        auto count = countUntil(_buffer[_pos .. $], tags);
        if (count < 0) throw new Exception("does not find tags in stream");
        char result = _buffer[_pos + count];
        _pos += count + 1;
        return result;
    }
    string readUTF8Char() {
        long pos = _pos;
        ubyte tag = read();
        switch (tag >> 4) {
            case 0: .. case 7: break;
            case 12, 13: ++_pos; break;
            case 14: _pos += 2; break;
            default: throw new Exception("bad utf-8 encoding");
        }
        if (_pos > size) throw new Exception("bad utf-8 encoding"); 
        return cast(string)_buffer[pos .. _pos];
    }
    T readString(T = string)(int wlen) if (isSomeString!T) {
        long pos = _pos;
        for (int i = 0; i < wlen; ++i) {
            ubyte tag = read();
            switch (tag >> 4) {
                case 0: .. case 7: break;
                case 12, 13: ++_pos; break;
                case 14: _pos += 2; break;
                case 15: _pos += 3; ++i; break;
                default: throw new Exception("bad utf-8 encoding");
            }
        }
        if (_pos > size) throw new Exception("bad utf-8 encoding"); 
        return cast(T)_buffer[pos .. _pos];
    }
    T readInt(T = int)(char tag) if (isSigned!T) {
        int c = read();
        if (c == tag) return 0;
        T result = 0;
        long len = size;
        T sign = 1;
        switch (c) {
            case TagNeg: sign = -1; goto case TagPos;
            case TagPos: c = read(); goto default;
            default: break;
        }
        while (_pos < len && c != tag) {
            result *= 10;
            result += (c - '0') * sign;
            c = read();
        }
        return result;
    }
    T readInt(T)(char tag) if (isUnsigned!T) {
        return cast(T)readInt!(Signed!T)(tag);
    }
    void skip(int n) {
        _pos += n;
    }
    BytesIO write(in char[] data) {
        if (data.length > 0) {
            _buffer ~= data;
        }
        return this;
    }
    BytesIO write(in byte[] data) {
        return write(cast(char[])data);
    }
    BytesIO write(in ubyte[] data) {
        return write(cast(char[])data);
    }
    BytesIO write(T)(in T x) {
        static if (isIntegral!T ||
            isSomeChar!T ||
            is(T == float)) {
            _buffer ~= cast(char[])to!string(x);
        }
        else static if (is(T == double) ||
            is(T == real)) {
            _buffer ~= cast(char[])format("%.16g", x);
        }
        return this;
    }
    override string toString() {
        return cast(string)_buffer;
    }
}

unittest {
    BytesIO bytes = new BytesIO("i123;d3.14;");
    assert(bytes.readUntil(';') == "i123");
    assert(bytes.readUntil(';') == "d3.14");
    bytes.write("hello");
    assert(bytes.read(5) == "hello");
    const int i = 123456789;
    bytes.write(i).write(';');
    assert(bytes.readInt(';') == i);
    bytes.write(1).write('1').write(';');
    assert(bytes.readInt(';') == 11);
    const float f = 3.14159265;
    bytes.write(f).write(';');
    assert(bytes.readUntil(';') == "3.14159");
    const double d = 3.141592653589793238;
    bytes.write(d).write(';');
    assert(bytes.readUntil(';') == "3.141592653589793");
    const real r = 3.141592653589793238;
    bytes.write(r).write(';');
    assert(bytes.readUntil(';', '.') == "3");
    assert(bytes.skipUntil(';', '.') == ';');
    bytes.write("你好啊");
    assert(bytes.readString(3) == "你好啊");
}