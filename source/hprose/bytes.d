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
 * LastModified: Aug 6, 2014                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.bytes;
@trusted:

import hprose.tags;
import std.algorithm;
import std.conv;
import std.stdio;
import std.traits;
import std.bigint;
import std.string;

class BytesIO {
    private ubyte[] _buffer;
    private int _pos;
    this() {
        this("");
    }
    this(string data) {
        init(data);
    }
    this(ubyte[] data) {
        init(data);
    }
    void init(string data) {
        init(cast(ubyte[])data);
    }
    void init(ubyte[] data) {
        _buffer = data;
        _pos = 0;
    }
    void close() {
        _buffer.length = 0;
        _pos = 0;
    }
    @property int size() {
        return _buffer.length;
    }
    ubyte read() {
        if (size > _pos) {
            return _buffer[_pos++];
        }
        else {
            throw new Exception("no byte found in stream");
        }
    }
    ubyte[] read(int n) {
        ubyte[] bytes = _buffer[_pos .. _pos + n];
        _pos += n;
        return bytes;
    }
    ubyte[] readFull() {
        ubyte[] bytes = _buffer[_pos .. $];
        _pos = size;
        return bytes;
    }
    ubyte[] readUntil(T...)(T tags) {
        int count = countUntil(_buffer[_pos .. $], tags);
        if (count < 0) return readFull();
        ubyte[] bytes = _buffer[_pos .. _pos + count];
        _pos += count + 1;
        return bytes;
    }
    ubyte skipUntil(T...)(T tags) {
        int count = countUntil(_buffer[_pos .. $], tags);
        if (count < 0) throw new Exception("does not find tags in stream");
        ubyte result = _buffer[_pos + count];
        _pos += count + 1;
        return result;
    }
    string readUTF8Char() {
        int pos = _pos;
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
    string readString(int wlen) {
        int len = 0;
        int pos = _pos;
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
        return cast(string)_buffer[pos .. _pos];
    }
    int readInt(char tag) {
        int c = read();
        if (c == tag) return 0;
        int result = 0;
        int len = size;
        int sign = 1;
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
    void skip(int n) {
        _pos += n;
    }
    @property bool eof() {
        return _pos >= size;
    }
    BytesIO write(in ubyte[] data) {
        if (data.length > 0) {
            _buffer ~= data;
        }
        return this;
    }
    BytesIO write(in byte[] data) {
        return write(cast(ubyte[])data);
    }
    BytesIO write(in char[] str) {
        return write(cast(ubyte[])str);
    }
    BytesIO write(T)(in T x) {
        static if (isIntegral!(T) ||
                   isSomeChar!(T) ||
                   is(T == float)) {
            _buffer ~= cast(ubyte[])to!string(x);
        }
        else static if (is(T == double) ||
                        is(T == real)) {
            _buffer ~= cast(ubyte[])format("%.16g", x);
        }
        return this;
	}
    override string toString() {
        return cast(string)_buffer;
    }
    @property immutable(ubyte)[] buffer() {
		return cast(immutable(ubyte)[])_buffer;
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