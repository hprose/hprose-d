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
 * hprose/io/tags.d                                       *
 *                                                        *
 * hprose tags for D.                                     *
 *                                                        *
 * LastModified: Mar 3, 2015                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
\**********************************************************/

module hprose.io.tags;
@safe:

enum
    /* Serialize Tags */
    TagInteger     = 'i',
    TagLong        = 'l',
    TagDouble      = 'd',
    TagNull        = 'n',
    TagEmpty       = 'e',
    TagTrue        = 't',
    TagFalse       = 'f',
    TagNaN         = 'N',
    TagInfinity    = 'I',
    TagDate        = 'D',
    TagTime        = 'T',
    TagUTC         = 'Z',
    TagBytes       = 'b',
    TagUTF8Char    = 'u',
    TagString      = 's',
    TagGuid        = 'g',
    TagList        = 'a',
    TagMap         = 'm',
    TagClass       = 'c',
    TagObject      = 'o',
    TagRef         = 'r',
    /* Serialize Marks */
    TagPos         = '+',
    TagNeg         = '-',
    TagSemicolon   = ';',
    TagOpenbrace   = '{',
    TagClosebrace  = '}',
    TagQuote       = '"',
    TagPoint       = '.',
    /* Protocol Tags */
    TagFunctions   = 'F',
    TagCall        = 'C',
    TagResult      = 'R',
    TagArgument    = 'A',
    TagError       = 'E',
    TagEnd         = 'z';
