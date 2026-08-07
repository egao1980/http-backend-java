(in-package #:http-backend-java)

;;; Sync + async http-protocol backend over java.net.http.HttpClient (ABCL).

(defclass java-backend (http-backend ws-backend)
  ((http-client :initarg :http-client :accessor java-backend-http-client
                :initform nil
                :documentation "Cached java.net.http.HttpClient instance."))
  (:default-initargs :name "java"))

(defvar *java-http-client* nil
  "Optional shared HttpClient override for tests.")

(defun make-java-backend ()
  #-abcl
  (error 'unsupported-operation
         :operation 'make-java-backend
         :message "http-backend-java requires ABCL (java.net.http)")
  #+abcl
  (make-instance 'java-backend))

(defmethod backend-http-versions ((backend java-backend))
  (declare (ignore backend))
  ;; HttpClient negotiates h2 when available; we advertise both.
  '(:http/1.1 :http/2))

(defmethod backend-ws-transports ((backend java-backend))
  (declare (ignore backend))
  ;; java.net.http.WebSocket is RFC 6455 (HTTP/1.1 Upgrade).
  #+abcl '(:http/1.1)
  #-abcl '())

#+abcl
(defun %ensure-http-client (backend &key (follow-redirects t) (verify t))
  (or *java-http-client*
      (java-backend-http-client backend)
      (let* ((b (%jstatic "newBuilder" "java.net.http.HttpClient"))
             (redir (if follow-redirects
                        (java:jfield "java.net.http.HttpClient$Redirect" "NORMAL")
                        (java:jfield "java.net.http.HttpClient$Redirect" "NEVER")))
             (b (%jcall "followRedirects" b redir))
             ;; TLS verify: default SSLContext; insecure needs custom trust (TODO).
             (client (%jcall "build" b)))
        (declare (ignore verify))
        (setf (java-backend-http-client backend) client)
        client)))

#+abcl
(defun %header-alist (headers)
  (loop for pair in headers
        for name = (string-downcase (string (if (consp pair) (car pair) pair)))
        for value = (if (consp pair) (cdr pair) nil)
        when value
          collect (cons name (if (stringp value) value (princ-to-string value)))))

#+abcl
(defun %merge-headers (client-headers request-headers)
  (append (%header-alist client-headers)
          (%header-alist request-headers)))

#+abcl
(defun %build-java-request (url method headers body)
  (let* ((uri (java:jnew "java.net.URI" url))
         (b (%jstatic "newBuilder" "java.net.http.HttpRequest" uri))
         (method* (string-upcase (string method)))
         (publisher (if body
                        (%jstatic "ofByteArray" "java.net.http.HttpRequest$BodyPublishers"
                                  (%octets-to-jbytes (coerce-to-octets body)))
                        (%jstatic "noBody" "java.net.http.HttpRequest$BodyPublishers"))))
    (setf b (%jcall "method" b method* publisher))
    (dolist (pair headers)
      (let ((name (car pair)) (val (cdr pair)))
        ;; HttpClient forbids hop-by-hop headers; skip host/content-length if set by publisher.
        (unless (member name '("host" "content-length" "connection" "upgrade")
                        :test #'string-equal)
          (ignore-errors
            (setf b (%jcall "header" b name (princ-to-string val)))))))
    (%jcall "build" b)))

#+abcl
(defun %version-keyword (jversion)
  (let ((v (string (%jcall "toString" jversion))))
    (if (search "2" v) :http/2 :http/1.1)))

#+abcl
(defun %java-response->http-response (jresp request url cookie-jar &key decompress)
  (let* ((status (%jcall "statusCode" jresp))
         (jheaders (%jcall "headers" jresp))
         (alist (%headers-to-alist jheaders))
         (ht (%alist-to-ht alist))
         (body (%jbytes-to-octets (%jcall "body" jresp)))
         (version (%version-keyword (%jcall "version" jresp)))
         (uri (%jcall "toString" (%jcall "uri" jresp)))
         (final-url (or uri url)))
    (merge-response-cookies cookie-jar final-url ht)
    (multiple-value-bind (body* headers*)
        (if decompress
            (let ((ce (gethash "content-encoding" ht)))
              (if ce
                  (let* ((codings (parse-content-encoding ce))
                         (decoded (if codings
                                      (ignore-errors (decode-content-codings codings body))
                                      body)))
                    (values (or decoded body)
                            (let ((n (make-hash-table :test #'equal)))
                              (maphash (lambda (k v) (setf (gethash k n) v)) ht)
                              (remhash "content-encoding" n)
                              (remhash "content-length" n)
                              n)))
                  (values body ht)))
            (values body ht))
      (make-instance 'http-response
                     :status status
                     :headers headers*
                     :body body*
                     :url final-url
                     :http-version version
                     :request request))))

(defmethod send ((backend java-backend) client request &key)
  #+abcl
  (let* ((url (http-request-url request))
         (method (http-request-method request))
         (headers (%merge-headers (http-client-headers client)
                                  (http-request-headers request)))
         (timeout (or (http-request-timeout request)
                      (http-client-timeout client)))
         (max-redirects (or (http-request-max-redirects request)
                            (http-client-max-redirects client)))
         (verify (http-client-verify client))
         (cookie-jar (resolve-cookie-jar client request :url url))
         (follow (not (eql max-redirects 0))))
    (setf headers (inject-auth-range-headers
                   headers
                   :auth (effective-auth client request)
                   :range (http-request-range request)))
    (multiple-value-bind (content extra-headers content-length)
        (prepare-request-body request)
      (declare (ignore content-length))
      (setf headers (append headers extra-headers))
      (when (streamp content)
        (error 'unsupported-operation
               :operation :stream-body
               :message "http-backend-java wave-1: stream bodies not yet supported; pass octets"))
      (let* ((jclient (%ensure-http-client backend
                                           :follow-redirects follow
                                           :verify verify))
             (jreq (%build-java-request url method headers content))
             (handler (%jstatic "ofByteArray" "java.net.http.HttpResponse$BodyHandlers"))
             (jresp (if (and (numberp timeout) (plusp timeout))
                        ;; Timeout via HttpRequest.Builder.timeout — rebuild if needed.
                        (%jcall "send" jclient jreq handler)
                        (%jcall "send" jclient jreq handler))))
        (declare (ignore timeout))
        (%java-response->http-response
         jresp request url cookie-jar
         :decompress (http-request-decompress request)))))
  #-abcl
  (error 'unsupported-operation :operation 'send
         :message "http-backend-java requires ABCL"))

(defclass java-async-handle ()
  ((future :initarg :future :reader java-async-future)
   (canceled :initform nil :accessor java-async-canceled-p)))

(defmethod send-async ((backend java-backend) client request
                       &key callback error-callback)
  #+abcl
  (let* ((url (http-request-url request))
         (method (http-request-method request))
         (headers (%merge-headers (http-client-headers client)
                                  (http-request-headers request)))
         (cookie-jar (resolve-cookie-jar client request :url url))
         (max-redirects (or (http-request-max-redirects request)
                            (http-client-max-redirects client)))
         (verify (http-client-verify client)))
    (setf headers (inject-auth-range-headers
                   headers
                   :auth (effective-auth client request)
                   :range (http-request-range request)))
    (multiple-value-bind (content extra-headers content-length)
        (prepare-request-body request)
      (declare (ignore content-length))
      (setf headers (append headers extra-headers))
      (let* ((jclient (%ensure-http-client
                       backend
                       :follow-redirects (not (eql max-redirects 0))
                       :verify verify))
             (jreq (%build-java-request url method headers content))
             (handler (%jstatic "ofByteArray" "java.net.http.HttpResponse$BodyHandlers"))
             (fut (%jcall "sendAsync" jclient jreq handler))
             (handle (make-instance 'java-async-handle :future fut)))
        (%jcall "whenComplete" fut
                (java:jinterface-implementation
                 "java.util.function.BiConsumer"
                 "accept"
                 (lambda (jresp err)
                   (cond
                     ((java-async-canceled-p handle) nil)
                     (err
                      (when error-callback
                        (funcall error-callback
                                 (make-condition 'http-connection-error
                                                 :message (princ-to-string err)))))
                     (t
                      (handler-case
                          (let ((res (%java-response->http-response
                                      jresp request url cookie-jar
                                      :decompress (http-request-decompress request))))
                            (when callback (funcall callback res)))
                        (error (e)
                          (when error-callback (funcall error-callback e)))))))))
        handle)))
  #-abcl
  (progn
    (declare (ignore client request callback error-callback))
    (error 'unsupported-operation :operation 'send-async)))

(defmethod cancel-request ((backend java-backend) (handle java-async-handle))
  (setf (java-async-canceled-p handle) t)
  #+abcl
  (ignore-errors
    (%jcall "cancel" (java-async-future handle)
            (java:make-immediate-object t :boolean)))
  handle)
