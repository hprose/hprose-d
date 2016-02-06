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
 * hprose/rpc/tcpcontext.d                                *
 *                                                        *
 * hprose tcp context class for D.                        *
 *                                                        *
 * LastModified: Feb 1, 2016                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.rpc.tcpcontext;

import hprose.rpc.context;
import vibe.core.net;

class TcpContext: Context {
    TCPConnection conn;
    this(TCPConnection conn) {
        this.conn = conn;
    }
}