var http = require('http');

var host = process.env.VCAP_APP_HOST || "127.0.0.1";
var port = process.env.VCAP_APP_PORT || 1337;

http.createServer(function (req, res) {
  res.writeHead(200, {'Content-Type': 'text/html'});
  res.write('<title>Stackato environment variables</title>');
  res.write('<h1>Stackato environment variables</h1>');
  res.write('<table>');
  for (var env in process.env){
    res.write('<tr><td style="text-align: right; vertical-align: top; padding: 4px 1em; "><b>'
              + env + '</b></td>');
    res.write('<td><tt style="font-family: Monaco, Consolas, monospace;">'
              + process.env[env] + '</tt></td></tr>');
  }
  res.write('</table>');
  res.end();
}).listen(port, host);

console.log('Server running at ' + host + ":" + port);
