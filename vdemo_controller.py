#!/usr/bin/env python3

import os
import queue
import sys
import threading
import tkinter
import logging
import re
import ssl
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

logging.basicConfig(format="++ %(message)s", level=logging.INFO)
tkroot = tkinter.Tk()
vdemo_request = tkinter.StringVar(value="")
replyQueue = queue.Queue()


class ServerRequestHandler(BaseHTTPRequestHandler):

    def __init__(self, request, client_address, server):
        self.transforms = (
            (re.compile("/vdemo/api(/list)?/?"), "list"),
            (re.compile("/vdemo/api/grouplist/?"), "grouplist"),
            (re.compile("/vdemo/api/all/(?P<cmd>start|stop|check)/?"), "all %(cmd)s all"),
            (re.compile("/vdemo/api/terminate/?"), "terminate"),
            (re.compile("/vdemo/api/group/(?P<group>[^/]+)/(?P<cmd>start|stop|check)/?"), "all %(cmd)s %(group)s"),
            (re.compile("/vdemo/api/component/(?P<comp>[^/]+)/(?P<cmd>start|stop|check|stopwait)/?"), "component %(comp)s %(cmd)s"),
        )
        super().__init__(request, client_address, server)

    def get_cmd(self, purl):
        for pat, fmt in self.transforms:
            m = re.fullmatch(pat, purl.path)
            if m:
                self.vdemo_cmd = fmt % m.groupdict()
                return True
        return False

    def get_vdemo_response(self, purl):
        if self.get_cmd(purl):
            # the next statement modifies a tcl variable and triggers a trace callback
            # the result is communicated and popped here from replyQueue
            vdemo_request.set(self.vdemo_cmd)
            self.vdemo_reply = replyQueue.get()
            replyQueue.task_done()
            return True
        return False

    def do_GET(self):
        #self.response_type = "text/html"
        self.response_type = "text/plain"
        self.error_message_format = "ERROR: Bad request"

        purl = urlparse(self.path)
        if self.get_vdemo_response(purl):
            logging.info("path:'%(path)s' params:'%(params)s' query:'%(query)s'" % purl._asdict())
            self.send_response(200)
            self.send_header("Content-type", self.response_type)
            self.end_headers()
            self.wfile.write(bytes(self.vdemo_reply, "utf-8"))
        elif purl.path == "/vdemo/api/help":
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()
            self.wfile.write(bytes(
                "<html><head><title>vdemo help</title></head>"
                "<body>"
                "<p>Examples:</p>"
                "<p>http://localhost:4443/vdemo/api/list</p>"
                "<p>http://localhost:4443/vdemo/api/grouplist</p>"
                "<p>http://localhost:4443/vdemo/api/all/(start|stop|check)</p>"
                "<p>http://localhost:4443/vdemo/api/group/NAME/(start|stop|check)</p>"
                "<p>http://localhost:4443/vdemo/api/component/NAME/(start|stop|check)</p>"
                "<p>http://localhost:4443/vdemo/api/terminate</p>"
                "</body></html>", "utf-8"))
        else:
            self.send_error(400)

    def log_message(self, format, *args):
        return


class VDemo:
    # evaluates the command using the tcl interpreter
    def handle_request(self, varname, index, op):
        # Note: a tcl error causes a segfault here
        reply = tkroot.eval('if { [catch { set response [handle_remote_request {*}$%s] } msg] } { '
                            'return "ERROR\n$msg" } { return $response }' % varname)
        replyQueue.put(reply)

    def run(self):
        tkroot.eval('source "%s"' % sys.argv[1])
        # The following statement causes the tcl event loop to callback if vdemo_request changes
        # This is thread safe, although frequently something else is assumed and a polling strategy is suggested.
        vdemo_request.trace("w", self.handle_request)
        if "VDEMO_SERVER_PORT" in os.environ:
            pemfile, pemfilename = tempfile.mkstemp(prefix="vdemo", suffix=".pem")
            subprocess.call(["bash", "-c", "openssl req -newkey rsa:2048 -x509 -nodes -keyout %s "
                                           "-new -out %s -subj /CN=localhost -reqexts SAN -extensions SAN "
                                           "-config <(cat /etc/ssl/openssl.cnf; printf '[SAN]\\nsubjectAltName=DNS:localhost') "
                                           "-sha256 -days 3650 &>/dev/null || echo error generating ssl certificate" % (pemfilename, pemfilename)])
            server = HTTPServer(('localhost', int(os.environ["VDEMO_SERVER_PORT"])), ServerRequestHandler)
            server.socket = ssl.wrap_socket(server.socket, certfile=pemfilename, server_side=True)
            os.close(pemfile)
            os.remove(pemfilename)
            thread = threading.Thread(None, server.serve_forever)
            thread.daemon = True
            thread.start()
        tkroot.mainloop()


if __name__ == "__main__":
    vd = VDemo()
    vd.run()
