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
 * LastModified: Aug 4, 2014                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.reader;
@safe:

import hprose.bytes;
import hprose.common;
import hprose.classmanager;
import hprose.tags;
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

private alias void* any;

private interface ReaderRefer {
    void set(in any value);
    const any read(int index);
    void reset();
}

private final class FakeReaderRefer : ReaderRefer {
    void set(in any value) {}
    const any read(int index) {
        throw new Exception("Unexcepted serialize tag '" ~ TagRef ~ "' in stream");
    }
    void reset() {}
}

class Reader {
    this() {
    }
}

