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
 * hprose/io/writer.d                                     *
 *                                                        *
 * hprose writer library for D.                           *
 *                                                        *
 * LastModified: Jul 15, 2015                             *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.io.writer;

@trusted:

import hprose.io.bytes;
import hprose.io.classmanager;
import hprose.io.common;
import hprose.io.tags;
import std.bigint;
import std.container;
import std.datetime;
import std.json;
import std.math;
import std.stdio;
import std.string;
import std.traits;
import std.typecons;
import std.typetuple;
import std.utf;
import std.uuid;
import std.variant;

private {
    alias void* any;

    interface WriterRefer {
        void set(in any value);
        bool write(in any value);
        void reset();
    }

    final class FakeWriterRefer : WriterRefer {
        void set(in any value) {}
        bool write(in any value) { return false; }
        void reset() {}
    }

    final class RealWriterRefer : WriterRefer {
        private int[any] _references;
        private int _refcount = 0;
        private BytesIO _bytes;
        this(BytesIO bytes) {
            _bytes = bytes;
        }
        void set(in any value) {
            if (value !is null) {
                _references[value] = _refcount;
            }
            ++_refcount;
        }
        bool write(in any value) {
            if (value is null) return false;
            int i = _references.get(value, -1);
            if (i < 0) return false;
            _bytes.write(TagRef).write(i).write(TagSemicolon);
            return true;
        }
        void reset() {
            _references = null;
            _refcount = 0;
        }
    }
}

unittest {
    class Test {
        int a;
    }
    BytesIO bytes = new BytesIO();
    WriterRefer wr = new RealWriterRefer(bytes);
    string s = "hello";
    assert(wr.write(cast(any)s) == false);
    wr.set(cast(any)s);
    assert(wr.write(cast(any)s) == true);
    int[] a = [1,2,3,4,5,6];
    assert(wr.write(cast(any)a) == false);
    wr.set(cast(any)a);
    assert(wr.write(cast(any)a) == true);
    int[string] m = ["hello":1, "world":2];
    assert(wr.write(cast(any)m) == false);
    wr.set(cast(any)m);
    assert(wr.write(cast(any)m) == true);
    Test t = new Test();
    assert(wr.write(cast(any)t) == false);
    wr.set(cast(any)t);
    assert(wr.write(cast(any)t) == true);
    wr.reset();
    assert(wr.write(cast(any)s) == false);
    assert(wr.write(cast(any)a) == false);
    assert(wr.write(cast(any)m) == false);
    assert(wr.write(cast(any)t) == false);
}

class Writer {
    private {
        BytesIO _bytes;
        WriterRefer _refer;
        int[string] _classref;
        int _crcount = 0;

        pure string hnsecsToString(int hnsecs) {
            if (hnsecs == 0) return "";
            if (hnsecs % 10000 == 0) {
                return TagPoint ~ format("%03d", hnsecs / 10000);
            }
            else if (hnsecs % 10 == 0) {
                return TagPoint ~ format("%06d", hnsecs / 10);
            }
            else {
                return TagPoint ~ format("%09d", hnsecs * 100);
            }
        }

        int writeClass(T)(string name) if (is(T == struct) || is(T == class)) {
            _bytes.write(TagClass).write(name.length).write(TagQuote).write(name).write(TagQuote);
            enum fieldList = getSerializableFields!T;
            enum count = fieldList.length;
            if (count > 0) _bytes.write(count);
            _bytes.write(TagOpenbrace);
            foreach(f; fieldList) {
                writeString(f);
            }
            _bytes.write(TagClosebrace);
            int index = _crcount++;
            _classref[name] = index;
            return index;
        }
    }

    this(BytesIO bytes, bool simple = false) {
        _bytes = bytes;
        if (simple) {
            _refer = new FakeWriterRefer();
        }
        else {
            _refer = new RealWriterRefer(_bytes);
        }
    }
    void reset() {
        _refer.reset();
        _classref = null;
        _crcount = 0;
    }
    void serialize(T)(ref T value) if (isStaticArray!T) {
        serialize(value[0 .. $]);
    }
    void serialize(T)(T value) if (isSerializable!T) {
        alias Unqual!T U;
        static if (is(U == typeof(null))) {
            writeNull();
        }
        else static if (is(U == enum)) {
            serialize!(OriginalType!T)(cast(OriginalType!T)value);
        }
        else static if (isIntegral!U) {
            static if (is(U == byte) ||
                is(U == ubyte) ||
                is(U == short) ||
                is(U == ushort) ||
                is(U == int)) {
                writeInteger(cast(int)value);
            }
            else static if (is(U == long)) {
                if (value > int.max || value < int.min) {
                    writeLong(value);
                }
                else {
                    writeInteger(cast(int)value);
                }
            }
            else {
                if (value > int.max) {
                    writeLong(value);
                }
                else {
                    writeInteger(cast(int)value);
                }
            }
        }
        else static if (is(U : BigInt)) {
            writeLong(value);
        }
        else static if (isFloatingPoint!U) {
            writeDouble(value);
        }
        else static if (isBoolean!U) {
            writeBool(value);
        }
        else static if (isSomeChar!U) {
            static if (is(T == dchar)) {
                if (value > value.init) {
                    char[4] buf;
                    writeString(toUTF8(buf, value));
                }
                else {
                    writeUtf8Char(cast(wchar)value);
                }
            }
            else {
                writeUtf8Char(cast(wchar)value);
            }
        }
        else static if (isStaticArray!U) {
            serialize(value[0 .. $]);
        }
        else static if (is(U == struct)) {
            static if (isInstanceOf!(Nullable, U)) {
                if (value.isNull()) {
                    writeNull();
                }
                else {
                    serialize(value.get());
                }
            }
            else static if (is(U == DateTime)) {
                writeDateTime(value);
            }
            else static if (is(U == Date)) {
                writeDate(value);
            }
            else static if (is(U == TimeOfDay)) {
                writeTime(value);
            }
            else static if (is(U == SysTime)) {
                writeSysTime(value);
            }
            else static if (is(U == UUID)) {
                writeUUID(value);
            }
            else static if (is(U == JSONValue)) {
                final switch (value.type()) {
                    case JSON_TYPE.STRING:   serialize(value.str);      break;
                    case JSON_TYPE.INTEGER:  serialize(value.integer);  break;
                    case JSON_TYPE.UINTEGER: serialize(value.uinteger); break;
                    case JSON_TYPE.FLOAT:    serialize(value.floating); break;
                    case JSON_TYPE.OBJECT:   serialize(value.object);   break;
                    case JSON_TYPE.ARRAY:    serialize(value.array);    break;
                    case JSON_TYPE.TRUE:     serialize(true);           break;
                    case JSON_TYPE.FALSE:    serialize(false);          break;
                    case JSON_TYPE.NULL:     serialize(null);           break;
                }
            }
            else static if (is(U == Variant)) {
                Variant v = value;
                alias TypeTuple!(byte, ubyte, short, ushort, int, uint, long, ulong,
                    float, double, real, bool, char, wchar, dchar,
                    BigInt, DateTime, Date, TimeOfDay, SysTime,
                    UUID, Variant, JSONValue) typeTuple;
                TypeInfo type = value.type();
                if (type is typeid(null)) {
                    return writeNull();
                }
                foreach(V; typeTuple) {
                    if (type is typeid(V)) {
                        return serialize(v.get!(V));
                    }
                    else if (type is typeid(V[])) {
                        return serialize(v.get!(V[]));
                    }
                    else if (type is typeid(const(V)[])) {
                        return serialize(v.get!(const(V)[]));
                    }
                    else if (type is typeid(immutable(V)[])) {
                        return serialize(v.get!(immutable(V)[]));
                    }
                    foreach(K; typeTuple) {
                        if (type is typeid(V[K])) {
                            return serialize(v.get!(V[K]));
                        }
                    }
                }
                throw new Exception("Not support to serialize this data.");
            }
            else static if (isIterable!U) {
                writeArrayWithRef(value);
            }
            else {
                writeObject(value);
            }
        }
        else static if (is(U == class) ||
            isSomeString!U ||
            isDynamicArray!U ||
            isAssociativeArray!U) {
            if (value is null) {
                writeNull();
            }
            else static if (isSomeString!U) {
                if (value.length == 0) {
                    writeEmpty();
                }
                else {
                    writeStringWithRef(value);
                }
            }
            else static if (isDynamicArray!U) {
                static if (is(Unqual!(ForeachType!U) == ubyte) ||
                    is(Unqual!(ForeachType!U) == byte)) {
                    writeBytesWithRef(value);
                }
                else {
                    writeArrayWithRef(value);
                }
            }
            else static if (isAssociativeArray!U) {
                writeAssociativeArrayWithRef(value);
            }
            else static if (isIterable!U) {
                writeArrayWithRef(value);
            }
            else {
                writeObjectWithRef(value);
            }
        }
        else {
            throw new Exception("Not support to serialize this data.");
        }
    }
    void writeNull() {
        _bytes.write(TagNull);
    }
    void writeInteger(int value) {
        if (value >= 0 && value <= 9) {
            _bytes.write(value);
        }
        else {
            _bytes.write(TagInteger).write(value).write(TagSemicolon);
        }
    }
    void writeLong(T)(in T value) if (is(T == uint) || is(T == long) || is(T == ulong)) {
        _bytes.write(TagLong).write(value).write(TagSemicolon);
    }
    void writeLong(BigInt value) {
        _bytes.write(TagLong).write(value.toDecimalString()).write(TagSemicolon);
    }
    void writeDouble(T)(in T value) if (isFloatingPoint!T) {
        if (isNaN(value)) {
            _bytes.write(TagNaN);
        }
        else if (isInfinity(value)) {
            _bytes.write(TagInfinity).write(value > 0 ? TagPos : TagNeg);
        }
        else {
            _bytes.write(TagDouble).write(value).write(TagSemicolon);
        }
    }
    void writeBool(bool value) {
        _bytes.write(value ? TagTrue : TagFalse);
    }
    void writeUtf8Char(wchar value) {
        _bytes.write(TagUTF8Char).write(toUTF8([value]));
    }
    void writeDateTime(DateTime value) {
        if (!value.isAD) {
            throw new Exception("Years BC is not supported in hprose.");
        }
        if (value.year > 9999) {
            throw new Exception("Year after 9999 is not supported in hprose.");
        }
        _refer.set(null);
        _bytes.write(TagDate).write(value.toISOString()).write(TagSemicolon);
    }
    void writeDate(Date value) {
        if (!value.isAD) {
            throw new Exception("Years BC is not supported in hprose.");
        }
        if (value.year > 9999) {
            throw new Exception("Year after 9999 is not supported in hprose.");
        }
        _refer.set(null);
        _bytes.write(TagDate).write(value.toISOString()).write(TagSemicolon);
    }
    void writeTime(TimeOfDay value) {
        _refer.set(null);
        _bytes.write(TagTime).write(value.toISOString()).write(TagSemicolon);
    }
    void writeSysTime(SysTime value) {
        if (!value.isAD) {
            throw new Exception("Years BC is not supported in hprose.");
        }
        if (value.year > 9999) {
            throw new Exception("Year after 9999 is not supported in hprose.");
        }
        const auto tzType = typeid(value.timezone);
        const bool isLocalTime = tzType is typeid(LocalTime);
        if (isLocalTime || tzType is typeid(UTC)) {
            _refer.set(null);
            const char tag = isLocalTime ? TagSemicolon : TagUTC;
            int hnsecs = value.fracSec.hnsecs;
            Date date = Date(value.year, value.month, value.day);
            TimeOfDay time = TimeOfDay(value.hour, value.minute, value.second);
            if (time == TimeOfDay(0, 0, 0) && hnsecs == 0) {
                _bytes.write(TagDate)
                    .write(date.toISOString())
                        .write(tag);
            }
            else if (date == Date(1970, 1, 1)) {
                _bytes.write(TagTime)
                    .write(time.toISOString())
                        .write(hnsecsToString(hnsecs))
                        .write(tag);
            }
            else {
                _bytes.write(TagDate)
                    .write(date.toISOString())
                        .write(TagTime)
                        .write(time.toISOString())
                        .write(hnsecsToString(hnsecs))
                        .write(tag);
            }
        }
        else {
            writeSysTime(value.toUTC());
        }
    }
    void writeUUID(UUID value) {
        _refer.set(null);
        _bytes.write(TagGuid).write(TagQuote).write(value.toString()).write(TagQuote);
    }
    void writeEmpty() {
        _bytes.write(TagEmpty);
    }
    void writeString(T)(T value) if (isSomeString!T) {
        _refer.set(cast(any)value);
        _bytes.write(TagString);
        auto len = codeLength!wchar(value);
        if (len > 0) _bytes.write(len);
        static if (is(T : const char[])) {
            _bytes.write(TagQuote).write(value).write(TagQuote);
        }
        else {
            _bytes.write(TagQuote).write(toUTF8(value)).write(TagQuote);
        }
    }
    void writeStringWithRef(T)(T value) if (isSomeString!T) {
        if (!_refer.write(cast(any)value)) writeString(value);
    }
    void writeBytes(T)(T value)
        if (isDynamicArray!T &&
            (is(Unqual!(ForeachType!T) == ubyte) ||
            is(Unqual!(ForeachType!T) == byte))) {
        _refer.set(cast(any)value);
        _bytes.write(TagBytes);
        auto len = value.length;
        if (len > 0) _bytes.write(len);
        _bytes.write(TagQuote).write(value).write(TagQuote);
    }
    void writeBytesWithRef(T)(T value)
        if (isDynamicArray!T &&
            (is(Unqual!(ForeachType!T) == ubyte) ||
            is(Unqual!(ForeachType!T) == byte))) {
        if (!_refer.write(cast(any)value)) writeBytes(value);
    }
    void writeArray(T)(T value) if ((isIterable!T || isDynamicArray!T) && isSerializable!T) {
        static if (isDynamicArray!T &&
            is(Unqual!(ForeachType!T) == ubyte) ||
            is(Unqual!(ForeachType!T) == byte)) {
            writeBytes(value);
        }
        else static if (isSomeString!T) {
            writeString(value);
        }
        else {
            static if (is(T == struct)) {
                _refer.set(null);
            }
            else {
                _refer.set(cast(any)value);
            }
            _bytes.write(TagList);
            static if (isDynamicArray!T ||
                __traits(hasMember, T, "length") &&
                is(typeof(__traits(getMember, T.init, "length")) == size_t)) {
                auto len = value.length;
            }
            else {
                auto len = 0;
                foreach(ref e; value) { ++len; }
            }
            if (len > 0) _bytes.write(len);
            _bytes.write(TagOpenbrace);
            foreach(ref e; value) serialize(e);
            _bytes.write(TagClosebrace);
        }
    }
    alias writeArray writeList;
    void writeArrayWithRef(T)(T value) if ((isIterable!T || isDynamicArray!T) && isSerializable!T) {
        static if (is(T == struct)) {
            writeArray(value);
        }
        else {
            if (!_refer.write(cast(any)value)) writeArray(value);
        }
    }
    alias writeArrayWithRef writeListWithRef;
    void writeAssociativeArray(T)(T value) if (isAssociativeArray!T && isSerializable!T) {
        _refer.set(cast(any)value);
        _bytes.write(TagMap);
        auto len = value.length;
        if (len > 0) _bytes.write(len);
        _bytes.write(TagOpenbrace);
        foreach(k, ref v; value) {
            serialize(k);
            serialize(v);
        }
        _bytes.write(TagClosebrace);
    }
    alias writeAssociativeArray writeMap;
    void writeAssociativeArrayWithRef(T)(T value) if (isAssociativeArray!T && isSerializable!T) {
        if (!_refer.write(cast(any)value)) writeAssociativeArray(value);
    }
    alias writeAssociativeArrayWithRef writeMapWithRef;
    void writeObject(T)(T value) if (is(T == struct) || is(T == class)) {
        string name = ClassManager.getAlias!T;
        int index = _classref.get(name, writeClass!T(name));
        static if (is(T == struct)) {
            _refer.set(null);
        }
        else {
            _refer.set(cast(any)value);
        }
        _bytes.write(TagObject).write(index).write(TagOpenbrace);
        enum fieldList = getSerializableFields!T;
        foreach(f; fieldList) {
            serialize(__traits(getMember, value, f));
        }
        _bytes.write(TagClosebrace);
    }
    void writeObjectWithRef(T)(T value) if (is(T == struct) || is(T == class)) {
        static if (is(T == struct)) {
            writeObject(value);
        }
        else {
            if (!_refer.write(cast(any)value)) writeObject(value);
        }
    }
    void writeTuple(T...)(T args) {
        _refer.set(null);
        _bytes.write(TagList);
        auto len = args.length;
        if (len > 0) _bytes.write(len);
        _bytes.write(TagOpenbrace);
        foreach(ref e; args) serialize(e);
        _bytes.write(TagClosebrace);
    }
}

private {
    class MyClass {
        const int a;
        static const byte b;
        private int c = 3;
        @property {
            int x() const { return c; }
            int x(int value) { return c = value; }
        }
        this() { this.a = 1; }
        this(int a) { this.a = a; }
        void hello() {}
    };

    struct MyStruct {
        static const byte b;
        int c = 3;
        void hello() {}
    }
}

unittest {
    BytesIO bytes = new BytesIO();
    Writer rw = new Writer(bytes);
    Writer fw = new Writer(bytes, true);
    MyClass mc = null;
    int[] nia = null;
    int[string] nias = null;
    fw.serialize(null);
    fw.serialize(mc);
    fw.serialize(nia);
    fw.serialize(nias);
    fw.serialize(1);
    fw.serialize(12345);
    int i = -123456789;
    fw.serialize(i);
    assert(bytes.toString() == "nnnn1i12345;i-123456789;");

    bytes.init("");
    rw.serialize(BigInt(1234567890987654321L));
    assert(bytes.toString() == "l1234567890987654321;");

    bytes.init("");
    rw.serialize(3.14159265358979323846f);
    rw.serialize(3.14159265358979323846);
    rw.serialize(float.nan);
    rw.serialize(double.nan);
    rw.serialize(float.infinity);
    rw.serialize(-real.infinity);
    assert(bytes.toString() == "d3.14159;d3.141592653589793;NNI+I-");

    bytes.init("");
    rw.serialize(true);
    rw.serialize(false);
    assert(bytes.toString() == "tf");

    bytes.init("");
    rw.serialize(Date(1980, 12, 01));
    assert(bytes.toString() == "D19801201;");

    bytes.init("");
    rw.serialize(DateTime(1980, 12, 01, 17, 48, 54));
    assert(bytes.toString() == "D19801201T174854;");

    bytes.init("");
    rw.serialize(DateTime(1980, 12, 01));
    assert(bytes.toString() == "D19801201T000000;");

    bytes.init("");
    rw.serialize(TimeOfDay(17, 48, 54));
    assert(bytes.toString() == "T174854;");

    bytes.init("");
    rw.serialize(SysTime(DateTime(1980, 12, 01, 17, 48, 54)));
    assert(bytes.toString() == "D19801201T174854;");

    bytes.init("");
    rw.serialize(SysTime(DateTime(1980, 12, 01, 17, 48, 54), UTC()));
    assert(bytes.toString() == "D19801201T174854Z");

    bytes.init("");
    rw.serialize(SysTime(DateTime(1980, 12, 01, 17, 48, 54), FracSec.from!"usecs"(802_400)));
    assert(bytes.toString() == "D19801201T174854.802400;");

    bytes.init("");
    rw.serialize(SysTime(DateTime(1980, 12, 01, 17, 48, 54), FracSec.from!"usecs"(802_4), UTC()));
    assert(bytes.toString() == "D19801201T174854.008024Z");

    bytes.init("");
    rw.serialize(UUID());
    assert(bytes.toString() == "g\"00000000-0000-0000-0000-000000000000\"");

    bytes.init("");
    rw.serialize(dnsNamespace);
    assert(bytes.toString() == "g\"" ~ dnsNamespace.toString() ~ "\"");

    bytes.init("");
    rw.reset();
    rw.serialize("");
    rw.serialize('我');
    rw.serialize("hello");
    rw.serialize("hello");
    assert(bytes.toString() == "eu我s5\"hello\"r0;");

    ubyte[8] ba1 = [0,1,2,3,4,5,0x90,0xff];
    ubyte[8] ba2 = [0,1,2,3,4,5,0x90,0xff];
    bytes.init("");
    rw.reset();
    rw.serialize(ba1);
    rw.serialize(ba1);
    rw.serialize(ba2);
    assert(bytes.toString() == "b8\"\x00\x01\x02\x03\x04\x05\x90\xff\"r0;b8\"\x00\x01\x02\x03\x04\x05\x90\xff\"");
    int[5] ia = [0,1,2,3,4];
    int[] ida = [0,1,2,3,4];

    bytes.init("");
    rw.reset();
    rw.serialize(ia);
    rw.serialize(ida);
    rw.serialize(ia);
    assert(bytes.toString() == "a5{01234}a5{01234}r0;");
    string[string] ssa = ["Hello": "World", "Hi": "World"];

    bytes.init("");
    rw.reset();
    rw.serialize(ssa);
    rw.serialize(ssa);
    assert(bytes.toString() == "m2{s5\"Hello\"s5\"World\"s2\"Hi\"r2;}r0;");

    bytes.init("");
    rw.reset();
    rw.serialize(MyStruct());
    rw.serialize(new MyClass());
    assert(bytes.toString() == "c8\"MyStruct\"1{s1\"c\"}o0{3}c7\"MyClass\"1{s1\"x\"}o1{3}");

    SList!(int) slist = SList!(int)([1,2,3,4,5,6,7]);
    Array!(int) array = Array!(int)([1,2,3,4,5,6,7]);
    bytes.init("");
    rw.reset();
    rw.serialize(slist);
    rw.serialize(array);
    rw.serialize(array);
    assert(bytes.toString() == "a7{1234567}a7{1234567}a7{1234567}");

    const char[] a = ['\xe4','\xbd','\xa0','\xe5','\xa5','\xbd'];
    const Variant vi = a;
    const JSONValue jv = 12;
    bytes.init("");
    rw.reset();
    rw.serialize(vi);
    rw.serialize(jv);
    assert(bytes.toString() == "s2\"你好\"i12;");

    Nullable!int ni = 10;
    bytes.init("");
    rw.reset();
    rw.serialize(ni);
    ni.nullify();
    rw.serialize(ni);
    assert(bytes.toString() == "i10;n");

    bytes.init("");
    rw.reset();
    rw.writeTuple(1,"Hello", "Hello");
    assert(bytes.toString() == "a3{1s5\"Hello\"r1;}");

    enum Color {
        Red, Blue, Green
    }
    bytes.init("");
    rw.reset();
    rw.writeTuple(Color.Red, Color.Blue, Color.Green);
    rw.serialize(tuple(Color.Red, Color.Blue, Color.Green));
    rw.writeArray(tuple(Color.Red, Color.Blue, Color.Green));
    assert(bytes.toString() == "a3{012}a3{012}a3{012}");
}
