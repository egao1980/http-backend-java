(in-package #:http-backend-java)

;;; java.net.http.WebSocket (RFC 6455) — ABCL.

(defclass java-ws-connection (ws-connection)
  ((websocket :initarg :websocket :accessor java-ws-websocket)
   (handlers :initform (make-hash-table :test #'eq)
             :accessor java-ws-handlers)
   (lock :initform (bt:make-lock "java-ws") :reader java-ws-lock)
   (closed-p :initform nil :accessor java-ws-closed-p)))

#+abcl
(defun %ws-fire (conn event &rest args)
  (let ((fn (gethash event (java-ws-handlers conn))))
    (when fn (ignore-errors (apply fn args)))))

#+abcl
(defun %make-ws-listener (conn)
  (java:jinterface-implementation
   "java.net.http.WebSocket$Listener"
   "onOpen"
   (lambda (ws)
     (declare (ignore ws))
     (setf (%connection-ready-state conn) :open)
     (%ws-fire conn :open)
     nil)
   "onText"
   (lambda (ws data last)
     (declare (ignore ws last))
     (%ws-fire conn :message (if (stringp data) data (princ-to-string data)))
     nil)
   "onBinary"
   (lambda (ws data last)
     (declare (ignore ws last))
     (let* ((bb data) ; java.nio.ByteBuffer
            (n (%jcall "remaining" bb))
            (arr (java:jnew-array "byte" n)))
       (%jcall "get" bb arr)
       (%ws-fire conn :message (%jbytes-to-octets arr)))
     nil)
   "onPing"
   (lambda (ws message)
     (declare (ignore ws))
     (%ws-fire conn :pong (%jbytes-to-octets
                           (let* ((n (%jcall "remaining" message))
                                  (arr (java:jnew-array "byte" n)))
                             (%jcall "get" message arr)
                             arr)))
     nil)
   "onPong"
   (lambda (ws message)
     (declare (ignore ws message))
     (%ws-fire conn :pong)
     nil)
   "onClose"
   (lambda (ws status-code reason)
     (declare (ignore ws))
     (setf (java-ws-closed-p conn) t
           (%connection-ready-state conn) :closed)
     (%ws-fire conn :close status-code reason)
     nil)
   "onError"
   (lambda (ws error)
     (declare (ignore ws))
     (%ws-fire conn :error error)
     nil)))

(defmethod connect ((backend java-backend) client url &key transport)
  (declare (ignore transport))
  #+abcl
  (let* ((jclient (%ensure-http-client backend
                                       :verify (ws-client-verify client)))
         (builder (%jcall "newWebSocketBuilder" jclient))
         (headers (append (ws-client-headers client)
                          (when (ws-client-auth client)
                            (let ((h (inject-auth-range-headers
                                      nil :auth (ws-client-auth client))))
                              h))))
         (conn (make-instance 'java-ws-connection
                              :url url
                              :ready-state :connecting)))
    (dolist (pair headers)
      (ignore-errors
        (%jcall "header" builder (car pair) (princ-to-string (cdr pair)))))
    (when (ws-client-protocols client)
      (let* ((protos (mapcar #'princ-to-string
                             (let ((p (ws-client-protocols client)))
                               (if (listp p) p (list p)))))
             (first (first protos))
             (rest (rest protos))
             (arr (java:jnew-array "java.lang.String" (length rest))))
        (loop for i from 0 for s in rest
              do (setf (java:jarray-ref arr i) s))
        (%jcall "subprotocols" builder first arr)))
    (let* ((uri (java:jnew "java.net.URI" url))
           (fut (%jcall "buildAsync" builder uri (%make-ws-listener conn)))
           (ws (%jcall "join" fut)))
      (setf (java-ws-websocket conn) ws)
      conn))
  #-abcl
  (error 'unsupported-operation :operation 'connect
         :message "http-backend-java requires ABCL"))

(defmethod on-event ((connection java-ws-connection) event handler)
  (setf (gethash event (java-ws-handlers connection)) handler)
  connection)

(defmethod send-text ((connection java-ws-connection) text &key)
  #+abcl
  (progn
    (%jcall "sendText" (java-ws-websocket connection) text
            (java:make-immediate-object t :boolean))
    (%jcall "request" (java-ws-websocket connection) 1)
    text)
  #-abcl
  (error 'unsupported-operation :operation 'send-text))

(defmethod send-binary ((connection java-ws-connection) octets &key)
  #+abcl
  (let* ((bytes (%octets-to-jbytes octets))
         (bb (%jstatic "wrap" "java.nio.ByteBuffer" bytes)))
    (%jcall "sendBinary" (java-ws-websocket connection) bb
            (java:make-immediate-object t :boolean))
    (%jcall "request" (java-ws-websocket connection) 1)
    octets)
  #-abcl
  (error 'unsupported-operation :operation 'send-binary))

(defmethod ping ((connection java-ws-connection) &optional payload &key)
  #+abcl
  (let* ((bytes (%octets-to-jbytes (or payload #())))
         (bb (%jstatic "wrap" "java.nio.ByteBuffer" bytes)))
    (%jcall "sendPing" (java-ws-websocket connection) bb)
    connection)
  #-abcl
  (progn (declare (ignore payload))
         (error 'unsupported-operation :operation 'ping)))

(defmethod close-connection ((connection java-ws-connection) &key (code 1000) reason)
  #+abcl
  (unless (java-ws-closed-p connection)
    (setf (java-ws-closed-p connection) t
          (%connection-ready-state connection) :closing)
    (ignore-errors
      (%jcall "sendClose" (java-ws-websocket connection)
              (or code 1000)
              (or reason "")))
    (setf (%connection-ready-state connection) :closed))
  #-abcl
  (declare (ignore code reason))
  connection)
