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
 * hprose/reader.d                                        *
 *                                                        *
 * hprose reader library for D.                           *
 *                                                        *
 * LastModified: Feb 8, 2015                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.reader;
@trusted:

import hprose.bytes;
import hprose.common;
import hprose.classmanager;
import hprose.tags;
import std.algorithm;
import std.bigint;
import std.container;
import std.datetime;
import std.json;
import std.math;
import std.stdio;
import std.string;
import std.traits;
import std.typecons;
import std.uuid;
import std.utf;
import std.variant;
import std.conv;

private interface ReaderRefer {
    void set(Variant value);
    Variant read(int index);
    void reset();
}

private final class FakeReaderRefer : ReaderRefer {
    void set(Variant value) {}
    Variant read(int index) {
        throw new Exception("Unexcepted serialize tag '" ~ TagRef ~ "' in stream");
    }
    void reset() {}
}

private final class RealReaderRefer : ReaderRefer {
    private Variant[] _references;
    void set(Variant value) {
        _references ~= value;
    }
    Variant read(int index) {
        return _references[index];
    }
    void reset() {
        _references = null;
    }
}

class RawReader {
public:
    this(BytesIO bytes) {
        _bytes = bytes;
    }
    static Exception unexpectedTag(char tag, string expectTags = "") {
        if ((tag != 0) && (expectTags.length != 0)) {
            return new Exception("Tags '" ~ expectTags ~ "' expected, but '" ~ tag ~ "' found in stream");
        }
        else if (tag != 0) {
            return new Exception("Unexpected serialize tag '" ~ tag ~ "' in stream");
        }
        else {
            return new Exception("No byte found in stream");
        }
    }
    BytesIO readRaw() {
        BytesIO bytes = new BytesIO();
        readRaw(bytes);
        return bytes;
    }
    BytesIO readRaw(BytesIO bytes) {
        return readRaw(bytes, _bytes.read());
    }
    BytesIO readRaw(BytesIO bytes, char tag) {
        bytes.write(tag);
        switch (tag) {
            case '0': .. case '9': break;
            case TagNull, TagEmpty, TagTrue, TagFalse, TagNaN: break;
            case TagInfinity: bytes.write(_bytes.read()); break;
            case TagInteger, TagLong, TagDouble, TagRef: readNumberRaw(bytes); break;
            case TagDate, TagTime: readDateTimeRaw(bytes); break;
            case TagUTF8Char: readUTF8CharRaw(bytes); break;
            case TagBytes: readBytesRaw(bytes); break;
            case TagString: readStringRaw(bytes); break;
            case TagGuid: readGuidRaw(bytes); break;
            case TagList, TagMap, TagObject: readComplexRaw(bytes); break;
            case TagClass: readComplexRaw(bytes); readRaw(bytes); break;
            case TagError: readRaw(bytes); break;
            default: throw unexpectedTag(tag);
        }
        return bytes;
    }
protected:
    BytesIO _bytes;
private:
    int stoi(string str) {
        if (str.length == 0) return 0;
        return to!int(str);
    }
    void readNumberRaw(BytesIO bytes) {
        bytes.write(_bytes.readUntil(TagSemicolon)).write(TagSemicolon);
    }
    void readDateTimeRaw(BytesIO bytes) {
        bytes.write(_bytes.readUntil(TagSemicolon, TagUTC));
    }
    void readUTF8CharRaw(BytesIO bytes) {
        bytes.write(_bytes.readUTF8Char());
    }
    void readBytesRaw(BytesIO bytes) {
        string len = cast(string)_bytes.readUntil(TagQuote);
        bytes.write(len).write(TagQuote).write(_bytes.read(stoi(len))).write(TagQuote);
        _bytes.skip(1);
    }
    void readStringRaw(BytesIO bytes) {
        string len = cast(string)_bytes.readUntil(TagQuote);
        bytes.write(len).write(TagQuote).write(_bytes.readString(stoi(len))).write(TagQuote);
        _bytes.skip(1);
    }
    void readGuidRaw(BytesIO bytes) {
        bytes.write(_bytes.read(38));
    }
    void readComplexRaw(BytesIO bytes) {
        bytes.write(_bytes.readUntil(TagOpenbrace)).write(TagOpenbrace);
        ubyte tag;
        while ((tag = _bytes.read()) != TagClosebrace) {
            readRaw(bytes, tag);
        }
        bytes.write(tag);
    }
}

class Reader : RawReader {
private:
    bool _simple;
    ReaderRefer _refer;
    Tuple!(TypeInfo, string[])[] _classref;
    string _readStringWithoutTag() {
        string result = _bytes.readString(_bytes.readInt(TagQuote));
        _bytes.skip(1);
        return result;
    }
    void setRef(T)(ref T value) {
        if (_simple) return;
        _refer.set(Variant(value));
    }
    T readRef(T)() {
		static if (is(Unqual!T == Variant)) {
			return cast(T)_refer.read(_bytes.readInt(TagSemicolon));
		}
		else {
        	return cast(T)_refer.read(_bytes.readInt(TagSemicolon)).get!(Unqual!T);
		}
    }
    T readInteger(T)(char tag) if (isIntegral!T) {
        alias U = Unqual!T;
        switch(tag) {
            case '0': .. case '9': return cast(T)(tag - '0');
            case TagInteger, TagLong: return readIntegerWithoutTag!T();
            case TagDouble: return cast(T)to!U(readDoubleWithoutTag!real());
            case TagNull: return cast(T)to!U(0);
            case TagEmpty: return cast(T)to!U(0);
            case TagTrue: return cast(T)to!U(1);
            case TagFalse: return cast(T)to!U(0);
            case TagUTF8Char: return cast(T)to!U(readUTF8CharWithoutTag!string());
            case TagString: return cast(T)to!U(readStringWithoutTag!string());
            case TagRef: return cast(T)to!U(readRef!string());
            default: throw unexpectedTag(tag);
        }
    }
    T readBigInt(T)(char tag) if (is(Unqual!T == BigInt)) {
        switch(tag) {
            case '0': .. case '9': return cast(T)BigInt(tag - '0');
            case TagInteger, TagLong: return readBigIntWithoutTag!T();
            case TagDouble: return cast(T)BigInt(to!long(readDoubleWithoutTag!real()));
            case TagNull: return cast(T)BigInt(0);
            case TagEmpty: return cast(T)BigInt(0);
            case TagTrue: return cast(T)BigInt(1);
            case TagFalse: return cast(T)BigInt(0);
            case TagUTF8Char: return cast(T)BigInt(readUTF8CharWithoutTag!string());
            case TagString: return cast(T)BigInt(readStringWithoutTag!string());
            case TagRef: return cast(T)BigInt(readRef!string());
            default: throw unexpectedTag(tag);
        }
    }
    T readDouble(T)(char tag) if (isFloatingPoint!T) {
        alias U = Unqual!T;
        switch(tag) {
            case '0': .. case '9': return cast(T)to!U(tag - '0');
            case TagInteger: return cast(T)readIntegerWithoutTag!int();
            case TagLong, TagDouble: return readDoubleWithoutTag!T();
            case TagNaN: return cast(T)U.nan;
            case TagInfinity: return readInfinityWithoutTag!T();
            case TagNull: return cast(T)to!U(0);
            case TagEmpty: return cast(T)to!U(0);
            case TagTrue: return cast(T)to!U(1);
            case TagFalse: return cast(T)to!U(0);
            case TagUTF8Char: return cast(T)to!U(readUTF8CharWithoutTag!string());
            case TagString: return cast(T)to!U(readStringWithoutTag!string());
            case TagRef: return cast(T)to!U(readRef!string());
            default: throw unexpectedTag(tag);
        }
    }
    T readBoolean(T)(char tag) if (isBoolean!T) {
        switch(tag) {
            case '0': return cast(T)(false);
            case '1': .. case '9': return cast(T)(true);
            case TagInteger: return cast(T)(readIntegerWithoutTag!int() != 0);
            case TagLong: return cast(T)(readBigIntWithoutTag!BigInt() != BigInt(0));
            case TagDouble: return cast(T)(readDoubleWithoutTag!real() != 0);
            case TagNull: return cast(T)(false);
            case TagEmpty: return cast(T)(false);
            case TagTrue: return cast(T)(true);
            case TagFalse: return cast(T)(false);
            case TagUTF8Char: return cast(T)(countUntil("\00", readUTF8CharWithoutTag!char()) >= 0);
            case TagString: {
                auto v = readStringWithoutTag!string();
                return cast(T)(v != null && v != "" && v != "false");
            }
            case TagRef: {
                auto v = readRef!string();
                return cast(T)(v != null && v != "" && v != "false");
            }
            default: throw unexpectedTag(tag);
        }
    }
    T readDateTime(T)(char tag) if (is(Unqual!T == Date) ||
                                is(Unqual!T == TimeOfDay) ||
                                is(Unqual!T == DateTime) ||
                                is(Unqual!T == SysTime)) {
        switch(tag) {
            case TagDate: return readDateWithoutTag!T();
            case TagTime: return readTimeWithoutTag!T();
            case TagRef: return readRef!T();
            default: throw unexpectedTag(tag);
        }
    }
    T readUTF8Char(T)(char tag) if (isSomeChar!T) {
        alias U = Unqual!T;
        switch(tag) {
            case '0': .. case '9': return cast(T)(tag - '0');
            case TagInteger, TagLong: return cast(T)readIntegerWithoutTag!int();
            case TagDouble: return cast(T)to!U(readDoubleWithoutTag!real());
            case TagUTF8Char: return readUTF8CharWithoutTag!T();
            case TagString: return cast(T)readStringWithoutTag!(U[])()[0];
            case TagRef: return cast(T)readRef!(U[])()[0];
            default: throw unexpectedTag(tag);
        }
    }
    T readString(T)(char tag) if (isSomeString!T) {
        alias U = Unqual!T;
        switch(tag) {
            case '0': .. case '9': return cast(T)to!U("" ~ cast(char)tag);
            case TagInteger, TagLong, TagDouble: return cast(T)to!U(cast(string)_bytes.readUntil(TagSemicolon));
            case TagNaN: return cast(T)to!U("NAN");
            case TagInfinity: return cast(T)to!U(readInfinityWithoutTag!real());
            case TagNull: return null;
            case TagEmpty: return cast(T)to!U("");
            case TagTrue: return cast(T)to!U("true");
            case TagFalse: return cast(T)to!U("true");
            case TagUTF8Char: return readUTF8CharWithoutTag!T();
            case TagString: return readStringWithoutTag!T();
            case TagRef: return readRef!T();
            default: throw unexpectedTag(tag);
        }
    }
    T readUUID(T)(char tag) if (Unqual!T == UUID) {
        alias U = Unqual!T;
        switch(tag) {
            case TagNull: return UUID.init;
            case TagEmpty: return UUID.init;
            case TagBytes: return UUID(readBytesWithoutTag!(ubyte[16])());
            case TagGuid: return readUUIDWithoutTag!T();
            case TagString: return UUID(readStringWithoutTag!string());
            case TagRef: return readRef!T();
            default: throw unexpectedTag(tag);
        }
    }
    T readBytes(T)(char tag) if (isArray!T &&
                         (is(Unqual!(ForeachType!T) == ubyte) ||
                          is(Unqual!(ForeachType!T) == byte))) {
        alias U = Unqual!T;
        switch(tag) {
            case TagNull: return T.init;
            case TagEmpty: return T.init;
            case TagUTF8Char: return cast(T)(readUTF8CharWithoutTag!string());
            case TagString: return cast(T)(readStringWithoutTag!string());
            case TagBytes: return readBytesWithoutTag!T();
            case TagList: return readArrayWithoutTag!T();
            case TagRef: return readRef!T();
            default: throw unexpectedTag(tag);
        }
    }
    T readArray(T)(char tag) if (isArray!T) {
        alias U = Unqual!T;
        switch(tag) {
            case TagNull: return null;
            case TagEmpty: return T.init;
            case TagList: return readArrayWithoutTag!T();
            case TagRef: return readRef!T();
            default: throw unexpectedTag(tag);
        }
    }
    T readAssociativeArray(T)(char tag) if (isAssociativeArray!T) {
        alias U = Unqual!T;
        switch(tag) {
            case TagNull: return null;
            case TagEmpty: return T.init;
            case TagMap: return readAssociativeArrayWithoutTag!T();
            case TagRef: return readRef!T();
            default: throw unexpectedTag(tag);
        }
    }
	T readJSONValue(T)(char tag) if (is(Unqual!T == JSONValue)) {
		alias U = Unqual!T;
		switch(tag) {
			case '0': .. case '9': return JSONValue(cast(long)(tag - '0'));
			case TagInteger: return JSONValue(readIntegerWithoutTag!int());
			case TagLong: {
				BigInt bi = readBigIntWithoutTag!BigInt();
				if (bi > BigInt(ulong.max) || bi < BigInt(long.min)) {
					return JSONValue(bi.toDecimalString());
				}
				else if (bi > BigInt(long.max)) {
					return JSONValue(bi.toDecimalString().to!ulong());
				}
				else {
					return JSONValue(bi.toLong());
				}
			}
			case TagDouble: return JSONValue(readDoubleWithoutTag!double());
			case TagNaN: return JSONValue(double.nan);
			case TagInfinity: return JSONValue(readInfinityWithoutTag!double());
			case TagNull: return JSONValue(null);
			case TagEmpty: return JSONValue("");
			case TagTrue: return JSONValue(true);
			case TagFalse: return JSONValue(false);
			case TagUTF8Char: return JSONValue(readUTF8CharWithoutTag!string());
			case TagString: return JSONValue(readStringWithoutTag!string());
			case TagDate: return JSONValue(readDateWithoutTag!SysTime().toString());
			case TagTime: return JSONValue(readTimeWithoutTag!TimeOfDay().toString());
			case TagGuid: return JSONValue(readUUIDWithoutTag!UUID().toString());
			case TagList: return JSONValue(readArrayWithoutTag!(JSONValue[])());
			case TagMap: return JSONValue(readAssociativeArrayWithoutTag!(JSONValue[string])());
			default: throw unexpectedTag(tag);
		}
	}
    void readClass() {
        TypeInfo classtype = ClassManager.getClass(_readStringWithoutTag());
        int count = _bytes.readInt(TagOpenbrace);
        string[] fields;
        for (int i = 0; i < count; ++i) {
            fields ~= readString!string();
        }
        _bytes.skip(1);
        _classref ~= tuple(classtype, fields);
    }
    T unserialize(T)(char tag) if (isSerializable!T) {
        static if (isIntegral!T) {
            return readInteger!T(tag);
        }
        else static if (is(Unqual!T == BigInt)) {
            return readBigInt!T(tag);
        }
        else static if (isFloatingPoint!T) {
            return readDouble!T(tag);
        }
        else static if (isBoolean!T) {
            return readBoolean!T(tag);
        }
        else static if (is(Unqual!T == Date) || is(Unqual!T == TimeOfDay) ||
                        is(Unqual!T == DateTime) || is(Unqual!T == SysTime)) {
            return readDateTime!T(tag);
        }
        else static if (isSomeChar!T) {
            return readUTF8Char!T(tag);
        }
        else static if (isSomeString!T) {
            return readString!T(tag);
        }
        else static if (is(Unqual!T == UUID)) {
            return readUUID!T(tag);
        }
        else static if (isArray!T) {
            static if (is(Unqual!(ForeachType!T) == ubyte) ||
                       is(Unqual!(ForeachType!T) == byte)) {
                return readBytes!T(tag);
            }
            else {
                return readArray!T(tag);
            }
        }
        else static if (isAssociativeArray!T) {
            return readAssociativeArray!T(tag);
        }
		else static if (is(Unqual!T == JSONValue)) {
			return readJSONValue!T(tag);
		}
    }
public:
    this(BytesIO bytes, bool simple = false) {
        super(bytes);
        _simple = simple;
        if (simple) {
            _refer = new FakeReaderRefer();
        }
        else {
            _refer = new RealReaderRefer();
        }
    }
    void reset() {
        _classref = null;
        _refer.reset();
    }
    T unserialize(T)() if (isSerializable!T) {
        char tag = _bytes.read();
        alias U = Unqual!T;
        static if (isInstanceOf!(Nullable, U)) {
            if (tag == TagNull) {
                return T.init;
            }
            else {
                return cast(T)U(unserialize!(typeof(U.init.get()))(tag));
            }
        }
        else {
            return unserialize!T(tag);
        }
    }
    T readIntegerWithoutTag(T)() if (isIntegral!T) {
        return cast(T)_bytes.readInt!(Unqual!T)(TagSemicolon);
    }
    T readInteger(T)() if (isIntegral!T) {
        return readInteger!T(_bytes.read());
    }
    T readBigIntWithoutTag(T)() if (is(Unqual!T == BigInt)) {
        return cast(T)BigInt(cast(string)_bytes.readUntil(TagSemicolon));
    }
    T readBigInt(T)() if (is(Unqual!T == BigInt)) {
        return readBigInt!T(_bytes.read());
    }
    T readDoubleWithoutTag(T)() if (isFloatingPoint!T) {
        alias U = Unqual!T;
        return cast(T)to!U(cast(string)_bytes.readUntil(TagSemicolon));
    }
    T readInfinityWithoutTag(T)() if (isFloatingPoint!T) {
        alias U = Unqual!T;
        return cast(T)((_bytes.read() == TagNeg) ? -U.infinity : U.infinity);
    }
    T readDouble(T)() if (isFloatingPoint!T) {
        return readDouble!T(_bytes.read());
    }
    T readDateWithoutTag(T)() if (is(Unqual!T == Date) || is(Unqual!T == DateTime) || is(Unqual!T == SysTime)) {
        int year = to!int(cast(string)_bytes.read(4));
        int month = to!int(cast(string)_bytes.read(2));
        int day = to!int(cast(string)_bytes.read(2));
        static if (is(Unqual!T == Date)) {
            ubyte tag = _bytes.skipUntil(TagSemicolon, TagUTC);
            Date result = Date(year, month, day);
        }
        else {
            int hour = 0;
            int minute = 0;
            int second = 0;
            int hnsecs = 0;
            char tag = _bytes.read();
            if (tag == TagTime) {
                hour = to!int(cast(string)_bytes.read(2));
                minute = to!int(cast(string)_bytes.read(2));
                second = to!int(cast(string)_bytes.read(2));
                tag = _bytes.read();
                if (tag == TagPoint) {
                    hnsecs = to!int(cast(string)_bytes.read(3)) * 10000;
                    tag = _bytes.read();
                    if ((tag >= '0') && (tag <= '9')) {
                        hnsecs += (tag - '0') * 1000 + to!int(cast(string)_bytes.read(2)) * 10;
                        tag = _bytes.read();
                        if ((tag >= '0') && (tag <= '9')) {
                            hnsecs += (tag - '0');
                            _bytes.skip(2);
                            tag = _bytes.read();
                        }
                    }
                }
            }
            static if (is(Unqual!T == DateTime)) {
                DateTime result = DateTime(year, month, day, hour, minute, second);
            }
            else {
                SysTime result;
                if (tag == TagUTC) {
                    result = SysTime(DateTime(year, month, day, hour, minute, second), FracSec.from!"hnsecs"(hnsecs), UTC());
                }
                else {
                    result = SysTime(DateTime(year, month, day, hour, minute, second), FracSec.from!"hnsecs"(hnsecs), LocalTime());
                }
            }
        }
        setRef(result);
        return cast(T)result;
    }
    T readTimeWithoutTag(T)() if (is(Unqual!T == TimeOfDay) || is(Unqual!T == DateTime) || is(Unqual!T == SysTime)) {
        int year = 1970;
        int month = 1;
        int day = 1;
        int hour = to!int(cast(string)_bytes.read(2));
        int minute = to!int(cast(string)_bytes.read(2));
        int second = to!int(cast(string)_bytes.read(2));
        int hnsecs = 0;
        char tag = _bytes.read();
        if (tag == TagPoint) {
            hnsecs = to!int(cast(string)_bytes.read(3)) * 10000;
            tag = _bytes.read();
            if ((tag >= '0') && (tag <= '9')) {
                hnsecs += (tag - '0') * 1000 + to!int(cast(string)_bytes.read(2)) * 10;
                tag = _bytes.read();
                if ((tag >= '0') && (tag <= '9')) {
                    hnsecs += (tag - '0');
                    _bytes.skip(2);
                    tag = _bytes.read();
                }
            }
        }
        static if (is(Unqual!T == TimeOfDay)) {
            TimeOfDay result = TimeOfDay(hour, minute, second);
        }
        else static if (is(Unqual!T == DateTime)) {
            DateTime result = DateTime(year, month, day, hour, minute, second);
        }
        else {
            SysTime result;
            if (tag == TagUTC) {
                result = SysTime(DateTime(year, month, day, hour, minute, second), FracSec.from!"hnsecs"(hnsecs), UTC());
            }
            else {
                result = SysTime(DateTime(year, month, day, hour, minute, second), FracSec.from!"hnsecs"(hnsecs), LocalTime());
            }
        }
        setRef(result);
        return cast(T)result;
    }
    T readDateTime(T)() if (is(Unqual!T == Date) || is(Unqual!T == TimeOfDay) ||
                            is(Unqual!T == DateTime) || is(Unqual!T == SysTime)) {
        return readDateTime!T(_bytes.read());
    }
    T readUTF8CharWithoutTag(T)() if (isSomeChar!T || isSomeString!T) {
        alias U = Unqual!T;
        static if (is(U == string)) {
            return _bytes.readUTF8Char();
        }
        else {
            string s = _bytes.readUTF8Char();
            static if (isSomeChar!T) {
                foreach(U c; s) return cast(T)c;
            }
            else {
                return cast(T)to!U(s);
            }
        }
        assert(0);
    }
    T readUTF8Char(T)() if (isSomeChar!T) {
        return readUTF8Char!T(_bytes.read());
    }
    T readStringWithoutTag(T)() if (isSomeString!T) {
        alias U = Unqual!T;
        static if (is(U == string)) {
            string value = _readStringWithoutTag();
        }
        else {
            U value = to!U(_readStringWithoutTag());
        }
        setRef(value);
        return cast(T)value;
    }
    T readString(T)() if (isSomeString!T) {
        return readString!T(_bytes.read());
    }
    T readUUIDWithoutTag(T)() if (is(Unqual!T == UUID)) {
        _bytes.skip(1);
        UUID uuid = UUID(_bytes.read(36));
        _bytes.skip(1);
        setRef(uuid);
        return cast(T)uuid;
    }
    T readUUID(T)() if (Unqual!T == UUID) {
        return readUUID!T(_bytes.read());
    }
    T readBytesWithoutTag(T)() if (isArray!T &&
                                   (is(Unqual!(ForeachType!T) == ubyte) ||
                                    is(Unqual!(ForeachType!T) == byte))) {
        int len = _bytes.readInt(TagQuote);
        Unqual!(ForeachType!T)[] value = cast(Unqual!(ForeachType!T)[])(_bytes.read(len));
        _bytes.skip(1);
        setRef(value);
        return cast(T)value;
    }
    T readBytes(T)() if (isArray!T &&
                         (is(Unqual!(ForeachType!T) == ubyte) ||
                          is(Unqual!(ForeachType!T) == byte))) {
        return readBytes!T(_bytes.read());
    }
    T readArrayWithoutTag(T)() if (isArray!T) {
        int len = _bytes.readInt(TagOpenbrace);
        Unqual!(ForeachType!T)[] value = new Unqual!(ForeachType!T)[len];
        setRef(value);
        foreach (int i; 0..len) value[i] = unserialize!(Unqual!(ForeachType!T))();
        _bytes.skip(1);
        return cast(T)value;
    }
    alias readArrayWithoutTag readListWithoutTag;
    T readArray(T)() if (isArray!T) {
        return readArray!T(_bytes.read());
    }
    alias readArray readList;
    T readAssociativeArrayWithoutTag(T)() if (isAssociativeArray!T) {
        Unqual!(ValueType!T)[Unqual!(KeyType!T)] value;
        setRef(value);
        foreach (int i; 0.._bytes.readInt(TagOpenbrace)) {
            auto k = unserialize!(Unqual!(KeyType!T))();
            auto v = unserialize!(Unqual!(ValueType!T))();
            value[k] = v;
        }
        _bytes.skip(1);
        return cast(T)value;
    }
    alias readAssociativeArrayWithoutTag readMapWithoutTag;
    T readAssociativeArray(T)() if (isAssociativeArray!T) {
        return readAssociativeArray!T(_bytes.read());
    }
    alias readAssociativeArray readMap;
	T readJSONValue(T)() if (Unqual!T == JSONValue) {
		return readJSONValue!T(_bytes.read());
	}
}

unittest {
    BytesIO bytes = new BytesIO("nnnnnnnnnnnnnnnnnn");
    Reader reader = new Reader(bytes);
    assert(reader.unserialize!byte() == 0);
    assert(reader.unserialize!short() == 0);
    assert(reader.unserialize!int() == 0);
    assert(reader.unserialize!long() == 0);
    assert(reader.unserialize!(Nullable!char)().isNull());
    assert(reader.unserialize!string() == null);
    assert(reader.unserialize!bool() == false);
    assert(reader.unserialize!float() == 0.0f);
    assert(reader.unserialize!double() == 0.0);
    assert(reader.unserialize!real() == 0.0);
    assert(reader.unserialize!(Nullable!int)().isNull());
    assert(reader.unserialize!(const byte)() == 0);
    assert(reader.unserialize!(const Nullable!char)().isNull());
    assert(reader.unserialize!(const BigInt)() == BigInt(0));
    assert(reader.unserialize!(immutable real)() == 0);
    assert(reader.unserialize!(immutable Nullable!int)().isNull());
    assert(reader.unserialize!(int[])() == null);
    assert(reader.unserialize!(int[string])() == null);
}

unittest {
    BytesIO bytes = new BytesIO("0000000000000000");
    Reader reader = new Reader(bytes);
    assert(reader.unserialize!byte() == 0);
    assert(reader.unserialize!short() == 0);
    assert(reader.unserialize!int() == 0);
    assert(reader.unserialize!long() == 0);
    assert(reader.unserialize!char() == 0);
    assert(reader.unserialize!string() == "0");
    assert(reader.unserialize!bool() == false);
    assert(reader.unserialize!float() == 0.0f);
    assert(reader.unserialize!double() == 0.0);
    assert(reader.unserialize!real() == 0.0);
    assert(reader.unserialize!(Nullable!int)() == 0);
    assert(reader.unserialize!(const byte)() == 0);
    assert(reader.unserialize!(const char)() == 0);
    assert(reader.unserialize!(const BigInt)() == BigInt(0));
    assert(reader.unserialize!(immutable real)() == 0);
    assert(reader.unserialize!(immutable Nullable!int)() == 0);
}

unittest {
    BytesIO bytes = new BytesIO("1111111111111111");
    Reader reader = new Reader(bytes);
    assert(reader.unserialize!byte() == 1);
    assert(reader.unserialize!short() == 1);
    assert(reader.unserialize!int() == 1);
    assert(reader.unserialize!long() == 1);
    assert(reader.unserialize!char() == 1);
    assert(reader.unserialize!string() == "1");
    assert(reader.unserialize!bool() == true);
    assert(reader.unserialize!float() == 1.0f);
    assert(reader.unserialize!double() == 1.0);
    assert(reader.unserialize!real() == 1.0);
    assert(reader.unserialize!(Nullable!int)() == 1);
    assert(reader.unserialize!(const byte)() == 1);
    assert(reader.unserialize!(const char)() == 1);
    assert(reader.unserialize!(const BigInt)() == BigInt(1));
    assert(reader.unserialize!(immutable real)() == 1);
    assert(reader.unserialize!(immutable Nullable!int)() == 1);
}

unittest {
    BytesIO bytes = new BytesIO("9999999999999999");
    Reader reader = new Reader(bytes);
    assert(reader.unserialize!byte() == 9);
    assert(reader.unserialize!short() == 9);
    assert(reader.unserialize!int() == 9);
    assert(reader.unserialize!long() == 9);
    assert(reader.unserialize!char() == 9);
    assert(reader.unserialize!string() == "9");
    assert(reader.unserialize!bool() == true);
    assert(reader.unserialize!float() == 9.0f);
    assert(reader.unserialize!double() == 9.0);
    assert(reader.unserialize!real() == 9.0);
    assert(reader.unserialize!(Nullable!int)() == 9);
    assert(reader.unserialize!(const byte)() == 9);
    assert(reader.unserialize!(const char)() == 9);
    assert(reader.unserialize!(const BigInt)() == BigInt(9));
    assert(reader.unserialize!(immutable real)() == 9);
    assert(reader.unserialize!(immutable Nullable!int)() == 9);
}

unittest {
    import hprose.writer;
    BytesIO bytes = new BytesIO();
    Writer writer = new Writer(bytes);
    for (int i = 0; i < 16; i++) writer.serialize(-1234567890);
    Reader reader = new Reader(bytes);
    assert(reader.unserialize!byte() == cast(byte)-1234567890);
    assert(reader.unserialize!short() == cast(short)-1234567890);
    assert(reader.unserialize!int() == -1234567890);
    assert(reader.unserialize!long() == -1234567890);
    assert(reader.unserialize!dchar() == -1234567890);
    assert(reader.unserialize!string() == "-1234567890");
    assert(reader.unserialize!bool() == true);
    auto f = reader.unserialize!float();
    assert(f == cast(float)-1234567890);
    assert(reader.unserialize!double() == -1234567890);
    assert(reader.unserialize!real() == -1234567890);
    assert(reader.unserialize!(Nullable!int)() == -1234567890);
    assert(reader.unserialize!(const uint)() == cast(uint)-1234567890);
    assert(reader.unserialize!(const ulong)() == cast(ulong)-1234567890);
    assert(reader.unserialize!(const BigInt)() == BigInt(-1234567890));
    assert(reader.unserialize!(immutable real)() == -1234567890);
    assert(reader.unserialize!(immutable Nullable!int)() == -1234567890);
}

unittest {
    import hprose.writer;
    BytesIO bytes = new BytesIO();
    Writer writer = new Writer(bytes);
    for (int i = 0; i < 6; i++) writer.serialize(BigInt("1234567890987654321234567890987654321"));
    Reader reader = new Reader(bytes);
    assert(reader.unserialize!string() == "1234567890987654321234567890987654321");
    assert(reader.unserialize!bool() == true);
    auto f = reader.unserialize!float();
    auto f2 = to!float("1234567890987654321234567890987654321");
    assert(f == f2);
    auto d = reader.unserialize!double();
    auto d2 = to!double("1234567890987654321234567890987654321");
    assert(d == d2);
    auto r = reader.unserialize!real();
    auto r2 = to!real("1234567890987654321234567890987654321");
    assert(r == r2);
    assert(reader.unserialize!(const BigInt)() == BigInt("1234567890987654321234567890987654321"));
}

unittest {
    import hprose.writer;
    BytesIO bytes = new BytesIO();
    Writer writer = new Writer(bytes);
    for (int i = 0; i < 6; i++) writer.serialize(-3.1415926);
    Reader reader = new Reader(bytes);
    assert(reader.unserialize!byte() == -3);
    assert(reader.unserialize!int() == -3);
    assert(reader.unserialize!bool() == true);
    auto f = reader.unserialize!float();
    auto f2 = to!float("-3.1415926");
    assert(f == f2);
    auto d = reader.unserialize!double();
    auto d2 = to!double("-3.1415926");
    assert(d == d2);
    auto r = reader.unserialize!real();
    auto r2 = to!real("-3.1415926");
    assert(r == r2);
}

unittest {
    import hprose.writer;
    BytesIO bytes = new BytesIO();
    Writer writer = new Writer(bytes);
    for (int i = 0; i < 6; i++) writer.serialize("123");
    Reader reader = new Reader(bytes);
    assert(reader.unserialize!byte() == cast(byte)123);
    assert(reader.unserialize!int() == 123);
    assert(reader.unserialize!bool() == true);
    auto f = reader.unserialize!float();
    auto f2 = to!float("123");
    assert(f == f2);
    auto d = reader.unserialize!double();
    auto d2 = to!double("123");
    assert(d == d2);
    auto r = reader.unserialize!real();
    auto r2 = to!real("123");
    assert(r == r2);
}

unittest {
    import hprose.writer;
    BytesIO bytes = new BytesIO();
    Writer writer = new Writer(bytes);
    for (int i = 0; i < 6; i++) writer.serialize([1,2,3,4,5,6,7]);
    Reader reader = new Reader(bytes);
    assert(reader.unserialize!(byte[])() == cast(byte[])[1,2,3,4,5,6,7]);
    assert(reader.unserialize!(ubyte[])() == cast(ubyte[])[1,2,3,4,5,6,7]);
    assert(reader.unserialize!(int[])() == [1,2,3,4,5,6,7]);
    assert(reader.unserialize!(uint[])() == [1,2,3,4,5,6,7]);
    assert(reader.unserialize!(const ulong[])() == cast(const ulong[])[1,2,3,4,5,6,7]);
    assert(reader.unserialize!(immutable(double)[])() == cast(immutable(double)[])[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]);
}

unittest {
    import hprose.writer;
    BytesIO bytes = new BytesIO();
    Writer writer = new Writer(bytes);
    for (int i = 0; i < 6; i++) writer.serialize(["Jane": 10.0, "Jack":20, "Bob":15]);
    Reader reader = new Reader(bytes);
    assert(reader.unserialize!(int[string])() == ["Jane": 10, "Jack":20, "Bob":15]);
    assert(reader.unserialize!(double[string])() == cast(double[string])["Jane": 10, "Jack":20, "Bob":15]);
    assert(reader.unserialize!(byte[string])() == cast(byte[string])["Jane": 10, "Jack":20, "Bob":15]);
    assert(reader.unserialize!(ubyte[string])() == cast(ubyte[string])["Jane": 10, "Jack":20, "Bob":15]);
    assert(reader.unserialize!(const long[string])() == cast(const long[string])["Jane": 10, "Jack":20, "Bob":15]);
    assert(reader.unserialize!(immutable ulong[string])() == cast(immutable ulong[string])["Jane": 10, "Jack":20, "Bob":15]);
}

unittest {
    int i = 1234567890;
    float f = cast(float)i;
    assert(f == 1234567890);
    BytesIO bytes = new BytesIO("D20141221T120808.342123432;r0;");
    Reader reader = new Reader(bytes);
    auto st = reader.unserialize!(SysTime)();
    auto st2 = reader.unserialize!(shared SysTime)();
    assert(st == st2);
    bytes.init("i123456789;u111");
    reader.reset();
    assert(reader.unserialize!(const int)() == 123456789);
    assert(reader.unserialize!(const double) == 1.0);
    assert(reader.unserialize!(int)() == 1);
    assert(reader.unserialize!(Nullable!int)() == 1);
}

unittest {
	import hprose.writer;
	import std.math;
	BytesIO bytes = new BytesIO();
	Writer writer = new Writer(bytes);
	writer.serialize(1);
	writer.serialize(long.max);
	writer.serialize(ulong.max);
	writer.serialize(BigInt("1234567890987654321234567890"));
	writer.serialize(PI);
	writer.serialize("你");
	writer.serialize("一闪一闪亮晶晶，烧饼油条卷大葱");
	writer.serialize(UUID("21f7f8de-8051-5b89-8680-0195ef798b6a"));
	writer.serialize(SysTime(DateTime(2015, 2, 8, 23, 05, 31)));
	writer.serialize(TimeOfDay(12, 12, 21));
	writer.serialize(Date(2015, 2, 8));
	Reader reader = new Reader(bytes);
	JSONValue jv = reader.unserialize!(JSONValue)();
	assert(jv == JSONValue(1));
	jv = reader.unserialize!(JSONValue)();
	assert(jv == JSONValue(long.max));
	jv = reader.unserialize!(JSONValue)();
	assert(jv == JSONValue(ulong.max));
	jv = reader.unserialize!(JSONValue)();
	assert(jv.str == "1234567890987654321234567890");
	jv = reader.unserialize!(JSONValue)();
	assert(jv == JSONValue(PI));
	jv = reader.unserialize!(JSONValue)();
	assert(jv.str == "你");
	jv = reader.unserialize!(JSONValue)();
	assert(jv.str == "一闪一闪亮晶晶，烧饼油条卷大葱");
	jv = reader.unserialize!(JSONValue)();
	assert(jv.str == "21f7f8de-8051-5b89-8680-0195ef798b6a");
	jv = reader.unserialize!(JSONValue)();
	assert(jv.str == "2015-Feb-08 23:05:31");
	jv = reader.unserialize!(JSONValue)();
	assert(jv.str == "12:12:21");
	jv = reader.unserialize!(JSONValue)();
	assert(jv.str == "2015-Feb-08 00:00:00");
}