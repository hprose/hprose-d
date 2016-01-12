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
 * hprose/rpc/httpcontext.d                               *
 *                                                        *
 * hprose http context class for D.                       *
 *                                                        *
 * LastModified: Jan 11, 2016                             *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.rpc.httpcontext;

import hprose.rpc.context;
import vibe.http.server;

class HttpContext: Context {
    HTTPServerRequest request;
    HTTPServerResponse response;
    this(HTTPServerRequest req, HTTPServerResponse res) {
        request = req;
        response = res;
    }
}