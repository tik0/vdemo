#!/usr/bin/env python3

import os
import queue
import sys
import threading
import tkinter
import logging
import re
import ssl
import base64
import string
import random
import socket
import csv
import io
from collections import namedtuple
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse
from string import Template

logging.basicConfig(format="++ %(message)s", level=logging.INFO)
tkroot = tkinter.Tk()
Response = namedtuple('Response', 'code location content content_type')


def make_response(code=200, location=None, content="", content_type="text/plain"):
    return Response(code=code, location=location, content=content, content_type=content_type)


class ServerRequestHandler(BaseHTTPRequestHandler):
    help_msg = bytes(
        "<html><head><title>vdemo help</title></head>"
        "<body>"
        "<p>Examples:</p>"
        "<p>http://localhost:4443/vdemo/api/list</p>"
        "<p>http://localhost:4443/vdemo/api/grouplist</p>"
        "<p>http://localhost:4443/vdemo/api/all/(start|stop|check)</p>"
        "<p>http://localhost:4443/vdemo/api/group/NAME/(start|stop|check)</p>"
        "<p>http://localhost:4443/vdemo/api/component/NAME/(start|stop|check)</p>"
        "<p>http://localhost:4443/vdemo/api/terminate</p>"
        "<p>http://localhost:4443/vdemo/api/busy</p>"
        "</body></html>", "utf-8")

    def __init__(self, request, client_address, server):
        self.transforms = (
            (re.compile("/vdemo/?"), "list", self.process_vdemo_frontpage),
            (re.compile("/vdemo/api(/list)?/?"), "list", self.process_vdemo_list),
            (re.compile("/vdemo/api/grouplist/?"), "grouplist", self.process_vdemo_grouplist),
            (re.compile("/vdemo/api/all/(?P<cmd>start|stop|check)/?"), "all %(cmd)s all", self.process_vdemo_allcmd),
            (re.compile("/vdemo/api/terminate/?"), "terminate", self.process_vdemo_terminate),
            (re.compile("/vdemo/api/busy/?"), "busy", self.process_vdemo_busy),
            (re.compile("/vdemo/api/group/(?P<group>[^/]+)/(?P<cmd>start|stop|check)/?"),
             "all %(cmd)s %(group)s", self.process_vdemo_groupcmd),
            (re.compile("/vdemo/api/component/(?P<comp>[^/]+)/(?P<cmd>start|stop|check|stopwait)/?"),
             "component %(comp)s %(cmd)s", self.process_vdemo_componentcmd)
        )
        self.authkey = server.authkey
        self.vdemo_request = server.vdemo_request
        self.replyQueue = server.replyQueue
        self.socket = server.socket
        self.templates = server.templates
        self.vdemo_id = server.vdemo_id
        super().__init__(request, client_address, server)

    def process_vdemo_frontpage(self, reply):
        reader = csv.DictReader(io.StringIO(reply), delimiter='\t', quoting=csv.QUOTE_NONE)
        rows = []
        grouprows = []
        groups = set()
        for row in reader:
            groups.add(row['group'])
            rows.append(Template(self.templates['row.html']).safe_substitute(row))
        for group in groups:
            grouprows.append(Template(self.templates['grouprow.html']).safe_substitute(group=group))

        result = Template(self.templates['main.html']).safe_substitute(
            rows="\n".join(rows), style=self.templates['vdemo.css'], vdemo_id=self.vdemo_id,
            grouprows="\n".join(grouprows))
        return make_response(content=result, content_type="text/html")

    def process_vdemo_list(self, reply):
        return make_response(content=reply)

    def process_vdemo_grouplist(self, reply):
        return make_response(content=reply)

    def process_vdemo_allcmd(self, reply):
        return make_response(code=202, content=reply, location="/vdemo/api/busy")

    def process_vdemo_terminate(self, reply):
        return make_response()

    def process_vdemo_busy(self, reply):
        if reply == "0":
            return make_response(code=303, location="/vdemo/api/list")
        else:
            return make_response(content=reply, location="/vdemo/api/busy")

    def process_vdemo_groupcmd(self, reply):
        return make_response(code=202, content=reply, location="/vdemo/api/busy")

    def process_vdemo_componentcmd(self, reply):
        return make_response(code=202, content=reply, location="/vdemo/api/busy")

    def get_vdemo_response(self, purl):
        for pat, fmt, process_func in self.transforms:
            m = re.fullmatch(pat, purl.path)
            if m:
                vdemo_cmd = fmt % m.groupdict()
                # the next statement modifies a tcl variable and triggers a trace callback
                # the result is communicated and popped here from replyQueue
                self.vdemo_request.set(vdemo_cmd)
                reply = self.replyQueue.get()
                self.replyQueue.task_done()
                return process_func(reply)
        return None

    def do_AUTHHEAD(self):
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm=\"vdemo\"')
        self.send_header('Content-type', 'text/html')
        self.send_header("Content-length", 0)
        self.end_headers()

    def do_GET(self):
        self.error_message_format = "ERROR: Bad request"
        authorized = (self.headers.get('Authorization') == 'Basic '+self.authkey)
        purl = urlparse(self.path)
        if authorized:
            response = self.get_vdemo_response(purl)
        else:
            response = None
        if response:
            content = bytes(response.content, "utf-8")
            logging.debug("webpath:'%(path)s' params:'%(params)s' query:'%(query)s'" % purl._asdict())
            self.send_response(response.code)
            self.send_header("Content-type", response.content_type)
            self.send_header("Content-length", len(content))
            if response.location:
                self.send_header("Location", response.location)
            self.end_headers()
            if response.content:
                self.wfile.write(content)
        elif purl.path == "/vdemo/api/help":
            content = self.help_msg
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.send_header("Content-length", len(content))
            self.end_headers()
            self.wfile.write(content)
        elif not self.headers.get('Authorization') or not authorized:
            self.do_AUTHHEAD()
        else:
            self.send_error(404)

    def log_message(self, format, *args):
        return


class VdemoApiServer(HTTPServer):

    def __init__(self, server_address, RequestHandlerClass, authkey):
        super().__init__(server_address, RequestHandlerClass)
        vdemodir = os.path.dirname(__file__)
        pemfilename = os.path.join(vdemodir, "vdemo_cert.pem")
        self.templates = self.load_templates(os.path.join(vdemodir, "webdata"))
        self.vdemo_id = os.path.splitext(os.path.basename(os.getenv("VDEMO_demoConfig", "vdemo")))[0]
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
        reply = tkroot.eval('if { [catch { global %s; set response [handle_remote_request {*}$%s] } msg] } { '
                            'return "ERROR\n$msg\n$::errorInfo" } { return $response }' % (varname, varname))
        self.replyQueue.put(reply)

    def load_templates(self, path):
        templates = {}
        for file in os.listdir(path):
            filepath = os.path.join(path, file)
            if os.path.isfile(filepath):
                templates[file] = open(filepath).read()
        return templates


class VDemo:

    def run(self):
        try:
            authkey = os.getenv("VDEMO_SERVER_KEY", None)
            serverport = os.getenv("VDEMO_SERVER_PORT", None)
            if serverport:
                if not authkey:
                    logging.warning("environment variable VDEMO_SERVER_KEY not set, generating random key")
                    authkey = ''.join(random.SystemRandom().choice(string.ascii_uppercase + string.digits) for _ in range(12))
                serverport = int(serverport)
                fqdn = socket.getfqdn()
                apiurl = "https://vdemo:%s@%s:%s/vdemo/api" % (authkey, fqdn, serverport)
                os.environ["VDEMO_apiurl"] = apiurl
                server = VdemoApiServer(('', serverport), ServerRequestHandler,
                                        base64.b64encode(bytes("vdemo:" + authkey, "utf-8")).decode('ascii'))
                thread = threading.Thread(None, server.serve_forever)
                thread.daemon = True
                thread.start()
            tkroot.eval('source "%s"' % sys.argv[1])
            if serverport:
                logging.info("vdemo api url: %s" % apiurl)
            tkroot.mainloop()
        except OSError:
            logging.exception("vdemo startup failed (if applicable use -s or VDEMO_SERVER_PORT to specifiy a different port)")
            tkroot.eval('catch { finish }')
        except SystemExit as ex:
            return ex.code
        except:
            logging.exception("error in vdemo controller")
        return 0



if __name__ == "__main__":
    if os.getenv("VDEMO_DEBUG_LEVEL", None):
        logging.basicConfig(level=logging.DEBUG)
    vd = VDemo()
    sys.exit(vd.run())
