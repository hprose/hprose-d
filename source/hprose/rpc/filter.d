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
 * hprose/rpc/filter.d                                    *
 *                                                        *
 * hprose filter interface for D.                         *
 *                                                        *
 * LastModified: Mar 3, 2015                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.rpc.filter;

import hprose.rpc.context;

interface Filter {
    ubyte[] inputFilter(ubyte[] data, Context context);
    ubyte[] outputFilter(ubyte[] data, Context context);
}
