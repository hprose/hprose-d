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
 * hprose/rpc/context.d                                   *
 *                                                        *
 * hprose context class for D.                            *
 *                                                        *
 * LastModified: Jan 11, 2016                             *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.rpc.context;

import std.variant;

class Context {
    public Variant[string] userdata;
    T get(T)(string key) {
        return userdata.get!(T)(key);
    }
    void set(T)(string key, T value) {
        userdata[key] = Variant!T(value);
    }
}
