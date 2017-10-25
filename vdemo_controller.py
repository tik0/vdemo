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
import base64
import string
import random
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

logging.basicConfig(format="++ %(message)s", level=logging.INFO)
tkroot = tkinter.Tk()


class ServerRequestHandler(BaseHTTPRequestHandler):

    def __init__(self, request, client_address, server):
        self.transforms = (
            (re.compile("/vdemo/api(/list)?/?"), "list", 200),
            (re.compile("/vdemo/api/grouplist/?"), "grouplist", 200),
            (re.compile("/vdemo/api/all/(?P<cmd>start|stop|check)/?"), "all %(cmd)s all", 202),
            (re.compile("/vdemo/api/terminate/?"), "terminate", 200),
            (re.compile("/vdemo/api/group/(?P<group>[^/]+)/(?P<cmd>start|stop|check)/?"), "all %(cmd)s %(group)s", 202),
            (re.compile("/vdemo/api/component/(?P<comp>[^/]+)/(?P<cmd>start|stop|check|stopwait)/?"), "component %(comp)s %(cmd)s", 202),
        )
        self.authkey = server.authkey
        self.vdemo_request = server.vdemo_request
        self.vdemo_reply = None
        self.replyQueue = server.replyQueue
        self.socket = server.socket
        super().__init__(request, client_address, server)

    def get_cmd(self, purl):
        for pat, fmt, response_code in self.transforms:
            m = re.fullmatch(pat, purl.path)
            if m:
                self.vdemo_cmd = fmt % m.groupdict()
                self.response_code = response_code
                return True
        return False

    def get_vdemo_response(self, purl):
        if self.get_cmd(purl):
            # the next statement modifies a tcl variable and triggers a trace callback
            # the result is communicated and popped here from replyQueue
            self.vdemo_request.set(self.vdemo_cmd)
            self.vdemo_reply = self.replyQueue.get()
            self.replyQueue.task_done()
            return True
        return False

    def do_AUTHHEAD(self):
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm=\"vdemo\"')
        self.send_header('Content-type', 'text/html')
        self.send_header("Content-length", 0)
        self.end_headers()

    def do_GET(self):
        self.response_type = "text/plain"
        self.error_message_format = "ERROR: Bad request"
        authorized = (self.headers.get('Authorization') == 'Basic '+self.authkey)
        purl = urlparse(self.path)
        if authorized and self.get_vdemo_response(purl):
            logging.info("webpath:'%(path)s' params:'%(params)s' query:'%(query)s'" % purl._asdict())
            content = bytes(self.vdemo_reply, "utf-8")
            self.send_response(self.response_code)
            self.send_header("Content-type", self.response_type)
            self.send_header("Content-length", len(content))
            if self.response_code == 202:
                self.send_header("Location", "/vdemo/api")
            self.end_headers()
            self.wfile.write(content)

        elif purl.path == "/vdemo/api/help":
            content = bytes(
                "<html><head><title>vdemo help</title></head>"
                "<body>"
                "<p>Examples:</p>"
                "<p>http://localhost:4443/vdemo/api/list</p>"
                "<p>http://localhost:4443/vdemo/api/grouplist</p>"
                "<p>http://localhost:4443/vdemo/api/all/(start|stop|check)</p>"
                "<p>http://localhost:4443/vdemo/api/group/NAME/(start|stop|check)</p>"
                "<p>http://localhost:4443/vdemo/api/component/NAME/(start|stop|check)</p>"
                "<p>http://localhost:4443/vdemo/api/terminate</p>"
                "</body></html>", "utf-8")
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.send_header("Content-length", len(content))
            self.end_headers()
            self.wfile.write(content)
        elif not self.headers.get('Authorization') or not authorized:
            self.do_AUTHHEAD()
        else:
            self.send_error(400)

    def log_message(self, format, *args):
        return


class VdemoApiServer(HTTPServer):

    def __init__(self, server_address, RequestHandlerClass, pemfilename, authkey):
        super().__init__(server_address, RequestHandlerClass)
        context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        context.load_cert_chain(certfile=pemfilename)  # 1. key, 2. cert, 3. intermediates
        context.options |= ssl.OP_NO_TLSv1 | ssl.OP_NO_TLSv1_1  # optional
        context.set_ciphers('EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH')
        self.socket = context.wrap_socket(self.socket, server_side=True)
        self.authkey = authkey
        self.vdemo_request = tkinter.StringVar(value="")
        self.replyQueue = queue.Queue()
        # The following statement causes the tcl event loop to callback if vdemo_request changes
        # This is thread safe, although frequently something else is assumed and a polling strategy is suggested.
        self.vdemo_request.trace("w", self.vdemo_request_callback)

    # evaluates the command using the tcl interpreter
    def vdemo_request_callback(self, varname, index, op):
        # Note: a tcl error causes a segfault here
        reply = tkroot.eval('if { [catch { set response [handle_remote_request {*}$%s] } msg] } { '
                            'return "ERROR\n$msg" } { return $response }' % varname)
        self.replyQueue.put(reply)


class VDemo:

    def run(self):
        tkroot.eval('source "%s"' % sys.argv[1])
        if "VDEMO_SERVER_KEY" in os.environ:
            authkey = os.environ["VDEMO_SERVER_KEY"]
        else:
            logging.warning("environment variable VDEMO_SERVER_KEY not set, generating random key")
            authkey = ''.join(random.SystemRandom().choice(string.ascii_uppercase + string.digits) for _ in range(12))
        if "VDEMO_SERVER_PORT" in os.environ:
            serverport = int(os.environ["VDEMO_SERVER_PORT"])
            fqdn = socket.getfqdn()
            logging.info("vdemo api url: https://vdemo:%s@%s:%s/vdemo/api" % (authkey, fqdn, serverport))
            pemfile, pemfilename = tempfile.mkstemp(prefix="vdemo", suffix=".pem")
            subprocess.run(["bash", "-c", "openssl req -newkey rsa:2048 -x509 -nodes -keyout %s "
                            "-new -out %s -subj /CN=%s -reqexts SAN -extensions SAN "
                            "-config <(cat /etc/ssl/openssl.cnf; printf '[SAN]\\nsubjectAltName=DNS:%s') "
                            "-sha256 -days 3650 &>/dev/null || echo error generating ssl certificate"
                            % (pemfilename, pemfilename, fqdn, fqdn)])
            server = VdemoApiServer(('', serverport), ServerRequestHandler, pemfilename,
                                    base64.b64encode(bytes("vdemo:" + authkey, "utf-8")).decode('ascii'))
            os.close(pemfile)
            os.remove(pemfilename)
            thread = threading.Thread(None, server.serve_forever)
            thread.daemon = True
            thread.start()
        tkroot.mainloop()


if __name__ == "__main__":
    vd = VDemo()
    vd.run()
